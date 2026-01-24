package web

import (
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
	sessionCookieName = "admin_session"
	sessionDuration   = 4 * time.Hour
)

// AdminWeb handles the admin web interface
type AdminWeb struct {
	templates    *Templates
	sessions     *SessionStore
	userRepo     *repository.UserRepository
	deviceRepo   *repository.DeviceRepository
	vaultRepo    *repository.VaultRepository
	refreshRepo  *repository.RefreshTokenRepository
}

// NewAdminWeb creates a new admin web handler
func NewAdminWeb(
	userRepo *repository.UserRepository,
	deviceRepo *repository.DeviceRepository,
	vaultRepo *repository.VaultRepository,
	refreshRepo *repository.RefreshTokenRepository,
) (*AdminWeb, error) {
	templates, err := NewTemplates()
	if err != nil {
		return nil, err
	}

	return &AdminWeb{
		templates:   templates,
		sessions:    NewSessionStore(sessionDuration),
		userRepo:    userRepo,
		deviceRepo:  deviceRepo,
		vaultRepo:   vaultRepo,
		refreshRepo: refreshRepo,
	}, nil
}

// RegisterRoutes registers all admin web routes
func (a *AdminWeb) RegisterRoutes(r *gin.Engine) {
	// Serve static files
	staticSubFS, err := fs.Sub(GetStaticFS(), "static")
	if err == nil {
		r.StaticFS("/admin/static", http.FS(staticSubFS))
	}

	admin := r.Group("/admin")
	{
		// Public routes
		admin.GET("/login", a.loginPage)
		admin.POST("/login", a.login)
		admin.GET("/login/totp", a.totpPage)
		admin.POST("/login/totp", a.validateTOTP)

		// Protected routes (require valid session)
		protected := admin.Group("")
		protected.Use(a.authMiddleware())
		{
			admin.GET("/", a.index)
			admin.GET("/dashboard", a.dashboard)
			admin.GET("/users", a.usersPage)
			admin.POST("/users/:id/approve", a.approveUser)
			admin.POST("/users/:id/reject", a.rejectUser)
			admin.POST("/users/:id/block", a.blockUser)
			admin.POST("/logout", a.logout)
		}
	}
}

// authMiddleware checks for valid admin session
func (a *AdminWeb) authMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		sessionID, err := c.Cookie(sessionCookieName)
		if err != nil || sessionID == "" {
			c.Redirect(http.StatusFound, "/admin/login")
			c.Abort()
			return
		}

		session := a.sessions.Get(sessionID)
		if session == nil {
			// Clear invalid cookie
			c.SetCookie(sessionCookieName, "", -1, "/admin", "", false, true)
			c.Redirect(http.StatusFound, "/admin/login")
			c.Abort()
			return
		}

		// Check if TOTP verification is pending
		if session.TOTPPending {
			c.Redirect(http.StatusFound, "/admin/login/totp")
			c.Abort()
			return
		}

		c.Set("session", session)
		c.Next()
	}
}

// index redirects to dashboard or login
func (a *AdminWeb) index(c *gin.Context) {
	c.Redirect(http.StatusFound, "/admin/dashboard")
}

// loginPage shows the login form
func (a *AdminWeb) loginPage(c *gin.Context) {
	// If already logged in, redirect to dashboard
	if sessionID, err := c.Cookie(sessionCookieName); err == nil {
		if session := a.sessions.Get(sessionID); session != nil && session.IsFullyAuthenticated() {
			c.Redirect(http.StatusFound, "/admin/dashboard")
			return
		}
	}

	data := gin.H{
		"Title": "Admin Login",
		"Error": c.Query("error"),
	}
	c.Header("Content-Type", "text/html; charset=utf-8")
	if err := a.templates.Render(c.Writer, "login.html", data); err != nil {
		log.Error().Err(err).Msg("Failed to render login template")
		c.String(http.StatusInternalServerError, "Internal server error")
	}
}

// login handles the login form submission
func (a *AdminWeb) login(c *gin.Context) {
	email := c.PostForm("email")
	password := c.PostForm("password")

	if email == "" || password == "" {
		c.Redirect(http.StatusFound, "/admin/login?error=Email+and+password+required")
		return
	}

	// Get user from database
	user, err := a.userRepo.GetByEmail(c.Request.Context(), email)
	if err != nil {
		log.Debug().Str("email", email).Msg("Admin login failed: user not found")
		c.Redirect(http.StatusFound, "/admin/login?error=Invalid+credentials")
		return
	}

	// Check if user is admin
	if !user.IsAdmin {
		log.Warn().Str("email", email).Msg("Non-admin user attempted admin login")
		c.Redirect(http.StatusFound, "/admin/login?error=Invalid+credentials")
		return
	}

	// Verify password
	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(password)); err != nil {
		log.Debug().Str("email", email).Msg("Admin login failed: wrong password")
		c.Redirect(http.StatusFound, "/admin/login?error=Invalid+credentials")
		return
	}

	// Create session (may need TOTP verification)
	session, err := a.sessions.Create(user.ID, user.Email, user.IsAdmin, user.TOTPEnabled)
	if err != nil {
		log.Error().Err(err).Msg("Failed to create session")
		c.Redirect(http.StatusFound, "/admin/login?error=Internal+error")
		return
	}

	// Set session cookie
	c.SetCookie(sessionCookieName, session.ID, int(sessionDuration.Seconds()), "/admin", "", false, true)

	log.Info().Str("email", email).Bool("totp_required", user.TOTPEnabled).Msg("Admin login successful")

	// Redirect based on TOTP status
	if user.TOTPEnabled {
		c.Redirect(http.StatusFound, "/admin/login/totp")
	} else {
		c.Redirect(http.StatusFound, "/admin/dashboard")
	}
}

