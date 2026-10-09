//
//  PostcardService.swift
//  Sliding
//

import UIKit

/// Everything that will eventually come from the server: your mailbox, sending, and connections.
/// The app talks only to this, so a server-backed version can replace `LocalPostcardService`
/// without any screen changing.
protocol PostcardService: Sendable {
    /// Your stories and connections. Photos come with the records.
    func loadMailbox(for me: Person) async throws -> Mailbox

    /// Delivers a postcard and returns the copies that now belong to you: the sent one, plus
    /// your own copy to solve if you included yourself.
    func send(_ postcard: OutgoingPostcard, from me: Person) async throws -> [Mailbox.Item]

    func markOpened(_ storyID: UUID, for me: Person) async throws
    /// Records that you solved a story. Returns the sent story it was a copy of, if any, updated.
    func markSolved(_ storyID: UUID, by me: Person) async throws -> StoryRecord?
    func setArchived(_ storyID: UUID, _ archived: Bool, for me: Person) async throws

    func requestConnection(username: String, from me: Person) async throws -> Connection
    func accept(_ personID: String, for me: Person) async throws -> Connection
    /// Removes a connection, declines a request, or cancels one you sent.
    func remove(_ personID: String, for me: Person) async throws
}

nonisolated struct Mailbox: Sendable {
    struct Item: Sendable {
        let record: StoryRecord
        let photo: UIImage
    }

    var items: [Item]
    var connections: [Connection]
}

nonisolated struct OutgoingPostcard: Sendable {
    let photo: UIImage
    let caption: String
    let gridSize: Int
    let recipients: [Person]
    let includesMe: Bool
}

nonisolated enum PostcardError: LocalizedError {
    case unknownUser(String)
    case alreadyConnected(String)
    case notFound

    var errorDescription: String? {
        switch self {
        case .unknownUser(let name): "No one's called @\(name) yet."
        case .alreadyConnected(let name): "You're already connected with @\(name), or there's a request waiting."
        case .notFound: "That postcard isn't here any more."
        }
    }
}

// MARK: - On this device

