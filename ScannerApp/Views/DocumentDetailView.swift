import SwiftUI
import UIKit

enum ExportType {
    case pdf
    case images
}

struct DocumentDetailView: View {
    @Binding var document: ScannedDocument
    let onBackToScanning: () -> Void
    let onDismiss: () -> Void

    @State private var currentPageIndex: Int = 0
    @State private var exportType: ExportType = .pdf
    @State private var isEditingName = false
    @State private var editedName: String = ""
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []

    @FocusState private var isNameFieldFocused: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                GeometryReader { geometry in
                    PageCarouselView(
                        pages: document.pages,
                        currentPageIndex: $currentPageIndex,
                        pageWidth: geometry.size.width - 48,
                        spacing: 12
                    )
                }

                bottomControls
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheetView(items: shareItems)
        }
        .onAppear {
            editedName = document.name
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button(action: onBackToScanning) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .medium))
                    Text("Scan")
                        .font(.system(size: 17))
                }
                .foregroundColor(.white)
            }

            Spacer()

            Text("\(currentPageIndex + 1)/\(document.pages.count)")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.white)

            Spacer()

            Button(action: {
                // TODO: Implement reorder
            }) {
                Text("Reorder")
                    .font(.system(size: 17))
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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
                    withAnimation(.easeInOut(duration: 0.2)) {
                        exportType = exportType == .pdf ? .images : .pdf
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: exportType == .pdf ? "doc.fill" : "photo.fill")
                            .font(.system(size: 14))
                        Text(exportType == .pdf ? "PDF" : "Images")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.gray.opacity(0.4))
                    .cornerRadius(16)
                }
            }
            .padding(.horizontal, 20)

            Button(action: shareDocument) {
                HStack {
                    Image(systemName: exportType == .pdf ? "doc.fill" : "photo.fill")
                        .font(.system(size: 18))
                    Text(exportType == .pdf ? "Save PDF" : "Save Image(s)")
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.blue)
                .cornerRadius(12)
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

    private func shareDocument() {
        if exportType == .pdf {
            sharePDF()
        } else {
            shareImages()
        }
    }

    private func sharePDF() {
        // Always generate fresh PDF to ensure it's up to date
        let images = document.pages.compactMap { page -> UIImage? in
            if let cropped = page.croppedImagePath {
                return DocumentStorage.shared.loadImage(filename: cropped)
            }
            return DocumentStorage.shared.loadImage(filename: page.originalImagePath)
        }

        guard !images.isEmpty else { return }

        if let pdfData = PDFGenerator.shared.generatePDF(from: images),
           let pdfPath = DocumentStorage.shared.savePDF(pdfData, for: document.id) {
            document.pdfPath = pdfPath
            DocumentStorage.shared.updateDocument(document)

            let pdfURL = DocumentStorage.shared.getPDFURL(filename: pdfPath)

            // Verify file exists before sharing
            if FileManager.default.fileExists(atPath: pdfURL.path) {
                shareItems = [pdfURL]
                showShareSheet = true
            }
        }
    }

    private func shareImages() {
        let images = document.pages.compactMap { page -> UIImage? in
            if let cropped = page.croppedImagePath {
                return DocumentStorage.shared.loadImage(filename: cropped)
            }
            return DocumentStorage.shared.loadImage(filename: page.originalImagePath)
        }
        shareItems = images
        showShareSheet = true
    }
}

// MARK: - Page Carousel View

struct PageCarouselView: View {
    let pages: [ScannedPage]
    @Binding var currentPageIndex: Int
    let pageWidth: CGFloat
    let spacing: CGFloat

    @State private var dragOffset: CGFloat = 0

    private var totalOffset: CGFloat {
        let pageWithSpacing = pageWidth + spacing
        return -CGFloat(currentPageIndex) * pageWithSpacing + dragOffset
    }

    var body: some View {
        GeometryReader { geometry in
            let horizontalPadding = (geometry.size.width - pageWidth) / 2

            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                    PageItemView(page: page, width: pageWidth)
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

struct PageItemView: View {
    let page: ScannedPage
    let width: CGFloat

    var body: some View {
        GeometryReader { geometry in
            if let imagePath = page.croppedImagePath ?? Optional(page.originalImagePath),
               let image = DocumentStorage.shared.loadImage(filename: imagePath) {
                PageImageContent(
                    image: image,
                    width: width,
                    availableHeight: geometry.size.height
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

            // Adjustment button inside bottom-right
            Button(action: {
                // TODO: Implement adjustments
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