// totpPage shows the TOTP verification form
func (a *AdminWeb) totpPage(c *gin.Context) {
	sessionID, err := c.Cookie(sessionCookieName)
	if err != nil || sessionID == "" {
		c.Redirect(http.StatusFound, "/admin/login")
		return
	}

	session := a.sessions.Get(sessionID)
	if session == nil {
		c.Redirect(http.StatusFound, "/admin/login")
		return
	}

	if !session.TOTPPending {
		c.Redirect(http.StatusFound, "/admin/dashboard")
		return
	}

	data := gin.H{
		"Title": "Two-Factor Authentication",
		"Email": session.Email,
		"Error": c.Query("error"),
	}
	c.Header("Content-Type", "text/html; charset=utf-8")
	if err := a.templates.Render(c.Writer, "totp.html", data); err != nil {
		log.Error().Err(err).Msg("Failed to render TOTP template")
		c.String(http.StatusInternalServerError, "Internal server error")
	}
}

// validateTOTP handles TOTP verification
func (a *AdminWeb) validateTOTP(c *gin.Context) {
	sessionID, err := c.Cookie(sessionCookieName)
	if err != nil || sessionID == "" {
		c.Redirect(http.StatusFound, "/admin/login")
		return
	}

	session := a.sessions.Get(sessionID)
	if session == nil || !session.TOTPPending {
		c.Redirect(http.StatusFound, "/admin/login")
		return
	}

	code := c.PostForm("code")
	if code == "" || len(code) != 6 {
		c.Redirect(http.StatusFound, "/admin/login/totp?error=Invalid+code")
		return
	}

	// Get user to access TOTP secret
	user, err := a.userRepo.GetByID(c.Request.Context(), session.UserID)
	if err != nil {
		c.Redirect(http.StatusFound, "/admin/login?error=Session+expired")
		return
	}

	// Validate TOTP code
	if !totp.Validate(code, string(user.TOTPSecret)) {
		log.Debug().Str("email", user.Email).Msg("Invalid TOTP code")
		c.Redirect(http.StatusFound, "/admin/login/totp?error=Invalid+code")
		return
	}

	// Upgrade session to fully authenticated
	a.sessions.UpgradeFromTOTP(sessionID)
	log.Info().Str("email", user.Email).Msg("Admin TOTP verification successful")

	c.Redirect(http.StatusFound, "/admin/dashboard")
}

// dashboard shows the admin dashboard
func (a *AdminWeb) dashboard(c *gin.Context) {
	session := c.MustGet("session").(*Session)
	ctx := c.Request.Context()

	// Get statistics
	total, approved, pending, blocked, err := a.userRepo.Count(ctx)
	if err != nil {
		log.Error().Err(err).Msg("Failed to get user stats")
	}

	deviceCount, _ := a.deviceRepo.Count(ctx)
	vaultCount, _ := a.vaultRepo.Count(ctx)

	data := gin.H{
		"Title":        "Dashboard",
		"Email":        session.Email,
		"TotalUsers":   total,
		"ApprovedUsers": approved,
		"PendingUsers": pending,
		"BlockedUsers": blocked,
		"Devices":      deviceCount,
		"Vaults":       vaultCount,
	}
	c.Header("Content-Type", "text/html; charset=utf-8")
	if err := a.templates.Render(c.Writer, "dashboard.html", data); err != nil {
		log.Error().Err(err).Msg("Failed to render dashboard template")
		c.String(http.StatusInternalServerError, "Internal server error")
	}
}

