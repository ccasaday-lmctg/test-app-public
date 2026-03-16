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
apt-get install -y openjdk-17-jdk wget curl screen

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

# ── 5. Create start script ──────────────────────────────────
echo "[5/5] Writing start script to $START_SCRIPT..."
cat > "$START_SCRIPT" <<'STARTSCRIPT'
#!/bin/bash
# MultiPaper Master Start Script

MC_HOME="/opt/multipaper-master"
JAR_NAME="multipaper-master-2.12.3-all.jar"
SCREEN_NAME="mpm"
LOG_FILE="$MC_HOME/master.log"

cd "$MC_HOME" || exit 1

# If a screen session already exists, do nothing
if screen -list | grep -q "$SCREEN_NAME"; then
  echo "$(date): Master already running in screen '$SCREEN_NAME'." >> "$LOG_FILE"
  exit 0
fi

echo "$(date): Starting MultiPaper Master..." >> "$LOG_FILE"
screen -dmS "$SCREEN_NAME" \
  java -Xms512M -Xmx1G \
       -jar "$MC_HOME/$JAR_NAME"

echo "$(date): Master started in screen session '$SCREEN_NAME'." >> "$LOG_FILE"
echo "  Attach with:  screen -r $SCREEN_NAME"
echo "  Detach with:  Ctrl+A then D"
STARTSCRIPT

chmod +x "$START_SCRIPT"
chown "$MC_USER":"$MC_USER" "$START_SCRIPT"
echo "      Start script written."

# ── Register cron job (runs at boot as MC_USER) ─────────────
echo "Registering cron job for '$MC_USER'..."
CRON_JOB="@reboot sleep 10 && $START_SCRIPT >> /var/log/mpm_boot.log 2>&1"
CRON_TMP=$(mktemp)

crontab -u "$MC_USER" -l 2>/dev/null | grep -v "$START_SCRIPT" > "$CRON_TMP" || true
echo "$CRON_JOB" >> "$CRON_TMP"
crontab -u "$MC_USER" "$CRON_TMP"
rm "$CRON_TMP"
echo "      Cron job registered."

# ── First run ───────────────────────────────────────────────
echo ""
echo "===== Starting MultiPaper Master for the first time ====="
sudo -u "$MC_USER" "$START_SCRIPT"

echo ""
echo "====================================================="
echo " Setup complete!  $(date)"
echo "====================================================="
echo ""
echo " Directory    : $MC_HOME"
echo " Start script : $START_SCRIPT"
echo " Log file     : $LOG_FILE"
echo ""
echo " Useful commands:"
echo "   Attach to console  : sudo -u $MC_USER screen -r mpm"
echo "   Detach (keep alive): Ctrl+A then D"
echo "   Manual start       : sudo -u $MC_USER $START_SCRIPT"
echo ""
echo " NOTE: Master listens on port 35353 by default."
echo "       Ensure this port is open in your firewall/NSG."
echo "====================================================="
