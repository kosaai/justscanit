import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

class ImageProcessor {
    static let shared = ImageProcessor()
    private let context = CIContext(options: [.useSoftwareRenderer: false])

    private init() {}

    // MARK: - Process with Filter and Adjustments

    func processImage(
        _ image: UIImage,
        filterMode: FilterMode,
        adjustments: ImageAdjustments
    ) -> UIImage? {
        return autoreleasepool {
            guard let ciImage = CIImage(image: image) else { return nil }

            var output = ciImage

            // Apply filter mode
            switch filterMode {
            case .original:
                // No filter, just pass through
                break
            case .autoColor:
                output = applyAutoColorFilter(output)
            case .grayscale:
                output = applyGrayscaleFilter(output)
            }

            // Apply manual adjustments
            output = applyAdjustments(output, adjustments: adjustments)

            // Render output
            guard let cgImage = context.createCGImage(output, from: output.extent) else {
                return nil
            }

            return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
        }
    }

    // MARK: - Auto Color Filter

    private func applyAutoColorFilter(_ image: CIImage) -> CIImage {
        var output = image

        // Use document enhancer if available
        if #available(iOS 15.0, *) {
            if let documentEnhancer = CIFilter(name: "CIDocumentEnhancer") {
                documentEnhancer.setValue(output, forKey: kCIInputImageKey)
                documentEnhancer.setValue(1.0, forKey: "inputAmount")
                if let result = documentEnhancer.outputImage {
                    output = result
                }
            }
        }

        // Boost exposure
        let exposure = CIFilter.exposureAdjust()
        exposure.inputImage = output
        exposure.ev = 0.4
        output = exposure.outputImage ?? output

        // Increase contrast and brightness
        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = output
        colorControls.brightness = 0.05
        colorControls.contrast = 1.1
        output = colorControls.outputImage ?? output

        // Adjust highlights and shadows
        let highlightShadow = CIFilter.highlightShadowAdjust()
        highlightShadow.inputImage = output
        highlightShadow.highlightAmount = 0.9
        highlightShadow.shadowAmount = 0.2
        output = highlightShadow.outputImage ?? output

        // Sharpen
        let sharpen = CIFilter.unsharpMask()
        sharpen.inputImage = output
        sharpen.radius = 1.5
        sharpen.intensity = 0.5
        output = sharpen.outputImage ?? output

