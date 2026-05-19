//
//  ScanReceiptView.swift
//  VisionMLReceiptOCR
//
//  Created by Surya on 17/05/26.
//

import SwiftUI
import AVFoundation
import PhotosUI

// MARK: - ScanReceiptView
struct ScanReceiptView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var capturedImage: UIImage? = nil
    @State private var navigateToProcessing = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                // Camera live preview fills the screen
                CameraPreviewRepresentable(capturedImage: $capturedImage)
                    .ignoresSafeArea()

                // Shutter button overlay at bottom
                VStack {
                    Spacer()
                    Button {
                        // CameraPreviewRepresentable will set capturedImage via binding
                        NotificationCenter.default.post(name: .capturePhoto, object: nil)
                    } label: {
                        ZStack {
                            Circle()
                                .strokeBorder(.white, lineWidth: 4)
                                .frame(width: 76, height: 76)
                            Circle()
                                .fill(.white)
                                .frame(width: 60, height: 60)
                        }
                    }
                    .padding(.bottom, 48)
                }
            }
            .navigationTitle("Scan Struk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.black.opacity(0.6), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                // Left: close
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundColor(.white)
                            .fontWeight(.semibold)
                    }
                }
                // Right: upload image from library
                ToolbarItem(placement: .topBarTrailing) {
                    PhotosPicker(
                        selection: $selectedItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Image(systemName: "photo.badge.plus")
                            .foregroundColor(.white)
                            .fontWeight(.semibold)
                    }
                }
            }
            .onChange(of: selectedItem) { newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        capturedImage = uiImage
                    }
                }
            }
            .onChange(of: capturedImage) { image in
                if image != nil {
                    navigateToProcessing = true
                }
            }
            .navigationDestination(isPresented: $navigateToProcessing) {
                if let image = capturedImage {
                    ProcessingView(image: image)
                        .environmentObject(appState)
                }
            }
        }
    }
}

// MARK: - Camera Preview (UIViewRepresentable)

struct CameraPreviewRepresentable: UIViewRepresentable {
    @Binding var capturedImage: UIImage?

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.delegate = context.coordinator
        view.setupCamera()
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(capturedImage: $capturedImage)
    }

    class Coordinator: NSObject, CameraPreviewDelegate {
        @Binding var capturedImage: UIImage?
        init(capturedImage: Binding<UIImage?>) {
            _capturedImage = capturedImage
        }
        func didCapture(image: UIImage) {
            capturedImage = image
        }
    }
}

// MARK: - Camera Preview Delegate

protocol CameraPreviewDelegate: AnyObject {
    func didCapture(image: UIImage)
}

// MARK: - Camera UIView

class CameraPreviewView: UIView, AVCapturePhotoCaptureDelegate {
    weak var delegate: CameraPreviewDelegate?

