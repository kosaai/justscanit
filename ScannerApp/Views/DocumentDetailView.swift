import SwiftUI
import UIKit

enum ExportType {
    case pdf
    case images
}

// MARK: - Shareable Content

/// Identifiable wrapper for share sheet content.
/// Using `.sheet(item:)` ensures the sheet is recreated with fresh content each time.
struct ShareableContent: Identifiable {
    let id = UUID()
    let items: [Any]
    let cleanup: (() -> Void)?

    init(items: [Any], cleanup: (() -> Void)? = nil) {
        self.items = items
        self.cleanup = cleanup
    }
}

struct DocumentDetailView: View {
    @Binding var document: ScannedDocument
    let onBackToScanning: () -> Void
    let onDismiss: () -> Void

    @State private var currentPageIndex: Int = 0
    @State private var exportType: ExportType = .pdf
    @State private var isEditingName = false
    @State private var editedName: String = ""
    @State private var shareableContent: ShareableContent?
    @State private var isGeneratingShare = false
    @State private var showReorderView = false
    @State private var showAdjustmentToolbar = false
    @State private var showCropView = false
    @State private var showDeleteConfirmation = false
    @State private var isProcessingAdjustment = false

    @FocusState private var isNameFieldFocused: Bool

    private var saveButtonTitle: String {
        if exportType == .pdf {
            return "Save PDF"
        } else {
            return document.pages.count == 1 ? "Save Image" : "Save Images"
        }
    }

