package repository

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/sprobst76/vibedterm-server/internal/models"
)

var ErrRefreshTokenNotFound = errors.New("refresh token not found")

// RefreshTokenRepository handles refresh token database operations
type RefreshTokenRepository struct {
	db *pgxpool.Pool
}

// NewRefreshTokenRepository creates a new refresh token repository
func NewRefreshTokenRepository(db *pgxpool.Pool) *RefreshTokenRepository {
	return &RefreshTokenRepository{db: db}
}

// Create creates a new refresh token
func (r *RefreshTokenRepository) Create(ctx context.Context, userID, deviceID uuid.UUID, tokenHash string, expiresAt time.Time) (*models.RefreshToken, error) {
	token := &models.RefreshToken{
		ID:        uuid.New(),
		UserID:    userID,
		DeviceID:  deviceID,
		TokenHash: tokenHash,
		ExpiresAt: expiresAt,
		Revoked:   false,
		CreatedAt: time.Now(),
	}

	_, err := r.db.Exec(ctx, `
		INSERT INTO refresh_tokens (id, user_id, device_id, token_hash, expires_at, revoked, created_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
	`, token.ID, token.UserID, token.DeviceID, token.TokenHash, token.ExpiresAt, token.Revoked, token.CreatedAt)

	if err != nil {
		return nil, err
	}

	return token, nil
}

// GetByTokenHash retrieves a refresh token by its hash
func (r *RefreshTokenRepository) GetByTokenHash(ctx context.Context, tokenHash string) (*models.RefreshToken, error) {
	token := &models.RefreshToken{}
	err := r.db.QueryRow(ctx, `
		SELECT id, user_id, device_id, token_hash, expires_at, revoked, created_at
		FROM refresh_tokens WHERE token_hash = $1
	`, tokenHash).Scan(
		&token.ID, &token.UserID, &token.DeviceID, &token.TokenHash,
		&token.ExpiresAt, &token.Revoked, &token.CreatedAt,
	)

	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrRefreshTokenNotFound
	}
	if err != nil {
		return nil, err
	}

	return token, nil
}

// Revoke revokes a refresh token by hash
func (r *RefreshTokenRepository) Revoke(ctx context.Context, tokenHash string) error {
	_, err := r.db.Exec(ctx, `
		UPDATE refresh_tokens SET revoked = true WHERE token_hash = $1
	`, tokenHash)
	return err
}

// RevokeAllForUser revokes all refresh tokens for a user
func (r *RefreshTokenRepository) RevokeAllForUser(ctx context.Context, userID uuid.UUID) error {
	_, err := r.db.Exec(ctx, `
		UPDATE refresh_tokens SET revoked = true WHERE user_id = $1
	`, userID)
	return err
}

// RevokeAllForDevice revokes all refresh tokens for a device
func (r *RefreshTokenRepository) RevokeAllForDevice(ctx context.Context, deviceID uuid.UUID) error {
	_, err := r.db.Exec(ctx, `
		UPDATE refresh_tokens SET revoked = true WHERE device_id = $1
	`, deviceID)
	return err
}

// CleanupExpired removes expired tokens
func (r *RefreshTokenRepository) CleanupExpired(ctx context.Context) (int64, error) {
	result, err := r.db.Exec(ctx, `
		DELETE FROM refresh_tokens WHERE expires_at < NOW() OR revoked = true
	`)
	if err != nil {
		return 0, err
	}
	return result.RowsAffected(), nil
}
