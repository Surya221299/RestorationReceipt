//
//  ReceiptRestorationModel.swift
//  ReceiptRestoration
//
//  Created by Nicholas Tristandi on 17/05/26.
//

import Foundation
import UIKit
import onnxruntime_objc

#if canImport(onnxruntime_objc)
class ReceiptRestorationModel {
    private var session: ORTSession?
    private var env: ORTEnv?

    init() {
        setupModel()
    }

    private func setupModel() {
        do {
            // Initialize ONNX Runtime environment
            env = try ORTEnv(loggingLevel: .warning)

            // Get model path
            guard let modelPath = Bundle.main.path(forResource: "receipt_restoration", ofType: "onnx") else {
                print("Error: Could not find receipt_restoration.onnx in bundle")
                return
            }

            // Create session options
            let options = try ORTSessionOptions()

            // Create session
            guard let env = env else {
                print("Error: Environment not initialized")
                return
            }

            session = try ORTSession(env: env, modelPath: modelPath, sessionOptions: options)
            print("ONNX Runtime session created successfully")

        } catch {
            print("Error setting up ONNX Runtime: \(error)")
        }
    }

    // Restores a receipt image using the ONNX model
    // - Parameter image: Input receipt image
    // - Returns: Restored image
    func restoreReceipt(_ image: UIImage) async throws -> UIImage {
        guard let session = session else {
            throw ModelError.sessionNotInitialized
        }

        // Preprocess image
        guard let (inputData, originalSize, processedSize) = ImageProcessor.preprocessImage(image) else {
            throw ModelError.imagePreprocessingFailed
        }

        // Create input tensor
        let inputShape: [NSNumber] = [1, 3, 512, 512]
        let inputTensor = try ORTValue(
            tensorData: NSMutableData(data: Data(bytes: inputData, count: inputData.count * MemoryLayout<Float>.size)),
            elementType: .float,
            shape: inputShape
        )

        // Run inference
        let inputs = ["input": inputTensor]
        let outputs = try session.run(
            withInputs: inputs,
            outputNames: ["output"],
            runOptions: nil
        )

        // Get output tensor
        guard let outputTensor = outputs["output"] else {
            throw ModelError.outputNotFound
        }

        // Get output data
        let outputData = try outputTensor.tensorData() as Data
        let floatCount = outputData.count / MemoryLayout<Float>.size
        var floatArray = [Float](repeating: 0, count: floatCount)

        outputData.withUnsafeBytes { (pointer: UnsafeRawBufferPointer) in
            if let baseAddress = pointer.baseAddress {
                floatArray = Array(UnsafeBufferPointer(
                    start: baseAddress.assumingMemoryBound(to: Float.self),
                    count: floatCount
                ))
            }
        }

        // Postprocess output
        guard let outputImage = ImageProcessor.postprocessImage(data: floatArray, width: 512, height: 512) else {
            throw ModelError.imagePostprocessingFailed
        }

        // Crop back to original aspect ratio
        guard let finalImage = ImageProcessor.cropToOriginalAspectRatio(
            outputImage,
            originalSize: originalSize,
            processedSize: processedSize
        ) else {
            throw ModelError.imageCroppingFailed
        }

        return finalImage
    }

    enum ModelError: Error, LocalizedError {
        case sessionNotInitialized
        case imagePreprocessingFailed
        case imagePostprocessingFailed
        case imageCroppingFailed
        case outputNotFound

        var errorDescription: String? {
            switch self {
            case .sessionNotInitialized:
                return "ONNX Runtime session not initialized"
            case .imagePreprocessingFailed:
                return "Failed to preprocess image"
            case .imagePostprocessingFailed:
                return "Failed to postprocess image"
            case .imageCroppingFailed:
                return "Failed to crop image"
            case .outputNotFound:
                return "Model output not found"
            }
        }
    }
}
#else
class ReceiptRestorationModel {
    init() {}

    // Restores a receipt image using the ONNX model
    // - Parameter image: Input receipt image
    // - Returns: Restored image
    func restoreReceipt(_ image: UIImage) async throws -> UIImage {
        throw ModelError.onnxRuntimeUnavailable
    }

    enum ModelError: Error, LocalizedError {
        case onnxRuntimeUnavailable

        var errorDescription: String? {
            switch self {
            case .onnxRuntimeUnavailable:
                return "ONNX Runtime is not available. Add the 'onnxruntime' package to this target to enable inference."
            }
        }
    }
}
#endif

