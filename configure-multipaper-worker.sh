#!/bin/bash
# ============================================================
#  MultiPaper Minecraft Server - Ubuntu Setup Script
#  Installs JDK 17, creates dedicated user, downloads server
#  jar, accepts EULA, writes multipaper.yml, and registers
#  a cron job for boot start.
#
#  Usage: sudo ./setup_minecraft.sh <master-ip> <server-name>
#  Example: sudo ./setup_minecraft.sh 10.0.0.4 child-1
# ============================================================

set -euo pipefail

# ---------- Arguments ----------
if [[ $# -lt 2 ]]; then
  echo "ERROR: Missing required arguments." >&2
  echo "Usage: $0 <master-ip> <server-name>" >&2
  echo "Example: $0 10.0.0.4 child-1" >&2
  exit 1
fi

MASTER_IP="$1"
SERVER_NAME="$2"

# ---------- Configuration ----------
MC_USER="minecraft"
MC_HOME="/opt/minecraft"
JAR_URL="https://api.multipaper.io/v2/projects/multipaper/versions/1.20.1/builds/60/downloads/multipaper-1.20.1-60.jar"
JAR_NAME="multipaper-1.20.1-60.jar"
START_SCRIPT="$MC_HOME/start.sh"
LOG_FILE="/var/log/minecraft_setup.log"
# -----------------------------------

# Must be run as root
if [[ $EUID -ne 0 ]]; then
  echo "ERROR: Please run this script as root (sudo ./setup_minecraft.sh)" >&2
  exit 1
fi

exec > >(tee -a "$LOG_FILE") 2>&1
echo "===== Minecraft Setup Started: $(date) ====="
echo "      Master IP   : $MASTER_IP"
echo "      Server Name : $SERVER_NAME"

# ── 1. Install Java JDK 17 ──────────────────────────────────
echo "[1/7] Installing OpenJDK 17..."
apt-get update -y
apt-get install -y openjdk-17-jdk wget curl

java_version=$(java -version 2>&1 | head -n1)
echo "      Installed: $java_version"

# ── 2. Create dedicated non-root user ───────────────────────
echo "[2/7] Creating dedicated user '$MC_USER'..."
if id "$MC_USER" &>/dev/null; then
  echo "      User '$MC_USER' already exists — skipping creation."
else
  useradd --system \
          --create-home \
          --home-dir "$MC_HOME" \
          --shell /bin/bash \
          --comment "Minecraft Server User" \
          "$MC_USER"
  echo "      User '$MC_USER' created."
fi

# ── 3. Create server directory ──────────────────────────────
echo "[3/7] Setting up server directory at $MC_HOME..."
mkdir -p "$MC_HOME"
chown "$MC_USER":"$MC_USER" "$MC_HOME"

# ── 4. Download the MultiPaper jar ──────────────────────────
echo "[4/7] Downloading MultiPaper jar..."
if [[ -f "$MC_HOME/$JAR_NAME" ]]; then
  echo "      Jar already present — skipping download."
else
  wget -q --show-progress -O "$MC_HOME/$JAR_NAME" "$JAR_URL"
  echo "      Download complete."
fi
chown "$MC_USER":"$MC_USER" "$MC_HOME/$JAR_NAME"

# ── 5. Accept EULA ──────────────────────────────────────────
echo "[5/7] Accepting Minecraft EULA..."
cat > "$MC_HOME/eula.txt" <<EOF
# Minecraft EULA - Auto-accepted by setup script
# https://aka.ms/MinecraftEULA
eula=true
EOF
chown "$MC_USER":"$MC_USER" "$MC_HOME/eula.txt"
echo "      eula.txt written."

# ── 6. Write multipaper.yml ─────────────────────────────────
echo "[6/7] Writing multipaper.yml..."
cat > "$MC_HOME/multipaper.yml" <<EOF
master-connection:
  advertise-to-built-in-proxy: true
  master-address: ${MASTER_IP}:35353
  my-name: ${SERVER_NAME}
optimizations:
  dont-save-just-for-lighting-updates: false
  max-footstep-packets-sent-per-player: -1
  reduce-player-position-updates-in-unloaded-chunks: false
  ticks-per-inactive-entity-tracking: 1
  use-event-based-io: true
peer-connection:
  compression-threshold: 0
  consolidation-delay: 0
sync-settings:
  files:
    files-to-not-sync:
    - plugins/bStats
    files-to-only-upload-on-server-stop:
    - plugins/MyPluginDirectory/my_big_database.db
    files-to-sync-in-real-time:
    - plugins/MyPluginDirectory/userdata
    files-to-sync-on-startup:
    - myconfigfile.yml
    - plugins/MyPlugin.jar
    log-file-syncs: true
  persistent-player-entity-ids: true
  persistent-vehicle-entity-ids-seconds: 15
  sync-entity-ids: true
  sync-json-files: true
  sync-permissions: false
  sync-scoreboards: true
  use-local-player-count-for-server-is-full-kick: false
EOF
chown "$MC_USER":"$MC_USER" "$MC_HOME/multipaper.yml"
echo "      multipaper.yml written (master: ${MASTER_IP}:35353, name: ${SERVER_NAME})."

# ── 7. Create systemd service ───────────────────────────────
echo "[7/7] Writing systemd service..."
cat > /etc/systemd/system/minecraft.service <<EOF
[Unit]
Description=MultiPaper Minecraft Server
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=${MC_USER}
WorkingDirectory=${MC_HOME}
ExecStart=/usr/bin/java -Xms1G -Xmx2G \
  -XX:+UseG1GC \
  -XX:+ParallelRefProcEnabled \
  -XX:MaxGCPauseMillis=200 \
  -jar ${MC_HOME}/${JAR_NAME} nogui
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=minecraft

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable minecraft.service
systemctl start minecraft.service
echo "      Systemd service enabled and started."

chown -R "$MC_USER":"$MC_USER" "$MC_HOME"
chmod 755 "$MC_HOME"

echo ""
echo "====================================================="
echo " Setup complete!  $(date)"
echo "====================================================="
echo ""
echo " Server directory : $MC_HOME"
echo " Log file         : $LOG_FILE"
echo " Service          : minecraft.service (auto-starts on boot)"
echo ""
echo " Useful commands:"
echo "   Check status   : systemctl status minecraft"
echo "   View logs      : journalctl -u minecraft -f"
echo "   Stop server    : systemctl stop minecraft"
echo "   Start server   : systemctl start minecraft"
echo "   Restart server : systemctl restart minecraft"
echo ""
echo " NOTE: Adjust -Xms / -Xmx in /etc/systemd/system/minecraft.service to match your RAM."
echo "       Run 'systemctl daemon-reload && systemctl restart minecraft' after editing."
echo "====================================================="
