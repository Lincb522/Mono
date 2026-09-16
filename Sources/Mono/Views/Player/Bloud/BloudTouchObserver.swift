import SwiftUI
import UIKit

/// Observes touches inside the player without competing with buttons, scrolling or seeking.
struct BloudTouchObserver: UIViewRepresentable {
    var isEnabled: Bool
    var onOrientation: ((UIInterfaceOrientation) -> Void)? = nil
    var onTouch: (CGPoint, Bool) -> Void

    func makeUIView(context: Context) -> ProbeView { ProbeView() }

    func updateUIView(_ view: ProbeView, context: Context) {
        view.observationEnabled = isEnabled
        view.onTouch = onTouch
        view.onOrientation = onOrientation
        view.reportOrientation()
    }

    static func dismantleUIView(_ view: ProbeView, coordinator: ()) { view.detach() }

    final class ProbeView: UIView {
        var observationEnabled = true
        var onTouch: ((CGPoint, Bool) -> Void)?
        var onOrientation: ((UIInterfaceOrientation) -> Void)?
        private var recognizer: TouchRecognizer?
        private var hoverRecognizer: HoverRecognizer?
        private var lastHoverPoint: CGPoint?

        init() {
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
            backgroundColor = .clear
        }

        required init?(coder: NSCoder) { return nil }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            detach()
            guard let window else { return }
            let observer = TouchRecognizer(target: nil, action: nil)
            observer.probe = self
            observer.cancelsTouchesInView = false
            observer.delaysTouchesBegan = false
            observer.delaysTouchesEnded = false
            window.addGestureRecognizer(observer)
            recognizer = observer
            let hover = HoverRecognizer(target: self, action: #selector(observeHover(_:)))
            hover.cancelsTouchesInView = false
            hover.delaysTouchesBegan = false
            hover.delaysTouchesEnded = false
            window.addGestureRecognizer(hover)
            hoverRecognizer = hover
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            reportOrientation()
        }

        func reportOrientation() {
            if let orientation = window?.windowScene?.interfaceOrientation { onOrientation?(orientation) }
        }

        func detach() {
            if let recognizer { recognizer.view?.removeGestureRecognizer(recognizer) }
            if let hoverRecognizer { hoverRecognizer.view?.removeGestureRecognizer(hoverRecognizer) }
            recognizer = nil
            hoverRecognizer = nil
            lastHoverPoint = nil
        }
        @objc private func observeHover(_ hover: UIHoverGestureRecognizer) {
            guard recognizer?.state != .began, recognizer?.state != .changed else { return }
            let point = hover.location(in: self)
            if observationEnabled, bounds.contains(point), hover.state == .began || hover.state == .changed {
                lastHoverPoint = point
                onTouch?(point, true)
            } else if let lastHoverPoint {
                onTouch?(lastHoverPoint, false)
                self.lastHoverPoint = nil
            }
        }

    }

    final class HoverRecognizer: UIHoverGestureRecognizer {
        override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
        override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    }

    final class TouchRecognizer: UIGestureRecognizer {
        weak var probe: ProbeView?
        private weak var primaryTouch: UITouch?

        override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
        override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            guard primaryTouch == nil, let probe, probe.observationEnabled,
                  let touch = touches.first, probe.bounds.contains(touch.location(in: probe)) else { return }
            primaryTouch = touch
            state = .began
            probe.onTouch?(touch.location(in: probe), true)
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
            guard let touch = primaryTouch, touches.contains(touch), let probe,
                  probe.observationEnabled else { return }
            state = .changed
            probe.onTouch?(touch.location(in: probe), true)
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            finish(touches, cancelled: false)
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
            finish(touches, cancelled: true)
        }

        override func reset() {
            super.reset()
            primaryTouch = nil
        }

        private func finish(_ touches: Set<UITouch>, cancelled: Bool) {
            guard let touch = primaryTouch, touches.contains(touch) else { return }
            // A button can open a sheet before touchesEnded. Still release the
            // gaze that began here even when observation was disabled meanwhile.
            if let probe { probe.onTouch?(touch.location(in: probe), false) }
            state = cancelled ? .cancelled : .ended
            primaryTouch = nil
        }
    }
}
