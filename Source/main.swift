import AppKit
import UniformTypeIdentifiers

struct Note: Codable {
    var id = UUID()
    var text = ""
    var modified = Date()
    var title: String { text.split(separator: "\n").first.map(String.init) ?? "Новая заметка" }
}

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class Bubble: NSView {
    var onOpen: (() -> Void)?
    var onMove: (() -> Void)?
    private var initialMouse = NSPoint.zero
    private var initialOrigin = NSPoint.zero
    private var dragged = false
    var previewTitle = "Новая заметка"
    var previewBody = "Нажмите, чтобы начать писать"
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var needsPanelToBecomeKey: Bool { false }
    override func accessibilityPerformPress() -> Bool { onOpen?(); return true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.98, green: 0.76, blue: 0.34, alpha: 1).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 3), xRadius: 20, yRadius: 20).fill()
        let ink = NSColor(calibratedWhite: 0.12, alpha: 1)
        if let icon = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(paletteColors: [ink])
            (icon.withSymbolConfiguration(config) ?? icon).draw(in: NSRect(x: 16, y: (bounds.height - 24) / 2, width: 24, height: 24))
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let titleY: CGFloat = previewBody.isEmpty ? (bounds.height - 18) / 2 : bounds.midY + 1
        (previewTitle as NSString).draw(in: NSRect(x: 52, y: titleY, width: bounds.width - 68, height: 18), withAttributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: ink, .paragraphStyle: paragraph
        ])
        (previewBody as NSString).draw(in: NSRect(x: 52, y: bounds.midY - 18, width: bounds.width - 68, height: 16), withAttributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: ink.withAlphaComponent(0.72), .paragraphStyle: paragraph
        ])
    }
    override func mouseDown(with event: NSEvent) {
        initialMouse = NSEvent.mouseLocation
        initialOrigin = window?.frame.origin ?? .zero
        dragged = false
    }
    override func mouseDragged(with event: NSEvent) {
        let p = NSEvent.mouseLocation
        let dx = p.x - initialMouse.x, dy = p.y - initialMouse.y
        if hypot(dx, dy) > 8 { dragged = true }
        if dragged { window?.setFrameOrigin(NSPoint(x: initialOrigin.x + dx, y: initialOrigin.y + dy)) }
    }
    override func mouseUp(with event: NSEvent) {
        if dragged { onMove?() } else { onOpen?() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate {
    var statusItem: NSStatusItem!
    var bubble: FloatingPanel!
    var editor: FloatingPanel!
    var settingsWindow: FloatingPanel?
    var themePicker: NSPopUpButton?
    var noteSplit: NSSplitView?
    var restoringLayout = false
    let table = NSTableView()
    let textView = NSTextView()
    let status = NSTextField(labelWithString: "")
    var notes: [Note] = []
    var selectedID: UUID?
    var loading = false
    var dirty = false
    var storageUnavailable = false
    var dataURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("QuickNote/notes.json")
    var index: Int? { notes.firstIndex { $0.id == selectedID } }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        makeMenu()
        load()
        makeBubble()
        makeEditor()
        select(0)
        applyTheme()
        bubble.orderFrontRegardless()
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        if storageUnavailable { showError("Не удалось прочитать сохранённые заметки. Исходный файл сохранён без изменений. Проверьте файл в папке данных через меню приложения.") }
    }

    func makeMenu() {
        let main = NSMenu()
        let editItem = NSMenuItem(title: "Правка", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "Правка")
        for (title, selector, key) in [("Отменить", Selector(("undo:")), "z"), ("Повторить", Selector(("redo:")), "Z"), ("Вырезать", #selector(NSText.cut(_:)), "x"), ("Копировать", #selector(NSText.copy(_:)), "c"), ("Вставить", #selector(NSText.paste(_:)), "v"), ("Выбрать всё", #selector(NSText.selectAll(_:)), "a")] {
            edit.addItem(withTitle: title, action: selector, keyEquivalent: key)
        }
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "QuickNoteStatusItem"
        statusItem.behavior = []
        statusItem.isVisible = true
        if let statusButton = statusItem.button {
            let icon = NSImage(systemSymbolName: "note.text", accessibilityDescription: "QuickNote")
            icon?.isTemplate = true
            icon?.size = NSSize(width: 18, height: 18)
            statusButton.image = icon
            statusButton.title = " QN"
            statusButton.imagePosition = .imageLeading
            statusButton.setAccessibilityLabel("QuickNote — меню приложения")
        }
        statusItem.button?.toolTip = "QuickNote — быстрые заметки"
        let menu = NSMenu()
        for (title, action, key) in [("Открыть блокнот", #selector(openEditor), ""), ("Новая заметка", #selector(newNote), "n"), ("Сохранить", #selector(saveAction), "s"), ("Экспортировать заметку…", #selector(exportNote), "e"), ("Свернуть в кнопку", #selector(collapse), "w"), ("Вернуть кнопку на экран", #selector(resetBubble), ""), ("Открыть папку данных", #selector(openData), ""), ("Настройки…", #selector(openSettings), ",")] {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.target = self
        }
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Завершить QuickNote", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        statusItem.menu = menu
        let fileItem = NSMenuItem(title: "Заметки", action: nil, keyEquivalent: "")
        fileItem.submenu = menu.copy() as? NSMenu
        main.insertItem(fileItem, at: 0)
    }

    func applyTheme() {
        let theme = UserDefaults.standard.string(forKey: "theme") ?? "system"
        let appearance: NSAppearance?
        switch theme {
        case "dark": appearance = NSAppearance(named: .darkAqua)
        case "light": appearance = NSAppearance(named: .aqua)
        default: appearance = nil
        }
        // Keep the menu-bar button on the system appearance for contrast.
        editor?.appearance = appearance
        settingsWindow?.appearance = appearance
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .textColor
        textView.insertionPointColor = .textColor
        table.backgroundColor = .controlBackgroundColor
        editor?.contentView?.needsDisplay = true
    }

    @objc func changeTheme(_ sender: NSPopUpButton) {
        let themes = ["system", "light", "dark"]
        guard themes.indices.contains(sender.indexOfSelectedItem) else { return }
        UserDefaults.standard.set(themes[sender.indexOfSelectedItem], forKey: "theme")
        applyTheme()
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let window = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 180), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Настройки QuickNote"
            window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications]
            window.center()
            window.setFrameUsingName("QuickNoteSettings")
            window.setFrameAutosaveName("QuickNoteSettings")
            window.delegate = self
            let root = NSView()
            window.contentView = root
            let title = NSTextField(labelWithString: "Оформление")
            title.font = .systemFont(ofSize: 17, weight: .semibold)
            let picker = NSPopUpButton(frame: .zero, pullsDown: false)
            picker.addItems(withTitles: ["Как в системе", "Светлая тема", "Тёмная тема"])
            picker.target = self
            picker.action = #selector(changeTheme(_:))
            picker.setAccessibilityLabel("Тема оформления")
            let hint = NSTextField(labelWithString: "Применяется сразу и сохраняется после выхода.")
            hint.font = .systemFont(ofSize: 12)
            hint.textColor = .secondaryLabelColor
            for view in [title, picker, hint] { view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view) }
            NSLayoutConstraint.activate([
                title.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
                title.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
                picker.leadingAnchor.constraint(equalTo: title.leadingAnchor),
                picker.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
                picker.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 18),
                hint.leadingAnchor.constraint(equalTo: title.leadingAnchor),
                hint.topAnchor.constraint(equalTo: picker.bottomAnchor, constant: 16)
            ])
            themePicker = picker
            settingsWindow = window
        }
        let theme = UserDefaults.standard.string(forKey: "theme") ?? "system"
        themePicker?.selectItem(at: ["system", "light", "dark"].firstIndex(of: theme) ?? 0)
        applyTheme()
        NSApp.activate(ignoringOtherApps: true)
        if let settingsWindow { keepWindowVisible(settingsWindow); settingsWindow.makeKeyAndOrderFront(nil) }
    }

    func load() {
        if FileManager.default.fileExists(atPath: dataURL.path) {
            do { notes = try JSONDecoder().decode([Note].self, from: Data(contentsOf: dataURL)) }
            catch { storageUnavailable = true }
        }
        if notes.isEmpty { notes = [Note()] }
    }

    @discardableResult func save() -> Bool {
        updatePreview()
        guard !storageUnavailable else { status.stringValue = "Ошибка чтения хранилища — используйте экспорт"; return false }
        do {
            try FileManager.default.createDirectory(at: dataURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(notes).write(to: dataURL, options: .atomic)
            dirty = false
            status.stringValue = "Сохранено на этом Mac · \(Date().formatted(date: .omitted, time: .shortened))"
            return true
        } catch { status.stringValue = "Не удалось сохранить — используйте экспорт"; return false }
    }

    func makeBubble() {
        bubble = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 220, height: 64), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        bubble.level = .floating
        bubble.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        if #available(macOS 13.0, *) { bubble.collectionBehavior.insert(.canJoinAllApplications) }
        bubble.isOpaque = false
        bubble.backgroundColor = .clear
        bubble.hasShadow = true
        bubble.hidesOnDeactivate = false
        let view = Bubble(frame: NSRect(x: 0, y: 0, width: 220, height: 64))
        view.toolTip = "Нажмите, чтобы открыть заметки. Перетащите, чтобы переместить."
        view.setAccessibilityElement(true)
        view.setAccessibilityLabel("Открыть QuickNote")
        view.setAccessibilityRole(.button)
        view.onOpen = { [weak self] in
            guard let self else { return }
            self.select(0)
            self.openEditor()
        }
        view.onMove = { [weak self] in self?.persistBubble() }
        bubble.contentView = view
        updatePreview()
        resetBubble()
        if let position = UserDefaults.standard.string(forKey: "bubblePosition") { bubble.setFrameOrigin(NSPointFromString(position)); constrainBubble() }
    }

    func updatePreview() {
        guard let view = bubble?.contentView as? Bubble else { return }
        let latest = notes.first
        view.previewTitle = String((latest?.title ?? "Новая заметка").prefix(200))
        let lines = (latest?.text ?? "").split(separator: "\n", omittingEmptySubsequences: true)
        let body = lines.dropFirst().joined(separator: " ")
        view.previewBody = String(body.prefix(300))
        view.setAccessibilityLabel("Открыть последнюю заметку: \(view.previewTitle)")
        view.needsDisplay = true
    }

    func persistBubble() { constrainBubble(); UserDefaults.standard.set(NSStringFromPoint(bubble.frame.origin), forKey: "bubblePosition") }
    func constrainBubble() {
        let frame = bubble.frame
        let screen = NSScreen.screens.first { $0.visibleFrame.intersects(frame) } ?? NSScreen.main
        guard let r = screen?.visibleFrame else { return }
        bubble.setFrameOrigin(NSPoint(x: min(max(frame.minX, r.minX), r.maxX - frame.width), y: min(max(frame.minY, r.minY), r.maxY - frame.height)))
    }
    @objc func screenChanged() { persistBubble(); keepWindowVisible(editor); if let settingsWindow { keepWindowVisible(settingsWindow) } }
    @objc func resetBubble() {
        guard let r = NSScreen.main?.visibleFrame else { return }
        bubble.setFrameOrigin(NSPoint(x: r.maxX - bubble.frame.width - 24, y: r.midY))
    }

    func button(_ title: String, _ action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        return b
    }

    func makeEditor() {
        editor = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 760, height: 510), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        editor.title = "QuickNote"
        editor.level = .floating
        editor.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        if #available(macOS 13.0, *) { editor.collectionBehavior.insert(.canJoinAllApplications) }
        editor.hidesOnDeactivate = false
        editor.isReleasedWhenClosed = false
        editor.minSize = NSSize(width: 680, height: 350)
        editor.center()
        editor.setFrameUsingName("QuickNoteEditor")
        editor.setFrameAutosaveName("QuickNoteEditor")
        let root = NSView()
        editor.contentView = root
        let toolbar = NSStackView(views: [button("＋ Заметка", #selector(newNote)), button("Сохранить", #selector(saveAction)), button("Экспорт…", #selector(exportNote)), button("Удалить", #selector(deleteNote)), button("Свернуть ↗", #selector(collapse)), button("⚙", #selector(openSettings))])
        toolbar.spacing = 8
        toolbar.orientation = .horizontal
        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        let sidebar = NSScrollView()
        sidebar.hasVerticalScroller = true
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("note"))
        col.title = "Заметки"
        col.width = 200
        table.addTableColumn(col)
        table.headerView = nil
        table.autosaveName = "QuickNoteColumns"
        table.autosaveTableColumns = true
        table.rowHeight = 54
        table.style = .sourceList
        table.delegate = self
        table.dataSource = self
        table.allowsEmptySelection = false
        sidebar.documentView = table
        let writing = NSScrollView()
        writing.hasVerticalScroller = true
        writing.borderType = .noBorder
        textView.frame = NSRect(x: 0, y: 0, width: 520, height: 400)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = NSFont.systemFont(ofSize: 16)
        textView.textContainerInset = NSSize(width: 24, height: 24)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = self
        writing.documentView = textView
        split.addArrangedSubview(sidebar)
        split.addArrangedSubview(writing)
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.stringValue = "Автосохранение · ⌘N — новая · ⌘S — сохранить · ⌘W — свернуть"
        for view in [toolbar, split, status] { view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view) }
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16), toolbar.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            split.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 12), split.leadingAnchor.constraint(equalTo: root.leadingAnchor), split.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            split.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -8),
            status.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16), status.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16), status.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10),
            sidebar.widthAnchor.constraint(greaterThanOrEqualToConstant: 150), writing.widthAnchor.constraint(greaterThanOrEqualToConstant: 280)
        ])
        noteSplit = split
        root.layoutSubtreeIfNeeded()
        restoringLayout = true
        let savedWidth = UserDefaults.standard.object(forKey: "sidebarWidth") as? Double ?? 210
        split.setPosition(min(max(CGFloat(savedWidth), 150), max(150, split.bounds.width - 281)), ofDividerAt: 0)
        restoringLayout = false
        NotificationCenter.default.addObserver(self, selector: #selector(splitResized), name: NSSplitView.didResizeSubviewsNotification, object: split)
        keepWindowVisible(editor)
        editor.delegate = self
    }

    @objc func splitResized() {
        guard !restoringLayout, let split = noteSplit, let sidebar = split.arrangedSubviews.first else { return }
        UserDefaults.standard.set(Double(sidebar.frame.width), forKey: "sidebarWidth")
    }

    func windowDidMove(_ notification: Notification) { rememberWindow(notification) }
    func windowDidResize(_ notification: Notification) { rememberWindow(notification) }
    func rememberWindow(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === editor { window.saveFrame(usingName: "QuickNoteEditor") }
        if window === settingsWindow { window.saveFrame(usingName: "QuickNoteSettings") }
    }

    func keepWindowVisible(_ window: NSWindow) {
        let frame = window.frame
        let screen = NSScreen.screens.first { $0.visibleFrame.intersects(frame) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        var fitted = frame
        fitted.size.width = min(frame.width, visible.width)
        fitted.size.height = min(frame.height, visible.height)
        fitted.origin.x = min(max(frame.minX, visible.minX), visible.maxX - fitted.width)
        fitted.origin.y = min(max(frame.minY, visible.minY), visible.maxY - fitted.height)
        if fitted != frame { window.setFrame(fitted, display: false) }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { notes.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let label = NSTextField(labelWithString: notes[row].title)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 2
        return label
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = table.selectedRow
        guard notes.indices.contains(row) else { return }
        selectedID = notes[row].id
        loading = true
        textView.string = notes[row].text
        textView.undoManager?.removeAllActions()
        loading = false
    }
    func select(_ row: Int) {
        table.reloadData()
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableViewSelectionDidChange(Notification(name: NSTableView.selectionDidChangeNotification))
    }
    func textDidChange(_ notification: Notification) {
        guard !loading, let i = index else { return }
        notes[i].text = textView.string
        notes[i].modified = Date()
        dirty = true
        table.reloadData(forRowIndexes: IndexSet(integer: i), columnIndexes: IndexSet(integer: 0))
        _ = save()
    }
    @objc func openEditor() {
        bubble.orderOut(nil)
        NSApp.activate(ignoringOtherApps: true)
        editor.makeKeyAndOrderFront(nil)
        editor.makeFirstResponder(textView)
    }
    @objc func collapse() { if dirty { _ = save() }; editor.orderOut(nil); updatePreview(); bubble.orderFrontRegardless() }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === editor { collapse(); return false }
        return true
    }
    @objc func newNote() { notes.insert(Note(), at: 0); dirty = true; select(0); _ = save(); openEditor() }
    @objc func saveAction() { if !save() { showError("Сохранение не удалось. Экспортируйте заметку в текстовый файл, чтобы не потерять изменения.") } }
    @objc func deleteNote() {
        guard let i = index else { return }
        let alert = NSAlert()
        alert.messageText = "Удалить заметку?"
        alert.informativeText = "Заметка «\(notes[i].title.prefix(60))» будет удалена."
        alert.addButton(withTitle: "Отмена")
        alert.addButton(withTitle: "Удалить")
        alert.beginSheetModal(for: editor) { [weak self] result in
            guard result == .alertSecondButtonReturn, let self else { return }
            self.notes.remove(at: i)
            if self.notes.isEmpty { self.notes.append(Note()) }
            self.dirty = true
            self.select(min(i, self.notes.count - 1))
            _ = self.save()
        }
    }
    @objc func exportNote() {
        guard let i = index else { return }
        openEditor()
        let note = notes[i]
        let choice = NSAlert()
        choice.messageText = "Экспорт заметки"
        choice.informativeText = "Выберите формат: обычный текст TXT или документ PDF."
        choice.addButton(withTitle: "TXT")
        choice.addButton(withTitle: "PDF")
        choice.addButton(withTitle: "Отмена")
        choice.beginSheetModal(for: editor) { [weak self] response in
            guard let self else { return }
            guard response == .alertFirstButtonReturn || response == .alertSecondButtonReturn else { return }
            self.saveExport(note, asPDF: response == .alertSecondButtonReturn)
        }
    }
    func saveExport(_ note: Note, asPDF: Bool) {
        let panel = NSSavePanel()
        panel.title = asPDF ? "Экспорт в PDF" : "Экспорт в TXT"
        panel.allowedContentTypes = [asPDF ? .pdf : .plainText]
        panel.canSelectHiddenExtension = true
        let name = String(note.title.prefix(60)).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        panel.nameFieldStringValue = name + (asPDF ? ".pdf" : ".txt")
        panel.beginSheetModal(for: editor) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                if asPDF {
                    try PDFExporter.data(text: note.text, title: note.title).write(to: url, options: .atomic)
                } else {
                    try note.text.write(to: url, atomically: true, encoding: .utf8)
                }
            } catch { self?.showError("Не удалось экспортировать заметку: \(error.localizedDescription)") }
        }
    }
    @objc func openData() { NSWorkspace.shared.open(dataURL.deletingLastPathComponent()) }
    @objc func quitApp() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if dirty && !save() { openEditor(); showError("Изменения не сохранены. Экспортируйте заметку перед выходом."); return .terminateCancel }
        persistBubble()
        splitResized()
        editor.saveFrame(usingName: "QuickNoteEditor")
        settingsWindow?.saveFrame(usingName: "QuickNoteSettings")
        return .terminateNow
    }
    func showError(_ message: String) {
        let alert = NSAlert(); alert.messageText = "QuickNote"; alert.informativeText = message; alert.runModal()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
