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
    }
}

// MARK: - Compose

/// One board for the whole compose step: it shows the live camera, then the photo you took,
/// and once you approve the photo it flips over so you can write on its back.
struct ComposeScreen: View {
    @Bindable var draft: SendDraft
    var onDone: () -> Void

    private enum Stage { case capture, review, write }

    @State private var stage: Stage = .capture
    @State private var camera = CameraModel()
    @State private var pickerItem: PhotosPickerItem?
    @State private var isCapturing = false
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
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    use(image)
                }
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
            if let photo = draft.photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else if let session = camera.session {
                CameraPreview(session: session)
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
            GridOverlay(n: draft.gridSize)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var messageSide: some View {
        MessagePaper(from: "You") { scale in
            MessageText(text: draft.caption, placeholder: Self.placeholder,
                        showsCursor: captionFocused, scale: scale)
                .animation(.snappy, value: draft.caption.count)
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
        .disabled(isCapturing)
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
            camera.isAvailable
                ? "Find a moment worth puzzling over. It becomes a \(draft.gridSize)×\(draft.gridSize) puzzle."
                : "No camera here, so the shutter grabs a sample photo. Or pick one from your library."
        case .review:
            "Looking good? Use it, or try another."
        case .write:
            ""
        }
    }

    // MARK: Actions

    private func shoot() {
        guard camera.isAvailable else { return use(StoryArt.samplePhoto()) }
        isCapturing = true
        Task {
            if let image = await camera.capture() { use(image) }
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

    private func retake() {
        withAnimation(.snappy) {
            draft.photo = nil
            stage = .capture
        }
        Task { await camera.start() }
    }

    /// Flip to the message side. The keyboard opens from `.task(id: stage)` once the flip lands.
    private func approve() {
        withAnimation(.spring(duration: 0.6)) { stage = .write }
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

    private var selectedNames: [String] { model.connections.filter(\.isSelected).map(\.name) }

    private var sendTitle: String {
        switch selectedNames.count {
        case 0: "Choose someone"
        case 1...2: "Send to \(selectedNames.joined(separator: " & "))"
        default: "Send to \(selectedNames.count) people"
        }
    }

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(spacing: 10) {
                preview
                SectionLabel(title: "Who should solve it")

                ForEach($model.connections) { $connection in
                    Button {
                        withAnimation(.snappy) { connection.isSelected.toggle() }
                    } label: {
                        HStack(spacing: 14) {
                            Avatar(name: connection.name, ringed: connection.isSelected)
                            Text(connection.name).font(Theme.display(17))
                            Spacer()
                            Image(systemName: connection.isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 24, weight: .semibold))
                                .opacity(connection.isSelected ? 1 : 0.35)
                        }
                        .foregroundStyle(connection.isSelected ? .white : Theme.ink)
                        .padding(8)
                        .padding(.trailing, 10)
                        .modifier(SelectableRow(selected: connection.isSelected))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(connection.isSelected ? .isSelected : [])
                }
            }
            .padding(20)
        }
        .screenBackground()
        .screenTitle("Send")
        .safeAreaInset(edge: .bottom) {
            Button(sendTitle) {
                model.send(draft)
                onSent()
            }
            .buttonStyle(PrimaryButtonStyle(fullWidth: true))
            .disabled(selectedNames.isEmpty)
            .padding(20)
            .background(Theme.cream)
        }
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
