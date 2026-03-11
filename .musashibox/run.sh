#!/bin/bash
set -e

PATH=/usr/local/bin:$PATH

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== musashibox ===${NC}\n"

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
  $SCRIPT_DIR/.musashibox/slack_notif.sh "[musashibox]${PROJECT_NAME}" "Error: SSH key not found at $HOME_DIR/.ssh-keys/" "#E01F4C"
  exit 1
fi

# ========================
# DOCKER Run
# ========================
DOCKER_IMAGE_NAME="musashibox-${PROJECT_NAME}"
DOCKER_TAG_NAME="${DOCKER_IMAGE_NAME}:latest"

if ! command -v docker &> /dev/null; then
  echo -e "${RED}Error: Docker is not installed${NC}"
  $SCRIPT_DIR/.musashibox/slack_notif.sh "[musashibox]${PROJECT_NAME}" "Docker is not installed" "#E01F4C"
  exit 1
fi

# Build
echo -e "${YELLOW}Building image...${NC}"
docker build -t ${DOCKER_TAG_NAME} .
echo -e "${GREEN}Build complete${NC}\n"

# Run
echo -e "${YELLOW}Starting container...${NC}\n"

docker run -i --rm \
    --name ${DOCKER_IMAGE_NAME} \
    --env-file $SCRIPT_DIR/.env \
    -v "$(pwd)/ssh-keys:/home/sandbox/.ssh-keys:ro" \
    ${DOCKER_TAG_NAME}

echo -e "\n${GREEN}Container exited.${NC}"
