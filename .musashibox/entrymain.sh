#!/bin/bash
set -e

HOME_DIR="/home/sandbox"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

PROJECT_DIR="/workspace/project"
tmp_message=${1}

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  musashibox Starting ${date}           ${NC}"
echo -e "${CYAN}========================================${NC}"

# -----------------------------------------
# Step 1: SSH config (keys are mounted from host)
# -----------------------------------------
echo -e "\n${YELLOW}[1/4] SSH setup...${NC}"

if [ ! -f "$HOME_DIR/.ssh-keys/id_ed25519" ]; then
  echo -e "${RED}  Error: SSH key not found at $HOME_DIR/.ssh-keys/${NC}" >&2
  echo "SSH key not found: Run setup-keys.sh on the host first." | tee -a $tmp_message
  exit 2
fi

mkdir -p "$HOME_DIR/.ssh"
cp "$HOME_DIR/.ssh-keys/id_ed25519"     "$HOME_DIR/.ssh/id_ed25519"
cp "$HOME_DIR/.ssh-keys/id_ed25519.pub" "$HOME_DIR/.ssh/id_ed25519.pub"
chmod 700 "$HOME_DIR/.ssh"
chmod 600 "$HOME_DIR/.ssh/id_ed25519"
chmod 644 "$HOME_DIR/.ssh/id_ed25519.pub"

cat > "$HOME_DIR/.ssh/config" << 'SSHEOF'
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking accept-new
SSHEOF
chmod 600 "$HOME_DIR/.ssh/config"

echo -e "${GREEN}  SSH configured${NC}"

# -----------------------------------------
# Step 3: Git Repository
# -----------------------------------------
echo -e "\n${YELLOW}[3/4] Git repository...${NC}"

git config --global user.email "musashibox@example.com"
git config --global user.name "musashibox"
ssh-keyscan -H github.com >> ~/.ssh/known_hosts

if [ -n "$GIT_REPO_URL" ]; then
  if [ -d "$PROJECT_DIR/.git" ]; then
    echo "  Pulling latest..."
    cd "$PROJECT_DIR"
    git pull origin "$(git rev-parse --abbrev-ref HEAD)" || echo "  Note: pull failed, continuing with local"
    echo -e "${GREEN}  Repository updated${NC}"
  else
    echo "  Cloning $GIT_REPO_URL ..."
    rm -rf "$PROJECT_DIR"
    git clone "$GIT_REPO_URL" "$PROJECT_DIR"
    echo -e "${GREEN}  Repository cloned${NC}"
  fi
else
  echo "  No GIT_REPO_URL set, skipping."
  mkdir -p "$PROJECT_DIR"
fi

cd "$PROJECT_DIR"

echo -e "\n${CYAN}========================================${NC}"
echo -e "${CYAN}  Launching Claude Code CLI${NC}"
echo -e "${CYAN}========================================${NC}\n"


# 1) find_next_todo.sh を実行して出力を受け取る
OUT="$("${PROJECT_DIR}/.musashibox/find_next_todo.sh")"
echo $OUT

[ -n "${OUT}" ] || {
  # echo "Nothing to do 🙄 Please review pending todos." | tee -a $tmp_message >&2
  echo "Nothing to do 🙄 Please review pending todos." | tee -a $tmp_message
  exit 1
}

# 2) 「:」で分割して TODO_TYPE / TODO_FILE に入れる
#    例: DEVELOP:path/to/todo1.md
TODO_TYPE="$(echo $OUT | cut -d: -f1)"
TODO_FILE="$(echo $OUT | cut -d: -f2)"

echo "$TODO_TYPE `$TODO_FILE` " >> $tmp_message

# 3) TODO_TYPE に応じて出力
case "${TODO_TYPE}" in
  PLAN)
    COMMAND="TODO_TYPE=${TODO_TYPE}, TODO_FILE=${TODO_FILE} として、TODO_FILEの指示にしたがって開発計画を作成せよ"
    exec claude --dangerously-skip-permissions -p "$COMMAND"
    ;;
  DEVELOP)
    COMMAND="TODO_TYPE=${TODO_TYPE}, TODO_FILE=${TODO_FILE} として、TODO_FILEの指示にしたがって実装・テスト・修正を実行せよ"
    exec claude --dangerously-skip-permissions -p "$COMMAND"
    ;;
  THINK)
    COMMAND="TODO_TYPE=${TODO_TYPE} として、TODOを作成せよ"
    exec claude --dangerously-skip-permissions -p "$COMMAND"
    ;;
  *)
    echo "Unknown TODO_TYPE=${TODO_TYPE}" | tee -a $tmp_message
    exit 3
    :
    ;;
esac
