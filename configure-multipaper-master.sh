#!/bin/bash
# ============================================================
#  MultiPaper Master - Ubuntu Setup Script
#  Installs JDK 17, creates dedicated user, downloads the
#  MultiPaper Master jar, and registers a cron job for boot.
# ============================================================

set -euo pipefail

# ---------- Configuration ----------
MC_USER="mpm"
MC_HOME="/opt/multipaper-master"
JAR_URL="https://api.multipaper.io/v2/projects/multipaper/versions/1.20.1/builds/60/downloads/multipaper-master-2.12.3-all.jar"
JAR_NAME="multipaper-master-2.12.3-all.jar"
START_SCRIPT="$MC_HOME/start.sh"
LOG_FILE="/var/log/multipaper_master_setup.log"
# -----------------------------------

# Must be run as root
if [[ $EUID -ne 0 ]]; then
  echo "ERROR: Please run this script as root (sudo ./setup_multipaper_master.sh)" >&2
  exit 1
fi

exec > >(tee -a "$LOG_FILE") 2>&1
echo "===== MultiPaper Master Setup Started: $(date) ====="

# ── 1. Install Java JDK 17 ──────────────────────────────────
echo "[1/5] Installing OpenJDK 17..."
apt-get update -y
apt-get install -y openjdk-17-jdk wget curl

java_version=$(java -version 2>&1 | head -n1)
echo "      Installed: $java_version"

# ── 2. Create dedicated non-root user ───────────────────────
echo "[2/5] Creating dedicated user '$MC_USER'..."
if id "$MC_USER" &>/dev/null; then
  echo "      User '$MC_USER' already exists — skipping creation."
else
  useradd --system \
          --create-home \
          --home-dir "$MC_HOME" \
          --shell /bin/bash \
          --comment "MultiPaper Master User" \
          "$MC_USER"
  echo "      User '$MC_USER' created."
fi

# ── 3. Create server directory ──────────────────────────────
echo "[3/5] Setting up directory at $MC_HOME..."
mkdir -p "$MC_HOME"
chown "$MC_USER":"$MC_USER" "$MC_HOME"

# ── 4. Download the MultiPaper Master jar ───────────────────
echo "[4/5] Downloading MultiPaper Master jar..."
if [[ -f "$MC_HOME/$JAR_NAME" ]]; then
  echo "      Jar already present — skipping download."
else
  wget -q --show-progress -O "$MC_HOME/$JAR_NAME" "$JAR_URL"
  echo "      Download complete."
fi
chown "$MC_USER":"$MC_USER" "$MC_HOME/$JAR_NAME"

# ── 5. Create systemd service ───────────────────────────────
echo "[5/5] Writing systemd service..."
cat > /etc/systemd/system/multipaper-master.service <<EOF
[Unit]
Description=MultiPaper Master
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=${MC_USER}
WorkingDirectory=${MC_HOME}
ExecStart=/usr/bin/java -Xms512M -Xmx1G \
  -jar ${MC_HOME}/${JAR_NAME}
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=multipaper-master

[Install]
WantedBy=multi-user.target
EOF

chown -R "$MC_USER":"$MC_USER" "$MC_HOME"
chmod 755 "$MC_HOME"

systemctl daemon-reload
systemctl enable multipaper-master.service
systemctl start multipaper-master.service
echo "      Systemd service enabled and started."

echo ""
echo "====================================================="
echo " Setup complete!  $(date)"
echo "====================================================="
echo ""
echo " Directory : $MC_HOME"
echo " Log file  : $LOG_FILE"
echo " Service   : multipaper-master.service (auto-starts on boot)"
echo ""
echo " Useful commands:"
echo "   Check status   : systemctl status multipaper-master"
echo "   View logs      : journalctl -u multipaper-master -f"
echo "   Stop           : systemctl stop multipaper-master"
echo "   Start          : systemctl start multipaper-master"
echo "   Restart        : systemctl restart multipaper-master"
echo ""
echo " NOTE: Master listens on port 35353 by default."
echo "       Ensure this port is open in your firewall/NSG."
echo "====================================================="
