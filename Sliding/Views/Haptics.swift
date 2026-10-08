//
//  Haptics.swift
//  Sliding
//

import CoreHaptics
import UIKit

/// Game haptics: a short tick per tile move, a rattle on shuffle, and a longer rising pattern on a win.
final class Haptics {
    static let shared = Haptics()

    private let tickGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private var engine: CHHapticEngine?

    private init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        engine = try? CHHapticEngine()
        engine?.isAutoShutdownEnabled = true
        engine?.resetHandler = { [weak self] in try? self?.engine?.start() }
    }

    /// One short, crisp tap.
    func tick(intensity: CGFloat = 0.7) {
        tickGenerator.impactOccurred(intensity: intensity)
    }

    /// A win: quick taps that build up, a warm buzz, then three small sparkles.
    func celebrate() {
        play(try? Self.winPattern()) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    /// A shuffle: an uneven rattle, like tiles tumbling, that settles with one firm thud.
    func shuffle() {
        play(try? Self.shufflePattern()) { [tickGenerator] in
            Task { @MainActor in
                for intensity in [0.5, 0.8, 0.4, 0.9, 0.5, 0.7] as [CGFloat] {
                    tickGenerator.impactOccurred(intensity: intensity)
                    try? await Task.sleep(for: .milliseconds(55))
                }
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            }
        }
    }

    /// Plays a Core Haptics pattern, or the fallback where Core Haptics isn't available.
    private func play(_ pattern: CHHapticPattern?, fallback: () -> Void) {
        guard let engine, let pattern else { return fallback() }
        do {
            try engine.start()
            try engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
        } catch {
            fallback()
        }
    }

    private static func shufflePattern() throws -> CHHapticPattern {
        // Slightly irregular timing and strength reads as a rattle rather than a beat.
        let rattle: [(TimeInterval, Float, Float)] = [
            (0.00, 0.55, 0.8), (0.05, 0.85, 0.6), (0.11, 0.45, 0.9), (0.16, 0.9, 0.5),
            (0.22, 0.5, 0.85), (0.27, 0.75, 0.6), (0.33, 0.4, 0.9),
        ]
        var events = rattle.map { time, intensity, sharpness in
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ], relativeTime: time)
        }
        // The tiles land.
        events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2),
        ], relativeTime: 0.45))
        return try CHHapticPattern(events: events, parameters: [])
    }

    private static func winPattern() throws -> CHHapticPattern {
        func tap(_ time: TimeInterval, _ intensity: Float, _ sharpness: Float) -> CHHapticEvent {
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ], relativeTime: time)
        }

        var events: [CHHapticEvent] = []
        // Build-up: five taps getting stronger.
        for (i, time) in [0.0, 0.09, 0.18, 0.27, 0.36].enumerated() {
            events.append(tap(time, 0.4 + Float(i) * 0.15, 0.5))
        }
        // A warm buzz that fades out.
        events.append(CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.25),
        ], relativeTime: 0.48, duration: 0.45))
        // Sparkles.
        events += [tap(1.05, 0.6, 0.9), tap(1.2, 0.5, 0.9), tap(1.35, 0.4, 0.9)]

        let fade = CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [
            .init(relativeTime: 0.48, value: 1),
            .init(relativeTime: 0.93, value: 0.1),
        ], relativeTime: 0)
        return try CHHapticPattern(events: events, parameterCurves: [fade])
    }
}
