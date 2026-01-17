package models

import (
	"time"

	"github.com/google/uuid"
)

// User represents a registered user
type User struct {
	ID           uuid.UUID  `json:"id"`
	Email        string     `json:"email"`
	PasswordHash string     `json:"-"`
	IsApproved   bool       `json:"is_approved"`
	IsAdmin      bool       `json:"is_admin"`
	IsBlocked    bool       `json:"is_blocked"`
	TOTPSecret   []byte     `json:"-"`
	TOTPEnabled  bool       `json:"totp_enabled"`
	TOTPVerified *time.Time `json:"-"`
	CreatedAt    time.Time  `json:"created_at"`
	UpdatedAt    time.Time  `json:"updated_at"`
	LastLoginAt  *time.Time `json:"last_login_at,omitempty"`
}

// Device represents a registered app instance
type Device struct {
	ID          uuid.UUID  `json:"id"`
	UserID      uuid.UUID  `json:"user_id"`
	DeviceName  string     `json:"device_name"`
	DeviceType  string     `json:"device_type"`
	DeviceModel string     `json:"device_model,omitempty"`
	AppVersion  string     `json:"app_version,omitempty"`
	LastSyncAt  *time.Time `json:"last_sync_at,omitempty"`
	CreatedAt   time.Time  `json:"created_at"`
	UpdatedAt   time.Time  `json:"updated_at"`
}

// EncryptedVault represents the user's encrypted vault blob
type EncryptedVault struct {
	ID              uuid.UUID  `json:"id"`
	UserID          uuid.UUID  `json:"user_id"`
	VaultBlob       []byte     `json:"vault_blob"`
	Revision        int        `json:"revision"`
	VaultVersion    int        `json:"vault_version"`
	UpdatedByDevice *uuid.UUID `json:"updated_by_device,omitempty"`
	UpdatedAt       time.Time  `json:"updated_at"`
	CreatedAt       time.Time  `json:"created_at"`
}

// RefreshToken for JWT refresh
type RefreshToken struct {
	ID        uuid.UUID `json:"id"`
	UserID    uuid.UUID `json:"user_id"`
	DeviceID  uuid.UUID `json:"device_id"`
	TokenHash string    `json:"-"`
	ExpiresAt time.Time `json:"expires_at"`
	Revoked   bool      `json:"revoked"`
	CreatedAt time.Time `json:"created_at"`
}

// RecoveryCode for 2FA recovery
type RecoveryCode struct {
	ID        uuid.UUID  `json:"id"`
	UserID    uuid.UUID  `json:"user_id"`
	CodeHash  string     `json:"-"`
	Used      bool       `json:"used"`
	UsedAt    *time.Time `json:"used_at,omitempty"`
	CreatedAt time.Time  `json:"created_at"`
}

// SyncLog for audit trail
type SyncLog struct {
	ID             uuid.UUID  `json:"id"`
	UserID         uuid.UUID  `json:"user_id"`
	DeviceID       *uuid.UUID `json:"device_id,omitempty"`
	Action         string     `json:"action"`
	RevisionBefore *int       `json:"revision_before,omitempty"`
	RevisionAfter  *int       `json:"revision_after,omitempty"`
	CreatedAt      time.Time  `json:"created_at"`
}

// --- Request/Response Types ---

// RegisterRequest for user registration
type RegisterRequest struct {
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required,min=8"`
}

// LoginRequest for user login
type LoginRequest struct {
	Email      string `json:"email" binding:"required,email"`
	Password   string `json:"password" binding:"required"`
	DeviceName string `json:"device_name" binding:"required"`
	DeviceType string `json:"device_type" binding:"required"`
}

// LoginResponse on successful login
type LoginResponse struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	ExpiresIn    int64  `json:"expires_in"`
	User         User   `json:"user"`
	DeviceID     string `json:"device_id"`
}

// LoginTOTPResponse when TOTP is required
type LoginTOTPResponse struct {
	RequiresTOTP bool   `json:"requires_totp"`
	TempToken    string `json:"temp_token"`
}

// TOTPValidateRequest for TOTP validation during login
type TOTPValidateRequest struct {
	TempToken string `json:"temp_token" binding:"required"`
	Code      string `json:"code" binding:"required,len=6"`
}

// RefreshRequest for token refresh
type RefreshRequest struct {
	RefreshToken string `json:"refresh_token" binding:"required"`
}

// RefreshResponse on successful refresh
type RefreshResponse struct {
	AccessToken string `json:"access_token"`
	ExpiresIn   int64  `json:"expires_in"`
}

// TOTPSetupResponse for TOTP setup
type TOTPSetupResponse struct {
	Secret    string `json:"secret"`
	QRCodeURL string `json:"qr_code_url"`
	Issuer    string `json:"issuer"`
}

// TOTPVerifyRequest for verifying TOTP setup
type TOTPVerifyRequest struct {
	Code string `json:"code" binding:"required,len=6"`
}

// TOTPDisableRequest for disabling TOTP
type TOTPDisableRequest struct {
	Code     string `json:"code" binding:"required,len=6"`
	Password string `json:"password" binding:"required"`
}

// RecoveryCodesResponse returns recovery codes
type RecoveryCodesResponse struct {
	Codes []string `json:"codes"`
}

// RecoveryValidateRequest for recovery code login
type RecoveryValidateRequest struct {
	TempToken string `json:"temp_token" binding:"required"`
	Code      string `json:"code" binding:"required"`
}

// VaultPushRequest for uploading vault
type VaultPushRequest struct {
	VaultBlob string `json:"vault_blob" binding:"required"` // Base64
	Revision  int    `json:"revision"`                      // 0 is valid for initial push
	DeviceID  string `json:"device_id" binding:"required"`
}

// VaultPushResponse on successful push
type VaultPushResponse struct {
	Status    string `json:"status"`
	Revision  int    `json:"revision"`
	Timestamp int64  `json:"timestamp"`
}

// VaultPullResponse for downloading vault
type VaultPullResponse struct {
	VaultBlob       string `json:"vault_blob"` // Base64
	Revision        int    `json:"revision"`
	UpdatedAt       int64  `json:"updated_at"`
	UpdatedByDevice string `json:"updated_by_device,omitempty"`
}

// VaultStatusResponse for sync status
type VaultStatusResponse struct {
	HasVault  bool  `json:"has_vault"`
	Revision  int   `json:"revision"`
	UpdatedAt int64 `json:"updated_at"`
}

// VaultConflictResponse when conflict detected
type VaultConflictResponse struct {
	Error          string `json:"error"`
	Code           string `json:"code"`
	LocalRevision  int    `json:"local_revision"`
	ServerRevision int    `json:"server_revision"`
	ServerDeviceID string `json:"server_device_id"`
	ServerUpdated  int64  `json:"server_updated_at"`
}

// DeviceListResponse for listing devices
type DeviceListResponse struct {
	Devices []Device `json:"devices"`
}

// RegisterDeviceRequest for registering a device
type RegisterDeviceRequest struct {
	DeviceName  string `json:"device_name" binding:"required"`
	DeviceType  string `json:"device_type" binding:"required"`
	DeviceModel string `json:"device_model,omitempty"`
	AppVersion  string `json:"app_version,omitempty"`
}

// ErrorResponse for API errors
type ErrorResponse struct {
	Error   string `json:"error"`
	Code    string `json:"code,omitempty"`
	Details string `json:"details,omitempty"`
}

// MessageResponse for simple messages
type MessageResponse struct {
	Message string `json:"message"`
}
