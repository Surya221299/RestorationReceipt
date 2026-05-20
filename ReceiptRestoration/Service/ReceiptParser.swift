//
//  ReceiptParser.swift
//  VisionMLReceiptOCR
//
//  Created by Surya on 17/05/26.
//

import Foundation

// MARK: - Receipt Parser

struct ReceiptParser {

    // MARK: Shared Regex

    private static let priceRegex = /(?:Rp\s?)?(\d{1,3}(?:[.,]\d{3})+)/
    private static let qtyAfterRegex = /^x\d+$|^\d+x$/
    private static let qtyStandaloneRegex = /^\d{1,3}$/
    private static let dateRegex = /\d{4}-\d{2}-\d{2}/
    private static let dateAltRegex = /\d{1,2}\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec|jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-zA-Z]*\s+\d{2,4}/
    private static let numberedRegex = /^\d+[.\)]\s*(.+)/

    private static let skipKeywords: [String] = [
        "subtotal", "sub total", "total", "ppn", "pajak", "tax",
        "tunai", "cash", "kembali", "bayar", "diskon", "discount",
        "payment", "debit", "kredit", "credit", "change",
        "terima kasih", "thank you", "please come", "powered",
        "kasir", "pelanggan", "no.meja", "kode struk", "tanggal",
        "pass", "wifi", "checkno", "closed", "pos1", "www.",
        "http", "ruko", "jl.", "jalan", "(021)", "1 pos", "1pos"
    ]

    // MARK: - Entry Point

    static func parse(raw: [OCRText], imageHeight: Double) -> ParsedReceiptData {
        return ParsedReceiptData(
            storeName: extractStoreName(from: raw),
            date: extractDate(from: raw.map { $0.text }),
            items: extractItemsByBBox(from: raw),
            total: extractTotal(from: raw)
        )
    }

    // MARK: - Row Threshold (adaptif dari tinggi teks aktual)
    //
    // Alih-alih menghitung dari imageHeight (yang tidak stabil lintas resolusi),
    // kita ukur median tinggi baris teks dari bbox itu sendiri, lalu pakai
    // sebagai acuan threshold grouping.
    // Ini bekerja konsisten di 288px maupun 4032px karena bbox selalu proporsional.

    private static func medianLineHeight(from raw: [OCRText]) -> Double {
        let heights = raw.map { token -> Double in
            let topY    = token.bbox[0][1]
            let bottomY = token.bbox[2][1]
            return abs(bottomY - topY)
        }.filter { $0 > 2 }.sorted()

        guard !heights.isEmpty else { return 12.0 }
        return heights[heights.count / 2]
    }

    /// Threshold grouping = 60% dari median tinggi baris.
    /// Logikanya: dua token di baris yang sama punya Y berdekatan (< 1 tinggi baris).
    /// Token di baris berbeda punya Y gap ≥ 1 tinggi baris.
    /// 60% memberi ruang jitter OCR tanpa over-grouping.
    private static func rowThreshold(from raw: [OCRText]) -> Double {
        let lineH = medianLineHeight(from: raw)
        return lineH * 0.6
    }

    // MARK: - Store Name

    private static func extractStoreName(from raw: [OCRText]) -> String? {
        // Ambil token paling atas (Y terkecil), skip yang terlalu pendek / noise
        let sorted = raw.sorted { $0.bbox[0][1] < $1.bbox[0][1] }
        for token in sorted {
            let t = token.text.trimmingCharacters(in: .whitespaces)
            guard t.count >= 3 else { continue }
            guard !t.allSatisfy({ $0.isNumber || $0 == "-" || $0 == " " }) else { continue }
            guard !isSkippable(t) else { continue }
            guard t.firstMatch(of: priceRegex) == nil else { continue }
            return t
        }
        return raw.first?.text
    }

    // MARK: - Date

    private static func extractDate(from texts: [String]) -> String? {
        for text in texts {
            if let m = text.firstMatch(of: dateRegex) { return String(m.output) }
            if let m = text.firstMatch(of: dateAltRegex) { return String(m.output) }
        }
        return nil
    }

    // MARK: - Items (bbox-based)

    private static func extractItemsByBBox(from raw: [OCRText]) -> [ReceiptItem] {
        let threshold = rowThreshold(from: raw)
        print("📏 rowThreshold=\(String(format: "%.1f", threshold))px  medianLineH=\(String(format: "%.1f", medianLineHeight(from: raw)))px")

        // 1. Cari stopY — baris Subtotal/Total pertama
        let stopY: Double = raw
            .filter {
                let t = $0.text.trimmingCharacters(in: .whitespaces).lowercased()
                return t.hasPrefix("subtotal") || t == "total:" || t == "total"
            }
            .map { $0.bbox[0][1] }
            .min() ?? Double.greatestFiniteMagnitude

        // 2. Filter zona item saja
        let itemZone = raw.filter { $0.bbox[0][1] < stopY }

        // 3. Sort by Y lalu X
        let sortedByY = itemZone.sorted {
            let dy = $0.bbox[0][1] - $1.bbox[0][1]
            if abs(dy) < threshold { return $0.bbox[0][0] < $1.bbox[0][0] }
            return dy < 0
        }

        // 4. Grouping ke rows menggunakan threshold adaptif
        var rows: [[OCRText]] = []
        var currentRow: [OCRText] = []
        var lastY: Double = -1

        for token in sortedByY {
            let y = token.bbox[0][1]
            if lastY < 0 || abs(y - lastY) < threshold {
                currentRow.append(token)
            } else {
                if !currentRow.isEmpty { rows.append(currentRow) }
                currentRow = [token]
            }
            lastY = y
        }
        if !currentRow.isEmpty { rows.append(currentRow) }

        print("📦 Rows di item zone: \(rows.count)")
        for (i, row) in rows.enumerated() {
            let texts = row.sorted { $0.bbox[0][0] < $1.bbox[0][0] }.map { $0.text }
            print("  row[\(i)]: \(texts)")
        }

        // 5. Parse tiap row: kiri = nama, kanan = harga
        var result: [ReceiptItem] = []
        var i = 0

        while i < rows.count {
            let row = rows[i]
            let sortedRow = row.sorted { $0.bbox[0][0] < $1.bbox[0][0] }

            let leftText  = sortedRow.first!.text.trimmingCharacters(in: .whitespaces)
            let rightText = sortedRow.last!.text.trimmingCharacters(in: .whitespaces)

            // Case A: Row berisi nama (kiri) + harga (kanan)
            if sortedRow.count >= 2,
               leftText.firstMatch(of: priceRegex) == nil,
               rightText.firstMatch(of: priceRegex) != nil,
               !isSkippable(leftText),
               leftText != rightText {

                result.append(ReceiptItem(
                    name: cleanItemName(leftText),
                    qty: nil,
                    price: formatPrice(rightText)
                ))
                i += 1

            // Case B: Row hanya berisi harga — cari nama di row berikutnya
            } else if sortedRow.count == 1,
                      leftText.firstMatch(of: priceRegex) != nil {

                if i + 1 < rows.count {
                    let nextRow = rows[i + 1].sorted { $0.bbox[0][0] < $1.bbox[0][0] }
                    let nameText = nextRow.first?.text.trimmingCharacters(in: .whitespaces) ?? ""
                    if !isSkippable(nameText), nameText.firstMatch(of: priceRegex) == nil {
                        result.append(ReceiptItem(
                            name: cleanItemName(nameText),
                            qty: nil,
                            price: formatPrice(leftText)
                        ))
                        i += 2
                        continue
                    }
                }
                i += 1

            // Case C: Skip (header, noise, dll)
            } else {
                i += 1
            }
        }

        return result
    }

    // MARK: - Total

    private static func extractTotal(from raw: [OCRText]) -> String? {
        let threshold = rowThreshold(from: raw)

        // Cari token "Total" (bukan "Subtotal")
        guard let totalToken = raw.first(where: {
            let t = $0.text.trimmingCharacters(in: .whitespaces)
                .lowercased()
                .replacingOccurrences(of: ":", with: "")
                .trimmingCharacters(in: .whitespaces)
            return t == "total"
        }) else { return nil }

        let totalY = totalToken.bbox[0][1]
        let totalX = totalToken.bbox[0][0]

        // Cari harga di baris yang sama (Y berdekatan), posisi X lebih kanan
        let sameRow = raw
            .filter {
                abs($0.bbox[0][1] - totalY) < threshold * 2   // sedikit longgar untuk total
                && $0.bbox[0][0] > totalX
                && $0.text.firstMatch(of: priceRegex) != nil
            }
            .sorted { $0.bbox[0][0] < $1.bbox[0][0] }

        if let found = sameRow.first {
            return formatPrice(found.text)
        }

        // Fallback: baris tepat di bawah Total
        let lineH = medianLineHeight(from: raw)
        return raw
            .filter {
                $0.bbox[0][1] > totalY
                && $0.bbox[0][1] < totalY + lineH * 2
                && $0.text.firstMatch(of: priceRegex) != nil
            }
            .sorted { $0.bbox[0][1] < $1.bbox[0][1] }
            .first
            .map { formatPrice($0.text) }
    }

    // MARK: - Helpers

    /// Hapus prefix angka + spasi dari nama item, misal "1 Bread Butter" → "Bread Butter"
    private static func cleanItemName(_ text: String) -> String {
        // Format "1 Nama Item" — qty jadi prefix, buang saja untuk nama bersih
        if let match = text.firstMatch(of: /^(\d+)\s+(.+)/),
           Int(String(match.output.1)) != nil {
            return String(match.output.2).trimmingCharacters(in: .whitespaces)
        }
        return text
    }

    private static func isSkippable(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.hasPrefix("-") || lower.hasPrefix("(") || lower.hasPrefix("[") { return true }
        for kw in skipKeywords {
            if lower.hasPrefix(kw) || lower.contains(kw) { return true }
        }
        return false
    }

    private static func formatPrice(_ text: String) -> String {
        var cleaned = text
            .replacingOccurrences(of: "Rp", with: "")
            .replacingOccurrences(of: " ", with: "")

        if cleaned.contains(",") && !cleaned.contains(".") {
            cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
        }

        return "Rp \(cleaned)"
    }
}
