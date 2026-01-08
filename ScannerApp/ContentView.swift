import SwiftUI
import Vision
import UIKit

enum AppScreen {
    case home
    case scanner
    case preview
}

struct ContentView: View {
    @State private var currentScreen: AppScreen = .home
    @State private var capturedImage: UIImage?
    @State private var detectedRectangle: VNRectangleObservation?
    @State private var currentDocument: ScannedDocument?
    @State private var showShareSheet = false
    @State private var shareURL: URL?

    var body: some View {
        ZStack {
            switch currentScreen {
            case .home:
                HomeView(onStartScanning: startScanning)
                    .transition(.opacity)

            case .scanner:
                ScannerView(
                    capturedImage: $capturedImage,
                    detectedRectangle: $detectedRectangle,
                    onCapture: {
                        if capturedImage != nil {
                            currentScreen = .preview
                        }
                    },
                    onDismiss: {
                        // Save current document if has pages
                        saveCurrentDocumentIfNeeded()
                        currentScreen = .home
                    }
                )
                .transition(.opacity)

            case .preview:
                if let image = capturedImage {
                    ScanPreviewView(
                        originalImage: image,
                        detectedRectangle: detectedRectangle,
                        currentDocument: $currentDocument,
                        onKeepScanning: {
                            // Reset for next capture
                            capturedImage = nil
                            detectedRectangle = nil
                            currentScreen = .scanner
                        },
                        onSavePDF: { document in
                            // Save document and show share
                            DocumentStorage.shared.addDocument(document)
                            currentDocument = nil
                            capturedImage = nil
                            detectedRectangle = nil

                            // Share the PDF
                            if let pdfPath = document.pdfPath {
                                shareURL = DocumentStorage.shared.getPDFURL(filename: pdfPath)
                                showShareSheet = true
                            }

                            currentScreen = .home
                        },
                        onDiscard: {
                            capturedImage = nil
                            detectedRectangle = nil
                            currentScreen = .scanner
                        }
                    )
                    .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: currentScreen)
        .sheet(isPresented: $showShareSheet) {
            if let url = shareURL {
                ShareSheetView(items: [url])
            }
        }
        .onAppear {
            // Start with scanner on first launch
            if DocumentStorage.shared.documents.isEmpty {
                currentScreen = .scanner
            }
        }
    }

    private func startScanning() {
        currentDocument = nil
        capturedImage = nil
        detectedRectangle = nil
        currentScreen = .scanner
    }

    private func saveCurrentDocumentIfNeeded() {
        guard let document = currentDocument, !document.pages.isEmpty else { return }

        // Generate PDF if has pages
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

                var finalDocument = document
                if let pdfData = PDFGenerator.shared.generatePDF(from: images),
                   let pdfPath = DocumentStorage.shared.savePDF(pdfData, for: document.id) {
                    finalDocument.pdfPath = pdfPath
                }

                DispatchQueue.main.async {
                    DocumentStorage.shared.addDocument(finalDocument)
                    self.currentDocument = nil
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
