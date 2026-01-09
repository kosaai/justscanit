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
        case .auto: return "bolt.badge.automaticit "
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

                        // Edge detection overlay (hidden during animation)
                        if cameraViewSize != .zero && !isAnimatingCapture {
                            EdgeOverlayView(
                                rectangle: cameraManager.detectedRectangle,
                                viewSize: cameraViewSize
                            )
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
                            // Top: Close button (fully below safe area)
                            HStack {
                                Button(action: onDismiss) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(width: 44, height: 44)
                                        .background(Color.black.opacity(0.5))
                                        .clipShape(Circle())
                                }
                                Spacer()
                            }
                            .padding(.leading, 16)
                            .padding(.top, geometry.safeAreaInsets.top + 44)

                            Spacer()

                            // Center-bottom: Status badge (only in auto mode, hidden during animation)
                            if captureMode == .auto && !isAnimatingCapture {
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

                    // Thumbnail section (25%) - zIndex ensures dragged thumbnails appear above camera
                    VStack(spacing: 0) {
                        ThumbnailStrip(
                            pages: scannedPages,
                            stripHeight: thumbnailAreaHeight - geometry.safeAreaInsets.bottom,
                            onDelete: deletePage
                        )

                        // Bottom safe area spacer
                        Spacer()
                            .frame(height: geometry.safeAreaInsets.bottom)
                    }
                    .frame(height: thumbnailAreaHeight)
                    .background(Color.black)
                    .zIndex(1)
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

        // Block new captures immediately
        isAnimatingCapture = true

        // Store the detected rectangle for animation
        let detectedRect = cameraManager.detectedRectangle

        // Prepare animation data with detected corners (view coordinates)
        if let rect = detectedRect {
            let viewCorners = convertRectangleToViewCorners(rect)
            captureAnimationData = CaptureAnimationData(
                viewCorners: viewCorners,
                normalizedCorners: [rect.topLeft, rect.topRight, rect.bottomRight, rect.bottomLeft],
                rawImage: nil,
                processedImage: nil
            )
        } else {
            // No detection - use centered default
            let centerX = cameraViewSize.width / 2
            let centerY = cameraViewSize.height / 2
            let w: CGFloat = 200
            let h: CGFloat = 280
            captureAnimationData = CaptureAnimationData(
                viewCorners: [
                    CGPoint(x: centerX - w/2, y: centerY - h/2),
                    CGPoint(x: centerX + w/2, y: centerY - h/2),
                    CGPoint(x: centerX + w/2, y: centerY + h/2),
                    CGPoint(x: centerX - w/2, y: centerY + h/2)
                ],
                normalizedCorners: nil,
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

        // IMMEDIATELY start animation with raw image
        captureAnimationData?.rawImage = image

        // Quick crop for animation (on main thread - fast operation)
        if let corners = captureAnimationData?.normalizedCorners {
            captureAnimationData?.croppedRawImage = quickCropToDocument(image, corners: corners)
        }

        startCaptureAnimationPhase1()

        // Process in background
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

                DispatchQueue.main.async {
                    if self.currentDocument == nil {
                        self.currentDocument = ScannedDocument()
                    }
                    self.currentDocument?.addPage(page)

                    // Update animation with processed image and continue sequence
                    self.continueAnimationWithProcessedImage(filteredImage, pageId: pageId)

                    self.cameraManager.capturedImage = nil
                    self.lastStableRectangle = nil
                }
            }
        }
    }

    private func startCaptureAnimationPhase1() {
        // Phase 1: Show cropped raw image at detected position
        capturePreviewPhase = .initial
        showCapturePreview = true

        // Phase 2: After brief moment, start growing animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.easeOut(duration: 0.4)) {
                self.capturePreviewPhase = .growing
            }
        }
    }

    private func continueAnimationWithProcessedImage(_ processedImage: UIImage, pageId: UUID) {
        // Update with processed image
        captureAnimationData?.processedImage = processedImage

        // Phase 3: Crossfade to enhanced image
        withAnimation(.easeInOut(duration: 0.3)) {
            self.capturePreviewPhase = .enhanced
        }

        // Phase 4: Fade out
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeOut(duration: 0.25)) {
                self.capturePreviewPhase = .fadeOut
            }

            // Add to thumbnails as preview fades
            if let image = self.captureAnimationData?.processedImage {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    self.scannedPages.append(ScannedPageThumbnail(
                        id: pageId,
                        image: image
                    ))
                }
            }
        }

        // Phase 5: Clean up
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            self.showCapturePreview = false
            self.captureAnimationData = nil
            self.capturePreviewPhase = .initial
        }

        // Re-enable detection after additional delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            self.isAnimatingCapture = false
        }
    }

    // Quick crop for animation - just bounding box, no perspective correction
    private func quickCropToDocument(_ image: UIImage, corners: [CGPoint]) -> UIImage? {
        guard corners.count == 4 else { return image }

        let imageSize = image.size

        // Convert normalized Vision coordinates to image coordinates
        let imageCorners = corners.map { point in
            CGPoint(
                x: point.x * imageSize.width,
                y: (1 - point.y) * imageSize.height
            )
        }

        // Calculate bounding rect
        let minX = imageCorners.map { $0.x }.min() ?? 0
        let minY = imageCorners.map { $0.y }.min() ?? 0
        let maxX = imageCorners.map { $0.x }.max() ?? imageSize.width
        let maxY = imageCorners.map { $0.y }.max() ?? imageSize.height

        let cropRect = CGRect(
            x: max(0, minX),
            y: max(0, minY),
            width: min(imageSize.width - minX, maxX - minX),
            height: min(imageSize.height - minY, maxY - minY)
        )

        guard let cgImage = image.cgImage,
              let croppedCGImage = cgImage.cropping(to: cropRect) else {
            return image
        }

        return UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)
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
        guard let lastPage = scannedPages.last else { return }
        deletePage(id: lastPage.id)
    }

    private func deletePage(id: UUID) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            scannedPages.removeAll { $0.id == id }

            if let index = currentDocument?.pages.firstIndex(where: { $0.id == id }) {
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
    let onDelete: (UUID) -> Void

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
                            SwipableThumbnail(
                                page: page,
                                width: thumbnailWidth,
                                height: thumbnailHeight,
                                onDelete: { onDelete(page.id) }
                            )
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
            .modifier(ScrollClipDisabledModifier())
        }
    }
}

