import SwiftUI
import AVFoundation
import Vision
import UIKit

struct ScannerView: View {
    @StateObject private var cameraManager = CameraManager()
    @Binding var capturedImage: UIImage?
    @Binding var detectedRectangle: VNRectangleObservation?
    @Binding var currentDocument: ScannedDocument?
    let onCapture: () -> Void
    let onDismiss: () -> Void
    let onFinish: () -> Void

    @State private var showCaptureAnimation = false
    @State private var scannedPages: [ScannedPageThumbnail] = []
    @State private var isHoldingSteady = false
    @State private var steadyTimer: Timer?
    @State private var lastStableRectangle: VNRectangleObservation?
    @State private var steadyProgress: CGFloat = 0
    @State private var cameraViewSize: CGSize = .zero
    @State private var captureMode: CaptureMode = .auto

    // Capture animation state
    @State private var captureAnimationData: CaptureAnimationData?
    @State private var showCapturePreview = false
    @State private var capturePreviewPhase: CapturePreviewPhase = .initial
    @State private var isAnimatingCapture = false  // Prevents new captures during animation

    private let steadyDuration: TimeInterval = 1.0

    private var lightIconName: String {
        switch cameraManager.lightMode {
        case .auto: return "bolt.badge.automatic"
        case .on: return "bolt.fill"
        case .off: return "bolt.slash"
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let screenHeight = geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom
            let screenWidth = geometry.size.width

            // 75% for camera, 25% for thumbnails (of total screen height)
            let thumbnailAreaHeight: CGFloat = screenHeight * 0.25
            let cameraAreaHeight: CGFloat = screenHeight - thumbnailAreaHeight

            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Camera section (75%)
                    ZStack {
                        // Camera preview
                        CameraPreviewView(session: cameraManager.session)
                            .background(
                                GeometryReader { camGeo in
                                    Color.clear.onAppear {
                                        cameraViewSize = camGeo.size
                                    }
                                    .onChange(of: camGeo.size) { newSize in
                                        cameraViewSize = newSize
                                    }
                                }
                            )

                        // Edge detection overlay
                        if cameraViewSize != .zero {
                            EdgeOverlayView(
                                rectangle: cameraManager.detectedRectangle,
                                viewSize: cameraViewSize
                            )
                        }

                        // Capture flash
                        if showCaptureAnimation {
                            Color.white
                                .transition(.opacity)
                        }

                        // Capture preview animation
                        if let animData = captureAnimationData, showCapturePreview {
                            CapturePreviewAnimation(
                                data: animData,
                                phase: capturePreviewPhase,
                                viewSize: cameraViewSize
                            )
                        }

                        // UI Overlay
                        VStack {
                            // Top: Close button
                            HStack {
                                Button(action: onDismiss) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(width: 32, height: 32)
                                        .background(Color.black.opacity(0.5))
                                        .clipShape(Circle())
                                }
                                Spacer()
                            }
                            .padding(.leading, 16)
                            .padding(.top, geometry.safeAreaInsets.top + 8)

                            Spacer()

                            // Center-bottom: Status badge (only in auto mode)
                            if captureMode == .auto {
                                StatusBadge(
                                    isDetected: cameraManager.detectedRectangle != nil,
                                    isHoldingSteady: isHoldingSteady,
                                    progress: steadyProgress
                                )
                            }

                            // Bottom: Action buttons
                            HStack {
                                // Settings menu (3 dots)
                                Menu {
                                    // Light settings
                                    Menu {
                                        ForEach(LightMode.allCases, id: \.self) { mode in
                                            Button {
                                                cameraManager.setTorchMode(mode)
                                            } label: {
                                                HStack {
                                                    Text(mode.rawValue)
                                                    if cameraManager.lightMode == mode {
                                                        Image(systemName: "checkmark")
                                                    }
                                                }
                                            }
                                        }
                                    } label: {
                                        Label("Light", systemImage: lightIconName)
                                    }

                                    // Capture mode settings
                                    Menu {
                                        ForEach(CaptureMode.allCases, id: \.self) { mode in
                                            Button {
                                                captureMode = mode
                                                if mode == .manual {
                                                    resetSteadyState()
                                                }
                                            } label: {
                                                HStack {
                                                    Text(mode.rawValue)
                                                    if captureMode == mode {
                                                        Image(systemName: "checkmark")
                                                    }
                                                }
                                            }
                                        }
                                    } label: {
                                        Label("Capture", systemImage: "camera")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .font(.system(size: 20))
                                        .foregroundColor(.white)
                                        .frame(width: 44, height: 44)
                                        .background(Color.black.opacity(0.5))
                                        .clipShape(Circle())
                                }

                                Spacer()

                                // Manual capture button (only in manual mode)
                                if captureMode == .manual {
                                    Button(action: manualCapture) {
                                        ZStack {
                                            Circle()
                                                .stroke(Color.white, lineWidth: 3)
                                                .frame(width: 66, height: 66)
                                            Circle()
                                                .fill(Color.white)
                                                .frame(width: 54, height: 54)
                                        }
                                    }
                                    .disabled(cameraManager.isCapturing)
                                }

                                Spacer()

                                if !scannedPages.isEmpty {
                                    Button(action: deleteLastPage) {
                                        Image(systemName: "trash")
                                            .font(.system(size: 20))
                                            .foregroundColor(.white)
                                            .frame(width: 44, height: 44)
                                            .background(Color.black.opacity(0.5))
                                            .clipShape(Circle())
                                    }
                                }

                                Button(action: finishScanning) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(width: 52, height: 52)
                                        .background(
                                            Circle().fill(scannedPages.isEmpty ? Color.gray : Color.blue)
                                        )
                                }
                                .disabled(scannedPages.isEmpty)
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                        }
                    }
                    .frame(height: cameraAreaHeight)
                    .clipped()

                    // Thumbnail section (25%)
                    VStack(spacing: 0) {
                        ThumbnailStrip(
                            pages: scannedPages,
                            stripHeight: thumbnailAreaHeight - geometry.safeAreaInsets.bottom
                        )

                        // Bottom safe area spacer
                        Spacer()
                            .frame(height: geometry.safeAreaInsets.bottom)
                    }
                    .frame(height: thumbnailAreaHeight)
                    .background(Color.black)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            cameraManager.setupCamera()
            cameraManager.startSession()
            loadExistingPages()
        }
        .onDisappear {
            cameraManager.stopSession()
            steadyTimer?.invalidate()
        }
        .onChange(of: cameraManager.detectedRectangle) { (newRect: VNRectangleObservation?) in
            handleRectangleDetection(newRect)
        }
        .onChange(of: cameraManager.capturedImage) { (newImage: UIImage?) in
            if let image = newImage {
                handleCapturedImage(image)
            }
        }
    }

