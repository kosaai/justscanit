import SwiftUI
import Vision

struct EdgeOverlayView: View {
    let rectangle: VNRectangleObservation?
    let viewSize: CGSize

    // Video aspect ratio (4:3 for photo preset in portrait = 3:4)
    private let videoAspectRatio: CGFloat = 3.0 / 4.0

    var body: some View {
        GeometryReader { geometry in
            if let rect = rectangle {
                let videoFrame = calculateVideoFrame(in: geometry.size)

                Path { path in
                    let corners = getCorners(rect, videoFrame: videoFrame)
                    guard corners.count == 4 else { return }

                    path.move(to: corners[0])
                    path.addLine(to: corners[1])
                    path.addLine(to: corners[2])
                    path.addLine(to: corners[3])
                    path.closeSubpath()
                }
                .fill(Color.blue.opacity(0.2))

                Path { path in
                    let corners = getCorners(rect, videoFrame: videoFrame)
                    guard corners.count == 4 else { return }

                    path.move(to: corners[0])
                    path.addLine(to: corners[1])
                    path.addLine(to: corners[2])
                    path.addLine(to: corners[3])
                    path.closeSubpath()
                }
                .stroke(Color.blue, lineWidth: 3)

                // Corner indicators
                ForEach(0..<4, id: \.self) { index in
                    let corners = getCorners(rect, videoFrame: videoFrame)
                    if index < corners.count {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 12, height: 12)
                            .position(corners[index])
                    }
                }
            }
        }
    }

    /// Calculate where the video frame is actually rendered within the view (resizeAspect letterboxing)
    private func calculateVideoFrame(in viewSize: CGSize) -> CGRect {
        let viewAspectRatio = viewSize.width / viewSize.height

        var videoWidth: CGFloat
        var videoHeight: CGFloat

        if videoAspectRatio < viewAspectRatio {
            // Video is taller than view - letterbox on sides (pillarboxing)
            videoHeight = viewSize.height
            videoWidth = videoHeight * videoAspectRatio
        } else {
            // Video is wider than view - letterbox on top/bottom
            videoWidth = viewSize.width
            videoHeight = videoWidth / videoAspectRatio
        }

        let x = (viewSize.width - videoWidth) / 2
        let y = (viewSize.height - videoHeight) / 2

        return CGRect(x: x, y: y, width: videoWidth, height: videoHeight)
    }

    private func getCorners(_ rect: VNRectangleObservation, videoFrame: CGRect) -> [CGPoint] {
        // Vision uses normalized coordinates (0-1) with origin at bottom-left
        // Convert to view coordinates within the video frame
        return [
            CGPoint(
                x: videoFrame.origin.x + rect.topLeft.x * videoFrame.width,
                y: videoFrame.origin.y + (1 - rect.topLeft.y) * videoFrame.height
            ),
            CGPoint(
                x: videoFrame.origin.x + rect.topRight.x * videoFrame.width,
                y: videoFrame.origin.y + (1 - rect.topRight.y) * videoFrame.height
            ),
            CGPoint(
                x: videoFrame.origin.x + rect.bottomRight.x * videoFrame.width,
                y: videoFrame.origin.y + (1 - rect.bottomRight.y) * videoFrame.height
            ),
            CGPoint(
                x: videoFrame.origin.x + rect.bottomLeft.x * videoFrame.width,
                y: videoFrame.origin.y + (1 - rect.bottomLeft.y) * videoFrame.height
            )
        ]
    }
}
