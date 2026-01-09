import SwiftUI
import Vision
import UIKit

struct ScanPreviewView: View {
    let originalImage: UIImage
    let detectedRectangle: VNRectangleObservation?

    @Binding var currentDocument: ScannedDocument?
    let onKeepScanning: () -> Void
    let onSavePDF: (ScannedDocument) -> Void
    let onDiscard: () -> Void

    @State private var croppedImage: UIImage?
    @State private var displayImage: UIImage?
    @State private var filterMode: FilterMode = .autoColor
    @State private var adjustments = ImageAdjustments()
    @State private var showCropView = false
    @State private var showFilters = false
    @State private var showAdjustments = false
    @State private var corners: [CGPoint] = []
    @State private var isProcessing = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Button(action: onDiscard) {
                        Image(systemName: "house.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                    }

                    Spacer()

                    if let doc = currentDocument {
                        Text("\(doc.pageCount + 1) page\(doc.pageCount == 0 ? "" : "s")")
                            .font(.headline)
                            .foregroundColor(.white)
                    }

                    Spacer()

                    // Placeholder for symmetry
                    Image(systemName: "house.fill")
                        .font(.title2)
                        .foregroundColor(.clear)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                // Image preview
                GeometryReader { geometry in
                    ZStack {
                        if showCropView {
                            CropOverlayView(
                                image: originalImage,
                                detectedRectangle: detectedRectangle,
                                corners: $corners,
                                onDone: applyCrop
                            )
                        } else {
                            Image(uiImage: displayImage ?? originalImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(Color(.systemGray6).opacity(0.3))

                // Tool panels
                if showFilters {
                    FilterPanel(selectedFilter: $filterMode, onSelect: applyFilter)
                        .transition(.move(edge: .bottom))
                } else if showAdjustments {
                    AdjustmentsPanel(adjustments: $adjustments, onAdjust: applyAdjustments)
                        .transition(.move(edge: .bottom))
                }

                // Toolbar
                if !showCropView {
                    ToolbarView(
                        showFilters: $showFilters,
                        showAdjustments: $showAdjustments,
                        onRetake: onDiscard,
                        onCrop: {
                            corners = [] // Clear corners so they initialize fresh
                            showCropView = true
                        },
                        onDelete: onDiscard
                    )

                    // Bottom buttons
                    HStack(spacing: 16) {
                        Button(action: keepScanning) {
                            Text("Keep scanning")
                                .font(.headline)
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color(.systemGray5))
                                .cornerRadius(25)
                        }

                        Button(action: savePDF) {
                            Text("Save PDF")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.blue)
                                .cornerRadius(25)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
                }
            }

            if isProcessing {
                Color.black.opacity(0.5).ignoresSafeArea()
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
            }
        }
        .onAppear {
            initializeImage()
        }
    }

    // MARK: - Actions

    private func initializeImage() {
        isProcessing = true

        DispatchQueue.global(qos: .userInitiated).async {
            autoreleasepool {
                // Auto-crop if rectangle detected
                var processed = originalImage
                if let rect = detectedRectangle {
                    if let cropped = ImageProcessor.shared.detectAndCrop(originalImage, rectangle: rect) {
                        processed = cropped
                    }
                }

                // Apply default filter
                let filtered = ImageProcessor.shared.processImage(
                    processed,
                    filterMode: .autoColor,
                    adjustments: .default
                ) ?? processed

                DispatchQueue.main.async {
                    self.croppedImage = processed
                    self.displayImage = filtered
                    self.isProcessing = false
                }
            }
        }
    }

    private func applyFilter(_ filter: FilterMode) {
        let base = croppedImage ?? originalImage

        DispatchQueue.global(qos: .userInitiated).async {
            autoreleasepool {
                let filtered = ImageProcessor.shared.processImage(base, filterMode: filter, adjustments: self.adjustments)

                DispatchQueue.main.async {
                    self.displayImage = filtered ?? base
                    self.filterMode = filter
                }
            }
        }
    }

    private func applyAdjustments() {
        let base = croppedImage ?? originalImage

        DispatchQueue.global(qos: .userInitiated).async {
            autoreleasepool {
                let adjusted = ImageProcessor.shared.processImage(base, filterMode: self.filterMode, adjustments: self.adjustments)

                DispatchQueue.main.async {
                    self.displayImage = adjusted ?? base
                }
            }
        }
    }

    private func applyCrop() {
        showCropView = false
        guard !corners.isEmpty else { return }

        isProcessing = true
        let cornersToUse = corners

        DispatchQueue.global(qos: .userInitiated).async {
            autoreleasepool {
                if let cropped = ImageProcessor.shared.correctPerspective(self.originalImage, corners: cornersToUse) {
                    let filtered = ImageProcessor.shared.processImage(cropped, filterMode: self.filterMode, adjustments: self.adjustments)

                    DispatchQueue.main.async {
                        self.croppedImage = cropped
                        self.displayImage = filtered ?? cropped
                        self.isProcessing = false
                    }
                } else {
                    DispatchQueue.main.async {
                        self.isProcessing = false
                    }
                }
            }
        }
    }

    private func keepScanning() {
        savePage()
        onKeepScanning()
    }

    private func savePDF() {
        savePage()

        guard var document = currentDocument else { return }

        isProcessing = true

        DispatchQueue.global(qos: .userInitiated).async {
            autoreleasepool {
                // Generate PDF
                let images = document.pages.compactMap { page -> UIImage? in
                    autoreleasepool {
                        if let cropped = page.croppedImagePath {
                            return DocumentStorage.shared.loadImage(filename: cropped)
                        }
                        return DocumentStorage.shared.loadImage(filename: page.originalImagePath)
                    }
                }

                if let pdfData = PDFGenerator.shared.generatePDF(from: images) {
                    if let pdfPath = DocumentStorage.shared.savePDF(pdfData, for: document.id) {
                        document.pdfPath = pdfPath
                    }
                }

                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.onSavePDF(document)
                }
            }
        }
    }

    private func savePage() {
        let pageId = UUID()

        guard let imagePath = DocumentStorage.shared.saveImage(originalImage, for: pageId) else { return }

        // Save the processed/filtered image (displayImage) for PDF generation
        // This includes both cropping and filter adjustments
        var processedPath: String?
        if let processed = displayImage {
            let processedId = UUID()
            processedPath = DocumentStorage.shared.saveImage(processed, for: processedId)
        }

        let page = ScannedPage(
            id: pageId,
            originalImagePath: imagePath,
            croppedImagePath: processedPath, // This now contains the filtered image
            corners: corners.isEmpty ? nil : corners,
            filterMode: filterMode,
            adjustments: adjustments
        )

        if currentDocument == nil {
            currentDocument = ScannedDocument()
        }
        currentDocument?.addPage(page)
    }
}

// MARK: - Toolbar View

struct ToolbarView: View {
    @Binding var showFilters: Bool
    @Binding var showAdjustments: Bool
    let onRetake: () -> Void
    let onCrop: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 24) {
                ToolButton(icon: "arrow.counterclockwise", label: "Retake", action: onRetake)
                ToolButton(icon: "crop", label: "Crop", action: onCrop)
                ToolButton(icon: "camera.filters", label: "Filters", isSelected: showFilters) {
                    showFilters.toggle()
                    showAdjustments = false
                }
                ToolButton(icon: "slider.horizontal.3", label: "Adjust", isSelected: showAdjustments) {
                    showAdjustments.toggle()
                    showFilters = false
                }
                ToolButton(icon: "trash", label: "Delete", action: onDelete)
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 12)
        .background(Color.black)
    }
}

