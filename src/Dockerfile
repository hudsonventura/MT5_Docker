FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Update and install core dependencies
RUN apt-get update && apt-get install -y \
    wget \
    curl \
    gnupg2 \
    ca-certificates \
    software-properties-common \
    sudo \
    && rm -rf /var/lib/apt/lists/* 


    

# Install Openbox, VNC, noVNC, and Wine
RUN apt-get update && apt-get install -y --install-recommends \
    openbox \
    obconf \
    tint2 \
    tigervnc-standalone-server \
    websockify \
    python3 \
    python3-numpy \
    x11-apps \
    net-tools \
    dbus-x11 \
    xfonts-base \
    xauth \
    pulseaudio \
    xterm \
    git \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Setup user first
RUN useradd -m -s /bin/bash headless && \
    echo "headless ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Clone noVNC and websockify at stable versions
RUN git clone --branch v1.4.0 --depth 1 https://github.com/novnc/noVNC.git /opt/noVNC && \
    git clone --branch v0.11.0 --depth 1 https://github.com/novnc/websockify.git /opt/noVNC/utils/websockify && \
    chown -R headless:headless /opt/noVNC

# Setup directories
RUN mkdir -p /home/headless/.vnc && \
    mkdir -p /home/headless/.config/openbox && \
    chown -R headless:headless /home/headless




# Add WineHQ repository
RUN dpkg --add-architecture i386 && \
    mkdir -pm755 /etc/apt/keyrings && \
    wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key && \
    wget -NP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/ubuntu/dists/noble/winehq-noble.sources && \
    apt-get update && apt-get install -y --install-recommends winehq-staging


# Copy configuration files
COPY index.html /opt/noVNC/index.html
COPY start.sh /start.sh
COPY build.sh /build.sh

# Make scripts executable and set ownership
RUN chmod +x /start.sh /build.sh && \
    chown headless:headless /opt/noVNC/index.html

USER headless
WORKDIR /home/headless

# Expose VNC and noVNC ports
EXPOSE 5901
EXPOSE 6901

CMD ["/bin/bash", "/start.sh"]
