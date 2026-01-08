import UIKit

class DocumentStorage: ObservableObject {
    static let shared = DocumentStorage()

    @Published var documents: [ScannedDocument] = []

    private let fileManager = FileManager.default
    private let documentsDirectory: URL
    private let imagesDirectory: URL
    private let pdfsDirectory: URL
    private let metadataFile: URL

    private init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        documentsDirectory = appSupport.appendingPathComponent("ScannerApp", isDirectory: true)
        imagesDirectory = documentsDirectory.appendingPathComponent("Images", isDirectory: true)
        pdfsDirectory = documentsDirectory.appendingPathComponent("PDFs", isDirectory: true)
        metadataFile = documentsDirectory.appendingPathComponent("documents.json")

        createDirectoriesIfNeeded()
        loadDocuments()
    }

    // MARK: - Directory Setup

    private func createDirectoriesIfNeeded() {
        try? fileManager.createDirectory(at: documentsDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: pdfsDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Image Storage

    func saveImage(_ image: UIImage, for pageId: UUID) -> String? {
        let filename = "\(pageId.uuidString).jpg"
        let fileURL = imagesDirectory.appendingPathComponent(filename)

        guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }

        do {
            try data.write(to: fileURL)
            return filename
        } catch {
            print("Error saving image: \(error)")
            return nil
        }
    }

    func loadImage(filename: String) -> UIImage? {
        let fileURL = imagesDirectory.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return UIImage(data: data)
    }

    func deleteImage(filename: String) {
        let fileURL = imagesDirectory.appendingPathComponent(filename)
        try? fileManager.removeItem(at: fileURL)
    }

    // MARK: - PDF Storage

    func savePDF(_ data: Data, for documentId: UUID) -> String? {
        let filename = "\(documentId.uuidString).pdf"
        let fileURL = pdfsDirectory.appendingPathComponent(filename)

        do {
            try data.write(to: fileURL)
            return filename
        } catch {
            print("Error saving PDF: \(error)")
            return nil
        }
    }

    func getPDFURL(filename: String) -> URL {
        return pdfsDirectory.appendingPathComponent(filename)
    }

    func deletePDF(filename: String) {
        let fileURL = pdfsDirectory.appendingPathComponent(filename)
        try? fileManager.removeItem(at: fileURL)
    }

    func getPDFSize(filename: String) -> Int64 {
        let fileURL = pdfsDirectory.appendingPathComponent(filename)
        guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
              let size = attributes[.size] as? Int64 else {
            return 0
        }
        return size
    }

    // MARK: - Document CRUD

    func loadDocuments() {
        guard let data = try? Data(contentsOf: metadataFile),
              let decoded = try? JSONDecoder().decode([ScannedDocument].self, from: data) else {
            documents = []
            return
        }
        documents = decoded.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    func saveDocuments() {
        guard let data = try? JSONEncoder().encode(documents) else { return }
        try? data.write(to: metadataFile)
    }

    func addDocument(_ document: ScannedDocument) {
        documents.insert(document, at: 0)
        saveDocuments()
    }

    func updateDocument(_ document: ScannedDocument) {
        if let index = documents.firstIndex(where: { $0.id == document.id }) {
            documents[index] = document
            documents.sort { $0.modifiedAt > $1.modifiedAt }
            saveDocuments()
        }
    }

    func deleteDocument(_ document: ScannedDocument) {
        // Delete associated files
        for page in document.pages {
            deleteImage(filename: page.originalImagePath)
            if let cropped = page.croppedImagePath {
                deleteImage(filename: cropped)
            }
        }
        if let pdf = document.pdfPath {
            deletePDF(filename: pdf)
        }

        // Remove from list
        documents.removeAll { $0.id == document.id }
        saveDocuments()
    }

    func getDocument(by id: UUID) -> ScannedDocument? {
        return documents.first { $0.id == id }
    }

    // MARK: - Helpers

    func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
