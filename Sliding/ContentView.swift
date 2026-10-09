//
//  ContentView.swift
//  Sliding
//
//  Created by Shuvam Shrestha on 7/10/2026.
//

import SwiftUI

/// Home: Received and Sent, switched with the two cards at the top. Archive and Connections
/// live in the top-right menu, and the floating camera button starts the send flow.
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var path: [Route] = []
    @Environment(AuthModel.self) private var auth
    @State private var box: Box = .received

    enum Box { case received, sent }

    private var toSolve: Int { model.received.filter { !$0.isSolved }.count }
    private var stillSolving: Int { model.sent.filter { !$0.isSolvedByEveryone }.count }
    private var shown: [Story] { box == .received ? model.received : model.sent }

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $path) {
            List {
                Group {
                    summary
                    SectionLabel(title: box == .received ? "Waiting for you" : "Sent by you")
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))

                ForEach(shown) { story in
                    ZStack {
                        // Hidden link keeps navigation without the list's disclosure chevron.
                        NavigationLink(value: Route.story(story.id)) { EmptyView() }
                            .opacity(0)
                        StoryCard(story: story)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20))
                    .swipeActions {
                        if !story.isSent {
                            Button("Archive", systemImage: "archivebox") {
                                model.setArchived(story, true)
                            }
                            .tint(Theme.ink)
                        }
                    }
                }

                if shown.isEmpty {
                    Group {
                        if !model.isLoaded {
                            PlayfulLoader(lines: ["Fetching your postcards…", "Shaking the mailbag…",
                                                  "Unsticking the stamps…"], size: 44)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 56)
                        } else if box == .received {
                            EmptyMessage(title: "All quiet for now",
                                         message: "When someone sends you a story, it'll show up here, scrambled and waiting.")
                        } else {
                            EmptyMessage(title: "Nothing sent yet",
                                         message: "Tap the camera to send your first story.")
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable { await model.refresh() }
            .contentMargins(.bottom, 110, for: .scrollContent)
            .safeAreaInset(edge: .top) { header }
            .toolbar(.hidden, for: .navigationBar)
            .screenBackground()
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .archive:
                    ArchiveView()
                case .connections:
                    ConnectionsView()
                case .profile:
                    ProfileView()
                case .story(let id):
                    if let story = model.story(id: id) {
                        StoryViewerView(story: story)
                    }
                }
            }
        }
        // Loads (or reloads) the mailbox for whoever is signed in.
        .task(id: auth.profile?.userID) {
            if let profile = auth.profile { await model.load(as: Person(profile)) }
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 14) {
                if let toast = model.toast {
                    Label(toast, systemImage: "paperplane.fill")
                        .font(Theme.body(14, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(Theme.ink, in: Capsule())
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .task {
                            try? await Task.sleep(for: .seconds(2.5))
                            withAnimation { model.toast = nil }
                        }
                }
                if path.isEmpty {
                    Button("Send a story", systemImage: "camera.fill") { model.isComposing = true }
                        .buttonStyle(CircleButtonStyle(fill: Theme.orange, foreground: .white, size: 70))
                        .shadow(color: Theme.orange.opacity(0.45), radius: 14, y: 6)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
            .animation(.spring, value: model.toast)
            .animation(.spring, value: path.isEmpty)
        }
        .overlay {
            if model.isShowingHowToPlay {
                HowToPlayOverlay {
                    withAnimation(.easeOut(duration: 0.2)) { model.isShowingHowToPlay = false }
                }
                .transition(.opacity)
            }
        }
        .fullScreenCover(isPresented: $model.isComposing) {
            SendFlowView()
                .environment(model)
                .environment(auth)
        }
    }

    /// "Hi Rose", using the first word of your name.
    private var greeting: String {
        guard let first = auth.profile?.displayName.split(separator: " ").first else { return "Hi there" }
        return "Hi \(first)"
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text(greeting)
                .font(Theme.display(32))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .layoutPriority(1)
            Spacer()
            Menu {
                Button("Profile", systemImage: "person.crop.circle") { path.append(.profile) }
                Button("Connections", systemImage: "person.2") { path.append(.connections) }
                Button("Archive", systemImage: "archivebox") { path.append(.archive) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 46, height: 46)
                    .softCard(Theme.paper, radius: 16)
            }
            .accessibilityLabel("More")
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(Theme.cream)
    }

    /// Received and Sent. The one showing is orange, tilted and floating; the other sits on sand.
    private var summary: some View {
        HStack(spacing: 14) {
            BoxCard(title: "Received", symbol: "tray.fill", count: model.isLoaded ? model.received.count : nil,
                    detail: !model.isLoaded ? "Loading…" : toSolve == 0 ? "All solved" : "\(toSolve) to solve",
                    selected: box == .received, tilt: -2) { select(.received) }
            BoxCard(title: "Sent", symbol: "paperplane.fill", count: model.isLoaded ? model.sent.count : nil,
                    detail: !model.isLoaded ? "Loading…" : stillSolving == 0 ? "All solved" : "\(stillSolving) being solved",
                    selected: box == .sent, tilt: 2) { select(.sent) }
        }
        .padding(.vertical, 8)
    }

    private func select(_ new: Box) {
        guard new != box else { return }
        Haptics.shared.tick(intensity: 0.6)
        withAnimation(.spring(duration: 0.4, bounce: 0.3)) { box = new }
    }
}

/// One of the two cards on home. Selected: orange with waves, tilted and floating.
private struct BoxCard: View {
    let title: String
    let symbol: String
    /// Nil while loading.
    let count: Int?
    let detail: String
    let selected: Bool
    let tilt: Double
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top) {
                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(selected ? .white.opacity(0.25) : Theme.paper, in: Circle())
                    Spacer()
                    Text(count.map { "\($0)" } ?? "–")
                        .font(Theme.display(36))
                        .fixedSize()
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 8)
                Text(title.uppercased())
                    .font(Theme.display(15))
                    .kerning(0.5)
                Text(detail)
                    .font(Theme.body(13, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(selected ? .white.opacity(0.85) : Theme.muted)
            }
            .foregroundStyle(selected ? .white : Theme.ink)
            .padding(18)
            .frame(height: selected ? 136 : 124)
            .modifier(BoxBackground(selected: selected, tilt: tilt))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(count.map { "\($0)" } ?? ""). \(detail)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct BoxBackground: ViewModifier {
    let selected: Bool
    let tilt: Double

    func body(content: Content) -> some View {
        if selected {
            content.wavyCard(Theme.orange)
                .floaty(tilt: tilt, seed: tilt < 0 ? 0.2 : 0.7)
                .shadow(color: Theme.orange.opacity(0.3), radius: 12, y: 6)
        } else {
            content.softCard()
        }
    }
}

/// "Your stories:" style label above a list.
struct SectionLabel: View {
    let title: String

    var body: some View {
        Text("\(title):")
            .font(Theme.body(17, weight: .semibold))
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }
}

struct EmptyMessage: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(Theme.display(19)).foregroundStyle(Theme.ink)
            Text(message).font(Theme.body(15)).foregroundStyle(Theme.muted)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(24)
        .softCard()
    }
}

