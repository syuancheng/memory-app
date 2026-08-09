package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	authpkg "memory-app/backend/internal/auth"
	"memory-app/backend/internal/db"
	"memory-app/backend/internal/mcpserver"
)

func main() {
	cfg := mcpserver.FromEnv()
	ctx := context.Background()

	pool, err := db.Open(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("open database: %v", err)
	}
	defer pool.Close()

	if err := db.Migrate(ctx, pool); err != nil {
		log.Fatalf("migrate database: %v", err)
	}
	if err := db.EnsureDemoUser(ctx, pool); err != nil {
		log.Fatalf("ensure demo user: %v", err)
	}

	authService, err := authpkg.NewService(pool, cfg.Auth)
	if err != nil {
		log.Fatalf("configure auth: %v", err)
	}

	var oauthServer *mcpserver.OAuthServer
	if cfg.OAuthEnabled {
		oauthServer, err = mcpserver.NewOAuthServer(mcpserver.OAuthConfig{
			PublicURL:               cfg.OAuthPublicURL,
			ClientID:                cfg.OAuthClientID,
			OwnerPassword:           cfg.OAuthOwnerPassword,
			TokenSecret:             cfg.OAuthTokenSecret,
			AllowedRedirectPrefixes: cfg.OAuthAllowedRedirectPrefixes,
			AuthService:             authService,
		})
		if err != nil {
			log.Fatalf("configure oauth: %v", err)
		}
	}

	handler := mcpserver.NewHTTPHandler(pool, mcpserver.ServerConfig{
		AuthToken:      cfg.AuthToken,
		AllowedHosts:   cfg.AllowedHosts,
		AllowedOrigins: cfg.AllowedOrigins,
		JSONResponse:   cfg.JSONResponse,
		OAuthServer:    oauthServer,
		PersonalTokens: authService,
	})

	mux := http.NewServeMux()
	mux.Handle("/mcp", handler)
	mux.Handle("/mcp/", handler)
	if oauthServer != nil {
		mux.HandleFunc("/.well-known/oauth-protected-resource", oauthServer.HandleProtectedResourceMetadata)
		mux.HandleFunc("/.well-known/oauth-authorization-server", oauthServer.HandleAuthorizationServerMetadata)
		mux.HandleFunc("/.well-known/openid-configuration", oauthServer.HandleAuthorizationServerMetadata)
		mux.HandleFunc("/oauth/authorize", oauthServer.HandleAuthorize)
		mux.HandleFunc("/oauth/token", oauthServer.HandleToken)
		mux.HandleFunc("/oauth/apple/start", oauthServer.HandleAppleStart)
		mux.HandleFunc("/oauth/apple/callback", oauthServer.HandleAppleCallback)
	}
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	server := &http.Server{
		Addr:              cfg.Addr,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}

	go func() {
		log.Printf("memory MCP server listening on %s", cfg.Addr)
		if cfg.AuthToken == "" {
			log.Print("MEMORY_MCP_TOKEN is not set; MCP endpoint is unauthenticated")
		}
		if oauthServer != nil {
			log.Printf("oauth enabled for MCP client %q", oauthServer.ClientID())
		}
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("listen: %v", err)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := server.Shutdown(shutdownCtx); err != nil {
		log.Printf("shutdown: %v", err)
	}
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(value); err != nil {
		log.Printf("write json: %v", err)
	}
}
