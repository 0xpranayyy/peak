# Peak

Native SwiftUI iOS app for [Polymarket](https://polymarket.com) prediction markets.

Share.xyz–inspired: minimal, clean, Apple HIG / Liquid Glass (iOS 26 gated with `#available`).

## Phases

| Phase | Status | What |
| --- | --- | --- |
| **1** Browse | Done | Markets, search, charts, order book, WS prices, watchlist, read-only portfolio |
| **2** Trade | Done | Place FOK/GTC orders via Node proxy (keys off-device) |
| **3** Trading ops | This branch | Open orders + cancel, live proxy portfolio/cash, deposit address |
| **4** Polish | Next | App icon, widgets / Live Activities, TestFlight |
| **5** Social | Later | Wallet follow / activity feed (Share-like) |

## Open in Xcode

1. Open `Peak.xcodeproj` in Xcode 16+ (iOS 18+).
2. Select a simulator → set Development Team → ⌘R.

## Trading (Phases 2–3)

```bash
cd backend
cp .env.example .env   # APP_TOKEN, PRIVATE_KEY, FUNDER_ADDRESS
npm install && npm start
```

In Peak: **Portfolio → bolt → Trading** → proxy URL + token.

Then you can:
- Place orders from event detail
- See **open orders** and cancel them
- View **cash / live portfolio** from the proxy
- **Deposit** via Polymarket Bridge address sheet

See [backend/README.md](backend/README.md).

## APIs

- Gamma / CLOB public reads / Data API / market WebSocket
- Authenticated CLOB via `backend/` proxy only
