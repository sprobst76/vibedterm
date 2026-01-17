package handlers

import (
	"encoding/base64"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"github.com/sprobst76/vibedterm-server/internal/middleware"
	"github.com/sprobst76/vibedterm-server/internal/models"
	"github.com/sprobst76/vibedterm-server/internal/repository"
)

// VaultHandler handles vault sync endpoints
type VaultHandler struct {
	vaultRepo  *repository.VaultRepository
	deviceRepo *repository.DeviceRepository
	syncRepo   *repository.SyncLogRepository
}

// NewVaultHandler creates a new vault handler
func NewVaultHandler(
	vaultRepo *repository.VaultRepository,
	deviceRepo *repository.DeviceRepository,
	syncRepo *repository.SyncLogRepository,
) *VaultHandler {
	return &VaultHandler{
		vaultRepo:  vaultRepo,
		deviceRepo: deviceRepo,
		syncRepo:   syncRepo,
	}
}

// Status returns the current vault status
func (h *VaultHandler) Status(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	vault, err := h.vaultRepo.GetByUserID(c.Request.Context(), userID)
	if err != nil {
		if err == repository.ErrVaultNotFound {
			c.JSON(http.StatusOK, models.VaultStatusResponse{
				HasVault:  false,
				Revision:  0,
				UpdatedAt: 0,
			})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get vault status"})
		return
	}

	c.JSON(http.StatusOK, models.VaultStatusResponse{
		HasVault:  true,
		Revision:  vault.Revision,
		UpdatedAt: vault.UpdatedAt.Unix(),
	})
}

// Pull downloads the encrypted vault
func (h *VaultHandler) Pull(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	deviceID, _ := middleware.GetDeviceID(c)

	vault, err := h.vaultRepo.GetByUserID(c.Request.Context(), userID)
	if err != nil {
		if err == repository.ErrVaultNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "no vault found", "code": "NO_VAULT"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get vault"})
		return
	}

	// Log sync
	_ = h.syncRepo.Create(c.Request.Context(), userID, &deviceID, "pull", &vault.Revision, nil)

	// Update device last sync
	_ = h.deviceRepo.UpdateLastSync(c.Request.Context(), deviceID)

	var updatedByDevice string
	if vault.UpdatedByDevice != nil {
		updatedByDevice = vault.UpdatedByDevice.String()
	}

	c.JSON(http.StatusOK, models.VaultPullResponse{
		VaultBlob:       base64.StdEncoding.EncodeToString(vault.VaultBlob),
		Revision:        vault.Revision,
		UpdatedAt:       vault.UpdatedAt.Unix(),
		UpdatedByDevice: updatedByDevice,
	})
}

// Push uploads the encrypted vault
func (h *VaultHandler) Push(c *gin.Context) {
	var req models.VaultPushRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request", "details": err.Error()})
		return
	}

	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	deviceID, _ := middleware.GetDeviceID(c)

	// Decode vault blob
	vaultBlob, err := base64.StdEncoding.DecodeString(req.VaultBlob)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid vault blob encoding"})
		return
	}

	ctx := c.Request.Context()

	// Check current vault state
	currentVault, err := h.vaultRepo.GetByUserID(ctx, userID)
	if err != nil && err != repository.ErrVaultNotFound {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to check vault"})
		return
	}

	// Handle first vault creation
	if currentVault == nil {
		vault, err := h.vaultRepo.Create(ctx, userID, vaultBlob, &deviceID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create vault"})
			return
		}

		_ = h.syncRepo.Create(ctx, userID, &deviceID, "push_initial", nil, &vault.Revision)
		_ = h.deviceRepo.UpdateLastSync(ctx, deviceID)

		c.JSON(http.StatusOK, models.VaultPushResponse{
			Status:    "created",
			Revision:  vault.Revision,
			Timestamp: vault.UpdatedAt.Unix(),
		})
		return
	}

	// Check for conflicts
	if req.Revision != currentVault.Revision {
		var serverDeviceID string
		if currentVault.UpdatedByDevice != nil {
			serverDeviceID = currentVault.UpdatedByDevice.String()
		}

		c.JSON(http.StatusConflict, models.VaultConflictResponse{
			Error:          "revision mismatch",
			Code:           "CONFLICT",
			LocalRevision:  req.Revision,
			ServerRevision: currentVault.Revision,
			ServerDeviceID: serverDeviceID,
			ServerUpdated:  currentVault.UpdatedAt.Unix(),
		})
		return
	}

	// Update vault
	oldRevision := currentVault.Revision
	vault, err := h.vaultRepo.Update(ctx, userID, vaultBlob, currentVault.Revision+1, &deviceID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update vault"})
		return
	}

	_ = h.syncRepo.Create(ctx, userID, &deviceID, "push", &oldRevision, &vault.Revision)
	_ = h.deviceRepo.UpdateLastSync(ctx, deviceID)

	c.JSON(http.StatusOK, models.VaultPushResponse{
		Status:    "updated",
		Revision:  vault.Revision,
		Timestamp: vault.UpdatedAt.Unix(),
	})
}

// ForceOverwrite overwrites the vault ignoring revision (requires confirmation)
func (h *VaultHandler) ForceOverwrite(c *gin.Context) {
	var req struct {
		VaultBlob string `json:"vault_blob" binding:"required"`
		DeviceID  string `json:"device_id" binding:"required"`
		Confirm   bool   `json:"confirm" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request"})
		return
	}

	if !req.Confirm {
		c.JSON(http.StatusBadRequest, gin.H{"error": "confirmation required"})
		return
	}

	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	deviceID, _ := uuid.Parse(req.DeviceID)

	vaultBlob, err := base64.StdEncoding.DecodeString(req.VaultBlob)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid vault blob encoding"})
		return
	}

	ctx := c.Request.Context()

	// Get current revision for logging
	currentVault, _ := h.vaultRepo.GetByUserID(ctx, userID)
	var oldRevision *int
	if currentVault != nil {
		oldRevision = &currentVault.Revision
	}

	// Delete and recreate
	_ = h.vaultRepo.Delete(ctx, userID)

	vault, err := h.vaultRepo.Create(ctx, userID, vaultBlob, &deviceID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to overwrite vault"})
		return
	}

	_ = h.syncRepo.Create(ctx, userID, &deviceID, "force_overwrite", oldRevision, &vault.Revision)
	_ = h.deviceRepo.UpdateLastSync(ctx, deviceID)

	c.JSON(http.StatusOK, models.VaultPushResponse{
		Status:    "overwritten",
		Revision:  vault.Revision,
		Timestamp: vault.UpdatedAt.Unix(),
	})
}

// History returns sync history
func (h *VaultHandler) History(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	logs, err := h.syncRepo.GetByUserID(c.Request.Context(), userID, 50)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get history"})
		return
	}

	type historyEntry struct {
		Action    string    `json:"action"`
		DeviceID  *string   `json:"device_id,omitempty"`
		Revision  *int      `json:"revision,omitempty"`
		Timestamp time.Time `json:"timestamp"`
	}

	entries := make([]historyEntry, len(logs))
	for i, log := range logs {
		var deviceID *string
		if log.DeviceID != nil {
			id := log.DeviceID.String()
			deviceID = &id
		}
		entries[i] = historyEntry{
			Action:    log.Action,
			DeviceID:  deviceID,
			Revision:  log.RevisionAfter,
			Timestamp: log.CreatedAt,
		}
	}

	c.JSON(http.StatusOK, gin.H{"history": entries})
}
