# Minimal English Memory App

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
