import UIKit
import SwiftUI

@available(iOS 15.0, *)
class RichTextEditorView: UIView {
    
    // MARK: - TextKit 2 Stack
    private let textContentStorage = NSTextContentStorage()
    private let textLayoutManager = NSTextLayoutManager()
    private let textContainer = NSTextContainer()
    
    // MARK: - Properties
    private var textView: UITextView!
    private let defaultFont = UIFont.systemFont(ofSize: 16)
    private let defaultTextColor = UIColor.label
    
    var onTextChange: ((NSAttributedString) -> Void)?
    var onFormattingChange: ((Bool, Bool, Bool, Bool, Bool, Bool, Bool, Bool, Bool) -> Void)?
    
    // Helper struct for list continuation
    private struct ListContinuation {
        let insertionPoint: Int
        let prefix: String
        let paragraphStyle: NSParagraphStyle?
    }
    
    private var pendingListContinuation: ListContinuation?
    private var lastTextLength: Int = 0
    
    // MARK: - Formatting Methods
    
    func toggleBold() {
        guard let textView = textView else { return }
        
        let selectedRange = textView.selectedRange
        if selectedRange.length > 0 {
            // Text is selected - apply/remove bold to selection
            toggleAttribute(.font, trait: .traitBold, range: selectedRange)
        } else {
            // No selection - set typing attributes
            toggleTypingAttribute(.font, trait: .traitBold)
        }
        notifyFormattingChange()
    }
    
    func toggleItalic() {
        guard let textView = textView else { return }
        
        let selectedRange = textView.selectedRange
        if selectedRange.length > 0 {
            // Text is selected - apply/remove italic to selection
            toggleAttribute(.font, trait: .traitItalic, range: selectedRange)
        } else {
            // No selection - set typing attributes
            toggleTypingAttribute(.font, trait: .traitItalic)
        }
        notifyFormattingChange()
    }
    
    func toggleUnderline() {
        guard let textView = textView else { return }
        
        let selectedRange = textView.selectedRange
        if selectedRange.length > 0 {
            // Text is selected - apply/remove underline to selection
            let mutableText = NSMutableAttributedString(attributedString: textView.attributedText)
            let originalSelection = selectedRange // Preserve selection
            
            // Check if underline is already applied
            var hasUnderline = false
            mutableText.enumerateAttribute(.underlineStyle, in: selectedRange) { value, _, _ in
                if let underlineValue = value as? Int, underlineValue != 0 {
                    hasUnderline = true
                }
            }
            
            // Toggle underline
            if hasUnderline {
                mutableText.removeAttribute(.underlineStyle, range: selectedRange)
            } else {
                mutableText.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: selectedRange)
            }
            
            textView.attributedText = mutableText
            onTextChange?(mutableText)
            
            // Restore selection after a brief delay to ensure the text view has updated
            DispatchQueue.main.async {
                self.textView.selectedRange = originalSelection
            }
        } else {
            // No selection - set typing attributes
            var typingAttributes = textView.typingAttributes
            
            // Check current underline state
            let currentUnderline = typingAttributes[.underlineStyle] as? Int
            let hasUnderline = currentUnderline != nil && currentUnderline != 0
            
            if hasUnderline {
                typingAttributes.removeValue(forKey: .underlineStyle)
            } else {
                typingAttributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            
            textView.typingAttributes = typingAttributes
        }
        notifyFormattingChange()
    }

