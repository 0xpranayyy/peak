import SwiftUI

struct CompareMarketsView: View {
    @State private var leftQuery = ""
    @State private var rightQuery = ""
    @State private var leftResults: [PeakEvent] = []
    @State private var rightResults: [PeakEvent] = []
    @State private var left: PeakEvent?
    @State private var right: PeakEvent?
    @State private var isSearchingLeft = false
    @State private var isSearchingRight = false

    var body: some View {
        List {
            Section {
                picker(
                    query: $leftQuery,
                    results: leftResults,
                    selected: $left,
                    isSearching: $isSearchingLeft,
                    side: .left
                )
            } header: {
                Text("Market A")
            }

            Section {
                picker(
                    query: $rightQuery,
                    results: rightResults,
                    selected: $right,
                    isSearching: $isSearchingRight,
                    side: .right
                )
            } header: {
                Text("Market B")
            }

            if let left, let right {
                Section {
                    compareRow("Yes", left: left.displayProbability, right: right.displayProbability) { PeakFormat.cents($0) }
                    compareRow("24h volume", left: left.volume24hr, right: right.volume24hr) { PeakFormat.compactCurrency($0) }
                    compareRow("Liquidity", left: left.liquidity, right: right.liquidity) { PeakFormat.compactCurrency($0) }
                    compareRow("Ends", leftLabel: PeakFormat.shortDate(left.endDate), rightLabel: PeakFormat.shortDate(right.endDate))
                } header: {
                    Text("Head to head")
                }
            } else {
                Section {
                    VStack(spacing: 14) {
                        PeakEmptyVisual(kind: .chart, size: 72)
                        Text("Pick two markets")
                            .font(.headline)
                        Text("Search above to compare odds, volume, and timing side by side.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.insetGrouped)
        .listRowSeparatorTint(PeakCanvas.hairline)
        .navigationTitle("Compare")
        .navigationBarTitleDisplayMode(.inline)
        .background(PeakMaterialBackground())
        .scrollContentBackground(.hidden)
        .peakChrome()
    }

    private enum Side { case left, right }

    @ViewBuilder
    private func picker(
        query: Binding<String>,
        results: [PeakEvent],
        selected: Binding<PeakEvent?>,
        isSearching: Binding<Bool>,
        side: Side
    ) -> some View {
        if let event = selected.wrappedValue {
            VStack(alignment: .leading, spacing: 8) {
                Text(event.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(3)
                HStack {
                    if let p = event.displayProbability {
                        Text(PeakFormat.cents(p))
                            .font(.body.monospacedDigit().weight(.bold))
                            .peakNumeric(value: p)
                    }
                    Spacer()
                    Button("Change") {
                        PeakHaptics.selection()
                        selected.wrappedValue = nil
                    }
                    .font(.caption.weight(.semibold))
                    .frame(minHeight: 44)
                }
            }
            .padding(.vertical, 2)
        } else {
            TextField("Search markets", text: query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: query.wrappedValue) { _, newValue in
                    Task { await search(newValue, side: side) }
                }

            if isSearching.wrappedValue {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(0..<3, id: \.self) { _ in
                        PeakSkeletonRow()
                    }
                }
                .padding(.vertical, 4)
            } else if results.isEmpty, query.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 {
                Text("No markets match that search.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }

            ForEach(results.prefix(6)) { event in
                Button {
                    PeakHaptics.selection()
                    selected.wrappedValue = event
                    query.wrappedValue = ""
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if let p = event.displayProbability {
                            Text(PeakFormat.cents(p))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
            }
        }
    }

    private func compareRow(_ title: String, left: Double?, right: Double?, format: (Double) -> String) -> some View {
        let l = left ?? 0
        let r = right ?? 0
        return HStack {
            Text(format(l))
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(l >= r ? Color.accentColor : Color.primary)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(format(r))
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .foregroundStyle(r >= l ? Color.accentColor : Color.primary)
        }
        .padding(.vertical, 2)
    }

    private func compareRow(_ title: String, leftLabel: String, rightLabel: String) -> some View {
        HStack {
            Text(leftLabel)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(rightLabel)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }

    private func search(_ raw: String, side: Side) async {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else {
            await MainActor.run {
                if side == .left {
                    leftResults = []
                    isSearchingLeft = false
                } else {
                    rightResults = []
                    isSearchingRight = false
                }
            }
            return
        }
        await MainActor.run {
            if side == .left { isSearchingLeft = true } else { isSearchingRight = true }
        }
        let result = try? await GammaAPI.search(q, limitPerType: 8)
        await MainActor.run {
            if side == .left {
                leftResults = result?.events ?? []
                isSearchingLeft = false
            } else {
                rightResults = result?.events ?? []
                isSearchingRight = false
            }
        }
    }
}