        return output
    }

    // MARK: - Grayscale Filter

    private func applyGrayscaleFilter(_ image: CIImage) -> CIImage {
        var output = image

        // First apply auto-color processing
        output = applyAutoColorFilter(output)

        // Convert to grayscale
        let grayscale = CIFilter.colorControls()
        grayscale.inputImage = output
        grayscale.saturation = 0
        output = grayscale.outputImage ?? output

        return output
    }

    // MARK: - Manual Adjustments

    private func applyAdjustments(_ image: CIImage, adjustments: ImageAdjustments) -> CIImage {
        var output = image

        // Skip if default values
        guard adjustments != .default else { return output }

        // Exposure
        if adjustments.exposure != 0 {
            let exposure = CIFilter.exposureAdjust()
            exposure.inputImage = output
            exposure.ev = adjustments.exposure
            output = exposure.outputImage ?? output
        }

        // Brightness and contrast
        if adjustments.brightness != 0 || adjustments.contrast != 1 {
            let colorControls = CIFilter.colorControls()
            colorControls.inputImage = output
            colorControls.brightness = adjustments.brightness
            colorControls.contrast = adjustments.contrast
            output = colorControls.outputImage ?? output
        }

        return output
    }

    // MARK: - Perspective Correction

    func correctPerspective(_ image: UIImage, corners: [CGPoint]) -> UIImage? {
        return autoreleasepool {
            guard corners.count == 4,
                  let ciImage = CIImage(image: image) else { return nil }

            // Convert corners from view coordinates to image coordinates
            let imageSize = image.size

            // Corners are: topLeft, topRight, bottomRight, bottomLeft
            // CIFilter expects coordinates in image space (origin bottom-left)
            let topLeft = CGPoint(x: corners[0].x, y: imageSize.height - corners[0].y)
            let topRight = CGPoint(x: corners[1].x, y: imageSize.height - corners[1].y)
            let bottomRight = CGPoint(x: corners[2].x, y: imageSize.height - corners[2].y)
            let bottomLeft = CGPoint(x: corners[3].x, y: imageSize.height - corners[3].y)

            let perspectiveCorrection = CIFilter.perspectiveCorrection()
            perspectiveCorrection.inputImage = ciImage
            perspectiveCorrection.topLeft = topLeft
            perspectiveCorrection.topRight = topRight
            perspectiveCorrection.bottomRight = bottomRight
            perspectiveCorrection.bottomLeft = bottomLeft

            guard let output = perspectiveCorrection.outputImage,
                  let cgImage = context.createCGImage(output, from: output.extent) else {
                return nil
            }

            return UIImage(cgImage: cgImage, scale: image.scale, orientation: .up)
        }
    }

    // MARK: - Detect and Crop

    /// Inset margin as a percentage (0.02 = 2% inward from each edge)
    private let cropMarginPercent: CGFloat = 0.02

    func detectAndCrop(_ image: UIImage, rectangle: VNRectangleObservation) -> UIImage? {
        let imageSize = image.size

        // Convert normalized coordinates to image coordinates
        var topLeft = CGPoint(
            x: rectangle.topLeft.x * imageSize.width,
            y: (1 - rectangle.topLeft.y) * imageSize.height
        )
        var topRight = CGPoint(
            x: rectangle.topRight.x * imageSize.width,
            y: (1 - rectangle.topRight.y) * imageSize.height
        )
        var bottomRight = CGPoint(
            x: rectangle.bottomRight.x * imageSize.width,
            y: (1 - rectangle.bottomRight.y) * imageSize.height
        )
        var bottomLeft = CGPoint(
            x: rectangle.bottomLeft.x * imageSize.width,
            y: (1 - rectangle.bottomLeft.y) * imageSize.height
        )

        // Apply inward margin to crop slightly inside the detected edges
        // This helps remove any background that Vision may have included
        let corners = applyInwardMargin(
            topLeft: &topLeft,
            topRight: &topRight,
            bottomRight: &bottomRight,
            bottomLeft: &bottomLeft,
            marginPercent: cropMarginPercent
        )

        return correctPerspective(image, corners: corners)
    }

    /// Get corners from rectangle with inward margin applied (for crop tool initialization)
    func getCornersFromRectangle(_ rectangle: VNRectangleObservation, imageSize: CGSize) -> [CGPoint] {
        var topLeft = CGPoint(
            x: rectangle.topLeft.x * imageSize.width,
            y: (1 - rectangle.topLeft.y) * imageSize.height
        )
        var topRight = CGPoint(
            x: rectangle.topRight.x * imageSize.width,
            y: (1 - rectangle.topRight.y) * imageSize.height
        )
        var bottomRight = CGPoint(
            x: rectangle.bottomRight.x * imageSize.width,
            y: (1 - rectangle.bottomRight.y) * imageSize.height
        )
        var bottomLeft = CGPoint(
            x: rectangle.bottomLeft.x * imageSize.width,
            y: (1 - rectangle.bottomLeft.y) * imageSize.height
        )

        return applyInwardMargin(
            topLeft: &topLeft,
            topRight: &topRight,
            bottomRight: &bottomRight,
            bottomLeft: &bottomLeft,
            marginPercent: cropMarginPercent
        )
    }

    /// Apply inward margin by moving each corner toward the center
    private func applyInwardMargin(
        topLeft: inout CGPoint,
        topRight: inout CGPoint,
        bottomRight: inout CGPoint,
        bottomLeft: inout CGPoint,
        marginPercent: CGFloat
    ) -> [CGPoint] {
        // Calculate center of the quadrilateral
        let centerX = (topLeft.x + topRight.x + bottomRight.x + bottomLeft.x) / 4
        let centerY = (topLeft.y + topRight.y + bottomRight.y + bottomLeft.y) / 4
        let center = CGPoint(x: centerX, y: centerY)

        // Move each corner toward center by marginPercent
        func moveTowardCenter(_ point: CGPoint) -> CGPoint {
            return CGPoint(
                x: point.x + (center.x - point.x) * marginPercent,
                y: point.y + (center.y - point.y) * marginPercent
            )
        }

        return [
            moveTowardCenter(topLeft),
            moveTowardCenter(topRight),
            moveTowardCenter(bottomRight),
            moveTowardCenter(bottomLeft)
        ]
    }

    // MARK: - Rotation

    func rotateImage(_ image: UIImage, clockwise: Bool = true) -> UIImage? {
        return autoreleasepool {
            let rotatedSize = CGSize(width: image.size.height, height: image.size.width)

            let format = UIGraphicsImageRendererFormat()
            format.scale = image.scale

            let renderer = UIGraphicsImageRenderer(size: rotatedSize, format: format)
            return renderer.image { _ in
                guard let context = UIGraphicsGetCurrentContext() else { return }

                // Move origin to center of rotated canvas
                context.translateBy(x: rotatedSize.width / 2, y: rotatedSize.height / 2)

                // Rotate - in UIKit coordinates (Y down), positive angle is clockwise
                context.rotate(by: clockwise ? .pi / 2 : -.pi / 2)

                // Draw image centered at origin using UIImage.draw which handles orientation correctly
                image.draw(in: CGRect(
                    x: -image.size.width / 2,
                    y: -image.size.height / 2,
                    width: image.size.width,
                    height: image.size.height
                ))
            }
        }
    }
}

// Import Vision for VNRectangleObservation
import Vision
