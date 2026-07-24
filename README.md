# Peak

Native SwiftUI iOS app for [Polymarket](https://polymarket.com) prediction markets.

Share.xyz–inspired: minimal, clean, Apple HIG / Liquid Glass (iOS 26 gated with `#available`).

## Phases

| Phase | Status | What |
| --- | --- | --- |
| **1** Browse | Done | Markets, search, charts, order book, WS prices, watchlist, read-only portfolio |
| **2** Trade | Done | Place FOK/GTC orders via Node proxy (keys off-device) |
| **3** Trading ops | Done | Open orders + cancel, live proxy portfolio/cash, deposit address |
| **4** Polish | This branch | App icon, home-screen widget, TestFlight notes, version 1.1 |
| **5** Social | Later | Wallet follow / activity feed (Share-like) |

## Open in Xcode

1. Open `Peak.xcodeproj` in Xcode 16+ (iOS 18+).
2. Select a simulator → set Development Team → ⌘R.
3. Add the **Trending market** widget: long-press Home Screen → Add Widget → Peak.

## Trading (Phases 2–3)

```bash
cd backend
cp .env.example .env   # APP_TOKEN, PRIVATE_KEY, FUNDER_ADDRESS
npm install && npm start
```

In Peak: **Portfolio → bolt → Trading** → proxy URL + token.

## TestFlight

1. In Xcode: select **Any iOS Device**, Product → Archive.
2. Organizer → Distribute App → App Store Connect → Upload.
3. App Store Connect → TestFlight → add internal/external testers.
4. Ensure bundle id `com.pranay.peak` and widget `com.pranay.peak.widget` share the same team.

Marketing version is **1.1** (build 2).

## APIs

- Gamma / CLOB public reads / Data API / market WebSocket
- Authenticated CLOB via `backend/` proxy only