    // MARK: - Auto-capture Logic

    private func handleRectangleDetection(_ newRect: VNRectangleObservation?) {
        // Only handle auto-capture in auto mode
        guard captureMode == .auto else { return }

        // Don't process during capture animation
        guard !isAnimatingCapture else { return }

        guard let rect = newRect else {
            resetSteadyState()
            return
        }

        if let lastRect = lastStableRectangle, isRectangleSimilar(rect, lastRect) {
            if !isHoldingSteady {
                startSteadyTimer()
            }
        } else {
            resetSteadyState()
            lastStableRectangle = rect
        }
    }

    private func manualCapture() {
        guard !isAnimatingCapture else { return }
        capturePhoto()
    }

    private func isRectangleSimilar(_ rect1: VNRectangleObservation, _ rect2: VNRectangleObservation) -> Bool {
        let threshold: CGFloat = 0.02

        return abs(rect1.topLeft.x - rect2.topLeft.x) < threshold &&
               abs(rect1.topLeft.y - rect2.topLeft.y) < threshold &&
               abs(rect1.topRight.x - rect2.topRight.x) < threshold &&
               abs(rect1.topRight.y - rect2.topRight.y) < threshold &&
               abs(rect1.bottomLeft.x - rect2.bottomLeft.x) < threshold &&
               abs(rect1.bottomLeft.y - rect2.bottomLeft.y) < threshold &&
               abs(rect1.bottomRight.x - rect2.bottomRight.x) < threshold &&
               abs(rect1.bottomRight.y - rect2.bottomRight.y) < threshold
    }

