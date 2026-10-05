import CoreGraphics

/// Owns both reminder timers and state machines, and enforces the "only one animates
/// at a time" rule: if both become due in the same tick, Blink fires first and Look-Away
/// stays pending, firing the instant Blink returns to idle.
final class ReminderScheduler {
    let blink = BlinkReminder()
    let lookAway = LookAwayReminder()

    /// Minutes; 0 disables that reminder.
    var blinkFreqMin: Double = 1
    var lookawayFreqMin: Double = 20

    private var blinkElapsed: CGFloat = 0
    private var lookAwayElapsed: CGFloat = 0
    private var lookAwayPending = false

    var isAnyActive: Bool { blink.isActive || lookAway.isActive }

    func update(_ dt: CGFloat) {
        blink.update(dt)
        lookAway.update(dt)

        if blinkFreqMin > 0 {
            blinkElapsed += dt
            if blinkElapsed >= CGFloat(blinkFreqMin * 60) && !isAnyActive {
                blinkElapsed = 0
                blink.fire()
            }
        }

        if lookawayFreqMin > 0 {
            lookAwayElapsed += dt
            if lookAwayElapsed >= CGFloat(lookawayFreqMin * 60) {
                lookAwayElapsed = 0
                lookAwayPending = true
            }
        }

        if lookAwayPending && !isAnyActive {
            lookAwayPending = false
            lookAway.fire()
        }
    }
}
