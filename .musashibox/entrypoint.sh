#!/usr/bin/env sh
set -e

PROJECT_DIR="/workspace/project"
child_pid=""
tmp_log="$(mktemp)"
tmp_message="$(mktemp)"

cleanup() {
  status="$1"
  local message=$(cat "$tmp_message" | jq -Rs . | sed 's/^"//;s/"$//')
  local content=$(cat "$tmp_log" | jq -Rs . | sed 's/^"//;s/"$//')

  if [ "$status" -ne 0 ]; then
    ${PROJECT_DIR}/.musashibox/slack_notif.sh "${message}" "Done. Check WORKLOG.md" "#74F40B"
  else
    ${PROJECT_DIR}/.musashibox/slack_notif.sh "${message}" "$content" "#E01F4C"
  fi

  # cat "$tmp_log"
  rm -f "$tmp_log"
}

forward_signal() {
  sig="$1"
  if [ -n "$child_pid" ]; then
    kill "-$sig" "$child_pid" 2>/dev/null || true
  else
    trap - "$sig"
    kill "-$sig" "$$"
  fi
}

trap 'forward_signal TERM' TERM
trap 'forward_signal INT' INT

/usr/local/bin/entrymain.sh "$tmp_message" "$@" 2> "$tmp_log" &
child_pid=$!

status=0
if ! wait "$child_pid"; then
  status=$?
fi

cleanup "$status"
echo "cleanup completed"

exit "$status"
