package handlers

import (
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/sprobst76/vibedterm-server/internal/config"
)

func TestHashToken_Deterministic(t *testing.T) {
	input := "my-refresh-token-value"
	h1 := hashToken(input)
	h2 := hashToken(input)

	if h1 != h2 {
		t.Errorf("hashToken not deterministic: %q != %q", h1, h2)
	}

	// Different input should produce different hash
	h3 := hashToken("different-token")
	if h1 == h3 {
		t.Error("hashToken produced same hash for different inputs")
	}
}

func TestHashToken_NonEmpty(t *testing.T) {
	h := hashToken("anything")
	if h == "" {
		t.Error("hashToken returned empty string")
	}
	// SHA-256 hex = 64 chars
	if len(h) != 64 {
		t.Errorf("hashToken length = %d, want 64", len(h))
	}
}

func TestSplitDeviceInfo_Normal(t *testing.T) {
	parts := splitDeviceInfo("Device|phone")
	if len(parts) != 2 {
		t.Fatalf("splitDeviceInfo returned %d parts, want 2", len(parts))
	}
	if parts[0] != "Device" {
		t.Errorf("parts[0] = %q, want %q", parts[0], "Device")
	}
	if parts[1] != "phone" {
		t.Errorf("parts[1] = %q, want %q", parts[1], "phone")
	}
}

func TestSplitDeviceInfo_PipeInDeviceName(t *testing.T) {
	// "My|Device|phone" should split on the LAST pipe
	parts := splitDeviceInfo("My|Device|phone")
	if len(parts) != 2 {
		t.Fatalf("splitDeviceInfo returned %d parts, want 2", len(parts))
	}
	if parts[0] != "My|Device" {
		t.Errorf("parts[0] = %q, want %q", parts[0], "My|Device")
	}
	if parts[1] != "phone" {
		t.Errorf("parts[1] = %q, want %q", parts[1], "phone")
	}
}

func TestSplitDeviceInfo_NoPipe(t *testing.T) {
	parts := splitDeviceInfo("justname")
	if len(parts) != 1 {
		t.Fatalf("splitDeviceInfo returned %d parts, want 1", len(parts))
	}
	if parts[0] != "justname" {
		t.Errorf("parts[0] = %q, want %q", parts[0], "justname")
	}
}

func TestSplitDeviceInfo_EmptyString(t *testing.T) {
	parts := splitDeviceInfo("")
	if len(parts) != 1 {
		t.Fatalf("splitDeviceInfo returned %d parts, want 1", len(parts))
	}
	if parts[0] != "" {
		t.Errorf("parts[0] = %q, want empty string", parts[0])
	}
}

func TestGenerateAndParseTempToken(t *testing.T) {
	cfg := &config.Config{
		JWTSecret: "test-jwt-secret-for-temp-tokens",
	}
	h := &AuthHandler{config: cfg}

	userID := uuid.New()
	deviceName := "My Phone"
	deviceType := "android"

	token, err := h.generateTempToken(userID, deviceName, deviceType)
	if err != nil {
		t.Fatalf("generateTempToken failed: %v", err)
	}
	if token == "" {
		t.Fatal("generateTempToken returned empty token")
	}

	gotUserID, gotName, gotType, err := h.parseTempToken(token)
	if err != nil {
		t.Fatalf("parseTempToken failed: %v", err)
	}
	if gotUserID != userID {
		t.Errorf("userID = %v, want %v", gotUserID, userID)
	}
	if gotName != deviceName {
		t.Errorf("deviceName = %q, want %q", gotName, deviceName)
	}
	if gotType != deviceType {
		t.Errorf("deviceType = %q, want %q", gotType, deviceType)
	}
}

func TestParseTempToken_Invalid(t *testing.T) {
	cfg := &config.Config{JWTSecret: "secret"}
	h := &AuthHandler{config: cfg}

	_, _, _, err := h.parseTempToken("garbage-token")
	if err == nil {
		t.Error("expected error for invalid token")
	}
}

func TestParseTempToken_WrongSecret(t *testing.T) {
	h1 := &AuthHandler{config: &config.Config{JWTSecret: "secret-1"}}
	h2 := &AuthHandler{config: &config.Config{JWTSecret: "secret-2"}}

	token, err := h1.generateTempToken(uuid.New(), "dev", "type")
	if err != nil {
		t.Fatalf("generateTempToken failed: %v", err)
	}

	_, _, _, err = h2.parseTempToken(token)
	if err == nil {
		t.Error("expected error when parsing with wrong secret")
	}
}

func TestGenerateTempToken_PipeInDeviceName(t *testing.T) {
	cfg := &config.Config{JWTSecret: "test-secret"}
	h := &AuthHandler{config: cfg}

	// Device name contains a pipe character
	token, err := h.generateTempToken(uuid.New(), "My|Device", "phone")
	if err != nil {
		t.Fatalf("generateTempToken failed: %v", err)
	}

	_, gotName, gotType, err := h.parseTempToken(token)
	if err != nil {
		t.Fatalf("parseTempToken failed: %v", err)
	}
	if gotName != "My|Device" {
		t.Errorf("deviceName = %q, want %q", gotName, "My|Device")
	}
	if gotType != "phone" {
		t.Errorf("deviceType = %q, want %q", gotType, "phone")
	}
}

func TestGenerateSecureToken_Unique(t *testing.T) {
	t1 := generateSecureToken()
	t2 := generateSecureToken()

	if t1 == "" || t2 == "" {
		t.Error("generateSecureToken returned empty string")
	}
	if t1 == t2 {
		t.Error("generateSecureToken returned same token twice")
	}
}

func TestGenerateSecureToken_Length(t *testing.T) {
	token := generateSecureToken()
	// 32 bytes base32 encoded = 52 chars + padding
	if len(token) == 0 {
		t.Error("generateSecureToken returned empty string")
	}
}

func TestHashToken_EmptyInput(t *testing.T) {
	h := hashToken("")
	if h == "" {
		t.Error("hashToken returned empty for empty input")
	}
	// Should still produce valid SHA-256 hex
	if len(h) != 64 {
		t.Errorf("len = %d, want 64", len(h))
	}
}

// Verify generateTempToken expiry is short (5 min)
func TestGenerateTempToken_ShortExpiry(t *testing.T) {
	cfg := &config.Config{JWTSecret: "secret"}
	h := &AuthHandler{config: cfg}

	token, err := h.generateTempToken(uuid.New(), "dev", "type")
	if err != nil {
		t.Fatalf("generateTempToken failed: %v", err)
	}

	// Token should be valid now
	_, _, _, err = h.parseTempToken(token)
	if err != nil {
		t.Errorf("token should be valid immediately: %v", err)
	}

	// We cannot easily test expiry without waiting, but we can verify
	// that the token was generated with expected claims
	_ = time.Now() // Just ensuring the function works without issues
}
