package main

import (
	"context"
	"github.com/leonardobarrosx/ninho/backend/internal/api"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"
)

func main() {
	cfg := api.Config{SupabaseURL: strings.TrimRight(os.Getenv("SUPABASE_URL"), "/"), PublishableKey: os.Getenv("SUPABASE_PUBLISHABLE_KEY"), SecretKey: os.Getenv("SUPABASE_SECRET_KEY"), Origins: strings.Split(os.Getenv("ALLOWED_ORIGINS"), ",")}
	if err := cfg.Validate(); err != nil {
		slog.Error("invalid configuration", "error", err)
		os.Exit(1)
	}
	if cfg.SecretKey == "" {
		// Google Play requires in-app account deletion, so production needs the key.
		slog.Warn("SUPABASE_SECRET_KEY is not set: account deletion is disabled")
	}
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	server := &http.Server{Addr: ":" + port, Handler: api.New(cfg), ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 15 * time.Second, WriteTimeout: 30 * time.Second, IdleTimeout: 60 * time.Second, MaxHeaderBytes: 16384}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	go func() {
		<-ctx.Done()
		shutdown, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		_ = server.Shutdown(shutdown)
	}()
	slog.Info("api listening", "port", port)
	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		slog.Error("server stopped", "error", err)
		os.Exit(1)
	}
}
