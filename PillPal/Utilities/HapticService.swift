import Foundation
import UIKit
import CoreHaptics

@MainActor
final class HapticService {
    static let shared = HapticService()

    private var engine: CHHapticEngine?
    private let supportsHaptics: Bool

    private init() {
        supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
        if supportsHaptics {
            createAndStartEngine()
        }
    }

    func playConfirm() {
        if supportsHaptics, playConfirmPattern() {
            return
        }

        // Fallback for devices/simulators without Core Haptics.
        let success = UINotificationFeedbackGenerator()
        success.prepare()
        success.notificationOccurred(.success)

        let impact = UIImpactFeedbackGenerator(style: .rigid)
        impact.prepare()
        impact.impactOccurred(intensity: 1.0)
    }

    private func createAndStartEngine() {
        do {
            engine = try CHHapticEngine()
            engine?.isAutoShutdownEnabled = true
            engine?.stoppedHandler = { _ in }
            engine?.resetHandler = { [weak self] in
                Task { @MainActor in
                    do {
                        try self?.engine?.start()
                    } catch {
                        self?.engine = nil
                    }
                }
            }
            try engine?.start()
        } catch {
            engine = nil
        }
    }

    private func playConfirmPattern() -> Bool {
        if engine == nil {
            createAndStartEngine()
        }

        guard let engine else {
            return false
        }

        do {
            let events = [
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.85)
                    ],
                    relativeTime: 0
                ),
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6)
                    ],
                    relativeTime: 0.08
                ),
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.62),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.35)
                    ],
                    relativeTime: 0.16
                )
            ]

            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
            return true
        } catch {
            return false
        }
    }
}
