package web

import (
	"errors"
	"io/fs"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/pquerna/otp/totp"
	"github.com/rs/zerolog/log"
	"golang.org/x/crypto/bcrypt"

	"github.com/sprobst76/vibedterm-server/internal/repository"
)

const (
	userSessionCookieName = "user_session"
	userSessionDuration   = 4 * time.Hour
)

// UserWeb handles the user-facing web interface
type UserWeb struct {
	templates  *Templates
	sessions   *SessionStore
	userRepo   *repository.UserRepository
	deviceRepo *repository.DeviceRepository
}

// NewUserWeb creates a new user web handler
func NewUserWeb(
	userRepo *repository.UserRepository,
	deviceRepo *repository.DeviceRepository,
	templates *Templates,
) *UserWeb {
	return &UserWeb{
		templates:  templates,
		sessions:   NewSessionStore(userSessionDuration),
		userRepo:   userRepo,
		deviceRepo: deviceRepo,
	}
}

// RegisterRoutes registers all user web routes
func (u *UserWeb) RegisterRoutes(r *gin.Engine) {
	// Serve static files for user pages (reuse admin CSS)
	staticSubFS, err := fs.Sub(GetStaticFS(), "static")
	if err == nil {
		r.StaticFS("/account/static", http.FS(staticSubFS))
	}

	// Public routes
	r.GET("/register", u.registerPage)
	r.POST("/register", u.register)

	account := r.Group("/account")
	{
		account.GET("/login", u.loginPage)
		account.POST("/login", u.login)
		account.GET("/login/totp", u.totpPage)
		account.POST("/login/totp", u.validateTOTP)

		// Protected routes
		protected := account.Group("")
		protected.Use(u.authMiddleware())
		{
			protected.GET("/settings", u.settingsPage)
			protected.POST("/settings/password", u.changePassword)
			protected.GET("/settings/totp", u.totpSettingsPage)
			protected.POST("/settings/totp/disable", u.disableTOTP)
			protected.GET("/devices", u.devicesPage)
			protected.POST("/devices/:id/delete", u.deleteDevice)
			protected.POST("/logout", u.logout)
		}
	}
}

// authMiddleware checks for valid user session (approved & not blocked)
func (u *UserWeb) authMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		sessionID, err := c.Cookie(userSessionCookieName)
		if err != nil || sessionID == "" {
			c.Redirect(http.StatusFound, "/account/login")
			c.Abort()
			return
		}

		session := u.sessions.Get(sessionID)
		if session == nil {
			c.SetCookie(userSessionCookieName, "", -1, "/account", "", false, true)
			c.Redirect(http.StatusFound, "/account/login")
			c.Abort()
			return
		}

		if session.TOTPPending {
			c.Redirect(http.StatusFound, "/account/login/totp")
			c.Abort()
			return
		}

		c.Set("session", session)
		c.Next()
	}
}

// registerPage shows the registration form
func (u *UserWeb) registerPage(c *gin.Context) {
	data := gin.H{
		"Title": "Register",
		"Error": c.Query("error"),
	}
	c.Header("Content-Type", "text/html; charset=utf-8")
	if err := u.templates.Render(c.Writer, "register.html", data); err != nil {
		log.Error().Err(err).Msg("Failed to render register template")
		c.String(http.StatusInternalServerError, "Internal server error")
	}
}

// register handles the registration form submission
func (u *UserWeb) register(c *gin.Context) {
	email := c.PostForm("email")
	password := c.PostForm("password")
	confirmPassword := c.PostForm("confirm_password")

	if email == "" || password == "" {
		c.Redirect(http.StatusFound, "/register?error=Email+and+password+required")
		return
	}

	if len(password) < 8 {
		c.Redirect(http.StatusFound, "/register?error=Password+must+be+at+least+8+characters")
		return
	}

	if password != confirmPassword {
		c.Redirect(http.StatusFound, "/register?error=Passwords+do+not+match")
		return
	}

	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		c.Redirect(http.StatusFound, "/register?error=Internal+error")
		return
	}

	_, err = u.userRepo.Create(c.Request.Context(), email, string(hashedPassword))
	if err != nil {
		if errors.Is(err, repository.ErrUserAlreadyExists) {
			c.Redirect(http.StatusFound, "/register?error=Email+already+registered")
			return
		}
		log.Error().Err(err).Msg("Failed to create user via web registration")
		c.Redirect(http.StatusFound, "/register?error=Registration+failed")
		return
	}

	// Redirect to login with success message
	c.Redirect(http.StatusFound, "/account/login?success=Registration+successful.+Please+wait+for+admin+approval.")
}

