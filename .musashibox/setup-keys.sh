#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEY_DIR="$SCRIPT_DIR/ssh-keys"
KEY_PATH="$KEY_DIR/id_ed25519"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${GREEN}=== SSH Key Setup ===${NC}\n"

mkdir -p "$KEY_DIR"

if [ -f "$KEY_PATH" ]; then
    echo -e "${YELLOW}SSH key already exists at $KEY_DIR${NC}"
    echo "To regenerate, delete ssh-keys/ and run again."
    echo ""
else
    ssh-keygen -t ed25519 -f "$KEY_PATH" -N "" -C "claude-sandbox@musashibox"
    echo -e "\n${GREEN}SSH key generated.${NC}"
fi

echo -e "${CYAN}============================================================${NC}"
echo -e "${CYAN}  Register this public key as a GitHub Deploy Key${NC}"
echo -e "${CYAN}  (Repo > Settings > Deploy keys > Add > Allow write access)${NC}"
echo -e "${CYAN}============================================================${NC}"
echo ""
cat "$KEY_PATH.pub"
echo ""
echo -e "${CYAN}============================================================${NC}"
echo ""
echo "After registering, run: ./run.sh"
