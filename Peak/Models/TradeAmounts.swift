import Foundation

/// Converts what the user typed into what CLOB is sent.
///
/// Extracted from `TradeStubSheet` so it can be tested: this decides how much
/// money moves, and it previously lived in `private` computed properties on a
/// View where nothing could reach it. The unit rules are subtle enough that a
/// mistake is silent — a sell interpreted as dollars instead of shares does not
/// error, it just sells the wrong quantity.
struct TradeAmounts: Equatable {
    /// Sells are entered in shares, buys in dollars.
    let isSell: Bool
    /// FOK/FAK are market orders; GTC/GTD are limits.
    let isMarket: Bool
    let price: Double
    /// The raw number in the field, in whichever unit the action uses.
    let entered: Double

    /// Dollar value of the order.
    var usd: Double {
        isSell ? entered * price : entered
    }

    /// Share quantity of the order.
    var shares: Double {
        if isSell { return entered }
        guard price > 0 else { return 0 }
        return entered / price
    }

    /// The `amount` CLOB expects.
    ///
    /// A market BUY spends a dollar budget; everything else is denominated in
    /// shares. Getting this backwards is the dangerous case — it would submit a
    /// valid order for the wrong size rather than failing.
    var orderAmount: Double {
        if isMarket && !isSell { return usd }
        return shares
    }

    /// Whether this is submittable at all. Prices outside (0,1) are not valid
    /// probabilities, and a zero amount is not an order.
    var isValid: Bool {
        entered > 0 && usd > 0 && shares > 0 && price > 0 && price < 1
    }
}

/// What actually happened to a submitted order, in the user's terms.
///
/// Market sells are FAK (fill-and-kill): CLOB fills whatever the book supports
/// and cancels the rest, rather than killing the whole order because one share
/// short. That is the right trade — a FOK sell into a thin book fails outright
/// and the user keeps every share — but it introduces an outcome the app did
/// not previously have to describe: a *partial* fill.
///
/// Reporting that honestly is the whole reason this type exists. Saying "your
/// order was submitted" when 34 of 50 shares sold would leave someone believing
/// they had exited a position they are still half in.
struct TradeFill: Equatable {
    /// Shares the user asked to trade.
    let requested: Double
    /// Shares actually filled — `nil` when the response did not report it.
    let filled: Double?
    let isSell: Bool

    /// Dust tolerance. Tick rounding can leave a hair under the requested size;
    /// that is a complete fill to a human, not a partial one worth a warning.
    private static let completeThreshold = 0.99

    /// Nothing matched. CLOB accepts such an order and reports success with a
    /// zero fill, so this is *not* an error path — but it is a failure to the
    /// user, and must never read as a success.
    var isEmpty: Bool {
        guard let filled else { return false }
        return filled <= 0
    }

    /// Filled meaningfully less than asked.
    var isPartial: Bool {
        guard let filled, filled > 0, requested > 0 else { return false }
        return filled < requested * Self.completeThreshold
    }

    /// True only when we can positively say the whole order filled.
    var isComplete: Bool {
        guard let filled, requested > 0 else { return false }
        return filled >= requested * Self.completeThreshold
    }

    /// Whether the UI should present this as a success.
    var didSucceed: Bool { !isEmpty }

    var message: String {
        let verb = isSell ? "sold" : "bought"
        if isEmpty {
            // Deliberately explains *why* and what to do, because the user's
            // shares are untouched and they need to decide whether to retry.
            return isSell
                ? "No buyers at this price right now, so nothing was sold. Your shares are untouched — try a lower price or a smaller size."
                : "No sellers at this price right now, so nothing was bought. Your cash is untouched — try a higher price or a smaller size."
        }
        if isPartial, let filled {
            return "Partly filled — \(Self.shares(filled)) of \(Self.shares(requested)) shares \(verb). The rest couldn’t be matched and was cancelled."
        }
        if isComplete, let filled {
            return "Filled — \(Self.shares(filled)) shares \(verb)."
        }
        // Fill size unknown. Never invent one; the vaguer line is the honest one.
        return "Your order was submitted."
    }

    /// Trims trailing zeros so whole share counts don't read as "50.00".
    private static func shares(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded() && abs(rounded) < 1_000_000 {
            return String(format: "%.0f", rounded)
        }
        return String(format: "%.2f", rounded)
    }
}
