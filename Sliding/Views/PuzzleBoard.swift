//
//  PuzzleBoard.swift
//  Sliding
//

import SwiftUI

/// Draws a puzzle face. Each tile is positioned from the shared PuzzleState,
/// so moving a tile animates it sliding on whichever face is showing.
/// Tiles move by tapping, or by swiping them toward the empty slot.
struct PuzzleBoard: View {
    let puzzle: PuzzleState
    let tiles: [UIImage]
    /// The uncut image, shown once solved so no seams show between tiles.
    var whole: UIImage? = nil
    var cornerRadius: CGFloat = 28
    /// Called with a tile's position when it's tapped or swiped into the gap.
    var onTap: ((Int) -> Void)? = nil

    private struct TileDrag: Equatable {
        let id: Int
        let translation: CGSize
    }

    /// The tile being dragged right now. Resets with a spring so a released tile settles smoothly.
    @GestureState(resetTransaction: Transaction(animation: .snappy(duration: 0.2)))
    private var drag: TileDrag?

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
                        .clipShape(RoundedRectangle(cornerRadius: puzzle.isSolved ? 0 : tileRadius(side: side, gap: gap),
                                                    style: .continuous))
                        .position(x: (CGFloat(position % n) + 0.5) * side,
                                  y: (CGFloat(position / n) + 0.5) * side)
                        .offset(dragOffset(for: id, at: position, side: side))
                        .onTapGesture { onTap?(position) }
                        .gesture(swipe(id: id, position: position, side: side), isEnabled: onTap != nil)
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

    /// Tiles are inset by half the gap from the board's edge, so their corners nest inside the board's:
    /// board radius minus that inset. Capped so small boards (thumbnails) don't turn tiles into circles.
    private func tileRadius(side: CGFloat, gap: CGFloat) -> CGFloat {
        max(0, min(cornerRadius - gap / 2, side * 0.2))
    }

    /// The direction from a tile to the empty slot, if they're side by side; otherwise nil.
    private func directionToGap(from position: Int) -> CGVector? {
        guard !puzzle.isSolved else { return nil }
        let n = puzzle.n, gap = puzzle.blank
        switch gap - position {
        case -n: return CGVector(dx: 0, dy: -1)
        case n: return CGVector(dx: 0, dy: 1)
        case -1 where gap / n == position / n: return CGVector(dx: -1, dy: 0)
        case 1 where gap / n == position / n: return CGVector(dx: 1, dy: 0)
        default: return nil
        }
    }

    /// While dragging, a tile follows the finger only toward the gap, and at most one tile's length.
    private func dragOffset(for id: Int, at position: Int, side: CGFloat) -> CGSize {
        guard let drag, drag.id == id, let dir = directionToGap(from: position) else { return .zero }
        let along = drag.translation.width * dir.dx + drag.translation.height * dir.dy
        let distance = min(max(along, 0), side)
        return CGSize(width: dir.dx * distance, height: dir.dy * distance)
    }

    /// Swiping a tile toward the gap moves it once it's dragged a third of the way or flicked.
    /// Swipes in any other direction do nothing.
    private func swipe(id: Int, position: Int, side: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($drag) { value, state, _ in
                state = TileDrag(id: id, translation: value.translation)
            }
            .onEnded { value in
                guard let dir = directionToGap(from: position) else { return }
                let along = value.translation.width * dir.dx + value.translation.height * dir.dy
                let across = abs(value.translation.width * dir.dy) + abs(value.translation.height * dir.dx)
                let flung = value.predictedEndTranslation.width * dir.dx + value.predictedEndTranslation.height * dir.dy
                guard along > across else { return }
                if along > side * 0.3 || flung > side * 0.6 {
                    onTap?(position)
                }
            }
    }

    /// Every tile except the empty slot; once solved, the last piece drops in (or the whole image takes over).
    private var visibleTileIDs: [Int] {
        if puzzle.isSolved && whole != nil { return [] }
        return Array(1..<puzzle.count) + (puzzle.isSolved ? [puzzle.count] : [])
    }
}

/// A card that flips around its vertical axis, showing `back` past the halfway point.
/// The angle can go past 360; only where it lands matters.
/// With a `thickness`, the card shows a solid edge while it's side-on, like a real card.
///
/// By default each face is drawn flat at rest, so text fields on it edit normally. With `steady`,
/// the card is drawn the same way at every angle instead, so a drag that turns it isn't cancelled
/// by the card being rebuilt partway through.
struct FlipCard<Front: View, Back: View>: View, Animatable {
    var angle: Double
    var thickness: CGFloat = 0
    var cornerRadius: CGFloat = 0
    var edgeColor: Color = Theme.paper
    var steady = false
    @ViewBuilder var front: Front
    @ViewBuilder var back: Back

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    /// The angle folded into 0..<360.
    private var turn: Double {
        let a = angle.truncatingRemainder(dividingBy: 360)
        return a < 0 ? a + 360 : a
    }

    var body: some View {
        let turn = turn
        let showsFront = turn < 90 || turn > 270
        if !steady && (turn < 0.5 || turn > 359.5) {
            front
        } else if !steady && abs(turn - 180) < 0.5 {
            back
        } else {
            ZStack {
                // Both faces stay in place; the hidden one is just invisible and can't be touched.
                front
                    .opacity(showsFront ? 1 : 0)
                    .allowsHitTesting(showsFront)
                back
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                    .opacity(showsFront ? 0 : 1)
                    .allowsHitTesting(!showsFront)
            }
            .rotation3DEffect(.degrees(turn), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
            // A soft, faint shadow that grows a little as the card lifts side-on.
            .shadow(color: .black.opacity(thickness > 0 ? 0.18 * abs(sin(turn * .pi / 180)) : 0),
                    radius: 10, y: 6)
            // As a background, the edge takes exactly the card's size and never changes the layout.
            .background { edge(turn: turn, showsFront: showsFront) }
        }
    }

    /// The card's body behind the face you can see, drawn as thin slices stepped back in depth.
    /// Seen face-on they hide behind the face; side-on they spread out into a solid edge.
    @ViewBuilder
    private func edge(turn: Double, showsFront: Bool) -> some View {
        if thickness > 0 {
            let radians = turn * .pi / 180
            // Depth projects sideways by sin(angle); the body sits behind whichever face is showing.
            let shift = -sin(radians) * (showsFront ? 1 : -1)
            let slices = max(2, Int(thickness.rounded()))
            // A gentle shade as the card turns side-on, just enough to read as an edge.
            let shade = 0.08 * abs(sin(radians))
            ZStack {
                ForEach(1...slices, id: \.self) { i in
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(edgeColor)
                        .overlay(Color.black.opacity(shade))
                        .rotation3DEffect(.degrees(turn), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
                        .offset(x: shift * thickness * CGFloat(i) / CGFloat(slices))
                }
            }
            .allowsHitTesting(false)
        }
    }
}
