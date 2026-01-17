package database

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/rs/zerolog/log"
)

// DB is the database connection pool
var DB *pgxpool.Pool

// Connect establishes a connection to the PostgreSQL database
func Connect(databaseURL string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	config, err := pgxpool.ParseConfig(databaseURL)
	if err != nil {
		return fmt.Errorf("failed to parse database URL: %w", err)
	}

	// Connection pool settings
	config.MaxConns = 25
	config.MinConns = 5
	config.MaxConnLifetime = time.Hour
	config.MaxConnIdleTime = 30 * time.Minute

	pool, err := pgxpool.NewWithConfig(ctx, config)
	if err != nil {
		return fmt.Errorf("failed to create connection pool: %w", err)
	}

	// Test connection
	if err := pool.Ping(ctx); err != nil {
		return fmt.Errorf("failed to ping database: %w", err)
	}

	DB = pool
	log.Info().Msg("Connected to PostgreSQL database")
	return nil
}

// Close closes the database connection pool
func Close() {
	if DB != nil {
		DB.Close()
		log.Info().Msg("Database connection closed")
	}
}

// RunMigrations executes database migrations
func RunMigrations(ctx context.Context) error {
	migrations := []string{
		migrationUsers,
		migrationDevices,
		migrationEncryptedVaults,
		migrationRefreshTokens,
		migrationRecoveryCodes,
		migrationSyncLogs,
		migrationIndexes,
	}

	for i, migration := range migrations {
		_, err := DB.Exec(ctx, migration)
		if err != nil {
			return fmt.Errorf("migration %d failed: %w", i+1, err)
		}
	}

	log.Info().Msg("Database migrations completed")
	return nil
}

const migrationUsers = `
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,

    is_approved BOOLEAN DEFAULT false,
    is_admin BOOLEAN DEFAULT false,
    is_blocked BOOLEAN DEFAULT false,

    totp_secret BYTEA,
    totp_enabled BOOLEAN DEFAULT false,
    totp_verified_at TIMESTAMP,

    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    last_login_at TIMESTAMP
);
`

const migrationDevices = `
CREATE TABLE IF NOT EXISTS devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    device_name VARCHAR(255) NOT NULL,
    device_type VARCHAR(50) NOT NULL,
    device_model VARCHAR(255),
    app_version VARCHAR(50),

    last_sync_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),

    UNIQUE(user_id, device_name)
);
`

const migrationEncryptedVaults = `
CREATE TABLE IF NOT EXISTS encrypted_vaults (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    vault_blob BYTEA NOT NULL,
    revision INTEGER NOT NULL DEFAULT 1,
    vault_version INTEGER DEFAULT 1,

    updated_by_device UUID REFERENCES devices(id),
    updated_at TIMESTAMP DEFAULT NOW(),
    created_at TIMESTAMP DEFAULT NOW()
);
`

const migrationRefreshTokens = `
CREATE TABLE IF NOT EXISTS refresh_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,

    token_hash VARCHAR(255) NOT NULL,
    expires_at TIMESTAMP NOT NULL,
    revoked BOOLEAN DEFAULT false,

    created_at TIMESTAMP DEFAULT NOW()
);
`

const migrationRecoveryCodes = `
CREATE TABLE IF NOT EXISTS recovery_codes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    code_hash VARCHAR(255) NOT NULL,
    used BOOLEAN DEFAULT false,
    used_at TIMESTAMP,

    created_at TIMESTAMP DEFAULT NOW()
);
`

const migrationSyncLogs = `
CREATE TABLE IF NOT EXISTS sync_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id UUID REFERENCES devices(id),

    action VARCHAR(50) NOT NULL,
    revision_before INTEGER,
    revision_after INTEGER,

    created_at TIMESTAMP DEFAULT NOW()
);
`

const migrationIndexes = `
CREATE INDEX IF NOT EXISTS idx_devices_user_id ON devices(user_id);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user_id ON refresh_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_expires ON refresh_tokens(expires_at);
CREATE INDEX IF NOT EXISTS idx_recovery_codes_user_id ON recovery_codes(user_id);
CREATE INDEX IF NOT EXISTS idx_sync_logs_user_id ON sync_logs(user_id);
`
