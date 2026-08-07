package mcpserver

import (
	"os"
	"strconv"
	"strings"
)

type Config struct {
	DatabaseURL    string
	Addr           string
	AuthToken      string
	AllowedHosts   []string
	AllowedOrigins []string
	JSONResponse   bool
}

func FromEnv() Config {
	return Config{
		DatabaseURL:    env("DATABASE_URL", "postgres://memory:memory@localhost:5432/memory_app?sslmode=disable"),
		Addr:           ":" + env("PORT", "3001"),
		AuthToken:      strings.TrimSpace(os.Getenv("MEMORY_MCP_TOKEN")),
		AllowedHosts:   splitCSV(env("MEMORY_MCP_ALLOWED_HOSTS", "127.0.0.1,localhost")),
		AllowedOrigins: splitCSV(os.Getenv("MEMORY_MCP_ALLOWED_ORIGINS")),
		JSONResponse:   envBool("MEMORY_MCP_JSON_RESPONSE", false),
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
