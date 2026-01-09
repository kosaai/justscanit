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

    @State private var showDeleteConfirm = false
    @State private var documentToDelete: ScannedDocument?
    @State private var shareItem: ShareItem?

    var body: some View {
        NavigationView {
            ZStack {
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
                    // Document list
                    List {
                        Section(header: Text("All scans")) {
                            ForEach(storage.documents) { document in
                                DocumentRow(
                                    document: document,
                                    onShare: { shareDocument(document) },
                                    onDelete: {
                                        documentToDelete = document
                                        showDeleteConfirm = true
                                    }
                                )
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
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
            .navigationTitle("Scanner")
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
            // Generate PDF if not exists
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

// MARK: - Document Row

struct DocumentRow: View {
    let document: ScannedDocument
    let onShare: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            if let thumbPath = document.thumbnailPath,
               let thumbnail = DocumentStorage.shared.loadImage(filename: thumbPath) {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 50, height: 65)
                    .cornerRadius(6)
                    .clipped()
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.systemGray5))
                    .frame(width: 50, height: 65)
                    .overlay(
                        Image(systemName: "doc")
                            .foregroundColor(.secondary)
                    )
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(document.name)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(formatDate(document.modifiedAt))
                        .font(.caption)
                        .foregroundColor(.secondary)

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
                    .foregroundColor(.secondary)
                    .padding(8)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "'Today'"
        } else if Calendar.current.isDateInYesterday(date) {
            formatter.dateFormat = "'Yesterday'"
        } else {
            formatter.dateFormat = "MMM d, yyyy"
        }
        return formatter.string(from: date)
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
