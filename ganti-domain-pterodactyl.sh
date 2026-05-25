#!/bin/bash

# ============================================================
#   Script Ganti Domain Pterodactyl Panel
#   by rizxddev - github.com/rizxddev/GDPTL
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

NGINX_CONF=""
OLD_DOMAIN=""
NEW_DOMAIN=""
ROLLBACK_DONE=0

ok()   { echo -e "${GREEN}    [OK] $1${NC}"; }
err()  { echo -e "${RED}    [ERROR] $1${NC}"; }
warn() { echo -e "${YELLOW}    [WARN] $1${NC}"; }
info() { echo -e "${CYAN}[*] $1${NC}"; }

# ── Rollback ─────────────────────────────────────────────────
rollback() {
  if [ $ROLLBACK_DONE -eq 1 ]; then return; fi
  ROLLBACK_DONE=1
  echo ""
  warn "Terjadi error — menjalankan rollback..."

  if [ -f "${NGINX_CONF}.bak" ]; then
    cp "${NGINX_CONF}.bak" "$NGINX_CONF"
    systemctl reload nginx 2>/dev/null
    ok "Nginx config dikembalikan ke semula"
  fi

  if [ -f /var/www/pterodactyl/.env.bak ]; then
    cp /var/www/pterodactyl/.env.bak /var/www/pterodactyl/.env
    ok ".env dikembalikan ke semula"
  fi

  err "Script dihentikan. Semua perubahan dibatalkan."
  exit 1
}
trap rollback ERR

# ── Cek root ─────────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
  err "Jalankan script ini sebagai root!"
  exit 1
fi

echo ""
echo -e "${BOLD}===== GANTI DOMAIN PTERODACTYL PANEL =====${NC}"
echo -e "${BOLD}===== by rizxddev                      =====${NC}"
echo ""

# ── Cek dependency ───────────────────────────────────────────
info "Mengecek dependency..."

# Nginx
if ! command -v nginx &>/dev/null; then
  err "Nginx tidak ditemukan!"
  exit 1
fi
ok "Nginx ditemukan"

# Certbot
if ! command -v certbot &>/dev/null; then
  err "Certbot tidak ditemukan! Install dulu: apt install certbot python3-certbot-nginx"
  exit 1
fi
ok "Certbot ditemukan"

# Pterodactyl
if [ ! -f /var/www/pterodactyl/.env ]; then
  err "File .env Pterodactyl tidak ditemukan di /var/www/pterodactyl/"
  exit 1
fi
ok "Pterodactyl ditemukan"

# PHP-FPM
PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null)
if [ -z "$PHP_VERSION" ]; then
  err "PHP tidak ditemukan!"
  exit 1
fi
ok "PHP $PHP_VERSION ditemukan"

if ! systemctl is-active --quiet php${PHP_VERSION}-fpm; then
  err "PHP-FPM $PHP_VERSION tidak aktif! Jalankan: systemctl start php${PHP_VERSION}-fpm"
  exit 1
fi
ok "PHP-FPM $PHP_VERSION aktif"

# ── Auto detect Nginx config ──────────────────────────────────
info "Mencari Nginx config Pterodactyl..."

OLD_DOMAIN=$(grep "^APP_URL=" /var/www/pterodactyl/.env | sed 's|APP_URL=https\?://||' | tr -d '\r')

if [ -n "$OLD_DOMAIN" ]; then
  NGINX_CONF=$(grep -rl "$OLD_DOMAIN" /etc/nginx/sites-enabled/ 2>/dev/null | head -1)
fi

if [ -z "$NGINX_CONF" ]; then
  # Coba cari file yang ada root pterodactyl
  NGINX_CONF=$(grep -rl "pterodactyl" /etc/nginx/sites-enabled/ 2>/dev/null | head -1)
fi

if [ -z "$NGINX_CONF" ]; then
  err "Nginx config untuk Pterodactyl tidak ditemukan di /etc/nginx/sites-enabled/"
  err "Pastikan panel sudah terinstall dengan benar."
  exit 1
fi
ok "Config ditemukan: $NGINX_CONF"

echo ""
echo -e "${YELLOW}Domain lama:${NC} ${OLD_DOMAIN:-tidak terdeteksi}"
echo ""

# ── Input domain baru ────────────────────────────────────────
read -p "$(echo -e ${BOLD}"Masukkan domain baru: "${NC})" NEW_DOMAIN

if [ -z "$NEW_DOMAIN" ]; then
  err "Domain tidak boleh kosong!"
  exit 1
fi

