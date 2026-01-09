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

    private let steadyDuration: TimeInterval = 1.0

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

                            // Center-bottom: Status badge
                            StatusBadge(
                                isDetected: cameraManager.detectedRectangle != nil,
                                isHoldingSteady: isHoldingSteady,
                                progress: steadyProgress
                            )

                            // Bottom: Action buttons
                            HStack {
                                Button(action: {}) {
                                    Image(systemName: "ellipsis")
                                        .font(.system(size: 20))
                                        .foregroundColor(.white)
                                        .frame(width: 44, height: 44)
                                        .background(Color.black.opacity(0.5))
                                        .clipShape(Circle())
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
        withAnimation(.easeInOut(duration: 0.1)) {
            showCaptureAnimation = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation {
                showCaptureAnimation = false
            }
        }

        cameraManager.capturePhoto()
        resetSteadyState()
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

                DispatchQueue.main.async {
                    if self.currentDocument == nil {
                        self.currentDocument = ScannedDocument()
                    }
                    self.currentDocument?.addPage(page)

                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        self.scannedPages.append(ScannedPageThumbnail(
                            id: pageId,
                            image: filteredImage
                        ))
                    }

                    self.cameraManager.capturedImage = nil
                    self.lastStableRectangle = nil
                }
            }
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
                    DocumentStorage.shared.addDocument(finalDocument)
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