    private func startSteadyTimer() {
        isHoldingSteady = true
        steadyProgress = 0

        let updateInterval: TimeInterval = 0.05
        let progressIncrement = CGFloat(updateInterval / steadyDuration)

        steadyTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { timer in
            steadyProgress += progressIncrement

            if steadyProgress >= 1.0 {
                timer.invalidate()
                capturePhoto()
            }
        }
    }

    private func resetSteadyState() {
        steadyTimer?.invalidate()
        steadyTimer = nil
        isHoldingSteady = false
        steadyProgress = 0
    }

    private func capturePhoto() {
        // Don't capture during animation
        guard !isAnimatingCapture else { return }

        // Store the detected rectangle for animation
        let detectedRect = cameraManager.detectedRectangle

        withAnimation(.easeInOut(duration: 0.1)) {
            showCaptureAnimation = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation {
                showCaptureAnimation = false
            }
        }

        // Prepare animation data with detected corners
        if let rect = detectedRect {
            let corners = convertRectangleToViewCorners(rect)
            captureAnimationData = CaptureAnimationData(
                corners: corners,
                rawImage: nil,
                processedImage: nil
            )
        }

        cameraManager.capturePhoto()
        resetSteadyState()
    }

    private func convertRectangleToViewCorners(_ rect: VNRectangleObservation) -> [CGPoint] {
        // Convert Vision coordinates to view coordinates
        let cameraAspect: CGFloat = 3.0 / 4.0
        let viewAspect = cameraViewSize.width / cameraViewSize.height

        var scaleX: CGFloat = 1.0
        var scaleY: CGFloat = 1.0
        var offsetX: CGFloat = 0.0
        var offsetY: CGFloat = 0.0

        if viewAspect < cameraAspect {
            let visibleWidthRatio = viewAspect / cameraAspect
            offsetX = (1.0 - visibleWidthRatio) / 2.0
            scaleX = visibleWidthRatio
        } else {
            let visibleHeightRatio = cameraAspect / viewAspect
            offsetY = (1.0 - visibleHeightRatio) / 2.0
            scaleY = visibleHeightRatio
        }

        func transform(_ point: CGPoint) -> CGPoint {
            let adjustedX = (point.x - offsetX) / scaleX
            let adjustedY = (point.y - offsetY) / scaleY
            return CGPoint(
                x: adjustedX * cameraViewSize.width,
                y: (1 - adjustedY) * cameraViewSize.height
            )
        }

        return [
            transform(rect.topLeft),
            transform(rect.topRight),
            transform(rect.bottomRight),
            transform(rect.bottomLeft)
        ]
    }

    private func handleCapturedImage(_ image: UIImage) {
        let rect = cameraManager.detectedRectangle

        DispatchQueue.global(qos: .userInitiated).async {
            autoreleasepool {
                var processedImage = image

                if let rectangle = rect {
                    if let cropped = ImageProcessor.shared.detectAndCrop(image, rectangle: rectangle) {
                        processedImage = cropped
                    }
                }

                let filteredImage = ImageProcessor.shared.processImage(
                    processedImage,
                    filterMode: .autoColor,
                    adjustments: .default
                ) ?? processedImage

                let pageId = UUID()
                guard let originalPath = DocumentStorage.shared.saveImage(image, for: pageId) else { return }

                let processedId = UUID()
                let processedPath = DocumentStorage.shared.saveImage(filteredImage, for: processedId)

                let page = ScannedPage(
                    id: pageId,
                    originalImagePath: originalPath,
                    croppedImagePath: processedPath,
                    filterMode: .autoColor,
                    adjustments: .default
                )

                // Create thumbnail for animation
                let thumbnailImage = filteredImage

                DispatchQueue.main.async {
                    if self.currentDocument == nil {
                        self.currentDocument = ScannedDocument()
                    }
                    self.currentDocument?.addPage(page)

                    // Start capture animation sequence
                    self.startCaptureAnimation(
                        rawImage: image,
                        processedImage: thumbnailImage,
                        pageId: pageId
                    )

                    self.cameraManager.capturedImage = nil
                    self.lastStableRectangle = nil
                }
            }
        }
    }

