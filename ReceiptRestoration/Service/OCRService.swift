//
//  OCRService.swift
//  VisionMLReceiptOCR
//
//  Created by Surya on 17/05/26.
//

import UIKit

struct OCRService {

    static func uploadReceipt(image: UIImage) async throws -> OCRResponse {
        // Preprocess dulu sebelum upload
        let imageToUpload: UIImage
        if let result = ImageProcessor.preprocessImage(image) {
            print("✅ Preprocess berhasil — originalSize: \(result.originalSize), processedSize: \(result.processedSize)")

            if let processed = ImageProcessor.postprocessImage(
                data: result.data,
                width: Int(result.processedSize.width),
                height: Int(result.processedSize.height)
            ) {
                print("✅ Postprocess berhasil")

                if let cropped = ImageProcessor.cropToOriginalAspectRatio(
                    processed,
                    originalSize: result.originalSize,
                    processedSize: result.processedSize
                ) {
                    print("✅ Crop berhasil — finalSize: \(cropped.size)")
                    imageToUpload = cropped
                } else {
                    print("❌ Crop gagal — pakai original")
                    imageToUpload = image
                }
            } else {
                print("❌ Postprocess gagal — pakai original")
                imageToUpload = image
            }
        } else {
            print("❌ Preprocess gagal — pakai original")
            imageToUpload = image
        }
        let url = URL(string: "https://surya2212-paddleocrreceipt.hf.space/ocr")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120

        let boundary = UUID().uuidString
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )

        let imageData: Data
        let fileName: String
        let mimeType: String

        if let pngData = image.pngData() {
            imageData = pngData
            fileName = "receipt.png"
            mimeType = "image/png"
        } else if let jpegData = image.jpegData(compressionQuality: 0.8) {
            imageData = jpegData
            fileName = "receipt.jpg"
            mimeType = "image/jpeg"
        }
        
        else {
            throw NSError(
                domain: "ImageEncoding",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Gagal encode gambar"]
            )
        }

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        
        // Tambahkan baris ini:
        if let jsonString = String(data: data, encoding: .utf8) {
            print("RAW JSON:", jsonString)
        }

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(OCRResponse.self, from: data)
    }
}

