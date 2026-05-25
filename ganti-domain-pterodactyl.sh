#!/bin/bash

# ============================================================
#   Script Ganti Domain Pterodactyl Panel
#   Dibuat otomatis - aman, tidak hapus database/data
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════╗"
echo "║     GANTI DOMAIN PTERODACTYL PANEL           ║"
echo "║     Aman - Database & Data Tidak Terhapus    ║"
echo "╚══════════════════════════════════════════════╝"
echo -e "${NC}"

# Cek root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[ERROR] Jalankan script ini sebagai root!${NC}"
  exit 1
fi

# ── Ambil domain lama dari .env ──────────────────────────────
OLD_DOMAIN=""
if [ -f /var/www/pterodactyl/.env ]; then
  OLD_DOMAIN=$(grep "^APP_URL=" /var/www/pterodactyl/.env | sed 's|APP_URL=https\?://||' | tr -d '\r')
fi

echo -e "${YELLOW}Domain lama terdeteksi:${NC} ${OLD_DOMAIN:-tidak ditemukan}"
echo ""

# ── Input domain baru ────────────────────────────────────────
read -p "$(echo -e ${BOLD}"Masukkan domain baru (contoh: panel.domainku.com): "${NC})" NEW_DOMAIN

if [ -z "$NEW_DOMAIN" ]; then
  echo -e "${RED}[ERROR] Domain tidak boleh kosong!${NC}"
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

# ── Step 1: Update .env ──────────────────────────────────────
echo -e "${CYAN}[1/5] Update APP_URL di .env ...${NC}"
if [ -f /var/www/pterodactyl/.env ]; then
  sed -i "s|^APP_URL=.*|APP_URL=https://$NEW_DOMAIN|" /var/www/pterodactyl/.env
  echo -e "${GREEN}    ✓ .env diperbarui${NC}"
else
  echo -e "${RED}    ✗ File .env tidak ditemukan di /var/www/pterodactyl/${NC}"
  exit 1
fi

# ── Step 2: Update Nginx config ──────────────────────────────
echo -e "${CYAN}[2/5] Update konfigurasi Nginx ...${NC}"
NGINX_CONF="/etc/nginx/sites-enabled/pterodactyl.conf"

if [ ! -f "$NGINX_CONF" ]; then
  # Coba cari di sites-available
  NGINX_CONF=$(grep -rl "$OLD_DOMAIN" /etc/nginx/sites-enabled/ 2>/dev/null | head -1)
fi

if [ -f "$NGINX_CONF" ]; then
  # Backup dulu
  cp "$NGINX_CONF" "${NGINX_CONF}.bak"
  echo -e "${GREEN}    ✓ Backup config: ${NGINX_CONF}.bak${NC}"

  if [ -n "$OLD_DOMAIN" ]; then
    sed -i "s|$OLD_DOMAIN|$NEW_DOMAIN|g" "$NGINX_CONF"
  fi

  # Hapus baris SSL lama yang di-manage Certbot agar diganti baru
  sed -i '/# managed by Certbot/d' "$NGINX_CONF"
  sed -i '/ssl_certificate/d' "$NGINX_CONF"
  sed -i '/ssl_dhparam/d' "$NGINX_CONF"
  sed -i '/options-ssl-nginx/d' "$NGINX_CONF"
  sed -i '/listen.*443.*ssl/d' "$NGINX_CONF"
  sed -i '/ipv6only=on/d' "$NGINX_CONF"

  # Tambahkan listen 80 sementara agar certbot bisa verify
  sed -i "/server_name $NEW_DOMAIN/a\\    listen 80;" "$NGINX_CONF"

  echo -e "${GREEN}    ✓ Nginx config diperbarui${NC}"
else
  echo -e "${RED}    ✗ File Nginx config tidak ditemukan, skip...${NC}"
fi

# ── Step 3: Test & Reload Nginx ──────────────────────────────
echo -e "${CYAN}[3/5] Test & reload Nginx ...${NC}"
nginx_test=$(nginx -t 2>&1)
if echo "$nginx_test" | grep -q "successful"; then
  systemctl reload nginx
  echo -e "${GREEN}    ✓ Nginx reload berhasil${NC}"
else
  echo -e "${RED}    ✗ Nginx config error:${NC}"
  echo "$nginx_test"
  echo -e "${YELLOW}    Restore backup? Nginx config dikembalikan ke semula.${NC}"
  cp "${NGINX_CONF}.bak" "$NGINX_CONF"
  systemctl reload nginx
  exit 1
fi

# ── Step 4: Request SSL Certificate baru ─────────────────────
echo -e "${CYAN}[4/5] Request SSL Certificate untuk $NEW_DOMAIN ...${NC}"
echo -e "${YELLOW}    Pastikan domain sudah pointing ke IP VPS ini sebelum lanjut!${NC}"
echo ""

certbot --nginx -d "$NEW_DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email 2>&1

if [ $? -eq 0 ]; then
  echo -e "${GREEN}    ✓ SSL Certificate berhasil dibuat${NC}"
else
  echo -e "${RED}    ✗ SSL gagal. Coba manual: certbot --nginx -d $NEW_DOMAIN${NC}"
  echo -e "${YELLOW}    Panel tetap bisa diakses via HTTP dulu: http://$NEW_DOMAIN${NC}"
fi

# ── Step 5: Clear cache Pterodactyl ──────────────────────────
echo -e "${CYAN}[5/5] Clear cache Pterodactyl ...${NC}"
cd /var/www/pterodactyl
php artisan config:cache 2>&1 | tail -1
php artisan view:clear 2>&1 | tail -1
php artisan queue:restart 2>&1 | tail -1
echo -e "${GREEN}    ✓ Cache dibersihkan${NC}"

# ── Selesai ──────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗"
echo -e "║           SELESAI! 🎉                        ║"
echo -e "╚══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Panel bisa diakses di: ${BOLD}https://$NEW_DOMAIN${NC}"
echo ""
echo -e "${YELLOW}Catatan:${NC}"
echo "  • Database & semua data AMAN, tidak ada yang dihapus"
echo "  • Backup Nginx config ada di: ${NGINX_CONF}.bak"
echo "  • Jika panel belum bisa diakses, tunggu 1-2 menit lalu refresh"
echo ""
