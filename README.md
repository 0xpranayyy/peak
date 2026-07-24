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
| **Search** | Gamma `public-search` across events & markets |
| **Event detail** | Outcome prices, Charts price history, CLOB order book / midpoint / spread, live WS prices |
| **Watchlist** | Local star list (UserDefaults) |
| **Portfolio** | Read-only positions via Data API; wallet address in Keychain |
| **Trade** | Yes/No opens a **Phase 2 stub sheet** — `TradingService` protocol is stubbed only |

## APIs

- **Gamma** `https://gamma-api.polymarket.com` — `/events`, `/markets`, `/public-search`, `/tags`
- **CLOB** `https://clob.polymarket.com` — `/price`, `/book`, `/prices-history`, `/midpoint`, `/spread`, `/clob-markets/{condition_id}`
- **Data** `https://data-api.polymarket.com` — `/positions?user=`
- **WebSocket** `wss://ws-subscriptions-clob.polymarket.com/ws/market` — `assets_ids` subscribe, `PING` every 10s

Gamma fields like `outcomes`, `outcomePrices`, and `clobTokenIds` are decoded carefully (JSON-encoded strings or native arrays).

## Project layout

```
Peak.xcodeproj/
Peak/
  PeakApp.swift
  Info.plist
  App/RootTabView.swift
  Features/Markets Search EventDetail Watchlist Portfolio
  DesignSystem/
  Networking/
  Models/
  Services/
  Assets.xcassets/
```

## Limitations

- Trading is intentionally unavailable (`StubTradingService` throws `TradingError.notAvailable`).
- Portfolio is wallet lookup only — no auth, balances beyond positions, or deposits.
- App icon is a placeholder asset slot; add a 1024×1024 image in `Assets.xcassets/AppIcon`.
- Requires a Mac with Xcode to build/run; Command Line Tools alone are not enough for a full simulator run.
