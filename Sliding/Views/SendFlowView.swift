//
//  SendFlowView.swift
//  Sliding
//

import PhotosUI
import SwiftUI

nonisolated enum SendStep: Hashable {
    case recipients
}

/// Compose (camera → preview → write) on one screen, then Send to.
/// Presented full screen from the camera button.
struct SendFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @State private var draft = SendDraft()
    @State private var path: [SendStep] = []

    var body: some View {
        NavigationStack(path: $path) {
            ComposeScreen(draft: draft) { path.append(.recipients) }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", systemImage: "xmark") { dismiss() }
                            .tint(.white)
                    }
                }
                .navigationDestination(for: SendStep.self) { _ in
                    RecipientsScreen(draft: draft) { dismiss() }
                }
        }
        // Compose is black like a camera; Send goes back to the light app style.
        .preferredColorScheme(path.isEmpty ? .dark : .light)
        .tint(Theme.ink)
        // Start with whoever you sent to last time.
        .onAppear { draft = model.newDraft() }
    }
}

// MARK: - Compose

/// One board for the whole compose step: it shows the live camera, then the photo you took,
/// and once you approve the photo it flips over so you can write on its back.
struct ComposeScreen: View {
    @Bindable var draft: SendDraft
    var onDone: () -> Void
    @Environment(AuthModel.self) private var auth

    private enum Stage { case capture, review, write }

    @State private var stage: Stage = .capture
    @State private var camera = CameraModel()
    @Environment(\.openURL) private var openURL
    @State private var pickerItem: PhotosPickerItem?
    @State private var isCapturing = false
    /// A photo is on its way in, from the shutter or the library.
    @State private var developing = false
    /// Where the viewfinder was last tapped to focus; a new id replays the focus square.
    @State private var focusPoint: CGPoint?
    @State private var focusTap = UUID()
    @FocusState private var captionFocused: Bool

    private static let maxLength = 60
    private static let placeholder = "Your story…"
    private static let difficulties: [(name: String, n: Int)] = [("Easy", 2), ("Medium", 3), ("Hard", 4)]

