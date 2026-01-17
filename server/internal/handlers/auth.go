package handlers

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base32"
	"encoding/hex"
	"errors"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/pquerna/otp/totp"
	"golang.org/x/crypto/bcrypt"

	"github.com/sprobst76/vibedterm-server/internal/config"
	"github.com/sprobst76/vibedterm-server/internal/middleware"
	"github.com/sprobst76/vibedterm-server/internal/models"
	"github.com/sprobst76/vibedterm-server/internal/repository"
)

// AuthHandler handles authentication endpoints
type AuthHandler struct {
	userRepo    *repository.UserRepository
	deviceRepo  *repository.DeviceRepository
	refreshRepo *repository.RefreshTokenRepository
	config      *config.Config
}

// NewAuthHandler creates a new auth handler
func NewAuthHandler(
	userRepo *repository.UserRepository,
	deviceRepo *repository.DeviceRepository,
	refreshRepo *repository.RefreshTokenRepository,
	cfg *config.Config,
) *AuthHandler {
	return &AuthHandler{
		userRepo:    userRepo,
		deviceRepo:  deviceRepo,
		refreshRepo: refreshRepo,
		config:      cfg,
	}
}

// Register handles user registration
func (h *AuthHandler) Register(c *gin.Context) {
	var req models.RegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request", "details": err.Error()})
		return
	}

	// Hash password
	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to process password"})
		return
	}

	// Create user
	user, err := h.userRepo.Create(c.Request.Context(), req.Email, string(hashedPassword))
	if err != nil {
		if errors.Is(err, repository.ErrUserAlreadyExists) {
			c.JSON(http.StatusConflict, gin.H{"error": "email already registered"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create user"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"message": "registration successful, awaiting admin approval",
		"user_id": user.ID,
	})
}

// Login handles user login
func (h *AuthHandler) Login(c *gin.Context) {
	var req models.LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request", "details": err.Error()})
		return
	}

	// Get user
	user, err := h.userRepo.GetByEmail(c.Request.Context(), req.Email)
	if err != nil {
		if errors.Is(err, repository.ErrUserNotFound) {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid credentials"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to authenticate"})
		return
	}

	// Check password
	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.Password)); err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid credentials"})
		return
	}

	// Check if blocked
	if user.IsBlocked {
		c.JSON(http.StatusForbidden, gin.H{"error": "account blocked", "code": "ACCOUNT_BLOCKED"})
		return
	}

	// Check if approved
	if !user.IsApproved {
		c.JSON(http.StatusForbidden, gin.H{"error": "account pending approval", "code": "PENDING_APPROVAL"})
		return
	}

	// Check if TOTP is required
	if user.TOTPEnabled {
		// Generate temporary token for TOTP validation
		tempToken, err := h.generateTempToken(user.ID, req.DeviceName, req.DeviceType)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate temp token"})
			return
		}
		c.JSON(http.StatusOK, models.LoginTOTPResponse{
			RequiresTOTP: true,
			TempToken:    tempToken,
		})
		return
	}

	// Complete login
	h.completeLogin(c, user, req.DeviceName, req.DeviceType)
}

// ValidateTOTP handles TOTP validation during login
func (h *AuthHandler) ValidateTOTP(c *gin.Context) {
	var req models.TOTPValidateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request"})
		return
	}

	// Parse temp token
	userID, deviceName, deviceType, err := h.parseTempToken(req.TempToken)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid or expired token"})
		return
	}

	// Get user
	user, err := h.userRepo.GetByID(c.Request.Context(), userID)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user not found"})
		return
	}

	// Validate TOTP
	if !totp.Validate(req.Code, base32.StdEncoding.EncodeToString(user.TOTPSecret)) {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid TOTP code"})
		return
	}

	// Complete login
	h.completeLogin(c, user, deviceName, deviceType)
}

