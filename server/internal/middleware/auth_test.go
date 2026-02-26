package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

func init() {
	gin.SetMode(gin.TestMode)
}

func TestGenerateAndValidateToken(t *testing.T) {
	secret := "test-secret-key"
	userID := uuid.New()
	deviceID := uuid.New()
	email := "test@example.com"

	token, err := GenerateToken(userID, email, deviceID, true, secret, time.Hour)
	if err != nil {
		t.Fatalf("GenerateToken failed: %v", err)
	}

	claims, err := ValidateToken(token, secret)
	if err != nil {
		t.Fatalf("ValidateToken failed: %v", err)
	}

	if claims.UserID != userID {
		t.Errorf("UserID = %v, want %v", claims.UserID, userID)
	}
	if claims.Email != email {
		t.Errorf("Email = %q, want %q", claims.Email, email)
	}
	if claims.DeviceID != deviceID {
		t.Errorf("DeviceID = %v, want %v", claims.DeviceID, deviceID)
	}
	if !claims.IsAdmin {
		t.Error("IsAdmin = false, want true")
	}
}

func TestGenerateAndValidateToken_NotAdmin(t *testing.T) {
	secret := "test-secret"
	userID := uuid.New()
	deviceID := uuid.New()

	token, err := GenerateToken(userID, "user@test.com", deviceID, false, secret, time.Hour)
	if err != nil {
		t.Fatalf("GenerateToken failed: %v", err)
	}

	claims, err := ValidateToken(token, secret)
	if err != nil {
		t.Fatalf("ValidateToken failed: %v", err)
	}

	if claims.IsAdmin {
		t.Error("IsAdmin = true, want false")
	}
}

func TestValidateToken_Expired(t *testing.T) {
	secret := "test-secret"
	userID := uuid.New()
	deviceID := uuid.New()

	// Generate token with negative duration (already expired)
	token, err := GenerateToken(userID, "test@test.com", deviceID, false, secret, -time.Hour)
	if err != nil {
		t.Fatalf("GenerateToken failed: %v", err)
	}

	_, err = ValidateToken(token, secret)
	if err != ErrExpiredToken {
		t.Errorf("error = %v, want ErrExpiredToken", err)
	}
}

func TestValidateToken_WrongKey(t *testing.T) {
	userID := uuid.New()
	deviceID := uuid.New()

	token, err := GenerateToken(userID, "test@test.com", deviceID, false, "correct-key", time.Hour)
	if err != nil {
		t.Fatalf("GenerateToken failed: %v", err)
	}

	_, err = ValidateToken(token, "wrong-key")
	if err == nil {
		t.Error("expected error for wrong key, got nil")
	}
	if err != ErrInvalidToken {
		t.Errorf("error = %v, want ErrInvalidToken", err)
	}
}

func TestValidateToken_Garbage(t *testing.T) {
	_, err := ValidateToken("not-a-valid-token", "secret")
	if err != ErrInvalidToken {
		t.Errorf("error = %v, want ErrInvalidToken", err)
	}
}

func TestJWTMiddleware_NoAuthHeader(t *testing.T) {
	r := gin.New()
	r.Use(JWTMiddleware("secret"))
	r.GET("/test", func(c *gin.Context) {
		c.String(http.StatusOK, "ok")
	})

	w := httptest.NewRecorder()
	req := httptest.NewRequest("GET", "/test", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Errorf("status = %d, want %d", w.Code, http.StatusUnauthorized)
	}
}

func TestJWTMiddleware_InvalidFormat(t *testing.T) {
	r := gin.New()
	r.Use(JWTMiddleware("secret"))
	r.GET("/test", func(c *gin.Context) {
		c.String(http.StatusOK, "ok")
	})

	w := httptest.NewRecorder()
	req := httptest.NewRequest("GET", "/test", nil)
	req.Header.Set("Authorization", "NotBearer sometoken")
	r.ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Errorf("status = %d, want %d", w.Code, http.StatusUnauthorized)
	}
}

