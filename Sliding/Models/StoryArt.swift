//
//  StoryArt.swift
//  Sliding
//

import SwiftUI

/// Renders images for the puzzle: placeholder photos for sample data, and the message card on the back.
enum StoryArt {
    static func photo(symbol: String, color: Color) -> UIImage {
        render(
            ZStack {
                color
                Waves(color: .white.opacity(0.14), lineWidth: 26)
                Image(systemName: symbol)
                    .font(.system(size: 230, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 600, height: 600)
        )
    }

    /// Stands in for the camera where there isn't one (the Simulator).
    static func samplePhoto() -> UIImage {
        let options: [(String, Color)] = [
            ("sun.max.fill", Theme.yellow),
            ("mountain.2.fill", Theme.sky),
            ("pawprint.fill", Theme.orange),
            ("cup.and.saucer.fill", Theme.green),
            ("tent.fill", Theme.teal),
            ("bicycle", Theme.purple),
            ("birthday.cake.fill", Theme.orange),
        ]
        let pick = options.randomElement()!
        return photo(symbol: pick.0, color: pick.1)
    }

    /// Type shrinks smoothly as the message grows, so short messages are big enough to reach
    /// across many tiles and long ones still fit. Sizes are in the 600pt message layout:
    /// 10 characters → 120, 20 → 85, 40 → 60, 60 → 49.
    static func messageFontSize(for text: String) -> CGFloat {
        guard !text.isEmpty else { return 54 }   // the placeholder, which can't wrap
        return 120 * (10 / CGFloat(max(text.count, 10))).squareRoot()
    }

    static func message(_ text: String, from: String) -> UIImage {
        render(MessageCard(text: text, from: from).frame(width: 600, height: 600))
    }

    private static func render(_ view: some View) -> UIImage {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.uiImage ?? UIImage()
    }
}

/// The back of the puzzle: the caption on lined note paper.
private struct MessageCard: View {
    let text: String
    let from: String

    var body: some View {
        MessagePaper(from: from) { scale in
            MessageText(text: text, scale: scale)
        }
    }
}

/// The message as it appears on the board: centered, shrinking as it grows, always fully visible.
/// Used for both the rendered puzzle and the live editor, so they match exactly.
struct MessageText: View {
    let text: String
    var placeholder: String? = nil
    var showsCursor = false
    let scale: CGFloat

    /// When the text last changed; the cursor stays solid while typing and blinks once you pause.
    @State private var lastEdit = Date.now

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let since = context.date.timeIntervalSince(lastEdit)
            let cursorOn = since < 0.6 || Int(since / 0.5).isMultiple(of: 2)
            // The cursor keeps its space while hidden, so the text never shifts as it blinks.
            let cursor = Text("|").foregroundStyle(Theme.orange.opacity(cursorOn ? 1 : 0))

            Group {
                if text.isEmpty, let placeholder {
                    if showsCursor {
                        Text("\(cursor)\(Text(placeholder).foregroundStyle(Theme.muted.opacity(0.5)))")
                    } else {
                        Text(placeholder).foregroundStyle(Theme.muted.opacity(0.5))
                    }
                } else if showsCursor {
                    Text("\(text)\(cursor)")
                } else {
                    Text(text)
                }
            }
            .font(Theme.display(StoryArt.messageFontSize(for: text) * scale))
            .minimumScaleFactor(0.3)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: text) { lastEdit = .now }
    }
}

/// Lined note paper for the message side, laid out at 600pt and scaled to any square,
/// so the editable board in the send flow matches the rendered puzzle exactly.
struct MessagePaper<Message: View>: View {
    let from: String
    @ViewBuilder var message: (_ scale: CGFloat) -> Message

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / 600
            ZStack {
                Theme.paper
                Canvas { context, size in
                    for y in stride(from: 56 * scale, to: size.height, by: 48 * scale) {
                        context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 3 * scale)),
                                     with: .color(Theme.sand))
                    }
                }
                VStack(alignment: .leading, spacing: 24 * scale) {
                    message(scale)
                    Text("— \(from)")
                        .font(Theme.body(32 * scale, weight: .bold))
                        .foregroundStyle(Theme.orange)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .foregroundStyle(Theme.ink)
                .padding(48 * scale)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

extension UIImage {
    /// Center-crops to a square (and bakes in orientation), capped at `maxSide` pixels.
    func squareCropped(maxSide: CGFloat = 1200) -> UIImage {
        let side = min(size.width, size.height)
        let target = min(side * scale, maxSide)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: target, height: target), format: format).image { _ in
            let ratio = target / side
            let drawSize = CGSize(width: size.width * ratio, height: size.height * ratio)
            draw(in: CGRect(x: (target - drawSize.width) / 2, y: (target - drawSize.height) / 2,
                            width: drawSize.width, height: drawSize.height))
        }
    }

    /// Cuts the image into n×n tiles, row by row. Tile id k lives at index k-1.
    func slices(_ n: Int) -> [UIImage] {
        guard let cg = cgImage else { return [] }
        let w = cg.width / n, h = cg.height / n
        return (0..<(n * n)).compactMap { i in
            cg.cropping(to: CGRect(x: (i % n) * w, y: (i / n) * h, width: w, height: h))
                .map { UIImage(cgImage: $0) }
        }
    }
}
