#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== musashibox-claude ===${NC}\n"

# ========================
# musashibox ENV Variables
# ========================
if [ -f "$SCRIPT_DIR/.env" ]; then
  set -a
  . "$SCRIPT_DIR/.env"
  set +a
fi

# ========================
# SSH Setup
# ========================
if [ ! -f "ssh-keys/id_ed25519" ]; then
    echo -e "${RED}Error: SSH key not found!${NC}"
    echo ""
    echo "  Run ./setup-keys.sh first to generate SSH keys,"
    echo "  then register the public key on GitHub."
    exit 1
fi

# ========================
# DOCKER Run
# ========================
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is not installed${NC}"
    exit 1
fi

# Build
echo -e "${YELLOW}Building image...${NC}"
docker build -t musashibox-claude:latest .
echo -e "${GREEN}Build complete${NC}\n"

# Run
echo -e "${YELLOW}Starting container...${NC}\n"

docker run -it --rm \
    --name musashibox-claude \
    -e CLAUDE_CODE_OAUTH_TOKEN -e GIT_REPO_URL \
    -e CLAUDE_CODE_EFFORT_LEVEL -e ANTHROPIC_MODEL \
    -v "$(pwd)/ssh-keys:/home/sandbox/.ssh-keys:ro" \
    musashibox-claude:latest

echo -e "\n${GREEN}Container exited.${NC}"
