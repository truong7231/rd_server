FROM alpine:3.23

ENV TZ=Asia/Ho_Chi_Minh
ENV PORT=8080
ENV DISPLAY=:99
ENV VNC_PORT=5900

RUN set -eux; \
  ALPINE_VER="$(cut -d. -f1,2 /etc/alpine-release)"; \
  echo "http://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VER}/main" > /etc/apk/repositories; \
  echo "http://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VER}/community" >> /etc/apk/repositories; \
  apk add --no-cache \
    ca-certificates tzdata \
    # noVNC/websockify
    novnc websockify \
    # VNC server (kèm X server)
    tigervnc \
    # WM (có thể bỏ nếu bạn chấp nhận không có WM; giữ lại cho thao tác ổn định hơn)
    fluxbox \
    # Browser
    chromium \
    # Fonts tối thiểu
    ttf-dejavu fontconfig \
  ; \
  update-ca-certificates

RUN ln -sf /usr/share/novnc/vnc.html /usr/share/novnc/index.html 2>/dev/null || true

RUN cat > /usr/local/bin/start-gui.sh <<'EOF'
#!/bin/sh
set -eu

echo "TZ=${TZ}"
echo "PORT=${PORT}"
echo "DISPLAY=${DISPLAY}"
echo "VNC_PORT=${VNC_PORT}"

# Dọn lock cũ
rm -f /tmp/.X99-lock 2>/dev/null || true
rm -rf /tmp/.X11-unix/X99 2>/dev/null || true
mkdir -p /tmp/.X11-unix

# 1) Start Xvnc (TigerVNC) = X server + VNC server
# Giảm RAM: geometry nhỏ + 16-bit
# SecurityTypes=None để khỏi password (tùy bạn, nhưng free tier thường chỉ cần demo)
echo "Starting Xvnc..."
Xvnc "${DISPLAY}" \
  -geometry 1024x576 \
  -depth 16 \
  -rfbport "${VNC_PORT}" \
  -SecurityTypes None \
  -AlwaysShared=1 \
  -NeverShared=0 \
  -localhost=0 \
  >/dev/null 2>&1 &
sleep 1

# 2) WM (có thể comment dòng này để giảm thêm chút RAM/CPU, nhưng thao tác cửa sổ sẽ khó hơn)
echo "Starting window manager..."
fluxbox >/dev/null 2>&1 &
sleep 1

# 3) noVNC
echo "Starting noVNC on 0.0.0.0:${PORT} -> localhost:${VNC_PORT}"
websockify --web=/usr/share/novnc "0.0.0.0:${PORT}" "localhost:${VNC_PORT}" >/dev/null 2>&1 &

# 4) Chromium low-end flags
# - Giới hạn heap JS: tùy workload, thử 64~128
# - Tắt site isolation để giảm process
# - Giữ cache gần như 0
CHROME_FLAGS="
  --no-sandbox
  --disable-dev-shm-usage
  --disable-gpu
  --disable-extensions
  --disable-background-networking
  --disable-sync
  --disable-component-update
  --disable-crash-reporter
  --metrics-recording-only
  --no-first-run
  --no-zygote
  --disable-features=Translate,BackForwardCache,PreloadMediaEngagementData,MediaRouter,SitePerProcess
  --renderer-process-limit=1
  --disk-cache-size=1
  --media-cache-size=1
  --user-data-dir=/tmp/chrome-profile
  --blink-settings=imagesEnabled=false
  --js-flags=--max-old-space-size=96
  --window-size=1024,576
"

echo "Starting Chromium (non-headless)..."
# Chạy 1 lần; nếu crash mới restart (tránh loop liên tục ăn CPU)
while true; do
  chromium $CHROME_FLAGS about:blank >/dev/null 2>&1 || true
  sleep 2
done
EOF

RUN chmod +x /usr/local/bin/start-gui.sh
CMD ["/usr/local/bin/start-gui.sh"]
