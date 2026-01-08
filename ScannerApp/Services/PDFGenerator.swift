import UIKit
import PDFKit

class PDFGenerator {
    static let shared = PDFGenerator()

    private init() {}

    // MARK: - Generate PDF from Images

    func generatePDF(from images: [UIImage], title: String = "Scanned Document") -> Data? {
        let pdfDocument = PDFDocument()

        for (index, image) in images.enumerated() {
            autoreleasepool {
                if let pdfPage = PDFPage(image: image) {
                    pdfDocument.insert(pdfPage, at: index)
                }
            }
        }

        return pdfDocument.dataRepresentation()
    }

    // MARK: - Save PDF to Files

    func savePDF(_ data: Data, fileName: String) -> URL? {
        let fileManager = FileManager.default

        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }

        let sanitizedName = fileName.replacingOccurrences(of: "/", with: "-")
        let fileURL = documentsURL.appendingPathComponent("\(sanitizedName).pdf")

        do {
            try data.write(to: fileURL)
            return fileURL
        } catch {
            print("Error saving PDF: \(error)")
            return nil
        }
    }

    // MARK: - Get Temporary PDF URL for Sharing

    func createTemporaryPDF(from images: [UIImage], fileName: String = "Scan") -> URL? {
        guard let pdfData = generatePDF(from: images) else { return nil }

        let tempDir = FileManager.default.temporaryDirectory
        let sanitizedName = fileName.replacingOccurrences(of: "/", with: "-")
        let fileURL = tempDir.appendingPathComponent("\(sanitizedName).pdf")

        do {
            try pdfData.write(to: fileURL)
            return fileURL
        } catch {
            print("Error creating temporary PDF: \(error)")
            return nil
        }
    }
}
