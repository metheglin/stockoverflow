#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TODO_DIR="$SCRIPT_DIR/todo"

# Search for inprogress files
inprogress_files=()
while IFS= read -r -d '' f; do
  inprogress_files+=("$f")
done < <(find "$TODO_DIR" -maxdepth 1 -name '*_inprogress.md' -print0 2>/dev/null | sort -z)

if [ ${#inprogress_files[@]} -gt 0 ]; then
  file="${inprogress_files[0]}"
  basename_file="$(basename "$file")"
  # Extract TODO_TYPE: second to last segment when split by '_'
  # Format: {YYYYmmdd}_{HHMM}_{TODO_TITLE}_{TODO_TYPE}_{TODO_STATUS}.md
  todo_type="$(echo "$basename_file" | rev | cut -d'_' -f2 | rev)"
  rel_path="todo/$basename_file"
  echo "${todo_type}:${rel_path}"
  exit 0
fi

# Search for pending files
pending_files=()
while IFS= read -r -d '' f; do
  pending_files+=("$f")
done < <(find "$TODO_DIR" -maxdepth 1 -name '*_pending.md' -print0 2>/dev/null | sort -z)

pending_count=${#pending_files[@]}

if [ "$pending_count" -ge 5 ]; then
  # 5 or more pending files: exit silently
  exit 0
fi

# Fewer than 5 pending files: return THINK
echo "THINK:"
