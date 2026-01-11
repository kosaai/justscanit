import SwiftUI
import Vision

struct EdgeOverlayView: View {
    let rectangle: VNRectangleObservation?
    let viewSize: CGSize

    var body: some View {
        GeometryReader { geometry in
            if let rect = rectangle {
                let corners = convertCorners(rect, in: geometry.size)

                // Fill
                Path { path in
                    path.move(to: corners[0])
                    path.addLine(to: corners[1])
                    path.addLine(to: corners[2])
                    path.addLine(to: corners[3])
                    path.closeSubpath()
                }
                .fill(AppColors.accent.opacity(0.15))

                // Stroke
                Path { path in
                    path.move(to: corners[0])
                    path.addLine(to: corners[1])
                    path.addLine(to: corners[2])
                    path.addLine(to: corners[3])
                    path.closeSubpath()
                }
                .stroke(AppColors.accent, lineWidth: 2)

                // Corner dots
                ForEach(0..<4, id: \.self) { index in
                    Circle()
                        .fill(AppColors.accent)
                        .frame(width: 10, height: 10)
                        .position(corners[index])
                }
            }
        }
    }

    private func convertCorners(_ rect: VNRectangleObservation, in size: CGSize) -> [CGPoint] {
        // Vision coordinates: normalized (0-1), origin at bottom-left
        // View coordinates: pixels, origin at top-left
        // Camera uses resizeAspectFill: video is scaled to fill and may be cropped

        // Camera captures 4:3 in landscape -> 3:4 in portrait = 0.75 aspect ratio
        let cameraAspect: CGFloat = 3.0 / 4.0
        let viewAspect = size.width / size.height

        var scaleX: CGFloat = 1.0
        var scaleY: CGFloat = 1.0
        var offsetX: CGFloat = 0.0
        var offsetY: CGFloat = 0.0

        if viewAspect < cameraAspect {
            // View is narrower - sides are cropped
            let visibleWidthRatio = viewAspect / cameraAspect
            offsetX = (1.0 - visibleWidthRatio) / 2.0
            scaleX = visibleWidthRatio
        } else {
            // View is wider - top/bottom are cropped
            let visibleHeightRatio = cameraAspect / viewAspect
            offsetY = (1.0 - visibleHeightRatio) / 2.0
            scaleY = visibleHeightRatio
        }

        func transform(_ point: CGPoint) -> CGPoint {
            let adjustedX = (point.x - offsetX) / scaleX
            let adjustedY = (point.y - offsetY) / scaleY
            return CGPoint(
                x: adjustedX * size.width,
                y: (1 - adjustedY) * size.height
            )
        }

        return [
            transform(rect.topLeft),
            transform(rect.topRight),
            transform(rect.bottomRight),
            transform(rect.bottomLeft)
        ]
    }
}
