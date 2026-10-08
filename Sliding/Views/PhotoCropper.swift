//
//  PhotoCropper.swift
//  Sliding
//

import SwiftUI

/// Pinch and drag a photo inside a square frame to choose the crop.
///
/// Zoom runs from 1 (the photo just fills the frame) up to `maxScale`. Pinching out past 1, zooming
/// in past the max, or dragging an edge into the frame stretches with resistance, and springs back
/// on release. `scale` and `offset` are the crop: offset is in units of the frame's side, so the
/// same values work at any size and can be applied to the full-resolution photo afterward.
struct PhotoCropper: View {
    let image: UIImage
    @Binding var scale: CGFloat
    @Binding var offset: CGSize

    static let maxScale: CGFloat = 4
    /// How much of an over-pull shows while stretching past a limit.
    private static let resistance: CGFloat = 0.3

    @State private var startScale: CGFloat?
    @State private var startOffset: CGSize?

    var body: some View {
        GeometryReader { geo in
            let side = geo.size.width
            let shownScale = Self.rubberBanded(scale, min: 1, max: Self.maxScale)
            let size = Self.coverSize(of: image.size, scale: shownScale)
            let shownOffset = Self.rubberBanded(offset, coverSize: size)

            Image(uiImage: image)
                .resizable()
                .frame(width: size.width * side, height: size.height * side)
                .offset(x: shownOffset.width * side, y: shownOffset.height * side)
                .frame(width: side, height: side)
                .contentShape(Rectangle())
                .gesture(
                    SimultaneousGesture(
                        MagnifyGesture()
                            .onChanged { value in
                                if startScale == nil { startScale = scale }
                                scale = (startScale ?? 1) * value.magnification
                            }
                            .onEnded { _ in
                                startScale = nil
                                settle()
                            },
                        DragGesture()
                            .onChanged { value in
                                if startOffset == nil { startOffset = offset }
                                let start = startOffset ?? .zero
                                offset = CGSize(width: start.width + value.translation.width / side,
                                                height: start.height + value.translation.height / side)
                            }
                            .onEnded { _ in
                                startOffset = nil
                                settle()
                            }
                    )
                )
        }
        .aspectRatio(1, contentMode: .fit)
        .clipped()
        .accessibilityLabel("Photo crop")
        .accessibilityHint("Pinch to zoom and drag to frame the photo.")
    }

    /// Spring back inside the limits once fingers lift.
    private func settle() {
        guard startScale == nil, startOffset == nil else { return }
        let clampedScale = min(max(scale, 1), Self.maxScale)
        let limits = Self.offsetLimits(Self.coverSize(of: image.size, scale: clampedScale))
        let clampedOffset = CGSize(width: min(max(offset.width, -limits.width), limits.width),
                                   height: min(max(offset.height, -limits.height), limits.height))
        withAnimation(.spring(duration: 0.4, bounce: 0.25)) {
            scale = clampedScale
            offset = clampedOffset
        }
    }

    /// The photo's displayed size in units of the frame's side, covering the frame at scale 1.
    static func coverSize(of imageSize: CGSize, scale: CGFloat) -> CGSize {
        let shortSide = min(imageSize.width, imageSize.height)
        return CGSize(width: imageSize.width / shortSide * scale, height: imageSize.height / shortSide * scale)
    }

    /// How far the photo can move before an edge would come inside the frame.
    static func offsetLimits(_ coverSize: CGSize) -> CGSize {
        CGSize(width: max(0, (coverSize.width - 1) / 2), height: max(0, (coverSize.height - 1) / 2))
    }

    private static func rubberBanded(_ value: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
        if value < lower { return lower - (lower - value) * resistance }
        if value > upper { return upper + (value - upper) * resistance }
        return value
    }

    private static func rubberBanded(_ offset: CGSize, coverSize: CGSize) -> CGSize {
        let limits = offsetLimits(coverSize)
        func band(_ value: CGFloat, _ limit: CGFloat) -> CGFloat {
            rubberBanded(value, min: -limit, max: limit)
        }
        return CGSize(width: band(offset.width, limits.width), height: band(offset.height, limits.height))
    }
}

extension UIImage {
    /// Redraws the photo upright, at most `maxSide` pixels on its long edge, so its pixels match what's shown.
    func normalized(maxSide: CGFloat = 2400) -> UIImage {
        let longSide = max(size.width, size.height) * scale
        let factor = min(1, maxSide / longSide)
        let target = CGSize(width: (size.width * scale * factor).rounded(), height: (size.height * scale * factor).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// The square a `PhotoCropper` frame shows for this scale and offset, as its own image.
    func cropped(scale: CGFloat, offset: CGSize) -> UIImage {
        let cover = PhotoCropper.coverSize(of: size, scale: scale)
        let pointsPerUnit = size.width / cover.width   // photo points per frame side
        // Where the frame's top-left corner falls on the photo, measured from the photo's top-left.
        let originX = ((cover.width - 1) / 2 - offset.width) * pointsPerUnit
        let originY = ((cover.height - 1) / 2 - offset.height) * pointsPerUnit
        let rect = CGRect(x: originX * self.scale, y: originY * self.scale,
                          width: pointsPerUnit * self.scale, height: pointsPerUnit * self.scale).integral
        guard let cg = cgImage?.cropping(to: rect) else { return squareCropped() }
        return UIImage(cgImage: cg).squareCropped()
    }
}
