# Cardly

AI flashcards for active recall.

Backend internals — architecture, API reference, auth, MCP — are documented in
[`docs/`](docs/). This file covers setup and configuration.

Monorepo for the MVP:

- `backend`: Go REST API with PostgreSQL storage and simple review scheduling
- `web`: Next.js card management website
- `ios/MemoryApp`: SwiftUI review app

## Configuration

Both servers read configuration from the environment. Two variables have no
default and the process exits if they are missing, because the alternatives —
a hard-coded fallback secret, or silently signing tokens with a value published
in this repository — are worse than failing to boot.

| Variable | Required | Notes |
|---|---|---|
| `DATABASE_URL` | no | Defaults to the local Docker Postgres. |
| `AUTH_TOKEN_SECRET` | **yes, both servers** | HMAC key for session tokens, verification codes and MCP personal tokens. The API and MCP servers must be given the **same** value or tokens minted by one are rejected by the other. |
| `RESEND_API_KEY` | to send email | From resend.com. |
| `RESEND_FROM` | to send email | e.g. `Cardly <noreply@mail.example.com>`. The domain must be verified in Resend. |
| `AUTH_DEV_CODE_LOG` | no | Prints codes to the server log instead of sending them. **Takes priority over Resend**, so never set it in production. |
| `SMTP_HOST` / `SMTP_PORT` / `SMTP_USER` / `SMTP_PASS` / `SMTP_FROM` | no | Legacy fallback, used only when `RESEND_*` is absent. |
| `MEMORY_MCP_TOKEN` | no | Static bearer token shared with MCP clients. Maps to the demo user, so it is only useful for smoke tests. |
| `MEMORY_MCP_ALLOW_DEMO_TOKEN` | no | Must be `true` for the static token above to be accepted at all. Off by default: every holder lands in the same tenant and can see and delete each other's cards. |
| `MEMORY_MCP_OAUTH_ENABLED` | no | Enables the OAuth flow used by ChatGPT. |
| `MEMORY_MCP_OAUTH_TOKEN_SECRET` | **yes when OAuth is on** | Signs OAuth access tokens. Startup refuses values equal to `MEMORY_MCP_TOKEN` or `AUTH_TOKEN_SECRET`: those tokens carry a user id in their payload, so anyone holding a secret that also serves as a client credential could mint one for any account. |
| `MEMORY_MCP_OWNER_PASSWORD` | for OAuth | Entered on the authorization page. |
| `MEMORY_MCP_PUBLIC_URL` | for OAuth | Public origin, used to build the discovery documents. |
| `MEMORY_MCP_ALLOWED_HOSTS` | no | Defaults to `127.0.0.1,localhost`. **Requests arriving under any other Host get a 403**, so a deployment behind a domain must list it here. |

Sign-in works two ways against the same account: a six-digit code sent by
email, or a password. Passwords are optional — a code always works, an
account with no password simply cannot use the password form. Signing in
with a code to an address that has never been seen creates the account.

## Local Setup

Start PostgreSQL:

```bash
docker compose up -d postgres
```

Start the backend. `AUTH_DEV_CODE_LOG` keeps codes in the log so you do not
need working email in development:

```bash
cd backend
AUTH_TOKEN_SECRET=dev-secret \
AUTH_DEV_CODE_LOG=true \
PORT=8081 go run ./cmd/server
```

To exercise real delivery instead, drop `AUTH_DEV_CODE_LOG` and set the
Resend variables.

Start the MCP server. It must share `AUTH_TOKEN_SECRET` with the API server,
and its OAuth secret has to be distinct from both:

```bash
cd backend
AUTH_TOKEN_SECRET=dev-secret \
MEMORY_MCP_OAUTH_ENABLED=true \
MEMORY_MCP_OAUTH_TOKEN_SECRET=a-different-secret \
MEMORY_MCP_PUBLIC_URL=https://mcp.example.com \
MEMORY_MCP_ALLOWED_HOSTS=127.0.0.1,localhost,mcp.example.com \
MEMORY_MCP_OWNER_PASSWORD=replace-with-an-owner-password \
PORT=3001 go run ./cmd/mcp-server
```

The MCP endpoint is:

```text
https://mcp.example.com/mcp
```

In ChatGPT, create a custom app with OAuth authentication, client ID
`recall-deck-chatgpt`, no client secret, and token endpoint auth method `none`.

For clients that authenticate with a bearer token rather than OAuth, generate a
personal access token from **Me → MCP Access** in the iOS app. Unlike
`MEMORY_MCP_TOKEN`, a personal token is bound to your account, so cards created
through it land in your own data.

Available MCP tools:

- `get_subjects_sets`
- `add_cards` for single or batch card creation
- `delete_card`

The MCP server uses the same PostgreSQL database as the backend. It requires Go 1.23 or newer because it uses the official `modelcontextprotocol/go-sdk`.

## Tests

```bash
cd backend
go test ./...
```

Tests that need Postgres skip themselves when it is unreachable, so the suite
still runs without Docker — but it then covers much less. The suite in
`internal/api/isolation_test.go` is the regression net for tenant isolation:
each case drives the real router with one user's session against another
user's resources.

Start the website:

```bash
cd web
npm install
npm run dev
```

Open `http://localhost:3000/cards`.

## iOS

Open `ios/MemoryApp/MemoryApp.xcodeproj` in Xcode 16.4 or later.

The app talks to `https://api.siyuancheng.com/api` unless
`MEMORY_API_BASE_URL` is set, **including in the Simulator**. To run against a
local backend, set it in the Xcode scheme, or launch from the command line:

```bash
SIMCTL_CHILD_MEMORY_API_BASE_URL="http://127.0.0.1:8081/api" \
  xcrun simctl launch --terminate-running-process booted com.siyuancheng.MemoryApp
```

Note that the variable is read from the process environment, so tapping the app
icon in the Simulator starts it against production.

Install an iOS Simulator runtime from `Xcode > Settings > Platforms` before simulator builds.

## MVP Flow

1. Create a Subject and Tags in the website.
2. Create a card with Front, Answer, and Grammar / Phrases.
3. Open the iOS app, tap Review, choose Subject and Tags.
4. Tap the front card to show the back side.
5. Tap masked answer words to reveal them individually.
6. Rate Forgot, Fuzzy, or Remembered.
