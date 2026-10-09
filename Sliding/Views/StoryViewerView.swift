//
//  StoryViewerView.swift
//  Sliding
//

import SwiftUI

/// Solve a story: the photo on the front, the message on the back, sliding together in a dark tray.
/// Tap tiles to slide them, hold the board to peek at the photo, shake the phone to shuffle.
/// The card stays photo-side up until it's solved; then it spins freely with a swipe.
struct StoryViewerView: View {
    let story: Story
    @Environment(AppModel.self) private var model
    /// The overlay opens on its own the first time someone plays.
    @AppStorage("hasSeenHowToPlay") private var hasSeenHowToPlay = false
    /// The card's turn in degrees: 0 is the photo, 180 the message. Spins keep counting past 360.
    @State private var angle: Double
    /// Where the angle was when the current spin started; nil when not spinning.
    @State private var spinStart: Double?
    /// True while a finger is spinning the card. Resets even if the system cancels the swipe,
    /// which is how a cancelled spin still gets to settle on a face.
    @GestureState private var spinning = false
    /// The latest finger movement, so a cancelled swipe can still finish the spin it started.
    @State private var lastSpin: (translation: CGFloat, predicted: CGFloat) = (0, 0)
    /// The first time a story opens, it shows its scrambled message briefly, then turns to the photo.
    @State private var teasing: Bool
    /// A new story is still coming in: the board shows a loader until it's here.
    @State private var arriving: Bool
    @State private var celebrating = false
    /// Set each time the puzzle is solved; a new value restarts the confetti.
    @State private var confetti: UUID?
    /// Where the finger has moved since touching the board; nil when nothing is touching it.
    /// Gesture state resets even if the gesture is cancelled, so a peek can never get stuck on.
    @GestureState private var press: CGSize?
    /// Set once a finger has stayed still on the board long enough. Lasts until it lifts.
    @State private var held = false
    @State private var holdTimer: Task<Void, Never>?
    /// The lift that ends a peek also reads as a tap on whatever tile is under it; skip that tap.
    /// Cleared on the next touch, so it can't swallow a real tap later.
    @State private var skipTap = false

    /// Hold this long, moving less than this far, to peek. Moving further first is a swipe.
    private static let peekDelay: Duration = .milliseconds(350)
    private static let peekSlop: CGFloat = 8

    /// Card geometry. Inner corners are the outer corner minus the padding, so the board nests inside.
    private static let cardPadding: CGFloat = 12
    private static let cardRadius: CGFloat = 34
    private static let innerRadius = cardRadius - cardPadding
    /// The page is darker than the card so the card still stands out as its own object.
    private static let pageColor = Color(red: 0.06, green: 0.06, blue: 0.065)

    /// Card turn per point dragged: a full-width drag turns it about halfway round.
    private static let spinPerPoint = 0.55
    /// A flick that would have carried the finger this much further flips the card, however short it was.
    private static let flickCarry: CGFloat = 60
    private static let thickness: CGFloat = 10

    init(story: Story) {
        self.story = story
        let tease = story.isNew && !story.isSolved
        _teasing = State(initialValue: tease)
        // The card waits, hidden, until its pieces are cut. Usually that's instant on a second visit.
        _arriving = State(initialValue: tease || story.photoPieces == nil || story.messagePieces == nil)
        _angle = State(initialValue: tease ? 180 : 0)
    }

