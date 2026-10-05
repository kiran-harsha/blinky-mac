import AppKit

/// Draws the smiley: a circular face, two eyes (open/closed/looking), and a fixed smile.
/// Pure drawing function — all animation state lives in `BlinkReminder`/`LookAwayReminder`.
enum Smiley {
    static let radius: CGFloat = 70

    private static let faceFill = NSColor(red: 1, green: 0.84, blue: 0.2, alpha: 1)
    private static let ink = NSColor(red: 0.6, green: 0.45, blue: 0.05, alpha: 1)
    private static let pupilColor = NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)

    /// - eyeClosedAmount: 0 = open, 1 = fully closed (driven by the blink reminder)
    /// - lookDirection/lookAmount: pupil offset toward a direction (driven by the look-away reminder)
    static func draw(_ c: CGContext, at center: CGPoint, eyeClosedAmount: CGFloat = 0,
                      lookDirection: LookAwayReminder.Direction? = nil, lookAmount: CGFloat = 0,
                      alpha: CGFloat) {
        c.saveGState()
        c.setAlpha(alpha)
        c.translateBy(x: center.x, y: center.y)

        c.setFillColor(faceFill.cgColor)
        c.setStrokeColor(ink.cgColor)
        c.setLineWidth(3)
        let face = CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)
        c.fillEllipse(in: face)
        c.strokeEllipse(in: face)

        let eyeDX: CGFloat = radius * 0.4, eyeY: CGFloat = radius * 0.25
        for ex in [-eyeDX, eyeDX] {
            drawEye(c, at: CGPoint(x: ex, y: eyeY), closedAmount: eyeClosedAmount,
                    direction: lookDirection, lookAmount: lookAmount)
        }

        c.setStrokeColor(ink.cgColor)
        c.setLineWidth(4)
        c.setLineCap(.round)
        c.beginPath()
        c.move(to: CGPoint(x: -radius * 0.4, y: -radius * 0.25))
        c.addQuadCurve(to: CGPoint(x: radius * 0.4, y: -radius * 0.25), control: CGPoint(x: 0, y: -radius * 0.6))
        c.strokePath()

        c.restoreGState()
    }

    private static func drawEye(_ c: CGContext, at p: CGPoint, closedAmount: CGFloat,
                                 direction: LookAwayReminder.Direction?, lookAmount: CGFloat) {
        let eyeW: CGFloat = radius * 0.3
        // Switch to a closed eyelid line well before the eye is geometrically flat, so the
        // closed state is visible for several frames instead of 1-2 at ~30fps.
        if closedAmount > 0.85 {
            c.setStrokeColor(NSColor(red: 0.3, green: 0.2, blue: 0.05, alpha: 1).cgColor)
            c.setLineWidth(3)
            c.setLineCap(.round)
            c.beginPath()
            c.move(to: CGPoint(x: p.x - eyeW / 2, y: p.y))
            c.addLine(to: CGPoint(x: p.x + eyeW / 2, y: p.y))
            c.strokePath()
            return
        }
        let eyeH = eyeW * (1 - closedAmount)
        let eyeRect = CGRect(x: p.x - eyeW / 2, y: p.y - eyeH / 2, width: eyeW, height: eyeH)
        c.setFillColor(NSColor.white.cgColor)
        c.fillEllipse(in: eyeRect)

        // Clip the pupil to the (shrinking) white of the eye so it shrinks with the eyelid
        // instead of staying full-size and overhanging the sclera.
        c.saveGState()
        c.addEllipse(in: eyeRect)
        c.clip()

        var pupil = p
        let shift = radius * 0.1 * lookAmount
        switch direction {
        case .left: pupil.x -= shift
        case .right: pupil.x += shift
        case .up: pupil.y += shift
        case .down: pupil.y -= shift
        case nil: break
        }
        c.setFillColor(pupilColor.cgColor)
        let pupilSize = eyeW * 0.5
        c.fillEllipse(in: CGRect(x: pupil.x - pupilSize / 2, y: pupil.y - pupilSize / 2,
                                  width: pupilSize, height: pupilSize))
        c.restoreGState()
    }
}
