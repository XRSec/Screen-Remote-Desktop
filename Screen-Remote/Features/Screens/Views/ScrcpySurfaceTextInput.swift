import AppKit

extension ScrcpyInputEventView: NSTextInputClient {
    private static let commandKeyCodes: [Selector: UInt32] = [
        #selector(deleteBackward(_:)): 67,
        #selector(deleteForward(_:)): 112,
        #selector(insertNewline(_:)): 66,
        #selector(insertTab(_:)): 61,
        #selector(moveLeft(_:)): 21,
        #selector(moveRight(_:)): 22,
        #selector(moveUp(_:)): 19,
        #selector(moveDown(_:)): 20,
        #selector(cancelOperation(_:)): 111
    ]

    override func keyDown(with event: NSEvent) {
        guard isEnabled else { return }
        if handleCommandShortcut(event) { return }
        if inputContext?.handleEvent(event) != true {
            interpretKeyEvents([event])
        }
    }

    override func doCommand(by selector: Selector) {
        guard let keyCode = Self.commandKeyCodes[selector] else {
            super.doCommand(by: selector)
            return
        }
        if selector == #selector(deleteBackward(_:)), let markedText, markedText.length > 0 {
            let string = markedText.string as NSString
            markedText.deleteCharacters(in: string.rangeOfComposedCharacterSequence(at: string.length - 1))
            if markedText.length == 0 { self.markedText = nil }
            return
        }
        onKeyCommand?(keyCode)
    }

    func insertText(_ string: Any, replacementRange: NSRange) {
        guard let text = Self.plainText(from: string), !text.isEmpty else { return }
        markedText = nil
        onText?(text)
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        guard let text = Self.plainText(from: string) else {
            markedText = nil
            return
        }
        markedText = NSMutableAttributedString(string: text)
    }

    func unmarkText() {
        markedText = nil
    }

    func selectedRange() -> NSRange {
        NSRange(location: markedText?.length ?? 0, length: 0)
    }

    func markedRange() -> NSRange {
        guard let markedText, markedText.length > 0 else {
            return NSRange(location: NSNotFound, length: 0)
        }
        return NSRange(location: 0, length: markedText.length)
    }

    func hasMarkedText() -> Bool {
        markedText?.length ?? 0 > 0
    }

    func attributedSubstring(
        forProposedRange range: NSRange,
        actualRange: NSRangePointer?
    ) -> NSAttributedString? {
        nil
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        []
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let window else { return .zero }
        return window.convertToScreen(convert(bounds, to: nil))
    }

    func characterIndex(for point: NSPoint) -> Int {
        0
    }

    private func handleCommandShortcut(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
              let character = event.charactersIgnoringModifiers?.lowercased() else { return false }
        switch character {
        case "c":
            onCopy?(1)
        case "x":
            onCopy?(2)
        case "v":
            if let text = NSPasteboard.general.string(forType: .string) {
                onPaste?(text)
            }
        default:
            return false
        }
        return true
    }

    private static func plainText(from value: Any) -> String? {
        if let attributed = value as? NSAttributedString { return attributed.string }
        return value as? String
    }
}
