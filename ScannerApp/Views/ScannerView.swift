import SwiftUI
import AVFoundation
import Vision
import UIKit

struct ScannerView: View {
    @StateObject private var cameraManager = CameraManager()
    @Binding var capturedImage: UIImage?
    @Binding var detectedRectangle: VNRectangleObservation?
    let onCapture: () -> Void
    let onDismiss: () -> Void

    @State private var showCaptureAnimation = false

    var body: some View {
        ZStack {
            // Black background for letterboxing
            Color.black.ignoresSafeArea()

            // Camera preview
            GeometryReader { geometry in
                ZStack {
                    CameraPreviewView(session: cameraManager.session)
                        .ignoresSafeArea()

                    // Edge detection overlay
                    EdgeOverlayView(
                        rectangle: cameraManager.detectedRectangle,
                        viewSize: geometry.size
                    )

                    // Capture flash animation
                    if showCaptureAnimation {
                        Color.white
                            .ignoresSafeArea()
                            .transition(.opacity)
                    }

                    // Status indicator
                    VStack {
                        Spacer()

                        if cameraManager.detectedRectangle != nil {
                            Text("Document detected")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(20)
                                .padding(.bottom, 120)
                        }
                    }
                }
            }

            // Controls overlay
            VStack {
                // Top bar
                HStack {
                    Button(action: onDismiss) {
                        Image(systemName: "house.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)

                Spacer()

                // Bottom controls
                HStack {
                    Spacer()

                    // Capture button
                    Button(action: capturePhoto) {
                        ZStack {
                            Circle()
                                .stroke(Color.white, lineWidth: 4)
                                .frame(width: 70, height: 70)

                            Circle()
                                .fill(Color.white)
                                .frame(width: 58, height: 58)
                        }
                    }
                    .disabled(cameraManager.isCapturing)

                    Spacer()
                }
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            cameraManager.setupCamera()
            cameraManager.startSession()
        }
        .onDisappear {
            cameraManager.stopSession()
        }
        .onChange(of: cameraManager.capturedImage) { (newImage: UIImage?) in
            if let image = newImage {
                capturedImage = image
                detectedRectangle = cameraManager.detectedRectangle
                onCapture()
            }
        }
    }

    private func capturePhoto() {
        withAnimation(.easeInOut(duration: 0.1)) {
            showCaptureAnimation = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation {
                showCaptureAnimation = false
            }
        }

        cameraManager.capturePhoto()
    }
}
