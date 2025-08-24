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
    }
    
    func toggleUnderline() {
        guard let textView = textView else { return }
        
        let selectedRange = textView.selectedRange
        if selectedRange.length > 0 {
            // Text is selected - apply/remove underline to selection
            let mutableText = NSMutableAttributedString(attributedString: textView.attributedText)
            
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
    }
    
    private func toggleAttribute(_ attribute: NSAttributedString.Key, trait: UIFontDescriptor.SymbolicTraits, range: NSRange) {
        let mutableText = NSMutableAttributedString(attributedString: textView.attributedText)
        
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
    
    private let coordinator = Coordinator()
    
    class Coordinator {
        var editorView: RichTextEditorView?
        
        func toggleBold() {
            editorView?.toggleBold()
        }
        
        func toggleItalic() {
            editorView?.toggleItalic()
        }
        
        func toggleUnderline() {
            editorView?.toggleUnderline()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        return coordinator
    }
    
    func makeUIView(context: Context) -> RichTextEditorView {
        let editorView = RichTextEditorView()
        editorView.onTextChange = { newAttributedText in
            DispatchQueue.main.async {
                attributedText = newAttributedText
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
}