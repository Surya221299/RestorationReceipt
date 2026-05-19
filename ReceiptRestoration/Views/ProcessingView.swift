//
//  ProcessingView.swift
//  VisionMLReceiptOCR
//
//  Created by Surya on 17/05/26.
//

import SwiftUI
import PhotosUI

// MARK: - ProcessingView

struct ProcessingView: View {
    let image: UIImage

    @EnvironmentObject var appState: AppState

    @State private var isProcessing: Bool = true
    @State private var parsedData: ParsedReceiptData? = nil
    @State private var ocrTexts: [OCRText] = []
    @State private var errorMessage: String? = nil
    @State private var showResultSheet: Bool = false
    @State private var sheetDetent: PresentationDetent = .medium

    var body: some View {
        GeometryReader { screen in
            ZStack(alignment: .bottom) {
                Color.black.ignoresSafeArea()

                // MARK: - Image full screen + bounding boxes
                ZStack {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: screen.size.width, height: screen.size.height)

                    // Bounding boxes overlay
                    if !ocrTexts.isEmpty {
                        BoundingBoxOverlay(
                            ocrTexts: ocrTexts,
                            imageSize: image.size,
                            displaySize: CGSize(
                                width: screen.size.width,
                                height: screen.size.height
                            )
                        )
                    }

                    if isProcessing {
                        ZStack {
                            Color.black.opacity(0.5).ignoresSafeArea()
                            VStack(spacing: 16) {
                                SparklesAnimationView()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                HStack(spacing: 8) {
                                    ProgressView().tint(.white)
                                    Text("Memproses struk…")
                                        .font(.system(size: 14))
                                        .foregroundColor(.white)
                                }
                            }
                        }
                        .transition(.opacity)
                    }
                }
                .frame(width: screen.size.width, height: screen.size.height)
                .animation(.easeInOut(duration: 0.4), value: isProcessing)
            }
        }
        .ignoresSafeArea()
        //.navigationTitle("Hasil Scan")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .task { await runOCR() }
        .onChange(of: showResultSheet) { isShowing in
            if isShowing { sheetDetent = .fraction(0.75) }
        }
        .sheet(isPresented: $showResultSheet) {
            ResultSheetView(
                parsedData: parsedData,
                onContinue: {
                    if let data = parsedData {
                        appState.addRecord(
                            date: data.date,
                            storeName: data.storeName,
                            totalString: data.total,
                            items: data.items
                        )
                    }
                    NotificationCenter.default.post(name: .dismissToHome, object: nil)
                }
            )
            .presentationDetents([.fraction(0.08), .fraction(0.75), .large], selection: $sheetDetent)
            .presentationDragIndicator(.visible)
            .presentationBackgroundInteraction(.enabled)
            .interactiveDismissDisabled(true)

        }
    }

    private func runOCR() async {
        isProcessing = true
        errorMessage = nil
        do {
            let response = try await OCRService.uploadReceipt(image: image)
            ocrTexts = response.raw
            
            // Pass originalSize.height — ini resolusi asli gambar
            // bbox dari OCR server sudah dalam koordinat original image
            parsedData = ReceiptParser.parse(
                raw: response.raw,
                imageHeight: Double(image.size.height)  // ← gunakan ini
            )
            
            withAnimation { showResultSheet = true }
        } catch {
            errorMessage = "Gagal memproses: \(error.localizedDescription)"
        }
        withAnimation { isProcessing = false }
    }
}

// MARK: - Bounding Box Overlay

struct BoundingBoxOverlay: View {
    let ocrTexts: [OCRText]
    let imageSize: CGSize
    let displaySize: CGSize

    // Hitung scale dan offset untuk scaledToFit
    private var transform: (scale: CGFloat, offsetX: CGFloat, offsetY: CGFloat) {
        let scaleX = displaySize.width / imageSize.width
        let scaleY = displaySize.height / imageSize.height
        let scale = min(scaleX, scaleY)
        let offsetX = (displaySize.width - imageSize.width * scale) / 2
        let offsetY = (displaySize.height - imageSize.height * scale) / 2
        return (scale, offsetX, offsetY)
    }

    var body: some View {
        let t = transform
        Canvas { context, size in
            for ocr in ocrTexts {
                guard ocr.bbox.count == 4 else { continue }

                // bbox: [[topLeft], [topRight], [bottomRight], [bottomLeft]]
                let points = ocr.bbox.map { pt in
                    CGPoint(
                        x: pt[0] * t.scale + t.offsetX,
                        y: pt[1] * t.scale + t.offsetY
                    )
                }

                var path = Path()
                path.move(to: points[0])
                path.addLine(to: points[1])
                path.addLine(to: points[2])
                path.addLine(to: points[3])
                path.closeSubpath()

                context.stroke(path, with: .color(.yellow.opacity(0.9)), lineWidth: 1.5)
                context.fill(path, with: .color(.yellow.opacity(0.15)))
            }
        }
        .frame(width: displaySize.width, height: displaySize.height)
        .transition(.opacity)
        .animation(.easeIn(duration: 0.3), value: ocrTexts.count)
    }
}

// MARK: - Notification

extension Notification.Name {
    static let dismissToHome = Notification.Name("dismissToHome")
}

struct ResultSheetView: View {
    let parsedData: ParsedReceiptData?
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let data = parsedData {
                    if let storeName = data.storeName {
                        Text(storeName)
                            .font(.title2.bold())
                            .frame(maxWidth: .infinity, alignment: .center)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "calendar").foregroundStyle(.secondary)
                        Text(data.date ?? "-").foregroundStyle(.secondary)
                    }

                    Divider()

                    Text("Item Belanja").font(.headline)

                    if data.items.isEmpty {
                        Text("Tidak ada item ditemukan")
                            .foregroundStyle(.secondary)
                            .italic()
                    } else {
                        ForEach(data.items) { item in
                            HStack(alignment: .top, spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name).fontWeight(.medium)
                                    if let qty = item.qty {
                                        Text(qty).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text(item.price ?? "-").fontWeight(.semibold)
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    Divider()

                    HStack {
                        Text("Total").font(.headline)
                        Spacer()
                        Text(data.total ?? "-")
                            .font(.headline)
                            .foregroundColor(Color(hex: "FF8466"))
                    }
                    .padding(.vertical, 4)

                } else {
                    Text("Tidak ada data")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 32)
                }

                Button(action: onContinue) {
                    Label("Save & Continue", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: "FF936C"), Color(hex: "FF936C").opacity(0.80)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: Color(hex: "FF936C").opacity(0.30), radius: 12, x: 0, y: 6)
                }
                .padding(.top, 8)
            }
            .padding(20)
        }
    }
}

//// MARK: - Notification
//
//extension Notification.Name {
//    static let dismissToHome = Notification.Name("dismissToHome")
//}
