package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"github.com/sprobst76/vibedterm-server/internal/repository"
)

// AdminHandler handles admin endpoints
type AdminHandler struct {
	userRepo    *repository.UserRepository
	deviceRepo  *repository.DeviceRepository
	vaultRepo   *repository.VaultRepository
	refreshRepo *repository.RefreshTokenRepository
}

// NewAdminHandler creates a new admin handler
func NewAdminHandler(
	userRepo *repository.UserRepository,
	deviceRepo *repository.DeviceRepository,
	vaultRepo *repository.VaultRepository,
	refreshRepo *repository.RefreshTokenRepository,
) *AdminHandler {
	return &AdminHandler{
		userRepo:    userRepo,
		deviceRepo:  deviceRepo,
		vaultRepo:   vaultRepo,
		refreshRepo: refreshRepo,
	}
}

// Dashboard returns admin dashboard statistics
func (h *AdminHandler) Dashboard(c *gin.Context) {
	ctx := c.Request.Context()

	total, approved, pending, blocked, err := h.userRepo.Count(ctx)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get user stats"})
		return
	}

	deviceCount, _ := h.deviceRepo.Count(ctx)
	vaultCount, _ := h.vaultRepo.Count(ctx)

	c.JSON(http.StatusOK, gin.H{
		"users": gin.H{
			"total":    total,
			"approved": approved,
			"pending":  pending,
			"blocked":  blocked,
		},
		"devices": deviceCount,
		"vaults":  vaultCount,
	})
}

// ListUsers returns all users
func (h *AdminHandler) ListUsers(c *gin.Context) {
	users, err := h.userRepo.List(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to list users"})
		return
	}

	// Strip sensitive data
	type userResponse struct {
		ID          uuid.UUID  `json:"id"`
		Email       string     `json:"email"`
		IsApproved  bool       `json:"is_approved"`
		IsAdmin     bool       `json:"is_admin"`
		IsBlocked   bool       `json:"is_blocked"`
		TOTPEnabled bool       `json:"totp_enabled"`
		CreatedAt   string     `json:"created_at"`
		LastLoginAt *string    `json:"last_login_at,omitempty"`
	}

	response := make([]userResponse, len(users))
	for i, u := range users {
		var lastLogin *string
		if u.LastLoginAt != nil {
			s := u.LastLoginAt.Format("2006-01-02T15:04:05Z")
			lastLogin = &s
		}
		response[i] = userResponse{
			ID:          u.ID,
			Email:       u.Email,
			IsApproved:  u.IsApproved,
			IsAdmin:     u.IsAdmin,
			IsBlocked:   u.IsBlocked,
			TOTPEnabled: u.TOTPEnabled,
			CreatedAt:   u.CreatedAt.Format("2006-01-02T15:04:05Z"),
			LastLoginAt: lastLogin,
		}
	}

	c.JSON(http.StatusOK, gin.H{"users": response})
}

// ApproveUser approves a user
func (h *AdminHandler) ApproveUser(c *gin.Context) {
	userIDStr := c.Param("id")
	userID, err := uuid.Parse(userIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid user ID"})
		return
	}

	if err := h.userRepo.SetApproved(c.Request.Context(), userID, true); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to approve user"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "user approved"})
}

// BlockUser blocks or unblocks a user
func (h *AdminHandler) BlockUser(c *gin.Context) {
	userIDStr := c.Param("id")
	userID, err := uuid.Parse(userIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid user ID"})
		return
	}

	var req struct {
		Blocked bool `json:"blocked"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request"})
		return
	}

	if err := h.userRepo.SetBlocked(c.Request.Context(), userID, req.Blocked); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update user"})
		return
	}

	// Revoke all tokens if blocking
	if req.Blocked {
		_ = h.refreshRepo.RevokeAllForUser(c.Request.Context(), userID)
	}

	action := "unblocked"
	if req.Blocked {
		action = "blocked"
	}
	c.JSON(http.StatusOK, gin.H{"message": "user " + action})
}

// DeleteUser deletes a user and all their data
func (h *AdminHandler) DeleteUser(c *gin.Context) {
	userIDStr := c.Param("id")
	userID, err := uuid.Parse(userIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid user ID"})
		return
	}

	var req struct {
		Confirm bool `json:"confirm"`
	}
	if err := c.ShouldBindJSON(&req); err != nil || !req.Confirm {
		c.JSON(http.StatusBadRequest, gin.H{"error": "confirmation required"})
		return
	}

	// Delete user (cascade deletes devices, vault, tokens, etc.)
	if err := h.userRepo.Delete(c.Request.Context(), userID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to delete user"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "user deleted"})
}

// GetUserDevices returns devices for a specific user
func (h *AdminHandler) GetUserDevices(c *gin.Context) {
	userIDStr := c.Param("id")
	userID, err := uuid.Parse(userIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid user ID"})
		return
	}

	devices, err := h.deviceRepo.GetByUserID(c.Request.Context(), userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to get devices"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"devices": devices})
}
