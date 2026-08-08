package mcpserver

import (
	"os"
	"strconv"
	"strings"

	"memory-app/backend/internal/auth"
)

type Config struct {
	DatabaseURL                  string
	Addr                         string
	AuthToken                    string
	AllowedHosts                 []string
	AllowedOrigins               []string
	JSONResponse                 bool
	OAuthEnabled                 bool
	OAuthPublicURL               string
	OAuthClientID                string
	OAuthOwnerPassword           string
	OAuthTokenSecret             string
	OAuthAllowedRedirectPrefixes []string
	Auth                         auth.Config
}

func FromEnv() Config {
	authToken := strings.TrimSpace(os.Getenv("MEMORY_MCP_TOKEN"))
	return Config{
		DatabaseURL:                  env("DATABASE_URL", "postgres://memory:memory@localhost:5432/memory_app?sslmode=disable"),
		Addr:                         ":" + env("PORT", "3001"),
		AuthToken:                    authToken,
		AllowedHosts:                 splitCSV(env("MEMORY_MCP_ALLOWED_HOSTS", "127.0.0.1,localhost")),
		AllowedOrigins:               splitCSV(os.Getenv("MEMORY_MCP_ALLOWED_ORIGINS")),
		JSONResponse:                 envBool("MEMORY_MCP_JSON_RESPONSE", false),
		OAuthEnabled:                 envBool("MEMORY_MCP_OAUTH_ENABLED", false),
		OAuthPublicURL:               strings.TrimRight(env("MEMORY_MCP_PUBLIC_URL", "http://127.0.0.1:3001"), "/"),
		OAuthClientID:                env("MEMORY_MCP_OAUTH_CLIENT_ID", "recall-deck-chatgpt"),
		OAuthOwnerPassword:           strings.TrimSpace(os.Getenv("MEMORY_MCP_OWNER_PASSWORD")),
		OAuthTokenSecret:             env("MEMORY_MCP_OAUTH_TOKEN_SECRET", authToken),
		OAuthAllowedRedirectPrefixes: splitCSV(env("MEMORY_MCP_OAUTH_ALLOWED_REDIRECT_PREFIXES", "https://chatgpt.com/connector/oauth/")),
		Auth: auth.Config{
			TokenSecret: env("AUTH_TOKEN_SECRET", env("MEMORY_MCP_OAUTH_TOKEN_SECRET", authToken)),
			DevCodeLog:  envBool("AUTH_DEV_CODE_LOG", false),
			SMTP: auth.SMTPConfig{
				Host: strings.TrimSpace(os.Getenv("SMTP_HOST")),
				Port: env("SMTP_PORT", "587"),
				User: strings.TrimSpace(os.Getenv("SMTP_USER")),
				Pass: os.Getenv("SMTP_PASS"),
				From: strings.TrimSpace(os.Getenv("SMTP_FROM")),
			},
			Apple: auth.AppleConfig{
				TeamID:        strings.TrimSpace(os.Getenv("APPLE_TEAM_ID")),
				KeyID:         strings.TrimSpace(os.Getenv("APPLE_KEY_ID")),
				PrivateKey:    strings.TrimSpace(os.Getenv("APPLE_PRIVATE_KEY")),
				IOSBundleID:   env("APPLE_IOS_BUNDLE_ID", "com.siyuancheng.MemoryApp"),
				WebServicesID: strings.TrimSpace(os.Getenv("APPLE_WEB_SERVICES_ID")),
				RedirectURI:   strings.TrimSpace(os.Getenv("APPLE_REDIRECT_URI")),
			},
		},
	}
}

func env(key string, fallback string) string {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	return value
}

func envBool(key string, fallback bool) bool {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback
	}
	parsed, err := strconv.ParseBool(value)
	if err != nil {
		return fallback
	}
	return parsed
}

func splitCSV(value string) []string {
	parts := strings.Split(value, ",")
	values := make([]string, 0, len(parts))
	for _, part := range parts {
		part = strings.TrimSpace(part)
		if part != "" {
			values = append(values, part)
		}
	}
	return values
}
