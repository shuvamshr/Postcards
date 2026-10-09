//
//  StoryCard.swift
//  Sliding
//

import SwiftUI

/// A rounded row in Received or Sent: the puzzle thumbnail, who it's from or to, and where it stands.
/// New received stories are orange with waves and tilt slightly to stand out.
struct StoryCard: View {
    let story: Story

    private var highlighted: Bool { story.isNew && !story.isSent }

    var body: some View {
        HStack(spacing: 14) {
            thumbnail

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    // Sent rows lead with your message; the avatars on the right show who it went to.
                    Text(story.isSent ? (story.caption.isEmpty ? "A photo" : "“\(story.caption)”") : story.senderLabel)
                        .font(Theme.display(18))
                        .lineLimit(1)
                    if highlighted {
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

            if story.isSent {
                RecipientStack(story: story)
            } else {
                Image(systemName: story.isSolved ? "checkmark" : "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(story.isSolved ? .white : (highlighted ? Theme.orange : Theme.muted))
                    .frame(width: 32, height: 32)
                    .background(story.isSolved ? Theme.green : (highlighted ? .white : Theme.paper), in: Circle())
            }
        }
        .foregroundStyle(highlighted ? .white : Theme.ink)
        .padding(7)
        .padding(.trailing, 8)
        .modifier(RowBackground(highlighted: highlighted))
        .modifier(NewRowTilt(highlighted: highlighted, seed: seed))
        .padding(.vertical, highlighted ? 6 : 0)
        .accessibilityElement(children: .combine)
    }

    /// The puzzle as it stands (sent ones are always whole), with the sender's avatar tucked on the corner.
    private var thumbnail: some View {
        // Concentric with the row: row radius 38 minus 7pt inset.
        StoryThumbnail(story: story, cornerRadius: 31)
            .frame(width: 62, height: 62)
            .overlay(alignment: .bottomTrailing) {
                if !story.isSent {
                    Avatar(name: story.senderLabel, size: 24, ringed: true)
                        .offset(x: 4, y: 4)
                }
            }
            .accessibilityHidden(true)
    }

    /// A stable 0–1 value per story so new rows float out of step with each other.
    private var seed: Double {
        Double(story.id.uuidString.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 10) / 10
    }

    /// Where the story stands, in plain words.
    private var subtitle: String {
        let when = story.sentAt.timeIntervalSinceNow > -60
            ? "just now"
            : story.sentAt.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
        if story.isSent {
            if story.isSolvedByEveryone {
                return story.recipients.count == 1 ? "Solved · \(when)" : "All solved · \(when)"
            }
            if story.recipients.count == 1 { return "Waiting · \(when)" }
            return "\(story.solvedBy.count) of \(story.recipients.count) solved · \(when)"
        }
        if story.isSolved { return story.caption.isEmpty ? "Solved" : "“\(story.caption)”" }
        if story.moves > 0 { return "In progress · \(story.n)×\(story.n) puzzle" }
        return "\(story.n)×\(story.n) puzzle · \(when)"
    }
}

/// Overlapping avatars for who a story went to. Anyone who solved it gets a green check.
private struct RecipientStack: View {
    let story: Story
    /// Never more than three bubbles: three people fit, more shows two and "+N".
    private var shown: Int { story.recipients.count <= 3 ? story.recipients.count : 2 }

    var body: some View {
        HStack(spacing: -8) {
            ForEach(Array(story.recipients.prefix(shown).enumerated()), id: \.element.id) { index, person in
                Avatar(name: story.label(for: person), size: 30, ringed: true)
                    .overlay(alignment: .bottomTrailing) {
                        if story.hasSolved(person) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 7, weight: .black))
                                .foregroundStyle(.white)
                                .frame(width: 14, height: 14)
                                .background(Theme.green, in: Circle())
                                .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                                .offset(x: 2, y: 2)
                        }
                    }
                    // Earlier avatars sit on top, so each check stays visible.
                    .zIndex(Double(-index))
            }
            if story.recipients.count > shown {
                Text("+\(story.recipients.count - shown)")
                    .font(Theme.display(12))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 32, height: 32)
                    .background(Theme.paper, in: Circle())
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
                    .zIndex(-10)
            }
        }
    }
}

/// A story's puzzle as it stands, small. Its tiles are cut the first time it's shown, off the
/// main thread; until then the photo stands in.
struct StoryThumbnail: View {
    let story: Story
    let cornerRadius: CGFloat

    var body: some View {
        Group {
            if let pieces = story.photoPieces {
                PuzzleBoard(puzzle: story.puzzle, tiles: pieces.tiles, whole: story.photo, cornerRadius: cornerRadius)
            } else {
                Image(uiImage: story.photo)
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
                    .blur(radius: story.isSolved ? 0 : 6)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        }
        // Solved ones show the whole photo, so they never need cutting.
        .task(id: story.id) { if !story.isSolved { await story.preparePhoto() } }
        .accessibilityHidden(true)
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

    /// "Grandma Rose" → "GR", "Mom" → "M", "🌸 Nana" → "N". Falls back to the first character.
    private var initials: String {
        let letters = name.split(separator: " ").compactMap { $0.first(where: \.isLetter) }.prefix(2)
        if letters.isEmpty { return name.first.map(String.init) ?? "?" }
        return String(letters).uppercased()
    }

    var body: some View {
        Text(initials)
            .font(Theme.display(size * 0.4))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(size * 0.1)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Theme.accent(for: name), in: Circle())
            .overlay {
                if ringed { Circle().strokeBorder(.white, lineWidth: 2.5) }
            }
            .accessibilityHidden(true)
    }
}
