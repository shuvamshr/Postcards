//
//  StoryViewerView.swift
//  Sliding
//

import SwiftUI

/// Solve a story: the photo on the front, the message on the back, sliding together in a dark tray.
/// Tap tiles to slide them, hold the board to peek at the photo, shake the phone to shuffle.
struct StoryViewerView: View {
    let story: Story
    @Environment(AppModel.self) private var model
    /// The overlay opens on its own the first time someone plays.
    @AppStorage("hasSeenHowToPlay") private var hasSeenHowToPlay = false
    @State private var face = 0   // 0 photo, 1 message
    @State private var celebrating = false
    /// Set each time the puzzle is solved; a new value restarts the confetti.
    @State private var confetti: UUID?
    /// True while a finger is held on the board long enough to count as a peek.
    @GestureState private var holding = false
    /// Lifting a finger after a peek can also register as a tap; ignore that one.
    @State private var ignoreNextTap = false

    /// Card geometry. Inner corners are the outer corner minus the padding, so everything nests:
    /// the board, and the switch's rounded ends (its height is twice the inner radius).
    private static let cardPadding: CGFloat = 12
    private static let cardRadius: CGFloat = 34
    private static let innerRadius = cardRadius - cardPadding
    /// The page is darker than the card so the card still stands out as its own object.
    private static let pageColor = Color(red: 0.06, green: 0.06, blue: 0.065)

    private var flipped: Bool { face == 1 }
    private var canPeek: Bool { !flipped && !story.isSolved }
    private var peeking: Bool { holding && canPeek }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 16)

            // One dark card, like a post: who sent it, the puzzle, and the Photo / Message switch.
            VStack(spacing: Self.cardPadding) {
                sender
                    .padding(.leading, 4)
                    .padding(.trailing, 2)
                    .padding(.vertical, 4)

                FlipCard(angle: flipped ? 180 : 0) {
                    PuzzleBoard(puzzle: story.puzzle, tiles: story.photoTiles, whole: story.photo,
                                cornerRadius: Self.innerRadius, onTap: slide)
                } back: {
                    PuzzleBoard(puzzle: story.puzzle, tiles: story.messageTiles, whole: story.message,
                                cornerRadius: Self.innerRadius, onTap: slide)
                }
                .overlay { peekOverlay }
                .simultaneousGesture(peekGesture, isEnabled: canPeek)

                SegmentedSwitch(options: ["Photo", "Message"], selection: $face, onDark: true)
                    .frame(height: Self.innerRadius * 2)
                    .animation(.spring(duration: 0.6), value: face)
            }
            .padding(Self.cardPadding)
            .background(Theme.ink, in: RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous))
            .overlay {
                // A hairline edge separates the card from the dark page.
                RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
            .scaleEffect(celebrating ? 1.03 : (peeking ? 0.985 : 1))
            .animation(.spring(duration: 0.25), value: peeking)

            if story.isSolved {
                unlocked
                    .padding(.top, 28)
            }

            Spacer(minLength: 24)
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 22)
        .padding(.bottom, 16)
        .animation(.spring, value: story.isSolved)
        .overlay {
            if let confetti {
                Celebration { self.confetti = nil }
                    .id(confetti)
            }
        }
        .background {
            ZStack {
                Self.pageColor
                Waves(color: .white.opacity(0.035), lineWidth: 26)
            }
            .ignoresSafeArea()
        }
        // Dark page: switch the app's chrome (status bar, back button) to dark while it's showing.
        .onAppear { model.isOnDarkPage = true }
        .onDisappear { model.isOnDarkPage = false }
        // The card shows who sent it, so the bar only holds back and help.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // Same Liquid Glass circle as the back button.
                Button("How to play", systemImage: "questionmark") { showHowToPlay() }
                    .labelStyle(.iconOnly)
                    .tint(.white)
            }
        }
        .onAppear {
            story.isNew = false
            if !hasSeenHowToPlay {
                hasSeenHowToPlay = true
                showHowToPlay()
            }
        }
        .onChange(of: holding) { _, nowHolding in
            if nowHolding {
                ignoreNextTap = true
                if canPeek { Haptics.shared.tick(intensity: 0.5) }
            } else {
                Task {
                    try? await Task.sleep(for: .milliseconds(250))
                    ignoreNextTap = false
                }
            }
        }
        .onChange(of: story.isSolved) { _, solved in
            guard solved else { return }
            confetti = UUID()
            Haptics.shared.celebrate()
            // A small bounce as the last piece drops in.
            withAnimation(.spring(duration: 0.3, bounce: 0.5)) { celebrating = true }
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                withAnimation(.spring(duration: 0.4)) { celebrating = false }
            }
        }
        .onShake { reshuffle() }
    }

    /// The post header: avatar, name and when it was sent, with the puzzle size on the right.
    private var sender: some View {
        HStack(spacing: 12) {
            Avatar(name: story.from, size: 36, ringed: true)
            VStack(alignment: .leading, spacing: 1) {
                Text(story.from).font(Theme.display(17))
                Text(story.sentAt, format: .relative(presentation: .named))
                    .font(Theme.body(13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 0)
            Text("\(story.n)×\(story.n)")
                .font(Theme.body(13, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.white.opacity(0.12), in: Capsule())
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
    }

    /// Press and hold the board, then keep holding: a peek lasts until the finger lifts.
    private var peekGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.35, maximumDistance: 20)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .updating($holding) { value, state, _ in
                if case .second(true, _) = value { state = true }
            }
    }

    /// The finished photo, shown while the board is held. Photo side only.
    private var peekOverlay: some View {
        Image(uiImage: story.photo)
            .resizable()
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Self.innerRadius, style: .continuous))
            .overlay(alignment: .top) {
                Label("Peeking", systemImage: "eye.fill")
                    .font(Theme.body(13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.45), in: Capsule())
                    .padding(12)
            }
            .opacity(peeking ? 1 : 0)
            .animation(.easeOut(duration: 0.15), value: peeking)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func showHowToPlay() {
        withAnimation(.easeOut(duration: 0.2)) { model.isShowingHowToPlay = true }
    }

    private var unlocked: some View {
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

    private func reshuffle() {
        withAnimation(.snappy) {
            story.puzzle.shuffle()
            story.moves = 0
        }
        Haptics.shared.shuffle()
    }

    private func slide(_ position: Int) {
        if ignoreNextTap {
            ignoreNextTap = false
            return
        }
        var moved = false
        withAnimation(.snappy(duration: 0.2)) {
            moved = story.puzzle.move(position)
            if moved { story.moves += 1 }
        }
        if moved { Haptics.shared.tick() }
    }
}
