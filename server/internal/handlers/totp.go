package handlers

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base32"
	"encoding/hex"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/pquerna/otp/totp"
	"golang.org/x/crypto/bcrypt"

	"github.com/sprobst76/vibedterm-server/internal/config"
	"github.com/sprobst76/vibedterm-server/internal/middleware"
	"github.com/sprobst76/vibedterm-server/internal/models"
	"github.com/sprobst76/vibedterm-server/internal/repository"
)

// TOTPHandler handles TOTP-related endpoints
type TOTPHandler struct {
	userRepo     *repository.UserRepository
	recoveryRepo *repository.RecoveryCodeRepository
	config       *config.Config
}

// NewTOTPHandler creates a new TOTP handler
func NewTOTPHandler(
	userRepo *repository.UserRepository,
	recoveryRepo *repository.RecoveryCodeRepository,
	cfg *config.Config,
) *TOTPHandler {
	return &TOTPHandler{
		userRepo:     userRepo,
		recoveryRepo: recoveryRepo,
		config:       cfg,
	}
}

// Setup initiates TOTP setup
func (h *TOTPHandler) Setup(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	user, err := h.userRepo.GetByID(c.Request.Context(), userID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
		return
	}

	if user.TOTPEnabled {
		c.JSON(http.StatusBadRequest, gin.H{"error": "TOTP already enabled"})
		return
	}

	// Generate TOTP key
	key, err := totp.Generate(totp.GenerateOpts{
		Issuer:      h.config.TOTPIssuer,
		AccountName: user.Email,
	})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate TOTP"})
		return
	}

	// Store secret (not yet enabled)
	secret, _ := base32.StdEncoding.DecodeString(key.Secret())
	if err := h.userRepo.SetTOTPSecret(c.Request.Context(), userID, secret); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to save TOTP secret"})
		return
	}

	c.JSON(http.StatusOK, models.TOTPSetupResponse{
		Secret:    key.Secret(),
		QRCodeURL: key.URL(),
		Issuer:    h.config.TOTPIssuer,
	})
}

// Verify verifies and enables TOTP
func (h *TOTPHandler) Verify(c *gin.Context) {
	var req models.TOTPVerifyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request"})
		return
	}

	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	user, err := h.userRepo.GetByID(c.Request.Context(), userID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
		return
	}

	if user.TOTPEnabled {
		c.JSON(http.StatusBadRequest, gin.H{"error": "TOTP already enabled"})
		return
	}

	if len(user.TOTPSecret) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "TOTP not set up"})
		return
	}

	// Validate code
	secret := base32.StdEncoding.EncodeToString(user.TOTPSecret)
	if !totp.Validate(req.Code, secret) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid TOTP code"})
		return
	}

	// Enable TOTP
	if err := h.userRepo.EnableTOTP(c.Request.Context(), userID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to enable TOTP"})
		return
	}

	// Generate recovery codes
	codes, err := h.generateRecoveryCodes(c, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "TOTP enabled but failed to generate recovery codes"})
		return
	}

	c.JSON(http.StatusOK, models.RecoveryCodesResponse{
		Codes: codes,
	})
}

// Disable disables TOTP
func (h *TOTPHandler) Disable(c *gin.Context) {
	var req models.TOTPDisableRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request"})
		return
	}

	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	user, err := h.userRepo.GetByID(c.Request.Context(), userID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
		return
	}

	// Verify password
	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.Password)); err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid password"})
		return
	}

	// Verify TOTP code
	secret := base32.StdEncoding.EncodeToString(user.TOTPSecret)
	if !totp.Validate(req.Code, secret) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid TOTP code"})
		return
	}

	// Disable TOTP
	if err := h.userRepo.DisableTOTP(c.Request.Context(), userID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to disable TOTP"})
		return
	}

	// Delete recovery codes
	_ = h.recoveryRepo.DeleteAllForUser(c.Request.Context(), userID)

	c.JSON(http.StatusOK, gin.H{"message": "TOTP disabled"})
}

// RegenerateRecoveryCodes generates new recovery codes
func (h *TOTPHandler) RegenerateRecoveryCodes(c *gin.Context) {
	var req struct {
		Code string `json:"code" binding:"required"`
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

	user, err := h.userRepo.GetByID(c.Request.Context(), userID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
		return
	}

	if !user.TOTPEnabled {
		c.JSON(http.StatusBadRequest, gin.H{"error": "TOTP not enabled"})
		return
	}

	// Verify TOTP code
	secret := base32.StdEncoding.EncodeToString(user.TOTPSecret)
	if !totp.Validate(req.Code, secret) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid TOTP code"})
		return
	}

	// Delete old recovery codes
	_ = h.recoveryRepo.DeleteAllForUser(c.Request.Context(), userID)

	// Generate new codes
	codes, err := h.generateRecoveryCodes(c, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate recovery codes"})
		return
	}

	c.JSON(http.StatusOK, models.RecoveryCodesResponse{
		Codes: codes,
	})
}

// ValidateRecovery validates recovery code during login
func (h *TOTPHandler) ValidateRecovery(c *gin.Context) {
	var req models.RecoveryValidateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request"})
		return
	}

	// Parse temp token (reusing from auth handler)
	claims, err := middleware.ValidateToken(req.TempToken, h.config.JWTSecret)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid or expired token"})
		return
	}

	userID := claims.UserID

	// Hash the recovery code
	codeHash := hashRecoveryCode(req.Code)

	// Find and use recovery code
	recoveryCode, err := h.recoveryRepo.GetByUserAndHash(c.Request.Context(), userID, codeHash)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid recovery code"})
		return
	}

	if recoveryCode.Used {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "recovery code already used"})
		return
	}

	// Mark as used
	if err := h.recoveryRepo.MarkUsed(c.Request.Context(), recoveryCode.ID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to process recovery code"})
		return
	}

	// Get device info from temp token
	parts := splitDeviceInfo(claims.Email)
	if len(parts) != 2 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid token format"})
		return
	}

	// Verify user exists
	_, err = h.userRepo.GetByID(c.Request.Context(), userID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
		return
	}

	// Return success - client needs to re-login with credentials
	c.JSON(http.StatusOK, gin.H{
		"message":          "recovery code accepted",
		"remaining_codes":  h.countRemainingCodes(c, userID),
		"requires_relogin": true,
	})
}

func (h *TOTPHandler) generateRecoveryCodes(c *gin.Context, userID uuid.UUID) ([]string, error) {
	codes := make([]string, 10)
	ctx := c.Request.Context()

	for i := 0; i < 10; i++ {
		code := generateRecoveryCode()
		codes[i] = code

		codeHash := hashRecoveryCode(code)
		if _, err := h.recoveryRepo.Create(ctx, userID, codeHash); err != nil {
			return nil, err
		}
	}

	return codes, nil
}

func (h *TOTPHandler) countRemainingCodes(c *gin.Context, userID uuid.UUID) int {
	count, _ := h.recoveryRepo.CountUnused(c.Request.Context(), userID)
	return count
}

func generateRecoveryCode() string {
	b := make([]byte, 5)
	rand.Read(b)
	return hex.EncodeToString(b)
}

func hashRecoveryCode(code string) string {
	hash := sha256.Sum256([]byte(code))
	return hex.EncodeToString(hash[:])
}
