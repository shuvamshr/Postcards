//
//  PuzzleState.swift
//  Sliding
//

import Foundation

/// A sliding-tile puzzle on an n×n board.
/// `tiles[position]` holds a tile id (1...count-1), and 0 marks the empty slot.
/// The photo and the message share one PuzzleState, so they always move together.
nonisolated struct PuzzleState: Equatable {
    let n: Int
    private(set) var tiles: [Int]

    var count: Int { n * n }
    var isSolved: Bool { tiles == Self.solvedTiles(n) }
    var blank: Int { tiles.firstIndex(of: 0)! }

    static func solved(n: Int) -> PuzzleState {
        PuzzleState(n: n, tiles: solvedTiles(n))
    }

    static func shuffled(n: Int) -> PuzzleState {
        var puzzle = solved(n: n)
        puzzle.shuffle()
        return puzzle
    }

    private static func solvedTiles(_ n: Int) -> [Int] {
        Array(1..<(n * n)) + [0]
    }

    /// Where a tile currently sits. Once solved, the final piece (id == count) fills the empty slot.
    func position(of id: Int) -> Int {
        id == count ? blank : tiles.firstIndex(of: id)!
    }

    func neighbors(of position: Int) -> [Int] {
        let row = position / n, col = position % n
        var result: [Int] = []
        if row > 0 { result.append(position - n) }
        if row < n - 1 { result.append(position + n) }
        if col > 0 { result.append(position - 1) }
        if col < n - 1 { result.append(position + 1) }
        return result
    }

    /// Slides the tile at `position` into the empty slot if they're adjacent.
    @discardableResult
    mutating func move(_ position: Int) -> Bool {
        guard !isSolved else { return false }
        let empty = blank
        guard neighbors(of: empty).contains(position) else { return false }
        tiles.swapAt(position, empty)
        return true
    }

    /// Scrambles with random legal moves, so the result is always solvable.
    /// Repeats until at least half the tiles are out of place, so small boards still feel like a puzzle.
    mutating func shuffle() {
        tiles = Self.solvedTiles(n)
        repeat {
            var previous = -1
            for _ in 0..<(count * 20) {
                let empty = blank
                let options = neighbors(of: empty).filter { $0 != previous }
                let pick = options.randomElement()!
                tiles.swapAt(pick, empty)
                previous = empty
            }
        } while misplacedCount < max(2, (count - 1) / 2)
    }

    private var misplacedCount: Int {
        zip(tiles, Self.solvedTiles(n)).filter { $0 != 0 && $0 != $1 }.count
    }
}
