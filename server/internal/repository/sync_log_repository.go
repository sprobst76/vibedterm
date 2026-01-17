package repository

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/sprobst76/vibedterm-server/internal/models"
)

// SyncLogRepository handles sync log database operations
type SyncLogRepository struct {
	db *pgxpool.Pool
}

// NewSyncLogRepository creates a new sync log repository
func NewSyncLogRepository(db *pgxpool.Pool) *SyncLogRepository {
	return &SyncLogRepository{db: db}
}

// Create creates a new sync log entry
func (r *SyncLogRepository) Create(ctx context.Context, userID uuid.UUID, deviceID *uuid.UUID, action string, revisionBefore, revisionAfter *int) error {
	log := &models.SyncLog{
		ID:             uuid.New(),
		UserID:         userID,
		DeviceID:       deviceID,
		Action:         action,
		RevisionBefore: revisionBefore,
		RevisionAfter:  revisionAfter,
		CreatedAt:      time.Now(),
	}

	_, err := r.db.Exec(ctx, `
		INSERT INTO sync_logs (id, user_id, device_id, action, revision_before, revision_after, created_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
	`, log.ID, log.UserID, log.DeviceID, log.Action, log.RevisionBefore, log.RevisionAfter, log.CreatedAt)

	return err
}

// GetByUserID retrieves sync logs for a user
func (r *SyncLogRepository) GetByUserID(ctx context.Context, userID uuid.UUID, limit int) ([]models.SyncLog, error) {
	rows, err := r.db.Query(ctx, `
		SELECT id, user_id, device_id, action, revision_before, revision_after, created_at
		FROM sync_logs WHERE user_id = $1 ORDER BY created_at DESC LIMIT $2
	`, userID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var logs []models.SyncLog
	for rows.Next() {
		var log models.SyncLog
		err := rows.Scan(&log.ID, &log.UserID, &log.DeviceID, &log.Action, &log.RevisionBefore, &log.RevisionAfter, &log.CreatedAt)
		if err != nil {
			return nil, err
		}
		logs = append(logs, log)
	}

	return logs, nil
}

// DeleteOld deletes logs older than the specified duration
func (r *SyncLogRepository) DeleteOld(ctx context.Context, olderThan time.Duration) (int64, error) {
	result, err := r.db.Exec(ctx, `
		DELETE FROM sync_logs WHERE created_at < $1
	`, time.Now().Add(-olderThan))
	if err != nil {
		return 0, err
	}
	return result.RowsAffected(), nil
}

// Count returns total sync log count
func (r *SyncLogRepository) Count(ctx context.Context) (int, error) {
	var count int
	err := r.db.QueryRow(ctx, `SELECT COUNT(*) FROM sync_logs`).Scan(&count)
	return count, err
}
