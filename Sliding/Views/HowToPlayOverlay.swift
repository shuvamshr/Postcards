//
//  HowToPlayOverlay.swift
//  Sliding
//

import SwiftUI

/// A playful how-to-play card over a soft dim. Tap anywhere to close it.
struct HowToPlayOverlay: View {
    var onDismiss: () -> Void
    @State private var shown = false
    /// How many steps have slid in so far; they arrive one after another after the card pops up.
    @State private var revealed = 0

    private let steps: [(symbol: String, color: Color, title: String, detail: String)] = [
        ("hand.tap.fill", Theme.sky, "Tap to slide", "Tap a tile next to the gap."),
        ("eye.fill", Theme.purple, "Hold to peek", "Hold the board to see the photo."),
        ("iphone.gen3.radiowaves.left.and.right", Theme.yellow, "Shake to shuffle", "Mixed up? Start over."),
    ]

    var body: some View {
        ZStack {
            Theme.ink.opacity(shown ? 0.4 : 0)
                .ignoresSafeArea()

            card
                .padding(.horizontal, 24)
                .scaleEffect(shown ? 1 : 0.88)
                .opacity(shown ? 1 : 0)
                .floaty(tilt: -1, seed: 0.35)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: close)
        .task {
            withAnimation(.spring(duration: 0.45, bounce: 0.35)) { shown = true }
            try? await Task.sleep(for: .milliseconds(180))
            for _ in steps {
                withAnimation(.spring(duration: 0.4, bounce: 0.3)) { revealed += 1 }
                try? await Task.sleep(for: .milliseconds(70))
            }
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(named: "Close", close)
    }

    private var card: some View {
        VStack(spacing: 0) {
            header

            VStack(alignment: .leading, spacing: 20) {
                ForEach(Array(steps.enumerated()), id: \.element.title) { index, step in
                    HStack(spacing: 14) {
                        Image(systemName: step.symbol)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 46, height: 46)
                            .background(step.color, in: Circle())
                            .rotationEffect(.degrees(index.isMultiple(of: 2) ? -6 : 6))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(step.title).font(Theme.display(17))
                            Text(step.detail)
                                .font(Theme.body(14))
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer(minLength: 0)
                    }
                    .opacity(index < revealed ? 1 : 0)
                    .offset(x: index < revealed ? 0 : 24)
                }

                Button("Let's play", action: close)
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                    .padding(.top, 10)
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 22)
            .padding(.vertical, 24)
        }
        .background(Theme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(color: Theme.ink.opacity(0.25), radius: 24, y: 12)
    }

    /// Orange and wavy like the highlighted cards, with a tilted "?" sticker.
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("How to play").font(Theme.display(26))
                Text("Three ways to crack a story")
                    .font(Theme.body(14, weight: .medium))
                    .opacity(0.85)
            }
            Spacer()
            Text("?")
                .font(Theme.display(28))
                .foregroundStyle(Theme.orange)
                .frame(width: 52, height: 52)
                .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .rotationEffect(.degrees(shown ? 10 : -20))
                .shadow(color: Theme.ink.opacity(0.15), radius: 6, y: 3)
                .animation(.spring(duration: 0.6, bounce: 0.5).delay(0.15), value: shown)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 22)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .wavyCard(Theme.orange, radius: 0)
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.18)) { shown = false }
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            onDismiss()
        }
    }
}
