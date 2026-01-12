#!/bin/sh

# Script to download and install RGSX, update gamelist.xml, and clean up.
# Designed for Batocera, runs in POSIX-compliant shell.
# Displays messages in console or xterm (DISPLAY mode).

# Variables
URL="https://github.com/RetroGameSets/RGSX/releases/latest/download/RGSX_Full_latest.zip"
DEST_DIR="/userdata/roms"
RGSX_DIR="$DEST_DIR/ports/RGSX"
GAMELIST_FILE="$DEST_DIR/ports/gamelist.xml"
UPDATE_GAMELIST_PY="$RGSX_DIR/update_gamelist.py"
LOG_DIR="$DEST_DIR/ports/RGSX_INSTALL_LOGS"
LOG_FILE="$LOG_DIR/rgsx_install.log"
MODE="${1:-DISPLAY}"
TEXT_SIZE="72"
TEXT_COLOR="green"
DISPLAY_LOG="/tmp/rgsx_install_display.$$"
ZIP_FILE="/tmp/rgsx.$$.zip"

# Function to log with timestamp
log() {
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    printf "[%s] %s\n" "$timestamp" "$*" >> "$LOG_FILE" 2>&1
}

# Function to display messages
console_log() {
    message="[RGSX Install] $*"
    log "$message"
    printf "%s\n" "$message"
    if [ "$MODE" = "DISPLAY" ] && command -v xterm >/dev/null 2>&1; then
        printf "%s\n" "$message" >> "$DISPLAY_LOG"
    fi
}

# Error exit handler
error_exit() {
    log "Fatal Error: $*"
    console_log "Installation error: $*"
    console_log "Read $LOG_FILE for details"
    if [ "$MODE" = "DISPLAY" ] && command -v xterm >/dev/null 2>&1; then
        LC_ALL=C xterm -fullscreen -fg "$TEXT_COLOR" -bg black -fs "$TEXT_SIZE" -e "cat '$DISPLAY_LOG'; echo 'Press a key to exit...'; read -n 1; exit" || true
    fi
    rm -f "$ZIP_FILE" "$DISPLAY_LOG" 2>/dev/null
    exit 1
}

# Cleanup on exit
cleanup() {
    rm -f "$ZIP_FILE" "$DISPLAY_LOG" 2>/dev/null
    if [ -n "${XTERM_PID:-}" ]; then
        kill "$XTERM_PID" 2>/dev/null || true
    fi
}
trap cleanup 0 1 2 3 15

# Check dependencies
for cmd in curl unzip ping rm mkdir chmod find python3 sync ls cat touch; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        error_exit "Missing dependency: $cmd"
    fi
done

# Create directories
mkdir -p "$DEST_DIR/ports" "$LOG_DIR" || error_exit "Cannot create directories: $DEST_DIR/ports or $LOG_DIR"
chmod u+w "$DEST_DIR" "$LOG_DIR" 2>/dev/null || log "Warning: Failed to set directory permissions"

# Setup DISPLAY mode
if [ "$MODE" = "DISPLAY" ]; then
    DISPLAY=:0.0
    LC_ALL=C
    export DISPLAY LC_ALL
    if command -v xterm >/dev/null 2>&1; then
        console_log "Starting RGSX Installation..."
        xterm -fullscreen -fg "$TEXT_COLOR" -bg black -fs "$TEXT_SIZE" -e "tail -f '$DISPLAY_LOG'" &
        XTERM_PID=$!
        sleep 1
    else
        log "xterm not available, falling back to CONSOLE mode."
        MODE="CONSOLE"
    fi
else
    console_log "Starting RGSX Installation..."
fi

# Check internet
ping -c 1 8.8.8.8 >/dev/null 2>&1 || error_exit "No internet connection"

# Download with retries
console_log "Downloading RGSX..."
retries=3
i=1
while [ "$i" -le "$retries" ]; do
    if curl -L -o "$ZIP_FILE" "$URL"; then
        break
    fi
    log "Download attempt $i failed, retrying..."
    sleep 2
    i=$((i + 1))
done
[ -f "$ZIP_FILE" ] || error_exit "Download failed after $retries attempts"

# Verify ZIP
unzip -t "$ZIP_FILE" >/dev/null 2>&1 || error_exit "ZIP file is corrupted"

# Remove old RGSX dir if exists
if [ -d "$RGSX_DIR" ]; then
    rm -rf "$RGSX_DIR" || error_exit "Cannot remove old $RGSX_DIR"
    sync
fi

# Extract
console_log "Extracting files..."
unzip -q -o "$ZIP_FILE" -d "$DEST_DIR" || error_exit "Extraction failed"
[ -d "$RGSX_DIR" ] || error_exit "RGSX directory not found after extraction"

# Set permissions
console_log "Setting permissions..."
find "$RGSX_DIR" -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null || log "Warning: Failed to chmod some .sh files"
if [ -f "$UPDATE_GAMELIST_PY" ]; then
    chmod +x "$UPDATE_GAMELIST_PY" 2>/dev/null || log "Warning: Failed to chmod update_gamelist.py"
else
    error_exit "update_gamelist.py not found"
fi
chmod -R u+rwX "$RGSX_DIR" 2>/dev/null || log "Warning: Failed to set RGSX dir permissions"

# Update gamelist.xml
console_log "Updating gamelist.xml..."
python3 "$UPDATE_GAMELIST_PY" || error_exit "Failed to update gamelist.xml"
chmod 644 "$GAMELIST_FILE" 2>/dev/null || log "Warning: Failed to chmod gamelist.xml"

# Clean unnecessary files
rm -f "$DEST_DIR/RGSX.zip" "$DEST_DIR/windows/RGSX Retrobat.bat" 2>/dev/null

# Finalize
console_log "Install successful in ports system!"
console_log "Please update gamelist in Menu > Games > Update Games List"
log "Installation successful. RGSX added to $GAMELIST_FILE."
curl -s http://127.0.0.1:1234/reloadgames || log "Warning: Failed to reload games list"

if [ "$MODE" = "DISPLAY" ] && command -v xterm >/dev/null 2>&1; then
    kill "$XTERM_PID" 2>/dev/null || true
    LC_ALL=C xterm -fullscreen -fg "$TEXT_COLOR" -bg black -fs "$TEXT_SIZE" -e "cat '$DISPLAY_LOG'; echo 'Installation complete. Press a key to exit...'; read -n 1; exit" || true
fi

# Self-delete
script_file="$DEST_DIR/rgsx-install.sh"
rm -f "$script_file" 2>/dev/null || log "Warning: Failed to self-delete"

exit 0