// usersPage shows the user management page
func (a *AdminWeb) usersPage(c *gin.Context) {
	session := c.MustGet("session").(*Session)
	ctx := c.Request.Context()

	users, err := a.userRepo.List(ctx)
	if err != nil {
		log.Error().Err(err).Msg("Failed to list users")
		c.String(http.StatusInternalServerError, "Failed to load users")
		return
	}

	// Split users into pending and all
	var pendingUsers, allUsers []gin.H
	for _, u := range users {
		userMap := gin.H{
			"ID":          u.ID.String(),
			"Email":       u.Email,
			"IsApproved":  u.IsApproved,
			"IsAdmin":     u.IsAdmin,
			"IsBlocked":   u.IsBlocked,
			"TOTPEnabled": u.TOTPEnabled,
			"CreatedAt":   u.CreatedAt,
			"LastLoginAt": u.LastLoginAt,
		}
		allUsers = append(allUsers, userMap)
		if !u.IsApproved && !u.IsBlocked {
			pendingUsers = append(pendingUsers, userMap)
		}
	}

	data := gin.H{
		"Title":        "Users",
		"Email":        session.Email,
		"PendingUsers": pendingUsers,
		"AllUsers":     allUsers,
		"Success":      c.Query("success"),
		"Error":        c.Query("error"),
	}
	c.Header("Content-Type", "text/html; charset=utf-8")
	if err := a.templates.Render(c.Writer, "users.html", data); err != nil {
		log.Error().Err(err).Msg("Failed to render users template")
		c.String(http.StatusInternalServerError, "Internal server error")
	}
}

// approveUser approves a pending user
func (a *AdminWeb) approveUser(c *gin.Context) {
	userIDStr := c.Param("id")
	userID, err := uuid.Parse(userIDStr)
	if err != nil {
		c.Redirect(http.StatusFound, "/admin/users?error=Invalid+user+ID")
		return
	}

	if err := a.userRepo.SetApproved(c.Request.Context(), userID, true); err != nil {
		log.Error().Err(err).Str("user_id", userIDStr).Msg("Failed to approve user")
		c.Redirect(http.StatusFound, "/admin/users?error=Failed+to+approve+user")
		return
	}

	log.Info().Str("user_id", userIDStr).Msg("User approved via web interface")
	c.Redirect(http.StatusFound, "/admin/users?success=User+approved")
}

// rejectUser rejects (deletes) a pending user
func (a *AdminWeb) rejectUser(c *gin.Context) {
	userIDStr := c.Param("id")
	userID, err := uuid.Parse(userIDStr)
	if err != nil {
		c.Redirect(http.StatusFound, "/admin/users?error=Invalid+user+ID")
		return
	}

	// Only allow rejecting non-approved users
	user, err := a.userRepo.GetByID(c.Request.Context(), userID)
	if err != nil {
		c.Redirect(http.StatusFound, "/admin/users?error=User+not+found")
		return
	}

	if user.IsApproved {
		c.Redirect(http.StatusFound, "/admin/users?error=Cannot+reject+approved+user")
		return
	}

	if err := a.userRepo.Delete(c.Request.Context(), userID); err != nil {
		log.Error().Err(err).Str("user_id", userIDStr).Msg("Failed to reject user")
		c.Redirect(http.StatusFound, "/admin/users?error=Failed+to+reject+user")
		return
	}

	log.Info().Str("user_id", userIDStr).Msg("User rejected via web interface")
	c.Redirect(http.StatusFound, "/admin/users?success=User+rejected")
}

// blockUser blocks or unblocks a user
func (a *AdminWeb) blockUser(c *gin.Context) {
	userIDStr := c.Param("id")
	userID, err := uuid.Parse(userIDStr)
	if err != nil {
		c.Redirect(http.StatusFound, "/admin/users?error=Invalid+user+ID")
		return
	}

	action := c.PostForm("action")
	blocked := action == "block"

	// Get user to check if admin
	user, err := a.userRepo.GetByID(c.Request.Context(), userID)
	if err != nil {
		c.Redirect(http.StatusFound, "/admin/users?error=User+not+found")
		return
	}

	// Don't allow blocking admins
	if user.IsAdmin {
		c.Redirect(http.StatusFound, "/admin/users?error=Cannot+block+admin+users")
		return
	}

	if err := a.userRepo.SetBlocked(c.Request.Context(), userID, blocked); err != nil {
		log.Error().Err(err).Str("user_id", userIDStr).Bool("blocked", blocked).Msg("Failed to update user blocked status")
		c.Redirect(http.StatusFound, "/admin/users?error=Failed+to+update+user")
		return
	}

	// Revoke all tokens if blocking
	if blocked {
		_ = a.refreshRepo.RevokeAllForUser(c.Request.Context(), userID)
	}

	actionText := "unblocked"
	if blocked {
		actionText = "blocked"
	}
	log.Info().Str("user_id", userIDStr).Str("action", actionText).Msg("User status updated via web interface")
	c.Redirect(http.StatusFound, "/admin/users?success=User+"+actionText)
}

// logout destroys the session and redirects to login
func (a *AdminWeb) logout(c *gin.Context) {
	if sessionID, err := c.Cookie(sessionCookieName); err == nil {
		a.sessions.Delete(sessionID)
	}
	c.SetCookie(sessionCookieName, "", -1, "/admin", "", false, true)
	c.Redirect(http.StatusFound, "/admin/login")
}
