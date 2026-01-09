import SwiftUI
import UIKit

// Wrapper to make URL identifiable for sheet presentation
struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct HomeView: View {
    @ObservedObject var storage = DocumentStorage.shared
    let onStartScanning: () -> Void
    let onOpenDocument: (ScannedDocument) -> Void

    @State private var showDeleteConfirm = false
    @State private var documentToDelete: ScannedDocument?
    @State private var shareItem: ShareItem?

    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color(.systemBackground)
                    .ignoresSafeArea()

                if storage.documents.isEmpty {
                    // Empty state
                    VStack(spacing: 20) {
                        Image(systemName: "doc.viewfinder")
                            .font(.system(size: 70))
                            .foregroundColor(.secondary)

                        Text("No Scans Yet")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("Tap the button below to scan your first document")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                } else {
                    // Document list - edge to edge
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(storage.documents) { document in
                                DocumentCard(
                                    document: document,
                                    onTap: { onOpenDocument(document) },
                                    onShare: { shareDocument(document) },
                                    onDelete: {
                                        documentToDelete = document
                                        showDeleteConfirm = true
                                    }
                                )

                                if document.id != storage.documents.last?.id {
                                    Divider()
                                        .padding(.leading, 16)
                                }
                            }
                        }
                        .padding(.bottom, 100) // Space for FAB
                    }
                }

                // Floating scan button
                VStack {
                    Spacer()

                    Button(action: onStartScanning) {
                        ZStack {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 64, height: 64)
                                .shadow(color: .blue.opacity(0.4), radius: 8, x: 0, y: 4)

                            Image(systemName: "doc.viewfinder")
                                .font(.title2)
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Scans")
            .alert("Delete Document?", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    if let doc = documentToDelete {
                        storage.deleteDocument(doc)
                    }
                }
            } message: {
                Text("This will permanently delete the document and all its pages.")
            }
            .sheet(item: $shareItem) { item in
                ShareSheetView(items: [item.url])
            }
        }
    }

    private func shareDocument(_ document: ScannedDocument) {
        guard let pdfPath = document.pdfPath else {
            regeneratePDF(for: document)
            return
        }

        let url = DocumentStorage.shared.getPDFURL(filename: pdfPath)
        shareItem = ShareItem(url: url)
    }

    private func regeneratePDF(for document: ScannedDocument) {
        DispatchQueue.global(qos: .userInitiated).async {
            autoreleasepool {
                let images = document.pages.compactMap { page -> UIImage? in
                    autoreleasepool {
                        if let cropped = page.croppedImagePath {
                            return DocumentStorage.shared.loadImage(filename: cropped)
                        }
                        return DocumentStorage.shared.loadImage(filename: page.originalImagePath)
                    }
                }

                if let pdfData = PDFGenerator.shared.generatePDF(from: images),
                   let pdfPath = DocumentStorage.shared.savePDF(pdfData, for: document.id) {
                    var updatedDoc = document
                    updatedDoc.pdfPath = pdfPath
                    DocumentStorage.shared.updateDocument(updatedDoc)

                    DispatchQueue.main.async {
                        let url = DocumentStorage.shared.getPDFURL(filename: pdfPath)
                        self.shareItem = ShareItem(url: url)
                    }
                }
            }
        }
    }
}

// MARK: - Document Card (Bigger preview like Scannable)

struct DocumentCard: View {
    let document: ScannedDocument
    let onTap: () -> Void
    let onShare: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 16) {
                // Large thumbnail with stacked pages effect
                DocumentThumbnailStack(document: document)

                // Info
                VStack(alignment: .leading, spacing: 6) {
                    Text(document.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(formatDateTime(document.modifiedAt))
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        if let pdfPath = document.pdfPath {
                            Text(DocumentStorage.shared.formatFileSize(
                                DocumentStorage.shared.getPDFSize(filename: pdfPath)
                            ))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }

                        Text("\(document.pageCount) page\(document.pageCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Actions menu
                Menu {
                    Button(action: onShare) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .frame(width: 32, height: 32)
                }
            }
            .padding(16)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "'Today,' h:mm a"
        } else if Calendar.current.isDateInYesterday(date) {
            formatter.dateFormat = "'Yesterday,' h:mm a"
        } else {
            formatter.dateFormat = "MMM d, yyyy"
        }
        return formatter.string(from: date)
    }
}

// MARK: - Document Thumbnail Stack (shows stacked pages like Scannable)

struct DocumentThumbnailStack: View {
    let document: ScannedDocument

    private let thumbnailWidth: CGFloat = 100
    private let thumbnailHeight: CGFloat = 130

    var body: some View {
        ZStack {
            // Show stacked effect for multi-page documents
            if document.pageCount > 1 {
                // Back page (offset)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.systemGray5))
                    .frame(width: thumbnailWidth - 8, height: thumbnailHeight - 8)
                    .offset(x: 6, y: 6)

                if document.pageCount > 2 {
                    // Middle page
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.systemGray4))
                        .frame(width: thumbnailWidth - 4, height: thumbnailHeight - 4)
                        .offset(x: 3, y: 3)
                }
            }

            // Front page (main thumbnail)
            if let firstPage = document.pages.first {
                let imagePath = firstPage.croppedImagePath ?? firstPage.originalImagePath
                if let image = DocumentStorage.shared.loadImage(filename: imagePath) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: thumbnailWidth, height: thumbnailHeight)
                        .cornerRadius(6)
                        .clipped()
                        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                } else {
                    placeholderThumbnail
                }
            } else {
                placeholderThumbnail
            }

            // Page count badge
            if document.pageCount > 1 {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("\(document.pageCount)")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color(.systemBackground))
                                    .shadow(color: .black.opacity(0.15), radius: 1, x: 0, y: 1)
                            )
                    }
                }
                .frame(width: thumbnailWidth + 8, height: thumbnailHeight + 8)
            }
        }
        .frame(width: thumbnailWidth + 10, height: thumbnailHeight + 10)
    }

    private var placeholderThumbnail: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color(.systemGray5))
            .frame(width: thumbnailWidth, height: thumbnailHeight)
            .overlay(
                Image(systemName: "doc")
                    .font(.title)
                    .foregroundColor(.secondary)
            )
    }
}

// MARK: - Share Sheet

struct ShareSheetView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