// loginPage shows the login form
func (u *UserWeb) loginPage(c *gin.Context) {
	// If already logged in, redirect to settings
	if sessionID, err := c.Cookie(userSessionCookieName); err == nil {
		if session := u.sessions.Get(sessionID); session != nil && session.IsFullyAuthenticated() {
			c.Redirect(http.StatusFound, "/account/settings")
			return
		}
	}

	data := gin.H{
		"Title":   "Login",
		"Error":   c.Query("error"),
		"Success": c.Query("success"),
	}
	c.Header("Content-Type", "text/html; charset=utf-8")
	if err := u.templates.Render(c.Writer, "user_login.html", data); err != nil {
		log.Error().Err(err).Msg("Failed to render user login template")
		c.String(http.StatusInternalServerError, "Internal server error")
	}
}

// login handles the login form submission
func (u *UserWeb) login(c *gin.Context) {
	email := c.PostForm("email")
	password := c.PostForm("password")

	if email == "" || password == "" {
		c.Redirect(http.StatusFound, "/account/login?error=Email+and+password+required")
		return
	}

	user, err := u.userRepo.GetByEmail(c.Request.Context(), email)
	if err != nil {
		c.Redirect(http.StatusFound, "/account/login?error=Invalid+credentials")
		return
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(password)); err != nil {
		c.Redirect(http.StatusFound, "/account/login?error=Invalid+credentials")
		return
	}

	if user.IsBlocked {
		c.Redirect(http.StatusFound, "/account/login?error=Account+has+been+blocked")
		return
	}

	if !user.IsApproved {
		c.Redirect(http.StatusFound, "/account/login?error=Account+pending+admin+approval")
		return
	}

	session, err := u.sessions.Create(user.ID, user.Email, user.IsAdmin, user.TOTPEnabled)
	if err != nil {
		log.Error().Err(err).Msg("Failed to create user session")
		c.Redirect(http.StatusFound, "/account/login?error=Internal+error")
		return
	}

	c.SetCookie(userSessionCookieName, session.ID, int(userSessionDuration.Seconds()), "/account", "", false, true)

	// Update last login
	_ = u.userRepo.UpdateLastLogin(c.Request.Context(), user.ID)

	if user.TOTPEnabled {
		c.Redirect(http.StatusFound, "/account/login/totp")
	} else {
		c.Redirect(http.StatusFound, "/account/settings")
	}
}

// totpPage shows the TOTP verification form
func (u *UserWeb) totpPage(c *gin.Context) {
	sessionID, err := c.Cookie(userSessionCookieName)
	if err != nil || sessionID == "" {
		c.Redirect(http.StatusFound, "/account/login")
		return
	}

	session := u.sessions.Get(sessionID)
	if session == nil {
		c.Redirect(http.StatusFound, "/account/login")
		return
	}

	if !session.TOTPPending {
		c.Redirect(http.StatusFound, "/account/settings")
		return
	}

	data := gin.H{
		"Title": "Two-Factor Authentication",
		"Email": session.Email,
		"Error": c.Query("error"),
	}
	c.Header("Content-Type", "text/html; charset=utf-8")
	if err := u.templates.Render(c.Writer, "user_totp.html", data); err != nil {
		log.Error().Err(err).Msg("Failed to render user TOTP template")
		c.String(http.StatusInternalServerError, "Internal server error")
	}
}

