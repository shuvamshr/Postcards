//
//  AppModel.swift
//  Sliding
//

import SwiftUI

/// App-wide state. There is no backend yet, so everything is in memory and starts from sample data.
@Observable
final class AppModel {
    var stories: [Story] = []
    var connections: [Connection]
    var toast: String?
    /// Whether the send flow is showing.
    var isComposing = false
    /// Whether a dark page (the puzzle) is showing, so the app switches its chrome to dark.
    var isOnDarkPage = false
    /// Whether the how-to-play overlay is showing. Drawn at the app root so it covers the toolbar too.
    var isShowingHowToPlay = false
    private(set) var isLoaded = false

    init() {
        connections = [
            Connection(name: "Mom", isSelected: true),
            Connection(name: "Dad", isSelected: true),
            Connection(name: "Grandma Rose"),
            Connection(name: "Leo"),
            Connection(name: "Aunt Priya"),
            Connection(name: "Cousin Sam"),
        ]
    }

    var received: [Story] { stories.filter { !$0.isArchived }.sorted { $0.sentAt > $1.sentAt } }
    var archived: [Story] { stories.filter(\.isArchived).sorted { $0.sentAt > $1.sentAt } }

    /// Rendering the sample puzzles takes a moment, so it runs after the first frame is on screen.
    func loadSampleData() async {
        guard !isLoaded else { return }
        try? await Task.sleep(for: .milliseconds(60))
        stories = SampleData.stories()
        isLoaded = true
    }

    func stories(from name: String) -> [Story] {
        stories.filter { $0.from == name }.sorted { $0.sentAt > $1.sentAt }
    }

    /// The next story to solve: the newest unsolved one.
    var nextToSolve: Story? { received.first { !$0.isSolved } }

    func story(id: Story.ID) -> Story? {
        stories.first { $0.id == id }
    }

    func addConnection(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        connections.append(Connection(name: trimmed))
    }

    /// Sending only confirms for now; delivering to other people needs a backend.
    func send(_ draft: SendDraft) {
        let names = connections.filter(\.isSelected).map(\.name)
        toast = "On its way to \(ListFormatter.localizedString(byJoining: names))"

        #if DEBUG
        // Testing aid: with no backend yet, drop a copy into Received so the sent story can be solved here.
        if let photo = draft.photo {
            let echo = Story(from: "You", caption: draft.caption, sentAt: .now, photo: photo,
                             gridSize: draft.gridSize, isNew: true)
            stories.append(echo)
        }
        #endif
    }
}

nonisolated enum Route: Hashable {
    case archive
    case story(UUID)
}

enum SampleData {
    static func stories() -> [Story] {
        let now = Date.now
        let hour: TimeInterval = 3600
        return [
            Story(from: "Leo", caption: "First day at the new job!", sentAt: now - 2 * hour,
                  photo: StoryArt.photo(symbol: "briefcase.fill", color: Theme.sky), gridSize: 3, isNew: true),
            Story(from: "Grandma Rose", caption: "Made your favourite dumplings", sentAt: now - 5 * hour,
                  photo: StoryArt.photo(symbol: "fork.knife", color: Theme.yellow), gridSize: 3, isNew: true),
            Story(from: "Dad", caption: "Caught a big one at the lake", sentAt: now - 26 * hour,
                  photo: StoryArt.photo(symbol: "fish.fill", color: Theme.green), gridSize: 4, moves: 14),
            Story(from: "Aunt Priya", caption: "Biscuit finally learned to sit", sentAt: now - 72 * hour,
                  photo: StoryArt.photo(symbol: "dog.fill", color: Theme.purple), gridSize: 2),
            Story(from: "Cousin Sam", caption: "Graduation day!", sentAt: now - 96 * hour,
                  photo: StoryArt.photo(symbol: "graduationcap.fill", color: Theme.teal), gridSize: 3,
                  isArchived: true, solved: true, moves: 41),
            Story(from: "Mom", caption: "The garden is finally blooming", sentAt: now - 144 * hour,
                  photo: StoryArt.photo(symbol: "leaf.fill", color: Theme.yellow), gridSize: 2,
                  isArchived: true, solved: true, moves: 6),
            Story(from: "Mom", caption: "Sunset from the porch", sentAt: now - 216 * hour,
                  photo: StoryArt.photo(symbol: "sun.horizon.fill", color: Theme.orange), gridSize: 3,
                  isArchived: true, solved: true, moves: 27),
        ]
    }
}
