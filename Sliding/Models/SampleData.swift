//
//  SampleData.swift
//  Sliding
//

#if DEBUG
import SwiftUI

/// Pretend people and postcards for trying the app before there's a backend. Debug builds only:
/// `LocalPostcardService` puts them in a new mailbox once, and they're saved like real ones after that.
enum SampleData {
    private static let mom = Person(id: "sample-mom", name: "Mom", username: "mom")
    private static let dad = Person(id: "sample-dad", name: "Dad", username: "dad")
    private static let rose = Person(id: "sample-rose", name: "Grandma Rose", username: "grandmarose")
    private static let leo = Person(id: "sample-leo", name: "Leo", username: "leo")
    private static let priya = Person(id: "sample-priya", name: "Aunt Priya", username: "auntpriya")
    private static let sam = Person(id: "sample-sam", name: "Cousin Sam", username: "cousinsam")

    /// What to start a new mailbox with, and how far along each sample puzzle is.
    struct Seed {
        var items: [Mailbox.Item] = []
        var connections: [Connection] = []
    }

    /// A postcard plus its progress, which goes to this device's progress store.
    private struct Sample {
        let record: StoryRecord
        let symbol: String
        let color: Color
        var solved = false
        var moves = 0
    }

    static func mailbox(for me: Person) -> Seed {
        let now = Date.now, hour: TimeInterval = 3600
        func received(_ from: Person, _ caption: String, hoursAgo: Double, n: Int, opened: Bool = true,
                      archived: Bool = false) -> StoryRecord {
            StoryRecord(id: UUID(), box: .received, sender: from, recipients: [me], caption: caption,
                        sentAt: now - hoursAgo * hour, gridSize: n, isOpened: opened, isArchived: archived)
        }
        func sent(_ to: [Person], _ caption: String, hoursAgo: Double, n: Int, solvedBy: [Person] = []) -> StoryRecord {
            StoryRecord(id: UUID(), box: .sent, sender: me, recipients: to, caption: caption,
                        sentAt: now - hoursAgo * hour, gridSize: n, solvedBy: Set(solvedBy.map(\.id)), isOpened: true)
        }

        let samples = [
            Sample(record: received(leo, "First day at the new job!", hoursAgo: 2, n: 3, opened: false),
                   symbol: "briefcase.fill", color: Theme.sky),
            Sample(record: received(rose, "Made your favourite dumplings", hoursAgo: 5, n: 3, opened: false),
                   symbol: "fork.knife", color: Theme.yellow),
            Sample(record: received(dad, "Caught a big one at the lake", hoursAgo: 26, n: 4),
                   symbol: "fish.fill", color: Theme.green, moves: 14),
            Sample(record: received(priya, "Biscuit finally learned to sit", hoursAgo: 72, n: 2),
                   symbol: "dog.fill", color: Theme.purple),
            Sample(record: received(sam, "Graduation day!", hoursAgo: 96, n: 3, archived: true),
                   symbol: "graduationcap.fill", color: Theme.teal, solved: true, moves: 41),
            Sample(record: received(mom, "The garden is finally blooming", hoursAgo: 144, n: 2, archived: true),
                   symbol: "leaf.fill", color: Theme.yellow, solved: true, moves: 6),
            Sample(record: received(mom, "Sunset from the porch", hoursAgo: 216, n: 3, archived: true),
                   symbol: "sun.horizon.fill", color: Theme.orange, solved: true, moves: 27),
            Sample(record: sent([mom, dad, rose], "Our new kitchen!", hoursAgo: 3, n: 3, solvedBy: [mom]),
                   symbol: "house.fill", color: Theme.teal),
            Sample(record: sent([leo], "Ran my first 10k", hoursAgo: 30, n: 4),
                   symbol: "figure.run", color: Theme.orange),
            Sample(record: sent([mom, dad], "Pancake Sunday", hoursAgo: 100, n: 2, solvedBy: [mom, dad]),
                   symbol: "frying.pan.fill", color: Theme.yellow),
        ]

        let connections = [mom, dad, rose, leo, priya, sam].map { Connection(person: $0) } + [
            // Waiting on you to accept.
            Connection(person: Person(id: "sample-raj", name: "Uncle Raj", username: "rajkumar"), status: .incoming),
            Connection(person: Person(id: "sample-nina", name: "Nina Park", username: "ninapark"), status: .incoming),
        ]
        return seed(samples, connections: connections, for: me)
    }

