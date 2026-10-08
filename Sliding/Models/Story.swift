//
//  Story.swift
//  Sliding
//

import SwiftUI

/// A photo story received from a connection. The photo is the front of the puzzle,
/// the caption is rendered onto the back, and both are cut into the same tiles.
@Observable
final class Story: Identifiable {
    let id = UUID()
    let from: String
    let caption: String
    let sentAt: Date
    let photo: UIImage
    let message: UIImage
    let photoTiles: [UIImage]
    let messageTiles: [UIImage]
    var puzzle: PuzzleState
    /// Slides made so far; only used to tell a started puzzle from an untouched one.
    var moves = 0
    var isNew: Bool
    var isArchived: Bool

    var n: Int { puzzle.n }
    var isSolved: Bool { puzzle.isSolved }

    init(from: String, caption: String, sentAt: Date, photo: UIImage, gridSize n: Int,
         isNew: Bool = false, isArchived: Bool = false, solved: Bool = false, moves: Int = 0) {
        self.from = from
        self.caption = caption
        self.sentAt = sentAt
        let square = photo.squareCropped()
        let message = StoryArt.message(caption, from: from)
        self.photo = square
        self.message = message
        self.photoTiles = square.slices(n)
        self.messageTiles = message.slices(n)
        self.puzzle = solved ? .solved(n: n) : .shuffled(n: n)
        self.moves = moves
        self.isNew = isNew
        self.isArchived = isArchived
    }
}

nonisolated struct Connection: Identifiable {
    let id = UUID()
    var name: String
    var isSelected = false
}

/// What the sender is putting together in the send flow.
@Observable
final class SendDraft {
    var photo: UIImage?
    var caption = ""
    var gridSize = 3
}
