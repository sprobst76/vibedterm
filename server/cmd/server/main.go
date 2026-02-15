package main

import (
	"context"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"
	"golang.org/x/crypto/bcrypt"

	"github.com/sprobst76/vibedterm-server/internal/config"
	"github.com/sprobst76/vibedterm-server/internal/database"
	"github.com/sprobst76/vibedterm-server/internal/handlers"
	"github.com/sprobst76/vibedterm-server/internal/middleware"
	"github.com/sprobst76/vibedterm-server/internal/repository"
	"github.com/sprobst76/vibedterm-server/internal/web"
)

func main() {
	// Setup logging
	zerolog.TimeFieldFormat = zerolog.TimeFormatUnix
	log.Logger = log.Output(zerolog.ConsoleWriter{Out: os.Stdout})

	// Load configuration
	cfg := config.Load()
	log.Info().Str("addr", cfg.ServerAddr).Msg("Starting VibedTerm server")

	// Connect to database
	if err := database.Connect(cfg.DatabaseURL); err != nil {
		log.Fatal().Err(err).Msg("Failed to connect to database")
	}
	defer database.Close()

	// Run migrations
	ctx := context.Background()
	if err := database.RunMigrations(ctx); err != nil {
		log.Fatal().Err(err).Msg("Failed to run migrations")
	}

	// Create repositories
	userRepo := repository.NewUserRepository(database.DB)
	deviceRepo := repository.NewDeviceRepository(database.DB)
	refreshRepo := repository.NewRefreshTokenRepository(database.DB)
	recoveryRepo := repository.NewRecoveryCodeRepository(database.DB)
	vaultRepo := repository.NewVaultRepository(database.DB)
	syncLogRepo := repository.NewSyncLogRepository(database.DB)

	// Create handlers
	authHandler := handlers.NewAuthHandler(userRepo, deviceRepo, refreshRepo, cfg)
	totpHandler := handlers.NewTOTPHandler(userRepo, recoveryRepo, cfg)
	vaultHandler := handlers.NewVaultHandler(vaultRepo, deviceRepo, syncLogRepo)
	deviceHandler := handlers.NewDeviceHandler(deviceRepo, refreshRepo)
	adminHandler := handlers.NewAdminHandler(userRepo, deviceRepo, vaultRepo, refreshRepo)

	// Create shared templates and web interfaces
	templates, err := web.NewTemplates()
	if err != nil {
		log.Fatal().Err(err).Msg("Failed to parse web templates")
	}
	adminWeb := web.NewAdminWeb(userRepo, deviceRepo, vaultRepo, refreshRepo, templates)
	userWeb := web.NewUserWeb(userRepo, deviceRepo, templates)

	// Setup Gin
	gin.SetMode(cfg.ServerMode)
	r := gin.New()
	r.Use(gin.Recovery())
	r.Use(ginLogger())

	// CORS middleware
	r.Use(corsMiddleware())

	// Register web interface routes
	adminWeb.RegisterRoutes(r)
	userWeb.RegisterRoutes(r)

	// Health check
	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	// API v1
	v1 := r.Group("/api/v1")
	{
		// Public routes
		auth := v1.Group("/auth")
		{
			auth.POST("/register", authHandler.Register)
			auth.POST("/login", authHandler.Login)
			auth.POST("/login/totp", authHandler.ValidateTOTP)
			auth.POST("/login/recovery", totpHandler.ValidateRecovery)
			auth.POST("/refresh", authHandler.Refresh)
			auth.POST("/logout", authHandler.Logout)
		}

		// Protected routes
		protected := v1.Group("")
		protected.Use(middleware.JWTMiddleware(cfg.JWTSecret))
		{
			// User profile
			protected.POST("/auth/logout-all", authHandler.LogoutAll)

			// TOTP management
			totp := protected.Group("/totp")
			{
				totp.POST("/setup", totpHandler.Setup)
				totp.POST("/verify", totpHandler.Verify)
				totp.POST("/disable", totpHandler.Disable)
				totp.POST("/recovery-codes", totpHandler.RegenerateRecoveryCodes)
			}

			// Vault sync
			vault := protected.Group("/vault")
			{
				vault.GET("/status", vaultHandler.Status)
				vault.GET("/pull", vaultHandler.Pull)
				vault.POST("/push", vaultHandler.Push)
				vault.POST("/force-overwrite", vaultHandler.ForceOverwrite)
				vault.GET("/history", vaultHandler.History)
			}

			// Device management
			devices := protected.Group("/devices")
			{
				devices.GET("", deviceHandler.List)
				devices.POST("", deviceHandler.Register)
				devices.GET("/current", deviceHandler.GetCurrent)
				devices.PUT("/:id", deviceHandler.Rename)
				devices.DELETE("/:id", deviceHandler.Delete)
			}

			// Admin routes
			admin := protected.Group("/admin")
			admin.Use(middleware.AdminMiddleware())
			{
				admin.GET("/dashboard", adminHandler.Dashboard)
				admin.GET("/users", adminHandler.ListUsers)
				admin.POST("/users/:id/approve", adminHandler.ApproveUser)
				admin.POST("/users/:id/block", adminHandler.BlockUser)
				admin.DELETE("/users/:id", adminHandler.DeleteUser)
				admin.GET("/users/:id/devices", adminHandler.GetUserDevices)
			}
		}
	}

	// Create admin user if configured
	createAdminUser(ctx, userRepo, cfg)

	// Start server with graceful shutdown
	srv := &http.Server{
		Addr:    cfg.ServerAddr,
		Handler: r,
	}

	go func() {
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatal().Err(err).Msg("Failed to start server")
		}
	}()

	// Wait for interrupt signal
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	log.Info().Msg("Shutting down server...")

	// Graceful shutdown with 5 second timeout
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		log.Fatal().Err(err).Msg("Server forced to shutdown")
	}

	log.Info().Msg("Server exited")
}

func ginLogger() gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		path := c.Request.URL.Path

		c.Next()

		log.Info().
			Int("status", c.Writer.Status()).
			Str("method", c.Request.Method).
			Str("path", path).
			Dur("latency", time.Since(start)).
			Str("ip", c.ClientIP()).
			Msg("")
	}
}

func corsMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Header("Access-Control-Allow-Origin", "*")
		c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		c.Header("Access-Control-Allow-Headers", "Authorization, Content-Type")
		c.Header("Access-Control-Max-Age", "86400")

		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}

		c.Next()
	}
}

func createAdminUser(ctx context.Context, userRepo *repository.UserRepository, cfg *config.Config) {
	if cfg.AdminEmail == "" || cfg.AdminPassword == "" {
		return
	}

	// Check if admin already exists
	_, err := userRepo.GetByEmail(ctx, cfg.AdminEmail)
	if err == nil {
		log.Info().Str("email", cfg.AdminEmail).Msg("Admin user already exists")
		return
	}

	// Create admin user
	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(cfg.AdminPassword), bcrypt.DefaultCost)
	if err != nil {
		log.Error().Err(err).Msg("Failed to hash admin password")
		return
	}

	user, err := userRepo.Create(ctx, cfg.AdminEmail, string(hashedPassword))
	if err != nil {
		log.Error().Err(err).Msg("Failed to create admin user")
		return
	}

	// Approve and set as admin via direct SQL
	_, err = database.DB.Exec(ctx, `
		UPDATE users SET is_approved = true, is_admin = true WHERE id = $1
	`, user.ID)
	if err != nil {
		log.Error().Err(err).Msg("Failed to set admin privileges")
		return
	}

	log.Info().Str("email", cfg.AdminEmail).Msg("Admin user created")
}
