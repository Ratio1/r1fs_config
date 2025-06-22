#!/usr/bin/env bash
# ipfs-nginx-setup.sh â€” secure nginx reverse-proxy for Kubo 0.35 API
# Usage: sudo ./ipfs-nginx-setup.sh [SERVER_IP] [USER] [PASS]
set -euo pipefail

### ---- 1. Vars & helpers -------------------------------------------------
SERVER_IP="${1:-$(ip route get 1.1.1.1 | awk '{print $7; exit}')}"  # pick first routed IPv4 :contentReference[oaicite:0]{index=0}
BASIC_USER="${2:-r1fs}"

# If $3 is absent ¿ generate a random 24-char password (¿108-bit entropy)
if [[ $# -lt 3 || -z "$3" ]]; then
  BASIC_PASS="$(openssl rand -base64 18 | tr -d '/+=')"
  GEN_PASS=true
else
  BASIC_PASS="$3"
  GEN_PASS=false
fi

# Certificate filenames 
LOCAL_CRT="$PWD/r1fs_cert.crt"                      
LOCAL_KEY="$PWD/r1fs_cert.key"                       
CERT_DIR=/etc/ssl/certs
KEY_DIR=/etc/ssl/private
SYS_CRT="$CERT_DIR/r1fs_cert.crt"
SYS_KEY="$KEY_DIR/r1fs_cert.key"

HTPASS=/etc/nginx/.htpasswd
SITE=/etc/nginx/sites-available/ipfs-api.conf

echo "==> Using public IP  $SERVER_IP"
echo "==> Creating user    $BASIC_USER"
$GEN_PASS && echo "   ¿ Generated password for user '${BASIC_USER}':  ${BASIC_PASS}"

### ---- 2. Install packages ----------------------------------------------
apt-get update -qq
apt-get install -y nginx openssl apache2-utils  # htpasswd lives here :contentReference[oaicite:1]{index=1}

# ---- Kill the port-80 “default” listener -------------------------------
rm -f /etc/nginx/sites-enabled/default  

### ---- 3. Generate self-signed certificate -------------------------------
if [[ ! -f "$LOCAL_CRT" || ! -f "$LOCAL_KEY" ]]; then                
  echo "==> Generating self-signed TLS certificate in $PWD …"
  openssl req -x509 -nodes -newkey rsa:4096 -days 365 \
          -subj "/CN=r1fs" \
          -addext "subjectAltName = DNS:r1fs" \
          -keyout "$LOCAL_KEY" -out "$LOCAL_CRT"
else
  echo "==> Re-using existing $LOCAL_CRT and $LOCAL_KEY"
fi
install -Dm600 "$LOCAL_CRT" "$SYS_CRT"
install -Dm600 "$LOCAL_KEY" "$SYS_KEY"
echo "==> Installed certificate to $SYS_CRT"
echo "==> Installed key         to $SYS_KEY"


### ---- 4. Build bcrypt .htpasswd ----------------------------------------
htpasswd -c -B -b -C 12 "$HTPASS" "$BASIC_USER" "$BASIC_PASS"       # bcrypt cost-factor 12 :contentReference[oaicite:3]{index=3}
chmod 644 "$HTPASS"

### ---- 5. Write nginx vhost ---------------------------------------------
cat >"$SITE"<<EOF
server {
    listen ${SERVER_IP}:5443 ssl http2;
    # --- TLS ----------------------------------------------------------------
    ssl_certificate     $SYS_CRT;
    ssl_certificate_key $SYS_KEY;
    ssl_protocols       TLSv1.3;                                        # TLS 1.3 only :contentReference[oaicite:4]{index=4}
    ssl_conf_command    Ciphersuites TLS_AES_256_GCM_SHA384:TLS_AES_128_GCM_SHA256;
    add_header Strict-Transport-Security "max-age=31536000" always;

    # --- Basic-Auth ---------------------------------------------------------
    auth_basic           "IPFS Private Relay API";
    auth_basic_user_file $HTPASS;                                       # nginx reads bcrypt hashes :contentReference[oaicite:5]{index=5}

    # --- Reverse proxy ------------------------------------------------------
    #proxy_set_header Authorization \$http_authorization;                # pass creds if inner layer is enabled :contentReference[oaicite:6]{index=6}
    #proxy_pass_header   Authorization;

    # Allow only the pin endpoints
    location = /api/v0/pin/add { proxy_pass http://127.0.0.1:5001; }
    location = /api/v0/pin/rm  { proxy_pass http://127.0.0.1:5001; }
    location = /api/v0/version { proxy_pass http://127.0.0.1:5001; }
    location /               { return 403; }                            # everything else forbidden
}
EOF

ln -s "$SITE" /etc/nginx/sites-enabled/ 2>/dev/null || true

### ---- 6. Harden & reload -------------------------------------------------
nginx -t                                              # syntax check :contentReference[oaicite:7]{index=7}
systemctl reload nginx
echo "==> nginx is now serving https://${SERVER_IP}/api/v0/pin/add"