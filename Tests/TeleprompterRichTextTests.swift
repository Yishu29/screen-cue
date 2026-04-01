import Foundation
import AppKit

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct TeleprompterRichTextTests {
    static func main() {
        testSelectedTextCanBeBolded()
        testTypingAttributesCanBeItalicizedWithoutSelection()
        testUnderlineCanBeToggled()
        testSelectedTextCanChangeColor()
        testInsertedPlainTextUsesCurrentTypingAttributes()
        testRichTextCodecRoundTripsFormatting()
        print("PASS")
    }

    private static func testSelectedTextCanBeBolded() {
        let storage = NSTextStorage(string: "hello world", attributes: TeleprompterTextFormatter.defaultAttributes)
        var typingAttributes = TeleprompterTextFormatter.defaultAttributes
        TeleprompterTextFormatter.apply(
            .toggleBold,
            to: storage,
            selectedRange: NSRange(location: 0, length: 5),
            typingAttributes: &typingAttributes
        )

        let font = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        expect(font?.fontDescriptor.symbolicTraits.contains(.bold) == true, "Selected text should become bold")
    }

    private static func testTypingAttributesCanBeItalicizedWithoutSelection() {
        let storage = NSTextStorage(string: "hello", attributes: TeleprompterTextFormatter.defaultAttributes)
        var typingAttributes = TeleprompterTextFormatter.defaultAttributes
        TeleprompterTextFormatter.apply(
            .toggleItalic,
            to: storage,
            selectedRange: NSRange(location: 3, length: 0),
            typingAttributes: &typingAttributes
        )

        let font = typingAttributes[.font] as? NSFont
        expect(font?.fontDescriptor.symbolicTraits.contains(.italic) == true, "Typing attributes should become italic with no selection")
    }

    private static func testUnderlineCanBeToggled() {
        let storage = NSTextStorage(string: "hello world", attributes: TeleprompterTextFormatter.defaultAttributes)
        var typingAttributes = TeleprompterTextFormatter.defaultAttributes
        TeleprompterTextFormatter.apply(
            .toggleUnderline,
            to: storage,
            selectedRange: NSRange(location: 6, length: 5),
            typingAttributes: &typingAttributes
        )

        let underline = storage.attribute(.underlineStyle, at: 6, effectiveRange: nil) as? Int
        expect(underline == NSUnderlineStyle.single.rawValue, "Selected text should gain underline")
    }

    private static func testSelectedTextCanChangeColor() {
        let storage = NSTextStorage(string: "hello world", attributes: TeleprompterTextFormatter.defaultAttributes)
        var typingAttributes = TeleprompterTextFormatter.defaultAttributes
        TeleprompterTextFormatter.applyColor(
            .systemRed,
            to: storage,
            selectedRange: NSRange(location: 0, length: 5),
            typingAttributes: &typingAttributes
        )

        let color = storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        expect(color == .systemRed, "Selected text should change to requested color")
    }

    private static func testInsertedPlainTextUsesCurrentTypingAttributes() {
        let storage = NSTextStorage(string: "hello", attributes: TeleprompterTextFormatter.defaultAttributes)
        let boldFont = TeleprompterTextFormatter.toggledBoldFont(from: TeleprompterTextFormatter.defaultFont)
        let typingAttributes: [NSAttributedString.Key: Any] = [
            .font: boldFont,
            .foregroundColor: NSColor.systemBlue
        ]
        let insertionRange = NSRange(location: 5, length: 6)
        storage.replaceCharacters(in: NSRange(location: 5, length: 0), with: " world")
        TeleprompterTextFormatter.applyTypingAttributes(typingAttributes, to: storage, insertedRange: insertionRange)

        let color = storage.attribute(.foregroundColor, at: 6, effectiveRange: nil) as? NSColor
        let font = storage.attribute(.font, at: 6, effectiveRange: nil) as? NSFont
        expect(color == .systemBlue, "Inserted plain text should use current typing color")
        expect(font?.fontDescriptor.symbolicTraits.contains(.bold) == true, "Inserted plain text should use current typing font")
    }

    private static func testRichTextCodecRoundTripsFormatting() {
        let text = NSMutableAttributedString(string: "hello", attributes: TeleprompterTextFormatter.defaultAttributes)
        let boldFont = TeleprompterTextFormatter.toggledBoldFont(from: TeleprompterTextFormatter.defaultFont)
        text.addAttribute(.font, value: boldFont, range: NSRange(location: 0, length: 5))

        guard let data = TeleprompterRichTextCodec.encode(text),
              let decoded = TeleprompterRichTextCodec.decode(data) else {
            fputs("FAIL: Rich text codec should encode and decode\n", stderr)
            exit(1)
        }

        let font = decoded.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        expect(font?.fontDescriptor.symbolicTraits.contains(.bold) == true, "Decoded rich text should preserve bold font")
    }
}
