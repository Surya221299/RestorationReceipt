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
    private static let dateAltRegex = /\d{1,2}\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{2,4}/
    private static let numberedRegex = /^\d+[.\)]\s*(.+)/

    private static let skipKeywords: [String] = [
        "subtotal", "sub total", "total", "ppn", "pajak", "tax",
        "tunai", "cash", "kembali", "bayar", "diskon", "discount",
        "payment", "debit", "kredit", "credit", "change",
        "terima kasih", "thank you", "please come", "powered",
        "kasir", "pelanggan", "no.meja", "kode struk", "tanggal",
        "pass", "wifi", "checkno", "closed", "pos1", "www.",
        "http", "ruko", "jl.", "jalan", "(021)", "1 pos"
    ]

    // MARK: - Entry Point

    // MARK: - Row Threshold
        private static func rowThreshold(for imageHeight: Double) -> Double {
            let ratio = 0.015
            let computed = imageHeight * ratio
            return min(max(computed, 15), 80)
        }
    static func parse(raw: [OCRText], imageHeight: Double) -> ParsedReceiptData {
        return ParsedReceiptData(
            storeName: extractStoreName(from: raw.map { $0.text }),
            date: extractDate(from: raw.map { $0.text }),
            items: extractItemsByBBox(from: raw, imageHeight: imageHeight),
            total: extractTotal(from: raw, imageHeight: imageHeight)
        )
    }

   // private static func extractItemsByBBox(from raw: [OCRText]) -> [ReceiptItem] {
    private static func extractItemsByBBox(from raw: [OCRText], imageHeight: Double) -> [ReceiptItem] {
        let threshold = rowThreshold(for: imageHeight)

        // 1. Cari stop index sebelum Subtotal/Total
        let stopY: Double = raw
            .first(where: {
                let t = $0.text.trimmingCharacters(in: .whitespaces).lowercased()
                return t.hasPrefix("subtotal") || t == "total:"
            })
            .map { $0.bbox[0][1] } ?? Double.greatestFiniteMagnitude

        // 2. Filter hanya zona item
        let itemZone = raw.filter { $0.bbox[0][1] < stopY }

        // 3. Sort by Y
        let sortedByY = itemZone.sorted { $0.bbox[0][1] < $1.bbox[0][1] }

        // 4. Grouping ke rows — threshold lebih besar untuk real device
        var rows: [[OCRText]] = []
        var currentRow: [OCRText] = []
        var lastY: Double = -1

        for token in sortedByY {
            let y = token.bbox[0][1]
            // Threshold 60px untuk real device (resolusi 4032px)
            if lastY < 0 || abs(y - lastY) < 60 {
                currentRow.append(token)
            } else {
                if !currentRow.isEmpty { rows.append(currentRow) }
                currentRow = [token]
            }
            lastY = y
        }
        if !currentRow.isEmpty { rows.append(currentRow) }

        // 5. Tiap row: kiri = nama, kanan = harga
        // Tapi satu item bisa tersebar di 2 rows (nama Y != harga Y)
        // Jadi perlu pair: row yang hanya berisi harga → gabungkan dengan row nama terdekat
        var result: [ReceiptItem] = []

        var i = 0
        while i < rows.count {
            let row = rows[i]
            let sortedRow = row.sorted { $0.bbox[0][0] < $1.bbox[0][0] }

            let leftToken  = sortedRow.first!
            let rightToken = sortedRow.last!

            let leftText  = leftToken.text.trimmingCharacters(in: .whitespaces)
            let rightText = rightToken.text.trimmingCharacters(in: .whitespaces)

            // Case A: Row berisi nama DAN harga (simulator-style / baris rapi)
            if leftText.firstMatch(of: priceRegex) == nil
                && rightText.firstMatch(of: priceRegex) != nil
                && !isSkippable(leftText)
                && leftText != rightText {
                result.append(ReceiptItem(
                    name: leftText,
                    qty: nil,
                    price: formatPrice(rightText)
                ))
                i += 1

            // Case B: Row hanya berisi harga (real device — harga Y lebih kecil dari nama)
            } else if leftText.firstMatch(of: priceRegex) != nil && row.count == 1 {
                // Lihat row berikutnya — seharusnya nama item
                if i + 1 < rows.count {
                    let nextRow = rows[i + 1].sorted { $0.bbox[0][0] < $1.bbox[0][0] }
                    let nameText = nextRow.first?.text.trimmingCharacters(in: .whitespaces) ?? ""
                    if !isSkippable(nameText) && nameText.firstMatch(of: priceRegex) == nil {
                        result.append(ReceiptItem(
                            name: nameText,
                            qty: nil,
                            price: formatPrice(leftText)
                        ))
                        i += 2  // skip row nama juga
                        continue
                    }
                }
                i += 1

            // Case C: Row hanya nama (harga sudah dikonsumsi di atas, atau memang tidak ada)
            } else {
                i += 1
            }
        }

        return result
    }
    // MARK: - Store Name

    private static func extractStoreName(from texts: [String]) -> String? {
        for text in texts {
            let t = text.trimmingCharacters(in: .whitespaces)
            guard t.count >= 3 else { continue }
            guard !t.allSatisfy({ $0.isNumber || $0 == "-" || $0 == " " }) else { continue }
            guard !isSkippable(t) else { continue }
            return t
        }
        return texts.first
    }

    // MARK: - Date

    private static func extractDate(from texts: [String]) -> String? {
        for text in texts {
            if let m = text.firstMatch(of: dateRegex) { return String(m.output) }
            if let m = text.firstMatch(of: dateAltRegex) { return String(m.output) }
        }
        return nil
    }

    // MARK: - Items

    private static func extractItems(from texts: [String]) -> [ReceiptItem] {
        if texts.contains(where: { $0.firstMatch(of: numberedRegex) != nil }) {
            return parseNumberedFormat(texts)
        }
        if detectsQtyFirstFormat(texts) {
            return parseQtyFirstFormat(texts)
        }
        return parseNameFirstFormat(texts)
    }

    private static func detectsQtyFirstFormat(_ texts: [String]) -> Bool {
        let stop = stopIndex(in: texts)
        for i in 0..<stop {
            let t = texts[i].trimmingCharacters(in: .whitespaces)
            guard t.firstMatch(of: qtyStandaloneRegex) != nil else { continue }
            if i + 1 < stop {
                let next = texts[i + 1].trimmingCharacters(in: .whitespaces)
                if next.firstMatch(of: priceRegex) == nil && !isSkippable(next) && next.count > 2 {
                    return true
                }
            }
        }
        return false
    }

    private static func parseNumberedFormat(_ texts: [String]) -> [ReceiptItem] {
        var items: [ReceiptItem] = []
        var i = 0
        while i < texts.count {
            let text = texts[i]
            if let match = text.firstMatch(of: numberedRegex) {
                let name = String(match.output.1).trimmingCharacters(in: .whitespaces)
                var qty: String? = nil
                var price: String? = nil
                if i + 1 < texts.count {
                    let next = texts[i + 1]
                    let isQty = next.contains("x") || next.lowercased().contains("lusin") || next.lowercased().contains("pcs")
                    if isQty {
                        qty = next
                        if i + 2 < texts.count, texts[i + 2].firstMatch(of: priceRegex) != nil {
                            price = formatPrice(texts[i + 2])
                            i += 2
                        } else { i += 1 }
                    } else if next.firstMatch(of: priceRegex) != nil {
                        price = formatPrice(next)
                        i += 1
                    }
                }
                items.append(ReceiptItem(name: name, qty: qty, price: price))
            }
            i += 1
        }
        return items
    }

    private static func parseNameFirstFormat(_ texts: [String]) -> [ReceiptItem] {
        var items: [ReceiptItem] = []
        let stop = stopIndex(in: texts)
        let start = startIndexForNameFirst(texts, stop: stop)
        var i = start
        while i < stop {
            let text = texts[i].trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty,
                  !isSkippable(text),
                  text.firstMatch(of: priceRegex) == nil,
                  text.firstMatch(of: qtyAfterRegex) == nil,
                  text.firstMatch(of: qtyStandaloneRegex) == nil
            else { i += 1; continue }

            var qty: String? = nil
            var price: String? = nil
            var advance = 0
            if i + 1 < stop {
                let next = texts[i + 1].trimmingCharacters(in: .whitespaces)
                if next.firstMatch(of: qtyAfterRegex) != nil {
                    qty = next; advance = 1
                    if i + 2 < stop, texts[i + 2].firstMatch(of: priceRegex) != nil {
                        price = formatPrice(texts[i + 2]); advance = 2
                    }
                } else if next.firstMatch(of: priceRegex) != nil {
                    price = formatPrice(next); advance = 1
                }
            }
            items.append(ReceiptItem(name: text, qty: qty, price: price))
            i += advance + 1
        }
        return items
    }

    private static func parseQtyFirstFormat(_ texts: [String]) -> [ReceiptItem] {
        var items: [ReceiptItem] = []
        let stop = stopIndex(in: texts)

        let start: Int = {
            for idx in 0..<stop {
                let t = texts[idx].trimmingCharacters(in: .whitespaces)
                guard t.firstMatch(of: qtyStandaloneRegex) != nil else { continue }
                if idx + 1 < stop {
                    let next = texts[idx + 1].trimmingCharacters(in: .whitespaces)
                    if next.firstMatch(of: priceRegex) == nil && !isSkippable(next) && next.count > 2 {
                        return idx
                    }
                }
            }
            return 0
        }()

        var i = start
        while i < stop {
            let text = texts[i].trimmingCharacters(in: .whitespaces)
            if text.firstMatch(of: qtyStandaloneRegex) != nil, i + 1 < stop {
                let qtyStr = text
                let nameLine = texts[i + 1].trimmingCharacters(in: .whitespaces)
                guard nameLine.firstMatch(of: priceRegex) == nil,
                      !isSkippable(nameLine),
                      nameLine.count > 2
                else { i += 1; continue }

                var price: String? = nil
                var advance = 1
                if i + 2 < stop {
                    let afterName = texts[i + 2].trimmingCharacters(in: .whitespaces)
                    if afterName.firstMatch(of: priceRegex) != nil && !isSkippable(afterName) {
                        price = formatPrice(afterName)
                        advance = 2
                    }
                }
                items.append(ReceiptItem(name: nameLine, qty: qtyStr, price: price))
                i += advance + 1
            } else {
                i += 1
            }
        }
        return items
    }

    // MARK: - Total

        //private static func extractTotal(from raw: [OCRText]) -> String? {
    private static func extractTotal(from raw: [OCRText], imageHeight: Double) -> String? {
        let threshold = rowThreshold(for: imageHeight)

        // Cari token "Total:"
        guard let totalToken = raw.first(where: {
            $0.text.trimmingCharacters(in: .whitespaces)
                .lowercased()
                .replacingOccurrences(of: ":", with: "")
                .trimmingCharacters(in: .whitespaces) == "total"
        }) else { return nil }

        let totalY = totalToken.bbox[0][1]

        // Cari token harga di baris yang sama (Y berdekatan, X lebih besar)
        let candidate = raw
            .filter {
                abs($0.bbox[0][1] - totalY) < 60          // same row
                && $0.bbox[0][0] > totalToken.bbox[0][0]   // di sebelah kanan
                && $0.text.firstMatch(of: priceRegex) != nil
            }
            .sorted { $0.bbox[0][0] < $1.bbox[0][0] }
            .first

        if let c = candidate {
            return formatPrice(c.text)
        }

        // Fallback: cari di baris tepat di bawah Total
        return raw
            .filter {
                $0.bbox[0][1] > totalY
                && $0.bbox[0][1] < totalY + 120
                && $0.text.firstMatch(of: priceRegex) != nil
            }
            .sorted { $0.bbox[0][1] < $1.bbox[0][1] }
            .first
            .map { formatPrice($0.text) }
    }

    // MARK: - Helpers

    private static func stopIndex(in texts: [String]) -> Int {
        texts.firstIndex(where: {
            let t = $0.trimmingCharacters(in: .whitespaces)
                .lowercased()
                .replacingOccurrences(of: ":", with: "")
                .trimmingCharacters(in: .whitespaces)
            return t == "subtotal" || t == "sub total" || t == "total"
        }) ?? texts.count
    }

    private static func startIndexForNameFirst(_ texts: [String], stop: Int) -> Int {
        for idx in 0..<stop {
            guard idx + 1 < stop else { break }
            let next = texts[idx + 1].trimmingCharacters(in: .whitespaces)
            let nextIsQty   = next.firstMatch(of: qtyAfterRegex) != nil
            let nextIsPrice = next.firstMatch(of: priceRegex) != nil && !next.contains("-")
            if nextIsQty || nextIsPrice { return idx }
        }
        return 0
    }

    private static func isSkippable(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.hasPrefix("-") || lower.hasPrefix("(") || lower.hasPrefix("[") { return true }
        for kw in skipKeywords {
            if lower.hasPrefix(kw) { return true }
        }
        return false
    }

    private static func formatPrice(_ text: String) -> String {
        var cleaned = text
            .replacingOccurrences(of: "Rp", with: "")
            .replacingOccurrences(of: " ", with: "")

        // jika ada format 43,500 -> ubah jadi 43.500
        if cleaned.contains(",") && !cleaned.contains(".") {
            cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
        }

        return "Rp \(cleaned)"
    }
}
