#!/bin/bash
# ============================================================
#  MultiPaper Minecraft Server - Ubuntu Setup Script
#  Installs JDK 17, creates dedicated user, downloads server
#  jar, accepts EULA, and registers a cron job for boot start.
# ============================================================

set -euo pipefail

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

# ── 1. Install Java JDK 17 ──────────────────────────────────
echo "[1/6] Installing OpenJDK 17..."
apt-get update -y
apt-get install -y openjdk-17-jdk wget curl screen

java_version=$(java -version 2>&1 | head -n1)
echo "      Installed: $java_version"

# ── 2. Create dedicated non-root user ───────────────────────
echo "[2/6] Creating dedicated user '$MC_USER'..."
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
echo "[3/6] Setting up server directory at $MC_HOME..."
mkdir -p "$MC_HOME"
chown "$MC_USER":"$MC_USER" "$MC_HOME"

# ── 4. Download the MultiPaper jar ──────────────────────────
echo "[4/6] Downloading MultiPaper jar..."
if [[ -f "$MC_HOME/$JAR_NAME" ]]; then
  echo "      Jar already present — skipping download."
else
  wget -q --show-progress -O "$MC_HOME/$JAR_NAME" "$JAR_URL"
  echo "      Download complete."
fi
chown "$MC_USER":"$MC_USER" "$MC_HOME/$JAR_NAME"

# ── 5. Accept EULA ──────────────────────────────────────────
echo "[5/6] Accepting Minecraft EULA..."
cat > "$MC_HOME/eula.txt" <<EOF
# Minecraft EULA - Auto-accepted by setup script
# https://aka.ms/MinecraftEULA
eula=true
EOF
chown "$MC_USER":"$MC_USER" "$MC_HOME/eula.txt"
echo "      eula.txt written."

# ── 6. Create start script ──────────────────────────────────
echo "[6/6] Writing start script to $START_SCRIPT..."
cat > "$START_SCRIPT" <<'STARTSCRIPT'
#!/bin/bash
# Minecraft Server Start Script
# Runs inside a detached 'screen' session so the server
# survives SSH disconnects and can be re-attached at any time.

MC_HOME="/opt/minecraft"
JAR_NAME="multipaper-1.20.1-60.jar"
SCREEN_NAME="minecraft"
LOG_FILE="$MC_HOME/server.log"

cd "$MC_HOME" || exit 1

# If a screen session already exists, do nothing
if screen -list | grep -q "$SCREEN_NAME"; then
  echo "$(date): Server already running in screen '$SCREEN_NAME'." >> "$LOG_FILE"
  exit 0
fi

echo "$(date): Starting MultiPaper server..." >> "$LOG_FILE"
screen -dmS "$SCREEN_NAME" \
  java -Xms1G -Xmx2G \
       -XX:+UseG1GC \
       -XX:+ParallelRefProcEnabled \
       -XX:MaxGCPauseMillis=200 \
       -jar "$MC_HOME/$JAR_NAME" nogui

echo "$(date): Server started in screen session '$SCREEN_NAME'." >> "$LOG_FILE"
echo "  Attach with:  screen -r $SCREEN_NAME"
echo "  Detach with:  Ctrl+A then D"
STARTSCRIPT

chmod +x "$START_SCRIPT"
chown "$MC_USER":"$MC_USER" "$START_SCRIPT"
echo "      Start script written."

# ── 7. Register cron job (runs at boot as MC_USER) ──────────
echo "[7/7] Installing cron job for $MC_USER..."
CRON_JOB="@reboot sleep 20 && $START_SCRIPT >> /var/log/minecraft_boot.log 2>&1"
CRON_TMP=$(mktemp)

# Preserve any existing crontab for the user, then append our job
crontab -u "$MC_USER" -l 2>/dev/null | grep -v "$START_SCRIPT" > "$CRON_TMP" || true
echo "$CRON_JOB" >> "$CRON_TMP"
crontab -u "$MC_USER" "$CRON_TMP"
rm "$CRON_TMP"
echo "      Cron job registered."

# ── First run ───────────────────────────────────────────────
echo ""
echo "===== Starting server for the first time ====="
sudo -u "$MC_USER" "$START_SCRIPT"

echo ""
echo "====================================================="
echo " Setup complete!  $(date)"
echo "====================================================="
echo ""
echo " Server directory : $MC_HOME"
echo " Start script     : $START_SCRIPT"
echo " Log file         : $LOG_FILE"
echo " Boot cron job    : registered for user '$MC_USER'"
echo ""
echo " Useful commands:"
echo "   Attach to console  : sudo -u $MC_USER screen -r minecraft"
echo "   Detach (keep alive): Ctrl+A then D"
echo "   Stop server        : In console, type 'stop'"
echo "   Manual start       : sudo -u $MC_USER $START_SCRIPT"
echo ""
echo " NOTE: Adjust -Xms / -Xmx in $START_SCRIPT to match your RAM."
echo "====================================================="
