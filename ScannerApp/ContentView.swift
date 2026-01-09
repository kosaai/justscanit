import SwiftUI
import Vision
import UIKit

enum AppScreen {
    case home
    case scanner
    case documentDetail
}

struct ContentView: View {
    @State private var currentScreen: AppScreen = .home
    @State private var capturedImage: UIImage?
    @State private var detectedRectangle: VNRectangleObservation?
    @State private var currentDocument: ScannedDocument?

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
                        discardCurrentDocument()
                        currentScreen = .home
                    },
                    onFinish: {
                        currentScreen = .documentDetail
                    }
                )
                .transition(.opacity)

            case .documentDetail:
                if let doc = Binding($currentDocument) {
                    DocumentDetailView(
                        document: doc,
                        onBackToScanning: {
                            currentScreen = .scanner
                        },
                        onDismiss: {
                            currentDocument = nil
                            currentScreen = .home
                        }
                    )
                    .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: currentScreen)
        .onAppear {
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
