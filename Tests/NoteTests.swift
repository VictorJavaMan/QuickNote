import AppKit
import PDFKit

@main struct NoteTests {
    static func tryImport(_ data: Data) -> String { try! TextFileImporter.decode(data) }
    static func main() throws {
        let sample = "Привет, JSON!\n{\"ok\": true}"
        assert(tryImport(Data(sample.utf8)) == sample)
        assert(tryImport(Data([0xEF, 0xBB, 0xBF]) + Data(sample.utf8)) == sample)
        assert(tryImport(Data([0xFF, 0xFE]) + sample.data(using: .utf16LittleEndian)!) == sample)
        assert(tryImport(Data([0, 0, 0xFE, 0xFF]) + sample.data(using: .utf32BigEndian)!) == sample)
        assert(tryImport(Data()) == "")
        let cyrillic = "Привет"
        let cp = try TextFileImporter.decode(cyrillic.data(using: .windowsCP1251)!, encoding: .windows1251)
        assert(cp == cyrillic)
        do { _ = try TextFileImporter.decode(Data([0, 1, 2, 3])); assertionFailure("Binary accepted") } catch {}
        do { _ = try TextFileImporter.decode(Data([0xFF, 0xA0])); assertionFailure("Invalid UTF-8 accepted") } catch {}
        print("PASS: text import UTF-8, BOM, UTF-16/32, CP1251, empty and binary rejection")
        let legacy = "[{\"id\":\"601B0C93-76F4-48B7-8820-16141C74C018\",\"text\":\"Старая заметка\",\"modified\":0}]"
        let old = try JSONDecoder().decode([Note].self, from: Data(legacy.utf8))
        assert(old[0].text == "Старая заметка" && old[0].richText == nil)
        assert(old[0].attributedText.string == old[0].text)
        let rich = NSMutableAttributedString(string: "Жирный текст\nСсылка и курсив", attributes: [.font: NSFont.systemFont(ofSize: 16)])
        rich.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 20), range: NSRange(location: 0, length: 6))
        rich.addAttribute(.foregroundColor, value: NSColor.red, range: NSRange(location: 0, length: 6))
        rich.addAttribute(.link, value: URL(string: "https://example.com")!, range: NSRange(location: 13, length: 6))
        rich.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 13, length: 6))
        let style = NSMutableParagraphStyle(); style.firstLineHeadIndent = 18; style.lineSpacing = 6
        rich.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: rich.length))
        var note = Note()
        try note.update(content: rich)
        let reloaded = try JSONDecoder().decode(Note.self, from: JSONEncoder().encode(note))
        let restored = reloaded.attributedText
        assert(restored.string == rich.string)
        let font = restored.attribute(.font, at: 0, effectiveRange: nil) as! NSFont
        assert(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
        assert(font.pointSize == 20)
        let color = restored.attribute(.foregroundColor, at: 0, effectiveRange: nil) as! NSColor
        assert(color.usingColorSpace(.deviceRGB)!.redComponent > 0.9)
        assert(restored.attribute(.link, at: 13, effectiveRange: nil) != nil)
        assert(restored.attribute(.underlineStyle, at: 13, effectiveRange: nil) as? Int == 1)
        let paragraph = restored.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as! NSParagraphStyle
        assert(paragraph.firstLineHeadIndent == 18 && paragraph.lineSpacing == 6)
        var notes = [Note(text: "Новая"), reloaded, old[0]]
        let originalIDs = notes.map(\.id)
        NoteOrdering.togglePin(old[0].id, in: &notes)
        assert(NoteOrdering.displayed(notes).first!.id == old[0].id)
        assert(NoteOrdering.preview(notes)!.id == old[0].id)
        assert(notes.map(\.id) == originalIDs)
        notes = try JSONDecoder().decode([Note].self, from: JSONEncoder().encode(notes))
        assert(NoteOrdering.preview(notes)!.id == old[0].id)
        NoteOrdering.togglePin(reloaded.id, in: &notes)
        assert(notes.filter { $0.isPinned == true }.count == 1)
        assert(NoteOrdering.preview(notes)!.id == reloaded.id)
        NoteOrdering.togglePin(reloaded.id, in: &notes)
        assert(NoteOrdering.preview(notes)!.id == notes[0].id)
        NoteOrdering.togglePin(old[0].id, in: &notes)
        notes.removeAll { $0.id == old[0].id }
        assert(NoteOrdering.preview(notes)!.id == notes[0].id)
        let pdfData = try PDFExporter.data(text: note.text, title: note.title, richText: restored)
        let pdf = PDFDocument(data: pdfData)!
        assert(pdf.string!.contains("Жирный текст"))
        let output = CommandLine.arguments[1]
        try pdfData.write(to: URL(fileURLWithPath: output + "/rich-text.pdf"))
        let image = pdf.page(at: 0)!.thumbnail(of: NSSize(width: 595, height: 842), for: .mediaBox)
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output + "/rich-text.png"))
        print("PASS: legacy migration; rich text, colors, links and paragraph round trip; pin/re-pin/unpin/delete and persistence; PDF export")
    }
}
