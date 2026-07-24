# Peak

Native SwiftUI iOS app for [Polymarket](https://polymarket.com) prediction markets.

Share.xyz–inspired: minimal, clean, Apple HIG / Liquid Glass (iOS 26 gated with `#available`). Browse markets, live prices, charts, watchlist, and a read-only portfolio. **No order placement in v1.**

## Open in Xcode

1. Open `Peak.xcodeproj` in Xcode 16+ (iOS 18 deployment target; Liquid Glass gated for iOS 26).
2. Select an iPhone simulator or device.
3. Set your Development Team under Signing & Capabilities if needed (`PRODUCT_BUNDLE_IDENTIFIER` is `com.pranay.peak`).
4. Run (⌘R).

The project uses `PBXFileSystemSynchronizedRootGroup` — everything under `Peak/` is picked up automatically.

## Features (v1)

| Tab | What it does |
| --- | --- |
| **Markets** | Gamma events with tags, sort (trending / volume / new / ending / liquidity), infinite scroll |
| **Search** | Gamma `public-search` + recent queries |
| **Event detail** | Outcome prices, Charts price history, CLOB order book / midpoint / spread, live WS prices |
| **Watchlist** | Local star list (UserDefaults) |
| **Portfolio** | Read-only positions + recent activity via Data API; wallet in Keychain |
| **Trade** | Yes/No opens a **Phase 2 stub sheet** — `TradingService` protocol is stubbed only |

## APIs

- **Gamma** `https://gamma-api.polymarket.com` — `/events`, `/markets`, `/public-search`, `/tags`
- **CLOB** `https://clob.polymarket.com` — `/price`, `/prices` (via concurrent `/price`), `/book`, `/prices-history`, `/midpoint`, `/spread`, `/clob-markets/{condition_id}`
- **Data** `https://data-api.polymarket.com` — `/positions?user=`, `/activity?user=`
- **WebSocket** `wss://ws-subscriptions-clob.polymarket.com/ws/market` — `assets_ids` subscribe, `PING` every 10s

Gamma fields like `outcomes`, `outcomePrices`, and `clobTokenIds` are decoded carefully (JSON-encoded strings or native arrays).

## Phase 2 (not in this branch)

Order placement against CLOB V2 needs wallet auth, EIP-712 order signing, and pUSD collateral. Peak exposes `TradingService` / `StubTradingService` so a future client can plug in without rewriting the trade sheet UI.

## Limitations

- Trading is intentionally unavailable (`StubTradingService` throws `TradingError.notAvailable`).
- Portfolio is wallet lookup only — positions + recent activity; no deposits or balances beyond Data API.
- App icon is a placeholder asset slot; add a 1024×1024 image in `Assets.xcassets/AppIcon`.
- Requires a Mac with Xcode to build/run; Command Line Tools alone are not enough for a full simulator run.
