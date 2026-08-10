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
			// 不设兜底值。曾经回落到硬编码的 "development-auth-secret"，
			// 意味着生产忘配也会静默启动，并用一个公开在源码里的密钥签发全部
			// session token 与验证码哈希。缺失时宁可启动失败。
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