// validateTOTP handles TOTP verification during login
func (u *UserWeb) validateTOTP(c *gin.Context) {
	sessionID, err := c.Cookie(userSessionCookieName)
	if err != nil || sessionID == "" {
		c.Redirect(http.StatusFound, "/account/login")
		return
	}

	session := u.sessions.Get(sessionID)
	if session == nil || !session.TOTPPending {
		c.Redirect(http.StatusFound, "/account/login")
		return
	}

	code := c.PostForm("code")
	if code == "" || len(code) != 6 {
		c.Redirect(http.StatusFound, "/account/login/totp?error=Invalid+code")
		return
	}

	user, err := u.userRepo.GetByID(c.Request.Context(), session.UserID)
	if err != nil {
		c.Redirect(http.StatusFound, "/account/login?error=Session+expired")
		return
	}

	if !totp.Validate(code, string(user.TOTPSecret)) {
		c.Redirect(http.StatusFound, "/account/login/totp?error=Invalid+code")
		return
	}

	u.sessions.UpgradeFromTOTP(sessionID)
	c.Redirect(http.StatusFound, "/account/settings")
}

// settingsPage shows the user settings page
func (u *UserWeb) settingsPage(c *gin.Context) {
	session := c.MustGet("session").(*Session)

	user, err := u.userRepo.GetByID(c.Request.Context(), session.UserID)
	if err != nil {
		log.Error().Err(err).Msg("Failed to get user for settings page")
		c.String(http.StatusInternalServerError, "Internal server error")
		return
	}

	data := gin.H{
		"Title":       "Account Settings",
		"Email":       user.Email,
		"CreatedAt":   user.CreatedAt,
		"TOTPEnabled": user.TOTPEnabled,
		"Success":     c.Query("success"),
		"Error":       c.Query("error"),
	}
	c.Header("Content-Type", "text/html; charset=utf-8")
	if err := u.templates.Render(c.Writer, "user_settings.html", data); err != nil {
		log.Error().Err(err).Msg("Failed to render user settings template")
		c.String(http.StatusInternalServerError, "Internal server error")
	}
}

// changePassword handles password change
func (u *UserWeb) changePassword(c *gin.Context) {
	session := c.MustGet("session").(*Session)

	currentPassword := c.PostForm("current_password")
	newPassword := c.PostForm("new_password")
	confirmPassword := c.PostForm("confirm_password")

	if currentPassword == "" || newPassword == "" || confirmPassword == "" {
		c.Redirect(http.StatusFound, "/account/settings?error=All+fields+are+required")
		return
	}

	if len(newPassword) < 8 {
		c.Redirect(http.StatusFound, "/account/settings?error=New+password+must+be+at+least+8+characters")
		return
	}

	if newPassword != confirmPassword {
		c.Redirect(http.StatusFound, "/account/settings?error=New+passwords+do+not+match")
		return
	}

	user, err := u.userRepo.GetByID(c.Request.Context(), session.UserID)
	if err != nil {
		c.Redirect(http.StatusFound, "/account/settings?error=Internal+error")
		return
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(currentPassword)); err != nil {
		c.Redirect(http.StatusFound, "/account/settings?error=Current+password+is+incorrect")
		return
	}

	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(newPassword), bcrypt.DefaultCost)
	if err != nil {
		c.Redirect(http.StatusFound, "/account/settings?error=Internal+error")
		return
	}

	if err := u.userRepo.UpdatePassword(c.Request.Context(), session.UserID, string(hashedPassword)); err != nil {
		log.Error().Err(err).Msg("Failed to update user password")
		c.Redirect(http.StatusFound, "/account/settings?error=Failed+to+update+password")
		return
	}

	c.Redirect(http.StatusFound, "/account/settings?success=Password+updated+successfully")
}

// totpSettingsPage shows TOTP management page
func (u *UserWeb) totpSettingsPage(c *gin.Context) {
	session := c.MustGet("session").(*Session)

	user, err := u.userRepo.GetByID(c.Request.Context(), session.UserID)
	if err != nil {
		c.Redirect(http.StatusFound, "/account/settings")
		return
	}

	if !user.TOTPEnabled {
		c.Redirect(http.StatusFound, "/account/settings")
		return
	}

	data := gin.H{
		"Title":   "Two-Factor Authentication",
		"Email":   user.Email,
		"Success": c.Query("success"),
		"Error":   c.Query("error"),
	}
	c.Header("Content-Type", "text/html; charset=utf-8")
	if err := u.templates.Render(c.Writer, "user_totp_settings.html", data); err != nil {
		log.Error().Err(err).Msg("Failed to render TOTP settings template")
		c.String(http.StatusInternalServerError, "Internal server error")
	}
}