/// Archived stories as a two-column gallery of photo cards.
struct ArchiveView: View {
    @Environment(AppModel.self) private var model
    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ScrollView {
            if model.archived.isEmpty {
                EmptyMessage(title: "Nothing saved yet",
                             message: "Swipe left on a story in Received to keep it here.")
                    .padding(20)
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(Array(model.archived.enumerated()), id: \.element.id) { index, story in
                        NavigationLink(value: Route.story(story.id)) {
                            ArchiveCard(story: story)
                                .floaty(tilt: index.isMultiple(of: 2) ? -1 : 1,
                                        seed: Double(index % 5) / 5)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Move to Received", systemImage: "tray.and.arrow.up") {
                                model.setArchived(story, false)
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .screenBackground()
        .screenTitle("Archive")
    }
}

private struct ArchiveCard: View {
    let story: Story

    var body: some View {
        StoryThumbnail(story: story, cornerRadius: Theme.corner)
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("FROM \(story.senderLabel.uppercased())")
                        .font(Theme.display(11))
                        .lineLimit(1)
                        .kerning(0.6)
                        .opacity(0.85)
                    Text(story.isSolved ? (story.caption.isEmpty ? "Solved" : story.caption) : "Not solved yet")
                        .font(Theme.display(17))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .foregroundStyle(.white)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(alignment: .bottom) {
                    LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
                }
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: Theme.corner, bottomTrailingRadius: Theme.corner,
                                                  style: .continuous))
            }
            .accessibilityElement(children: .combine)
    }
}

#Preview {
    ContentView()
        .environment(AppModel())
}