// Refresh handles token refresh
func (h *AuthHandler) Refresh(c *gin.Context) {
	var req models.RefreshRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request"})
		return
	}

	// Hash the refresh token
	tokenHash := hashToken(req.RefreshToken)

	// Find and validate refresh token
	refreshToken, err := h.refreshRepo.GetByTokenHash(c.Request.Context(), tokenHash)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid refresh token"})
		return
	}

	if refreshToken.Revoked {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "refresh token revoked"})
		return
	}

	if time.Now().After(refreshToken.ExpiresAt) {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "refresh token expired"})
		return
	}

	// Get user
	user, err := h.userRepo.GetByID(c.Request.Context(), refreshToken.UserID)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "user not found"})
		return
	}

	// Check if user is still valid
	if user.IsBlocked || !user.IsApproved {
		c.JSON(http.StatusForbidden, gin.H{"error": "account no longer active"})
		return
	}

	// Generate new access token
	accessToken, err := middleware.GenerateToken(
		user.ID,
		user.Email,
		refreshToken.DeviceID,
		user.IsAdmin,
		h.config.JWTSecret,
		h.config.AccessTokenDuration,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate token"})
		return
	}

	c.JSON(http.StatusOK, models.RefreshResponse{
		AccessToken: accessToken,
		ExpiresIn:   int64(h.config.AccessTokenDuration.Seconds()),
	})
}

// Logout revokes refresh token
func (h *AuthHandler) Logout(c *gin.Context) {
	var req models.RefreshRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request"})
		return
	}

	tokenHash := hashToken(req.RefreshToken)
	_ = h.refreshRepo.Revoke(c.Request.Context(), tokenHash)

	c.JSON(http.StatusOK, gin.H{"message": "logged out successfully"})
}

// LogoutAll revokes all refresh tokens for user
func (h *AuthHandler) LogoutAll(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	_ = h.refreshRepo.RevokeAllForUser(c.Request.Context(), userID)
	c.JSON(http.StatusOK, gin.H{"message": "all sessions logged out"})
}

// completeLogin generates tokens and responds
func (h *AuthHandler) completeLogin(c *gin.Context, user *models.User, deviceName, deviceType string) {
	ctx := c.Request.Context()

	// Create or update device
	device, err := h.deviceRepo.Create(ctx, user.ID, deviceName, deviceType, "", "")
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to register device"})
		return
	}

	// Generate access token
	accessToken, err := middleware.GenerateToken(
		user.ID,
		user.Email,
		device.ID,
		user.IsAdmin,
		h.config.JWTSecret,
		h.config.AccessTokenDuration,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate access token"})
		return
	}

	// Generate refresh token
	refreshTokenStr := generateSecureToken()
	refreshTokenHash := hashToken(refreshTokenStr)

	_, err = h.refreshRepo.Create(
		ctx,
		user.ID,
		device.ID,
		refreshTokenHash,
		time.Now().Add(h.config.RefreshTokenDuration),
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate refresh token"})
		return
	}

	// Update last login
	_ = h.userRepo.UpdateLastLogin(ctx, user.ID)

	c.JSON(http.StatusOK, models.LoginResponse{
		AccessToken:  accessToken,
		RefreshToken: refreshTokenStr,
		ExpiresIn:    int64(h.config.AccessTokenDuration.Seconds()),
		User:         *user,
		DeviceID:     device.ID.String(),
	})
}

// generateTempToken creates a temporary token for TOTP flow
func (h *AuthHandler) generateTempToken(userID uuid.UUID, deviceName, deviceType string) (string, error) {
	// Simple approach: JWT with short expiry
	return middleware.GenerateToken(
		userID,
		deviceName+"|"+deviceType, // Store device info in email field temporarily
		uuid.Nil,
		false,
		h.config.JWTSecret,
		5*time.Minute, // Short-lived
	)
}

// parseTempToken extracts data from temp token
func (h *AuthHandler) parseTempToken(tokenStr string) (uuid.UUID, string, string, error) {
	claims, err := middleware.ValidateToken(tokenStr, h.config.JWTSecret)
	if err != nil {
		return uuid.Nil, "", "", err
	}

	// Parse device info from email field
	parts := splitDeviceInfo(claims.Email)
	if len(parts) != 2 {
		return uuid.Nil, "", "", errors.New("invalid temp token format")
	}

	return claims.UserID, parts[0], parts[1], nil
}

func splitDeviceInfo(s string) []string {
	for i := len(s) - 1; i >= 0; i-- {
		if s[i] == '|' {
			return []string{s[:i], s[i+1:]}
		}
	}
	return []string{s}
}

func generateSecureToken() string {
	b := make([]byte, 32)
	rand.Read(b)
	return base32.StdEncoding.EncodeToString(b)
}

func hashToken(token string) string {
	hash := sha256.Sum256([]byte(token))
	return hex.EncodeToString(hash[:])
}
