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
