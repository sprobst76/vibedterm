package config

import (
	"os"
	"strconv"
	"time"
)

// Config holds all configuration for the server
type Config struct {
	// Server
	ServerAddr string
	ServerMode string // "debug", "release", "test"

	// Database
	DatabaseURL string

	// JWT
	JWTSecret            string
	AccessTokenDuration  time.Duration
	RefreshTokenDuration time.Duration

	// TOTP
	TOTPIssuer string

	// Rate Limiting
	RateLimitLogin   int // per minute
	RateLimitGeneral int // per minute

	// Admin
	AdminEmail    string
	AdminPassword string
}

// Load reads configuration from environment variables
func Load() *Config {
	return &Config{
		// Server
		ServerAddr: getEnv("SERVER_ADDR", ":8080"),
		ServerMode: getEnv("GIN_MODE", "debug"),

		// Database
		DatabaseURL: getEnv("DATABASE_URL", "postgres://vibedterm:vibedterm@localhost:5432/vibedterm?sslmode=disable"),

		// JWT
		JWTSecret:            getEnv("JWT_SECRET", "change-me-in-production-please"),
		AccessTokenDuration:  getDurationEnv("JWT_ACCESS_DURATION", 15*time.Minute),
		RefreshTokenDuration: getDurationEnv("JWT_REFRESH_DURATION", 30*24*time.Hour),

		// TOTP
		TOTPIssuer: getEnv("TOTP_ISSUER", "VibedTerm"),

		// Rate Limiting
		RateLimitLogin:   getIntEnv("RATE_LIMIT_LOGIN", 5),
		RateLimitGeneral: getIntEnv("RATE_LIMIT_GENERAL", 100),

		// Admin
		AdminEmail:    getEnv("ADMIN_EMAIL", ""),
		AdminPassword: getEnv("ADMIN_PASSWORD", ""),
	}
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func getIntEnv(key string, defaultValue int) int {
	if value := os.Getenv(key); value != "" {
		if i, err := strconv.Atoi(value); err == nil {
			return i
		}
	}
	return defaultValue
}

func getDurationEnv(key string, defaultValue time.Duration) time.Duration {
	if value := os.Getenv(key); value != "" {
		if d, err := time.ParseDuration(value); err == nil {
			return d
		}
	}
	return defaultValue
}
