import CoreGraphics

/// Blink reminder: two blinks then a fade-out, driven by `update(_:)`. Pure state, no AppKit,
/// so it can be unit tested and reused by `Smiley`'s drawing code without a window.
final class BlinkReminder {
    private enum Phase { case idle, animating, fadingOut }

    private static let halfCycle: CGFloat = 0.35       // ~350ms per half-cycle
    private static let blinkDuration: CGFloat = halfCycle * 4  // two full blinks ≈ 1.4s
    private static let fadeDuration: CGFloat = 0.3

    private var phase: Phase = .idle
    private var t: CGFloat = 0

    var isActive: Bool { phase != .idle }

    /// Starts the animation; a no-op while already animating.
    func fire() {
        guard phase == .idle else { return }
        phase = .animating
        t = 0
    }

    func update(_ dt: CGFloat) {
        guard phase != .idle else { return }
        t += dt
        switch phase {
        case .animating:
            if t >= Self.blinkDuration { phase = .fadingOut; t = 0 }
        case .fadingOut:
            if t >= Self.fadeDuration { phase = .idle; t = 0 }
        case .idle:
            break
        }
    }

    /// 0 = eyes open, 1 = eyes fully closed; cycles closed/open twice during the animation.
    var eyeClosedAmount: CGFloat {
        guard phase == .animating else { return 0 }
        let half = Self.halfCycle
        let cycle = t.truncatingRemainder(dividingBy: half * 2)
        return cycle < half ? cycle / half : 1 - (cycle - half) / half
    }

    /// 1 = fully visible, 0 = fully faded.
    var alpha: CGFloat {
        switch phase {
        case .idle: return 0
        case .animating: return 1
        case .fadingOut: return 1 - min(1, t / Self.fadeDuration)
        }
    }
}