    var body: some View {
        ZStack {
            // Background (always present)
            Color.black.ignoresSafeArea()

            // Main detail view (guard against empty pages during deletion transition)
            if !showReorderView && !document.pages.isEmpty {
                detailContent
                    .transition(.opacity)
            }

            // Reorder view (also guard against empty pages)
            if showReorderView && !document.pages.isEmpty {
                ReorderPagesView(
                    pages: document.pages,
                    onDone: { reorderedPages in
                        document.pages = reorderedPages
                        document.modifiedAt = Date()
                        DocumentStorage.shared.updateDocument(document)
                        // Ensure current page index is valid
                        if currentPageIndex >= document.pages.count {
                            currentPageIndex = max(0, document.pages.count - 1)
                        }
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showReorderView = false
                        }
                    },
                    onCancel: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showReorderView = false
                        }
                    },
                    onDeletePage: { pageId in
                        deletePage(id: pageId)
                    }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showReorderView)
        .sheet(item: $shareableContent, onDismiss: {
            shareableContent?.cleanup?()
        }) { content in
            ActivityViewControllerRepresentable(items: content.items)
        }
        .alert("Delete Page?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteCurrentPage()
            }
        } message: {
            Text("This page will be permanently removed from the document.")
        }
        .onAppear {
            editedName = document.name
        }
        .overlay {
            // Adjustment toolbar
            if showAdjustmentToolbar && !showCropView {
                adjustmentToolbarOverlay
            }
        }
        .fullScreenCover(isPresented: $showCropView) {
            cropViewContent
        }
    }

    // MARK: - Detail Content

    private var detailContent: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                GeometryReader { geometry in
                    PageCarouselView(
                        pages: document.pages,
                        currentPageIndex: $currentPageIndex,
                        pageWidth: geometry.size.width - 48,
                        spacing: 12,
                        onTapBackground: {
                            if isEditingName {
                                finishEditingName()
                            }
                        },
                        onAdjust: {
                            showAdjustments()
                        }
                    )
                }

                bottomControls
            }

            if isGeneratingShare || isProcessingAdjustment {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.5)
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        ZStack {
            // Center: Page indicator (always truly centered)
            Text("\(currentPageIndex + 1)/\(document.pages.count)")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.white)

            // Left and right buttons
            HStack {
                Button(action: {
                    if isEditingName { finishEditingName() }
                    onBackToScanning()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .medium))
                        Text("Scan")
                            .font(.system(size: 17))
                    }
                    .foregroundColor(.white)
                }

                Spacer()

                if document.pages.count >= 2 {
                    Button(action: {
                        if isEditingName { finishEditingName() }
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showReorderView = true
                        }
                    }) {
                        Text("Reorder")
                            .font(.system(size: 17))
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            if isEditingName { finishEditingName() }
        }
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 12) {
            HStack {
                if isEditingName {
                    TextField("Document name", text: $editedName)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.white)
                        .textFieldStyle(.plain)
                        .focused($isNameFieldFocused)
                        .onSubmit {
                            finishEditingName()
                        }
                } else {
                    Text(document.name)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.white)
                        .onTapGesture {
                            startEditingName()
                        }
                }

                Spacer()

                Button(action: {
                    if isEditingName { finishEditingName() }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        exportType = exportType == .pdf ? .images : .pdf
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: exportType == .pdf ? "doc.fill" : "photo.fill")
                            .font(.system(size: 14))
                            .frame(width: 14, height: 14)
                        Text(exportType == .pdf ? "PDF" : "Images")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .frame(width: 80)
                    .padding(.vertical, 6)
                    .background(Color.gray.opacity(0.4))
                    .cornerRadius(16)
                }
            }
            .padding(.horizontal, 20)

            Button(action: shareDocument) {
                HStack {
                    Image(systemName: exportType == .pdf ? "doc.fill" : "photo.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 22, height: 22)
                    Text(saveButtonTitle)
                        .font(.system(size: 18, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 28)
                .padding(.vertical, 16)
                .background(AppColors.accent)
                .cornerRadius(14)
                .shadow(color: AppColors.accent.opacity(0.4), radius: 8, x: 0, y: 4)
            }
            .padding(.horizontal, 20)
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Actions

    private func startEditingName() {
        editedName = document.name
        isEditingName = true
        isNameFieldFocused = true
    }

    private func finishEditingName() {
        isEditingName = false
        isNameFieldFocused = false
        if !editedName.isEmpty {
            document.name = editedName
            DocumentStorage.shared.updateDocument(document)
        }
    }

    private func deletePage(id: UUID) {
        guard let index = document.pages.firstIndex(where: { $0.id == id }) else { return }

        let page = document.pages[index]

        // Delete image files
        DocumentStorage.shared.deleteImage(filename: page.originalImagePath)
        if let cropped = page.croppedImagePath {
            DocumentStorage.shared.deleteImage(filename: cropped)
        }

        // Remove from document
        document.pages.remove(at: index)
        document.modifiedAt = Date()

        // Update storage
        if document.pages.isEmpty {
            // If no pages left, delete document and go back to scanner
            DocumentStorage.shared.deleteDocument(document)
            onBackToScanning()
        } else {
            DocumentStorage.shared.updateDocument(document)
            // Adjust current page index if needed
            if currentPageIndex >= document.pages.count {
                currentPageIndex = document.pages.count - 1
            }
        }
    }

    private func shareDocument() {
        // Apply any pending name edit before sharing
        if isEditingName {
            finishEditingName()
        }

        if exportType == .pdf {
            sharePDF()
        } else {
            shareImages()
        }
    }

    private func sharePDF() {
        // Prevent double-tap
        guard !isGeneratingShare else { return }
        isGeneratingShare = true

        // Generate PDF on background thread to avoid UI blocking
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.generatePDFForSharing()

            DispatchQueue.main.async {
                self.isGeneratingShare = false

                switch result {
                case .success(let url):
                    self.shareableContent = ShareableContent(
                        items: [url],
                        cleanup: {
                            // Clean up temporary file after sharing
                            try? FileManager.default.removeItem(at: url)
                        }
                    )
                case .failure(let error):
                    print("PDF sharing failed: \(error)")
                }
            }
        }
    }

    private func generatePDFForSharing() -> Result<URL, ShareError> {
        // Load images from document pages
        let images = document.pages.compactMap { page -> UIImage? in
            let path = page.croppedImagePath ?? page.originalImagePath
            return DocumentStorage.shared.loadImage(filename: path)
        }

        guard !images.isEmpty else {
            return .failure(.noImages)
        }

        // Generate PDF data
        guard let pdfData = PDFGenerator.shared.generatePDF(from: images) else {
            return .failure(.pdfGenerationFailed)
        }

        // Create temporary file with document name
        let sanitizedName = document.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(sanitizedName).pdf")

        // Remove existing file if present
        try? FileManager.default.removeItem(at: tempURL)

        // Write PDF to temporary file
        do {
            try pdfData.write(to: tempURL)
            return .success(tempURL)
        } catch {
            return .failure(.fileWriteFailed(error))
        }
    }

    private func shareImages() {
        let images = document.pages.compactMap { page -> UIImage? in
            let path = page.croppedImagePath ?? page.originalImagePath
            return DocumentStorage.shared.loadImage(filename: path)
        }

        guard !images.isEmpty else {
            print("No images to share")
            return
        }

        shareableContent = ShareableContent(items: images)
    }

    // MARK: - Adjustment Toolbar

    private var currentPage: ScannedPage? {
        guard currentPageIndex < document.pages.count else { return nil }
        return document.pages[currentPageIndex]
    }

    private var isCurrentPageEnhanced: Bool {
        currentPage?.filterMode != .original
    }

    private var adjustmentToolbarOverlay: some View {
        VStack {
            Spacer()

            // Tap outside to dismiss
            Color.black.opacity(0.001)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showAdjustmentToolbar = false
                    }
                }

            PageAdjustmentToolbar(
                isEnhanced: isCurrentPageEnhanced,
                onDelete: {
                    showDeleteConfirmation = true
                },
                onRotate: {
                    rotateCurrentPage()
                },
                onCrop: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showAdjustmentToolbar = false
                    }
                    showCropView = true
                },
                onRestoreEnhance: {
                    toggleEnhanceCurrentPage()
                }
            )
            .transition(.move(edge: .bottom))
        }
        .ignoresSafeArea(edges: .bottom)
    }

    @ViewBuilder
    private var cropViewContent: some View {
        if let page = currentPage,
           let originalImage = DocumentStorage.shared.loadImage(filename: page.originalImagePath) {
            CropView(
                originalImage: originalImage,
                initialCorners: page.corners,
                onCancel: {
                    showCropView = false
                },
                onApply: { newCorners in
                    applyCrop(corners: newCorners)
                    showCropView = false
                }
            )
        }
    }

    private func showAdjustments() {
        if isEditingName { finishEditingName() }
        withAnimation(.easeInOut(duration: 0.25)) {
            showAdjustmentToolbar.toggle()
        }
    }

    private func deleteCurrentPage() {
        guard currentPageIndex < document.pages.count else { return }
        let page = document.pages[currentPageIndex]
        deletePage(id: page.id)
        withAnimation(.easeInOut(duration: 0.25)) {
            showAdjustmentToolbar = false
        }
    }

    private func rotateCurrentPage() {
        guard currentPageIndex < document.pages.count else { return }
        isProcessingAdjustment = true

        let pageIndex = currentPageIndex
        let page = document.pages[pageIndex]

        DispatchQueue.global(qos: .userInitiated).async {
            autoreleasepool {
                // Load the cropped/display image (or original if no cropped)
                let imagePath = page.croppedImagePath ?? page.originalImagePath
                guard let image = DocumentStorage.shared.loadImage(filename: imagePath),
                      let rotatedImage = ImageProcessor.shared.rotateImage(image, clockwise: true) else {
                    DispatchQueue.main.async {
                        self.isProcessingAdjustment = false
                    }
                    return
                }

                // Save rotated image
                let newId = UUID()
                guard let newPath = DocumentStorage.shared.saveImage(rotatedImage, for: newId) else {
                    DispatchQueue.main.async {
                        self.isProcessingAdjustment = false
                    }
                    return
                }

                // Delete old cropped image if it exists
                if let oldCropped = page.croppedImagePath {
                    DocumentStorage.shared.deleteImage(filename: oldCropped)
                }

                DispatchQueue.main.async {
                    // Update page with new image path and clear corners (they're no longer valid)
                    self.document.pages[pageIndex].croppedImagePath = newPath
                    self.document.pages[pageIndex].corners = nil
                    self.document.modifiedAt = Date()
                    DocumentStorage.shared.updateDocument(self.document)
                    self.isProcessingAdjustment = false
                }
            }
        }
    }

    private func toggleEnhanceCurrentPage() {
        guard currentPageIndex < document.pages.count else { return }
        isProcessingAdjustment = true

        let pageIndex = currentPageIndex
        let page = document.pages[pageIndex]
        let newFilterMode: FilterMode = page.filterMode == .original ? .autoColor : .original

        DispatchQueue.global(qos: .userInitiated).async {
            autoreleasepool {
                var baseImage: UIImage?

                // If we have corners, we can re-derive the crop from the original
                if let corners = page.corners {
                    if let originalImage = DocumentStorage.shared.loadImage(filename: page.originalImagePath) {
                        baseImage = ImageProcessor.shared.correctPerspective(originalImage, corners: corners) ?? originalImage
                    }
                }
                // Otherwise, use the existing cropped image (e.g., after rotation when corners are cleared)
                else if let croppedPath = page.croppedImagePath {
                    baseImage = DocumentStorage.shared.loadImage(filename: croppedPath)
                }
                // Last resort: use original image
                else {
                    baseImage = DocumentStorage.shared.loadImage(filename: page.originalImagePath)
                }

                guard let imageToProcess = baseImage else {
                    DispatchQueue.main.async {
                        self.isProcessingAdjustment = false
                    }
                    return
                }

                // Apply new filter
                let processedImage = ImageProcessor.shared.processImage(
                    imageToProcess,
                    filterMode: newFilterMode,
                    adjustments: page.adjustments
                ) ?? imageToProcess

                // Save processed image
                let newId = UUID()
                guard let newPath = DocumentStorage.shared.saveImage(processedImage, for: newId) else {
                    DispatchQueue.main.async {
                        self.isProcessingAdjustment = false
                    }
                    return
                }

                // Delete old cropped image
                if let oldCropped = page.croppedImagePath {
                    DocumentStorage.shared.deleteImage(filename: oldCropped)
                }

                DispatchQueue.main.async {
                    self.document.pages[pageIndex].croppedImagePath = newPath
                    self.document.pages[pageIndex].filterMode = newFilterMode
                    self.document.modifiedAt = Date()
                    DocumentStorage.shared.updateDocument(self.document)
                    self.isProcessingAdjustment = false
                }
            }
        }
    }

    private func applyCrop(corners: [CGPoint]) {
        guard currentPageIndex < document.pages.count else { return }
        isProcessingAdjustment = true

        let pageIndex = currentPageIndex
        let page = document.pages[pageIndex]

        DispatchQueue.global(qos: .userInitiated).async {
            autoreleasepool {
                // Load original image
                guard let originalImage = DocumentStorage.shared.loadImage(filename: page.originalImagePath) else {
                    DispatchQueue.main.async {
                        self.isProcessingAdjustment = false
                    }
                    return
                }

                // Apply perspective correction
                guard let cropped = ImageProcessor.shared.correctPerspective(originalImage, corners: corners) else {
                    DispatchQueue.main.async {
                        self.isProcessingAdjustment = false
                    }
                    return
                }

                // Apply current filter
                let processedImage = ImageProcessor.shared.processImage(
                    cropped,
                    filterMode: page.filterMode,
                    adjustments: page.adjustments
                ) ?? cropped

                // Save processed image
                let newId = UUID()
                guard let newPath = DocumentStorage.shared.saveImage(processedImage, for: newId) else {
                    DispatchQueue.main.async {
                        self.isProcessingAdjustment = false
                    }
                    return
                }

                // Delete old cropped image
                if let oldCropped = page.croppedImagePath {
                    DocumentStorage.shared.deleteImage(filename: oldCropped)
                }

                DispatchQueue.main.async {
                    self.document.pages[pageIndex].croppedImagePath = newPath
                    self.document.pages[pageIndex].corners = corners
                    self.document.modifiedAt = Date()
                    DocumentStorage.shared.updateDocument(self.document)
                    self.isProcessingAdjustment = false
                }
            }
        }
    }
}

