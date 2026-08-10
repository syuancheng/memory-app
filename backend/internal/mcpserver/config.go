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
	// AllowDemoToken 允许静态 MEMORY_MCP_TOKEN 映射到共享的 demo 用户。
	// 默认关闭：静态 token 是分发给客户端的共享凭据，所有持有者会落到同一个
	// 租户里互相可见可删。真实场景请改用个人访问令牌（mcp_tokens）。
	AllowDemoToken bool
	Auth           auth.Config
}

// Validate 在启动时强制密钥隔离。
//
// 背景：OAuthTokenSecret 曾经默认回落到 MEMORY_MCP_TOKEN，而后者是要**分发给
// MCP 客户端**的共享静态 token。由于 OAuth 访问令牌的 payload 里明文带 user_id
// 且仅靠该密钥做 HMAC 校验，任何持有静态 token 的人都能自行签发
// {"sub":"owner","user_id":"<任意受害者>"} 并完整读写该用户的数据。
// 因此三个密钥必须各自独立配置，不能互相回落。
func (c Config) Validate() error {
	if c.Auth.TokenSecret == "" {
		return errors.New("AUTH_TOKEN_SECRET is required")
	}
	if c.OAuthEnabled {
		if c.OAuthTokenSecret == "" {
			return errors.New("MEMORY_MCP_OAUTH_TOKEN_SECRET is required when OAuth is enabled")
		}
		if c.AuthToken != "" && c.OAuthTokenSecret == c.AuthToken {
			return errors.New("MEMORY_MCP_OAUTH_TOKEN_SECRET must differ from MEMORY_MCP_TOKEN: the latter is shared with clients and would let any holder forge access tokens for any user")
		}
		if c.OAuthTokenSecret == c.Auth.TokenSecret {
			return errors.New("MEMORY_MCP_OAUTH_TOKEN_SECRET must differ from AUTH_TOKEN_SECRET")
		}
	}
	return nil
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
		OAuthTokenSecret:             strings.TrimSpace(os.Getenv("MEMORY_MCP_OAUTH_TOKEN_SECRET")),
		AllowDemoToken:               envBool("MEMORY_MCP_ALLOW_DEMO_TOKEN", false),
		OAuthAllowedRedirectPrefixes: splitCSV(env("MEMORY_MCP_OAUTH_ALLOWED_REDIRECT_PREFIXES", "https://chatgpt.com/connector/oauth/")),
		Auth: auth.Config{
			TokenSecret: strings.TrimSpace(os.Getenv("AUTH_TOKEN_SECRET")),
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
