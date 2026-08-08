package config

import (
	"os"
	"strings"

	"memory-app/backend/internal/auth"
)

type Config struct {
	DatabaseURL string
	Port        string
	AppEnv      string
	Auth        auth.Config
}

func FromEnv() Config {
	return Config{
		DatabaseURL: env("DATABASE_URL", "postgres://memory:memory@localhost:5432/memory_app?sslmode=disable"),
		Port:        env("PORT", "8080"),
		AppEnv:      env("APP_ENV", "development"),
		Auth: auth.Config{
			TokenSecret: env("AUTH_TOKEN_SECRET", env("MEMORY_MCP_OAUTH_TOKEN_SECRET", "development-auth-secret")),
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
	value := strings.ToLower(strings.TrimSpace(os.Getenv(key)))
	if value == "" {
		return fallback
	}
	return value == "1" || value == "true" || value == "yes"
}
