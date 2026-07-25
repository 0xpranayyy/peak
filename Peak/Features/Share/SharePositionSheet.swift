import SwiftUI
import UIKit

struct PeakPositionShareCard: View {
    let position: PortfolioPosition

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.11, blue: 0.12),
                    Color(red: 0.07, green: 0.20, blue: 0.22),
                    Color(red: 0.04, green: 0.09, blue: 0.10),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Ellipse()
                .fill(
                    Color(red: 0.28, green: 0.78, blue: 0.62)
                        .opacity(position.percentPnl >= 0 ? 0.35 : 0.12)
                )
                .frame(width: 320, height: 240)
                .offset(x: 100, y: -140)
                .blur(radius: 8)

            VStack(alignment: .leading, spacing: 0) {
                PeakShareBrandHeader()
                    .padding(.bottom, 28)

                Text(position.title)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .padding(.bottom, 10)

                Text(position.outcome.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.bottom, 28)

                Text(String(format: "%+.1f%%", position.percentPnl))
                    .font(.system(size: 48, weight: .bold).monospacedDigit())
                    .foregroundStyle(
                        position.percentPnl >= 0
                            ? Color(red: 0.72, green: 0.96, blue: 0.88)
                            : Color(red: 1.0, green: 0.55, blue: 0.5)
                    )
                    .padding(.bottom, 8)

                Text("PnL \(PeakFormat.usd(position.cashPnl))  ·  Value \(PeakFormat.usd(position.currentValue))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))

                Spacer()

                HStack {
                    Text("Avg \(PeakFormat.cents(position.avgPrice)) → \(PeakFormat.cents(position.currentPrice))")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    PeakShareBrandFooter(trailing: "Trade on Peak")
                        .frame(maxWidth: 170)
                }
            }
            .padding(28)
        }
        .frame(width: 390, height: 520)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

struct SharePositionSheet: View {
    let position: PortfolioPosition
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
                            .padding(.horizontal, 20)
                            .accessibilityLabel("Share card for \(position.title)")
                            .accessibilityAddTraits(.isImage)
                    } else {
                        ProgressView("Rendering card…")
                            .frame(maxWidth: .infinity, minHeight: 320)
                    }
                }
                .padding(.vertical, 16)
            }
            .background(PeakMaterialBackground())
            .navigationTitle("Share position")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if let image {
                        ShareLink(
                            item: Image(uiImage: image),
                            preview: SharePreview(position.title, image: Image(uiImage: image))
                        ) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share position card")
                    }
                }
            }
            .task {
                let card = PeakPositionShareCard(position: position)
                let renderer = ImageRenderer(content: card)
                renderer.scale = 3
                renderer.isOpaque = true
                image = renderer.uiImage
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
