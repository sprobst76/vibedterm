package web

import (
	"crypto/rand"
	"encoding/hex"
	"sync"
	"time"

	"github.com/google/uuid"
)

// Session represents an admin session
type Session struct {
	ID          string
	UserID      uuid.UUID
	Email       string
	IsAdmin     bool
	TOTPPending bool // true if TOTP verification is still needed
	CreatedAt   time.Time
	ExpiresAt   time.Time
}

// IsValid checks if the session is still valid
func (s *Session) IsValid() bool {
	return time.Now().Before(s.ExpiresAt)
}

// IsFullyAuthenticated checks if session completed TOTP verification (if required)
func (s *Session) IsFullyAuthenticated() bool {
	return s.IsValid() && !s.TOTPPending
}

// SessionStore manages admin sessions in memory
type SessionStore struct {
	mu       sync.RWMutex
	sessions map[string]*Session
	duration time.Duration
}

// NewSessionStore creates a new session store with the given session duration
func NewSessionStore(duration time.Duration) *SessionStore {
	store := &SessionStore{
		sessions: make(map[string]*Session),
		duration: duration,
	}
	// Start cleanup goroutine
	go store.cleanup()
	return store
}

// Create creates a new session for a user
func (s *SessionStore) Create(userID uuid.UUID, email string, isAdmin bool, totpRequired bool) (*Session, error) {
	sessionID, err := generateSessionID()
	if err != nil {
		return nil, err
	}

	session := &Session{
		ID:          sessionID,
		UserID:      userID,
		Email:       email,
		IsAdmin:     isAdmin,
		TOTPPending: totpRequired,
		CreatedAt:   time.Now(),
		ExpiresAt:   time.Now().Add(s.duration),
	}

	s.mu.Lock()
	s.sessions[sessionID] = session
	s.mu.Unlock()

	return session, nil
}

// Get retrieves a session by ID
func (s *SessionStore) Get(sessionID string) *Session {
	s.mu.RLock()
	defer s.mu.RUnlock()

	session, exists := s.sessions[sessionID]
	if !exists || !session.IsValid() {
		return nil
	}
	return session
}

// UpgradeFromTOTP marks the session as fully authenticated after TOTP verification
func (s *SessionStore) UpgradeFromTOTP(sessionID string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()

	session, exists := s.sessions[sessionID]
	if !exists || !session.IsValid() {
		return false
	}

	session.TOTPPending = false
	// Extend session after successful TOTP
	session.ExpiresAt = time.Now().Add(s.duration)
	return true
}

// Delete removes a session
func (s *SessionStore) Delete(sessionID string) {
	s.mu.Lock()
	delete(s.sessions, sessionID)
	s.mu.Unlock()
}

// cleanup periodically removes expired sessions
func (s *SessionStore) cleanup() {
	ticker := time.NewTicker(10 * time.Minute)
	defer ticker.Stop()

	for range ticker.C {
		s.mu.Lock()
		for id, session := range s.sessions {
			if !session.IsValid() {
				delete(s.sessions, id)
			}
		}
		s.mu.Unlock()
	}
}

// generateSessionID creates a cryptographically random session ID
func generateSessionID() (string, error) {
	bytes := make([]byte, 32)
	if _, err := rand.Read(bytes); err != nil {
		return "", err
	}
	return hex.EncodeToString(bytes), nil
}
