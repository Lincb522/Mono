import XCTest
import UIKit
@testable import Mono

@MainActor
final class AriaPosterFittedTextTests: XCTestCase {
    func testLongLyricsFitBothDimensionsWithoutLineTruncation() throws {
        let texts = [
            String(repeating: "让每一行歌词完整地显示在屏幕里面", count: 10),
            String(repeating: "A-long-unbroken-lyric-word", count: 12),
            "First line\nSecond line\n第三行歌词\nFourth line",
        ]
        for size in [CGSize(width: 160, height: 64), CGSize(width: 600, height: 180)] {
            for text in texts {
                let view = AriaPosterTextBox(frame: CGRect(origin: .zero, size: size))
                view.configure(text: text, font: .italicSystemFont(ofSize: 112), color: .white, outline: false)
                view.setNeedsLayout()
                view.layoutIfNeeded()
                let label = try XCTUnwrap(view.subviews.compactMap { $0 as? UILabel }.first)
                let measured = label.sizeThatFits(CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude))
                XCTAssertEqual(label.text, text)
                XCTAssertEqual(label.numberOfLines, 0)
                XCTAssertEqual(label.lineBreakMode, .byCharWrapping)
                XCTAssertLessThanOrEqual(measured.width, label.bounds.width)
                XCTAssertLessThanOrEqual(measured.height, label.bounds.height)
            }
        }
    }

    func testOutlineRefitsAfterViewportRotation() throws {
        let view = AriaPosterTextBox(frame: CGRect(x: 0, y: 0, width: 600, height: 180))
        view.configure(text: String(repeating: "歌词 Outline ", count: 12),
                       font: .boldSystemFont(ofSize: 100), color: .white, outline: true)
        view.layoutIfNeeded()
        view.frame = CGRect(x: 0, y: 0, width: 220, height: 70)
        view.setNeedsLayout()
        view.layoutIfNeeded()
        let label = try XCTUnwrap(view.subviews.compactMap { $0 as? UILabel }.first)
        XCTAssertEqual(label.numberOfLines, 0)
        XCTAssertNotNil(label.attributedText)
        let measured = label.sizeThatFits(CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude))
        XCTAssertLessThanOrEqual(measured.height, label.bounds.height)
    }
}
