#!/bin/bash

# ============================================================
# MT5 Docker - Startup Script
# ============================================================
# All Wine/X11 noise is redirected to /tmp/wine.log
# Only clean step-by-step progress is shown in console
# ============================================================

WINE_LOG="/tmp/wine.log"
> "$WINE_LOG"  # Clear log file

# ============================================================
# Step display functions with spinner
# Each spinner frame ends with \n so Docker flushes it,
# and uses ANSI cursor-up (\033[1A) to overwrite the previous frame.
# ============================================================
STEP_NUM=0
TOTAL_STEPS=9
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

# Function to download servers.dat
download_servers_dat() {
    mkdir -p "$MT5_DIR/Config"
    wget -q "https://github.com/hudsonventura/MT5_Docker/raw/refs/heads/main/servers.dat" -O "$SERVERS_DAT" 2>>"$WINE_LOG"
}

# ============================================================
# Configuration
# ============================================================
VNC_PORT=5901
NOVNC_PORT=6901
DISPLAY_NUM=1
RESOLUTION="1280x800"
DEPTH=24

# Paths
MT5_INSTALLER="/home/headless/mt5setup.exe"
MT5_DIR="/home/headless/.wine/drive_c/Program Files/MetaTrader 5"
MT5_WIN_DIR="C:\Program Files\MetaTrader 5"
MT5_EXE="$MT5_DIR/terminal64.exe"
SERVERS_DAT="$MT5_DIR/Config/servers.dat"
MIN_SIZE=1048576  # 1MB in bytes

echo ""
echo "  ╔══════════════════════════════════════════════╗"
echo "  ║ MT5 Docker - Run MetaTrader 5 in a Container ║"
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
export DISPLAY=:$DISPLAY_NUM

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
# Step 5: Initialize Wine
# ============================================================
step_start "Initializing Wine environment. This may take some time. Please be patient."

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
# Step 7: Apply configuration
# ============================================================
step_start "Applying configuration"



sleep 1
step_done "Configuration applied"


# ============================================================
# Step 8: Check servers.dat
# ============================================================
step_start "Checking servers.dat"
if [ -f "$SERVERS_DAT" ]; then
    FILE_SIZE=$(stat -c%s "$SERVERS_DAT" 2>/dev/null || echo 0)
    if [ "$FILE_SIZE" -ge "$MIN_SIZE" ]; then
        step_done "servers.dat OK ($(( FILE_SIZE / 1024 ))KB)"
    else
        download_servers_dat
        step_done "servers.dat downloaded"
    fi
else
    download_servers_dat
    step_done "servers.dat downloaded"
fi



# ============================================================
# Step 9: Start MetaTrader 5
# ============================================================
step_start "Starting MetaTrader 5"

# Keep wineserver alive to prevent premature exit of Wine processes
wineserver -p >>"$WINE_LOG" 2>&1 &

wine "$MT5_EXE" /config:"$MT5_WIN_DIR\mt5.ini" >>"$WINE_LOG" 2>&1 &
MT5_PID=$!

# Wait for MT5 process to appear
WAIT_TIMEOUT=120
WAIT_COUNT=0
MT5_STARTED=false
while [ "$WAIT_COUNT" -lt "$WAIT_TIMEOUT" ]; do
    if pgrep -f "terminal64.exe" > /dev/null 2>&1; then
        MT5_STARTED=true
        break
    fi
    if ! kill -0 $MT5_PID 2>/dev/null; then
        break
    fi
    sleep 2
    WAIT_COUNT=$((WAIT_COUNT + 2))
done

if [ "$MT5_STARTED" = true ]; then
    step_done "MetaTrader 5 started"
else
    step_fail "MetaTrader 5 failed to start (check $WINE_LOG)"
fi



# ============================================================
# Ready!
# ============================================================
echo ""
echo "  ╔══════════════════════════════════════════════╗"
echo "  ║              ✔  Ready!                       ║"
echo "  ╠══════════════════════════════════════════════╣"
echo "  ║  VNC:   localhost:$VNC_PORT                       ║"
echo "  ║  Web:   http://localhost:$NOVNC_PORT/vnc.html       ║"
echo "  ║  Pass:  ${VNC_PW:-password}                      ║"
echo "  ╠══════════════════════════════════════════════╣"
echo "  ║  Logs:  $WINE_LOG                        ║"
echo "  ╚══════════════════════════════════════════════╝"
echo ""
echo "  Press Ctrl-C to stop the container."
echo ""

# ============================================================
# Monitor MT5 process
# ============================================================
while true; do
    MT5_RUNNING=false

    # Check if the wine launcher process is still alive
    if kill -0 $MT5_PID 2>/dev/null; then
        MT5_RUNNING=true
    fi

    # Check for terminal64.exe by name (case-insensitive)
    if pgrep -fi "terminal64" > /dev/null 2>&1; then
        MT5_RUNNING=true
    fi

    # Check if MT5 installer is running
    if pgrep -fi "mt5setup" > /dev/null 2>&1; then
        MT5_RUNNING=true
    fi

    # Check if any wine process is running (fallback)
    if pgrep -x "wine" > /dev/null 2>&1 || pgrep -x "wine64" > /dev/null 2>&1 || pgrep -f "wine-preloader" > /dev/null 2>&1 || pgrep -f "wine64-preloader" > /dev/null 2>&1; then
        MT5_RUNNING=true
    fi

    # If nothing is running, exit
    if [ "$MT5_RUNNING" = false ]; then
        break
    fi

    sleep 10
done

echo ""
echo "  MetaTrader 5 has exited. Shutting down container."
exit 0