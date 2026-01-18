#!/bin/bash
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}"
echo "╔═══════════════════════════════════════╗"
echo "║     VibedTerm Server Deployment       ║"
echo "╚═══════════════════════════════════════╝"
echo -e "${NC}"

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    echo -e "${YELLOW}Warning: Running as root. Consider using a non-root user.${NC}"
fi

# Check Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is not installed${NC}"
    exit 1
fi

if ! docker compose version &> /dev/null; then
    echo -e "${RED}Error: Docker Compose is not installed${NC}"
    exit 1
fi

# Check Traefik network
if ! docker network ls | grep -q traefik; then
    echo -e "${YELLOW}Creating traefik network...${NC}"
    docker network create traefik
    echo -e "${GREEN}✓ Traefik network created${NC}"
else
    echo -e "${GREEN}✓ Traefik network exists${NC}"
fi

# Setup .env file
if [ ! -f .env ]; then
    echo -e "${YELLOW}Creating .env file...${NC}"
    cp .env.example .env

    # Generate secure values
    POSTGRES_PW=$(openssl rand -base64 24 | tr -d '/+=' | head -c 32)
    JWT_SECRET=$(openssl rand -base64 32)

    # Update .env with generated values
    sed -i "s/change-me-in-production/$POSTGRES_PW/" .env
    sed -i "s/your-super-secret-jwt-key-change-me/$JWT_SECRET/" .env

    echo -e "${GREEN}✓ Generated secure POSTGRES_PASSWORD${NC}"
    echo -e "${GREEN}✓ Generated secure JWT_SECRET${NC}"
    echo ""
    echo -e "${YELLOW}Please edit .env to set:${NC}"
    echo "  - ADMIN_EMAIL"
    echo "  - ADMIN_PASSWORD"
    echo ""
    read -p "Press Enter after editing .env, or Ctrl+C to abort..."
else
    echo -e "${GREEN}✓ .env file exists${NC}"
fi

# Validate required env vars
source .env
if [ -z "$ADMIN_EMAIL" ] || [ "$ADMIN_EMAIL" = "admin@example.com" ]; then
    echo -e "${RED}Error: Please set ADMIN_EMAIL in .env${NC}"
    exit 1
fi

if [ -z "$ADMIN_PASSWORD" ] || [ "$ADMIN_PASSWORD" = "change-me-immediately" ]; then
    echo -e "${RED}Error: Please set ADMIN_PASSWORD in .env${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Configuration validated${NC}"

# Build and start
echo ""
echo -e "${BLUE}Building and starting services...${NC}"
docker compose -f docker-compose.prod.yml up -d --build

# Wait for health check
echo ""
echo -e "${YELLOW}Waiting for server to be healthy...${NC}"
sleep 5

for i in {1..30}; do
    if docker compose -f docker-compose.prod.yml exec -T server wget -q --spider http://localhost:8080/health 2>/dev/null; then
        echo -e "${GREEN}✓ Server is healthy${NC}"
        break
    fi
    if [ $i -eq 30 ]; then
        echo -e "${RED}Warning: Health check timeout. Check logs with 'make prod-logs'${NC}"
    fi
    sleep 1
done

# Done
echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              Deployment Complete!                         ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  API Health:  https://vibedterm.lab.example.com/health"
echo "  Admin Panel: https://vibedterm.lab.example.com/admin/"
echo ""
echo "  Admin Login: $ADMIN_EMAIL"
echo ""
echo -e "${YELLOW}Useful commands:${NC}"
echo "  make prod-logs    - View logs"
echo "  make prod-update  - Update to latest version"
echo "  make prod-restart - Restart services"
echo ""
