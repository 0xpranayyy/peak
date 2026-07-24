# Peak trading proxy

Node server that signs Polymarket **CLOB V2** orders with your private key so the iOS app never stores it.

## Setup

```bash
cd backend
cp .env.example .env
# edit .env — APP_TOKEN, PRIVATE_KEY, FUNDER_ADDRESS
npm install
npm start
```

Health check:

```bash
curl -H "Authorization: Bearer $APP_TOKEN" http://127.0.0.1:8080/health
```

On a physical iPhone, use your Mac’s LAN IP (e.g. `http://192.168.1.20:8080`) in **Portfolio → Trading**.

## Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/health` | Connectivity |
| GET | `/portfolio` | Positions + balance for `FUNDER_ADDRESS` |
| GET | `/activity` | Recent activity |
| GET | `/orders` | Open orders + trades |
| POST | `/orders` | Place order `{ tokenID, price, size, side, orderType? }` |
| DELETE | `/orders/:id` | Cancel |

All routes require `Authorization: Bearer <APP_TOKEN>`.