    private func startCaptureAnimation(rawImage: UIImage, processedImage: UIImage, pageId: UUID) {
        // Block new captures during animation
        isAnimatingCapture = true

        // Update animation data with images
        if captureAnimationData != nil {
            captureAnimationData?.rawImage = rawImage
            captureAnimationData?.processedImage = processedImage
        } else {
            // No corners detected, create centered animation
            let centerX = cameraViewSize.width / 2
            let centerY = cameraViewSize.height / 2
            let width: CGFloat = 200
            let height: CGFloat = 260
            captureAnimationData = CaptureAnimationData(
                corners: [
                    CGPoint(x: centerX - width/2, y: centerY - height/2),
                    CGPoint(x: centerX + width/2, y: centerY - height/2),
                    CGPoint(x: centerX + width/2, y: centerY + height/2),
                    CGPoint(x: centerX - width/2, y: centerY + height/2)
                ],
                rawImage: rawImage,
                processedImage: processedImage
            )
        }

        // Phase 1: Show at detected position (skewed)
        capturePreviewPhase = .initial
        showCapturePreview = true

        // Phase 2: Animate to rectangle with processed image
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeInOut(duration: 0.4)) {
                self.capturePreviewPhase = .transformed
            }
        }

        // Phase 3: Fade out
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            withAnimation(.easeOut(duration: 0.3)) {
                self.capturePreviewPhase = .fadeOut
            }

            // Add to thumbnails as preview fades
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                self.scannedPages.append(ScannedPageThumbnail(
                    id: pageId,
                    image: processedImage
                ))
            }
        }

        // Phase 4: Clean up
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            self.showCapturePreview = false
            self.captureAnimationData = nil
            self.capturePreviewPhase = .initial
            self.isAnimatingCapture = false
        }
    }

    // MARK: - Actions

    private func loadExistingPages() {
        guard let doc = currentDocument else { return }

        scannedPages = doc.pages.compactMap { page in
            if let path = page.croppedImagePath ?? Optional(page.originalImagePath),
               let image = DocumentStorage.shared.loadImage(filename: path) {
                return ScannedPageThumbnail(id: page.id, image: image)
            }
            return nil
        }
    }

    private func deleteLastPage() {
        guard !scannedPages.isEmpty else { return }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            let removed = scannedPages.removeLast()

            if let index = currentDocument?.pages.firstIndex(where: { $0.id == removed.id }) {
                let page = currentDocument?.pages[index]
                if let path = page?.originalImagePath {
                    DocumentStorage.shared.deleteImage(filename: path)
                }
                if let path = page?.croppedImagePath {
                    DocumentStorage.shared.deleteImage(filename: path)
                }
                currentDocument?.pages.remove(at: index)
            }
        }
    }

    private func finishScanning() {
        guard !scannedPages.isEmpty, let document = currentDocument else { return }

        // Check if this is an existing document being edited
        let isExistingDocument = DocumentStorage.shared.documents.contains { $0.id == document.id }

        DispatchQueue.global(qos: .userInitiated).async {
            autoreleasepool {
                let images = document.pages.compactMap { page -> UIImage? in
                    if let cropped = page.croppedImagePath {
                        return DocumentStorage.shared.loadImage(filename: cropped)
                    }
                    return DocumentStorage.shared.loadImage(filename: page.originalImagePath)
                }

                var finalDocument = document
                if let pdfData = PDFGenerator.shared.generatePDF(from: images),
                   let pdfPath = DocumentStorage.shared.savePDF(pdfData, for: document.id) {
                    finalDocument.pdfPath = pdfPath
                }

                DispatchQueue.main.async {
                    if isExistingDocument {
                        DocumentStorage.shared.updateDocument(finalDocument)
                    } else {
                        DocumentStorage.shared.addDocument(finalDocument)
                    }
                    self.onFinish()
                }
            }
        }
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let isDetected: Bool
    let isHoldingSteady: Bool
    let progress: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.viewfinder")
                .font(.system(size: 16))

            Text(statusText)
                .font(.system(size: 14, weight: .medium))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.6))
                .overlay(
                    GeometryReader { geometry in
                        if isHoldingSteady {
                            Capsule()
                                .fill(Color.blue.opacity(0.5))
                                .frame(width: geometry.size.width * progress)
                        }
                    }
                    .clipShape(Capsule())
                )
        )
    }

    private var statusText: String {
        if isHoldingSteady {
            return "Hold Steady..."
        } else if isDetected {
            return "Document Detected"
        } else {
            return "Looking for Document"
        }
    }
}

// MARK: - Thumbnail Strip