/// Stands in for the server: keeps each person's mailbox in a folder on this device.
/// Pretend network delays come from `FakeLatency`; debug builds seed sample data on first load.
actor LocalPostcardService: PostcardService {
    private struct Stored: Codable {
        var records: [StoryRecord] = []
        var connections: [Connection] = []
        /// Which photo file each record uses; a sent story and your own copy share one.
        var photoFiles: [UUID: String] = [:]
    }

    private let root: URL
    private var cache: [String: Stored] = [:]

    init(root: URL = URL.applicationSupportDirectory.appending(path: "Mailboxes", directoryHint: .isDirectory)) {
        self.root = root
    }

    func loadMailbox(for me: Person) async throws -> Mailbox {
        await FakeLatency.wait(1.6)
        var stored = try load(me)
        #if DEBUG
        if !hasSeeded(me) {
            stored = try await seed(for: me)
        }
        #endif
        let items = stored.records.compactMap { record -> Mailbox.Item? in
            guard let file = stored.photoFiles[record.id],
                  let image = UIImage(contentsOfFile: folder(for: me).appending(path: file).path(percentEncoded: false)) else { return nil }
            return Mailbox.Item(record: record, photo: image)
        }
        return Mailbox(items: items, connections: stored.connections)
    }

    func send(_ postcard: OutgoingPostcard, from me: Person) async throws -> [Mailbox.Item] {
        await FakeLatency.wait(2.2)
        var stored = try load(me)
        let file = try savePhoto(postcard.photo, for: me)
        let everyone = postcard.recipients + (postcard.includesMe ? [me] : [])
        let sent = StoryRecord(id: UUID(), box: .sent, sender: me, recipients: everyone,
                               caption: postcard.caption, sentAt: .now, gridSize: postcard.gridSize)
        var items = [Mailbox.Item(record: sent, photo: postcard.photo)]
        stored.records.append(sent)
        stored.photoFiles[sent.id] = file
        if postcard.includesMe {
            let copy = StoryRecord(id: UUID(), box: .received, sender: me, recipients: [me],
                                   caption: postcard.caption, sentAt: .now, gridSize: postcard.gridSize,
                                   copyOf: sent.id)
            stored.records.append(copy)
            stored.photoFiles[copy.id] = file
            items.append(Mailbox.Item(record: copy, photo: postcard.photo))
        }
        // Delivery to the other recipients happens on the server.
        try save(stored, for: me)
        return items
    }

    func markOpened(_ storyID: UUID, for me: Person) async throws {
        try change(storyID, for: me) { $0.isOpened = true }
    }

    func markSolved(_ storyID: UUID, by me: Person) async throws -> StoryRecord? {
        var stored = try load(me)
        guard let copy = stored.records.first(where: { $0.id == storyID }),
              let sentID = copy.copyOf,
              let index = stored.records.firstIndex(where: { $0.id == sentID }) else { return nil }
        // On the server, the sender's sent story gets ticked off for whoever solved it.
        stored.records[index].solvedBy.insert(me.id)
        try save(stored, for: me)
        return stored.records[index]
    }

    func setArchived(_ storyID: UUID, _ archived: Bool, for me: Person) async throws {
        try change(storyID, for: me) { $0.isArchived = archived }
    }

    func requestConnection(username: String, from me: Person) async throws -> Connection {
        await FakeLatency.wait(0.8)
        var stored = try load(me)
        guard !stored.connections.contains(where: { $0.username == username }) else {
            throw PostcardError.alreadyConnected(username)
        }
        // The server would look the username up; here everyone exists, and stays a request.
        let request = Connection(person: Person(id: "user-\(username)", name: "@\(username)", username: username),
                                 status: .outgoing)
        stored.connections.append(request)
        try save(stored, for: me)
        return request
    }

    func accept(_ personID: String, for me: Person) async throws -> Connection {
        var stored = try load(me)
        guard let index = stored.connections.firstIndex(where: { $0.id == personID }) else {
            throw PostcardError.notFound
        }
        stored.connections[index].status = .connected
        try save(stored, for: me)
        return stored.connections[index]
    }

    func remove(_ personID: String, for me: Person) async throws {
        var stored = try load(me)
        stored.connections.removeAll { $0.id == personID }
        try save(stored, for: me)
    }

    // MARK: Storage

    private func folder(for me: Person) -> URL {
        let safe = me.id.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : "_" }.joined()
        return root.appending(path: safe, directoryHint: .isDirectory)
    }

    private func load(_ me: Person) throws -> Stored {
        if let cached = cache[me.id] { return cached }
        let file = folder(for: me).appending(path: "mailbox.json")
        guard FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else { return Stored() }
        let stored = try JSONDecoder().decode(Stored.self, from: Data(contentsOf: file))
        cache[me.id] = stored
        return stored
    }

    private func save(_ stored: Stored, for me: Person) throws {
        cache[me.id] = stored
        let folder = folder(for: me)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(stored).write(to: folder.appending(path: "mailbox.json"), options: .atomic)
    }

    private func savePhoto(_ photo: UIImage, for me: Person) throws -> String {
        let folder = folder(for: me)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = "\(UUID().uuidString).jpg"
        guard let data = photo.jpegData(compressionQuality: 0.85) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: folder.appending(path: name), options: .atomic)
        return name
    }

    private func change(_ storyID: UUID, for me: Person, _ edit: (inout StoryRecord) -> Void) throws {
        var stored = try load(me)
        guard let index = stored.records.firstIndex(where: { $0.id == storyID }) else { throw PostcardError.notFound }
        edit(&stored.records[index])
        try save(stored, for: me)
    }

    #if DEBUG
    private func hasSeeded(_ me: Person) -> Bool {
        FileManager.default.fileExists(atPath: folder(for: me).appending(path: "mailbox.json").path(percentEncoded: false))
    }

    /// Fills a new mailbox with the sample people and postcards, once.
    private func seed(for me: Person) async throws -> Stored {
        let stress = UserDefaults.standard.bool(forKey: "StressTest")
        let samples = await MainActor.run { stress ? SampleData.stressMailbox(for: me) : SampleData.mailbox(for: me) }
        var stored = Stored(connections: samples.connections)
        for item in samples.items {
            stored.records.append(item.record)
            stored.photoFiles[item.record.id] = try savePhoto(item.photo, for: me)
        }
        try save(stored, for: me)
        return stored
    }
    #endif
}

/// Puzzle progress stays on this device: it changes with every slide, and only you need it.
@MainActor
enum PuzzleProgressStore {
    private static func key(_ ownerID: String) -> String { "progress.\(ownerID)" }

    static func load(for ownerID: String) -> [UUID: PuzzleProgress] {
        guard let data = UserDefaults.standard.data(forKey: key(ownerID)),
              let all = try? JSONDecoder().decode([UUID: PuzzleProgress].self, from: data) else { return [:] }
        return all
    }

    static func save(_ stories: [Story], for ownerID: String) {
        saveAll(Dictionary(uniqueKeysWithValues: stories.filter { !$0.isSent }.map { ($0.id, $0.progress) }),
                for: ownerID)
    }

    static func saveAll(_ all: [UUID: PuzzleProgress], for ownerID: String) {
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: key(ownerID))
        }
    }
}
