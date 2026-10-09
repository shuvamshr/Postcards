//
//  Story.swift
//  Sliding
//

import SwiftUI

/// Someone in the app. `id` is their account ID; everything is matched by it, and the name is
/// only for showing. Two people can share a name, and names can change.
nonisolated struct Person: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var name: String
    var username: String?
}

/// A postcard as the service stores it: who sent it to whom, the words, and its status.
/// The photo travels separately, since it's large.
nonisolated struct StoryRecord: Codable, Identifiable, Sendable {
    enum Box: String, Codable, Sendable { case received, sent }

    var id: UUID
    /// Whose mailbox this copy is in, from their point of view.
    var box: Box
    var sender: Person
    var recipients: [Person]
    var caption: String
    var sentAt: Date
    var gridSize: Int
    /// IDs of the recipients who've solved it. Filled in for sent stories.
    var solvedBy: Set<String> = []
    var isOpened = false
    var isArchived = false
    /// For a copy you sent yourself: the sent story it came from, so solving it shows up in Sent.
    var copyOf: UUID?
}

/// The pieces cut from a story, made only when it's about to be shown.
nonisolated struct PhotoPieces: Sendable {
    let tiles: [UIImage]
}

nonisolated struct MessagePieces: Sendable {
    let image: UIImage
    let tiles: [UIImage]
}

/// A postcard in the app: the record from the service, its photo, and how far you've got.
/// The photo is the front of the puzzle; the caption is drawn onto the back, and both are cut
/// into the same tiles.
@Observable
final class Story: Identifiable {
    private(set) var record: StoryRecord
    let photo: UIImage
    /// The signed-in person this copy belongs to, so they show as "You".
    let ownerID: String
    /// Progress lives on this device only.
    var puzzle: PuzzleState
    /// Slides made so far; only used to tell a started puzzle from an untouched one.
    var moves: Int

    /// Cut lazily, off the main thread: a mailbox can hold far more stories than are ever opened.
    private(set) var photoPieces: PhotoPieces?
    private(set) var messagePieces: MessagePieces?
    @ObservationIgnored private var cuttingPhoto: Task<Void, Never>?
    @ObservationIgnored private var cuttingMessage: Task<Void, Never>?

    init(record: StoryRecord, photo: UIImage, ownerID: String, progress: PuzzleProgress?) {
        self.record = record
        self.photo = photo
        self.ownerID = ownerID
        if let progress, progress.puzzle.n == record.gridSize {
            puzzle = progress.puzzle
            moves = progress.moves
        } else {
            // Sent stories are already solved; your own puzzle is the one you got.
            puzzle = record.box == .sent ? .solved(n: record.gridSize) : .shuffled(n: record.gridSize)
            moves = 0
        }
    }

    var id: UUID { record.id }
    var sender: Person { record.sender }
    var recipients: [Person] { record.recipients }
    var caption: String { record.caption }
    var sentAt: Date { record.sentAt }
    var solvedBy: Set<String> { record.solvedBy }
    var copyOf: UUID? { record.copyOf }
    var isArchived: Bool { record.isArchived }
    var isNew: Bool { !record.isOpened }

    var n: Int { puzzle.n }
    var isSolved: Bool { puzzle.isSolved }
    var isSent: Bool { record.box == .sent }
    var isSolvedByEveryone: Bool { recipients.allSatisfy { solvedBy.contains($0.id) } }
    var progress: PuzzleProgress { PuzzleProgress(puzzle: puzzle, moves: moves) }

    /// How someone shows on this copy: their name, or "You" for the person it belongs to.
    func label(for person: Person) -> String { person.id == ownerID ? "You" : person.name }
    var senderLabel: String { label(for: sender) }
    var recipientNames: String { Self.summary(of: recipients.map(label(for:))) }
    func hasSolved(_ person: Person) -> Bool { solvedBy.contains(person.id) }

    /// "Mom & Dad", "Mom, Dad & Leo", "Mom, Dad & 3 others".
    static func summary(of names: [String]) -> String {
        if names.count > 3 { return "\(names.prefix(2).joined(separator: ", ")) & \(names.count - 2) others" }
        if names.count < 2 { return names.first ?? "" }
        return "\(names.dropLast().joined(separator: ", ")) & \(names.last!)"
    }

    // MARK: Changes from the service

    func update(_ change: (inout StoryRecord) -> Void) { change(&record) }

    /// Takes newer status from the service, keeping the pieces already cut and the progress made here.
    func refresh(from newer: StoryRecord) { record = newer }

    // MARK: Pieces

    /// Cuts the photo into tiles, for thumbnails and the puzzle.
    func preparePhoto() async {
        if photoPieces != nil { return }
        if let cuttingPhoto { return await cuttingPhoto.value }
        let photo = photo, n = record.gridSize
        let task = Task {
            let tiles = await Task.detached(priority: .userInitiated) { photo.slices(n) }.value
            photoPieces = PhotoPieces(tiles: tiles)
        }
        cuttingPhoto = task
        await task.value
    }

    /// Draws the message card and cuts it, for opening the puzzle. Drawing needs the main thread;
    /// cutting doesn't.
    func prepareMessage() async {
        if messagePieces != nil { return }
        if let cuttingMessage { return await cuttingMessage.value }
        let task = Task {
            let image = StoryArt.message(record.caption, from: record.sender.name)
            let n = record.gridSize
            let tiles = await Task.detached(priority: .userInitiated) { image.slices(n) }.value
            messagePieces = MessagePieces(image: image, tiles: tiles)
        }
        cuttingMessage = task
        await task.value
    }

    func prepareAll() async {
        async let photo: Void = preparePhoto()
        async let message: Void = prepareMessage()
        _ = await (photo, message)
    }
}

/// A puzzle's progress on this device.
nonisolated struct PuzzleProgress: Codable, Sendable {
    var puzzle: PuzzleState
    var moves: Int
}

/// Someone you're connected with, or a request either way. Connecting takes both people:
/// one asks, the other accepts.
nonisolated struct Connection: Identifiable, Codable, Sendable {
    enum Status: String, Codable, Sendable { case connected, incoming, outgoing }

    var person: Person
    var status: Status = .connected

    var id: String { person.id }
    var name: String { person.name }
    var username: String? { person.username }
    var isConnected: Bool { status == .connected }
}

/// What the sender is putting together in the send flow, including who it's going to.
@Observable
final class SendDraft {
    var photo: UIImage?
    var caption = ""
    var gridSize = 3
    /// A photo picked from the library, kept whole so it can be cropped in the preview.
    var original: UIImage?
    var cropScale: CGFloat = 1
    var cropOffset: CGSize = .zero
    /// IDs of the connections it's going to.
    var recipientIDs: Set<String> = []
    /// Whether you get your own copy to solve too.
    var includesMe = false

    init(recipientIDs: Set<String> = [], includesMe: Bool = false) {
        self.recipientIDs = recipientIDs
        self.includesMe = includesMe
    }
}
