//
//  ImageProcessor.swift
//  ReceiptRestoration
//
//  Created by Nicholas Tristandi on 17/05/26.
//

import UIKit
import CoreImage
import Accelerate

class ImageProcessor {

    // Converts a UIImage to a float array in NCHW format normalized to [0, 1]
    // - Parameter image: Input UIImage
    // - Returns: Tuple of (float array, original size, processed size)
    static func preprocessImage(_ image: UIImage) -> (data: [Float], originalSize: CGSize, processedSize: CGSize)? {
        // Target size for the model
        let targetSize = CGSize(width: 512, height: 512)

        // Resize image while maintaining aspect ratio
        guard let resizedImage = resizeImage(image, targetSize: targetSize) else {
            return nil
        }

        guard let cgImage = resizedImage.cgImage else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height

        // Create bitmap context
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let pixelBuffer = context.data else {
            return nil
        }

        let pixels = pixelBuffer.assumingMemoryBound(to: UInt8.self)
        let pixelCount = width * height

        // Convert to NCHW format: [batch, channels, height, width]
        // Normalize to [0, 1]
        var floatArray = [Float](repeating: 0, count: pixelCount * 3)

        for i in 0..<pixelCount {
            let r = Float(pixels[i * 4 + 0]) / 255.0
            let g = Float(pixels[i * 4 + 1]) / 255.0
            let b = Float(pixels[i * 4 + 2]) / 255.0

            // NCHW format: all R values, then all G values, then all B values
            floatArray[i] = r
            floatArray[pixelCount + i] = g
            floatArray[pixelCount * 2 + i] = b
        }

        return (floatArray, image.size, CGSize(width: width, height: height))
    }

    // Converts a float array in NCHW format back to UIImage
    // - Parameters:
    //   - data: Float array in NCHW format with values in [0, 1]
    //   - width: Image width
    //   - height: Image height
    // - Returns: UIImage
    static func postprocessImage(data: [Float], width: Int, height: Int) -> UIImage? {
        let pixelCount = width * height

        guard data.count == pixelCount * 3 else {
            return nil
        }

        // Convert NCHW to RGB interleaved format
        var pixels = [UInt8](repeating: 0, count: pixelCount * 4)

        for i in 0..<pixelCount {
            let r = data[i]
            let g = data[pixelCount + i]
            let b = data[pixelCount * 2 + i]

            // Clamp values to [0, 1] and convert to UInt8
            pixels[i * 4 + 0] = UInt8(max(0, min(1, r)) * 255)
            pixels[i * 4 + 1] = UInt8(max(0, min(1, g)) * 255)
            pixels[i * 4 + 2] = UInt8(max(0, min(1, b)) * 255)
            pixels[i * 4 + 3] = 255 // Alpha
        }

        // Create CGImage from pixel data
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitsPerComponent = 8
        let bytesPerRow = width * 4

        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else {
            return nil
        }

        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    // Resizes an image to target size while maintaining aspect ratio with padding
    // - Parameters:
    //   - image: Input image
    //   - targetSize: Target size
    // - Returns: Resized image
    static func resizeImage(_ image: UIImage, targetSize: CGSize) -> UIImage? {
        let size = image.size
        let widthRatio = targetSize.width / size.width
        let heightRatio = targetSize.height / size.height

        // Use the smaller ratio to maintain aspect ratio
        let ratio = min(widthRatio, heightRatio)
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)

        // Calculate padding
        let xOffset = (targetSize.width - newSize.width) / 2
        let yOffset = (targetSize.height - newSize.height) / 2

        UIGraphicsBeginImageContextWithOptions(targetSize, false, 1.0)
        defer { UIGraphicsEndImageContext() }

        // Fill with black background
        UIColor.black.setFill()
        UIRectFill(CGRect(origin: .zero, size: targetSize))

        // Draw image centered with padding
        image.draw(in: CGRect(x: xOffset, y: yOffset, width: newSize.width, height: newSize.height))

        return UIGraphicsGetImageFromCurrentImageContext()
    }

    // Crops the padded image back to original aspect ratio
    // - Parameters:
    //   - image: Padded image
    //   - originalSize: Original image size
    //   - processedSize: Processed image size (512x512)
    // - Returns: Cropped image
    static func cropToOriginalAspectRatio(_ image: UIImage, originalSize: CGSize, processedSize: CGSize) -> UIImage? {
        let size = originalSize
        let widthRatio = processedSize.width / size.width
        let heightRatio = processedSize.height / size.height
        let ratio = min(widthRatio, heightRatio)

        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        let xOffset = (processedSize.width - newSize.width) / 2
        let yOffset = (processedSize.height - newSize.height) / 2

        guard let cgImage = image.cgImage else {
            return nil
        }

        let cropRect = CGRect(x: xOffset, y: yOffset, width: newSize.width, height: newSize.height)

        guard let croppedCGImage = cgImage.cropping(to: cropRect) else {
            return nil
        }

        return UIImage(cgImage: croppedCGImage)
    }
}
