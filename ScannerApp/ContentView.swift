import SwiftUI
import Vision
import UIKit

enum AppScreen {
    case home
    case scanner
    case documentPreview
}

struct ContentView: View {
    @State private var currentScreen: AppScreen = .home
    @State private var capturedImage: UIImage?
    @State private var detectedRectangle: VNRectangleObservation?
    @State private var currentDocument: ScannedDocument?
    @State private var shareItem: ShareItem?

    var body: some View {
        ZStack {
            switch currentScreen {
            case .home:
                HomeView(
                    onStartScanning: startScanning,
                    onOpenDocument: openExistingDocument
                )
                .transition(.opacity)

            case .scanner:
                ScannerView(
                    capturedImage: $capturedImage,
                    detectedRectangle: $detectedRectangle,
                    currentDocument: $currentDocument,
                    onCapture: {},
                    onDismiss: {
                        // Discard current session
                        discardCurrentDocument()
                        currentScreen = .home
                    },
                    onFinish: {
                        // Scanner finished - show share sheet for the saved document
                        if let doc = DocumentStorage.shared.documents.first,
                           let pdfPath = doc.pdfPath {
                            let url = DocumentStorage.shared.getPDFURL(filename: pdfPath)
                            shareItem = ShareItem(url: url)
                        }
                        currentDocument = nil
                        currentScreen = .home
                    }
                )
                .transition(.opacity)

            case .documentPreview:
                // Future: Document preview/edit screen
                EmptyView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: currentScreen)
        .sheet(item: $shareItem) { item in
            ShareSheetView(items: [item.url])
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

    private func openExistingDocument(_ document: ScannedDocument) {
        // Load existing document into scanner
        currentDocument = document
        capturedImage = nil
        detectedRectangle = nil
        currentScreen = .scanner
    }

    private func discardCurrentDocument() {
        guard let document = currentDocument else { return }

        // Only delete files if this is a NEW document (not saved to storage yet)
        let isExistingDocument = DocumentStorage.shared.documents.contains { $0.id == document.id }

        if !isExistingDocument {
            // Delete any saved files for this unsaved session
            for page in document.pages {
                DocumentStorage.shared.deleteImage(filename: page.originalImagePath)
                if let cropped = page.croppedImagePath {
                    DocumentStorage.shared.deleteImage(filename: cropped)
                }
            }
        }

        currentDocument = nil
    }
}

#Preview {
    ContentView()
}
