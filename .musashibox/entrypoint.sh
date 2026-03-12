#!/usr/bin/env sh
set -e

PROJECT_DIR="/workspace/project"
child_pid=""
tmp_log="$(mktemp)"

cleanup() {
  status="$1"
  local message=$(tail -n1 "$tmp_log")
  local meta="TODO_TYPE=${TODO_TYPE}, TODO_FILE=${TODO_FILE}, GIT_REPO_URL=${GIT_REPO_URL}"

  if [ "$status" -ne 0 ]; then
    ${PROJECT_DIR}/.musashibox/slack_notif.sh "${meta}: ${message}" "$(cat $tmp_log)" "#E01F4C"
  else
    ${PROJECT_DIR}/.musashibox/slack_notif.sh "${meta}: ${message}" "$(cat $tmp_log)" "#74F40B"
  fi

  cat "$tmp_log"
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

/usr/local/bin/entrymain.sh "$@" > "$tmp_log" 2>&1 &
child_pid=$!

status=0
if ! wait "$child_pid"; then
  status=$?
fi

cleanup "$status"
echo "cleanup completed"

exit "$status"
