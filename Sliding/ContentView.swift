//
//  ContentView.swift
//  Sliding
//
//  Created by Shuvam Shrestha on 7/10/2026.
//

import SwiftUI

/// Received is the home screen. Archive and Connections live in the top-right menu,
/// and the floating camera button starts the send flow.
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var path: [Route] = []
    @State private var showConnections = false

    private var toSolve: Int { model.received.filter { !$0.isSolved }.count }

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $path) {
            List {
                Group {
                    summary
                    SectionLabel(title: "Waiting for you")
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))

                ForEach(model.received) { story in
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
                        Button("Archive", systemImage: "archivebox") {
                            withAnimation { story.isArchived = true }
                        }
                        .tint(Theme.ink)
                    }
                }

                if model.received.isEmpty {
                    Group {
                        if model.isLoaded {
                            EmptyMessage(title: "All quiet for now",
                                         message: "When someone sends you a story, it'll show up here, scrambled and waiting.")
                        } else {
                            ProgressView().frame(maxWidth: .infinity).padding(30)
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins(.bottom, 110, for: .scrollContent)
            .safeAreaInset(edge: .top) { header }
            .toolbar(.hidden, for: .navigationBar)
            .screenBackground()
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .archive:
                    ArchiveView()
                case .story(let id):
                    if let story = model.story(id: id) {
                        StoryViewerView(story: story)
                    }
                }
            }
        }
        .task { await model.loadSampleData() }
        .overlay(alignment: .bottom) {
            VStack(spacing: 14) {
                if let toast = model.toast {
                    Label(toast, systemImage: "paperplane.fill")
                        .font(Theme.body(14, weight: .semibold))
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
            .padding(.bottom, 8)
            .animation(.spring, value: model.toast)
            .animation(.spring, value: path.isEmpty)
        }
        .sheet(isPresented: $showConnections) {
            ConnectionsSheet()
                .environment(model)
                .presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: $model.isComposing) {
            SendFlowView()
                .environment(model)
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("Hi there")
                .font(Theme.display(32))
            Spacer()
            Menu {
                Button("Connections", systemImage: "person.2") { showConnections = true }
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

    /// A tilted orange card that opens the next story to solve, and a sand card for the Archive.
    private var summary: some View {
        HStack(spacing: 14) {
            Button {
                if let next = model.nextToSolve { path.append(.story(next.id)) }
            } label: {
                VStack(alignment: .leading) {
                    HStack(alignment: .top) {
                        Image(systemName: toSolve == 0 ? "checkmark" : "puzzlepiece.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .background(.white.opacity(0.25), in: Circle())
                        Spacer()
                        Text("\(toSolve)").font(Theme.display(36))
                    }
                    Spacer()
                    Text(toSolve == 0 ? "ALL SOLVED" : "SOLVE NEXT →")
                        .font(Theme.display(15))
                        .kerning(0.5)
                }
                .foregroundStyle(.white)
                .padding(18)
                .frame(height: 130)
                .wavyCard(Theme.orange)
                .floaty(tilt: -2, seed: 0.2)
            }
            .buttonStyle(.plain)
            .disabled(toSolve == 0)
            .accessibilityLabel(toSolve == 0 ? "All stories solved" : "\(toSolve) to solve. Open the next one.")

            Button {
                path.append(.archive)
            } label: {
                VStack(alignment: .trailing) {
                    HStack(alignment: .top) {
                        Image(systemName: "archivebox.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .background(Theme.paper, in: Circle())
                        Spacer()
                        Text("\(model.archived.count)").font(Theme.display(36))
                    }
                    Spacer()
                    Text("ARCHIVE").font(Theme.display(15)).kerning(0.5).foregroundStyle(Theme.muted)
                }
                .foregroundStyle(Theme.ink)
                .padding(18)
                .frame(height: 118)
                .softCard()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Archive, \(model.archived.count) stories")
        }
        .padding(.vertical, 8)
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
                                withAnimation { story.isArchived = false }
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
        PuzzleBoard(puzzle: story.puzzle, tiles: story.photoTiles, whole: story.photo, cornerRadius: Theme.corner)
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("FROM \(story.from.uppercased())")
                        .font(Theme.display(11))
                        .kerning(0.6)
                        .opacity(0.85)
                    Text(story.isSolved ? story.caption : "Not solved yet")
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

/// People who can send you stories and receive yours.
struct ConnectionsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var isAdding = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(model.connections) { connection in
                        HStack(spacing: 14) {
                            Avatar(name: connection.name)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(connection.name).font(Theme.display(17))
                                Text(summary(for: connection.name))
                                    .font(Theme.body(14))
                                    .foregroundStyle(Theme.muted)
                            }
                            Spacer()
                        }
                        .foregroundStyle(Theme.ink)
                        .padding(8)
                        .padding(.trailing, 10)
                        .softCard(radius: 40)
                        .contextMenu {
                            Button("Remove", systemImage: "trash", role: .destructive) {
                                model.connections.removeAll { $0.id == connection.id }
                            }
                        }
                    }

                    Button("Add connection", systemImage: "person.badge.plus") {
                        newName = ""
                        isAdding = true
                    }
                    .buttonStyle(PrimaryButtonStyle(fullWidth: true))
                    .padding(.top, 8)
                }
                .padding(20)
            }
            .screenBackground()
            .screenTitle("Connections")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Add connection", isPresented: $isAdding) {
                TextField("Name", text: $newName)
                Button("Add") { model.addConnection(named: newName) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("They'll be able to send you stories, and you can send them yours.")
            }
        }
        .tint(Theme.ink)
    }

    private func summary(for name: String) -> String {
        let received = model.stories(from: name)
        guard let latest = received.first else { return "Hasn't sent a story yet" }
        let count = received.count == 1 ? "1 story" : "\(received.count) stories"
        return "\(count) · last \(latest.sentAt.formatted(.relative(presentation: .named)))"
    }
}

#Preview {
    ContentView()
        .environment(AppModel())
}
