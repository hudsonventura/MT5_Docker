#!/bin/bash

# ============================================================
# MT5 Docker - Build Script (Compile MQL5 Experts)
# ============================================================
# Downloads and installs MetaTrader 5 if not present,
# then runs MetaEditor64.exe to compile MQL5 expert files.
# All Wine/X11 noise is redirected to /tmp/wine.log
# ============================================================

WINE_LOG="/tmp/wine.log"
> "$WINE_LOG"  # Clear log file

# ============================================================
# Step display functions with spinner
# ============================================================
STEP_NUM=0
TOTAL_STEPS=8
SPINNER_PID=""

spinner_start() {
    local msg="$1"
    (
        local spin_chars='|/-\'
        local first=true
        local i=0
        while true; do
            local char="${spin_chars:$i:1}"
            if [ "$first" = true ]; then
                printf " [%d/%d] %s %-45s\n" "$STEP_NUM" "$TOTAL_STEPS" "$char" "$msg ..."
                first=false
            else
                printf "\033[1A\r [%d/%d] %s %-45s\n" "$STEP_NUM" "$TOTAL_STEPS" "$char" "$msg ..."
            fi
            sleep 0.2
            i=$(( (i + 1) % ${#spin_chars} ))
        done
    ) &
    SPINNER_PID=$!
}

spinner_stop() {
    if [ -n "$SPINNER_PID" ]; then
        kill "$SPINNER_PID" 2>/dev/null
        wait "$SPINNER_PID" 2>/dev/null
        SPINNER_PID=""
    fi
}

step_start() {
    STEP_NUM=$((STEP_NUM + 1))
    spinner_start "$1"
}

step_done() {
    spinner_stop
    printf "\033[1A\r [%d/%d] ✔  %-45s\n" "$STEP_NUM" "$TOTAL_STEPS" "$1"
}

step_fail() {
    spinner_stop
    printf "\033[1A\r [%d/%d] ✘  %-45s\n" "$STEP_NUM" "$TOTAL_STEPS" "$1"
}

# ============================================================
# Configuration
# ============================================================
VNC_PORT=5901
NOVNC_PORT=6901
DISPLAY_NUM=1
RESOLUTION=800x600
DEPTH=24
export DISPLAY=:$DISPLAY_NUM

# Paths
MT5_INSTALLER="/home/headless/mt5setup.exe"
MT5_DIR="/home/headless/.wine/drive_c/Program Files/MetaTrader 5"
MT5_EXE="$MT5_DIR/terminal64.exe"
METAEDITOR_EXE="$MT5_DIR/MetaEditor64.exe"

echo ""
echo "  ╔══════════════════════════════════════════════╗"
echo "  ║   MT5 Docker - MQL5 Experts Compile          ║"
echo "  ╚══════════════════════════════════════════════╝"
echo ""

# ============================================================
# Step 1: Check Wine
# ============================================================
step_start "Checking Wine"
if command -v wine &> /dev/null; then
    WINE_VER=$(wine --version 2>>"$WINE_LOG")
    step_done "Wine OK ($WINE_VER)"
else
    step_fail "Wine is not installed"
    exit 1
fi

# ============================================================
# Step 2: Start VNC Server
# ============================================================
step_start "Starting VNC server"
mkdir -p ~/.vnc
echo "${VNC_PW:-password}" | vncpasswd -f > ~/.vnc/passwd 2>>"$WINE_LOG"
chmod 600 ~/.vnc/passwd

# Clean up existing VNC locks
vncserver -kill :$DISPLAY_NUM 2>/dev/null || true
rm -rf /tmp/.X11-unix/X$DISPLAY_NUM
rm -rf /tmp/.X$DISPLAY_NUM-lock

vncserver :$DISPLAY_NUM -geometry $RESOLUTION -depth $DEPTH -rfbport $VNC_PORT -localhost no >>"$WINE_LOG" 2>&1

# Wait for X server
for i in {1..10}; do
    if xset q > /dev/null 2>&1; then
        break
    fi
    sleep 1
done
step_done "VNC server started (port $VNC_PORT)"

# ============================================================
# Step 3: Start Desktop Environment
# ============================================================
step_start "Starting desktop environment"
openbox >>"$WINE_LOG" 2>&1 &
tint2 >>"$WINE_LOG" 2>&1 &
sleep 1
step_done "Desktop environment started"

# ============================================================
# Step 4: Start noVNC
# ============================================================
step_start "Starting noVNC web client"
/opt/noVNC/utils/novnc_proxy --vnc localhost:$VNC_PORT --listen $NOVNC_PORT --web /opt/noVNC >>"$WINE_LOG" 2>&1 &
sleep 1
step_done "noVNC started (port $NOVNC_PORT)"

# ============================================================
# Step 5: Initialize Wine environment
# ============================================================
step_start "Initializing Wine environment"

# Fix ownership of .wine directory (volume mounts may create it as root)
if [ -d "$HOME/.wine" ]; then
    sudo chown -R $(whoami):$(whoami) "$HOME/.wine" 2>>"$WINE_LOG"
fi

WINEDLLOVERRIDES="mscoree,mshtml=" wineboot -i >>"$WINE_LOG" 2>&1
while pgrep -u $(whoami) wineboot >/dev/null 2>&1; do
    sleep 1
done
step_done "Wine environment initialized"

# ============================================================
# Step 6: Install MetaTrader 5 (if needed)
# ============================================================
if [ ! -f "$MT5_EXE" ]; then
    step_start "Downloading MetaTrader 5 installer"
    wget -q "https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe" -O "$MT5_INSTALLER" 2>>"$WINE_LOG"
    step_done "MT5 installer downloaded"

    step_start "Installing MetaTrader 5 (silent mode)"
    wine "$MT5_INSTALLER" /auto >>"$WINE_LOG" 2>&1 &

    # Wait for the installer to finish
    while [ ! -f "$MT5_EXE" ]; do
        sleep 10
    done
    step_done "MetaTrader 5 installed"
    STEP_NUM=$((STEP_NUM - 1))  # Adjust for the extra step
else
    step_start "Checking MetaTrader 5 installation"
    sleep 1
    step_done "MetaTrader 5 already installed"
fi

# ============================================================
# Step 7: Kill MetaTrader 5 and installer processes
# ============================================================
step_start "Stopping MetaTrader 5 processes"

# Kill terminal64.exe if running
pkill -fi "terminal64" 2>/dev/null || true
# Kill the installer if still running
pkill -fi "mt5setup" 2>/dev/null || true
# Kill any MetaEditor if running
pkill -fi "metaeditor" 2>/dev/null || true

# Wait for processes to die
sleep 3

# Force kill if still around
pkill -9 -fi "terminal64" 2>/dev/null || true
pkill -9 -fi "mt5setup" 2>/dev/null || true
pkill -9 -fi "metaeditor" 2>/dev/null || true

sleep 2
step_done "MetaTrader 5 processes stopped"

# ============================================================
# Step 8: Compile MQL5 Experts with MetaEditor64
# ============================================================
step_start "Compiling MQL5 Experts"

if [ ! -f "$METAEDITOR_EXE" ]; then
    step_fail "MetaEditor64.exe not found at $METAEDITOR_EXE"
    exit 1
fi

wine 'C:/Program Files/MetaTrader 5/MetaEditor64.exe' /compile:'C:/MQL5/Experts/' /include:'C:/MQL5/' /log >>"$WINE_LOG" 2>&1
COMPILE_EXIT=$?

if [ $COMPILE_EXIT -eq 0 ]; then
    step_done "MQL5 Experts compiled successfully"
else
    step_fail "MQL5 compilation failed (exit code: $COMPILE_EXIT)"
fi

# ============================================================
# Done!
# ============================================================
echo ""
echo "  ╔══════════════════════════════════════════════╗"
echo "  ║         ✔  Build Complete!                    ║"
echo "  ╠══════════════════════════════════════════════╣"
echo "  ║  Logs:  $WINE_LOG                        ║"
echo "  ╚══════════════════════════════════════════════╝"
echo ""

# Show compilation log if it exists
if [ -f "$WINE_LOG" ]; then
    echo "  Compilation log:"
    echo "  ─────────────────────────────────────────────"
    grep -i -E "(compil|error|warning|result)" "$WINE_LOG" 2>/dev/null | tail -20 | sed 's/^/  /'
    echo ""
fi

exit $COMPILE_EXIT
