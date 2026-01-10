import SwiftUI
import UIKit
import Vision

struct CropView: View {
    let originalImage: UIImage
    let initialCorners: [CGPoint]?
    let onCancel: () -> Void
    let onApply: ([CGPoint]) -> Void

    @State private var corners: [CGPoint] = []
    @State private var currentViewSize: CGSize = .zero
    @State private var imageFrame: CGRect = .zero
    @State private var magnifierPosition: CGPoint = .zero
    @State private var showMagnifier = false
    @State private var isInitialized = false

    private let handleSize: CGFloat = 24
    private let magnifierSize: CGFloat = 140
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
                    .foregroundColor(AppColors.accent)
                    .font(.system(size: 17, weight: .bold))
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
                                CropCornerHandle(
                                    position: corners[index],
                                    size: handleSize,
                                    onDragChanged: { newPosition in
                                        handleCornerDrag(index: index, position: newPosition)
                                    },
                                    onDragStarted: {
                                        showMagnifier = true
                                    },
                                    onDragEnded: {
                                        showMagnifier = false
                                    }
                                )
                            }

                            // Edge handles (midpoints)
                            ForEach(0..<4, id: \.self) { index in
                                let nextIndex = (index + 1) % 4
                                let midpoint = CGPoint(
                                    x: (corners[index].x + corners[nextIndex].x) / 2,
                                    y: (corners[index].y + corners[nextIndex].y) / 2
                                )
                                // Calculate edge angle from the two corner points
                                let edgeAngle = atan2(
                                    corners[nextIndex].y - corners[index].y,
                                    corners[nextIndex].x - corners[index].x
                                )
                                CropEdgeHandle(
                                    position: midpoint,
                                    angle: edgeAngle,
                                    onDragChanged: { newPosition in
                                        handleEdgeDrag(index: index, position: newPosition)
                                    },
                                    onDragStarted: {
                                        showMagnifier = true
                                    },
                                    onDragEnded: {
                                        showMagnifier = false
                                    }
                                )
                            }
                        }

                        // Magnifier loupe
                        if showMagnifier && imageFrame.width > 0 {
                            CropMagnifierView(
                                image: originalImage,
                                focusPoint: magnifierPosition,
                                corners: corners,
                                imageFrame: imageFrame,
                                size: magnifierSize,
                                zoom: magnifierZoom
                            )
                        }
                    }
                    .coordinateSpace(name: "cropArea")
                    .onAppear {
                        currentViewSize = geometry.size
                        imageFrame = calculateImageFrame(in: geometry.size)
                        initializeCornersIfNeeded()
                    }
                    .onChange(of: geometry.size) { newSize in
                        currentViewSize = newSize
                        imageFrame = calculateImageFrame(in: newSize)
                        if !isInitialized {
                            initializeCornersIfNeeded()
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

    private func initializeCornersIfNeeded() {
        guard !isInitialized && imageFrame.width > 0 else { return }
        isInitialized = true

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
            // Try to detect rectangle using Vision
            detectRectangle()
        }
    }

    private func detectRectangle() {
        guard let cgImage = originalImage.cgImage else {
            setDefaultCorners()
            return
        }

        let request = VNDetectRectanglesRequest { request, error in
            DispatchQueue.main.async {
                if let results = request.results as? [VNRectangleObservation],
                   let rect = results.first {
                    // Convert Vision coordinates to view coordinates
                    let scaleX = imageFrame.width
                    let scaleY = imageFrame.height

                    // Vision coordinates: origin bottom-left, normalized 0-1
                    corners = [
                        CGPoint(
                            x: imageFrame.origin.x + rect.topLeft.x * scaleX,
                            y: imageFrame.origin.y + (1 - rect.topLeft.y) * scaleY
                        ),
                        CGPoint(
                            x: imageFrame.origin.x + rect.topRight.x * scaleX,
                            y: imageFrame.origin.y + (1 - rect.topRight.y) * scaleY
                        ),
                        CGPoint(
                            x: imageFrame.origin.x + rect.bottomRight.x * scaleX,
                            y: imageFrame.origin.y + (1 - rect.bottomRight.y) * scaleY
                        ),
                        CGPoint(
                            x: imageFrame.origin.x + rect.bottomLeft.x * scaleX,
                            y: imageFrame.origin.y + (1 - rect.bottomLeft.y) * scaleY
                        )
                    ]
                } else {
                    setDefaultCorners()
                }
            }
        }

        request.minimumAspectRatio = 0.3
        request.maximumAspectRatio = 1.0
        request.minimumSize = 0.2
        request.maximumObservations = 1
        request.minimumConfidence = 0.5

        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            try? handler.perform([request])
        }
    }

    private func setDefaultCorners() {
        let padding: CGFloat = 20
        corners = [
            CGPoint(x: imageFrame.minX + padding, y: imageFrame.minY + padding),
            CGPoint(x: imageFrame.maxX - padding, y: imageFrame.minY + padding),
            CGPoint(x: imageFrame.maxX - padding, y: imageFrame.maxY - padding),
            CGPoint(x: imageFrame.minX + padding, y: imageFrame.maxY - padding)
        ]
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

    private func handleCornerDrag(index: Int, position: CGPoint) {
        guard index < corners.count else { return }

        // Clamp to image bounds
        let clampedX = max(imageFrame.minX, min(imageFrame.maxX, position.x))
        let clampedY = max(imageFrame.minY, min(imageFrame.maxY, position.y))

        corners[index] = CGPoint(x: clampedX, y: clampedY)
        magnifierPosition = CGPoint(x: clampedX, y: clampedY)
    }

    private func handleEdgeDrag(index: Int, position: CGPoint) {
        let nextIndex = (index + 1) % 4

        // For top/bottom edges (0 and 2), move vertically
        // For left/right edges (1 and 3), move horizontally
        if index == 0 || index == 2 {
            // Top or bottom edge - move both corners vertically
            let clampedY = max(imageFrame.minY, min(imageFrame.maxY, position.y))
            let deltaY = clampedY - (corners[index].y + corners[nextIndex].y) / 2

            corners[index].y = max(imageFrame.minY, min(imageFrame.maxY, corners[index].y + deltaY))
            corners[nextIndex].y = max(imageFrame.minY, min(imageFrame.maxY, corners[nextIndex].y + deltaY))

            // Use edge midpoint X, not finger position - magnifier should only move vertically for horizontal edges
            let midpointX = (corners[index].x + corners[nextIndex].x) / 2
            magnifierPosition = CGPoint(x: midpointX, y: clampedY)
        } else {
            // Left or right edge - move both corners horizontally
            let clampedX = max(imageFrame.minX, min(imageFrame.maxX, position.x))
            let deltaX = clampedX - (corners[index].x + corners[nextIndex].x) / 2

            corners[index].x = max(imageFrame.minX, min(imageFrame.maxX, corners[index].x + deltaX))
            corners[nextIndex].x = max(imageFrame.minX, min(imageFrame.maxX, corners[nextIndex].x + deltaX))

            // Use edge midpoint Y, not finger position - magnifier should only move horizontally for vertical edges
            let midpointY = (corners[index].y + corners[nextIndex].y) / 2
            magnifierPosition = CGPoint(x: clampedX, y: midpointY)
        }
    }
}