# Validasi format domain (sederhana)
if [[ ! "$NEW_DOMAIN" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
  err "Format domain tidak valid: $NEW_DOMAIN"
  exit 1
fi

echo ""
echo -e "${YELLOW}Domain baru:${NC} $NEW_DOMAIN"
read -p "Lanjutkan? (y/n): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  echo "Dibatalkan."
  exit 0
fi

echo ""

# ── Validasi DNS sebelum lanjut ───────────────────────────────
info "Validasi DNS $NEW_DOMAIN..."

VPS_IP=$(curl -4 -s --max-time 5 ifconfig.me 2>/dev/null)
DNS_IP=$(dig +short "$NEW_DOMAIN" @8.8.8.8 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)

if [ -z "$DNS_IP" ]; then
  err "Domain $NEW_DOMAIN tidak resolve ke IP apapun!"
  err "Pastikan A Record sudah dibuat di DNS provider kamu."
  exit 1
fi

ok "DNS resolve ke: $DNS_IP"

if [ -n "$VPS_IP" ] && [ "$DNS_IP" != "$VPS_IP" ]; then
  warn "IP VPS ($VPS_IP) tidak sama dengan IP DNS ($DNS_IP)"
  warn "SSL mungkin gagal dibuat. Lanjutkan tetap? (y/n): "
  read -r FORCE
  if [[ "$FORCE" != "y" && "$FORCE" != "Y" ]]; then
    echo "Dibatalkan."
    exit 0
  fi
else
  ok "DNS sudah pointing ke IP VPS ($VPS_IP)"
fi

echo ""

# ── Backup ───────────────────────────────────────────────────
info "Membuat backup..."
cp "$NGINX_CONF" "${NGINX_CONF}.bak"
cp /var/www/pterodactyl/.env /var/www/pterodactyl/.env.bak
ok "Backup dibuat: ${NGINX_CONF}.bak & .env.bak"

echo ""

# ── Step 1: Update .env ──────────────────────────────────────
info "[1/5] Update APP_URL di .env..."
sed -i "s|^APP_URL=.*|APP_URL=https://$NEW_DOMAIN|" /var/www/pterodactyl/.env
# Verifikasi
NEW_URL=$(grep "^APP_URL=" /var/www/pterodactyl/.env)
if [[ "$NEW_URL" != "APP_URL=https://$NEW_DOMAIN" ]]; then
  err "Gagal update .env!"
  rollback
fi
ok ".env diperbarui"

# ── Step 2: Update Nginx config ──────────────────────────────
info "[2/5] Update konfigurasi Nginx..."

# Ganti domain lama dengan domain baru
if [ -n "$OLD_DOMAIN" ]; then
  sed -i "s|$OLD_DOMAIN|$NEW_DOMAIN|g" "$NGINX_CONF"
fi

# Hapus SSL lines lama certbot agar bisa di-generate ulang
sed -i '/ssl_certificate/d' "$NGINX_CONF"
sed -i '/ssl_dhparam/d' "$NGINX_CONF"
sed -i '/options-ssl-nginx/d' "$NGINX_CONF"
sed -i '/listen.*443.*ssl/d' "$NGINX_CONF"
sed -i '/ipv6only=on/d' "$NGINX_CONF"
sed -i '/# managed by Certbot/d' "$NGINX_CONF"

# Pastikan ada listen 80 di server block utama
if ! grep -q "listen 80" "$NGINX_CONF"; then
  sed -i "/server_name $NEW_DOMAIN/a\\    listen 80;" "$NGINX_CONF"
fi

ok "Nginx config diperbarui"

# ── Step 3: Test & Reload Nginx ──────────────────────────────
info "[3/5] Test & reload Nginx..."
NGINX_TEST=$(nginx -t 2>&1)
if ! echo "$NGINX_TEST" | grep -q "successful"; then
  err "Nginx config error:"
  echo "$NGINX_TEST"
  rollback
fi
systemctl reload nginx
ok "Nginx reload berhasil"

# ── Step 4: SSL Certificate ───────────────────────────────────
info "[4/5] Request SSL Certificate untuk $NEW_DOMAIN..."

# Cek apakah cert sudah ada
if certbot certificates 2>/dev/null | grep -q "$NEW_DOMAIN"; then
  warn "Certificate sudah ada, reinstall..."
  certbot install --cert-name "$NEW_DOMAIN" --nginx --non-interactive 2>&1
else
  certbot --nginx -d "$NEW_DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email 2>&1
fi

if [ $? -ne 0 ]; then
  warn "SSL gagal dibuat. Panel tetap bisa diakses via HTTP."
  warn "Coba manual: certbot --nginx -d $NEW_DOMAIN"
else
  ok "SSL Certificate berhasil"
fi

# ── Step 5: Clear cache ───────────────────────────────────────
info "[5/5] Clear cache Pterodactyl..."
cd /var/www/pterodactyl || rollback
php artisan config:cache &>/dev/null && ok "Config cache cleared"
php artisan view:clear &>/dev/null && ok "View cache cleared"
php artisan queue:restart &>/dev/null && ok "Queue restarted"

# ── Selesai ──────────────────────────────────────────────────
echo ""
echo -e "${GREEN}===== SELESAI! =====${NC}"
echo ""
echo -e "Panel: ${BOLD}https://$NEW_DOMAIN${NC}"
echo ""
echo -e "${YELLOW}Catatan:${NC}"
echo "  - Database & semua data aman"
echo "  - Backup ada di: ${NGINX_CONF}.bak & .env.bak"
echo "  - Jika belum bisa diakses, tunggu 1-2 menit lalu refresh"
echo ""
