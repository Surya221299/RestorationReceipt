# ReceiptRestoration

An iOS application for scanning, restoring, and parsing paper receipts into structured expense records using on-device image preprocessing, ONNX machine learning models, and OCR.

![Application Screenshot](screenshot.jpeg)

## Features

- Camera & Photo Library Scanner: Live camera capture viewfinder and photo gallery picker.
- Image Preprocessing & Restoration: Enhances degraded receipt images using an ONNX runtime model and Apple Accelerate/CoreImage frameworks.
- Optical Character Recognition (OCR): Detects text and bounding box coordinates via a PaddleOCR service.
- Smart Receipt Parser: Spatial- and regex-based extraction of store name, transaction date, line items (quantities and prices), and total amounts.
- Bounding Box Visualization: Overlays detected OCR text regions directly onto the scanned image.
- Expense Tracking: Local transaction history and cumulative spending summary.

## Tech Stack

- Platform: iOS 16.1+
- Language: Swift 5
- Frameworks: SwiftUI, Accelerate, CoreImage, AVFoundation
- ML Engine: ONNX Runtime Mobile (`onnxruntime-objc`)
- OCR Engine: PaddleOCR API
- Dependency Manager: CocoaPods

## Project Structure

```text
RestorationReceipt/
├── ReceiptRestoration/
│   ├── Models/            # Data models and ONNX inference wrappers
│   ├── ONNX Models/       # Model files (.onnx) for image restoration
│   ├── Service/           # OCR networking and heuristic parsing logic
│   ├── ViewModels/        # Global app state and image processing pipeline
│   └── Views/             # SwiftUI views (Scanner, Processing, History)
├── Podfile                # CocoaPods configuration
└── ReceiptRestoration.xcworkspace
```

## Getting Started

### Prerequisites

- macOS with Xcode 15 or later
- iOS 16.1+ deployment target
- CocoaPods installed

### Installation

1. Clone the repository:
   ```bash
   git clone github.com/Surya221299/RestorationReceipt.git
   cd RestorationReceipt-main
   ```

2. Install CocoaPods dependencies:
   ```bash
   pod install
   ```

3. Open the project in Xcode:
   ```bash
   open ReceiptRestoration.xcworkspace
   ```
   *Note: Always open `.xcworkspace`, not `.xcodeproj`.*

4. Verify that `receipt_restoration.onnx` is bundled in the app target's **Copy Bundle Resources** build phase.

5. Select an iOS Simulator or connected device and run the project (`Cmd + R`).

## Architecture Notes

1. **Preprocessing Pipeline**: Input images are downscaled to maintain aspect ratio and transformed into NCHW float tensors normalized to `[0, 1]`.
2. **Inference**: The ONNX model processes the image to restore legibility of faded thermal receipts before OCR submission.
3. **Parsing Strategy**: OCR text tokens are grouped into line items dynamically using relative vertical coordinates (adaptive row threshold) rather than fixed pixel offsets.
