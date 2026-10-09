//
//  ConnectionsView.swift
//  Sliding
//

import SwiftUI

/// The people you swap postcards with, from the ⋯ menu.
struct ConnectionsView: View {
    @Environment(AppModel.self) private var model
    @State private var isAdding = false
    @State private var newUsername = ""
    /// The connection or request waiting on a "are you sure?".
    @State private var removing: Connection?

    var body: some View {
        List {
            row { inviteCard.padding(.vertical, 8) }

            if !model.incomingRequests.isEmpty {
                row { SectionLabel(title: "Wants to connect") }
                ForEach(model.incomingRequests) { request in
                    row {
                        RequestRow(connection: request,
                                   accept: { Task { await model.accept(request) }
                                             Haptics.shared.tick(intensity: 0.8) },
                                   decline: { removing = request })
                    }
                }
            }

            row { SectionLabel(title: "Your people") }
            ForEach(model.connected) { connection in
                row { ConnectionRow(name: connection.name, stories: model.stories(from: connection.id)) }
                    .swipeActions {
                        // Not destructive-styled: that removes the row before the person confirms.
                        Button("Remove", systemImage: "person.badge.minus") { removing = connection }
                            .tint(.red)
                    }
            }
            if model.connected.isEmpty {
                row {
                    EmptyMessage(title: "No one here yet",
                                 message: "Add someone above. Once they accept, you can swap postcards.")
                }
            }

            if !model.outgoingRequests.isEmpty {
                row { SectionLabel(title: "Waiting to accept") }
                ForEach(model.outgoingRequests) { request in
                    row { PendingRow(connection: request) }
                        .swipeActions {
                            Button("Cancel", systemImage: "xmark") { removing = request }
                                .tint(Theme.ink)
                        }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, 40, for: .scrollContent)
        .screenBackground()
        .screenTitle("Connections")
        .alert("Add someone", isPresented: $isAdding) {
            TextField("Their username", text: $newUsername)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Send request") { Task { await model.requestConnection(username: newUsername) } }
                .disabled(AuthModel.usernameProblem(newUsername.trimmingCharacters(in: CharacterSet(charactersIn: "@ "))) != nil)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("We'll send them a request. Once they accept, you can send each other postcards.")
        }
        // A centered alert: a popover would point at whichever row it anchored to, not the one being removed.
        .alert(removalTitle, isPresented: removalShowing, presenting: removing) { connection in
            Button(removalAction(for: connection), role: .destructive) {
                Task { await model.remove(connection) }
            }
            Button("Keep", role: .cancel) {}
        } message: { connection in
            Text(removalMessage(for: connection))
        }
    }

    /// A clear, full-width list row with the page's spacing.
    private func row(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20))
    }

    // MARK: Confirming removals

    private var removalShowing: Binding<Bool> {
        Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })
    }

    private var removalTitle: String {
        guard let removing else { return "" }
        switch removing.status {
        case .connected: return "Remove \(removing.name)?"
        case .incoming: return "Decline \(removing.name)?"
        case .outgoing: return "Cancel request to \(removing.name)?"
        }
    }

    private func removalAction(for connection: Connection) -> String {
        switch connection.status {
        case .connected: "Remove"
        case .incoming: "Decline"
        case .outgoing: "Cancel request"
        }
    }

    private func removalMessage(for connection: Connection) -> String {
        switch connection.status {
        case .connected: "You won't be able to send each other postcards. Ones you've already swapped stay."
        case .incoming: "They won't be told. They can ask again later."
        case .outgoing: "They won't see your request any more."
        }
    }

    /// Orange, wavy and tilted like the highlighted cards: the way to add someone.
    private var inviteCard: some View {
        Button {
            newUsername = ""
            isAdding = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 50, height: 50)
                    .background(.white.opacity(0.25), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add someone").font(Theme.display(19))
                    Text("Family, friends, the cousin who never calls")
                        .font(Theme.body(14, weight: .medium))
                        .opacity(0.85)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.orange)
                    .frame(width: 32, height: 32)
                    .background(.white, in: Circle())
            }
            .foregroundStyle(.white)
            .padding(16)
            .wavyCard(Theme.orange)
            .floaty(tilt: -1.5, seed: 0.3)
            .shadow(color: Theme.orange.opacity(0.3), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
    }
}

/// One person: their initials, what they've sent you, and their latest photo on the right.
private struct ConnectionRow: View {
    let name: String
    let stories: [Story]

    var body: some View {
        HStack(spacing: 14) {
            Avatar(name: name, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(Theme.display(18)).lineLimit(1)
                Text(summary)
                    .font(Theme.body(14, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            latest
        }
        .foregroundStyle(Theme.ink)
        .padding(7)
        .padding(.trailing, 4)
        .softCard(radius: 38)
        .accessibilityElement(children: .combine)
    }

    private var summary: String {
        guard let newest = stories.first else { return "No postcards yet" }
        let count = stories.count == 1 ? "1 postcard" : "\(stories.count) postcards"
        let when = newest.sentAt.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
        return "\(count) · \(when)"
    }

    /// Their newest postcard as a small round thumbnail; a wave if they haven't sent one.
    @ViewBuilder
    private var latest: some View {
        if let newest = stories.first {
            StoryThumbnail(story: newest, cornerRadius: 22)
                .frame(width: 44, height: 44)
        } else {
            Image(systemName: "hand.wave.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .frame(width: 44, height: 44)
                .background(Theme.paper, in: Circle())
                .accessibilityHidden(true)
        }
    }
}

/// Someone asking to connect: orange and wavy like other things waiting on you, with Accept and Decline.
private struct RequestRow: View {
    let connection: Connection
    var accept: () -> Void
    var decline: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Avatar(name: connection.name, size: 52, ringed: true)
            VStack(alignment: .leading, spacing: 3) {
                Text(connection.name).font(Theme.display(18)).lineLimit(1)
                Text(connection.username.map { "@\($0)" } ?? "Wants to connect")
                    .font(Theme.body(14, weight: .medium))
                    .opacity(0.85)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button(action: decline) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.25), in: Circle())
            }
            .accessibilityLabel("Decline")
            Button(action: accept) {
                Text("Accept")
                    .font(Theme.body(14, weight: .bold))
                    .foregroundStyle(Theme.orange)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(.white, in: Capsule())
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .padding(7)
        .padding(.trailing, 4)
        .wavyCard(Theme.orange, radius: 38)
        .floaty(tilt: -1, seed: Double(connection.name.count % 10) / 10)
        .padding(.vertical, 4)
    }
}

/// A request you sent, waiting on the other person.
private struct PendingRow: View {
    let connection: Connection

    var body: some View {
        HStack(spacing: 14) {
            // A dashed outline where their avatar will be once they accept.
            Image(systemName: "person.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .frame(width: 52, height: 52)
                .overlay(Circle().strokeBorder(Theme.muted.opacity(0.5),
                                               style: StrokeStyle(lineWidth: 2, dash: [4, 4])))
            VStack(alignment: .leading, spacing: 3) {
                Text(connection.name).font(Theme.display(18)).lineLimit(1)
                Text("Request sent")
                    .font(Theme.body(14, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 4)
            Image(systemName: "hourglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .frame(width: 36, height: 36)
                .background(Theme.paper, in: Circle())
        }
        .foregroundStyle(Theme.ink)
        .padding(7)
        .padding(.trailing, 4)
        .softCard(radius: 38)
        .accessibilityElement(children: .combine)
    }
}
