import SwiftUI
import UIKit

struct HomeView: View {
    @ObservedObject var storage = DocumentStorage.shared
    let onStartScanning: () -> Void
    let onOpenDocument: (ScannedDocument) -> Void

    @State private var showDeleteConfirm = false
    @State private var documentToDelete: ScannedDocument?
    @State private var shareableContent: ShareableContent?
    @State private var isGeneratingShare = false

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

                // Full-width scan button
                VStack {
                    Spacer()

                    Button(action: onStartScanning) {
                        HStack(spacing: 10) {
                            Image(systemName: "doc.viewfinder")
                                .font(.system(size: 22, weight: .semibold))
                            Text("Just Scan It")
                                .font(.system(size: 18, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(AppColors.accent)
                        .cornerRadius(16)
                        .shadow(color: AppColors.accent.opacity(0.4), radius: 10, x: 0, y: 5)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
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
            .sheet(item: $shareableContent, onDismiss: {
                shareableContent?.cleanup?()
            }) { content in
                ActivityViewControllerRepresentable(items: content.items)
            }
            .overlay {
                if isGeneratingShare {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    ProgressView()
                        .scaleEffect(1.5)
                }
            }
        }
    }

    private func shareDocument(_ document: ScannedDocument) {
        guard !isGeneratingShare else { return }
        isGeneratingShare = true

        DispatchQueue.global(qos: .userInitiated).async {
            let result = generatePDFForSharing(document: document)

            DispatchQueue.main.async {
                isGeneratingShare = false

                switch result {
                case .success(let url):
                    shareableContent = ShareableContent(
                        items: [url],
                        cleanup: {
                            try? FileManager.default.removeItem(at: url)
                        }
                    )
                case .failure(let error):
                    print("HomeView PDF sharing failed: \(error)")
                }
            }
        }
    }

    private func generatePDFForSharing(document: ScannedDocument) -> Result<URL, ShareError> {
        let images = document.pages.compactMap { page -> UIImage? in
            let path = page.croppedImagePath ?? page.originalImagePath
            return DocumentStorage.shared.loadImage(filename: path)
        }

        guard !images.isEmpty else {
            return .failure(.noImages)
        }

        guard let pdfData = PDFGenerator.shared.generatePDF(from: images) else {
            return .failure(.pdfGenerationFailed)
        }

        let sanitizedName = document.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(sanitizedName).pdf")

        try? FileManager.default.removeItem(at: tempURL)

        do {
            try pdfData.write(to: tempURL)
            return .success(tempURL)
        } catch {
            return .failure(.fileWriteFailed(error))
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

