# RecallDeck

AI flashcards for active recall.

Monorepo for the MVP:

- `backend`: Go REST API with PostgreSQL storage and simple review scheduling
- `web`: Next.js card management website
- `ios/MemoryApp`: SwiftUI review app

## Local Setup

Start PostgreSQL:

```bash
docker compose up -d postgres
```

Start the backend:

```bash
cd backend
PORT=8081 go run ./cmd/server
```

Start the MCP server for ChatGPT or another MCP client:

```bash
cd backend
PORT=3001 MEMORY_MCP_TOKEN=replace-with-a-secret go run ./cmd/mcp-server
```

For ChatGPT custom MCP apps, enable the built-in single-user OAuth flow:

```bash
cd backend
PORT=3001 \
MEMORY_MCP_OAUTH_ENABLED=true \
MEMORY_MCP_PUBLIC_URL=https://mcp.example.com \
MEMORY_MCP_OAUTH_CLIENT_ID=recall-deck-chatgpt \
MEMORY_MCP_OWNER_PASSWORD=replace-with-an-owner-password \
MEMORY_MCP_OAUTH_TOKEN_SECRET=replace-with-a-token-signing-secret \
go run ./cmd/mcp-server
```

The MCP endpoint is:

```text
https://mcp.example.com/mcp
```

In ChatGPT, create a custom app with OAuth authentication, client ID
`recall-deck-chatgpt`, no client secret, and token endpoint auth method `none`.

Available MCP tools:

- `get_subjects_sets`
- `add_cards` for single or batch card creation
- `delete_card`

The MCP server uses the same PostgreSQL database as the backend. It requires Go 1.23 or newer because it uses the official `modelcontextprotocol/go-sdk`.

Start the website:

```bash
cd web
npm install
npm run dev
```

Open `http://localhost:3000/cards`.

## iOS

Open `ios/MemoryApp/MemoryApp.xcodeproj` in Xcode 16.4 or later.

For iOS Simulator, the default API base URL is:

```text
http://127.0.0.1:8081/api
```

For a physical iPhone, set the `MEMORY_API_BASE_URL` environment variable in the Xcode scheme to your Mac LAN IP, for example:

```text
http://192.168.1.20:8080/api
```

Install an iOS Simulator runtime from `Xcode > Settings > Platforms` before simulator builds.

## MVP Flow

1. Create a Subject and Tags in the website.
2. Create a card with Front, Answer, and Grammar / Phrases.
3. Open the iOS app, tap Review, choose Subject and Tags.
4. Tap the front card to show the back side.
5. Tap masked answer words to reveal them individually.
6. Rate Forgot, Fuzzy, or Remembered.