func TestJWTMiddleware_ValidToken(t *testing.T) {
	secret := "test-secret"
	userID := uuid.New()
	deviceID := uuid.New()
	email := "user@example.com"

	token, err := GenerateToken(userID, email, deviceID, true, secret, time.Hour)
	if err != nil {
		t.Fatalf("GenerateToken failed: %v", err)
	}

	var gotUserID uuid.UUID
	var gotEmail string
	var gotDeviceID uuid.UUID
	var gotIsAdmin bool

	r := gin.New()
	r.Use(JWTMiddleware(secret))
	r.GET("/test", func(c *gin.Context) {
		gotUserID = c.MustGet("user_id").(uuid.UUID)
		gotEmail = c.MustGet("email").(string)
		gotDeviceID = c.MustGet("device_id").(uuid.UUID)
		gotIsAdmin = c.MustGet("is_admin").(bool)
		c.String(http.StatusOK, "ok")
	})

	w := httptest.NewRecorder()
	req := httptest.NewRequest("GET", "/test", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", w.Code, http.StatusOK)
	}
	if gotUserID != userID {
		t.Errorf("user_id = %v, want %v", gotUserID, userID)
	}
	if gotEmail != email {
		t.Errorf("email = %q, want %q", gotEmail, email)
	}
	if gotDeviceID != deviceID {
		t.Errorf("device_id = %v, want %v", gotDeviceID, deviceID)
	}
	if !gotIsAdmin {
		t.Error("is_admin = false, want true")
	}
}

func TestJWTMiddleware_ExpiredToken(t *testing.T) {
	secret := "test-secret"
	token, _ := GenerateToken(uuid.New(), "x@x.com", uuid.New(), false, secret, -time.Hour)

	r := gin.New()
	r.Use(JWTMiddleware(secret))
	r.GET("/test", func(c *gin.Context) {
		c.String(http.StatusOK, "ok")
	})

	w := httptest.NewRecorder()
	req := httptest.NewRequest("GET", "/test", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Errorf("status = %d, want %d", w.Code, http.StatusUnauthorized)
	}
}

func TestAdminMiddleware_NotAdmin(t *testing.T) {
	r := gin.New()
	// Simulate JWTMiddleware having set is_admin=false
	r.Use(func(c *gin.Context) {
		c.Set("is_admin", false)
		c.Next()
	})
	r.Use(AdminMiddleware())
	r.GET("/test", func(c *gin.Context) {
		c.String(http.StatusOK, "ok")
	})

	w := httptest.NewRecorder()
	req := httptest.NewRequest("GET", "/test", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusForbidden {
		t.Errorf("status = %d, want %d", w.Code, http.StatusForbidden)
	}
}

func TestAdminMiddleware_IsAdmin(t *testing.T) {
	r := gin.New()
	r.Use(func(c *gin.Context) {
		c.Set("is_admin", true)
		c.Next()
	})
	r.Use(AdminMiddleware())
	r.GET("/test", func(c *gin.Context) {
		c.String(http.StatusOK, "ok")
	})

	w := httptest.NewRecorder()
	req := httptest.NewRequest("GET", "/test", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("status = %d, want %d", w.Code, http.StatusOK)
	}
}

func TestAdminMiddleware_NoClaimInContext(t *testing.T) {
	r := gin.New()
	r.Use(AdminMiddleware())
	r.GET("/test", func(c *gin.Context) {
		c.String(http.StatusOK, "ok")
	})

	w := httptest.NewRecorder()
	req := httptest.NewRequest("GET", "/test", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusForbidden {
		t.Errorf("status = %d, want %d", w.Code, http.StatusForbidden)
	}
}

func TestGetUserID(t *testing.T) {
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)

	// No user_id set
	_, err := GetUserID(c)
	if err == nil {
		t.Error("expected error when user_id not in context")
	}

	// Set user_id
	expected := uuid.New()
	c.Set("user_id", expected)
	got, err := GetUserID(c)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got != expected {
		t.Errorf("GetUserID = %v, want %v", got, expected)
	}
}

func TestGetDeviceID(t *testing.T) {
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)

	_, err := GetDeviceID(c)
	if err == nil {
		t.Error("expected error when device_id not in context")
	}

	expected := uuid.New()
	c.Set("device_id", expected)
	got, err := GetDeviceID(c)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got != expected {
		t.Errorf("GetDeviceID = %v, want %v", got, expected)
	}
}