    /// Whether the message side is facing up.
    private var flipped: Bool { cos(angle * .pi / 180) < 0 }
    private var canPeek: Bool { !flipped && !teasing && !story.isSolved }
    private var peeking: Bool { held && canPeek }
    /// Tiles stay put while peeking or teasing, so a finger can't move one underneath,
    /// and once solved, so swiping only ever turns the card.
    private var tileTap: ((Int) -> Void)? {
        if peeking || teasing || story.isSolved { return nil }
        return { slide($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 16)

            // One dark card, like a post: who sent it, then the puzzle.
            VStack(spacing: Self.cardPadding) {
                sender
                    .padding(.leading, 4)
                    .padding(.trailing, 2)
                    .padding(.vertical, 4)

                Group {
                    if let photo = story.photoPieces, let message = story.messagePieces {
                        FlipCard(angle: angle, thickness: Self.thickness, cornerRadius: Self.innerRadius,
                                 edgeColor: Theme.paper, steady: true) {
                            PuzzleBoard(puzzle: story.puzzle, tiles: photo.tiles, whole: story.photo,
                                        cornerRadius: Self.innerRadius, onTap: tileTap)
                        } back: {
                            PuzzleBoard(puzzle: story.puzzle, tiles: message.tiles, whole: message.image,
                                        cornerRadius: Self.innerRadius, onTap: tileTap)
                        }
                    } else {
                        // Holds the card's size while the pieces are cut.
                        Color.clear.aspectRatio(1, contentMode: .fit)
                    }
                }
                .overlay { peekOverlay }
                .simultaneousGesture(pressGesture)
                .overlay {
                    // Once solved, swipes and taps land on this still layer above the card. The card
                    // redraws as it turns, which would cancel a touch that started on the card itself.
                    if story.isSolved {
                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(spinGesture)
                            .onTapGesture { spin(by: 180) }
                    }
                }
                .accessibilityAction(named: "Flip card") { if story.isSolved { spin(by: 180) } }
            }
            .padding(Self.cardPadding)
            .background(Theme.ink, in: RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous))
            .overlay {
                // A hairline edge separates the card from the dark page.
                RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            }
            // Flattened first, so only the card's outline casts this shadow, not the board turning inside it.
            .compositingGroup()
            .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
            .scaleEffect(celebrating ? 1.03 : (peeking ? 0.985 : 1))
            .animation(.spring(duration: 0.25), value: peeking)
            // While a new story comes in, the whole card stays hidden and the loader holds its place.
            // Then the card pops up into view.
            .opacity(arriving ? 0 : 1)
            .scaleEffect(arriving ? 0.92 : 1)
            .overlay {
                if arriving {
                    PlayfulLoader(lines: ["Unfolding your postcard…", "Shuffling the pieces…"], onDark: true)
                        .transition(.opacity)
                }
            }

            if story.isSent {
                sentStatus
                    .padding(.top, 28)
            } else if story.isSolved {
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
            if !hasSeenHowToPlay && !story.isSent {
                hasSeenHowToPlay = true
                showHowToPlay()
            }
        }
        .task { await arrive() }
        .onDisappear { model.saveProgress() }
        // Sideways swipes turn a solved card, so only the screen's edge swipes back.
        .contentSwipeBackDisabled(story.isSolved)
        .onChange(of: spinning) { _, nowSpinning in
            // Swipe cancelled before it ended: finish it from the last movement seen.
            guard !nowSpinning, spinStart != nil else { return }
            endSpin(translation: lastSpin.translation, predicted: lastSpin.predicted)
        }
        .onChange(of: press != nil) { _, touching in
            if touching { pressBegan() } else { pressEnded() }
        }
        .onChange(of: press) { _, moved in
            // Moved before the peek started: it's a swipe, not a hold.
            guard !held, let moved, hypot(moved.width, moved.height) > Self.peekSlop else { return }
            holdTimer?.cancel()
        }
        .onChange(of: story.isSolved) { _, solved in
            guard solved else { return }
            model.didSolve(story)
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
            Avatar(name: story.senderLabel, size: 36, ringed: true)
            VStack(alignment: .leading, spacing: 1) {
                Text(story.senderLabel).font(Theme.display(17)).lineLimit(1)
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

    /// Tracks a finger on the board. It runs alongside the tiles' own tap and swipe gestures,
    /// so they can't cancel it partway through a peek.
    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($press) { value, state, _ in state = value.translation }
    }

    /// Press and hold the board, then keep holding: a peek lasts until the finger lifts.
    private func pressBegan() {
        skipTap = false
        holdTimer?.cancel()
        guard canPeek else { return }
        holdTimer = Task {
            try? await Task.sleep(for: Self.peekDelay)
            guard !Task.isCancelled, press != nil, canPeek else { return }
            held = true
            skipTap = true
            Haptics.shared.tick(intensity: 0.5)
        }
    }

    private func pressEnded() {
        holdTimer?.cancel()
        holdTimer = nil
        held = false
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

    /// Show the scrambled message for a moment, then turn to the photo to play.
    /// Waits out the screen's slide-in and the how-to-play card, so the tease is actually seen.
    /// Cuts the pieces if they aren't ready, shows the card, then teases a new story's message.
    private func arrive() async {
        if arriving {
            async let pieces: Void = story.prepareAll()
            // A new story is "coming in": the loader shows for a moment even when the pieces are quick.
            async let wait: Void = teasing ? FakeLatency.wait(1.2) : ()
            _ = await (pieces, wait)
            withAnimation(.spring(duration: 0.5, bounce: 0.25)) { arriving = false }
        }
        model.markOpened(story)
        await tease()
    }

    private func tease() async {
        guard teasing else { return }
        try? await Task.sleep(for: .milliseconds(350))
        while model.isShowingHowToPlay {
            try? await Task.sleep(for: .milliseconds(100))
        }
        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled else { return }
        withAnimation(.spring(duration: 0.7, bounce: 0.2)) { angle = 0 }
        try? await Task.sleep(for: .milliseconds(450))
        teasing = false
    }

    /// Swipe left or right to turn a solved card. It follows the finger, then settles on
    /// whichever face is showing more, or flips over on a quick flick.
    private var spinGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .updating($spinning) { _, state, _ in state = true }
            .onChanged { value in
                let start = spinStart ?? angle
                spinStart = start
                lastSpin = (value.translation.width, value.predictedEndTranslation.width)
                var instant = Transaction()
                instant.disablesAnimations = true
                withTransaction(instant) {
                    angle = start + value.translation.width * Self.spinPerPoint
                }
            }
            .onEnded { value in
                endSpin(translation: value.translation.width, predicted: value.predictedEndTranslation.width)
            }
    }

    /// Land on the face that's showing more. A quick flick flips to the other side instead.
    private func endSpin(translation: CGFloat, predicted: CGFloat) {
        guard let start = spinStart else { return }
        spinStart = nil
        // How much further the finger was heading when it let go: big means it was flicked.
        let carry = predicted - translation
        if abs(carry) > Self.flickCarry {
            settle(at: start + (carry > 0 ? 180 : -180))
        } else {
            settle(at: (angle / 180).rounded() * 180)
        }
    }

    private func spin(by degrees: Double) {
        settle(at: (angle / 180).rounded() * 180 + degrees)
    }

    /// Snap to a resting face with a soft spring, and a light tap if it changed sides.
    private func settle(at target: Double) {
        let flips = Int((target / 180).rounded()) != Int((angle / 180).rounded())
        withAnimation(.spring(duration: 0.45, bounce: 0.15)) { angle = target }
        if flips { Haptics.shared.tick(intensity: 0.6) }
    }

    private func showHowToPlay() {
        withAnimation(.easeOut(duration: 0.2)) { model.isShowingHowToPlay = true }
    }

    /// For your own stories: who it went to and who has solved it.
    private var sentStatus: some View {
        HStack(spacing: 12) {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text("Sent to \(story.recipientNames)").font(Theme.display(18)).lineLimit(1)
                Text(story.isSolvedByEveryone
                     ? "Everyone has solved it."
                     : "\(story.solvedBy.count) of \(story.recipients.count) solved so far.")
                    .font(Theme.body(14, weight: .medium))
                    .opacity(0.7)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(14)
    }

    private var unlocked: some View {
        HStack(spacing: 12) {
            Image(systemName: "gift.fill")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.25), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text("Story unlocked!").font(Theme.display(18))
                Text(!flipped ? "Swipe the card to read it."
                     : story.sender.id == story.ownerID ? "Now it's their turn."
                     : "\(story.sender.name) will be glad you saw it.")
                    .lineLimit(2)
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
        guard !skipTap else { return }
        var moved = false
        withAnimation(.snappy(duration: 0.2)) {
            moved = story.puzzle.move(position)
            if moved { story.moves += 1 }
        }
        if moved { Haptics.shared.tick() }
    }
}
