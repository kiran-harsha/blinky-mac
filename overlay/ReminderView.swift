import AppKit

/// Draws the smiley for whichever reminder is currently active. The look-away blur backdrop
/// is a separate `NSVisualEffectView` owned by `App`, layered behind this view.
final class ReminderView: NSView {
    let scheduler = ReminderScheduler()
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let c = NSGraphicsContext.current?.cgContext else { return }
        c.clear(bounds)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        if scheduler.blink.isActive {
            Smiley.draw(c, at: center, eyeClosedAmount: scheduler.blink.eyeClosedAmount, alpha: scheduler.blink.alpha)
        } else if scheduler.lookAway.isActive {
            Smiley.draw(c, at: center, lookDirection: scheduler.lookAway.currentDirection,
                        lookAmount: scheduler.lookAway.lookAmount, alpha: scheduler.lookAway.alpha)
        }
    }
}
