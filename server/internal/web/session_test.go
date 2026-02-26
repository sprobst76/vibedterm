package web

import (
	"testing"
	"time"

	"github.com/google/uuid"
)

func TestSessionStore_CreateAndGet(t *testing.T) {
	store := &SessionStore{
		sessions: make(map[string]*Session),
		duration: time.Hour,
	}

	userID := uuid.New()
	email := "test@example.com"

	session, err := store.Create(userID, email, true, false)
	if err != nil {
		t.Fatalf("Create failed: %v", err)
	}

	if session.ID == "" {
		t.Error("session ID is empty")
	}
	if session.UserID != userID {
		t.Errorf("UserID = %v, want %v", session.UserID, userID)
	}
	if session.Email != email {
		t.Errorf("Email = %q, want %q", session.Email, email)
	}
	if !session.IsAdmin {
		t.Error("IsAdmin = false, want true")
	}
	if session.TOTPPending {
		t.Error("TOTPPending = true, want false")
	}

	// Get should return the same session
	got := store.Get(session.ID)
	if got == nil {
		t.Fatal("Get returned nil for existing session")
	}
	if got.ID != session.ID {
		t.Errorf("Get returned session with ID %q, want %q", got.ID, session.ID)
	}
	if got.UserID != userID {
		t.Errorf("Get returned session with UserID %v, want %v", got.UserID, userID)
	}
}

func TestSessionStore_CreateWithTOTP(t *testing.T) {
	store := &SessionStore{
		sessions: make(map[string]*Session),
		duration: time.Hour,
	}

	session, err := store.Create(uuid.New(), "user@test.com", false, true)
	if err != nil {
		t.Fatalf("Create failed: %v", err)
	}

	if !session.TOTPPending {
		t.Error("TOTPPending = false, want true (totpRequired was true)")
	}
	if session.IsFullyAuthenticated() {
		t.Error("IsFullyAuthenticated should be false when TOTP is pending")
	}
}

func TestSessionStore_GetNonExistent(t *testing.T) {
	store := &SessionStore{
		sessions: make(map[string]*Session),
		duration: time.Hour,
	}

	got := store.Get("nonexistent-id")
	if got != nil {
		t.Errorf("Get returned %v for nonexistent session, want nil", got)
	}
}

func TestSessionStore_ExpiredSession(t *testing.T) {
	store := &SessionStore{
		sessions: make(map[string]*Session),
		duration: time.Millisecond, // Very short duration
	}

	session, err := store.Create(uuid.New(), "test@test.com", false, false)
	if err != nil {
		t.Fatalf("Create failed: %v", err)
	}

	// Wait for expiry
	time.Sleep(5 * time.Millisecond)

	got := store.Get(session.ID)
	if got != nil {
		t.Error("Get returned non-nil for expired session, want nil")
	}
}

func TestSessionStore_Delete(t *testing.T) {
	store := &SessionStore{
		sessions: make(map[string]*Session),
		duration: time.Hour,
	}

	session, err := store.Create(uuid.New(), "test@test.com", false, false)
	if err != nil {
		t.Fatalf("Create failed: %v", err)
	}

	// Verify it exists
	if store.Get(session.ID) == nil {
		t.Fatal("session should exist before delete")
	}

	store.Delete(session.ID)

	got := store.Get(session.ID)
	if got != nil {
		t.Error("Get returned non-nil after Delete, want nil")
	}
}

func TestSessionStore_DeleteNonExistent(t *testing.T) {
	store := &SessionStore{
		sessions: make(map[string]*Session),
		duration: time.Hour,
	}

	// Should not panic
	store.Delete("nonexistent")
}

func TestSessionStore_UpgradeFromTOTP(t *testing.T) {
	store := &SessionStore{
		sessions: make(map[string]*Session),
		duration: time.Hour,
	}

	session, err := store.Create(uuid.New(), "user@test.com", true, true)
	if err != nil {
		t.Fatalf("Create failed: %v", err)
	}

	if !session.TOTPPending {
		t.Fatal("precondition: TOTPPending should be true")
	}
	if session.IsFullyAuthenticated() {
		t.Fatal("precondition: should not be fully authenticated")
	}

	ok := store.UpgradeFromTOTP(session.ID)
	if !ok {
		t.Error("UpgradeFromTOTP returned false, want true")
	}

	// Re-fetch from store
	got := store.Get(session.ID)
	if got == nil {
		t.Fatal("session not found after upgrade")
	}
	if got.TOTPPending {
		t.Error("TOTPPending = true after upgrade, want false")
	}
	if !got.IsFullyAuthenticated() {
		t.Error("IsFullyAuthenticated = false after upgrade, want true")
	}
}

