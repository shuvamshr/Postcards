//
//  StoryViewerView.swift
//  Sliding
//

import SwiftUI

/// Solve a story: the photo on the front, the message on the back, sliding together in a dark tray.
struct StoryViewerView: View {
    let story: Story
    @State private var face = 0   // 0 photo, 1 message
    @State private var peeking = false
    @State private var celebrating = false
    /// Set each time the puzzle is solved; a new value restarts the confetti.
    @State private var confetti: UUID?

    private var flipped: Bool { face == 1 }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                sender

                PuzzleTray {
                    FlipCard(angle: flipped ? 180 : 0) {
                        PuzzleBoard(puzzle: story.puzzle, tiles: story.photoTiles, whole: story.photo,
                                    cornerRadius: 26, onTap: slide)
                    } back: {
                        PuzzleBoard(puzzle: story.puzzle, tiles: story.messageTiles, whole: story.message,
                                    cornerRadius: 26, onTap: slide)
                    }
                    .overlay { peekOverlay }
                }
                .scaleEffect(celebrating ? 1.03 : 1)

                SegmentedSwitch(options: ["Photo", "Message"], selection: $face)
                    .animation(.spring(duration: 0.6), value: face)

                if story.isSolved {
                    unlocked
                } else {
                    playControls
                }
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .animation(.spring, value: story.isSolved)
        }
        .overlay {
            if let confetti {
                Celebration { self.confetti = nil }
                    .id(confetti)
            }
        }
        .screenBackground()
        // The sender header carries the title, so the bar only holds the back button.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { story.isNew = false }
        .sensoryFeedback(.selection, trigger: story.moves)
        .sensoryFeedback(.success, trigger: story.isSolved) { _, solved in solved }
        .onChange(of: story.isSolved) { _, solved in
            guard solved else { return }
            confetti = UUID()
            // A small bounce as the last piece drops in.
            withAnimation(.spring(duration: 0.3, bounce: 0.5)) { celebrating = true }
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                withAnimation(.spring(duration: 0.4)) { celebrating = false }
            }
        }
    }

    private var sender: some View {
        HStack(spacing: 12) {
            Avatar(name: story.from, size: 46)
            VStack(alignment: .leading, spacing: 1) {
                Text(story.from).font(Theme.display(20))
                Text("\(story.sentAt, format: .relative(presentation: .named)) · \(story.n)×\(story.n) puzzle")
                    .font(Theme.body(14, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
        }
    }

    /// The finished picture (or message), shown while "Hold to peek" is pressed.
    private var peekOverlay: some View {
        Image(uiImage: flipped ? story.message : story.photo)
            .resizable()
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .opacity(peeking && !story.isSolved ? 1 : 0)
            .animation(.easeOut(duration: 0.15), value: peeking)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var playControls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Label("Hold to peek", systemImage: peeking ? "eye.fill" : "eye")
                    .font(Theme.body(16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(peeking ? Theme.ink : Theme.sand,
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .foregroundStyle(peeking ? .white : Theme.ink)
                    .onLongPressGesture(minimumDuration: 0, maximumDistance: 60) {
                    } onPressingChanged: { pressing in
                        peeking = pressing
                    }
                    .sensoryFeedback(.impact(weight: .light), trigger: peeking) { _, now in now }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Shows the finished picture while you hold it.")

                Button("Reshuffle", systemImage: "shuffle") { reshuffle() }
                    .buttonStyle(CircleButtonStyle(size: 54))
            }

            Text("Tap a tile next to the gap to slide it. Stuck? Peek, or switch to Message. The words can help.")
                .font(Theme.body(14))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
        }
    }

    private var unlocked: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "gift.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.25), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text("Story unlocked!").font(Theme.display(18))
                    Text(flipped ? "\(story.from) will be glad you saw it." : "Switch to Message to read it.")
                        .font(Theme.body(14, weight: .medium))
                        .opacity(0.85)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(14)
            .wavyCard(Theme.orange)
            .floaty(tilt: -1, seed: 0.6)
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
    }

    private func reshuffle() {
        withAnimation(.snappy) {
            story.puzzle.shuffle()
            story.moves = 0
        }
    }

    private func slide(_ position: Int) {
        withAnimation(.snappy(duration: 0.2)) {
            if story.puzzle.move(position) { story.moves += 1 }
        }
    }
}
