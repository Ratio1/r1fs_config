#!/usr/bin/env bash
# remove-ipfs-nginx.sh — undo the IPFS NGINX reverse-proxy
# Usage: sudo ./remove-ipfs-nginx.sh [--purge]
set -euo pipefail

PURGE=false
[[ "${1:-}" == "--purge" ]] && PURGE=true

SITE=/etc/nginx/sites-available/ipfs-api.conf
ENABLED=/etc/nginx/sites-enabled/ipfs-api.conf
CRT=/etc/ssl/certs/r1fs_cert.crt
KEY=/etc/ssl/private/r1fs_cert.key
HTPASS=/etc/nginx/.htpasswd

echo "==> Stopping NGINX (if running)…"
systemctl stop nginx 2>/dev/null || true

echo "==> Removing IPFS reverse-proxy files…"
rm -f "$ENABLED" "$SITE"              # virtual-host
rm -f "$CRT" "$KEY"                   # self-signed cert
rm -f "$HTPASS"                       # credentials
echo "    ✓ Deleted vhost, cert/key, and .htpasswd"

if $PURGE; then
  echo "==> Purging nginx package (apt)…"
  apt-get -y purge nginx nginx-common
  apt-get -y autoremove --purge
fi


# Reload only if nginx is still installed and its main conf exists
if [[ -f /etc/nginx/nginx.conf ]]; then
  echo "==> Testing core nginx config …"
  if nginx -t; then
    echo "==> Reloading clean nginx config…"
    systemctl reload nginx
  else
    echo "‼️  nginx -t failed – leaving nginx stopped so it won’t start with errors"
    systemctl stop nginx || true
    systemctl disable nginx 2>/dev/null || true
  fi
fi

echo "==> Closing port 443 in the firewall (if UFW present)…"
if command -v ufw >/dev/null 2>&1; then
  ufw --force delete allow 443/tcp || true
fi

echo "==> Removing any raw iptables rule for 443/tcp (optional)…"
iptables -D INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || true

echo "==> Cleanup complete."
if $PURGE; then
  echo "NGINX is fully removed.  Kubo continues to listen only on 127.0.0.1:5001."
else
  echo "NGINX is still installed but inactive.  You can start it later with:"
  echo "  sudo systemctl start nginx"
fi

