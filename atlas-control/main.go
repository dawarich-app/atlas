package main

import (
	"log"
	"net/http"
	"os"

	"github.com/dawarich-app/atlas/atlas-control/internal/server"
)

func main() {
	cfg := server.Config{
		ComposeFile:    envOr("COMPOSE_FILE", "/work/compose.yml"),
		HostProjectDir: os.Getenv("HOST_PROJECT_DIR"),
		EnvFile:        envOr("ENV_FILE", "/work/.env"),
		StateDir:       envOr("STATE_DIR", "/var/lib/atlas-control"),
		DataDir:        envOr("DATA_DIR", "/work/data"),
		RegionsDir:     envOr("REGIONS_DIR", "/work/regions"),
		ListenAddr:     envOr("LISTEN_ADDR", envOr("ATLAS_CONTROL_ADDR", ":8090")),
	}

	addr := cfg.ListenAddr

	handler := server.New(cfg)

	log.Printf("atlas-control listening on %s", addr)
	if err := http.ListenAndServe(addr, handler); err != nil {
		log.Fatalf("atlas-control server exited: %v", err)
	}
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
