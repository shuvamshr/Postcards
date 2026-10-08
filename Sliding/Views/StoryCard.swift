//
//  StoryCard.swift
//  Sliding
//

import SwiftUI

/// A rounded row in Received. New stories are orange with waves and tilt slightly
/// to stand out; everything else sits on plain sand.
struct StoryCard: View {
    let story: Story

    private var highlighted: Bool { story.isNew }

    var body: some View {
        HStack(spacing: 14) {
            // Concentric with the row: row radius 38 minus 7pt inset.
            PuzzleBoard(puzzle: story.puzzle, tiles: story.photoTiles, whole: story.photo, cornerRadius: 31)
                .frame(width: 62, height: 62)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(story.from).font(Theme.display(18))
                    if story.isNew {
                        Text("NEW")
                            .font(Theme.display(10))
                            .foregroundStyle(Theme.orange)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(.white, in: Capsule())
                    }
                }
                Text(subtitle)
                    .font(Theme.body(14, weight: .medium))
                    .foregroundStyle(highlighted ? .white.opacity(0.85) : Theme.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Image(systemName: story.isSolved ? "checkmark.circle.fill" : "chevron.right")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(story.isSolved ? Theme.green : (highlighted ? .white : Theme.muted))
        }
        .foregroundStyle(highlighted ? .white : Theme.ink)
        .padding(7)
        .padding(.trailing, 12)
        .modifier(RowBackground(highlighted: highlighted))
        .modifier(NewRowTilt(highlighted: highlighted, seed: seed))
        .padding(.vertical, highlighted ? 6 : 0)
        .accessibilityElement(children: .combine)
    }

    /// A stable 0–1 value per story so new rows float out of step with each other.
    private var seed: Double {
        Double(story.id.uuidString.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 10) / 10
    }

    /// Where the story stands, in plain words.
    private var subtitle: String {
        if story.isSolved { return "“\(story.caption)”" }
        if story.moves > 0 {
            return "In progress · \(story.n)×\(story.n) puzzle"
        }
        let when = story.sentAt.formatted(.relative(presentation: .named))
        return "\(story.n)×\(story.n) puzzle · \(when)"
    }
}

/// New rows tilt and float; the rest sit still.
private struct NewRowTilt: ViewModifier {
    let highlighted: Bool
    let seed: Double

    func body(content: Content) -> some View {
        if highlighted {
            content.floaty(tilt: -1, seed: seed)
        } else {
            content
        }
    }
}

private struct RowBackground: ViewModifier {
    let highlighted: Bool

    func body(content: Content) -> some View {
        if highlighted {
            content.wavyCard(Theme.orange, radius: 38)
        } else {
            content.softCard(radius: 38)
        }
    }
}

/// Initial-letter avatar for a connection. `ringed` adds a white ring so it reads on colored rows.
struct Avatar: View {
    let name: String
    var size: CGFloat = 48
    var ringed = false

    /// "Grandma Rose" → "GR", "Mom" → "M".
    private var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }

    var body: some View {
        Text(initials)
            .font(Theme.display(size * 0.4))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Theme.accent(for: name), in: Circle())
            .overlay {
                if ringed { Circle().strokeBorder(.white, lineWidth: 2.5) }
            }
            .accessibilityHidden(true)
    }
}
