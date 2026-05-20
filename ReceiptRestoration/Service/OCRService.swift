//
//  OCRService.swift
//  VisionMLReceiptOCR
//
//  Created by Surya on 17/05/26.
//

import UIKit

// Wrapper response agar caller tahu ukuran gambar yang benar-benar di-upload ke server.
// Ini penting supaya BoundingBoxOverlay dan ReceiptParser pakai koordinat yang tepat.
struct OCRUploadResult {
    let response: OCRResponse
    /// Ukuran gambar yang di-upload ke server (setelah downscale + preprocess).
    /// Gunakan ini sebagai `imageSize` di BoundingBoxOverlay dan `imageHeight` di ReceiptParser.
    let uploadedSize: CGSize
}

struct OCRService {

    // Maksimum dimensi gambar yang dikirim ke server.
    // Foto kamera iPhone bisa 4032x3024 — server OCR tidak butuh resolusi setinggi itu.
    // 1280px sudah cukup untuk teks struk dan jauh lebih cepat diupload.
    private static let maxUploadDimension: CGFloat = 1280

    static func uploadReceipt(image: UIImage) async throws -> OCRUploadResult {

        // 1. Downscale dulu ke resolusi yang wajar sebelum preprocessing apapun.
        let downscaled = downscaleIfNeeded(image, maxDimension: maxUploadDimension)
        print("📐 Ukuran setelah downscale: \(downscaled.size) (original: \(image.size))")

        // 2. Preprocess (resize ke 512x512, convert ke float array, dsb.)
        let imageToUpload: UIImage
        if let result = ImageProcessor.preprocessImage(downscaled) {
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
                    print("❌ Crop gagal — pakai downscaled")
                    imageToUpload = downscaled
                }
            } else {
                print("❌ Postprocess gagal — pakai downscaled")
                imageToUpload = downscaled
            }
        } else {
            print("❌ Preprocess gagal — pakai downscaled")
            imageToUpload = downscaled
        }

        // Catat ukuran final yang benar-benar di-upload.
        // Ini yang harus dipakai untuk menerjemahkan koordinat bbox dari server.
        let uploadedSize = imageToUpload.size
        print("📏 uploadedSize (koordinat bbox server): \(uploadedSize)")

        // 3. Encode ke JPEG — jauh lebih kecil dari PNG untuk foto struk.
        let imageData: Data
        let fileName: String
        let mimeType: String

        if let jpegData = imageToUpload.jpegData(compressionQuality: 0.85) {
            imageData = jpegData
            fileName = "receipt.jpg"
            mimeType = "image/jpeg"
            print("📦 Ukuran payload JPEG: \(jpegData.count / 1024) KB")
        } else {
            throw NSError(
                domain: "ImageEncoding",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Gagal encode gambar ke JPEG"]
            )
        }

        // 4. Build & send request
        let url = URL(string: "https://surya2212-paddleocrreceipt.hf.space/ocr")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120

        let boundary = UUID().uuidString
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        let (data, response) = try await URLSession.shared.upload(for: request, from: body)

        if let jsonString = String(data: data, encoding: .utf8) {
            print("RAW JSON:", jsonString)
        }

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let ocrResponse = try JSONDecoder().decode(OCRResponse.self, from: data)
        return OCRUploadResult(response: ocrResponse, uploadedSize: uploadedSize)
    }

    // MARK: - Private Helper

    /// Downscale gambar jika salah satu dimensinya melebihi `maxDimension`.
    /// Aspect ratio tetap dipertahankan. Jika sudah kecil, kembalikan gambar asli.
    private static func downscaleIfNeeded(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let largestSide = max(size.width, size.height)

        guard largestSide > maxDimension else {
            return image
        }

        let ratio = maxDimension / largestSide
        let newSize = CGSize(
            width: (size.width * ratio).rounded(),
            height: (size.height * ratio).rounded()
        )

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
