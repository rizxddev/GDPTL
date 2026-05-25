# Pterodactyl Domain Changer

Ganti domain Pterodactyl Panel otomatis tanpa hapus database atau data apapun.

## Cara Pakai

```bash
wget https://raw.githubusercontent.com/rizxddev/GDPTL/main/ganti-domain-pterodactyl.sh
chmod +x ganti-domain-pterodactyl.sh
bash ganti-domain-pterodactyl.sh
```

## Sebelum Jalankan

Pastikan domain baru sudah pointing ke IP VPS.

```bash
curl -4 ifconfig.me
nslookup domainbaru.com 8.8.8.8
```

IP harus sama.

## Yang Dilakukan Script

- Update `APP_URL` di `.env`
- Update konfigurasi Nginx
- Reinstall SSL Certificate via Certbot
- Clear cache Pterodactyl
- Backup config Nginx otomatis

## Requirement

- Ubuntu 20.04 / 22.04 / 24.04
- Nginx + Certbot sudah terinstall
- Pterodactyl Panel di `/var/www/pterodactyl`

## Recovery

Jika ada masalah, restore Nginx config:

```bash
cp /etc/nginx/sites-enabled/pterodactyl.conf.bak /etc/nginx/sites-enabled/pterodactyl.conf
systemctl reload nginx
```

## Lisensi

MIT
