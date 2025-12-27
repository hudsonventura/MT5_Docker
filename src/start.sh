#!/bin/bash

# Configuration
VNC_PORT=5901
NOVNC_PORT=6901
DISPLAY_NUM=1
RESOLUTION="1280x800"
DEPTH=24

# Set VNC Password
mkdir -p ~/.vnc
echo "${VNC_PW:-password}" | vncpasswd -f > ~/.vnc/passwd
chmod 600 ~/.vnc/passwd

# Clean up existing VNC locks
vncserver -kill :$DISPLAY_NUM 2>/dev/null || true
rm -rf /tmp/.X11-unix/X$DISPLAY_NUM
rm -rf /tmp/.X$DISPLAY_NUM-lock

# Start VNC Server
vncserver :$DISPLAY_NUM -geometry $RESOLUTION -depth $DEPTH -rfbport $VNC_PORT -localhost no

# Export Display
export DISPLAY=:$DISPLAY_NUM

# Wait for X server to be ready
echo "Waiting for X server..."
for i in {1..10}; do
    if xset q > /dev/null 2>&1; then
        echo "X server is ready."
        break
    fi
    sleep 1
done

# Start Openbox in the background
openbox &

# Start tint2 panel (optional, for a taskbar)
tint2 &

# Start noVNC (websockify)
echo "Starting noVNC..."
/opt/noVNC/utils/novnc_proxy --vnc localhost:$VNC_PORT --listen $NOVNC_PORT --web /opt/noVNC &

# Fix ownership of .wine directory (volume mounts may create it as root)
if [ -d "$HOME/.wine" ]; then
    sudo chown -R $(whoami):$(whoami) "$HOME/.wine"
fi

# Initialize Wine properly (this creates the Wine prefix with all necessary files)
echo "Initializing Wine environment..."
WINEDLLOVERRIDES="mscoree,mshtml=" wineboot -i
echo "Waiting for Wine initialization to complete..."
while pgrep -u $(whoami) wineboot >/dev/null; do
    sleep 1
done
echo "Wine initialization complete."

# Paths
MT5_INSTALLER="/home/headless/mt5setup.exe"
WINE_DRIVE_C="$HOME/.wine/drive_c"
MT5_DIR="$WINE_DRIVE_C/Program Files/MetaTrader 5"
MT5_EXE="$MT5_DIR/terminal64.exe"

# Download and Install MT5 if not present
if [ ! -f "$MT5_EXE" ]; then
    echo "MetaTrader 5 not found. Downloading and installing..."
    wget "https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe" -O "$MT5_INSTALLER"
    
    # Run installer
    echo "Installer started. Please connect via noVNC (port 6901) or VNC (port 5901) to complete installation."
    wine "$MT5_INSTALLER" &
    
    # Wait for the installer to finish or for the file to appear
    while [ ! -f "$MT5_EXE" ]; do
        sleep 5
    done
    echo "MetaTrader 5 installed successfully."
fi

# Copy mt5.ini if it exists in home
if [ -f "/home/headless/mt5.ini" ]; then
    echo "Applying mt5.ini configuration..."
    mkdir -p "$MT5_DIR"
    cp "/home/headless/mt5.ini" "$MT5_DIR/mt5.ini"
fi

# Start MetaTrader 5
echo "Starting MetaTrader 5..."
wine "$MT5_EXE" /config:"C:\Program Files\MetaTrader 5\mt5.ini" &
MT5_PID=$!

# Monitor MT5 process
while kill -0 $MT5_PID 2>/dev/null; do
    sleep 10
done

echo "MetaTrader 5 has exited. Shutting down container."
exit 0
