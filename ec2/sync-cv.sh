
#!/bin/bash
set -u

BUCKET="aws-lab7-cv-ali-2026-unique123"
LOG="/var/log/cv-sync.log"
SITE="s3://${BUCKET}/site/"
WEBROOT="/var/www/html"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG"
}

TOKEN=$(curl -fsS -X PUT \
  "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600") || {
    log "sync=FAILED reason=metadata_token"
    exit 1
}

INSTANCE_ID=$(curl -fsS \
  -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id) || {
    log "sync=FAILED reason=instance_id"
    exit 1
}

if ! aws s3 sync "$SITE" "$WEBROOT/"; then
    log "sync=FAILED reason=s3_sync"
    exit 1
fi

if ! grep -Fq '{{HOSTED_ON}}' "$WEBROOT/index.html"; then
    log "sync=FAILED reason=placeholder_missing"
    exit 1
fi

if ! sed -i "s/{{HOSTED_ON}}/EC2 - ${INSTANCE_ID}/g" \
  "$WEBROOT/index.html"; then
    log "sync=FAILED reason=footer_replacement"
    exit 1
fi

log "sync=SUCCESS instance_id=${INSTANCE_ID}"