struct ToolButton: View {
    let icon: String
    let label: String
    var isSelected: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(isSelected ? .blue : .white)
                Text(label)
                    .font(.caption)
                    .foregroundColor(isSelected ? .blue : .gray)
            }
        }
    }
}

// MARK: - Filter Panel

struct FilterPanel: View {
    @Binding var selectedFilter: FilterMode
    let onSelect: (FilterMode) -> Void

    var body: some View {
        HStack(spacing: 20) {
            ForEach(FilterMode.allCases, id: \.self) { filter in
                Button(action: { onSelect(filter) }) {
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(filterColor(filter))
                            .frame(width: 60, height: 60)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(selectedFilter == filter ? Color.blue : Color.clear, lineWidth: 3)
                            )

                        Text(filter.rawValue)
                            .font(.caption)
                            .foregroundColor(selectedFilter == filter ? .blue : .white)
                    }
                }
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .background(Color.black)
    }

    private func filterColor(_ filter: FilterMode) -> Color {
        switch filter {
        case .original: return Color.orange.opacity(0.6)
        case .autoColor: return Color.blue.opacity(0.6)
        case .grayscale: return Color.gray
        }
    }
}

// MARK: - Adjustments Panel

struct AdjustmentsPanel: View {
    @Binding var adjustments: ImageAdjustments
    let onAdjust: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            AdjustSlider(label: "Exposure", value: $adjustments.exposure, range: -1...1, onChange: onAdjust)
            AdjustSlider(label: "Brightness", value: $adjustments.brightness, range: -0.5...0.5, onChange: onAdjust)
            AdjustSlider(label: "Contrast", value: $adjustments.contrast, range: 0.5...2, onChange: onAdjust)
        }
        .padding(16)
        .background(Color.black)
    }
}