// MARK: - Corner Handle

struct CropCornerHandle: View {
    let position: CGPoint
    let size: CGFloat
    let onDragChanged: (CGPoint) -> Void
    let onDragStarted: () -> Void
    let onDragEnded: () -> Void

    @State private var isDragging = false

    var body: some View {
        Circle()
            .fill(AppColors.accent)
            .frame(width: size, height: size)
            .overlay(Circle().stroke(Color.white, lineWidth: 3))
            .position(position)
            .gesture(
                DragGesture(coordinateSpace: .named("cropArea"))
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            onDragStarted()
                        }
                        onDragChanged(value.location)
                    }
                    .onEnded { _ in
                        isDragging = false
                        onDragEnded()
                    }
            )
    }
}

// MARK: - Edge Handle

struct CropEdgeHandle: View {
    let position: CGPoint
    let angle: CGFloat  // Angle of the edge in radians
    let onDragChanged: (CGPoint) -> Void
    let onDragStarted: () -> Void
    let onDragEnded: () -> Void

    @State private var isDragging = false

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(AppColors.accent)
            .frame(width: 40, height: 14)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.white, lineWidth: 2)
            )
            .rotationEffect(Angle(radians: angle))
            .position(position)
            .gesture(
                DragGesture(coordinateSpace: .named("cropArea"))
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            onDragStarted()
                        }
                        onDragChanged(value.location)
                    }
                    .onEnded { _ in
                        isDragging = false
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
            .stroke(AppColors.accent, lineWidth: 2)
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

struct CropMagnifierView: View {
    let image: UIImage
    let focusPoint: CGPoint
    let corners: [CGPoint]
    let imageFrame: CGRect
    let size: CGFloat
    let zoom: CGFloat

    var body: some View {
        // Position magnifier above the focus point
        let displayY = max(size / 2 + 10, focusPoint.y - size / 2 - 50)
        let displayPosition = CGPoint(x: focusPoint.x, y: displayY)

        // Calculate the relative position within the image (0-1)
        let relX = (focusPoint.x - imageFrame.origin.x) / imageFrame.width
        let relY = (focusPoint.y - imageFrame.origin.y) / imageFrame.height

        // Clamp to valid range
        let clampedRelX = max(0, min(1, relX))
        let clampedRelY = max(0, min(1, relY))

        // Zoomed image dimensions
        let zoomedWidth = imageFrame.width * zoom
        let zoomedHeight = imageFrame.height * zoom

        // Offset to center the focus point in the magnifier
        // With center alignment (default), the image center is at the frame center,
        // so we need to offset from center (0.5) to the focus point
        let offsetX = (0.5 - clampedRelX) * zoomedWidth
        let offsetY = (0.5 - clampedRelY) * zoomedHeight

        // Transform corners to magnifier coordinate space
        let magnifierCorners = corners.map { corner -> CGPoint in
            let cornerRelX = (corner.x - imageFrame.origin.x) / imageFrame.width
            let cornerRelY = (corner.y - imageFrame.origin.y) / imageFrame.height
            // Position relative to focus point, scaled by zoom, centered in magnifier
            let magX = size / 2 + (cornerRelX - clampedRelX) * zoomedWidth
            let magY = size / 2 + (cornerRelY - clampedRelY) * zoomedHeight
            return CGPoint(x: magX, y: magY)
        }

        ZStack {
            // Zoomed image portion
            Image(uiImage: image)
                .resizable()
                .frame(width: zoomedWidth, height: zoomedHeight)
                .offset(x: offsetX, y: offsetY)
                .frame(width: size, height: size)
                .clipped()

            // Dark overlay outside crop area (in magnifier)
            if magnifierCorners.count >= 4 {
                MagnifierMaskView(corners: magnifierCorners, size: size)
            }

            // Blue crop border lines (in magnifier)
            if magnifierCorners.count >= 4 {
                MagnifierCropBorderView(corners: magnifierCorners, size: size)
            }

            // Crosshair
            Path { path in
                let center = size / 2
                let lineLength: CGFloat = 20
                let gap: CGFloat = 6

                // Horizontal lines with gap
                path.move(to: CGPoint(x: center - lineLength, y: center))
                path.addLine(to: CGPoint(x: center - gap, y: center))
                path.move(to: CGPoint(x: center + gap, y: center))
                path.addLine(to: CGPoint(x: center + lineLength, y: center))

                // Vertical lines with gap
                path.move(to: CGPoint(x: center, y: center - lineLength))
                path.addLine(to: CGPoint(x: center, y: center - gap))
                path.move(to: CGPoint(x: center, y: center + gap))
                path.addLine(to: CGPoint(x: center, y: center + lineLength))
            }
            .stroke(AppColors.accent, lineWidth: 1.5)
            .frame(width: size, height: size)

            // Border
            Circle()
                .stroke(Color.white, lineWidth: 3)
                .frame(width: size, height: size)
        }
        .clipShape(Circle())
        .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 5)
        .position(displayPosition)
    }
}

// MARK: - Magnifier Mask (Darkened area outside crop in magnifier)

struct MagnifierMaskView: View {
    let corners: [CGPoint]
    let size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            // Create full circle path
            let circlePath = Path(ellipseIn: CGRect(origin: .zero, size: canvasSize))

            // Create crop quadrilateral path
            var cropPath = Path()
            cropPath.move(to: corners[0])
            for i in 1..<corners.count {
                cropPath.addLine(to: corners[i])
            }
            cropPath.closeSubpath()

            // Fill the circle with semi-transparent dark
            context.fill(circlePath, with: .color(.black.opacity(0.4)))

            // Cut out the crop area
            context.blendMode = .destinationOut
            context.fill(cropPath, with: .color(.black))
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }
}

// MARK: - Magnifier Crop Border (Blue edges in magnifier)

struct MagnifierCropBorderView: View {
    let corners: [CGPoint]
    let size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            guard corners.count >= 4 else { return }

            // Draw the crop border
            var path = Path()
            path.move(to: corners[0])
            for i in 1..<corners.count {
                path.addLine(to: corners[i])
            }
            path.closeSubpath()

            context.stroke(path, with: .color(AppColors.accent), lineWidth: 3)
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }
}
