package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"github.com/sprobst76/vibedterm-server/internal/middleware"
	"github.com/sprobst76/vibedterm-server/internal/models"
	"github.com/sprobst76/vibedterm-server/internal/repository"
)

// DeviceHandler handles device management endpoints
type DeviceHandler struct {
	deviceRepo  *repository.DeviceRepository
	refreshRepo *repository.RefreshTokenRepository
}

// NewDeviceHandler creates a new device handler
func NewDeviceHandler(
	deviceRepo *repository.DeviceRepository,
	refreshRepo *repository.RefreshTokenRepository,
) *DeviceHandler {
	return &DeviceHandler{
		deviceRepo:  deviceRepo,
		refreshRepo: refreshRepo,
	}
}

// List lists all devices for the current user
func (h *DeviceHandler) List(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	devices, err := h.deviceRepo.GetByUserID(c.Request.Context(), userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list devices"})
		return
	}

	c.JSON(http.StatusOK, models.DeviceListResponse{
		Devices: devices,
	})
}

// Register registers a new device
func (h *DeviceHandler) Register(c *gin.Context) {
	var req models.RegisterDeviceRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request"})
		return
	}

	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	device, err := h.deviceRepo.Create(
		c.Request.Context(),
		userID,
		req.DeviceName,
		req.DeviceType,
		req.DeviceModel,
		req.AppVersion,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to register device"})
		return
	}

	c.JSON(http.StatusCreated, device)
}

// Rename renames a device
func (h *DeviceHandler) Rename(c *gin.Context) {
	deviceIDStr := c.Param("id")
	deviceID, err := uuid.Parse(deviceIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid device ID"})
		return
	}

	var req struct {
		Name string `json:"name" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request"})
		return
	}

	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	// Verify device belongs to user
	device, err := h.deviceRepo.GetByID(c.Request.Context(), deviceID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "device not found"})
		return
	}

	if device.UserID != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "access denied"})
		return
	}

	if err := h.deviceRepo.UpdateName(c.Request.Context(), deviceID, req.Name); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to rename device"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "device renamed"})
}

// Delete removes a device
func (h *DeviceHandler) Delete(c *gin.Context) {
	deviceIDStr := c.Param("id")
	deviceID, err := uuid.Parse(deviceIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid device ID"})
		return
	}

	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	// Verify device belongs to user
	device, err := h.deviceRepo.GetByID(c.Request.Context(), deviceID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "device not found"})
		return
	}

	if device.UserID != userID {
		c.JSON(http.StatusForbidden, gin.H{"error": "access denied"})
		return
	}

	// Revoke all refresh tokens for this device
	_ = h.refreshRepo.RevokeAllForDevice(c.Request.Context(), deviceID)

	// Delete device
	if err := h.deviceRepo.Delete(c.Request.Context(), deviceID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete device"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "device deleted"})
}

// GetCurrent returns the current device info
func (h *DeviceHandler) GetCurrent(c *gin.Context) {
	deviceID, err := middleware.GetDeviceID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "no device context"})
		return
	}

	device, err := h.deviceRepo.GetByID(c.Request.Context(), deviceID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "device not found"})
		return
	}

	c.JSON(http.StatusOK, device)
}
