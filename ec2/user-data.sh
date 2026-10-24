
#!/bin/bash
set -euo pipefail

# This script is intended for Amazon Linux 2023.
BUCKET="aws-lab7-cv-ali-2026-unique123"

dnf install -y httpd awscli
systemctl enable --now httpd

cat > /usr/local/bin/cv-sync.sh <<'SYNC_SCRIPT'
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
SYNC_SCRIPT

chmod 755 /usr/local/bin/cv-sync.sh

cat > /etc/systemd/system/cv-sync.service <<'SERVICE'
[Unit]
Description=Sync CV website files from private S3 bucket

[Service]
Type=oneshot
ExecStart=/usr/local/bin/cv-sync.sh
SERVICE

cat > /etc/systemd/system/cv-sync.timer <<'TIMER'
[Unit]
Description=Run CV website S3 sync every five minutes

[Timer]
OnBootSec=1min
OnUnitActiveSec=5min
Unit=cv-sync.service

[Install]
WantedBy=timers.target
TIMER

systemctl daemon-reload
systemctl enable --now cv-sync.timer

# Perform the first sync immediately.
systemctl start cv-sync.service
