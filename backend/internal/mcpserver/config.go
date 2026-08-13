package mcpserver

import (
	"errors"
	"os"
	"strings"

	"memory-app/backend/internal/auth"
)

type Config struct {
	DatabaseURL                  string
	Addr                         string
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

// Validate 在启动时强制密钥隔离。
//
// OAuth access token payload 里带 user_id，并靠该密钥做 HMAC 校验。
// 因此 OAuth token secret 必须独立配置，不能回落到 app session secret。
func (c Config) Validate() error {
	if c.Auth.TokenSecret == "" {
		return errors.New("AUTH_TOKEN_SECRET is required")
	}
	if c.OAuthEnabled {
		if c.OAuthTokenSecret == "" {
			return errors.New("MEMORY_MCP_OAUTH_TOKEN_SECRET is required when OAuth is enabled")
		}
		if c.OAuthTokenSecret == c.Auth.TokenSecret {
			return errors.New("MEMORY_MCP_OAUTH_TOKEN_SECRET must differ from AUTH_TOKEN_SECRET")
		}
	}
	return nil
}

func FromEnv() Config {
	return Config{
		DatabaseURL:                  env("DATABASE_URL", "postgres://memory:memory@localhost:5432/memory_app?sslmode=disable"),
		Addr:                         ":" + env("PORT", "3001"),
		AllowedHosts:                 splitCSV(env("MEMORY_MCP_ALLOWED_HOSTS", "127.0.0.1,localhost")),
		AllowedOrigins:               splitCSV(os.Getenv("MEMORY_MCP_ALLOWED_ORIGINS")),
		JSONResponse:                 envBool("MEMORY_MCP_JSON_RESPONSE", false),
		OAuthEnabled:                 envBool("MEMORY_MCP_OAUTH_ENABLED", false),
		OAuthPublicURL:               strings.TrimRight(env("MEMORY_MCP_PUBLIC_URL", "http://127.0.0.1:3001"), "/"),
		OAuthClientID:                env("MEMORY_MCP_OAUTH_CLIENT_ID", "recall-deck-chatgpt"),
		OAuthOwnerPassword:           strings.TrimSpace(os.Getenv("MEMORY_MCP_OWNER_PASSWORD")),
		OAuthTokenSecret:             strings.TrimSpace(os.Getenv("MEMORY_MCP_OAUTH_TOKEN_SECRET")),
		OAuthAllowedRedirectPrefixes: splitCSV(env("MEMORY_MCP_OAUTH_ALLOWED_REDIRECT_PREFIXES", "https://chatgpt.com/connector/oauth/")),
		Auth: auth.Config{
			TokenSecret: strings.TrimSpace(os.Getenv("AUTH_TOKEN_SECRET")),
			DevCodeLog:  envBool("AUTH_DEV_CODE_LOG", false),
			Resend: auth.ResendConfig{
				APIKey: strings.TrimSpace(os.Getenv("RESEND_API_KEY")),
				From:   strings.TrimSpace(os.Getenv("RESEND_FROM")),
			},
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

// envBool 与 internal/config 的实现保持一致。此前这里用 strconv.ParseBool，
// 不接受 "yes"，导致同一份环境变量在 API 与 MCP 两个进程里行为不同。
func envBool(key string, fallback bool) bool {
	value := strings.ToLower(strings.TrimSpace(os.Getenv(key)))
	if value == "" {
		return fallback
	}
	switch value {
	case "1", "true", "yes", "on":
		return true
	case "0", "false", "no", "off":
		return false
	default:
		return fallback
	}
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