// MARK: - Share Errors

enum ShareError: Error, CustomStringConvertible {
    case noImages
    case pdfGenerationFailed
    case fileWriteFailed(Error)

    var description: String {
        switch self {
        case .noImages:
            return "No images found in document pages"
        case .pdfGenerationFailed:
            return "Failed to generate PDF from images"
        case .fileWriteFailed(let error):
            return "Failed to write PDF file: \(error.localizedDescription)"
        }
    }
}

// MARK: - Activity View Controller (UIKit Bridge)

/// Proper UIActivityViewController wrapper that receives items at creation time.
struct ActivityViewControllerRepresentable: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // UIActivityViewController cannot be updated - it's created once with items
    }
}

// MARK: - Page Carousel View

struct PageCarouselView: View {
    let pages: [ScannedPage]
    @Binding var currentPageIndex: Int
    let pageWidth: CGFloat
    let spacing: CGFloat
    var onTapBackground: (() -> Void)? = nil
    var onAdjust: (() -> Void)? = nil

    @State private var dragOffset: CGFloat = 0

    private var totalOffset: CGFloat {
        let pageWithSpacing = pageWidth + spacing
        return -CGFloat(currentPageIndex) * pageWithSpacing + dragOffset
    }

    var body: some View {
        GeometryReader { geometry in
            let horizontalPadding = (geometry.size.width - pageWidth) / 2

            ZStack {
                // Background to catch taps
                Color.black
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onTapBackground?()
                    }

                HStack(alignment: .center, spacing: spacing) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                        PageItemView(page: page, width: pageWidth, onTap: onTapBackground, onAdjust: onAdjust)
                            .frame(height: geometry.size.height)
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .offset(x: totalOffset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragOffset = value.translation.width
                        }
                        .onEnded { value in
                            let pageWithSpacing = pageWidth + spacing
                            let threshold = pageWidth / 3
                            var newIndex = currentPageIndex

                            if value.translation.width < -threshold {
                                newIndex = min(currentPageIndex + 1, pages.count - 1)
                            } else if value.translation.width > threshold {
                                newIndex = max(currentPageIndex - 1, 0)
                            }

                            withAnimation(.easeOut(duration: 0.25)) {
                                currentPageIndex = newIndex
                                dragOffset = 0
                            }
                        }
                )
            }
        }
    }
}

