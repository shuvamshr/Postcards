//
//  Theme.swift
//  Sliding
//

import SwiftUI

/// Warm and soft: a cream page, sand-colored rounded rows, orange highlights with a wave pattern,
/// bright color blocks for photos, and rounded type. No outlines.
enum Theme {
    static let cream = Color(red: 0.953, green: 0.941, blue: 0.914)   // page
    static let sand = Color(red: 0.902, green: 0.890, blue: 0.859)    // rows, secondary buttons
    static let paper = Color(red: 0.992, green: 0.988, blue: 0.976)   // raised cards, message paper
    static let ink = Color(red: 0.16, green: 0.16, blue: 0.16)        // text
    static let muted = Color(red: 0.47, green: 0.46, blue: 0.43)      // secondary text
    static let orange = Color(red: 0.94, green: 0.54, blue: 0.30)     // highlight and primary action
    static let sky = Color(red: 0.36, green: 0.66, blue: 0.94)
    static let purple = Color(red: 0.60, green: 0.43, blue: 0.93)
    static let yellow = Color(red: 0.95, green: 0.80, blue: 0.30)
    static let green = Color(red: 0.32, green: 0.76, blue: 0.54)
    static let teal = Color(red: 0.20, green: 0.68, blue: 0.72)

    static let corner: CGFloat = 26
    /// Orange is reserved for "needs attention", so avatars draw from the other colors.
    private static let accents = [sky, purple, yellow, green, teal]

    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }

    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// A stable accent color per name, for avatars.
    static func accent(for name: String) -> Color {
        accents[name.unicodeScalars.reduce(0) { $0 + Int($1.value) } % accents.count]
    }
}

/// Soft diagonal waves, drawn over colored cards.
struct Waves: View {
    var color: Color = .white.opacity(0.13)
    var lineWidth: CGFloat = 9

    var body: some View {
        Canvas { context, size in
            let step = lineWidth * 4
            var start = -size.width * 0.6
            while start < size.height + size.width * 0.2 {
                var path = Path()
                var x: CGFloat = 0
                path.move(to: CGPoint(x: 0, y: start))
                while x <= size.width {
                    x += 4
                    let y = start + x * 0.45 + sin(x / (lineWidth * 7) * .pi * 2) * lineWidth
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                start += step
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    /// A flat rounded block.
    func softCard(_ fill: Color = Theme.sand, radius: CGFloat = Theme.corner) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// A colored rounded block with the wave pattern.
    func wavyCard(_ fill: Color = Theme.orange, radius: CGFloat = Theme.corner) -> some View {
        background {
            ZStack {
                fill
                Waves()
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }

    func screenBackground(_ color: Color = Theme.cream) -> some View {
        background(color.ignoresSafeArea())
    }

    /// A screen title in the display face, shown in the navigation bar.
    func screenTitle(_ title: String, color: Color = Theme.ink) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(Theme.display(18))
                        .foregroundStyle(color)
                }
            }
    }
}

/// The dark tray a puzzle sits in, like a physical slide puzzle.
struct PuzzleTray<Content: View>: View {
    var color = Theme.ink
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(8)
            .background(color, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
    }
}

/// Two-option switch with a sliding white knob, e.g. Photo / Message.
struct SegmentedSwitch: View {
    let options: [String]
    @Binding var selection: Int
    /// Light text on a faint track, for use on the dark puzzle tray.
    var onDark = false
    @Namespace private var knob

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                Button {
                    withAnimation(.spring(duration: 0.35)) { selection = index }
                } label: {
                    Text(options[index])
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(selection == index ? Theme.ink : (onDark ? .white.opacity(0.6) : Theme.muted))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .frame(minHeight: 38)
                        .background {
                            if selection == index {
                                Capsule().fill(Theme.paper).matchedGeometryEffect(id: "knob", in: knob)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == index ? .isSelected : [])
            }
        }
        .padding(4)
        .background(onDark ? .white.opacity(0.1) : Theme.sand, in: Capsule())
    }
}

/// A tilted card that gently sways and bobs, like it's resting on water.
/// Each card gets its own timing from `seed` so a group never moves in lockstep.
private struct Floaty: ViewModifier {
    let tilt: Double
    let seed: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var up = false

    func body(content: Content) -> some View {
        if reduceMotion {
            content.rotationEffect(.degrees(tilt))
        } else {
            content
                .rotationEffect(.degrees(tilt + (up ? 0.35 : -0.35)))
                .offset(y: up ? -1.5 : 1.5)
                .animation(.easeInOut(duration: 2.4 + seed * 1.4).repeatForever(autoreverses: true), value: up)
                .onAppear { up = true }
        }
    }
}

extension View {
    /// Tilt by `tilt` degrees with a slow floating motion. `seed` (0–1) varies the rhythm.
    func floaty(tilt: Double, seed: Double = 0.5) -> some View {
        modifier(Floaty(tilt: tilt, seed: seed))
    }
}

private struct DimWhenDisabled: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    func body(content: Content) -> some View {
        content.opacity(isEnabled ? 1 : 0.45)
    }
}

/// Full rounded button. Orange by default ("I want to give it"); pass sand for a secondary one.
struct PrimaryButtonStyle: ButtonStyle {
    var fill = Theme.orange
    var foreground = Color.white
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body(16, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
            .modifier(DimWhenDisabled())
    }
}

/// Small sand capsule.
struct ChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body(14, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(configuration.isPressed ? Theme.sand.opacity(0.6) : Theme.sand, in: Capsule())
            .modifier(DimWhenDisabled())
    }
}

/// Round icon button.
struct CircleButtonStyle: ButtonStyle {
    var fill = Theme.sand
    var foreground = Theme.ink
    var size: CGFloat = 52

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.system(size: size * 0.36, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(fill, in: Circle())
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
            .modifier(DimWhenDisabled())
    }
}
