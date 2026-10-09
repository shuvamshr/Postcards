//
//  Loading.swift
//  Sliding
//

import SwiftUI

/// Pretend network and device delays, so loading states can be seen before there's a backend.
/// Every wait in the app goes through here. Debug builds only: release builds never wait.
/// Remove the calls once real work takes the time instead.
enum FakeLatency {
    #if DEBUG
    static var isEnabled = true
    #else
    static let isEnabled = false
    #endif

    static func wait(_ seconds: Double) async {
        guard isEnabled else { return }
        try? await Task.sleep(for: .seconds(seconds))
    }
}

/// The app's loader: a tiny 2×2 sliding puzzle whose three tiles keep chasing the gap round.
struct TileLoader: View {
    var size: CGFloat = 44
    var colors: [Color] = [Theme.orange, Theme.sky, Theme.yellow]
    /// Where the gap starts, so loaders side by side move out of step.
    var phase = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Slots in clockwise order: top-left, top-right, bottom-right, bottom-left.
    private static let ring = [0, 1, 3, 2]
    /// Which tile sits in each slot (0–3); nil is the gap.
    @State private var slots: [Int?] = [0, 1, 2, nil]

    var body: some View {
        let cell = size / 2
        let gap = max(1.5, size * 0.05)
        ZStack(alignment: .topLeading) {
            ForEach(0..<3, id: \.self) { tile in
                let slot = slots.firstIndex(of: tile) ?? 0
                RoundedRectangle(cornerRadius: cell * 0.3, style: .continuous)
                    .fill(colors[tile % colors.count])
                    .frame(width: cell - gap, height: cell - gap)
                    .offset(x: CGFloat(slot % 2) * cell + gap / 2, y: CGFloat(slot / 2) * cell + gap / 2)
            }
        }
        .frame(width: size, height: size, alignment: .topLeading)
        .accessibilityHidden(true)
        .task {
            for _ in 0..<(phase % 4) { step() }
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(380))
                withAnimation(.snappy(duration: 0.28)) { step() }
            }
        }
    }

    /// Slide the tile just behind the gap (going round clockwise) into it.
    private func step() {
        guard let gap = slots.firstIndex(where: { $0 == nil }),
              let ringIndex = Self.ring.firstIndex(of: gap) else { return }
        let from = Self.ring[(ringIndex + 3) % 4]
        slots[gap] = slots[from]
        slots[from] = nil
    }
}

/// One line of loading copy that changes every so often, with a gentle roll between lines.
struct LoadingMessage: View {
    let lines: [String]
    var color: Color = Theme.muted
    @State private var index = 0

    var body: some View {
        // Both lines share one spot while they swap, so the old one rolls out as the new one rolls in.
        ZStack {
            Text(lines[index % max(lines.count, 1)])
                .font(Theme.body(15, weight: .semibold))
                .foregroundStyle(color)
                .multilineTextAlignment(.center)
                .id(index)
                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                        removal: .move(edge: .top).combined(with: .opacity)))
        }
        .clipped()
        .task {
            guard lines.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.6))
                withAnimation(.spring(duration: 0.4)) { index += 1 }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(lines.first ?? "Loading")
    }
}

/// The loader with its copy underneath, for full areas that are waiting.
struct PlayfulLoader: View {
    let lines: [String]
    var size: CGFloat = 52
    var onDark = false

    var body: some View {
        VStack(spacing: 16) {
            TileLoader(size: size)
                .floaty(tilt: -4, seed: 0.3)
            LoadingMessage(lines: lines, color: onDark ? .white.opacity(0.7) : Theme.muted)
        }
        .accessibilityElement(children: .combine)
    }
}
