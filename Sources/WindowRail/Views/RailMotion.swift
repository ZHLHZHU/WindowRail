import AppKit
import QuartzCore

/// A stationary clipped panel avoids sliding onto the neighbouring display.
/// Animate its contents with Core Animation, sampling the presentation layer on reversal.
final class RailTrackingView: NSView {
    var onMouseEntered: (() -> Void)?
    private var tracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }
    override func mouseEntered(with event: NSEvent) { onMouseEntered?() }
}

final class RailMotion {
    let clip = RailTrackingView()
    let content: NSView
    private var generation = 0
    private(set) var animating = false

    init(content: NSView) {
        self.content = content
        clip.wantsLayer = true
        clip.layer?.masksToBounds = true
        clip.layer?.cornerRadius = 6
        content.wantsLayer = true
        content.autoresizingMask = [.width, .height]
        clip.addSubview(content)
    }
    func resize(_ size: NSSize) {
        clip.setFrameSize(size)
        content.frame = NSRect(x: 0, y: 0, width: 174, height: size.height)
    }
    func setVisible(_ visible: Bool, completion: @escaping () -> Void) {
        guard let layer = content.layer else { completion(); return }
        generation += 1
        let token = generation
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let key = reduceMotion ? "opacity" : "transform.translation.x"
        let current = layer.presentation()?.value(forKeyPath: key) ?? layer.value(forKeyPath: key)
        let destination: Double = reduceMotion ? (visible ? 1 : 0) : (visible ? 0 : -Double(clip.bounds.width))
        layer.removeAllAnimations()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = CATransform3DIdentity
        layer.opacity = 1
        layer.setValue(destination, forKeyPath: key)
        CATransaction.commit()
        let animation = CABasicAnimation(keyPath: key)
        animation.fromValue = current
        animation.toValue = destination
        animation.duration = reduceMotion ? 0.12 : (visible ? 0.24 : 0.20)
        animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.68, 0.0, 1.0)
        animating = true
        layer.add(animation, forKey: "railReveal")
        DispatchQueue.main.asyncAfter(deadline: .now() + animation.duration) { [weak self] in
            guard let self, self.generation == token else { return }
            self.animating = false
            completion()
        }
    }
    func prepareHidden() {
        guard let layer = content.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            layer.opacity = 0
        } else {
            layer.transform = CATransform3DMakeTranslation(-clip.bounds.width, 0, 0)
        }
        CATransaction.commit()
    }
}
