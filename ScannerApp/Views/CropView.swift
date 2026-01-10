import SwiftUI
import UIKit

struct CropView: View {
    let originalImage: UIImage
    let initialCorners: [CGPoint]?
    let onCancel: () -> Void
    let onApply: ([CGPoint]) -> Void

    @State private var corners: [CGPoint] = []
    @State private var currentViewSize: CGSize = .zero
    @State private var imageFrame: CGRect = .zero
    @State private var activeHandleIndex: Int? = nil
    @State private var magnifierPosition: CGPoint = .zero
    @State private var showMagnifier = false

    private let handleSize: CGFloat = 24
    private let edgeHandleSize: CGFloat = 14
    private let magnifierSize: CGFloat = 120
    private let magnifierZoom: CGFloat = 2.5

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Button("Cancel") {
                        onCancel()
                    }
                    .foregroundColor(.red)
                    .font(.system(size: 17))

                    Spacer()

                    Text("Crop")
                        .font(.headline)
                        .foregroundColor(.white)

                    Spacer()

                    Button("Done") {
                        let imageCorners = convertCornersToImageCoordinates()
                        onApply(imageCorners)
                    }
                    .foregroundColor(.blue)
                    .font(.system(size: 17, weight: .semibold))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                // Image with crop overlay
                GeometryReader { geometry in
                    ZStack {
                        Image(uiImage: originalImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        if !corners.isEmpty {
                            // Dimmed overlay outside crop area
                            CropMaskView(corners: corners, bounds: geometry.size)

                            // Crop border
                            CropBorderView(corners: corners)

                            // Corner handles
                            ForEach(0..<4, id: \.self) { index in
                                CornerHandleView(
                                    position: $corners[index],
                                    size: handleSize,
                                    onDragStart: { handleDragStart(index: index) },
                                    onDragChanged: { pos in handleDragChanged(index: index, position: pos) },
                                    onDragEnded: { handleDragEnded() }
                                )
                            }

                            // Edge handles (midpoints)
                            ForEach(0..<4, id: \.self) { index in
                                let nextIndex = (index + 1) % 4
                                let midpoint = CGPoint(
                                    x: (corners[index].x + corners[nextIndex].x) / 2,
                                    y: (corners[index].y + corners[nextIndex].y) / 2
                                )
                                EdgeHandleView(
                                    midpoint: midpoint,
                                    isHorizontal: index == 0 || index == 2,
                                    onDragChanged: { delta in
                                        handleEdgeDrag(index: index, delta: delta)
                                    },
                                    onDragStart: { handleDragStart(index: index + 10) },
                                    onDragEnded: { handleDragEnded() }
                                )
                            }
                        }

                        // Magnifier loupe
                        if showMagnifier {
                            MagnifierView(
                                image: originalImage,
                                position: magnifierPosition,
                                imageFrame: imageFrame,
                                size: magnifierSize,
                                zoom: magnifierZoom
                            )
                        }
                    }
                    .onAppear {
                        currentViewSize = geometry.size
                        imageFrame = calculateImageFrame(in: geometry.size)
                        initializeCorners()
                    }
                    .onChange(of: geometry.size) { newSize in
                        currentViewSize = newSize
                        imageFrame = calculateImageFrame(in: newSize)
                        if corners.isEmpty {
                            initializeCorners()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Calculations

    private func calculateImageFrame(in containerSize: CGSize) -> CGRect {
        let imageSize = originalImage.size
        guard imageSize.width > 0 && imageSize.height > 0 else { return .zero }

        let scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        let scaledWidth = imageSize.width * scale
        let scaledHeight = imageSize.height * scale
        let x = (containerSize.width - scaledWidth) / 2
        let y = (containerSize.height - scaledHeight) / 2

        return CGRect(x: x, y: y, width: scaledWidth, height: scaledHeight)
    }

    private func initializeCorners() {
        guard corners.isEmpty && imageFrame.width > 0 else { return }

        if let initial = initialCorners, initial.count == 4 {
            // Convert from image coordinates to view coordinates
            let scaleX = imageFrame.width / originalImage.size.width
            let scaleY = imageFrame.height / originalImage.size.height

            corners = initial.map { corner in
                CGPoint(
                    x: imageFrame.origin.x + corner.x * scaleX,
                    y: imageFrame.origin.y + corner.y * scaleY
                )
            }
        } else {
            // Default to image bounds with padding
            let padding: CGFloat = 20
            corners = [
                CGPoint(x: imageFrame.minX + padding, y: imageFrame.minY + padding),
                CGPoint(x: imageFrame.maxX - padding, y: imageFrame.minY + padding),
                CGPoint(x: imageFrame.maxX - padding, y: imageFrame.maxY - padding),
                CGPoint(x: imageFrame.minX + padding, y: imageFrame.maxY - padding)
            ]
        }
    }

    private func convertCornersToImageCoordinates() -> [CGPoint] {
        guard !corners.isEmpty && imageFrame.width > 0 else { return [] }

        let scaleX = originalImage.size.width / imageFrame.width
        let scaleY = originalImage.size.height / imageFrame.height

        return corners.map { corner in
            CGPoint(
                x: (corner.x - imageFrame.origin.x) * scaleX,
                y: (corner.y - imageFrame.origin.y) * scaleY
            )
        }
    }

    // MARK: - Drag Handling

    private func handleDragStart(index: Int) {
        activeHandleIndex = index
        showMagnifier = true
    }

    private func handleDragChanged(index: Int, position: CGPoint) {
        guard index < corners.count else { return }

        // Clamp to image bounds
        let clampedX = max(imageFrame.minX, min(imageFrame.maxX, position.x))
        let clampedY = max(imageFrame.minY, min(imageFrame.maxY, position.y))

        corners[index] = CGPoint(x: clampedX, y: clampedY)
        magnifierPosition = CGPoint(x: clampedX, y: clampedY)
    }

    private func handleEdgeDrag(index: Int, delta: CGSize) {
        let nextIndex = (index + 1) % 4

        // For top/bottom edges (0 and 2), move vertically
        // For left/right edges (1 and 3), move horizontally
        if index == 0 || index == 2 {
            // Top or bottom edge - move both corners vertically
            let newY1 = max(imageFrame.minY, min(imageFrame.maxY, corners[index].y + delta.height))
            let newY2 = max(imageFrame.minY, min(imageFrame.maxY, corners[nextIndex].y + delta.height))
            corners[index].y = newY1
            corners[nextIndex].y = newY2

            magnifierPosition = CGPoint(
                x: (corners[index].x + corners[nextIndex].x) / 2,
                y: newY1
            )
        } else {
            // Left or right edge - move both corners horizontally
            let newX1 = max(imageFrame.minX, min(imageFrame.maxX, corners[index].x + delta.width))
            let newX2 = max(imageFrame.minX, min(imageFrame.maxX, corners[nextIndex].x + delta.width))
            corners[index].x = newX1
            corners[nextIndex].x = newX2

            magnifierPosition = CGPoint(
                x: newX1,
                y: (corners[index].y + corners[nextIndex].y) / 2
            )
        }
    }

    private func handleDragEnded() {
        activeHandleIndex = nil
        showMagnifier = false
    }
}

// MARK: - Corner Handle

struct CornerHandleView: View {
    @Binding var position: CGPoint
    let size: CGFloat
    let onDragStart: () -> Void
    let onDragChanged: (CGPoint) -> Void
    let onDragEnded: () -> Void

    var body: some View {
        Circle()
            .fill(Color.cyan)
            .frame(width: size, height: size)
            .overlay(Circle().stroke(Color.white, lineWidth: 3))
            .position(position)
            .gesture(
                DragGesture(coordinateSpace: .local)
                    .onChanged { value in
                        if value.translation == .zero {
                            onDragStart()
                        }
                        onDragChanged(value.location)
                    }
                    .onEnded { _ in
                        onDragEnded()
                    }
            )
    }
}

// MARK: - Edge Handle

struct EdgeHandleView: View {
    let midpoint: CGPoint
    let isHorizontal: Bool
    let onDragChanged: (CGSize) -> Void
    let onDragStart: () -> Void
    let onDragEnded: () -> Void

    @State private var lastDragValue: CGSize = .zero

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.cyan)
            .frame(
                width: isHorizontal ? 40 : 14,
                height: isHorizontal ? 14 : 40
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.white, lineWidth: 2)
            )
            .position(midpoint)
            .gesture(
                DragGesture(coordinateSpace: .local)
                    .onChanged { value in
                        if lastDragValue == .zero {
                            onDragStart()
                        }
                        let delta = CGSize(
                            width: value.translation.width - lastDragValue.width,
                            height: value.translation.height - lastDragValue.height
                        )
                        lastDragValue = value.translation
                        onDragChanged(delta)
                    }
                    .onEnded { _ in
                        lastDragValue = .zero
                        onDragEnded()
                    }
            )
    }
}

// MARK: - Crop Border

struct CropBorderView: View {
    let corners: [CGPoint]

