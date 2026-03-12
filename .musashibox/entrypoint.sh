#!/usr/bin/env sh
set -eu

PROJECT_DIR="/workspace/project"
child_pid=""
tmp_log="$(mktemp)"

cleanup() {
  status="$1"
  local message=$(tail -n1 "$tmp_log")
  local meta="TODO_TYPE=${TODO_TYPE}, TODO_FILE=${TODO_FILE}, GIT_REPO_URL=${GIT_REPO_URL}"

  if [ "$status" -ne 0 ]; then
    ${PROJECT_DIR}/.musashibox/slack_notif.sh "${meta}: ${message}" "$tmp_log" "#E01F4C"
  else
    ${PROJECT_DIR}/.musashibox/slack_notif.sh "${meta}: ${message}" "$tmp_log" "#74F40B"
  fi

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

/usr/local/bin/entrymain.sh "$@" 2> "$tmp_log" &
child_pid=$!

status=0
if ! wait "$child_pid"; then
  status=$?
fi

cleanup "$status"

exit "$status"
