import AppKit

struct Note: Codable {
    var id = UUID()
    var text = ""
    var modified = Date()
    // Optional fields keep existing notes.json files compatible.
    var importedName: String?
    var richText: Data?
    var isPinned: Bool?
    var title: String { importedName ?? text.split(separator: "\n").first.map(String.init) ?? "Новая заметка" }
    var attributedText: NSAttributedString {
        if let richText, let content = NSAttributedString(rtf: richText, documentAttributes: nil) { return content }
        return NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.textColor])
    }
    mutating func update(content: NSAttributedString) throws {
        let encoded = try content.data(from: NSRange(location: 0, length: content.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        text = content.string
        richText = encoded
        modified = Date()
    }
}

enum NoteOrdering {
    static func displayed(_ notes: [Note]) -> [Note] {
        notes.filter { $0.isPinned == true } + notes.filter { $0.isPinned != true }
    }
    static func preview(_ notes: [Note]) -> Note? { notes.first { $0.isPinned == true } ?? notes.first }
    static func togglePin(_ id: UUID, in notes: inout [Note]) {
        let enable = notes.first { $0.id == id }?.isPinned != true
        for index in notes.indices { notes[index].isPinned = enable && notes[index].id == id }
    }
}

final class NotePinButton: NSButton {
    var noteID: UUID?
}
