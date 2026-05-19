//
//  AppState.swift
//  VisionMLReceiptOCR
//
//  Created by Surya on 17/05/26.
//

import SwiftUI
import Combine

class AppState: ObservableObject {
    @Published var spendingRecords: [SpendingRecord] = []
    private let storageKey = "spending_records"


    var totalExpense: Double {
        spendingRecords.reduce(0) { $0 + $1.total }
    }

    var formattedTotalExpense: String {
        formatCurrency(totalExpense)
    }
    
    init() {
        load()
    }

    func addRecord(date: String?, storeName: String?, totalString: String?) {
        let name = storeName ?? "Toko Tidak Diketahui"
        let dateStr = date ?? currentDateString()
        let amount = parseAmount(from: totalString)
        let formatted = totalString ?? formatCurrency(amount)
        let record = SpendingRecord(
            id: UUID(),          // tambah ini
            date: dateStr,
            storeName: name,
            total: amount,
            formattedTotal: formatted,
            items: []            // tambah ini, nanti diisi saat panggil dari ProcessingView
        )
        spendingRecords.insert(record, at: 0)
    }

    private func parseAmount(from string: String?) -> Double {
        guard let s = string else { return 0 }
        // Strip non-numeric except dot/comma, then parse
        let cleaned = s
            .replacingOccurrences(of: "Rp", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Double(cleaned) ?? 0
    }

    private func currentDateString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private func formatCurrency(_ value: Double) -> String {
        let n = NumberFormatter()
        n.numberStyle = .decimal
        n.groupingSeparator = "."
        n.decimalSeparator = ","
        let formatted = n.string(from: NSNumber(value: value)) ?? "0"
        return "Rp \(formatted)"
    }
    
    func addRecord(date: String?, storeName: String?, totalString: String?, items: [ReceiptItem] = []) {
        let persistedItems = items.map {
            PersistedReceiptItem(id: UUID(), name: $0.name, qty: $0.qty, price: $0.price)
        }
        let record = SpendingRecord(
            id: UUID(),
            date: date ?? currentDateString(),
            storeName: storeName ?? "Toko Tidak Diketahui",
            total: parseAmount(from: totalString),
            formattedTotal: totalString ?? formatCurrency(parseAmount(from: totalString)),
            items: persistedItems
        )
        spendingRecords.insert(record, at: 0)
        save()
    }

    func save() {
        if let encoded = try? JSONEncoder().encode(spendingRecords) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([SpendingRecord].self, from: data)
        else { return }
        spendingRecords = decoded
    }
}