    func toggleStrikethrough() {
        guard let textView = textView else { return }
        let selectedRange = textView.selectedRange
        if selectedRange.length > 0 {
            let mutableText = NSMutableAttributedString(attributedString: textView.attributedText)
            let originalSelection = selectedRange
            var hasStrike = false
            mutableText.enumerateAttribute(.strikethroughStyle, in: selectedRange) { value, _, _ in
                if let v = value as? Int, v != 0 { hasStrike = true }
            }
            if hasStrike {
                mutableText.removeAttribute(.strikethroughStyle, range: selectedRange)
            } else {
                mutableText.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: selectedRange)
            }
            textView.attributedText = mutableText
            onTextChange?(mutableText)
            DispatchQueue.main.async { self.textView.selectedRange = originalSelection }
        } else {
            var typingAttributes = textView.typingAttributes
            let currentStrike = typingAttributes[.strikethroughStyle] as? Int
            let hasStrike = currentStrike != nil && currentStrike != 0
            if hasStrike {
                typingAttributes.removeValue(forKey: .strikethroughStyle)
            } else {
                typingAttributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            textView.typingAttributes = typingAttributes
        }
        notifyFormattingChange()
    }

    
    func toggleBulletList() {
        guard let textView = textView else { return }
        
        let selectedRange = textView.selectedRange
        let mutableText = NSMutableAttributedString(attributedString: textView.attributedText)
        
        // Get the range of lines affected
        let lineRanges = getLinesInRange(selectedRange, in: mutableText.string)
        
        // Check if any line already has bullet formatting
        let hasBulletList = lineRanges.contains { lineRange in
            return mutableText.string[lineRange].hasPrefix("• ")
        }
        
        var adjustedSelectionLocation = selectedRange.location
        var adjustedSelectionLength = selectedRange.length
        let hadSelection = selectedRange.length > 0
        
        // Apply or remove bullet formatting
        for lineRange in lineRanges.reversed() {
            let nsLineRange = NSRange(lineRange, in: mutableText.string)
            
            if hasBulletList {
                // Remove bullet formatting
                let lineText = mutableText.string[lineRange]
                if lineText.hasPrefix("• ") {
                    // Remove bullet and space
                    let newText = String(lineText.dropFirst(2))
                    mutableText.replaceCharacters(in: nsLineRange, with: newText)
                    
                    // Remove paragraph style
                    mutableText.removeAttribute(.paragraphStyle, range: NSRange(location: nsLineRange.location, length: newText.count))
                    
                    // Adjust selection
                    if nsLineRange.location <= selectedRange.location {
                        adjustedSelectionLocation -= 2
                    }
                    if hadSelection && nsLineRange.location < selectedRange.location + selectedRange.length {
                        adjustedSelectionLength -= 2
                    }
                }
            } else {
                // Add bullet formatting. If a numbered prefix exists, remove it first.
                let lineText = mutableText.string[lineRange]
                // Strip any numbered prefix first (e.g., "1. ")
                let contentText = lineText.replacingOccurrences(of: #"^\d+\. "#,
                                                                with: "",
                                                                options: .regularExpression)
                let newText = "• " + contentText
                mutableText.replaceCharacters(in: nsLineRange, with: newText)

                // Apply paragraph style with indentation
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.headIndent = 20
                paragraphStyle.firstLineHeadIndent = 0

                mutableText.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: nsLineRange.location, length: newText.count))

                // Adjust selection by net delta (added bullet minus any removed number prefix)
                let delta = newText.count - lineText.count
                if nsLineRange.location <= selectedRange.location {
                    adjustedSelectionLocation += delta
                }
                if hadSelection && nsLineRange.location < selectedRange.location + selectedRange.length {
                    adjustedSelectionLength += delta
                }
            }
        }
        
        textView.attributedText = mutableText
        onTextChange?(mutableText)
        
        // Restore adjusted selection
        let newSelection = NSRange(location: max(0, adjustedSelectionLocation), 
                                 length: max(0, adjustedSelectionLength))
        DispatchQueue.main.async {
            self.textView.selectedRange = newSelection
        }
        notifyFormattingChange()
    }
    
    func toggleNumberedList() {
        guard let textView = textView else { return }
        
        let selectedRange = textView.selectedRange
        let mutableText = NSMutableAttributedString(attributedString: textView.attributedText)
        
        // Get the range of lines affected
        let lineRanges = getLinesInRange(selectedRange, in: mutableText.string)
        
        // Check if any line already has numbered list formatting
        let hasNumberedList = lineRanges.contains { lineRange in
            let lineText = mutableText.string[lineRange]
            return lineText.range(of: #"^\d+\. "#, options: .regularExpression) != nil
        }
        
        var adjustedSelectionLocation = selectedRange.location
        var adjustedSelectionLength = selectedRange.length
        let hadSelection = selectedRange.length > 0
        
        // Apply or remove numbered list formatting
        for (index, lineRange) in lineRanges.reversed().enumerated() {
            let nsLineRange = NSRange(lineRange, in: mutableText.string)
            let lineText = mutableText.string[lineRange]
            
            if hasNumberedList {
                // Remove numbered list formatting
                if let range = lineText.range(of: #"^\d+\. "#, options: .regularExpression) {
                    let newText = String(lineText[range.upperBound...])
                    let removedLength = lineText.distance(from: lineText.startIndex, to: range.upperBound)
                    
                    mutableText.replaceCharacters(in: nsLineRange, with: newText)
                    
                    // Remove paragraph style
                    mutableText.removeAttribute(.paragraphStyle, range: NSRange(location: nsLineRange.location, length: newText.count))
                    
                    // Adjust selection
                    if nsLineRange.location <= selectedRange.location {
                        adjustedSelectionLocation -= removedLength
                    }
                    if hadSelection && nsLineRange.location < selectedRange.location + selectedRange.length {
                        adjustedSelectionLength -= removedLength
                    }
                }
            } else {
                // Add numbered list formatting. If a bullet exists, remove it first.
                let lineNumber = lineRanges.count - index
                let lineTextOriginal = lineText
                // Strip any bullet prefix first (e.g., "• ")
                let contentText = lineTextOriginal.replacingOccurrences(of: #"^• "#,
                                                                        with: "",
                                                                        options: .regularExpression)
                let newText = "\(lineNumber). " + contentText
                let addedLength = newText.count - lineTextOriginal.count

                mutableText.replaceCharacters(in: nsLineRange, with: newText)

                // Apply paragraph style with indentation
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.headIndent = 20
                paragraphStyle.firstLineHeadIndent = 0

                mutableText.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: nsLineRange.location, length: newText.count))

                // Adjust selection by net delta
                if nsLineRange.location <= selectedRange.location {
                    adjustedSelectionLocation += addedLength
                }
                if hadSelection && nsLineRange.location < selectedRange.location + selectedRange.length {
                    adjustedSelectionLength += addedLength
                }
            }
        }
        
        textView.attributedText = mutableText
        onTextChange?(mutableText)
        
        // Restore adjusted selection
        let newSelection = NSRange(location: max(0, adjustedSelectionLocation), 
                                 length: max(0, adjustedSelectionLength))
        DispatchQueue.main.async {
            self.textView.selectedRange = newSelection
        }
        notifyFormattingChange()
    }

    
    func toggleHeader1() {
        toggleHeaderSize(24)
    }
    
    func toggleHeader2() {
        toggleHeaderSize(20)
    }
    
    func toggleHeader3() {
        toggleHeaderSize(18)
    }
    
    func getSelectedText() -> String {
        guard let textView = textView else { return "" }
        
        let selectedRange = textView.selectedRange
        guard selectedRange.length > 0 else { return "" }
        
        let selectedText = (textView.attributedText.string as NSString).substring(with: selectedRange)
        return selectedText
    }
    
    func createLink(displayLabel: String, url: String) {
        guard let textView = textView else { return }
        
        let selectedRange = textView.selectedRange
        guard selectedRange.length > 0 else { return }
        
        let mutableText = NSMutableAttributedString(attributedString: textView.attributedText)
        
        // Replace the selected text with the display label
        mutableText.replaceCharacters(in: selectedRange, with: displayLabel)
        
        // Apply the link attribute to the new text
        let newRange = NSRange(location: selectedRange.location, length: displayLabel.count)
        if let linkURL = URL(string: url) {
            mutableText.addAttribute(.link, value: linkURL, range: newRange)
        }
        
        textView.attributedText = mutableText
        onTextChange?(mutableText)
        
        // Set cursor at the end of the link
        let newSelection = NSRange(location: selectedRange.location + displayLabel.count, length: 0)
        DispatchQueue.main.async {
            self.textView.selectedRange = newSelection
        }
    }
    
    private func toggleHeaderSize(_ fontSize: CGFloat) {
        guard let textView = textView else { return }
        
        let selectedRange = textView.selectedRange
        if selectedRange.length > 0 {
            // Text is selected - apply/remove header size to selection
            toggleHeaderAttribute(fontSize: fontSize, range: selectedRange)
        } else {
            // No selection - set typing attributes
            toggleHeaderTypingAttribute(fontSize: fontSize)
        }
        notifyFormattingChange()
    }
    
    private func toggleHeaderAttribute(fontSize: CGFloat, range: NSRange) {
        let mutableText = NSMutableAttributedString(attributedString: textView.attributedText)
        let selectedRange = textView.selectedRange // Preserve selection
        
        // Check if the selection already has this header size
        var hasHeaderSize = true
        mutableText.enumerateAttribute(.font, in: range) { value, _, _ in
            if let font = value as? UIFont {
                if font.pointSize != fontSize {
                    hasHeaderSize = false
                }
            } else {
                hasHeaderSize = false
            }
        }
        
        // Apply or remove the header size
        mutableText.enumerateAttribute(.font, in: range) { value, subRange, _ in
            let currentFont = (value as? UIFont) ?? defaultFont
            let newFont: UIFont
            
            if hasHeaderSize {
                // Remove header size - use default size but preserve traits
                newFont = fontByChangingSize(currentFont, newSize: defaultFont.pointSize)
            } else {
                // Apply header size - preserve traits but use header size
                newFont = fontByChangingSize(currentFont, newSize: fontSize)
            }
            
            mutableText.addAttribute(.font, value: newFont, range: subRange)
        }
        
        textView.attributedText = mutableText
        onTextChange?(mutableText)
        
        // Restore selection after a brief delay to ensure the text view has updated
        DispatchQueue.main.async {
            self.textView.selectedRange = selectedRange
        }
    }
    
    private func toggleHeaderTypingAttribute(fontSize: CGFloat) {
        var typingAttributes = textView.typingAttributes
        
        // Check if current typing attributes have the header font size
        let currentFont = (typingAttributes[.font] as? UIFont) ?? defaultFont
        let hasHeaderLevel = currentFont.pointSize == fontSize
        
        if hasHeaderLevel {
            // Remove header formatting - return to default font
            typingAttributes[.font] = defaultFont
            typingAttributes.removeValue(forKey: .paragraphStyle)
        } else {
            // Add header formatting - change font size while preserving traits
            let headerFont = fontByChangingSize(currentFont, newSize: fontSize)
            typingAttributes[.font] = headerFont
            typingAttributes[.paragraphStyle] = createHeaderParagraphStyle()
        }
        
        textView.typingAttributes = typingAttributes
    }
    
    private func createHeaderParagraphStyle() -> NSMutableParagraphStyle {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacing = 8
        paragraphStyle.paragraphSpacingBefore = 8
        return paragraphStyle
    }

    
    private func createHeaderFont(size: CGFloat, preservingTraitsFrom originalFont: UIFont) -> UIFont {
        // Start with system font at the header size
        let baseFont = UIFont.systemFont(ofSize: size)
        var traits = baseFont.fontDescriptor.symbolicTraits
        
        // Always add bold trait for headers
        traits.insert(.traitBold)
        
        // Preserve italic and underline from the original font, but only if it's not a default font
        if originalFont.pointSize != defaultFont.pointSize || originalFont != defaultFont {
            if originalFont.fontDescriptor.symbolicTraits.contains(.traitItalic) {
                traits.insert(.traitItalic)
            }
        }
        
        if let newDescriptor = baseFont.fontDescriptor.withSymbolicTraits(traits) {
            return UIFont(descriptor: newDescriptor, size: size)
        }
        
        return baseFont
    }
    
    private func getLinesInRange(_ range: NSRange, in text: String) -> [Range<String.Index>] {
        var lines: [Range<String.Index>] = []
        
        let nsText = text as NSString
        _ = nsText.substring(with: range) // Keep range validation
        
        // Find the start of the first line
        var lineStart = range.location
        while lineStart > 0 && nsText.character(at: lineStart - 1) != unichar(10) { // 10 is newline character
            lineStart -= 1
        }
        
        // Find the end of the last line
        var lineEnd = range.location + range.length
        while lineEnd < text.count && nsText.character(at: lineEnd) != unichar(10) { // 10 is newline character
            lineEnd += 1
        }
        
        let fullRange = NSRange(location: lineStart, length: lineEnd - lineStart)
        
        // Split into individual lines
        nsText.enumerateSubstrings(in: fullRange, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            if let stringRange = Range(lineRange, in: text) {
                lines.append(stringRange)
            }
        }
        
        return lines
    }
    
    private func toggleAttribute(_ attribute: NSAttributedString.Key, trait: UIFontDescriptor.SymbolicTraits, range: NSRange) {
        let mutableText = NSMutableAttributedString(attributedString: textView.attributedText)
        let selectedRange = textView.selectedRange // Preserve selection
        
        // Check if the trait is already applied to the entire selection
        var hasTraitApplied = true
        mutableText.enumerateAttribute(attribute, in: range) { value, _, _ in
            if let font = value as? UIFont {
                if !font.fontDescriptor.symbolicTraits.contains(trait) {
                    hasTraitApplied = false
                }
            } else {
                hasTraitApplied = false
            }
        }
        
        // Apply or remove the trait
        mutableText.enumerateAttribute(attribute, in: range) { value, subRange, _ in
            let currentFont = (value as? UIFont) ?? defaultFont
            let newFont: UIFont
            
            if hasTraitApplied {
                // Remove the trait
                newFont = fontByTogglingTrait(currentFont, trait: trait, add: false)
            } else {
                // Add the trait
                newFont = fontByTogglingTrait(currentFont, trait: trait, add: true)
            }
            
            mutableText.addAttribute(.font, value: newFont, range: subRange)
        }
        
        textView.attributedText = mutableText
        onTextChange?(mutableText)
        
        // Restore selection after a brief delay to ensure the text view has updated
        DispatchQueue.main.async {
            self.textView.selectedRange = selectedRange
        }
    }
    
    private func toggleTypingAttribute(_ attribute: NSAttributedString.Key, trait: UIFontDescriptor.SymbolicTraits) {
        var typingAttributes = textView.typingAttributes
        
        let currentFont = (typingAttributes[attribute] as? UIFont) ?? defaultFont
        let hasTrait = currentFont.fontDescriptor.symbolicTraits.contains(trait)
        let newFont = fontByTogglingTrait(currentFont, trait: trait, add: !hasTrait)
        typingAttributes[attribute] = newFont
        
        textView.typingAttributes = typingAttributes
    }
    
    private func fontByTogglingTrait(_ font: UIFont, trait: UIFontDescriptor.SymbolicTraits, add: Bool) -> UIFont {
        let descriptor = font.fontDescriptor
        var traits = descriptor.symbolicTraits
        
        if add {
            traits.insert(trait)
        } else {
            traits.remove(trait)
        }
        
        if let newDescriptor = descriptor.withSymbolicTraits(traits) {
            return UIFont(descriptor: newDescriptor, size: font.pointSize)
        }
        
        return font
    }
    
    private func fontByChangingSize(_ font: UIFont, newSize: CGFloat) -> UIFont {
        let descriptor = font.fontDescriptor
        return UIFont(descriptor: descriptor, size: newSize)
    }
    
    // MARK: - Formatting State Detection
    
    func getCurrentFormattingState() -> (isBold: Bool, isItalic: Bool, isUnderlined: Bool, isStrikethrough: Bool, isBulletList: Bool, isNumberedList: Bool, isH1: Bool, isH2: Bool, isH3: Bool) {
        guard let textView = textView else { return (false, false, false, false, false, false, false, false, false) }
        
        let selectedRange = textView.selectedRange
        guard let attributedText = textView.attributedText else { return (false, false, false, false, false, false, false, false, false) }
        
        if selectedRange.length > 0 {
            // Check formatting of selected text - use first character as representative
            let basicFormatting = getFormattingAtLocation(selectedRange.location, in: attributedText)
            let listFormatting = getListFormattingInRange(selectedRange, in: attributedText)
            let headerFormatting = getHeaderFormattingAtLocation(selectedRange.location, in: attributedText)
            return (basicFormatting.isBold, basicFormatting.isItalic, basicFormatting.isUnderlined, basicFormatting.isStrikethrough,
                   listFormatting.isBulletList, listFormatting.isNumberedList,
                   headerFormatting.isH1, headerFormatting.isH2, headerFormatting.isH3)
        } else {
            // Check typing attributes when no selection
            let typingAttributes = textView.typingAttributes
            let isBold = isAttributeBold(typingAttributes)
            let isItalic = isAttributeItalic(typingAttributes)
            let isUnderlined = isAttributeUnderlined(typingAttributes)
            let isStrikethrough = isAttributeStrikethrough(typingAttributes)
            let headerFormatting = getHeaderFormattingFromTypingAttributes(typingAttributes)
            
            // Check current line for list formatting
            let listFormatting = getListFormattingInRange(NSRange(location: selectedRange.location, length: 0), in: attributedText)
            
            return (isBold, isItalic, isUnderlined, isStrikethrough, listFormatting.isBulletList, listFormatting.isNumberedList,
                   headerFormatting.isH1, headerFormatting.isH2, headerFormatting.isH3)
        }
    }
    
    private func getFormattingAtLocation(_ location: Int, in attributedText: NSAttributedString) -> (isBold: Bool, isItalic: Bool, isUnderlined: Bool, isStrikethrough: Bool) {
        guard location < attributedText.length else { return (false, false, false, false) }
        
        let attributes = attributedText.attributes(at: location, effectiveRange: nil)
        let isBold = isAttributeBold(attributes)
        let isItalic = isAttributeItalic(attributes)
        let isUnderlined = isAttributeUnderlined(attributes)
        let isStrikethrough = isAttributeStrikethrough(attributes)
        
        return (isBold, isItalic, isUnderlined, isStrikethrough)
    }
    
    private func isAttributeBold(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
        if let font = attributes[.font] as? UIFont {
            return font.fontDescriptor.symbolicTraits.contains(.traitBold)
        }
        return false
    }
    
    private func isAttributeItalic(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
        if let font = attributes[.font] as? UIFont {
            return font.fontDescriptor.symbolicTraits.contains(.traitItalic)
        }
        return false
    }
    
    private func isAttributeUnderlined(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
        if let underlineValue = attributes[.underlineStyle] as? Int {
            return underlineValue != 0
        }
        return false
    }
    
    private func isAttributeStrikethrough(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
        if let strikeValue = attributes[.strikethroughStyle] as? Int {
            return strikeValue != 0
        }
        return false
    }

    private func getHeaderFormattingAtLocation(_ location: Int, in attributedText: NSAttributedString) -> (isH1: Bool, isH2: Bool, isH3: Bool) {
        guard location < attributedText.length else { return (false, false, false) }
        
        let attributes = attributedText.attributes(at: location, effectiveRange: nil)
        return getHeaderFormattingFromAttributes(attributes)
    }
    
    private func getHeaderFormattingFromTypingAttributes(_ attributes: [NSAttributedString.Key: Any]) -> (isH1: Bool, isH2: Bool, isH3: Bool) {
        return getHeaderFormattingFromAttributes(attributes)
    }
    
    private func getHeaderFormattingFromAttributes(_ attributes: [NSAttributedString.Key: Any]) -> (isH1: Bool, isH2: Bool, isH3: Bool) {
        if let font = attributes[.font] as? UIFont {
            let fontSize = font.pointSize
            
            // Headers are determined by font size only, independent of bold/italic
            switch fontSize {
            case 24:
                return (true, false, false)
            case 20:
                return (false, true, false)
            case 18:
                return (false, false, true)
            default:
                return (false, false, false)
            }
        }
        return (false, false, false)
    }

    
    private func getListFormattingInRange(_ range: NSRange, in attributedText: NSAttributedString) -> (isBulletList: Bool, isNumberedList: Bool) {
        let text = attributedText.string
        guard !text.isEmpty else { return (false, false) }
        
        // Find the current line(s)
        let nsText = text as NSString
        var lineStart = range.location
        
        // Find the start of the current line
        while lineStart > 0 && nsText.character(at: lineStart - 1) != unichar(10) { // 10 is newline character
            lineStart -= 1
        }
        
        // Get the line range
        var lineEnd = lineStart
        while lineEnd < text.count && nsText.character(at: lineEnd) != unichar(10) { // 10 is newline character
            lineEnd += 1
        }
        
        let lineRange = NSRange(location: lineStart, length: lineEnd - lineStart)
        guard lineRange.length > 0 else { return (false, false) }
        
        let lineText = nsText.substring(with: lineRange)
        
        // Check for bullet list
        let isBulletList = lineText.hasPrefix("• ")
        
        // Check for numbered list
        let isNumberedList = lineText.range(of: #"^\d+\. "#, options: .regularExpression) != nil
        
        return (isBulletList, isNumberedList)
    }
    
    private func notifyFormattingChange() {
        let state = getCurrentFormattingState()
        onFormattingChange?(state.isBold, state.isItalic, state.isUnderlined, state.isStrikethrough, state.isBulletList, state.isNumberedList, state.isH1, state.isH2, state.isH3)
    }
    
    // MARK: - Initialization
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupTextKit2Stack()
        setupTextView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTextKit2Stack()
        setupTextView()
    }
    
    private func setupTextKit2Stack() {
        // Connect NSTextContentStorage → NSTextLayoutManager → NSTextContainer
        textContentStorage.addTextLayoutManager(textLayoutManager)
        textLayoutManager.textContainer = textContainer
        
        // Configure text container
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false
        textContainer.lineFragmentPadding = 0
    }
    
    private func setupTextView() {
        // Create UITextView with TextKit 2 stack
        textView = UITextView(frame: .zero, textContainer: textContainer)
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.delegate = self
        textView.font = defaultFont
        textView.textColor = defaultTextColor
        textView.backgroundColor = .clear
        textView.isScrollEnabled = true
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        
        addSubview(textView)
        
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        
        // Set initial attributed text with default styling
        setDefaultAttributedText()
    }
    
    private func setDefaultAttributedText() {
        let defaultAttributes: [NSAttributedString.Key: Any] = [
            .font: defaultFont,
            .foregroundColor: defaultTextColor
        ]
        textView.attributedText = NSAttributedString(string: "", attributes: defaultAttributes)
        lastTextLength = 0
    }
    
    // MARK: - Public Methods
    func setAttributedText(_ attributedString: NSAttributedString) {
        // Preserve current caret/selection to prevent cursor jumping
        let currentSelection = textView?.selectedRange ?? NSRange(location: 0, length: 0)
        let wasFirstResponder = textView?.isFirstResponder ?? false

        textView.attributedText = attributedString
        lastTextLength = attributedString.length

        // Restore selection, clamped to valid range
        let maxLocation = max(0, min(currentSelection.location, attributedString.length))
        let maxLength = currentSelection.length > 0
            ? max(0, min(currentSelection.length, attributedString.length - maxLocation))
            : 0
        textView.selectedRange = NSRange(location: maxLocation, length: maxLength)

        // Ensure responder state remains consistent
        if wasFirstResponder, !textView.isFirstResponder {
            textView.becomeFirstResponder()
        }
    }
    
    func getAttributedText() -> NSAttributedString {
        return textView.attributedText ?? NSAttributedString()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        // TextKit 2 automatically handles layout updates
    }
}

