package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"memory-app/backend/internal/api"
	"memory-app/backend/internal/auth"
	"memory-app/backend/internal/config"
	"memory-app/backend/internal/db"
)

func main() {
	cfg := config.FromEnv()
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
	if err := db.EnsureDemoData(ctx, pool); err != nil {
		log.Fatalf("ensure demo data: %v", err)
	}
	authService, err := auth.NewService(pool, cfg.Auth)
	if err != nil {
		log.Fatalf("configure auth: %v", err)
	}

	server := &http.Server{
		Addr:              ":" + cfg.Port,
		Handler:           api.NewServer(pool, authService),
		ReadHeaderTimeout: 5 * time.Second,
	}

	go func() {
		log.Printf("backend listening on :%s", cfg.Port)
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