    /// Edge cases for checking the design: long names, long and empty messages, many recipients.
    /// Launch with `-StressTest YES` on a fresh mailbox.
    static func stressMailbox(for me: Person) -> Seed {
        let now = Date.now, hour: TimeInterval = 3600
        let long = Person(id: "stress-long", name: "Great-Grandma Margaret Elizabeth Fitzgerald-Worthington")
        let bart = Person(id: "stress-bart", name: "Bartholomew Alexander Montgomery III")
        let jo = Person(id: "stress-jo", name: "Jo")
        let nana = Person(id: "stress-nana", name: "🌸 Nana")
        let max = Person(id: "stress-max", name: "Uncle Maximilian")
        let ana = Person(id: "stress-ana", name: "Cousin Anastasia-Josephine")
        let everyone = [mom, dad, rose, leo, priya, sam, bart, jo, nana, max]

        func received(_ from: Person, _ caption: String, hoursAgo: Double, n: Int, opened: Bool = true,
                      archived: Bool = false) -> StoryRecord {
            StoryRecord(id: UUID(), box: .received, sender: from, recipients: [me], caption: caption,
                        sentAt: now - hoursAgo * hour, gridSize: n, isOpened: opened, isArchived: archived)
        }
        func sent(_ to: [Person], _ caption: String, hoursAgo: Double, n: Int, solvedBy: [Person] = []) -> StoryRecord {
            StoryRecord(id: UUID(), box: .sent, sender: me, recipients: to, caption: caption,
                        sentAt: now - hoursAgo * hour, gridSize: n, solvedBy: Set(solvedBy.map(\.id)), isOpened: true)
        }

        let samples = [
            Sample(record: received(long, "Look who turned one hundred today and still beat everyone at cards!",
                                    hoursAgo: 0.02, n: 4, opened: false), symbol: "birthday.cake.fill", color: Theme.orange),
            Sample(record: received(bart, "Hi", hoursAgo: 3, n: 3), symbol: "crown.fill", color: Theme.purple),
            Sample(record: received(jo, "", hoursAgo: 20, n: 2, opened: false), symbol: "star.fill", color: Theme.yellow),
            Sample(record: received(nana, "🌷🌷🌷 Spring is here 🌷🌷🌷", hoursAgo: 50, n: 3),
                   symbol: "leaf.fill", color: Theme.green, moves: 120),
            Sample(record: received(ana, "Supercalifragilisticexpialidocious adventures await us all", hoursAgo: 400, n: 3),
                   symbol: "airplane", color: Theme.sky, solved: true, moves: 33),
            Sample(record: received(max, "Fishing again", hoursAgo: 9000, n: 4), symbol: "fish.fill", color: Theme.teal),
            Sample(record: received(long, "", hoursAgo: 500, n: 2, archived: true),
                   symbol: "gift.fill", color: Theme.orange, solved: true),
            Sample(record: received(bart, "A really very long message that goes on and on to see how it wraps",
                                    hoursAgo: 600, n: 3, archived: true), symbol: "music.note", color: Theme.sky, solved: true),
            Sample(record: sent(everyone, "Family reunion photo — everyone made it this year, even the dog!",
                                hoursAgo: 0.01, n: 4, solvedBy: [mom, jo, leo, max]), symbol: "person.3.fill", color: Theme.teal),
            Sample(record: sent([long], "", hoursAgo: 2, n: 2), symbol: "camera.fill", color: Theme.orange),
            Sample(record: sent([bart, long, ana, jo], "Hi", hoursAgo: 26, n: 3, solvedBy: [bart, long, ana, jo]),
                   symbol: "hand.wave.fill", color: Theme.yellow),
            Sample(record: sent([nana, jo], "Supercalifragilisticexpialidocious", hoursAgo: 300, n: 3, solvedBy: [nana]),
                   symbol: "sparkles", color: Theme.purple),
        ]
        let connections = (everyone + [long, ana]).map { Connection(person: $0) }
        return seed(samples, connections: connections, for: me)
    }

    /// Draws the sample photos and saves each puzzle's starting progress on this device.
    private static func seed(_ samples: [Sample], connections: [Connection], for me: Person) -> Seed {
        var progress = PuzzleProgressStore.load(for: me.id)
        var seed = Seed(connections: connections)
        for sample in samples {
            seed.items.append(Mailbox.Item(record: sample.record,
                                           photo: StoryArt.photo(symbol: sample.symbol, color: sample.color)))
            if sample.record.box == .received {
                let n = sample.record.gridSize
                progress[sample.record.id] = PuzzleProgress(puzzle: sample.solved ? .solved(n: n) : .shuffled(n: n),
                                                            moves: sample.moves)
            }
        }
        PuzzleProgressStore.saveAll(progress, for: me.id)
        return seed
    }
}
#endif
