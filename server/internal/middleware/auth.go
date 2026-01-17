package middleware

import (
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
)

var (
	ErrInvalidToken = errors.New("invalid token")
	ErrExpiredToken = errors.New("token expired")
)

// Claims represents JWT claims
type Claims struct {
	UserID   uuid.UUID `json:"user_id"`
	Email    string    `json:"email"`
	DeviceID uuid.UUID `json:"device_id"`
	IsAdmin  bool      `json:"is_admin"`
	jwt.RegisteredClaims
}

// JWTMiddleware creates JWT authentication middleware
func JWTMiddleware(secret string) gin.HandlerFunc {
	return func(c *gin.Context) {
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "authorization header required"})
			c.Abort()
			return
		}

		parts := strings.SplitN(authHeader, " ", 2)
		if len(parts) != 2 || parts[0] != "Bearer" {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid authorization header format"})
			c.Abort()
			return
		}

		claims, err := ValidateToken(parts[1], secret)
		if err != nil {
			if errors.Is(err, ErrExpiredToken) {
				c.JSON(http.StatusUnauthorized, gin.H{"error": "token expired", "code": "TOKEN_EXPIRED"})
			} else {
				c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid token"})
			}
			c.Abort()
			return
		}

		// Store claims in context
		c.Set("user_id", claims.UserID)
		c.Set("email", claims.Email)
		c.Set("device_id", claims.DeviceID)
		c.Set("is_admin", claims.IsAdmin)

		c.Next()
	}
}

// AdminMiddleware requires admin privileges
func AdminMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		isAdmin, exists := c.Get("is_admin")
		if !exists || !isAdmin.(bool) {
			c.JSON(http.StatusForbidden, gin.H{"error": "admin access required"})
			c.Abort()
			return
		}
		c.Next()
	}
}

// GenerateToken generates a new JWT access token
func GenerateToken(userID uuid.UUID, email string, deviceID uuid.UUID, isAdmin bool, secret string, duration time.Duration) (string, error) {
	claims := &Claims{
		UserID:   userID,
		Email:    email,
		DeviceID: deviceID,
		IsAdmin:  isAdmin,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(duration)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			NotBefore: jwt.NewNumericDate(time.Now()),
			Issuer:    "vibedterm",
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString([]byte(secret))
}

// ValidateToken validates a JWT token and returns claims
func ValidateToken(tokenString string, secret string) (*Claims, error) {
	token, err := jwt.ParseWithClaims(tokenString, &Claims{}, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, ErrInvalidToken
		}
		return []byte(secret), nil
	})

	if err != nil {
		if errors.Is(err, jwt.ErrTokenExpired) {
			return nil, ErrExpiredToken
		}
		return nil, ErrInvalidToken
	}

	claims, ok := token.Claims.(*Claims)
	if !ok || !token.Valid {
		return nil, ErrInvalidToken
	}

	return claims, nil
}

// GetUserID extracts user ID from context
func GetUserID(c *gin.Context) (uuid.UUID, error) {
	userID, exists := c.Get("user_id")
	if !exists {
		return uuid.Nil, errors.New("user_id not found in context")
	}
	return userID.(uuid.UUID), nil
}

// GetDeviceID extracts device ID from context
func GetDeviceID(c *gin.Context) (uuid.UUID, error) {
	deviceID, exists := c.Get("device_id")
	if !exists {
		return uuid.Nil, errors.New("device_id not found in context")
	}
	return deviceID.(uuid.UUID), nil
}
