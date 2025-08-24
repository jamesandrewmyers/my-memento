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
    var onFormattingChange: ((Bool, Bool, Bool) -> Void)?
    
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
    
    // MARK: - Formatting State Detection
    
    func getCurrentFormattingState() -> (isBold: Bool, isItalic: Bool, isUnderlined: Bool) {
        guard let textView = textView else { return (false, false, false) }
        
        let selectedRange = textView.selectedRange
        guard let attributedText = textView.attributedText else { return (false, false, false) }
        
        if selectedRange.length > 0 {
            // Check formatting of selected text - use first character as representative
            return getFormattingAtLocation(selectedRange.location, in: attributedText)
        } else {
            // Check typing attributes when no selection
            let typingAttributes = textView.typingAttributes
            let isBold = isAttributeBold(typingAttributes)
            let isItalic = isAttributeItalic(typingAttributes)
            let isUnderlined = isAttributeUnderlined(typingAttributes)
            return (isBold, isItalic, isUnderlined)
        }
    }
    
    private func getFormattingAtLocation(_ location: Int, in attributedText: NSAttributedString) -> (isBold: Bool, isItalic: Bool, isUnderlined: Bool) {
        guard location < attributedText.length else { return (false, false, false) }
        
        let attributes = attributedText.attributes(at: location, effectiveRange: nil)
        let isBold = isAttributeBold(attributes)
        let isItalic = isAttributeItalic(attributes)
        let isUnderlined = isAttributeUnderlined(attributes)
        
        return (isBold, isItalic, isUnderlined)
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
    
    private func notifyFormattingChange() {
        let state = getCurrentFormattingState()
        onFormattingChange?(state.isBold, state.isItalic, state.isUnderlined)
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
    }
    
    // MARK: - Public Methods
    func setAttributedText(_ attributedString: NSAttributedString) {
        textView.attributedText = attributedString
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
        // Ensure new text gets default attributes
        ensureDefaultAttributes(in: textView)
        onTextChange?(textView.attributedText)
        notifyFormattingChange()
    }
    
    func textViewDidChangeSelection(_ textView: UITextView) {
        notifyFormattingChange()
    }
    
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        // Set typing attributes to default for new text
        textView.typingAttributes = [
            .font: defaultFont,
            .foregroundColor: defaultTextColor
        ]
        return true
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
            textView.attributedText = mutableText
        }
    }
}

// MARK: - SwiftUI Wrapper
@available(iOS 15.0, *)
struct RichTextEditor: UIViewRepresentable {
    @Binding var attributedText: NSAttributedString
    @State private var isBold = false
    @State private var isItalic = false
    @State private var isUnderlined = false
    
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
        
        func updateFormattingState(isBold: Bool, isItalic: Bool, isUnderlined: Bool) {
            parent?.updateFormattingState(isBold: isBold, isItalic: isItalic, isUnderlined: isUnderlined)
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
        
        editorView.onFormattingChange = { isBold, isItalic, isUnderlined in
            DispatchQueue.main.async {
                context.coordinator.updateFormattingState(isBold: isBold, isItalic: isItalic, isUnderlined: isUnderlined)
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
    
    func updateFormattingState(isBold: Bool, isItalic: Bool, isUnderlined: Bool) {
        self.isBold = isBold
        self.isItalic = isItalic
        self.isUnderlined = isUnderlined
    }
    
    func getFormattingState() -> (isBold: Bool, isItalic: Bool, isUnderlined: Bool) {
        return (isBold, isItalic, isUnderlined)
    }
}