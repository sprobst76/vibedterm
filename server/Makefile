.PHONY: help build run dev test clean tidy
.PHONY: docker-build docker-up docker-down db-up db-down
.PHONY: prod prod-up prod-stop prod-restart prod-logs prod-shell db-shell prod-update setup

# Default target
help:
	@echo "VibedTerm Server Makefile"
	@echo ""
	@echo "Local Development:"
	@echo "  make build        - Build the server binary"
	@echo "  make run          - Build and run the server"
	@echo "  make dev          - Run with hot reload (requires air)"
	@echo "  make test         - Run tests"
	@echo "  make clean        - Remove build artifacts"
	@echo "  make tidy         - Tidy go modules"
	@echo ""
	@echo "Docker (Development):"
	@echo "  make db-up        - Start PostgreSQL for development"
	@echo "  make db-down      - Stop PostgreSQL"
	@echo "  make docker-build - Build Docker image"
	@echo "  make docker-up    - Start all services (dev)"
	@echo "  make docker-down  - Stop all services"
	@echo ""
	@echo "Production (VPS):"
	@echo "  make setup        - Initial setup (create .env)"
	@echo "  make prod         - Build and start production stack"
	@echo "  make prod-up      - Start without rebuild"
	@echo "  make prod-stop    - Stop production stack"
	@echo "  make prod-restart - Restart production stack"
	@echo "  make prod-update  - Pull latest and redeploy"
	@echo "  make prod-logs    - Follow logs"
	@echo "  make prod-shell   - Shell into server container"
	@echo "  make db-shell     - PostgreSQL shell"

# ============================================
# Local Development
# ============================================

build:
	go build -o bin/server ./cmd/server

run: build
	./bin/server

# Development mode (requires air: go install github.com/cosmtrek/air@latest)
dev:
	air

test:
	go test -v ./...

clean:
	rm -rf bin/
	go clean

tidy:
	go mod tidy

# ============================================
# Docker (Development)
# ============================================

docker-build:
	docker build -t vibedterm-server .

docker-up:
	docker compose up -d

docker-down:
	docker compose down

db-up:
	docker compose -f docker-compose.dev.yml up -d
	@echo "PostgreSQL running on localhost:5432"

db-down:
	docker compose -f docker-compose.dev.yml down

# ============================================
# Production (VPS)
# ============================================

setup:
	@if [ -f .env ]; then \
		echo "⚠️  .env already exists. Remove it first to reset."; \
	else \
		cp .env.example .env; \
		echo "✅ Created .env from .env.example"; \
		echo ""; \
		echo "Edit .env and set secure values:"; \
		echo "  POSTGRES_PASSWORD  - Database password"; \
		echo "  JWT_SECRET         - Run: openssl rand -base64 32"; \
		echo "  ADMIN_EMAIL        - Your admin email"; \
		echo "  ADMIN_PASSWORD     - Secure admin password"; \
	fi

prod:
	docker compose -f docker-compose.prod.yml up -d --build
	@echo ""
	@echo "✅ VibedTerm is running!"
	@echo "   Health: https://vibedterm.lab.$${DOMAIN:-example.com}/health"
	@echo "   Admin:  https://vibedterm.lab.$${DOMAIN:-example.com}/admin/"

prod-up:
	docker compose -f docker-compose.prod.yml up -d

prod-stop:
	docker compose -f docker-compose.prod.yml down

prod-restart:
	docker compose -f docker-compose.prod.yml restart

prod-update:
	@echo "📦 Pulling latest changes..."
	git pull
	@echo "🔨 Rebuilding and restarting..."
	docker compose -f docker-compose.prod.yml up -d --build
	@echo "✅ Update complete!"

prod-logs:
	docker compose -f docker-compose.prod.yml logs -f

prod-shell:
	docker compose -f docker-compose.prod.yml exec server sh

db-shell:
	docker compose -f docker-compose.prod.yml exec postgres psql -U vibedterm

prod-clean:
	docker compose -f docker-compose.prod.yml down -v
	@echo "🗑️  Containers and volumes removed"