struct AdjustSlider: View {
    let label: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let onChange: () -> Void

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.white)
                .frame(width: 80, alignment: .leading)

            Slider(value: $value, in: range)
                .tint(.blue)
                .onChange(of: value) { (_: Float) in onChange() }
        }
    }
}

// MARK: - Crop Overlay View

struct CropOverlayView: View {
    let image: UIImage
    let detectedRectangle: VNRectangleObservation?
    @Binding var corners: [CGPoint]
    let onDone: () -> Void

    @State private var hasInitializedCorners = false
    @State private var currentViewSize: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            let imageFrame = calculateImageFrame(in: geometry.size)

            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Crop overlay
                if !corners.isEmpty {
                    CropShapeView(corners: corners)
                        .stroke(Color.blue, lineWidth: 2)

                    // Corner handles
                    ForEach(0..<corners.count, id: \.self) { index in
                        DraggableCorner(position: $corners[index])
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                currentViewSize = geometry.size
                initializeCorners(imageFrame: imageFrame)
            }
            .onChange(of: geometry.size) { (newSize: CGSize) in
                currentViewSize = newSize
                // Re-initialize if view size changes and corners haven't been set
                if corners.isEmpty {
                    let newFrame = calculateImageFrame(in: newSize)
                    initializeCorners(imageFrame: newFrame)
                }
            }
        }
        .overlay(alignment: .bottom) {
            HStack {
                Button("Cancel") {
                    corners = []
                    onDone()
                }
                .foregroundColor(.white)
                .padding()

                Spacer()

                Button("Apply") {
                    convertCornersToImageCoordinates()
                    onDone()
                }
                .foregroundColor(.blue)
                .font(.body.bold())
                .padding()
            }
            .padding(.horizontal)
            .background(Color.black.opacity(0.8))
        }
    }

    private func calculateImageFrame(in containerSize: CGSize) -> CGRect {
        let imageSize = image.size
        guard imageSize.width > 0 && imageSize.height > 0 else {
            return .zero
        }

        let scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        let scaledWidth = imageSize.width * scale
        let scaledHeight = imageSize.height * scale
        let x = (containerSize.width - scaledWidth) / 2
        let y = (containerSize.height - scaledHeight) / 2

        return CGRect(x: x, y: y, width: scaledWidth, height: scaledHeight)
    }

    private func initializeCorners(imageFrame: CGRect) {
        guard corners.isEmpty && !hasInitializedCorners else { return }
        guard imageFrame.width > 0 && imageFrame.height > 0 else { return }

        hasInitializedCorners = true

        let imageSize = image.size

        // If we have a detected rectangle, use its corners (with margin applied)
        if let rect = detectedRectangle {
            let imageCorners = ImageProcessor.shared.getCornersFromRectangle(rect, imageSize: imageSize)

            // Convert from image coordinates to view coordinates
            let scaleX = imageFrame.width / imageSize.width
            let scaleY = imageFrame.height / imageSize.height

            corners = imageCorners.map { corner in
                CGPoint(
                    x: imageFrame.origin.x + corner.x * scaleX,
                    y: imageFrame.origin.y + corner.y * scaleY
                )
            }
        } else {
            // Fallback to image bounds with padding
            let padding: CGFloat = 30
            corners = [
                CGPoint(x: imageFrame.minX + padding, y: imageFrame.minY + padding),
                CGPoint(x: imageFrame.maxX - padding, y: imageFrame.minY + padding),
                CGPoint(x: imageFrame.maxX - padding, y: imageFrame.maxY - padding),
                CGPoint(x: imageFrame.minX + padding, y: imageFrame.maxY - padding)
            ]
        }
    }

    /// Convert corners from view coordinates to image coordinates
    private func convertCornersToImageCoordinates() {
        guard !corners.isEmpty && currentViewSize.width > 0 else { return }

        let imageFrame = calculateImageFrame(in: currentViewSize)
        guard imageFrame.width > 0 && imageFrame.height > 0 else { return }

        let imageSize = image.size
        let scaleX = imageSize.width / imageFrame.width
        let scaleY = imageSize.height / imageFrame.height

        corners = corners.map { corner in
            CGPoint(
                x: (corner.x - imageFrame.origin.x) * scaleX,
                y: (corner.y - imageFrame.origin.y) * scaleY
            )
        }
    }
}

struct CropShapeView: Shape {
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

struct DraggableCorner: View {
    @Binding var position: CGPoint

    var body: some View {
        Circle()
            .fill(Color.blue)
            .frame(width: 24, height: 24)
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
            .position(position)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        position = value.location
                    }
            )
    }
}
