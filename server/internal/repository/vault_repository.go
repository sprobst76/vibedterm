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

var ErrVaultNotFound = errors.New("vault not found")

// VaultRepository handles vault database operations
type VaultRepository struct {
	db *pgxpool.Pool
}

// NewVaultRepository creates a new vault repository
func NewVaultRepository(db *pgxpool.Pool) *VaultRepository {
	return &VaultRepository{db: db}
}

// Create creates a new vault
func (r *VaultRepository) Create(ctx context.Context, userID uuid.UUID, vaultBlob []byte, deviceID *uuid.UUID) (*models.EncryptedVault, error) {
	vault := &models.EncryptedVault{
		ID:              uuid.New(),
		UserID:          userID,
		VaultBlob:       vaultBlob,
		Revision:        1,
		VaultVersion:    1,
		UpdatedByDevice: deviceID,
		CreatedAt:       time.Now(),
		UpdatedAt:       time.Now(),
	}

	_, err := r.db.Exec(ctx, `
		INSERT INTO encrypted_vaults (id, user_id, vault_blob, revision, vault_version, updated_by_device, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
	`, vault.ID, vault.UserID, vault.VaultBlob, vault.Revision, vault.VaultVersion, vault.UpdatedByDevice, vault.CreatedAt, vault.UpdatedAt)

	if err != nil {
		return nil, err
	}

	return vault, nil
}

// GetByUserID retrieves a vault by user ID
func (r *VaultRepository) GetByUserID(ctx context.Context, userID uuid.UUID) (*models.EncryptedVault, error) {
	vault := &models.EncryptedVault{}
	err := r.db.QueryRow(ctx, `
		SELECT id, user_id, vault_blob, revision, vault_version, updated_by_device, created_at, updated_at
		FROM encrypted_vaults WHERE user_id = $1
	`, userID).Scan(
		&vault.ID, &vault.UserID, &vault.VaultBlob, &vault.Revision, &vault.VaultVersion,
		&vault.UpdatedByDevice, &vault.CreatedAt, &vault.UpdatedAt,
	)

	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrVaultNotFound
	}
	if err != nil {
		return nil, err
	}

	return vault, nil
}

// Update updates the vault blob and revision
func (r *VaultRepository) Update(ctx context.Context, userID uuid.UUID, vaultBlob []byte, revision int, deviceID *uuid.UUID) (*models.EncryptedVault, error) {
	vault := &models.EncryptedVault{}
	err := r.db.QueryRow(ctx, `
		UPDATE encrypted_vaults
		SET vault_blob = $2, revision = $3, updated_by_device = $4, updated_at = NOW()
		WHERE user_id = $1
		RETURNING id, user_id, vault_blob, revision, vault_version, updated_by_device, created_at, updated_at
	`, userID, vaultBlob, revision, deviceID).Scan(
		&vault.ID, &vault.UserID, &vault.VaultBlob, &vault.Revision, &vault.VaultVersion,
		&vault.UpdatedByDevice, &vault.CreatedAt, &vault.UpdatedAt,
	)

	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrVaultNotFound
	}
	if err != nil {
		return nil, err
	}

	return vault, nil
}

// UpdateWithRevisionCheck updates only if revision matches (optimistic locking)
func (r *VaultRepository) UpdateWithRevisionCheck(ctx context.Context, userID uuid.UUID, vaultBlob []byte, expectedRevision int, deviceID *uuid.UUID) (*models.EncryptedVault, error) {
	vault := &models.EncryptedVault{}
	err := r.db.QueryRow(ctx, `
		UPDATE encrypted_vaults
		SET vault_blob = $2, revision = revision + 1, updated_by_device = $4, updated_at = NOW()
		WHERE user_id = $1 AND revision = $3
		RETURNING id, user_id, vault_blob, revision, vault_version, updated_by_device, created_at, updated_at
	`, userID, vaultBlob, expectedRevision, deviceID).Scan(
		&vault.ID, &vault.UserID, &vault.VaultBlob, &vault.Revision, &vault.VaultVersion,
		&vault.UpdatedByDevice, &vault.CreatedAt, &vault.UpdatedAt,
	)

	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrVaultNotFound
	}
	if err != nil {
		return nil, err
	}

	return vault, nil
}

// Delete deletes a vault
func (r *VaultRepository) Delete(ctx context.Context, userID uuid.UUID) error {
	_, err := r.db.Exec(ctx, `DELETE FROM encrypted_vaults WHERE user_id = $1`, userID)
	return err
}

// Count returns vault statistics
func (r *VaultRepository) Count(ctx context.Context) (int, error) {
	var count int
	err := r.db.QueryRow(ctx, `SELECT COUNT(*) FROM encrypted_vaults`).Scan(&count)
	return count, err
}