    private var captureSession: AVCaptureSession?
    private var photoOutput = AVCapturePhotoOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }

    func setupCamera() {
        let session = AVCaptureSession()
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input),
              session.canAddOutput(photoOutput) else { return }

        session.addInput(input)
        session.addOutput(photoOutput)

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = bounds
        self.layer.insertSublayer(layer, at: 0)
        previewLayer = layer
        captureSession = session

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(capturePhoto),
            name: .capturePhoto,
            object: nil
        )

        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
            DispatchQueue.main.async {
                self.configureFocus(for: device)
            }
        }
    }

    private func configureFocus(for device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()

            // Fokus ke titik tengah layar sebagai default
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
            }
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }

            // Izinkan fokus jarak dekat (macro)
            if device.isAutoFocusRangeRestrictionSupported {
                device.autoFocusRangeRestriction = .none
            }

            // Matikan smooth autofocus — lebih responsif untuk objek bergerak/mendekat
            if device.isSmoothAutoFocusSupported {
                device.isSmoothAutoFocusEnabled = false
            }

            device.unlockForConfiguration()
        } catch {
            print("Failed to configure focus: \(error)")
        }

        // Observe perubahan fokus untuk re-trigger saat blur terdeteksi
        device.addObserver(self, forKeyPath: "adjustingFocus", options: [.new], context: nil)
    }

    // Re-trigger continuous focus otomatis setelah fokus selesai adjust
    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        guard keyPath == "adjustingFocus",
              let isAdjusting = change?[.newKey] as? Bool,
              !isAdjusting,  // baru selesai fokus
              let device = (captureSession?.inputs.first as? AVCaptureDeviceInput)?.device
        else { return }

        // Setelah selesai fokus, pastikan tetap di continuous mode
        do {
            try device.lockForConfiguration()
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            device.unlockForConfiguration()
        } catch {}
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first,
              let device = (captureSession?.inputs.first as? AVCaptureDeviceInput)?.device
        else { return }

        let point = touch.location(in: self)
        guard let focusPoint = previewLayer?.captureDevicePointConverted(fromLayerPoint: point)
        else { return }

        do {
            try device.lockForConfiguration()

            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = focusPoint
                // autoFocus dulu, lalu kembali continuous setelah terkunci
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = focusPoint
                device.exposureMode = .autoExpose
            }
            if device.isAutoFocusRangeRestrictionSupported {
                device.autoFocusRangeRestriction = .none
            }

            device.unlockForConfiguration()
        } catch {
            print("Tap to focus failed: \(error)")
        }

        // Tampilkan focus indicator di titik tap
        showFocusIndicator(at: point)
    }

    private func showFocusIndicator(at point: CGPoint) {
        let size: CGFloat = 70
        let indicator = UIView(frame: CGRect(
            x: point.x - size / 2,
            y: point.y - size / 2,
            width: size,
            height: size
        ))
        indicator.layer.borderColor = UIColor.yellow.cgColor
        indicator.layer.borderWidth = 1.5
        indicator.alpha = 1.0
        addSubview(indicator)

        UIView.animate(withDuration: 0.3, animations: {
            indicator.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        }) { _ in
            UIView.animate(withDuration: 0.2, delay: 0.5, animations: {
                indicator.alpha = 0
            }) { _ in
                indicator.removeFromSuperview()
            }
        }
    }
    @objc func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else { return }

        let cropped = cropToPortrait(image)  // rename lebih jelas
        delegate?.didCapture(image: cropped)
    }

    private func cropToPortrait(_ image: UIImage) -> UIImage {
        let normalized = normalizeOrientation(image)
        let size = normalized.size

        // Pertahankan lebar penuh, crop tinggi ke 16:9 portrait
        let targetRatio: CGFloat = 9.0 / 16.0
        let currentRatio = size.width / size.height

        var cropRect: CGRect
        if currentRatio > targetRatio {
            let newWidth = size.height * targetRatio
            cropRect = CGRect(
                x: (size.width - newWidth) / 2,
                y: 0,
                width: newWidth,
                height: size.height
            )
        } else {
            let newHeight = size.width / targetRatio
            cropRect = CGRect(
                x: 0,
                y: (size.height - newHeight) / 2,
                width: size.width,
                height: newHeight
            )
        }

        guard let cgImage = normalized.cgImage?.cropping(to: cropRect) else {
            return normalized
        }
        return UIImage(cgImage: cgImage)
    }

    private func normalizeOrientation(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        defer { UIGraphicsEndImageContext() }
        image.draw(in: CGRect(origin: .zero, size: image.size))
        return UIGraphicsGetImageFromCurrentImageContext() ?? image
    }
    private func cropTo16x9(_ image: UIImage) -> UIImage {
        let normalizedImage = normalizeOrientation(image)
        let size = normalizedImage.size

        // Portrait: 9:16 bukan 16:9
        let targetRatio: CGFloat = 9.0 / 16.0
        let currentRatio = size.width / size.height

        var cropRect: CGRect
        if currentRatio > targetRatio {
            // Terlalu lebar → crop kiri kanan, pertahankan tinggi penuh
            let newWidth = size.height * targetRatio
            cropRect = CGRect(
                x: (size.width - newWidth) / 2,
                y: 0,
                width: newWidth,
                height: size.height
            )
        } else {
            // Terlalu tinggi → crop atas bawah, pertahankan lebar penuh
            let newHeight = size.width / targetRatio
            cropRect = CGRect(
                x: 0,
                y: (size.height - newHeight) / 2,
                width: size.width,
                height: newHeight
            )
        }

        guard let cgImage = normalizedImage.cgImage?.cropping(to: cropRect) else {
            return normalizedImage
        }

        return UIImage(cgImage: cgImage)
    }

    deinit {
        if let device = (captureSession?.inputs.first as? AVCaptureDeviceInput)?.device {
            device.removeObserver(self, forKeyPath: "adjustingFocus")
        }
        NotificationCenter.default.removeObserver(self)
        captureSession?.stopRunning()
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let capturePhoto = Notification.Name("capturePhoto")
}
