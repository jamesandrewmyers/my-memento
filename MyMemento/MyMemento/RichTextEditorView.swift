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
    
    func makeUIView(context: Context) -> RichTextEditorView {
        let editorView = RichTextEditorView()
        editorView.onTextChange = { newAttributedText in
            DispatchQueue.main.async {
                attributedText = newAttributedText
            }
        }
        return editorView
    }
    
    func updateUIView(_ uiView: RichTextEditorView, context: Context) {
        let currentText = uiView.getAttributedText()
        if !currentText.isEqual(to: attributedText) {
            uiView.setAttributedText(attributedText)
        }
    }
}