    var body: some View {
        CropShapePath(corners: corners)
            .stroke(Color.cyan, lineWidth: 2)
    }
}

struct CropShapePath: Shape {
    let corners: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard corners.count >= 4 else { return path }

        path.move(to: corners[0])
        for i in 1..<corners.count {
            path.addLine(to: corners[i])
        }
        path.closeSubpath()

        return path
    }
}

// MARK: - Crop Mask (Dimmed Area)

struct CropMaskView: View {
    let corners: [CGPoint]
    let bounds: CGSize

    var body: some View {
        Canvas { context, size in
            // Fill entire area with semi-transparent black
            let fullRect = Path(CGRect(origin: .zero, size: size))
            context.fill(fullRect, with: .color(.black.opacity(0.5)))

            // Cut out the crop area
            var cropPath = Path()
            guard corners.count >= 4 else { return }
            cropPath.move(to: corners[0])
            for i in 1..<corners.count {
                cropPath.addLine(to: corners[i])
            }
            cropPath.closeSubpath()

            context.blendMode = .destinationOut
            context.fill(cropPath, with: .color(.black))
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Magnifier

struct MagnifierView: View {
    let image: UIImage
    let position: CGPoint
    let imageFrame: CGRect
    let size: CGFloat
    let zoom: CGFloat

    private var magnifierOffset: CGFloat {
        size / 2 + 40 // Position above the handle
    }

    var body: some View {
        let displayPosition = CGPoint(
            x: position.x,
            y: max(size / 2 + 10, position.y - magnifierOffset)
        )

        ZStack {
            // Zoomed image portion
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(
                    width: imageFrame.width * zoom,
                    height: imageFrame.height * zoom
                )
                .offset(
                    x: -(position.x - imageFrame.origin.x) * zoom + size / 2,
                    y: -(position.y - imageFrame.origin.y) * zoom + size / 2
                )
                .frame(width: size, height: size)
                .clipShape(Circle())

            // Corner indicator lines
            Path { path in
                // Crosshair
                let center = size / 2
                let lineLength: CGFloat = 20

                path.move(to: CGPoint(x: center - lineLength, y: center))
                path.addLine(to: CGPoint(x: center + lineLength, y: center))
                path.move(to: CGPoint(x: center, y: center - lineLength))
                path.addLine(to: CGPoint(x: center, y: center + lineLength))
            }
            .stroke(Color.cyan, lineWidth: 1)
            .frame(width: size, height: size)

            // Border
            Circle()
                .stroke(Color.white, lineWidth: 3)
                .frame(width: size, height: size)
        }
        .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
        .position(displayPosition)
    }
}
