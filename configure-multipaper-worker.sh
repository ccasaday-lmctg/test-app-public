#!/bin/bash
# ============================================================
#  MultiPaper Minecraft Server - Ubuntu Setup Script
#  Installs JDK 17, creates dedicated user, downloads server
#  jar, accepts EULA, writes multipaper.yml, downloads
#  CoreProtect plugin, writes CoreProtect config, and
#  registers a systemd service for boot start.
#
#  Usage: sudo ./setup_minecraft.sh <master-ip> <server-name> \
#                <mysql-server> <mysql-db> <mysql-user> <mysql-password>
#  Example: sudo ./setup_minecraft.sh 10.0.0.4 child-1 \
#                db.example.com minecraft_db mc_user s3cur3pass
# ============================================================

set -euo pipefail

# ---------- Arguments ----------
if [[ $# -lt 6 ]]; then
  echo "ERROR: Missing required arguments." >&2
  echo "Usage: $0 <master-ip> <server-name> <mysql-server> <mysql-db> <mysql-user> <mysql-password>" >&2
  echo "Example: $0 10.0.0.4 child-1 db.example.com minecraft_db mc_user s3cur3pass" >&2
  exit 1
fi

MASTER_IP="$1"
SERVER_NAME="$2"
MYSQL_SERVER="$3"
MYSQL_DB="$4"
MYSQL_USERNAME="$5"
MYSQL_PASSWORD="$6"

# ---------- Configuration ----------
MC_USER="minecraft"
MC_HOME="/opt/minecraft"
JAR_URL="https://api.multipaper.io/v2/projects/multipaper/versions/1.20.1/builds/60/downloads/multipaper-1.20.1-60.jar"
JAR_NAME="multipaper-1.20.1-60.jar"
COREPROTECT_URL="https://cdn.modrinth.com/data/Lu3KuzdV/versions/HD2IvrxS/CoreProtect-CE-23.1.jar"
COREPROTECT_JAR="CoreProtect-CE-23.1.jar"
LOG_FILE="/var/log/minecraft_setup.log"
# -----------------------------------

# Must be run as root
if [[ $EUID -ne 0 ]]; then
  echo "ERROR: Please run this script as root (sudo ./setup_minecraft.sh)" >&2
  exit 1
fi

exec > >(tee -a "$LOG_FILE") 2>&1
echo "===== Minecraft Setup Started: $(date) ====="
echo "      Master IP    : $MASTER_IP"
echo "      Server Name  : $SERVER_NAME"
echo "      MySQL Server : $MYSQL_SERVER"
echo "      MySQL DB     : $MYSQL_DB"

# ── 1. Install Java JDK 17 ──────────────────────────────────
echo "[1/8] Installing OpenJDK 17..."
apt-get update -y
apt-get install -y openjdk-17-jdk wget curl

java_version=$(java -version 2>&1 | head -n1)
echo "      Installed: $java_version"

# ── 2. Create dedicated non-root user ───────────────────────
echo "[2/8] Creating dedicated user '$MC_USER'..."
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
echo "[3/8] Setting up server directory at $MC_HOME..."
mkdir -p "$MC_HOME"
chown "$MC_USER":"$MC_USER" "$MC_HOME"

# ── 4. Download the MultiPaper jar ──────────────────────────
echo "[4/8] Downloading MultiPaper jar..."
if [[ -f "$MC_HOME/$JAR_NAME" ]]; then
  echo "      Jar already present — skipping download."
else
  wget -q --show-progress -O "$MC_HOME/$JAR_NAME" "$JAR_URL"
  echo "      Download complete."
fi
chown "$MC_USER":"$MC_USER" "$MC_HOME/$JAR_NAME"

# ── 5. Accept EULA ──────────────────────────────────────────
echo "[5/8] Accepting Minecraft EULA..."
cat > "$MC_HOME/eula.txt" <<EOF
# Minecraft EULA - Auto-accepted by setup script
# https://aka.ms/MinecraftEULA
eula=true
EOF
chown "$MC_USER":"$MC_USER" "$MC_HOME/eula.txt"
echo "      eula.txt written."

# ── 6. Write multipaper.yml ─────────────────────────────────
echo "[6/8] Writing multipaper.yml..."
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

# ── 7. Download CoreProtect plugin ──────────────────────────
echo "[7/8] Downloading CoreProtect plugin..."
mkdir -p "$MC_HOME/plugins/CoreProtect"
if [[ -f "$MC_HOME/plugins/$COREPROTECT_JAR" ]]; then
  echo "      CoreProtect jar already present — skipping download."
else
  wget -q --show-progress -O "$MC_HOME/plugins/$COREPROTECT_JAR" "$COREPROTECT_URL"
  echo "      CoreProtect download complete."
fi

cat > "$MC_HOME/plugins/CoreProtect/config.yml" <<EOF
# CoreProtect Config

# CoreProtect is donationware. Obtain a donation key from coreprotect.net/donate/
donation-key: 

# MySQL is optional and not required.
# If you prefer to use MySQL, enable the following and fill out the fields.
use-mysql: true
table-prefix: co_
mysql-host: ${MYSQL_SERVER}
mysql-port: 3306
mysql-database: ${MYSQL_DB}
mysql-username: ${MYSQL_USERNAME}
mysql-password: ${MYSQL_PASSWORD}

# If modified, will automatically attempt to translate languages phrases.
# List of language codes: https://coreprotect.net/languages/
language: en

# If enabled, CoreProtect will check for updates when your server starts up.
# If an update is available, you'll be notified via your server console.
check-updates: true

# If enabled, other plugins will be able to utilize the CoreProtect API.
api-enabled: true

# If enabled, extra data is displayed during rollbacks and restores.
# Can be manually triggered by adding "#verbose" to your rollback command.
verbose: true

# If no radius is specified in a rollback or restore, this value will be
# used as the radius. Set to "0" to disable automatically adding a radius.
default-radius: 10

# The maximum radius that can be used in a command. Set to "0" to disable.
# To run a rollback or restore without a radius, you can use "r:#global".
max-radius: 100

# If enabled, items taken from containers (etc) will be included in rollbacks.
rollback-items: true

# If enabled, entities, such as killed animals, will be included in rollbacks.
rollback-entities: true

# If enabled, generic data, like zombies burning in daylight, won't be logged.
skip-generic-data: true

# Logs blocks placed by players.
block-place: true

# Logs blocks broken by players.
block-break: true

# Logs blocks that break off of other blocks; for example, a sign or torch
# falling off of a dirt block that a player breaks. This is required for
# beds/doors to properly rollback.
natural-break: true

# Properly track block movement, such as sand or gravel falling.
block-movement: true

# Properly track blocks moved by pistons.
pistons: true

# Logs blocks that burn up in a fire.
block-burn: true

# Logs when a block naturally ignites, such as from fire spreading.
block-ignite: true

# Logs explosions, such as TNT and Creepers.
explosions: true

# Track when an entity changes a block, such as an Enderman destroying blocks.
entity-change: true

# Logs killed entities, such as killed cows and enderman.
entity-kills: true

# Logs text on signs. If disabled, signs will be blank when rolled back.
sign-text: true

# Logs lava and water sources placed/removed by players who are using buckets.
buckets: true

# Logs natural tree leaf decay.
leaf-decay: true

# Logs tree growth. Trees are linked to the player who planted the sapling.
tree-growth: true

# Logs mushroom growth.
mushroom-growth: true

# Logs natural vine growth.
vine-growth: true

# Logs the spread of sculk blocks from sculk catalysts.
sculk-spread: true

# Logs when portals such as Nether portals generate naturally.
portals: true

# Logs water flow. If water destroys other blocks, such as torches,
# this allows it to be properly rolled back.
water-flow: true

# Logs lava flow. If lava destroys other blocks, such as torches,
# this allows it to be properly rolled back.
lava-flow: true

# Allows liquid to be properly tracked and linked to players.
# For example, if a player places water which flows and destroys torches,
# it can all be properly restored by rolling back that single player.
liquid-tracking: true

# Track item transactions, such as when a player takes items from
# a chest, furnace, or dispenser.
item-transactions: true

# Logs items dropped by players.
item-drops: true

# Logs items picked up by players.
item-pickups: true

# Track all hopper transactions, such as when a hopper removes items from a
# chest, furnace, or dispenser.
hopper-transactions: true

# Track player interactions, such as when a player opens a door, presses
# a button, or opens a chest. Player interactions can't be rolled back.
player-interactions: true

# Logs messages that players send in the chat.
player-messages: true

# Logs all commands used by players.
player-commands: true

# Logs the logins and logouts of players.
player-sessions: true

# Logs when a player changes their Minecraft username.
username-changes: true

# Logs changes made via the plugin "WorldEdit" if it's in use on your server.
worldedit: true
EOF
echo "      CoreProtect config.yml written."

# ── 8. Create systemd service ───────────────────────────────
echo "[8/8] Writing systemd service..."
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
