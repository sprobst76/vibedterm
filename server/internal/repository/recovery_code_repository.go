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

var ErrRecoveryCodeNotFound = errors.New("recovery code not found")

// RecoveryCodeRepository handles recovery code database operations
type RecoveryCodeRepository struct {
	db *pgxpool.Pool
}

// NewRecoveryCodeRepository creates a new recovery code repository
func NewRecoveryCodeRepository(db *pgxpool.Pool) *RecoveryCodeRepository {
	return &RecoveryCodeRepository{db: db}
}

// Create creates a new recovery code
func (r *RecoveryCodeRepository) Create(ctx context.Context, userID uuid.UUID, codeHash string) (*models.RecoveryCode, error) {
	code := &models.RecoveryCode{
		ID:        uuid.New(),
		UserID:    userID,
		CodeHash:  codeHash,
		Used:      false,
		CreatedAt: time.Now(),
	}

	_, err := r.db.Exec(ctx, `
		INSERT INTO recovery_codes (id, user_id, code_hash, used, created_at)
		VALUES ($1, $2, $3, $4, $5)
	`, code.ID, code.UserID, code.CodeHash, code.Used, code.CreatedAt)

	if err != nil {
		return nil, err
	}

	return code, nil
}

// GetByUserAndHash retrieves a recovery code by user ID and hash
func (r *RecoveryCodeRepository) GetByUserAndHash(ctx context.Context, userID uuid.UUID, codeHash string) (*models.RecoveryCode, error) {
	code := &models.RecoveryCode{}
	err := r.db.QueryRow(ctx, `
		SELECT id, user_id, code_hash, used, used_at, created_at
		FROM recovery_codes WHERE user_id = $1 AND code_hash = $2
	`, userID, codeHash).Scan(
		&code.ID, &code.UserID, &code.CodeHash, &code.Used, &code.UsedAt, &code.CreatedAt,
	)

	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrRecoveryCodeNotFound
	}
	if err != nil {
		return nil, err
	}

	return code, nil
}

// MarkUsed marks a recovery code as used
func (r *RecoveryCodeRepository) MarkUsed(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.Exec(ctx, `
		UPDATE recovery_codes SET used = true, used_at = NOW() WHERE id = $1
	`, id)
	return err
}

// DeleteAllForUser deletes all recovery codes for a user
func (r *RecoveryCodeRepository) DeleteAllForUser(ctx context.Context, userID uuid.UUID) error {
	_, err := r.db.Exec(ctx, `DELETE FROM recovery_codes WHERE user_id = $1`, userID)
	return err
}

// CountUnused counts unused recovery codes for a user
func (r *RecoveryCodeRepository) CountUnused(ctx context.Context, userID uuid.UUID) (int, error) {
	var count int
	err := r.db.QueryRow(ctx, `
		SELECT COUNT(*) FROM recovery_codes WHERE user_id = $1 AND used = false
	`, userID).Scan(&count)
	return count, err
}

// GetUnusedByUser returns all unused recovery codes for a user (for admin purposes)
func (r *RecoveryCodeRepository) GetUnusedByUser(ctx context.Context, userID uuid.UUID) ([]models.RecoveryCode, error) {
	rows, err := r.db.Query(ctx, `
		SELECT id, user_id, code_hash, used, used_at, created_at
		FROM recovery_codes WHERE user_id = $1 AND used = false
	`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var codes []models.RecoveryCode
	for rows.Next() {
		var code models.RecoveryCode
		err := rows.Scan(&code.ID, &code.UserID, &code.CodeHash, &code.Used, &code.UsedAt, &code.CreatedAt)
		if err != nil {
			return nil, err
		}
		codes = append(codes, code)
	}

	return codes, nil
}
