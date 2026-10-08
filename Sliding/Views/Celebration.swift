//
//  Celebration.swift
//  Sliding
//

import Lottie
import SwiftUI

/// Full-screen confetti from `Celebrate.json`, played once.
struct Celebration: View {
    var onFinished: () -> Void = {}

    var body: some View {
        LottieView(animation: .named("Celebrate"))
            .configure { view in view.contentMode = .scaleAspectFill }
            .playbackMode(.playing(.toProgress(1, loopMode: .playOnce)))
            .animationDidFinish { _ in onFinished() }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
