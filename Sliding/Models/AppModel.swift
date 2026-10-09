//
//  AppModel.swift
//  Sliding
//

import SwiftUI

/// App-wide state for whoever is signed in. Stories and connections come from a `PostcardService`;
/// today that's `LocalPostcardService` on this device, later a server. Screens only talk to this.
@Observable
final class AppModel {
    private(set) var stories: [Story] = []
    private(set) var connections: [Connection] = []
    /// Who's signed in. Everything is matched by their ID.
    private(set) var me: Person?
    var toast: String?
    /// Whether the send flow is showing.
    var isComposing = false
    /// Whether a dark page (the puzzle) is showing, so the app switches its chrome to dark.
    var isOnDarkPage = false
    /// Whether the how-to-play overlay is showing. Drawn at the app root so it covers the toolbar too.
    var isShowingHowToPlay = false
    private(set) var isLoaded = false
    /// Who you sent to last time, so the next postcard starts with them picked.
    private(set) var lastRecipientIDs: Set<String> = []
    private(set) var lastIncludedMe = false

    @ObservationIgnored private let service: any PostcardService

    init(service: any PostcardService = LocalPostcardService()) {
        self.service = service
    }

    var received: [Story] { stories.filter { !$0.isSent && !$0.isArchived }.sorted { $0.sentAt > $1.sentAt } }
    var sent: [Story] { stories.filter(\.isSent).sorted { $0.sentAt > $1.sentAt } }
    var archived: [Story] { stories.filter { !$0.isSent && $0.isArchived }.sorted { $0.sentAt > $1.sentAt } }

    var connected: [Connection] { connections.filter(\.isConnected) }
    var incomingRequests: [Connection] { connections.filter { $0.status == .incoming } }
    var outgoingRequests: [Connection] { connections.filter { $0.status == .outgoing } }

    /// Stories someone has sent you, newest first.
    func stories(from personID: String) -> [Story] {
        stories.filter { !$0.isSent && $0.sender.id == personID }.sorted { $0.sentAt > $1.sentAt }
    }

    func story(id: Story.ID) -> Story? {
        stories.first { $0.id == id }
    }

    // MARK: Loading

    /// Loads the mailbox for whoever just signed in.
    func load(as person: Person) async {
        if me?.id != person.id { reset() }
        me = person
        guard !isLoaded else { return }
        await fetch()
        isLoaded = true
    }

    /// Pull to refresh: fetches again, keeping the stories already here (and anything cut for them).
    func refresh() async {
        await fetch()
    }

    private func fetch() async {
        guard let me else { return }
        do {
            let mailbox = try await service.loadMailbox(for: me)
            guard self.me?.id == me.id else { return }   // signed out while loading
            let progress = PuzzleProgressStore.load(for: me.id)
            var merged: [Story] = []
            for item in mailbox.items {
                if let existing = story(id: item.record.id) {
                    existing.refresh(from: item.record)
                    merged.append(existing)
                } else {
                    merged.append(Story(record: item.record, photo: item.photo, ownerID: me.id,
                                        progress: progress[item.record.id]))
                }
            }
            stories = merged
            connections = mailbox.connections
        } catch {
            toast = "Couldn't load your postcards"
        }
    }

    /// Forgets everything about the person who was signed in, so the next person starts clean.
    func reset() {
        saveProgress()
        stories = []
        connections = []
        me = nil
        toast = nil
        isComposing = false
        isOnDarkPage = false
        isShowingHowToPlay = false
        isLoaded = false
        lastRecipientIDs = []
        lastIncludedMe = false
    }

    // MARK: Stories

    /// Saves puzzle progress on this device. Called when leaving a puzzle and when the app goes away.
    func saveProgress() {
        guard let me else { return }
        PuzzleProgressStore.save(stories, for: me.id)
    }

    func markOpened(_ story: Story) {
        guard story.isNew, let me else { return }
        story.update { $0.isOpened = true }
        Task { try? await service.markOpened(story.id, for: me) }
    }

    func setArchived(_ story: Story, _ archived: Bool) {
        guard let me else { return }
        withAnimation { story.update { $0.isArchived = archived } }
        Task { try? await service.setArchived(story.id, archived, for: me) }
    }

    /// Call when a received story is solved. Solving your own copy ticks you off in Sent.
    func didSolve(_ story: Story) {
        saveProgress()
        guard let me else { return }
        Task {
            if let updated = try? await service.markSolved(story.id, by: me) {
                self.story(id: updated.id)?.refresh(from: updated)
            }
        }
    }

    /// A fresh draft, starting with whoever you sent to last time (if they're still connected).
    func newDraft() -> SendDraft {
        let stillConnected = lastRecipientIDs.intersection(connected.map(\.id))
        return SendDraft(recipientIDs: stillConnected, includesMe: lastIncludedMe)
    }

    /// Sends a postcard. Your copies (sent, and your own to solve if you included yourself) come back
    /// from the service and join the mailbox.
    func send(_ draft: SendDraft) async -> Bool {
        guard let me, let photo = draft.photo else { return false }
        let recipients = connected.filter { draft.recipientIDs.contains($0.id) }.map(\.person)
        let postcard = OutgoingPostcard(photo: photo, caption: draft.caption, gridSize: draft.gridSize,
                                        recipients: recipients, includesMe: draft.includesMe)
        do {
            let items = try await service.send(postcard, from: me)
            for item in items {
                stories.append(Story(record: item.record, photo: item.photo, ownerID: me.id, progress: nil))
            }
            lastRecipientIDs = draft.recipientIDs
            lastIncludedMe = draft.includesMe
            let names = recipients.map(\.name) + (draft.includesMe ? ["You"] : [])
            toast = recipients.isEmpty ? "Ready for you to solve" : "On its way to \(Story.summary(of: names))"
            return true
        } catch {
            toast = "Couldn't send. Try again?"
            return false
        }
    }

    // MARK: Connections

    /// Asks someone to connect by username. They show as waiting until they accept.
    func requestConnection(username: String) async {
        guard let me else { return }
        let handle = username.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@")).lowercased()
        guard !handle.isEmpty else { return }
        do {
            let request = try await service.requestConnection(username: handle, from: me)
            withAnimation { connections.append(request) }
            toast = "Request sent to @\(handle)"
        } catch {
            toast = (error as? LocalizedError)?.errorDescription ?? "Couldn't send the request"
        }
    }

    func accept(_ connection: Connection) async {
        guard let me else { return }
        do {
            let accepted = try await service.accept(connection.id, for: me)
            if let index = connections.firstIndex(where: { $0.id == accepted.id }) {
                withAnimation(.spring(duration: 0.4)) { connections[index] = accepted }
            }
            toast = "You're connected with \(accepted.name)"
        } catch {
            toast = "Couldn't accept. Try again?"
        }
    }

    /// Removes a connection, declines a request, or cancels one you sent.
    func remove(_ connection: Connection) async {
        guard let me else { return }
        do {
            try await service.remove(connection.id, for: me)
            withAnimation { connections.removeAll { $0.id == connection.id } }
        } catch {
            toast = "Couldn't remove. Try again?"
        }
    }
}

nonisolated enum Route: Hashable {
    case archive
    case connections
    case profile
    case story(UUID)
}
