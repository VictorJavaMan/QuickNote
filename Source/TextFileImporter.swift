import Foundation

enum TextFileImporter {
    enum Encoding: Int { case automatic, utf8, utf16, windows1251, latin1 }
    static func read(_ url: URL, encoding: Encoding = .automatic) throws -> String {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw failure("Выберите обычный текстовый файл.") }
        guard (values.fileSize ?? 0) <= 20 * 1024 * 1024 else { throw failure("Файл больше 20 МБ. Откройте меньший фрагмент.") }
        return try decode(Data(contentsOf: url), encoding: encoding)
    }
    static func decode(_ data: Data, encoding: Encoding = .automatic) throws -> String {
        var text: String?
        switch encoding {
        case .utf8: text = String(data: data, encoding: .utf8)
        case .utf16: text = String(data: data, encoding: .utf16)
        case .windows1251: text = String(data: data, encoding: .windowsCP1251)
        case .latin1: text = String(data: data, encoding: .isoLatin1)
        case .automatic:
            if data.starts(with: [0xFF, 0xFE, 0, 0]) { text = String(data: data.dropFirst(4), encoding: .utf32LittleEndian) }
            else if data.starts(with: [0, 0, 0xFE, 0xFF]) { text = String(data: data.dropFirst(4), encoding: .utf32BigEndian) }
            else if data.starts(with: [0xFF, 0xFE]) { text = String(data: data.dropFirst(2), encoding: .utf16LittleEndian) }
            else if data.starts(with: [0xFE, 0xFF]) { text = String(data: data.dropFirst(2), encoding: .utf16BigEndian) }
            else { text = String(data: data, encoding: .utf8) }
        }
        guard var decoded = text else { throw failure("Не удалось прочитать кодировку. Попробуйте выбрать Windows-1251, UTF-16 или Latin-1 в окне открытия.") }
        if decoded.first == "\u{FEFF}" { decoded.removeFirst() }
        guard !decoded.unicodeScalars.contains(where: { $0.value == 0 || ($0.value < 32 && ![9, 10, 12, 13].contains($0.value)) }) else {
            throw failure("Файл содержит двоичные данные и не похож на текстовый.")
        }
        return decoded
    }
    static func failure(_ message: String) -> NSError {
        NSError(domain: "QuickNote.Import", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
