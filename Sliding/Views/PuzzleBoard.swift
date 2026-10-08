//
//  PuzzleBoard.swift
//  Sliding
//

import SwiftUI

/// Draws a puzzle face. Each tile is positioned from the shared PuzzleState,
/// so moving a tile animates it sliding on whichever face is showing.
struct PuzzleBoard: View {
    let puzzle: PuzzleState
    let tiles: [UIImage]
    /// The uncut image, shown once solved so no seams show between tiles.
    var whole: UIImage? = nil
    var cornerRadius: CGFloat = 28
    var onTap: ((Int) -> Void)? = nil

    var body: some View {
        GeometryReader { geo in
            let n = puzzle.n
            let side = geo.size.width / CGFloat(n)
            let gap = puzzle.isSolved ? 0 : max(2, side * 0.04)
            ZStack(alignment: .topLeading) {
                if puzzle.isSolved, let whole {
                    Image(uiImage: whole)
                        .resizable()
                        .frame(width: geo.size.width, height: geo.size.width)
                        .transition(.opacity)
                }
                ForEach(visibleTileIDs, id: \.self) { id in
                    let position = puzzle.position(of: id)
                    Image(uiImage: tiles[id - 1])
                        .resizable()
                        .frame(width: side - gap, height: side - gap)
                        .clipShape(RoundedRectangle(cornerRadius: puzzle.isSolved ? 0 : side * 0.1, style: .continuous))
                        .position(x: (CGFloat(position % n) + 0.5) * side,
                                  y: (CGFloat(position / n) + 0.5) * side)
                        .onTapGesture { onTap?(position) }
                        .accessibilityElement()
                        .accessibilityLabel("Tile \(id)")
                        .accessibilityAddTraits(onTap == nil ? [] : .isButton)
                }
            }
            .frame(width: geo.size.width, height: geo.size.width)
        }
        .aspectRatio(1, contentMode: .fit)
        .background(Theme.ink)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .animation(.easeOut(duration: 0.3), value: puzzle.isSolved)
    }

    /// Every tile except the empty slot; once solved, the last piece drops in (or the whole image takes over).
    private var visibleTileIDs: [Int] {
        if puzzle.isSolved && whole != nil { return [] }
        return Array(1..<puzzle.count) + (puzzle.isSolved ? [puzzle.count] : [])
    }
}

/// A card that flips around its vertical axis, showing `back` past the halfway point.
struct FlipCard<Front: View, Back: View>: View, Animatable {
    var angle: Double
    @ViewBuilder var front: Front
    @ViewBuilder var back: Back

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    var body: some View {
        // At rest, show each face untransformed so text fields on it edit normally.
        if angle < 0.5 {
            front
        } else if angle > 179.5 {
            back
        } else {
            ZStack {
                if angle < 90 {
                    front
                } else {
                    back.rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                }
            }
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
        }
    }
}
