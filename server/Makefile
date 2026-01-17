.PHONY: help build run dev test clean docker-build docker-up docker-down db-up db-down tidy

# Default target
help:
	@echo "VibedTerm Server Makefile"
	@echo ""
	@echo "Usage:"
	@echo "  make build       - Build the server binary"
	@echo "  make run         - Build and run the server"
	@echo "  make dev         - Run in development mode with hot reload"
	@echo "  make test        - Run tests"
	@echo "  make clean       - Remove build artifacts"
	@echo "  make tidy        - Tidy go modules"
	@echo ""
	@echo "Docker:"
	@echo "  make docker-build - Build Docker image"
	@echo "  make docker-up    - Start all services with Docker Compose"
	@echo "  make docker-down  - Stop all services"
	@echo "  make db-up        - Start only PostgreSQL (for development)"
	@echo "  make db-down      - Stop PostgreSQL"

# Build the server
build:
	go build -o bin/server ./cmd/server

# Run the server
run: build
	./bin/server

# Development mode (requires air: go install github.com/cosmtrek/air@latest)
dev:
	air

# Run tests
test:
	go test -v ./...

# Clean build artifacts
clean:
	rm -rf bin/
	go clean

# Tidy modules
tidy:
	go mod tidy

# Docker commands
docker-build:
	docker build -t vibedterm-server .

docker-up:
	docker-compose up -d

docker-down:
	docker-compose down

# Development database
db-up:
	docker-compose -f docker-compose.dev.yml up -d

db-down:
	docker-compose -f docker-compose.dev.yml down
