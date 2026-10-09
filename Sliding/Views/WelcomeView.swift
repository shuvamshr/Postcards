//
//  WelcomeView.swift
//  Sliding
//

import AuthenticationServices
import SwiftUI

/// First screen for signed-out users: a postcard that shows the whole idea on a loop,
/// then Sign in with Apple.
struct WelcomeView: View {
    @Environment(AuthModel.self) private var auth
    @State private var error: String?
    @State private var signingIn = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)

            DemoPostcard()
                .frame(maxWidth: 290)

            VStack(spacing: 10) {
                Text("Postcards")
                    .font(Theme.display(46))
                Text("Little photo puzzles, sent with love.")
                    .font(Theme.body(17, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 36)

            Spacer(minLength: 24)

            VStack(spacing: 14) {
                if signingIn {
                    HStack(spacing: 12) {
                        TileLoader(size: 26)
                        LoadingMessage(lines: ["Signing you in…", "Fetching your mailbox…"], color: Theme.ink)
                    }
                    .frame(height: 56)
                    .transition(.opacity)
                } else {
                    SignInWithAppleButton(.continue) { request in
                        request.requestedScopes = [.fullName]
                    } onCompletion: { result in
                        // Cancelled or failed: say so straight away. Otherwise wait for the account.
                        guard case .success = result else { return error = auth.handle(result) }
                        signIn { auth.handle(result) }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                if let error {
                    Text(error)
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.orange)
                        .multilineTextAlignment(.center)
                }

                #if DEBUG
                Button("Skip for now (testing only)") { signIn { auth.signInForTesting(); return nil } }
                    .disabled(signingIn)
                    .font(Theme.body(14, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 4)
                #endif
            }
        }
        .foregroundStyle(Theme.ink)
        .animation(.snappy, value: signingIn)
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .background {
            ZStack {
                Theme.cream
                Waves(color: Theme.sand.opacity(0.55), lineWidth: 22)
            }
            .ignoresSafeArea()
        }
    }
}

extension WelcomeView {
    /// Shows the loader while the account is set up, then finishes signing in.
    private func signIn(_ finish: @escaping () -> String?) {
        signingIn = true
        error = nil
        Task {
            await FakeLatency.wait(1.4)
            error = finish()
            signingIn = false
        }
    }
}

/// A postcard that plays the app on a loop: it arrives scrambled, the tiles slide home,
/// and it flips over to show the note on the back.
private struct DemoPostcard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var puzzle = PuzzleState.solved(n: 3)
    @State private var flipped = false

    private let photo = StoryArt.photo(symbol: "sun.horizon.fill", color: Theme.orange)
    private let tiles: [UIImage]
    private let note: String = "Wish you were here!"
    private let from = "Grandma Rose"

    init() {
        tiles = photo.slices(3)
    }

    var body: some View {
        VStack {
            FlipCard(angle: flipped ? 180 : 0) {
                PuzzleBoard(puzzle: puzzle, tiles: tiles, whole: photo, cornerRadius: 18)
            } back: {
                MessagePaper(from: from) { scale in
                    MessageText(text: note, scale: scale)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .padding(10)
            .background(Theme.paper, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(alignment: .topTrailing) { stamp.offset(x: 14, y: -16) }
            .shadow(color: Theme.ink.opacity(0.14), radius: 22, y: 12)
            .floaty(tilt: -3, seed: 0.4)
            .accessibilityHidden(true)
        }
        .task { await play() }
    }

    /// A postage stamp: perforated edge, tilted, with a heart.
    private var stamp: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 50, height: 58)
            .background(Theme.sky, in: RoundedRectangle(cornerRadius: 6))
            .padding(4)
            .background(Theme.paper, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Theme.sand, style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
            )
            .rotationEffect(.degrees(12))
            .shadow(color: Theme.ink.opacity(0.12), radius: 4, y: 2)
    }

    private func play() async {
        if reduceMotion {
            // Still show the idea, without the animation.
            puzzle = PuzzleState.scrambled(n: 3, moves: 12).puzzle
            return
        }
        while !Task.isCancelled {
            let (scrambled, solution) = PuzzleState.scrambled(n: 3, moves: 10)
            withAnimation(.snappy(duration: 0.45)) { puzzle = scrambled }
            try? await Task.sleep(for: .seconds(1.6))

            for position in solution {
                withAnimation(.snappy(duration: 0.22)) { _ = puzzle.move(position) }
                try? await Task.sleep(for: .milliseconds(300))
            }
            try? await Task.sleep(for: .seconds(0.9))

            withAnimation(.spring(duration: 0.7)) { flipped = true }
            try? await Task.sleep(for: .seconds(2.8))

            withAnimation(.spring(duration: 0.7)) { flipped = false }
            try? await Task.sleep(for: .seconds(1.6))
        }
    }
}

/// Right after signing in: sign your postcards. The postcard on top previews your name and stamp.
struct ProfileSetupView: View {
    @Environment(AuthModel.self) private var auth
    @State private var displayName = ""
    @State private var username = ""
    @State private var saving = false
    @FocusState private var focused: Field?

    private enum Field { case name, username }

    private var trimmedName: String { displayName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var usernameProblem: String? { AuthModel.usernameProblem(username) }
    private var canContinue: Bool { !trimmedName.isEmpty && usernameProblem == nil }

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                SignaturePostcard(name: trimmedName)
                    .frame(maxWidth: 200)
                    .padding(.top, 28)

                Text("Sign your postcards")
                    .font(Theme.display(30))

                VStack(spacing: 12) {
                    FieldRow(symbol: "person.fill") {
                        TextField("Your name", text: $displayName)
                            .textContentType(.name)
                            .submitLabel(.next)
                            .focused($focused, equals: .name)
                            .onSubmit { focused = .username }
                    }

                    FieldRow(symbol: "at") {
                        TextField("username", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.username)
                            .submitLabel(.done)
                            .focused($focused, equals: .username)
                            .onSubmit { if canContinue { save() } }
                    }

                    if !username.isEmpty, let usernameProblem {
                        Text(usernameProblem)
                            .font(Theme.body(13, weight: .medium))
                            .foregroundStyle(Theme.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 6)
                            .transition(.opacity)
                    }
                }
                .animation(.snappy, value: usernameProblem)

                Button { save() } label: {
                    if saving {
                        HStack(spacing: 10) {
                            TileLoader(size: 20, colors: [.white, .white.opacity(0.75), .white.opacity(0.5)])
                            Text("Saving @\(username.lowercased())…").lineLimit(1)
                        }
                    } else {
                        Text("Continue")
                    }
                }
                .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                .disabled(!canContinue || saving)
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background {
            ZStack {
                Theme.cream
                Waves(color: Theme.sand.opacity(0.55), lineWidth: 22)
            }
            .ignoresSafeArea()
        }
        .onAppear {
            if displayName.isEmpty { displayName = auth.suggestedName }
            if username.isEmpty { username = Self.suggestedUsername(from: auth.suggestedName) }
            focused = displayName.isEmpty ? .name : nil
        }
    }

    private func save() {
        guard canContinue, !saving else { return }
        saving = true
        focused = nil
        Task {
            await FakeLatency.wait(1.4)
            auth.saveProfile(displayName: trimmedName, username: username)
        }
    }

    /// "Rose Lee" → "roselee".
    private static func suggestedUsername(from name: String) -> String {
        String(name.lowercased().filter { $0.isLetter || $0.isNumber }.prefix(20))
    }
}

/// The back of a postcard, signed with your name as you type, with your initials as the stamp.
private struct SignaturePostcard: View {
    let name: String

    var body: some View {
        MessagePaper(from: name.isEmpty ? "…" : name) { scale in
            MessageText(text: "Hello!", scale: scale)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(10)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Avatar(name: name.isEmpty ? "?" : name, size: 50)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .frame(width: 50, height: 58)
                .background(Theme.accent(for: name.isEmpty ? "?" : name), in: RoundedRectangle(cornerRadius: 6))
                .padding(4)
                .background(Theme.paper, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Theme.sand, style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                )
                .rotationEffect(.degrees(10))
                .shadow(color: Theme.ink.opacity(0.12), radius: 4, y: 2)
                .offset(x: 14, y: -16)
                .animation(.snappy, value: name.isEmpty)
        }
        .shadow(color: Theme.ink.opacity(0.14), radius: 22, y: 12)
        .floaty(tilt: 3, seed: 0.6)
        .accessibilityHidden(true)
    }
}

/// A rounded input row with a small icon on the left.
private struct FieldRow<Field: View>: View {
    let symbol: String
    @ViewBuilder var field: Field

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.muted)
                .frame(width: 34, height: 34)
                .background(Theme.paper, in: Circle())
            field
                .font(Theme.body(18, weight: .semibold))
        }
        .padding(.leading, 10)
        .padding(.trailing, 16)
        .padding(.vertical, 10)
        .softCard(radius: 22)
    }
}
