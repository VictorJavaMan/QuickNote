import AppKit
import CoreText

/// A4 export with embedded fonts, selectable text and automatic pagination.
enum PDFExporter {
    static func data(text: String, title: String) throws -> Data {
        let buffer = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
        guard let consumer = CGDataConsumer(data: buffer),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, [kCGPDFContextTitle as String: title, kCGPDFContextCreator as String: "QuickNote"] as CFDictionary) else {
            throw NSError(domain: "QuickNote.PDF", code: 1, userInfo: [NSLocalizedDescriptionKey: "Не удалось создать PDF."])
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        paragraph.lineBreakMode = .byWordWrapping
        let attributed = NSAttributedString(string: text.isEmpty ? " " : text, attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph
        ])
        let setter = CTFramesetterCreateWithAttributedString(attributed)
        let textBox = mediaBox.insetBy(dx: 48, dy: 54)
        let path = CGPath(rect: textBox, transform: nil)
        var offset = 0
        var page = 1
        while offset < attributed.length {
            let frame = CTFramesetterCreateFrame(setter, CFRange(location: offset, length: 0), path, nil)
            let visible = CTFrameGetVisibleStringRange(frame)
            guard visible.length > 0 else {
                context.closePDF()
                throw NSError(domain: "QuickNote.PDF", code: 2, userInfo: [NSLocalizedDescriptionKey: "Не удалось разместить текст на странице."])
            }
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(mediaBox)
            context.textMatrix = .identity
            CTFrameDraw(frame, context)
            let footer = CTLineCreateWithAttributedString(NSAttributedString(string: "\(page)", attributes: [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor.gray]))
            let width = CTLineGetTypographicBounds(footer, nil, nil, nil)
            context.textPosition = CGPoint(x: (mediaBox.width - width) / 2, y: 27)
            CTLineDraw(footer, context)
            context.endPDFPage()
            offset += visible.length
            page += 1
        }
        context.closePDF()
        return buffer as Data
    }
}