// MARK: - UITextViewDelegate
@available(iOS 15.0, *)
extension RichTextEditorView: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        // Handle pending list continuation first, but only if it's from a return key operation
        if let continuation = pendingListContinuation {
            pendingListContinuation = nil
            
            let mutableText = NSMutableAttributedString(attributedString: textView.attributedText)
            let currentCursorPosition = textView.selectedRange.location
            
            // Only proceed if:
            // 1. We're still at the expected insertion point (within reasonable range)
            // 2. The text length makes sense 
            // 3. We actually have a newline character at the expected position
            if continuation.insertionPoint <= mutableText.length && 
               continuation.insertionPoint > 0 &&
               abs(currentCursorPosition - continuation.insertionPoint) <= 2 {
                
                let stringText = mutableText.string
                // Check if we have a newline at the insertion point - 1 (indicating this came from return key)
                if continuation.insertionPoint <= stringText.count {
                    let checkIndex = continuation.insertionPoint - 1
                    if checkIndex >= 0 && checkIndex < stringText.count {
                        let nsText = stringText as NSString
                        let charAtPosition = nsText.character(at: checkIndex)
                        
                        // Only continue if we have a newline, confirming this is from a return key
                        if charAtPosition == unichar(10) { // newline character
                            
                            // Prepare attributes for the list prefix
                            var attributes: [NSAttributedString.Key: Any] = [
                                .font: defaultFont,
                                .foregroundColor: defaultTextColor
                            ]
                            if let paragraphStyle = continuation.paragraphStyle {
                                attributes[.paragraphStyle] = paragraphStyle
                            }
                            
                            let listPrefixString = NSAttributedString(string: continuation.prefix, attributes: attributes)
                            
                            // Insert the list prefix at the continuation point
                            mutableText.insert(listPrefixString, at: continuation.insertionPoint)
                            
                            // Calculate new cursor position
                            let newCursorPosition = continuation.insertionPoint + continuation.prefix.count
                            
                            // Update text view without triggering another change event
                            textView.attributedText = mutableText
                            
                            // Set cursor position only if it makes sense
                            if newCursorPosition <= mutableText.length {
                                textView.selectedRange = NSRange(location: newCursorPosition, length: 0)
                            }
                            
                            // Skip ensureDefaultAttributes since we just set the text
                            onTextChange?(textView.attributedText)
                            notifyFormattingChange()
                            return
                        }
                    }
                }
            }
        }
        
        // Only run ensureDefaultAttributes for text additions, not deletions
        // This prevents cursor jumping during delete operations
        let currentLength = textView.attributedText.length
        if currentLength > lastTextLength {
            // Text was added, ensure it has default attributes
            ensureDefaultAttributes(in: textView)
        }
        lastTextLength = currentLength
        
        onTextChange?(textView.attributedText)
        notifyFormattingChange()
    }
    
    func textViewDidChangeSelection(_ textView: UITextView) {
        notifyFormattingChange()
    }
    
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        // Handle return key specially to maintain proper list formatting
        if text == "\n" {
            return handleReturnKeyImproved(in: textView, at: range)
        }
        
        // For other text, set typing attributes to default
        textView.typingAttributes = [
            .font: defaultFont,
            .foregroundColor: defaultTextColor
        ]
        return true
    }

    
    private func handleReturnKeyImproved(in textView: UITextView, at range: NSRange) -> Bool {
        let mutableText = NSMutableAttributedString(attributedString: textView.attributedText)
        let insertPosition = range.location
        
        // Get current line information
        let currentLineRange = getCurrentLineRange(at: insertPosition, in: mutableText.string)
        let currentLineText = String(mutableText.string[currentLineRange])
        
        // Check if we're in a list and determine what to do
        var shouldContinueList = false
        var shouldRemoveEmptyListItem = false
        var listPrefix = ""
        var listParagraphStyle: NSParagraphStyle?
        
        if currentLineText.hasPrefix("• ") {
            // Bullet list handling
            let contentAfterBullet = String(currentLineText.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !contentAfterBullet.isEmpty {
                // Non-empty bullet - continue the list
                shouldContinueList = true
                listPrefix = "• "
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.headIndent = 20
                paragraphStyle.firstLineHeadIndent = 0
                listParagraphStyle = paragraphStyle
            } else {
                // Empty bullet - remove it and end the list
                shouldRemoveEmptyListItem = true
            }
        } else if let numberedMatch = currentLineText.range(of: #"^(\d+)\. "#, options: .regularExpression) {
            // Numbered list handling
            let contentAfterNumber = String(currentLineText[numberedMatch.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !contentAfterNumber.isEmpty {
                // Non-empty numbered item - continue the list
                // Extract current number and increment
                let prefix = String(currentLineText[..<numberedMatch.upperBound])
                if let numberMatch = prefix.range(of: #"\d+"#, options: .regularExpression) {
                    let numberString = String(prefix[numberMatch])
                    if let currentNumber = Int(numberString) {
                        shouldContinueList = true
                        listPrefix = "\(currentNumber + 1). "
                        let paragraphStyle = NSMutableParagraphStyle()
                        paragraphStyle.headIndent = 20
                        paragraphStyle.firstLineHeadIndent = 0
                        listParagraphStyle = paragraphStyle
                    }
                }
            } else {
                // Empty numbered item - remove it and end the list
                shouldRemoveEmptyListItem = true
            }
        }
        
        // Handle empty list items
        if shouldRemoveEmptyListItem {
            // Calculate the range of the current line
            let stringText = mutableText.string
            
            // Convert String.Index range to NSRange
            let lineStartOffset = currentLineRange.lowerBound.utf16Offset(in: stringText)
            let lineEndOffset = currentLineRange.upperBound.utf16Offset(in: stringText)
            let lineNSRange = NSRange(location: lineStartOffset, length: lineEndOffset - lineStartOffset)
            
            // Remove the empty list item line
            mutableText.deleteCharacters(in: lineNSRange)
            
            // Insert a newline with default formatting (no list indentation)
            let newlineAttributes: [NSAttributedString.Key: Any] = [
                .font: defaultFont,
                .foregroundColor: defaultTextColor
            ]
            let newlineString = NSAttributedString(string: "\n", attributes: newlineAttributes)
            mutableText.insert(newlineString, at: lineNSRange.location)
            
            // Update the text view
            textView.attributedText = mutableText
            
            // Position cursor at the start of the new line
            let newCursorPosition = lineNSRange.location + 1
            textView.selectedRange = NSRange(location: newCursorPosition, length: 0)
            
            // Call the text change handler
            onTextChange?(textView.attributedText)
            notifyFormattingChange()
            
            return false // We handled the return ourselves
        }
        
        // Let UITextView handle the return normally first
        let insertionPoint = range.location
        
        // If we should continue a list, we'll do it in the textViewDidChange callback
        if shouldContinueList {
            // Store the list continuation info for the callback
            pendingListContinuation = ListContinuation(
                insertionPoint: insertionPoint + 1, // +1 because return will be inserted
                prefix: listPrefix,
                paragraphStyle: listParagraphStyle
            )
        }
        
        return true // Let UITextView handle the return normally
    }
    
    private func getCurrentLineRange(at position: Int, in text: String) -> Range<String.Index> {
        let nsText = text as NSString
        var lineStart = position
        var lineEnd = position
        
        // Find start of current line
        while lineStart > 0 && nsText.character(at: lineStart - 1) != unichar(10) {
            lineStart -= 1
        }
        
        // Find end of current line
        while lineEnd < text.count && nsText.character(at: lineEnd) != unichar(10) {
            lineEnd += 1
        }
        
        let startIndex = text.index(text.startIndex, offsetBy: lineStart)
        let endIndex = text.index(text.startIndex, offsetBy: lineEnd)
        
        return startIndex..<endIndex
    }
    
    private func ensureDefaultAttributes(in textView: UITextView) {
        let mutableText = NSMutableAttributedString(attributedString: textView.attributedText)
        let range = NSRange(location: 0, length: mutableText.length)
        
        mutableText.enumerateAttributes(in: range, options: []) { attributes, range, _ in
            if attributes[.font] == nil {
                mutableText.addAttribute(.font, value: defaultFont, range: range)
            }
            if attributes[.foregroundColor] == nil {
                mutableText.addAttribute(.foregroundColor, value: defaultTextColor, range: range)
            }
        }
        
        if !mutableText.isEqual(to: textView.attributedText) {
            // Preserve cursor position when updating attributed text
            let currentSelection = textView.selectedRange
            textView.attributedText = mutableText
            textView.selectedRange = currentSelection
        }
    }
    
    // MARK: - Hyperlink Interaction Override
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        // Override tap+hold behavior on hyperlinks to show custom link editor
        if interaction == .presentActions {
            // Get the link text for pre-population
            let linkText = (textView.attributedText.string as NSString).substring(with: characterRange)
            
            // Set selection to the link range for editing
            textView.selectedRange = characterRange
            
            // Trigger the link dialog with existing link data via notification
            NotificationCenter.default.post(
                name: NSNotification.Name("EditHyperlink"),
                object: nil,
                userInfo: [
                    "displayLabel": linkText,
                    "url": URL.absoluteString
                ]
            )
            
            // Return false to prevent the default system dialog
            return false
        }
        
        // Allow normal tap behavior (opening links)
        return true
    }
}

// MARK: - SwiftUI Wrapper
@available(iOS 15.0, *)
struct RichTextEditor: UIViewRepresentable {
    @Binding var attributedText: NSAttributedString
    @State private var isBold = false
    @State private var isItalic = false
    @State private var isUnderlined = false
    @State private var isStrikethrough = false
    @State private var isBulletList = false
    @State private var isNumberedList = false
    @State private var isH1 = false
    @State private var isH2 = false
    @State private var isH3 = false
    
    private let coordinator = Coordinator()
    
    class Coordinator {
        var editorView: RichTextEditorView?
        var parent: RichTextEditor?
        
        func toggleBold() {
            editorView?.toggleBold()
        }
        
        func toggleItalic() {
            editorView?.toggleItalic()
        }
        
        func toggleUnderline() {
            editorView?.toggleUnderline()
        }

        func toggleStrikethrough() {
            editorView?.toggleStrikethrough()
        }

        
        func toggleBulletList() {
            editorView?.toggleBulletList()
        }
        
        func toggleNumberedList() {
            editorView?.toggleNumberedList()
        }



        
        func toggleHeader1() {
            editorView?.toggleHeader1()
        }
        
        func toggleHeader2() {
            editorView?.toggleHeader2()
        }
        
        func toggleHeader3() {
            editorView?.toggleHeader3()
        }
        
        func getSelectedText() -> String {
            return editorView?.getSelectedText() ?? ""
        }
        
        func createLink(displayLabel: String, url: String) {
            editorView?.createLink(displayLabel: displayLabel, url: url)
        }
        
        func updateFormattingState(isBold: Bool, isItalic: Bool, isUnderlined: Bool, isStrikethrough: Bool, isBulletList: Bool, isNumberedList: Bool, isH1: Bool, isH2: Bool, isH3: Bool) {
            parent?.updateFormattingState(isBold: isBold, isItalic: isItalic, isUnderlined: isUnderlined, isStrikethrough: isStrikethrough, isBulletList: isBulletList, isNumberedList: isNumberedList, isH1: isH1, isH2: isH2, isH3: isH3)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        coordinator.parent = self
        return coordinator
    }
    
    func makeUIView(context: Context) -> RichTextEditorView {
        let editorView = RichTextEditorView()
        editorView.onTextChange = { newAttributedText in
            DispatchQueue.main.async {
                attributedText = newAttributedText
            }
        }
        
        editorView.onFormattingChange = { isBold, isItalic, isUnderlined, isStrikethrough, isBulletList, isNumberedList, isH1, isH2, isH3 in
            DispatchQueue.main.async {
                context.coordinator.updateFormattingState(isBold: isBold, isItalic: isItalic, isUnderlined: isUnderlined, isStrikethrough: isStrikethrough, isBulletList: isBulletList, isNumberedList: isNumberedList, isH1: isH1, isH2: isH2, isH3: isH3)
            }
        }
        
        // Store reference in coordinator for formatting methods
        coordinator.editorView = editorView
        
        return editorView
    }
    
    func updateUIView(_ uiView: RichTextEditorView, context: Context) {
        let currentText = uiView.getAttributedText()
        if !currentText.isEqual(to: attributedText) {
            uiView.setAttributedText(attributedText)
        }
    }
    
    // MARK: - Formatting Methods
    
    func toggleBold() {
        coordinator.toggleBold()
    }
    
    func toggleItalic() {
        coordinator.toggleItalic()
    }
    
    func toggleUnderline() {
        coordinator.toggleUnderline()
    }

    func toggleStrikethrough() {
        coordinator.toggleStrikethrough()
    }
    
    func updateFormattingState(isBold: Bool, isItalic: Bool, isUnderlined: Bool, isStrikethrough: Bool, isBulletList: Bool, isNumberedList: Bool, isH1: Bool, isH2: Bool, isH3: Bool) {
        self.isBold = isBold
        self.isItalic = isItalic
        self.isUnderlined = isUnderlined
        self.isStrikethrough = isStrikethrough
        self.isBulletList = isBulletList
        self.isNumberedList = isNumberedList
        self.isH1 = isH1
        self.isH2 = isH2
        self.isH3 = isH3
    }
    
    func getFormattingState() -> (isBold: Bool, isItalic: Bool, isUnderlined: Bool, isStrikethrough: Bool, isBulletList: Bool, isNumberedList: Bool, isH1: Bool, isH2: Bool, isH3: Bool) {
        return (isBold, isItalic, isUnderlined, isStrikethrough, isBulletList, isNumberedList, isH1, isH2, isH3)
    }
}
