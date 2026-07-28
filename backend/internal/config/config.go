package config

import "os"

type Config struct {
	DatabaseURL string
	Port        string
	AppEnv      string
}

func FromEnv() Config {
	return Config{
		DatabaseURL: env("DATABASE_URL", "postgres://memory:memory@localhost:5432/memory_app?sslmode=disable"),
		Port:        env("PORT", "8080"),
		AppEnv:      env("APP_ENV", "development"),
	}
}

func env(key string, fallback string) string {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	return value
}
