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

var ErrDeviceNotFound = errors.New("device not found")

// DeviceRepository handles device database operations
type DeviceRepository struct {
	db *pgxpool.Pool
}

// NewDeviceRepository creates a new device repository
func NewDeviceRepository(db *pgxpool.Pool) *DeviceRepository {
	return &DeviceRepository{db: db}
}

// Create creates a new device
func (r *DeviceRepository) Create(ctx context.Context, userID uuid.UUID, name, deviceType, model, appVersion string) (*models.Device, error) {
	device := &models.Device{
		ID:          uuid.New(),
		UserID:      userID,
		DeviceName:  name,
		DeviceType:  deviceType,
		DeviceModel: model,
		AppVersion:  appVersion,
		CreatedAt:   time.Now(),
		UpdatedAt:   time.Now(),
	}

	_, err := r.db.Exec(ctx, `
		INSERT INTO devices (id, user_id, device_name, device_type, device_model, app_version, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
		ON CONFLICT (user_id, device_name) DO UPDATE SET
			device_type = EXCLUDED.device_type,
			device_model = EXCLUDED.device_model,
			app_version = EXCLUDED.app_version,
			updated_at = NOW()
		RETURNING id
	`, device.ID, device.UserID, device.DeviceName, device.DeviceType, device.DeviceModel, device.AppVersion, device.CreatedAt, device.UpdatedAt)

	if err != nil {
		return nil, err
	}

	return device, nil
}

// GetByID retrieves a device by ID
func (r *DeviceRepository) GetByID(ctx context.Context, id uuid.UUID) (*models.Device, error) {
	device := &models.Device{}
	err := r.db.QueryRow(ctx, `
		SELECT id, user_id, device_name, device_type, device_model, app_version, last_sync_at, created_at, updated_at
		FROM devices WHERE id = $1
	`, id).Scan(
		&device.ID, &device.UserID, &device.DeviceName, &device.DeviceType, &device.DeviceModel,
		&device.AppVersion, &device.LastSyncAt, &device.CreatedAt, &device.UpdatedAt,
	)

	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrDeviceNotFound
	}
	if err != nil {
		return nil, err
	}

	return device, nil
}

// GetByUserID retrieves all devices for a user
func (r *DeviceRepository) GetByUserID(ctx context.Context, userID uuid.UUID) ([]models.Device, error) {
	rows, err := r.db.Query(ctx, `
		SELECT id, user_id, device_name, device_type, device_model, app_version, last_sync_at, created_at, updated_at
		FROM devices WHERE user_id = $1 ORDER BY last_sync_at DESC NULLS LAST
	`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var devices []models.Device
	for rows.Next() {
		var device models.Device
		err := rows.Scan(
			&device.ID, &device.UserID, &device.DeviceName, &device.DeviceType, &device.DeviceModel,
			&device.AppVersion, &device.LastSyncAt, &device.CreatedAt, &device.UpdatedAt,
		)
		if err != nil {
			return nil, err
		}
		devices = append(devices, device)
	}

	return devices, nil
}

// UpdateLastSync updates the last sync timestamp
func (r *DeviceRepository) UpdateLastSync(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.Exec(ctx, `
		UPDATE devices SET last_sync_at = NOW(), updated_at = NOW() WHERE id = $1
	`, id)
	return err
}

// UpdateName updates the device name
func (r *DeviceRepository) UpdateName(ctx context.Context, id uuid.UUID, name string) error {
	_, err := r.db.Exec(ctx, `
		UPDATE devices SET device_name = $2, updated_at = NOW() WHERE id = $1
	`, id, name)
	return err
}

// Delete deletes a device
func (r *DeviceRepository) Delete(ctx context.Context, id uuid.UUID) error {
	result, err := r.db.Exec(ctx, `DELETE FROM devices WHERE id = $1`, id)
	if err != nil {
		return err
	}
	if result.RowsAffected() == 0 {
		return ErrDeviceNotFound
	}
	return nil
}

// Count returns the total number of devices
func (r *DeviceRepository) Count(ctx context.Context) (int, error) {
	var count int
	err := r.db.QueryRow(ctx, `SELECT COUNT(*) FROM devices`).Scan(&count)
	return count, err
}
