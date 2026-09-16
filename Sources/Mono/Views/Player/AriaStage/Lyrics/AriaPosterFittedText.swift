import SwiftUI
import UIKit

/// UILabel performs native wrapping and font measurement in the actual proposed rectangle.
/// Fit both dimensions, including custom fonts, rather than truncate at a fixed line count.
struct AriaPosterFittedText: UIViewRepresentable {
    let text: String
    let font: UIFont
    let color: Color
    var outline: Bool = false

    func makeUIView(context: Context) -> AriaPosterTextBox { AriaPosterTextBox() }

    func updateUIView(_ view: AriaPosterTextBox, context: Context) {
        view.configure(text: text, font: font, color: UIColor(color), outline: outline)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: AriaPosterTextBox, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 1, height: proposal.height ?? font.lineHeight * 2)
    }
}

final class AriaPosterTextBox: UIView {
    private let label = UILabel()
    private var sourceText = ""
    private var sourceFont = UIFont.systemFont(ofSize: 32)
    private var sourceColor = UIColor.white
    private var outlined = false
    private var needsFit = true
    private var fittedSize = CGSize.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        label.numberOfLines = 0
        label.lineBreakMode = .byCharWrapping
        label.textAlignment = .center
        label.isAccessibilityElement = false
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(text: String, font: UIFont, color: UIColor, outline: Bool) {
        guard sourceText != text || sourceFont != font || sourceColor != color || outlined != outline else { return }
        sourceText = text
        sourceFont = font
        sourceColor = color
        outlined = outline
        needsFit = true
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Leave space for stroke and custom-font overhangs.
        let rect = bounds.insetBy(dx: 6, dy: 6)
        guard rect.width > 0, rect.height > 0 else { return }
        label.frame = rect
        guard needsFit || fittedSize != rect.size else { return }
        needsFit = false
        fittedSize = rect.size

        label.attributedText = nil
        label.text = sourceText
        label.font = sourceFont
        var lower: CGFloat = 0.1
        var upper: CGFloat = sourceFont.pointSize
        for _ in 0..<16 {
            let pointSize = (lower + upper) / 2
            label.font = sourceFont.withSize(pointSize)
            let measured = label.sizeThatFits(CGSize(width: rect.width, height: .greatestFiniteMagnitude))
            if measured.width <= rect.width && measured.height <= rect.height {
                lower = pointSize
            } else {
                upper = pointSize
            }
        }
        let fittedFont = sourceFont.withSize(lower)
        label.font = fittedFont
        label.textColor = sourceColor
        if outlined {
            label.attributedText = NSAttributedString(string: sourceText, attributes: [
                .font: fittedFont, .strokeColor: sourceColor,
                .strokeWidth: 1.4, .foregroundColor: UIColor.clear
            ])
        }
    }
}
