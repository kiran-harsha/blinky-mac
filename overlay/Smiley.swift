import AppKit

/// Draws the smiley: a cream circular face with a black outline, two pink round eyes
/// (open/closed/looking), and a fixed smile. Pure drawing function — all animation state
/// lives in `BlinkReminder`/`LookAwayReminder`.
enum Smiley {
    static let radius: CGFloat = 95

    private static let faceFill = NSColor(red: 0.97, green: 0.93, blue: 0.84, alpha: 1)
    private static let outline = NSColor.black
    private static let eyeColor = NSColor(red: 0.93, green: 0.25, blue: 0.55, alpha: 1)

    /// - eyeClosedAmount: 0 = open, 1 = fully closed (driven by the blink reminder)
    /// - lookDirection/lookAmount: eye offset toward a direction (driven by the look-away reminder)
    static func draw(_ c: CGContext, at center: CGPoint, eyeClosedAmount: CGFloat = 0,
                      lookDirection: LookAwayReminder.Direction? = nil, lookAmount: CGFloat = 0,
                      alpha: CGFloat) {
        c.saveGState()
        c.setAlpha(alpha)
        c.translateBy(x: center.x, y: center.y)

        c.setFillColor(faceFill.cgColor)
        c.setStrokeColor(outline.cgColor)
        c.setLineWidth(5)
        let face = CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)
        c.fillEllipse(in: face)
        c.strokeEllipse(in: face)

        let eyeDX: CGFloat = radius * 0.4, eyeY: CGFloat = radius * 0.25
        for ex in [-eyeDX, eyeDX] {
            drawEye(c, at: CGPoint(x: ex, y: eyeY), closedAmount: eyeClosedAmount,
                    direction: lookDirection, lookAmount: lookAmount)
        }

        c.setStrokeColor(outline.cgColor)
        c.setLineWidth(5)
        c.setLineCap(.round)
        c.beginPath()
        c.move(to: CGPoint(x: -radius * 0.4, y: -radius * 0.25))
        c.addQuadCurve(to: CGPoint(x: radius * 0.4, y: -radius * 0.25), control: CGPoint(x: 0, y: -radius * 0.6))
        c.strokePath()

        c.restoreGState()
    }

    /// A pink circle that shifts for look-away, and for blink slides a face-coloured
    /// "cutter" circle up over itself as it closes — carving the remaining visible pink
    /// down to a thin crescent moon rather than squashing it into a line.
    private static func drawEye(_ c: CGContext, at basePoint: CGPoint, closedAmount: CGFloat,
                                 direction: LookAwayReminder.Direction?, lookAmount: CGFloat) {
        var p = basePoint
        let eyeRadius: CGFloat = radius * 0.18
        let shift = eyeRadius * 0.9 * lookAmount
        switch direction {
        case .left: p.x -= shift
        case .right: p.x += shift
        case .up: p.y += shift
        case .down: p.y -= shift
        case nil: break
        }

        let eyeRect = CGRect(x: p.x - eyeRadius, y: p.y - eyeRadius, width: eyeRadius * 2, height: eyeRadius * 2)

        c.saveGState()
        c.addEllipse(in: eyeRect)
        c.clip()

        c.setFillColor(eyeColor.cgColor)
        c.fillEllipse(in: eyeRect)

        if closedAmount > 0 {
            let cutterRadius = eyeRadius * 1.05
            let openOffset = eyeRadius * 2.4    // far enough away: no overlap, eye looks fully open
            let closedOffset = eyeRadius * 0.5  // close enough: leaves a thin crescent, like a moon
            let yOffset = openOffset + (closedOffset - openOffset) * closedAmount
            c.setFillColor(faceFill.cgColor)
            c.fillEllipse(in: CGRect(x: p.x - cutterRadius, y: p.y - cutterRadius + yOffset,
                                      width: cutterRadius * 2, height: cutterRadius * 2))
        }
        c.restoreGState()
    }
}
