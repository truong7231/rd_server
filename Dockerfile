FROM alpine:3.23

ENV TZ=Asia/Ho_Chi_Minh
ENV PORT=8080

ENV DISPLAY=:99
ENV VNC_PORT=5900

# Bật community repo
RUN set -eux; \
  ALPINE_VER="$(cut -d. -f1,2 /etc/alpine-release)"; \
  echo "http://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VER}/main" > /etc/apk/repositories; \
  echo "http://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VER}/community" >> /etc/apk/repositories; \
  apk add --no-cache \
    ca-certificates tzdata \
    xvfb fluxbox \
    x11vnc novnc websockify \
    chromium \
    ttf-dejavu fontconfig \
    netcat-openbsd \
  ; \
  update-ca-certificates

# Ép noVNC dùng đúng websocket path
RUN cat > /usr/share/novnc/index.html <<'HTML'
<!doctype html>
<meta http-equiv="refresh" content="0; url=/vnc.html?path=websockify">
HTML

# Start script nhúng trong Dockerfile
RUN cat > /usr/local/bin/start-gui.sh <<'EOF'
#!/bin/sh
set -eu

echo "TZ=${TZ}"
echo "PORT=${PORT}"
echo "DISPLAY=${DISPLAY}"
echo "VNC_PORT=${VNC_PORT}"

# Cleanup X lock
rm -f /tmp/.X99-lock 2>/dev/null || true
rm -rf /tmp/.X11-unix/X99 2>/dev/null || true
mkdir -p /tmp/.X11-unix

echo "[1/5] Starting Xvfb..."
# Giảm RAM: geometry nhỏ + 16-bit
Xvfb "${DISPLAY}" -screen 0 1024x576x16 -nolisten tcp -ac &
sleep 1

echo "[2/5] Starting window manager (fluxbox)..."
fluxbox &
sleep 1

echo "[3/5] Starting VNC server (x11vnc)..."
# Quan trọng: ép listen IPv4 để tránh lỗi localhost/IPv6
x11vnc \
  -display "${DISPLAY}" \
  -listen 127.0.0.1 \
  -rfbport "${VNC_PORT}" \
  -forever -shared \
  -nopw \
  -noxrecord -noxfixes -noxdamage \
  &
sleep 1

echo "[4/5] Waiting for VNC port 127.0.0.1:${VNC_PORT}..."
for i in $(seq 1 30); do
  if nc -z 127.0.0.1 "${VNC_PORT}"; then
    echo "VNC is up."
    break
  fi
  echo "Still waiting..."
  sleep 1
done

echo "[5/5] Starting noVNC/websockify on 0.0.0.0:${PORT} -> 127.0.0.1:${VNC_PORT}"
# Quan trọng: target là 127.0.0.1 (không dùng localhost)
websockify --web=/usr/share/novnc "0.0.0.0:${PORT}" "127.0.0.1:${VNC_PORT}" &
sleep 1

echo "Starting Chromium (non-headless)..."
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

# Vòng lặp nhẹ: nếu chromium chết thì restart, không spam quá nhanh
while true; do
  chromium $CHROME_FLAGS about:blank || true
  echo "Chromium exited. Restarting in 2s..."
  sleep 2
done
EOF

RUN chmod +x /usr/local/bin/start-gui.sh

# Render sẽ set PORT, nên chỉ cần expose để dễ hiểu (không bắt buộc)
EXPOSE 8080

CMD ["/usr/local/bin/start-gui.sh"]