struct ThumbnailStrip: View {
    let pages: [ScannedPageThumbnail]
    let stripHeight: CGFloat

    private let horizontalPadding: CGFloat = 8
    private let spacing: CGFloat = 4

    // Calculate thumbnail size to fit 3 in a row with proper aspect ratio
    private var thumbnailHeight: CGFloat {
        max(stripHeight - 16, 80) // Leave some vertical padding
    }

    private var thumbnailWidth: CGFloat {
        thumbnailHeight / 1.4 // Inverse of page aspect ratio
    }

    var body: some View {
        if pages.isEmpty {
            VStack(spacing: 4) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 24))
                    .foregroundColor(.gray)
                Text("Scanned pages appear here")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                ScrollViewReader { proxy in
                    HStack(spacing: spacing) {
                        ForEach(pages) { page in
                            Image(uiImage: page.image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: thumbnailWidth, height: thumbnailHeight)
                                .cornerRadius(4)
                                .clipped()
                                .id(page.id)
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.5).combined(with: .opacity),
                                    removal: .scale(scale: 0.8).combined(with: .opacity)
                                ))
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, 8)
                    .onChange(of: pages.count) { (_: Int) in
                        if let lastPage = pages.last {
                            withAnimation {
                                proxy.scrollTo(lastPage.id, anchor: .trailing)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Types

struct ScannedPageThumbnail: Identifiable {
    let id: UUID
    let image: UIImage
}

// MARK: - Capture Animation Types

enum CapturePreviewPhase {
    case initial      // Show at detected corners (potentially skewed)
    case transformed  // Animate to rectangle with processed image
    case fadeOut      // Fade out
}

struct CaptureAnimationData {
    var corners: [CGPoint]  // topLeft, topRight, bottomRight, bottomLeft
    var rawImage: UIImage?
    var processedImage: UIImage?
}

// MARK: - Capture Preview Animation View

struct CapturePreviewAnimation: View {
    let data: CaptureAnimationData
    let phase: CapturePreviewPhase
    let viewSize: CGSize

    // Target rectangle (centered, smaller)
    private var targetRect: CGRect {
        let width: CGFloat = 180
        let height: CGFloat = 240
        return CGRect(
            x: (viewSize.width - width) / 2,
            y: (viewSize.height - height) / 2 - 40,
            width: width,
            height: height
        )
    }

    // Calculate bounding rect from corners
    private func boundingRect(from corners: [CGPoint]) -> CGRect {
        guard corners.count == 4 else {
            return targetRect
        }
        let minX = corners.map { $0.x }.min() ?? 0
        let minY = corners.map { $0.y }.min() ?? 0
        let maxX = corners.map { $0.x }.max() ?? 100
        let maxY = corners.map { $0.y }.max() ?? 130
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private var initialRect: CGRect {
        // Slightly shrunk from detected corners
        let corners = shrinkCorners(data.corners, by: 0.92)
        return boundingRect(from: corners)
    }

    private var currentRect: CGRect {
        switch phase {
        case .initial:
            return initialRect
        case .transformed, .fadeOut:
            return targetRect
        }
    }

    private var currentImage: UIImage? {
        switch phase {
        case .initial:
            return data.rawImage ?? data.processedImage
        case .transformed, .fadeOut:
            return data.processedImage ?? data.rawImage
        }
    }

    private var opacity: Double {
        switch phase {
        case .initial, .transformed:
            return 1.0
        case .fadeOut:
            return 0.0
        }
    }

    var body: some View {
        if let image = currentImage {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: currentRect.width, height: currentRect.height)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.4), radius: 10, x: 0, y: 5)
                .position(
                    x: currentRect.midX,
                    y: currentRect.midY
                )
                .opacity(opacity)
        }
    }

    private func shrinkCorners(_ corners: [CGPoint], by scale: CGFloat) -> [CGPoint] {
        guard corners.count == 4 else { return corners }

        // Calculate centroid
        let centerX = corners.reduce(0) { $0 + $1.x } / 4
        let centerY = corners.reduce(0) { $0 + $1.y } / 4

        // Scale corners toward center
        return corners.map { corner in
            CGPoint(
                x: centerX + (corner.x - centerX) * scale,
                y: centerY + (corner.y - centerY) * scale
            )
        }
    }
}
