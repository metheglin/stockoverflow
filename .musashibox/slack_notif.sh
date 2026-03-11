#!/usr/bin/env bash
set -u

# * * * * * * * * * * * * * * * * * * * * * * * * 
# Please set SLACK_WEBHOOK_URL in musashibox .env
# * * * * * * * * * * * * * * * * * * * * * * * * 

# Green: #74F40B
# Yello: #F6C709
# Red: #E01F4C

SUBJECT=${1}
CONTENT=${2}
COLOR=${3:-"#74F40B"}
PAYLOAD=$(cat <<EOF
{
  "text": "$SUBJECT",
  "attachments": [
    {
      "color": "$COLOR",
      "text": "$CONTENT"
    }
  ]
}
EOF
)
echo $SLACK_WEBHOOK_URL
echo "${PAYLOAD}"

curl -X POST -H 'Content-type: application/json' --data "${PAYLOAD}" "${SLACK_WEBHOOK_URL}"
