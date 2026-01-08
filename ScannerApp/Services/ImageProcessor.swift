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

    func detectAndCrop(_ image: UIImage, rectangle: VNRectangleObservation) -> UIImage? {
        let imageSize = image.size

        // Convert normalized coordinates to image coordinates
        let topLeft = CGPoint(
            x: rectangle.topLeft.x * imageSize.width,
            y: (1 - rectangle.topLeft.y) * imageSize.height
        )
        let topRight = CGPoint(
            x: rectangle.topRight.x * imageSize.width,
            y: (1 - rectangle.topRight.y) * imageSize.height
        )
        let bottomRight = CGPoint(
            x: rectangle.bottomRight.x * imageSize.width,
            y: (1 - rectangle.bottomRight.y) * imageSize.height
        )
        let bottomLeft = CGPoint(
            x: rectangle.bottomLeft.x * imageSize.width,
            y: (1 - rectangle.bottomLeft.y) * imageSize.height
        )

        return correctPerspective(image, corners: [topLeft, topRight, bottomRight, bottomLeft])
    }
}

// Import Vision for VNRectangleObservation
import Vision