// Helper to disable scroll clipping on iOS 17+
struct ScrollClipDisabledModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.scrollClipDisabled(true)
        } else {
            content
        }
    }
}

// MARK: - Swipable Thumbnail

struct SwipableThumbnail: View {
    let page: ScannedPageThumbnail
    let width: CGFloat
    let height: CGFloat
    let onDelete: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false

    // Threshold: 1/3 of thumbnail height
    private var deleteThreshold: CGFloat {
        height / 3
    }

    private var shouldDelete: Bool {
        -dragOffset > deleteThreshold
    }

    // Gradual opacity for delete icon based on drag progress
    private var deleteIconOpacity: Double {
        guard isDragging else { return 0 }
        let progress = -dragOffset / deleteThreshold
        // Start fading in at 70% of threshold, fully visible at 100%
        let fadeStart: Double = 0.7
        if progress < fadeStart { return 0 }
        return min(1.0, (progress - fadeStart) / (1.0 - fadeStart))
    }

    var body: some View {
        ZStack {
            // Thumbnail image with delete icon overlay
            Image(uiImage: page.image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: width, height: height)
                .cornerRadius(4)
                .clipped()
                .overlay(alignment: .top) {
                    // Delete icon above thumbnail, gradual fade
                    Circle()
                        .fill(Color.red)
                        .frame(width: 52, height: 52)
                        .overlay(
                            Image(systemName: "trash.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.white)
                        )
                        .offset(y: -60)  // Position above thumbnail
                        .opacity(deleteIconOpacity)
                }
                .offset(y: dragOffset)
                .opacity(isDragging ? (shouldDelete ? 0.7 : 0.9) : 1.0)
                .scaleEffect(isDragging ? 0.95 : 1.0)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            // Only allow upward swipes
                            let translation = value.translation.height
                            if translation < 0 {
                                isDragging = true
                                // Apply resistance as user drags further
                                dragOffset = translation * 0.8
                            }
                        }
                        .onEnded { value in
                            if shouldDelete {
                                // Animate off screen then delete
                                withAnimation(.easeOut(duration: 0.2)) {
                                    dragOffset = -200
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    onDelete()
                                }
                            } else {
                                // Snap back
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    dragOffset = 0
                                    isDragging = false
                                }
                            }
                        }
                )
        }
        .frame(width: width, height: height)
    }
}

// MARK: - Supporting Types

struct ScannedPageThumbnail: Identifiable {
    let id: UUID
    let image: UIImage
}

// MARK: - Capture Animation Types

enum CapturePreviewPhase {
    case initial      // Show cropped raw image, medium size at detected position
    case growing      // Animate to full size, still showing raw image
    case enhanced     // Crossfade to processed image
    case fadeOut      // Fade out
}