// disableTOTP handles TOTP disable request
func (u *UserWeb) disableTOTP(c *gin.Context) {
	session := c.MustGet("session").(*Session)

	password := c.PostForm("password")
	code := c.PostForm("code")

	if password == "" || code == "" {
		c.Redirect(http.StatusFound, "/account/settings/totp?error=Password+and+code+required")
		return
	}

	user, err := u.userRepo.GetByID(c.Request.Context(), session.UserID)
	if err != nil {
		c.Redirect(http.StatusFound, "/account/settings/totp?error=Internal+error")
		return
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(password)); err != nil {
		c.Redirect(http.StatusFound, "/account/settings/totp?error=Invalid+password")
		return
	}

	if !totp.Validate(code, string(user.TOTPSecret)) {
		c.Redirect(http.StatusFound, "/account/settings/totp?error=Invalid+TOTP+code")
		return
	}

	if err := u.userRepo.DisableTOTP(c.Request.Context(), session.UserID); err != nil {
		log.Error().Err(err).Msg("Failed to disable TOTP")
		c.Redirect(http.StatusFound, "/account/settings/totp?error=Failed+to+disable+2FA")
		return
	}

	log.Info().Str("email", session.Email).Msg("User disabled 2FA via web interface")
	c.Redirect(http.StatusFound, "/account/settings?success=Two-factor+authentication+disabled")
}

// devicesPage shows the user's devices
func (u *UserWeb) devicesPage(c *gin.Context) {
	session := c.MustGet("session").(*Session)

	devices, err := u.deviceRepo.GetByUserID(c.Request.Context(), session.UserID)
	if err != nil {
		log.Error().Err(err).Msg("Failed to list user devices")
		c.String(http.StatusInternalServerError, "Internal server error")
		return
	}

	data := gin.H{
		"Title":   "Devices",
		"Email":   session.Email,
		"Devices": devices,
		"Success": c.Query("success"),
		"Error":   c.Query("error"),
	}
	c.Header("Content-Type", "text/html; charset=utf-8")
	if err := u.templates.Render(c.Writer, "user_devices.html", data); err != nil {
		log.Error().Err(err).Msg("Failed to render devices template")
		c.String(http.StatusInternalServerError, "Internal server error")
	}
}

// deleteDevice removes a device
func (u *UserWeb) deleteDevice(c *gin.Context) {
	session := c.MustGet("session").(*Session)

	deviceIDStr := c.Param("id")
	deviceID, err := uuid.Parse(deviceIDStr)
	if err != nil {
		c.Redirect(http.StatusFound, "/account/devices?error=Invalid+device+ID")
		return
	}

	// Verify device belongs to user
	device, err := u.deviceRepo.GetByID(c.Request.Context(), deviceID)
	if err != nil {
		c.Redirect(http.StatusFound, "/account/devices?error=Device+not+found")
		return
	}

	if device.UserID != session.UserID {
		c.Redirect(http.StatusFound, "/account/devices?error=Device+not+found")
		return
	}

	if err := u.deviceRepo.Delete(c.Request.Context(), deviceID); err != nil {
		log.Error().Err(err).Msg("Failed to delete device")
		c.Redirect(http.StatusFound, "/account/devices?error=Failed+to+remove+device")
		return
	}

	log.Info().Str("device_id", deviceIDStr).Str("email", session.Email).Msg("Device removed via web interface")
	c.Redirect(http.StatusFound, "/account/devices?success=Device+removed")
}

// logout destroys the session
func (u *UserWeb) logout(c *gin.Context) {
	if sessionID, err := c.Cookie(userSessionCookieName); err == nil {
		u.sessions.Delete(sessionID)
	}
	c.SetCookie(userSessionCookieName, "", -1, "/account", "", false, true)
	c.Redirect(http.StatusFound, "/account/login")
}
