# Peak

Native SwiftUI iOS app for [Polymarket](https://polymarket.com) prediction markets.

Share.xyz–inspired: minimal, clean, Apple HIG / Liquid Glass (iOS 26 gated with `#available`). Browse markets, live prices, charts, watchlist, read-only portfolio, and **Phase 2 trading via a local proxy**.

## Open in Xcode

1. Open `Peak.xcodeproj` in Xcode 16+ (iOS 18 deployment target; Liquid Glass gated for iOS 26).
2. Select an iPhone simulator or device.
3. Set your Development Team under Signing & Capabilities if needed (`PRODUCT_BUNDLE_IDENTIFIER` is `com.pranay.peak`).
4. Run (⌘R).

The project uses `PBXFileSystemSynchronizedRootGroup` — everything under `Peak/` is picked up automatically.

## Features

| Tab | What it does |
| --- | --- |
| **Markets** | Gamma events with tags, sort, infinite scroll |
| **Search** | Gamma `public-search` + recent queries |
| **Event detail** | Charts, order book, live WS prices, Yes/No trade sheet |
| **Watchlist** | Local star list |
| **Portfolio** | Read-only positions + activity; trading proxy settings |

## Phase 2 trading

Private keys **never** enter the iOS app. Orders go through `backend/` (Node + `@polymarket/clob-client-v2`):

1. Configure `backend/.env` from `.env.example` and `npm start`.
2. In Peak: **Portfolio → bolt icon → Trading** — set proxy URL + `APP_TOKEN`.
3. On a market, tap Buy Yes/No → Place order.

See [backend/README.md](backend/README.md).

`TradingService` / `RemoteTradingService` is the seam; swap implementations without rewriting the trade UI.

## APIs (read path)

- **Gamma** `https://gamma-api.polymarket.com`
- **CLOB** `https://clob.polymarket.com` (public reads + proxy for signed orders)
- **Data** `https://data-api.polymarket.com`
- **WebSocket** `wss://ws-subscriptions-clob.polymarket.com/ws/market`

## Limitations

- Native in-app key import / EIP-712 signing is not shipped (proxy model instead).
- App icon is a placeholder; add a 1024×1024 asset when ready.
- Full Xcode is required to build/run on simulator.
