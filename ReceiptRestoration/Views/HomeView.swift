import SwiftUI

struct HomeView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
                VStack(spacing: 0) {
                    // MARK: Total Expense Card
                    TotalExpenseCard(total: appState.formattedTotalExpense)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 16)

                    // MARK: Section Header
                    if !appState.spendingRecords.isEmpty {
                        Text("Riwayat Belanja")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 6)
                    }

                    // MARK: List or Empty
                    if appState.spendingRecords.isEmpty {
                        EmptyStateView()
                            .padding(.top, 40)
                        Spacer()
                    } else {
                        List {
                            ForEach(appState.spendingRecords) { record in
                                ZStack {
                                    NavigationLink(destination: ReceiptDetailView(record: record)) {
                                        EmptyView()
                                    }
                                    .opacity(0)  // sembunyikan NavigationLink + chevron bawaannya

                                    SpendingRowView(record: record)
                                }
                                .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                            .onDelete { indexSet in
                                appState.spendingRecords.remove(atOffsets: indexSet)
                                appState.save()
                            }
                            Color.clear
                                .frame(height: 90)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
        }
        .background(Color(hex: "F9F2F0").ignoresSafeArea())
    }
}

// MARK: - Total Expense Card

struct TotalExpenseCard: View {
    let total: String

    var body: some View {
        VStack(spacing: 6) {
            Text("Total Pengeluaran")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.80))

            Text(total)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 24)
        .background(
            LinearGradient(
                colors: [Color(hex: "FF936C"), Color(hex: "FF936C").opacity(0.80)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: Color(hex: "FF936C").opacity(0.30), radius: 12, x: 0, y: 6)
    }
}

// MARK: - Spending Row

struct SpendingRowView: View {
    let record: SpendingRecord

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: "FF936C").opacity(0.20))
                    .frame(width: 44, height: 44)
                Image(systemName: "bag.fill")
                    .font(.system(size: 18))
                    .foregroundColor(Color(hex: "FF936C"))

                
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(record.storeName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(UIColor { trait in
                            trait.userInterfaceStyle == .dark ? .white : UIColor(Color(hex: "2D1A14"))
                        }))
                    .lineLimit(1)
                Text(record.date)
                    .font(.system(size: 12))
                    .foregroundColor(Color(UIColor { trait in
                        trait.userInterfaceStyle == .dark ? UIColor.white.withAlphaComponent(0.5) : UIColor(Color(hex: "2D1A14")).withAlphaComponent(0.45)
                    }))
            }

            Spacer()

            Text(record.formattedTotal)
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundColor(Color(hex: "FF8466"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        //.background(Color(.tertiarySystemBackground))
        .background(Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.18, green: 0.12, blue: 0.10, alpha: 0.5)  // warm dark
                : UIColor(Color(hex: "FFEDE9"))
        }))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color(hex: "FF936C").opacity(0.15), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "receipt")
                .font(.system(size: 56))
                .foregroundColor(.secondary.opacity(0.4))
            Text("Belum ada struk terscan")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
            Text("Tekan tombol kamera di bawah\nuntuk scan struk belanja")
                .font(.system(size: 13))
                .foregroundColor(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

// MARK: - Receipt Detail View

struct ReceiptDetailView: View {
    let record: SpendingRecord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                Text(record.storeName)
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity, alignment: .center)

                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .foregroundStyle(.secondary)
                    Text(record.date)
                        .foregroundStyle(.secondary)
                }

                Divider()

                Text("Item Belanja")
                    .font(.headline)

                if record.items.isEmpty {
                    Text("Tidak ada item tercatat")
                        .foregroundStyle(.secondary)
                        .italic()
                } else {
                    ForEach(record.items) { item in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .fontWeight(.medium)
                                if let qty = item.qty {
                                    Text(qty)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(item.price ?? "-")
                                .fontWeight(.semibold)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Divider()

                HStack {
                    Text("Total")
                        .font(.headline)
                    Spacer()
                    Text(record.formattedTotal)
                        .font(.headline)
                        .foregroundStyle(Color(red: 0.10, green: 0.60, blue: 0.90))
                }
                .padding(.vertical, 4)
            }
            .padding(16)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
        .navigationTitle("Detail Struk")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @State private var showScanView = false
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)

            Color.clear
                .tabItem {
                    Label("Scan", systemImage: "camera.fill")
                }
                .tag(1)
        }
        .tint(Color(hex: "FF8466"))
        .onChange(of: selectedTab) { tab in
            if tab == 1 {
                showScanView = true
                selectedTab = 0  // balik ke home agar tab camera tidak "aktif"
            }
        }
        .fullScreenCover(isPresented: $showScanView) {
            ScanReceiptView()
                .environmentObject(appState)
        }
        .onReceive(NotificationCenter.default.publisher(for: .dismissToHome)) { _ in
            showScanView = false
        }
    }
}
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
#Preview {
    HomeView()
        .environmentObject(AppState())
}