struct CaptureAnimationData {
    var viewCorners: [CGPoint]  // Corners in view coordinates (topLeft, topRight, bottomRight, bottomLeft)
    var normalizedCorners: [CGPoint]?  // Corners in normalized image coordinates for clipping
    var rawImage: UIImage?
    var croppedRawImage: UIImage?  // Cached cropped version
    var processedImage: UIImage?
}

// MARK: - Capture Preview Animation View

struct CapturePreviewAnimation: View {
    let data: CaptureAnimationData
    let phase: CapturePreviewPhase
    let viewSize: CGSize

    // Calculate center of detected document
    private var detectedCenter: CGPoint {
        guard data.viewCorners.count == 4 else {
            return CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
        }
        let centerX = data.viewCorners.reduce(0) { $0 + $1.x } / 4
        let centerY = data.viewCorners.reduce(0) { $0 + $1.y } / 4
        return CGPoint(x: centerX, y: centerY)
    }

    // Initial size (medium, 2x original)
    private var initialSize: CGSize {
        CGSize(width: 240, height: 320)
    }

    // Target size (90% of camera view)
    private var targetSize: CGSize {
        let maxWidth = viewSize.width * 0.92
        let maxHeight = viewSize.height * 0.92
        // Maintain document aspect ratio (roughly 1:1.4)
        let aspectRatio: CGFloat = 1.4
        let width = min(maxWidth, maxHeight / aspectRatio)
        let height = width * aspectRatio
        return CGSize(width: width, height: height)
    }

    // Target center (centered in view)
    private var targetCenter: CGPoint {
        CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
    }

    private var currentSize: CGSize {
        switch phase {
        case .initial:
            return initialSize
        case .growing, .enhanced, .fadeOut:
            return targetSize
        }
    }

    private var currentCenter: CGPoint {
        switch phase {
        case .initial:
            return detectedCenter
        case .growing, .enhanced, .fadeOut:
            return targetCenter
        }
    }

    // Raw image (cropped to document)
    private var rawCroppedImage: UIImage? {
        if let cached = data.croppedRawImage {
            return cached
        }
        if let raw = data.rawImage, let corners = data.normalizedCorners {
            return cropToQuadrilateral(raw, corners: corners)
        }
        return data.rawImage
    }

    private var showProcessedImage: Bool {
        switch phase {
        case .initial, .growing:
            return false
        case .enhanced, .fadeOut:
            return true
        }
    }

    private var opacity: Double {
        switch phase {
        case .initial, .growing, .enhanced:
            return 1.0
        case .fadeOut:
            return 0.0
        }
    }

    var body: some View {
        ZStack {
            // Raw cropped image (grows, then fades out)
            if let rawImage = rawCroppedImage {
                Image(uiImage: rawImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: currentSize.width, height: currentSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .opacity(showProcessedImage ? 0 : 1)
            }

            // Processed image (fades in on top)
            if showProcessedImage, let processed = data.processedImage {
                Image(uiImage: processed)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: currentSize.width, height: currentSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .shadow(color: .black.opacity(0.5), radius: 15, x: 0, y: 8)
        .position(currentCenter)
        .opacity(opacity)
    }

    // Crop image to quadrilateral defined by normalized corners
    private func cropToQuadrilateral(_ image: UIImage, corners: [CGPoint]) -> UIImage? {
        guard corners.count == 4 else { return image }

        let imageSize = image.size

        // Convert normalized Vision coordinates to image coordinates
        // Vision: origin bottom-left, normalized 0-1
        // Image: origin top-left, pixel coordinates
        let imageCorners = corners.map { point in
            CGPoint(
                x: point.x * imageSize.width,
                y: (1 - point.y) * imageSize.height
            )
        }

        // Calculate bounding rect
        let minX = imageCorners.map { $0.x }.min() ?? 0
        let minY = imageCorners.map { $0.y }.min() ?? 0
        let maxX = imageCorners.map { $0.x }.max() ?? imageSize.width
        let maxY = imageCorners.map { $0.y }.max() ?? imageSize.height

        // Add small margin and ensure bounds
        let margin: CGFloat = 10
        let cropRect = CGRect(
            x: max(0, minX - margin),
            y: max(0, minY - margin),
            width: min(imageSize.width - minX + margin, maxX - minX + 2 * margin),
            height: min(imageSize.height - minY + margin, maxY - minY + 2 * margin)
        )

        // Crop to bounding rect (fast operation, not perspective correction)
        guard let cgImage = image.cgImage,
              let croppedCGImage = cgImage.cropping(to: cropRect) else {
            return image
        }

        return UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)
    }
}