    private var hasCaption: Bool {
        !draft.caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The whole compose screen is black, like a camera app; the message paper stays cream.
    private let background = Color.black
    private let secondaryText = Color.white.opacity(0.6)
    private let raised = Color(white: 0.17)
    private let onRaised = Color.white

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                PuzzleTray(color: Color(white: 0.12)) {
                    FlipCard(angle: stage == .write ? 180 : 0) {
                        photoSide
                    } back: {
                        messageSide
                    }
                }

                if stage == .write {
                    HStack {
                        Text("Say what was happening.")
                        Spacer()
                        Text("\(draft.caption.count)/\(Self.maxLength)").monospacedDigit()
                    }
                    .font(Theme.body(14, weight: .medium))
                    .foregroundStyle(secondaryText)
                    .padding(.horizontal, 6)
                } else {
                    difficultyPicker
                    Text(hint)
                        .font(Theme.body(14))
                        .foregroundStyle(secondaryText)
                        .multilineTextAlignment(.center)
                }
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 20)
            .padding(.top, 4)
        }
        .background(alignment: .bottom) {
            // An invisible single-line field takes the typing; the board shows it in the same
            // centered, shrinking type the recipient will see. It lives outside the board so
            // the flip and resizing never tear it down mid-edit.
            TextField("Message", text: $draft.caption)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .focused($captionFocused)
                .onSubmit { captionFocused = false }
                .tint(.clear)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .allowsHitTesting(false)
        }
        .task(id: stage) {
            // Open the keyboard once the flip to the message side has landed.
            guard stage == .write else { return }
            try? await Task.sleep(for: .milliseconds(650))
            captionFocused = true
        }
        .scrollDismissesKeyboard(.interactively)
        .screenBackground(background)
        .screenTitle(title, color: .white)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            controls
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(background)
        }
        .task { await camera.start() }
        .onDisappear { camera.stop() }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            withAnimation { developing = true }
            Task {
                async let wait: Void = FakeLatency.wait(1.0)
                let data = try? await item.loadTransferable(type: Data.self)
                await wait
                if let data, let image = UIImage(data: data) { usePicked(image) }
                withAnimation { developing = false }
                pickerItem = nil
            }
        }
        .onChange(of: draft.caption) { _, text in
            // One run of text: pasted line breaks are dropped.
            if text.contains(where: \.isNewline) {
                draft.caption = text.filter { !$0.isNewline }
                captionFocused = false
                return
            }
            if text.count > Self.maxLength { draft.caption = String(text.prefix(Self.maxLength)) }
        }
    }

    // MARK: Board faces

    /// Live camera until a photo is taken, then the photo itself.
    private var photoSide: some View {
        ZStack {
            if developing {
                Color(white: 0.12)
                PlayfulLoader(lines: ["Developing your photo…", "Shaking the Polaroid…"], size: 46, onDark: true)
                    .transition(.opacity)
            } else if camera.isStarting && draft.photo == nil {
                Color(white: 0.12)
                PlayfulLoader(lines: ["Warming up the camera…", "Polishing the lens…"], size: 46, onDark: true)
                    .transition(.opacity)
            } else if stage == .review, let original = draft.original {
                // Picked from the library: pinch and drag to choose the square.
                PhotoCropper(image: original, scale: $draft.cropScale, offset: $draft.cropOffset)
            } else if let photo = draft.photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else if let session = camera.session {
                CameraPreview(session: session) { viewPoint, devicePoint in
                    camera.focus(at: devicePoint)
                    focusPoint = viewPoint
                    focusTap = UUID()
                }
                .overlay(alignment: .topLeading) {
                    if let focusPoint {
                        FocusSquare()
                            .id(focusTap)
                            .position(focusPoint)
                    }
                }
            } else if camera.isDenied {
                // Camera access was turned off: only Settings can turn it back on.
                ZStack {
                    Color(white: 0.16)
                    VStack(spacing: 14) {
                        Image(systemName: "video.slash.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                        VStack(spacing: 4) {
                            Text("Camera is off")
                                .font(Theme.display(19))
                                .foregroundStyle(.white)
                            Text("Postcards needs the camera to take your photo.")
                                .font(Theme.body(14, weight: .medium))
                                .foregroundStyle(.white.opacity(0.6))
                                .multilineTextAlignment(.center)
                        }
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                    .padding(24)
                }
            } else {
                // No camera (the Simulator): a dark viewfinder, so a taken photo is clearly different.
                ZStack {
                    Color(white: 0.24)
                    VStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 38, weight: .semibold))
                        Text("No camera here")
                            .font(Theme.body(14, weight: .semibold))
                    }
                    .foregroundStyle(.white.opacity(0.55))
                }
            }
            // The grid waits until there's something to cut, so it never runs through a loader or message.
            if !developing && (draft.photo != nil || camera.isAvailable) {
                GridOverlay(n: draft.gridSize)
                    .allowsHitTesting(false)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var messageSide: some View {
        MessagePaper(from: auth.profile?.displayName ?? "You") { scale in
            MessageText(text: draft.caption, placeholder: Self.placeholder,
                        showsCursor: captionFocused, scale: scale)
                .transaction { $0.animation = nil }   // keystrokes appear instantly
        }
        .overlay(GridOverlay(n: draft.gridSize, color: Theme.sand))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { captionFocused = true }
    }

    private var difficultyPicker: some View {
        HStack(spacing: 8) {
            ForEach(Self.difficulties, id: \.n) { option in
                let selected = draft.gridSize == option.n
                Button {
                    withAnimation(.snappy) { draft.gridSize = option.n }
                } label: {
                    VStack(spacing: 1) {
                        Text(option.name).font(Theme.body(15, weight: .semibold))
                        Text("\(option.n)×\(option.n)").font(Theme.body(12, weight: .medium)).opacity(0.7)
                    }
                    .foregroundStyle(selected ? Theme.ink : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(selected ? .white : raised,
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(option.name), \(option.n) by \(option.n)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    // MARK: Controls

    @ViewBuilder
    private var controls: some View {
        switch stage {
        case .capture:
            HStack {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Choose from library", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(CircleButtonStyle(fill: raised, foreground: onRaised, size: 56))
                Spacer()
                shutterButton
                Spacer()
                Color.clear.frame(width: 56, height: 56)
            }
        case .review:
            HStack(spacing: 12) {
                Button("Retake", systemImage: "arrow.uturn.backward", action: retake)
                    .buttonStyle(PrimaryButtonStyle(fill: raised, foreground: onRaised, fullWidth: true))
                Button("Use photo", systemImage: "checkmark", action: approve)
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true))
            }
        case .write:
            HStack(spacing: 12) {
                Button("Photo", systemImage: "photo") {
                    captionFocused = false
                    withAnimation(.spring(duration: 0.6)) { stage = .review }
                }
                .buttonStyle(PrimaryButtonStyle(fill: raised, foreground: onRaised))
                Button("Next", systemImage: "arrow.right", action: onDone)
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                    .disabled(!hasCaption)
            }
        }
    }

    private var shutterButton: some View {
        Button(action: shoot) {
            Circle()
                .fill(Theme.orange)
                .frame(width: 62, height: 62)
                .padding(6)
                .overlay(Circle().strokeBorder(Theme.orange, lineWidth: 3))
                .shadow(color: Theme.orange.opacity(0.4), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
        .disabled(isCapturing || developing || camera.isStarting || !canShoot)
        .accessibilityLabel("Take photo")
    }

    // MARK: Text

    private var title: String {
        switch stage {
        case .capture: "New story"
        case .review: "Preview"
        case .write: "Write it"
        }
    }

    private var hint: String {
        switch stage {
        case .capture:
            if camera.isStarting { " " }
            else if camera.isAvailable {
                "Find a moment worth puzzling over. It becomes a \(draft.gridSize)×\(draft.gridSize) puzzle."
            } else if camera.isDenied {
                "Turn the camera on in Settings, or pick a photo from your library."
            } else if usesSamplePhoto {
                "No camera here, so the shutter grabs a sample photo. Or pick one from your library."
            } else {
                "No camera here. Pick a photo from your library."
            }
        case .review:
            draft.original == nil
                ? "Looking good? Use it, or try another."
                : "Pinch to zoom and drag to frame it."
        case .write:
            ""
        }
    }

    // MARK: Actions

    /// Where there's no camera (the Simulator), debug builds let the shutter grab a sample photo
    /// so the flow can be tried. Never when access was denied, and never in release builds.
    private var usesSamplePhoto: Bool {
        #if DEBUG
        !camera.isAvailable && !camera.isDenied
        #else
        false
        #endif
    }

    private var canShoot: Bool { camera.isAvailable || usesSamplePhoto }

    private func shoot() {
        guard canShoot else { return }
        isCapturing = true
        withAnimation { developing = true }
        Task {
            async let wait: Void = FakeLatency.wait(0.9)
            let image = camera.isAvailable ? await camera.capture() : StoryArt.samplePhoto()
            await wait
            if let image { use(image) }
            withAnimation { developing = false }
            isCapturing = false
        }
    }

    private func use(_ image: UIImage) {
        withAnimation(.snappy) {
            draft.photo = image.squareCropped()
            stage = .review
        }
        camera.stop()
    }

    /// A library photo: keep the whole thing so the preview can crop it; start centered and filling the frame.
    private func usePicked(_ image: UIImage) {
        draft.original = image.normalized()
        draft.cropScale = 1
        draft.cropOffset = .zero
        use(image)
    }

    private func retake() {
        withAnimation(.snappy) {
            draft.photo = nil
            draft.original = nil
            stage = .capture
        }
        Task { await camera.start() }
    }

    /// Flip to the message side. The keyboard opens from `.task(id: stage)` once the flip lands.
    private func approve() {
        if let original = draft.original {
            draft.photo = original.cropped(scale: draft.cropScale, offset: draft.cropOffset)
        }
        withAnimation(.spring(duration: 0.6)) { stage = .write }
    }
}

/// The square that marks a tap-to-focus point: it lands slightly large, settles, then fades.
private struct FocusSquare: View {
    @State private var settled = false
    @State private var visible = true

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Theme.yellow, lineWidth: 2)
            .frame(width: 76, height: 76)
            .scaleEffect(settled ? 1 : 1.4)
            .opacity(visible ? 1 : 0)
            .allowsHitTesting(false)
            .task {
                withAnimation(.spring(duration: 0.3, bounce: 0.3)) { settled = true }
                try? await Task.sleep(for: .seconds(1.2))
                withAnimation(.easeOut(duration: 0.4)) { visible = false }
            }
    }
}

/// Lines showing how the photo will be cut into tiles.
struct GridOverlay: View {
    let n: Int
    var color: Color = .white.opacity(0.85)

    var body: some View {
        Canvas { context, size in
            var path = Path()
            for i in 1..<n {
                let x = size.width * CGFloat(i) / CGFloat(n)
                let y = size.height * CGFloat(i) / CGFloat(n)
                path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height))
                path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Recipients

struct RecipientsScreen: View {
    let draft: SendDraft
    var onSent: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(AuthModel.self) private var auth
    @State private var sending = false

    private var selectedNames: [String] {
        model.connected.filter { draft.recipientIDs.contains($0.id) }.map(\.name)
    }
    private var recipientCount: Int { selectedNames.count + (draft.includesMe ? 1 : 0) }

    private var sendTitle: String {
        let names = selectedNames + (draft.includesMe ? ["me"] : [])
        return switch names.count {
        case 0: "Choose someone"
        case 1...3: "Send to \(Story.summary(of: names))"
        default: "Send to \(names.count) people"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                preview
                SectionLabel(title: "Who should solve it")

                meRow

                // Only people who've accepted can be sent to.
                ForEach(model.connected) { connection in
                    let selected = draft.recipientIDs.contains(connection.id)
                    Button {
                        withAnimation(.snappy) {
                            if selected { draft.recipientIDs.remove(connection.id) }
                            else { draft.recipientIDs.insert(connection.id) }
                        }
                    } label: {
                        HStack(spacing: 14) {
                            Avatar(name: connection.name, ringed: selected)
                            Text(connection.name).font(Theme.display(17)).lineLimit(1)
                            Spacer()
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 24, weight: .semibold))
                                .opacity(selected ? 1 : 0.35)
                        }
                        .foregroundStyle(selected ? .white : Theme.ink)
                        .padding(8)
                        .padding(.trailing, 10)
                        .modifier(SelectableRow(selected: selected))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(20)
        }
        .screenBackground()
        .screenTitle("Send")
        .overlay {
            if sending {
                SendingOverlay(photo: draft.photo)
                    .transition(.opacity)
            }
        }
        .navigationBarBackButtonHidden(sending)
        .safeAreaInset(edge: .bottom) {
            Button(sendTitle, action: send)
            .buttonStyle(PrimaryButtonStyle(fullWidth: true))
            .disabled(recipientCount == 0 || sending)
            .padding(20)
            .background(Theme.cream)
        }
    }

    private func send() {
        withAnimation(.spring(duration: 0.4)) { sending = true }
        Task {
            if await model.send(draft) {
                onSent()
            } else {
                withAnimation { sending = false }
            }
        }
    }

    /// Send yourself a copy to solve too. Shows up in Received, and in Sent once you've solved it.
    private var meRow: some View {
        let selected = draft.includesMe
        return Button {
            withAnimation(.snappy) { draft.includesMe.toggle() }
        } label: {
            HStack(spacing: 14) {
                // Same bubble you appear as in Sent and Received.
                Avatar(name: "You", ringed: selected)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Me").font(Theme.display(17))
                    Text("Solve it yourself too")
                        .font(Theme.body(13, weight: .medium))
                        .opacity(0.75)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24, weight: .semibold))
                    .opacity(selected ? 1 : 0.35)
            }
            .foregroundStyle(selected ? .white : Theme.ink)
            .padding(8)
            .padding(.trailing, 10)
            .modifier(SelectableRow(selected: selected))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Me, solve it yourself too")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// What's being sent: the photo and the message.
    private var preview: some View {
        HStack(spacing: 14) {
            if let photo = draft.photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(draft.caption)
                    .font(Theme.display(17))
                    .lineLimit(2)
                Text("\(draft.gridSize)×\(draft.gridSize) puzzle · everyone gets their own copy")
                    .font(Theme.body(13, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.ink)
        .padding(10)
        .softCard(Theme.paper)
    }
}

/// Selected recipients turn orange with waves, like highlighted rows elsewhere.
private struct SelectableRow: ViewModifier {
    let selected: Bool

    func body(content: Content) -> some View {
        if selected {
            content.wavyCard(Theme.orange, radius: 38)
        } else {
            content.softCard(radius: 38)
        }
    }
}

/// While a story is sending: the postcard gets stamped, then waits for the post.
private struct SendingOverlay: View {
    let photo: UIImage?
    @State private var stamped = false

    var body: some View {
        ZStack {
            Theme.cream.opacity(0.92).ignoresSafeArea()
            VStack(spacing: 28) {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let photo {
                            Image(uiImage: photo).resizable().scaledToFill()
                        } else {
                            Theme.sand
                        }
                    }
                    .frame(width: 170, height: 170)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(10)
                    .background(Theme.paper, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .shadow(color: Theme.ink.opacity(0.12), radius: 18, y: 10)

                    // The stamp thumps down from above.
                    Image(systemName: "heart.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 52)
                        .background(Theme.orange, in: RoundedRectangle(cornerRadius: 6))
                        .padding(4)
                        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Theme.sand, style: StrokeStyle(lineWidth: 2, dash: [3, 3])))
                        .rotationEffect(.degrees(stamped ? 10 : -20))
                        .scaleEffect(stamped ? 1 : 2.2)
                        .opacity(stamped ? 1 : 0)
                        .offset(x: 14, y: -16)
                }
                .floaty(tilt: -3, seed: 0.5)

                LoadingMessage(lines: ["Licking the stamp…", "Popping it in the post…", "Off it goes!"])
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.spring(duration: 0.35, bounce: 0.45)) { stamped = true }
            Haptics.shared.tick(intensity: 0.8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sending")
    }
}
