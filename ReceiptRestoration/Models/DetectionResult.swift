//
//  DetectionResult.swift
//  VisionMLReceiptOCR
//
//  Created by Surya on 07/05/26.
//

import Foundation

struct OCRResponse: Codable {
    let raw: [OCRText]
    let parsed: ParsedReceipt
}

struct OCRText: Codable {
    let text: String
    let score: Double
    let bbox: [[Double]]  // tambah ini
}

struct ParsedReceipt: Codable {
    let items: [String]
    let total: String?
    let date: String?
}

struct ReceiptItem: Identifiable {
    let id = UUID()
    let name: String
    let qty: String?
    let price: String?
}

struct ParsedReceiptData {
    let storeName: String?
    let date: String?
    let items: [ReceiptItem]
    let total: String?
}

// MARK: - Home / Expense Models

struct SpendingRecord: Identifiable, Codable, Hashable {
    let id: UUID
    let date: String
    let storeName: String
    let total: Double
    let formattedTotal: String
    let items: [PersistedReceiptItem]  // tambah ini
}

// Tambah model item yang Codable
struct PersistedReceiptItem: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let qty: String?
    let price: String?
}
