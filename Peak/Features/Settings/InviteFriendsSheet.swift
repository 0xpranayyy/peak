import SwiftUI

/// Your referral code, a share link, and a cosmetic points balance.
///
/// Points have no redeemable value — see the Terms. This screen shows what
/// they are (a running count) and nothing more; it deliberately doesn't
/// promise anything about what they're "for".
struct InviteFriendsSheet: View {
    @EnvironmentObject private var referrals: ReferralStore
    @Environment(\.peakBrand) private var brand
    @Environment(\.dismiss) private var dismiss

    private var shareURL: URL? {
        guard let code = referrals.code else { return nil }
        return URL(string: "https://peakapp.site/invite/\(code)")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    codeCard
                    pointsCard
                    if !referrals.history.isEmpty {
                        historyList
                    }
                }
                .padding(20)
            }
            .background(PeakMaterialBackground())
            .navigationTitle("Invite friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                await referrals.fetchCode()
                await referrals.refreshPoints()
            }
        }
        .peakSheetChrome()
    }

    private var codeCard: some View {
        VStack(spacing: 14) {
            Text("Share Peak with a friend")
                .font(.headline)

            if let code = referrals.code {
                Text(code)
                    .font(.system(.title2, design: .monospaced).weight(.bold))
                    .tracking(2)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(brand.mid.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 48)
            }

            if let shareURL {
                ShareLink(item: shareURL) {
                    Label("Share invite link", systemImage: "square.and.arrow.up")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(brand.mid, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(18)
        .background(PeakCanvas.elevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var pointsCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Points")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(referrals.balance)")
                    .font(.system(.title, design: .rounded).weight(.bold).monospacedDigit())
            }
            Spacer()
        }
        .padding(18)
        .background(PeakCanvas.elevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var historyList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent activity")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(referrals.history) { entry in
                    HStack {
                        Text(entry.reason == "referral_bonus" ? "Friend joined" : "Welcome bonus")
                            .font(.subheadline)
                        Spacer()
                        Text("+\(entry.delta)")
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(PeakTradeStyle.buy)
                    }
                    .padding(.vertical, 10)
                    if entry.id != referrals.history.last?.id {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 14)
            .background(PeakCanvas.elevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}
