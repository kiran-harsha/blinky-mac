import CoreGraphics

/// Look-away (20-20-20) reminder: blur+smiley fade in, four 1s look-direction legs,
/// then fade out. Pure state, no AppKit — same reasoning as `BlinkReminder`.
final class LookAwayReminder {
    enum Direction { case left, right, up, down }
    private enum Phase { case idle, fadingIn, looking, fadingOut }

    private static let fadeInDuration: CGFloat = 0.4
    private static let legDuration: CGFloat = 1.0
    private static let legs: [Direction] = [.left, .right, .up, .down]
    private static let fadeOutDuration: CGFloat = 0.4

    private var phase: Phase = .idle
    private var t: CGFloat = 0
    private var legIndex = 0

    var isActive: Bool { phase != .idle }

    /// Starts the animation; a no-op while already animating.
    func fire() {
        guard phase == .idle else { return }
        phase = .fadingIn
        t = 0
        legIndex = 0
    }

    func update(_ dt: CGFloat) {
        guard phase != .idle else { return }
        t += dt
        switch phase {
        case .fadingIn:
            if t >= Self.fadeInDuration { phase = .looking; t = 0 }
        case .looking:
            if t >= Self.legDuration {
                t = 0
                legIndex += 1
                if legIndex >= Self.legs.count { phase = .fadingOut }
            }
        case .fadingOut:
            if t >= Self.fadeOutDuration { phase = .idle; t = 0 }
        case .idle:
            break
        }
    }

    var currentDirection: Direction? {
        phase == .looking ? Self.legs[legIndex] : nil
    }

    /// Unit amount the pupil should shift toward `currentDirection`; 0 outside the looking phase.
    var lookAmount: CGFloat { phase == .looking ? 1 : 0 }

    /// 1 = fully visible, 0 = fully hidden; shared by the blur backdrop and the smiley.
    var alpha: CGFloat {
        switch phase {
        case .idle: return 0
        case .fadingIn: return min(1, t / Self.fadeInDuration)
        case .looking: return 1
        case .fadingOut: return 1 - min(1, t / Self.fadeOutDuration)
        }
    }
}