struct PageItemView: View {
    let page: ScannedPage
    let width: CGFloat
    var onTap: (() -> Void)? = nil
    var onAdjust: (() -> Void)? = nil

    var body: some View {
        GeometryReader { geometry in
            if let imagePath = page.croppedImagePath ?? Optional(page.originalImagePath),
               let image = DocumentStorage.shared.loadImage(filename: imagePath) {
                PageImageContent(
                    image: image,
                    width: width,
                    availableHeight: geometry.size.height,
                    onTap: onTap,
                    onAdjust: onAdjust
                )
            }
        }
        .frame(width: width)
    }
}

struct PageImageContent: View {
    let image: UIImage
    let width: CGFloat
    let availableHeight: CGFloat
    var onTap: (() -> Void)? = nil
    var onAdjust: (() -> Void)? = nil

    private var imageAspect: CGFloat {
        image.size.width / image.size.height
    }

    private var isHeightConstrained: Bool {
        width / availableHeight > imageAspect
    }

    private var imageWidth: CGFloat {
        isHeightConstrained ? availableHeight * imageAspect : width
    }

    private var imageHeight: CGFloat {
        isHeightConstrained ? availableHeight : width / imageAspect
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: imageWidth, height: imageHeight)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 6)
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .onTapGesture {
                    onTap?()
                }

            // Adjustment button inside bottom-right
            Button(action: {
                onAdjust?()
            }) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }
            .padding(12)
        }
        .frame(width: width, height: availableHeight)
    }
}
