import SwiftUI

struct DailyDigestSettingsView: View {
    @EnvironmentObject private var digest: DailyDigestStore
    @EnvironmentObject private var categoryPrefs: CategoryPreferencesStore

    var body: some View {
        Form {
            Section {
                Toggle("Morning digest", isOn: $digest.isEnabled)
                if digest.isEnabled {
                    Stepper(value: $digest.hour, in: 6...12) {
                        Text("Around \(digest.hour):00")
                    }
                }
            } footer: {
                Text("Sends a daily local notification. Opening the app shows top movers.")
            }

            Section("Preview") {
                if digest.isLoading {
                    ProgressView()
                } else if digest.movers.isEmpty {
                    Text("No movers loaded yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(digest.movers.prefix(4)) { event in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2)
                            HStack {
                                if let p = event.displayProbability {
                                    Text(PeakFormat.cents(p))
                                        .font(.caption.monospacedDigit())
                                }
                                Spacer()
                                Text(PeakFormat.compactCurrency(event.volume24hr) + " 24h")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Button("Refresh movers") {
                    Task { await digest.refreshMovers(interests: categoryPrefs.interestedCategories) }
                }
            }
        }
        .navigationTitle("Morning digest")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await digest.refreshMovers(interests: categoryPrefs.interestedCategories)
            _ = await PriceAlertMonitor.shared.requestPermission()
        }
    }
}