func TestSessionStore_UpgradeNonExistent(t *testing.T) {
	store := &SessionStore{
		sessions: make(map[string]*Session),
		duration: time.Hour,
	}

	ok := store.UpgradeFromTOTP("nonexistent")
	if ok {
		t.Error("UpgradeFromTOTP returned true for nonexistent session, want false")
	}
}

func TestSessionStore_UpgradeExpired(t *testing.T) {
	store := &SessionStore{
		sessions: make(map[string]*Session),
		duration: time.Millisecond,
	}

	session, err := store.Create(uuid.New(), "test@test.com", false, true)
	if err != nil {
		t.Fatalf("Create failed: %v", err)
	}

	time.Sleep(5 * time.Millisecond)

	ok := store.UpgradeFromTOTP(session.ID)
	if ok {
		t.Error("UpgradeFromTOTP returned true for expired session, want false")
	}
}

func TestSession_IsValid(t *testing.T) {
	s := &Session{ExpiresAt: time.Now().Add(time.Hour)}
	if !s.IsValid() {
		t.Error("IsValid = false for future expiry, want true")
	}

	s.ExpiresAt = time.Now().Add(-time.Hour)
	if s.IsValid() {
		t.Error("IsValid = true for past expiry, want false")
	}
}

func TestSession_IsFullyAuthenticated(t *testing.T) {
	tests := []struct {
		name        string
		expiresAt   time.Time
		totpPending bool
		want        bool
	}{
		{"valid no totp", time.Now().Add(time.Hour), false, true},
		{"valid totp pending", time.Now().Add(time.Hour), true, false},
		{"expired no totp", time.Now().Add(-time.Hour), false, false},
		{"expired totp pending", time.Now().Add(-time.Hour), true, false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			s := &Session{
				ExpiresAt:   tt.expiresAt,
				TOTPPending: tt.totpPending,
			}
			if got := s.IsFullyAuthenticated(); got != tt.want {
				t.Errorf("IsFullyAuthenticated = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestSessionStore_MultipleSessions(t *testing.T) {
	store := &SessionStore{
		sessions: make(map[string]*Session),
		duration: time.Hour,
	}

	s1, _ := store.Create(uuid.New(), "user1@test.com", false, false)
	s2, _ := store.Create(uuid.New(), "user2@test.com", true, false)

	got1 := store.Get(s1.ID)
	got2 := store.Get(s2.ID)

	if got1 == nil || got2 == nil {
		t.Fatal("one or both sessions not found")
	}
	if got1.Email != "user1@test.com" {
		t.Errorf("session 1 email = %q, want %q", got1.Email, "user1@test.com")
	}
	if got2.Email != "user2@test.com" {
		t.Errorf("session 2 email = %q, want %q", got2.Email, "user2@test.com")
	}

	// Delete one, other should still exist
	store.Delete(s1.ID)
	if store.Get(s1.ID) != nil {
		t.Error("session 1 should be deleted")
	}
	if store.Get(s2.ID) == nil {
		t.Error("session 2 should still exist")
	}
}

func TestGenerateSessionID(t *testing.T) {
	id1, err := generateSessionID()
	if err != nil {
		t.Fatalf("generateSessionID failed: %v", err)
	}
	id2, err := generateSessionID()
	if err != nil {
		t.Fatalf("generateSessionID failed: %v", err)
	}

	if id1 == "" || id2 == "" {
		t.Error("generateSessionID returned empty string")
	}
	if id1 == id2 {
		t.Error("generateSessionID returned same ID twice")
	}
	// 32 bytes hex = 64 chars
	if len(id1) != 64 {
		t.Errorf("session ID length = %d, want 64", len(id1))
	}
}
