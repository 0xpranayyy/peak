# Peak

Native SwiftUI iOS app for [Polymarket](https://polymarket.com) prediction markets.

Share.xyz–inspired: minimal, clean, Apple HIG / Liquid Glass (iOS 26 gated with `#available`).

## Phases

| Phase | Status | What |
| --- | --- | --- |
| **1** Browse | Done | Markets, search, charts, order book, WS prices, watchlist, read-only portfolio |
| **2** Trade | Done | Place FOK/GTC orders via Node proxy (keys off-device) |
| **3** Trading ops | Done | Open orders + cancel, live proxy portfolio/cash, deposit address |
| **4** Polish | Done | App icon, home-screen widget, TestFlight notes, version 1.1 |
| **5** Social | This branch | Follow wallets, activity feed, leaderboard, trader profiles |

## Open in Xcode

1. Open `Peak.xcodeproj` in Xcode 16+ (iOS 18+).
2. Select a simulator → set Development Team → ⌘R.
3. Add the **Trending market** widget: long-press Home Screen → Add Widget → Peak.

## Social

**Social** tab:
- **Feed** — recent activity from followed wallets
- **Leaders** — Data API `/v1/leaderboard` (day/week/month/all)
- **Following** — manage followed addresses
- Trader profiles — public profile + positions + activity; Follow/Unfollow

## Trading (Phases 2–3)

```bash
cd backend
cp .env.example .env   # APP_TOKEN, PRIVATE_KEY, FUNDER_ADDRESS
npm install && npm start
```

In Peak: **Portfolio → bolt → Trading** → proxy URL + token.

## TestFlight

1. Archive in Xcode → upload to App Store Connect.
2. Bundle ids: `com.pranay.peak` + `com.pranay.peak.widget`.

## APIs

- Gamma / CLOB public reads / Data API / market WebSocket
- Social: `/v1/leaderboard`, Gamma `public-profile`, `/activity`
- Authenticated CLOB via `backend/` proxy only
