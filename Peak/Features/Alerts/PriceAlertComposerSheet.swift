import SwiftUI
import UIKit

struct PriceAlertComposerSheet: View {
    let event: PeakEvent
    let market: Market

    @EnvironmentObject private var alerts: PriceAlertStore
    @Environment(\.dismiss) private var dismiss

    @State private var isYes = true
    @State private var direction: PriceAlert.Direction = .atOrAbove
    @State private var centsText = ""
    @State private var status: String?
    @State private var didRequestNotifications = false
    @FocusState private var centsFocused: Bool

    private var currentPrice: Double {
        isYes ? market.yesPrice : market.noPrice
    }

    private var targetPrice: Double? {
        guard let cents = Double(centsText), cents > 0, cents < 100 else { return nil }
        return cents / 100
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Outcome", selection: $isYes) {
                        Text(market.yesLabel).tag(true)
                        Text(market.noLabel).tag(false)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: isYes) { _, _ in
                        seedDefaultTarget()
                    }

                    LabeledContent("Now") {
                        Text(PeakFormat.cents(currentPrice))
                            .font(.body.monospacedDigit().weight(.semibold))
                            .peakNumeric(value: currentPrice)
                    }
                } header: {
                    Text("Market")
                } footer: {
                    Text(event.title)
                }

                Section {
                    Picker("Direction", selection: $direction) {
                        ForEach(PriceAlert.Direction.allCases, id: \.self) { item in
                            Text(item.title).tag(item)
                        }
                    }

                    HStack {
                        TextField("50", text: $centsText)
                            .keyboardType(.decimalPad)
                            .font(.title3.monospacedDigit().weight(.semibold))
                            .focused($centsFocused)
                        Text("¢")
                            .foregroundStyle(.secondary)
                    }

                    if let targetPrice {
                        Text("Notify when \(isYes ? market.yesLabel : market.noLabel) \(direction == .atOrAbove ? "≥" : "≤") \(PeakFormat.cents(targetPrice))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Alert when")
                }

                if let status {
                    Section {
                        Text(status)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button {
                        centsFocused = false
                        Task { await save() }
                    } label: {
                        PeakPrimaryCTA(
                            title: "Create alert",
                            systemImage: "bell.badge",
                            isEnabled: targetPrice != nil
                        )
                    }
                    .peakPressable()
                    .disabled(targetPrice == nil)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .background(PeakMaterialBackground())
            .scrollContentBackground(.hidden)
            .navigationTitle("Price alert")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { centsFocused = false }
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                seedDefaultTarget()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    centsFocused = true
                }
            }
        }
        .presentationDetents([.medium, .large])
        .peakSheetChrome()
    }

    private func seedDefaultTarget() {
        let bump = direction == .atOrAbove ? 0.05 : -0.05
        let seeded = min(0.95, max(0.05, currentPrice + bump))
        centsText = String(Int((seeded * 100).rounded()))
    }

    private func save() async {
        guard let targetPrice else { return }
        if !didRequestNotifications {
            didRequestNotifications = true
            let granted = await PriceAlertMonitor.shared.requestPermission()
            if !granted {
                status = "Alert saved. Enable notifications in iOS Settings to get pings."
            }
        }
        if alerts.add(
            event: event,
            market: market,
            isYes: isYes,
            targetPrice: targetPrice,
            direction: direction
        ) != nil {
            PeakHaptics.success()
            dismiss()
        } else {
            status = "Couldn’t create alert for this market."
            PeakHaptics.error()
        }
    }
}

struct PriceAlertsSettingsView: View {
    @EnvironmentObject private var alerts: PriceAlertStore
    @StateObject private var monitor = PriceAlertMonitor.shared

    var body: some View {
        List {
            Section {
                LabeledContent("Notifications") {
                    Text(monitor.notificationsAllowed ? "On" : "Off")
                        .foregroundStyle(monitor.notificationsAllowed ? Color.secondary : Color.orange)
                }
                if !monitor.notificationsAllowed {
                    Button("Enable notifications") {
                        Task {
                            _ = await monitor.requestPermission()
                            await monitor.refreshAuthorizationStatus()
                        }
                    }
                    .frame(minHeight: 44)
                }
                Button("Check prices now") {
                    Task { await monitor.checkOnce() }
                }
                .frame(minHeight: 44)
            } footer: {
                Text("Peak checks your alert prices while the app is open, and about every 45 seconds in the background of an active session.")
            }

            Section {
                let active = alerts.alerts.filter { $0.isActive && $0.triggeredAt == nil }
                if active.isEmpty {
                    VStack(spacing: 14) {
                        PeakEmptyVisual(kind: .chart, size: 64)
                        Text("No active alerts")
                            .font(.headline)
                        Text("Open any market and set a price alert from the toolbar.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Browse markets") {
                            PeakRootTab.select(.markets)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.accentColor)
                        .controlSize(.large)
                        .frame(minHeight: 44)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(active) { alert in
                        alertRow(alert)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            alerts.remove(id: active[index].id)
                        }
                    }
                }
            } header: {
                Text("Active")
            }

            let triggered = alerts.alerts.filter { $0.triggeredAt != nil }
            if !triggered.isEmpty {
                Section {
                    ForEach(triggered) { alert in
                        alertRow(alert)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            alerts.remove(id: triggered[index].id)
                        }
                    }
                    Button("Clear triggered", role: .destructive) {
                        alerts.clearTriggered()
                    }
                } header: {
                    Text("Triggered")
                }
            }
        }
        .listStyle(.insetGrouped)
        .listRowSeparatorTint(PeakCanvas.hairline)
        .background(PeakMaterialBackground())
        .scrollContentBackground(.hidden)
        .navigationTitle("Price alerts")
        .navigationBarTitleDisplayMode(.inline)
        .peakChrome()
        .task {
            await monitor.refreshAuthorizationStatus()
        }
    }

    private func alertRow(_ alert: PriceAlert) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(alert.eventTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            Text("\(alert.outcomeLabel) \(alert.direction == .atOrAbove ? "≥" : "≤") \(alert.targetCentsLabel)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            if let triggered = alert.triggeredAt {
                Text("Hit \(triggered.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(PeakTradeStyle.buy)
            }
        }
        .padding(.vertical, 2)
    }
}
