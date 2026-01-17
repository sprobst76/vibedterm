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

var (
	ErrUserNotFound      = errors.New("user not found")
	ErrUserAlreadyExists = errors.New("user already exists")
)

// UserRepository handles user database operations
type UserRepository struct {
	db *pgxpool.Pool
}

// NewUserRepository creates a new user repository
func NewUserRepository(db *pgxpool.Pool) *UserRepository {
	return &UserRepository{db: db}
}

// Create creates a new user
func (r *UserRepository) Create(ctx context.Context, email, passwordHash string) (*models.User, error) {
	user := &models.User{
		ID:           uuid.New(),
		Email:        email,
		PasswordHash: passwordHash,
		IsApproved:   false,
		IsAdmin:      false,
		IsBlocked:    false,
		TOTPEnabled:  false,
		CreatedAt:    time.Now(),
		UpdatedAt:    time.Now(),
	}

	_, err := r.db.Exec(ctx, `
		INSERT INTO users (id, email, password_hash, is_approved, is_admin, is_blocked, totp_enabled, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
	`, user.ID, user.Email, user.PasswordHash, user.IsApproved, user.IsAdmin, user.IsBlocked, user.TOTPEnabled, user.CreatedAt, user.UpdatedAt)

	if err != nil {
		// Check for unique constraint violation
		if err.Error() == "ERROR: duplicate key value violates unique constraint \"users_email_key\" (SQLSTATE 23505)" {
			return nil, ErrUserAlreadyExists
		}
		return nil, err
	}

	return user, nil
}

// GetByID retrieves a user by ID
func (r *UserRepository) GetByID(ctx context.Context, id uuid.UUID) (*models.User, error) {
	user := &models.User{}
	err := r.db.QueryRow(ctx, `
		SELECT id, email, password_hash, is_approved, is_admin, is_blocked,
		       totp_secret, totp_enabled, totp_verified_at, created_at, updated_at, last_login_at
		FROM users WHERE id = $1
	`, id).Scan(
		&user.ID, &user.Email, &user.PasswordHash, &user.IsApproved, &user.IsAdmin, &user.IsBlocked,
		&user.TOTPSecret, &user.TOTPEnabled, &user.TOTPVerified, &user.CreatedAt, &user.UpdatedAt, &user.LastLoginAt,
	)

	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrUserNotFound
	}
	if err != nil {
		return nil, err
	}

	return user, nil
}

// GetByEmail retrieves a user by email
func (r *UserRepository) GetByEmail(ctx context.Context, email string) (*models.User, error) {
	user := &models.User{}
	err := r.db.QueryRow(ctx, `
		SELECT id, email, password_hash, is_approved, is_admin, is_blocked,
		       totp_secret, totp_enabled, totp_verified_at, created_at, updated_at, last_login_at
		FROM users WHERE email = $1
	`, email).Scan(
		&user.ID, &user.Email, &user.PasswordHash, &user.IsApproved, &user.IsAdmin, &user.IsBlocked,
		&user.TOTPSecret, &user.TOTPEnabled, &user.TOTPVerified, &user.CreatedAt, &user.UpdatedAt, &user.LastLoginAt,
	)

	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrUserNotFound
	}
	if err != nil {
		return nil, err
	}

	return user, nil
}

// UpdateLastLogin updates the last login timestamp
func (r *UserRepository) UpdateLastLogin(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.Exec(ctx, `
		UPDATE users SET last_login_at = NOW(), updated_at = NOW() WHERE id = $1
	`, id)
	return err
}

// SetTOTPSecret sets the TOTP secret for a user
func (r *UserRepository) SetTOTPSecret(ctx context.Context, id uuid.UUID, secret []byte) error {
	_, err := r.db.Exec(ctx, `
		UPDATE users SET totp_secret = $2, updated_at = NOW() WHERE id = $1
	`, id, secret)
	return err
}

// EnableTOTP enables TOTP for a user
func (r *UserRepository) EnableTOTP(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.Exec(ctx, `
		UPDATE users SET totp_enabled = true, totp_verified_at = NOW(), updated_at = NOW() WHERE id = $1
	`, id)
	return err
}

// DisableTOTP disables TOTP for a user
func (r *UserRepository) DisableTOTP(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.Exec(ctx, `
		UPDATE users SET totp_enabled = false, totp_secret = NULL, totp_verified_at = NULL, updated_at = NOW() WHERE id = $1
	`, id)
	return err
}

// UpdatePassword updates the user's password
func (r *UserRepository) UpdatePassword(ctx context.Context, id uuid.UUID, passwordHash string) error {
	_, err := r.db.Exec(ctx, `
		UPDATE users SET password_hash = $2, updated_at = NOW() WHERE id = $1
	`, id, passwordHash)
	return err
}

// SetApproved sets the approval status
func (r *UserRepository) SetApproved(ctx context.Context, id uuid.UUID, approved bool) error {
	_, err := r.db.Exec(ctx, `
		UPDATE users SET is_approved = $2, updated_at = NOW() WHERE id = $1
	`, id, approved)
	return err
}

// SetBlocked sets the blocked status
func (r *UserRepository) SetBlocked(ctx context.Context, id uuid.UUID, blocked bool) error {
	_, err := r.db.Exec(ctx, `
		UPDATE users SET is_blocked = $2, updated_at = NOW() WHERE id = $1
	`, id, blocked)
	return err
}

// Delete deletes a user
func (r *UserRepository) Delete(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.Exec(ctx, `DELETE FROM users WHERE id = $1`, id)
	return err
}

// List lists all users (for admin)
func (r *UserRepository) List(ctx context.Context) ([]models.User, error) {
	rows, err := r.db.Query(ctx, `
		SELECT id, email, password_hash, is_approved, is_admin, is_blocked,
		       totp_enabled, created_at, updated_at, last_login_at
		FROM users ORDER BY created_at DESC
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var users []models.User
	for rows.Next() {
		var user models.User
		err := rows.Scan(
			&user.ID, &user.Email, &user.PasswordHash, &user.IsApproved, &user.IsAdmin, &user.IsBlocked,
			&user.TOTPEnabled, &user.CreatedAt, &user.UpdatedAt, &user.LastLoginAt,
		)
		if err != nil {
			return nil, err
		}
		users = append(users, user)
	}

	return users, nil
}

// Count returns user statistics
func (r *UserRepository) Count(ctx context.Context) (total, approved, pending, blocked int, err error) {
	err = r.db.QueryRow(ctx, `SELECT COUNT(*) FROM users`).Scan(&total)
	if err != nil {
		return
	}
	err = r.db.QueryRow(ctx, `SELECT COUNT(*) FROM users WHERE is_approved = true`).Scan(&approved)
	if err != nil {
		return
	}
	err = r.db.QueryRow(ctx, `SELECT COUNT(*) FROM users WHERE is_approved = false AND is_blocked = false`).Scan(&pending)
	if err != nil {
		return
	}
	err = r.db.QueryRow(ctx, `SELECT COUNT(*) FROM users WHERE is_blocked = true`).Scan(&blocked)
	return
}
