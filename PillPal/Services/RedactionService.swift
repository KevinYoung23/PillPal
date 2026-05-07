import CoreGraphics
import Foundation
import PencilKit
import UIKit

struct RedactionService {
    static func burnRedactions(
        originals: [UIImage],
        drawings: [PKDrawing],
        canvasSizes: [CGSize]
    ) -> [UIImage] {
        originals.enumerated().map { index, image in
            let drawing = index < drawings.count ? drawings[index] : PKDrawing()
            let canvasSize = index < canvasSizes.count ? canvasSizes[index] : image.size
            return burnRedaction(original: image, drawing: drawing, canvasSize: canvasSize)
        }
    }

    static func burnRedaction(
        original: UIImage,
        drawing: PKDrawing,
        canvasSize: CGSize
    ) -> UIImage {
        guard canvasSize.width > 1, canvasSize.height > 1 else {
            return original
        }

        let renderer = UIGraphicsImageRenderer(size: original.size)
        return renderer.image { context in
            original.draw(in: CGRect(origin: .zero, size: original.size))

            guard !drawing.bounds.isEmpty else { return }
            let strokeImage = drawing.image(from: CGRect(origin: .zero, size: canvasSize), scale: 1.0)
            let opaqueStrokeImage = makeOpaqueStrokeImage(from: strokeImage)

            context.cgContext.saveGState()
            context.cgContext.scaleBy(
                x: original.size.width / canvasSize.width,
                y: original.size.height / canvasSize.height
            )
            opaqueStrokeImage.draw(in: CGRect(origin: .zero, size: canvasSize), blendMode: .normal, alpha: 1.0)
            context.cgContext.restoreGState()
        }
    }

    private static func makeOpaqueStrokeImage(from image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let bitsPerComponent = 8

        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        for offset in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
            let alpha = pixels[offset + 3]
            if alpha > 0 {
                pixels[offset] = 0
                pixels[offset + 1] = 0
                pixels[offset + 2] = 0
                pixels[offset + 3] = 255
            } else {
                pixels[offset] = 0
                pixels[offset + 1] = 0
                pixels[offset + 2] = 0
                pixels[offset + 3] = 0
            }
        }

        guard let output = context.makeImage() else { return image }
        return UIImage(cgImage: output, scale: image.scale, orientation: image.imageOrientation)
    }
}
