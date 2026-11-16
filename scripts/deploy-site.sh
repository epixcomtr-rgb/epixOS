#!/usr/bin/env bash
# epixOS — os.epix.tr sitesini yayına al
#
#   ./scripts/deploy-site.sh            # yayına al (Apache + tunnel kontrol)
#   ./scripts/deploy-site.sh local      # sadece yerel Apache'ye kopyala
#   ./scripts/deploy-site.sh check      # hiçbir şey yazma, durum raporu
#
# Hedef sunucu: EpixHostx@192.168.1.15 (ssh config'deki epixhost ile aynı)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SITE="$ROOT/site"
HOST="${EPIX_DEPLOY_HOST:-EpixHostx@192.168.1.15}"
SSH_KEY="${EPIX_SSH_KEY:-$HOME/.ssh/id_ed25519}"
REMOTE_DIR="/var/www/html_files/epix.tr/epixos"
VHOST="os.epix.tr.conf"
PORT="${EPIX_SITE_PORT:-1022}"
LOCAL_IP="${EPIX_LOCAL_IP:-192.168.1.15}"
HOSTNAME_="os.epix.tr"

c_ok()   { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
c_warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
c_err()  { printf '\033[1;31m[X]\033[0m %s\n' "$*" >&2; }

ssh_run() { ssh -o BatchMode=yes -i "$SSH_KEY" -o ConnectTimeout=10 "$HOST" "$@"; }

[[ -d "$SITE" ]] || { c_err "site/ klasörü yok"; exit 1; }
[[ -f "$SITE/index.html" ]] || { c_err "site/index.html yok"; exit 1; }

MODE="${1:-deploy}"

# ---------------------------------------------------------------- check
if [[ "$MODE" == "check" ]]; then
  c_ok "yerel dosyalar: $(find "$SITE" -type f | wc -l) dosya, $(du -sh "$SITE" | cut -f1)"
  c_ok "sunucu erişimi:"
  ssh_run 'echo "   host: $(hostname)  kullanıcı: $(id -un)"' || { c_err "ssh başarısız"; exit 1; }
  echo
  c_ok "Apache vhost:"
  ssh_run "test -f /etc/apache2/sites-enabled/$VHOST && echo '   etkin: $VHOST' || echo '   YOK: $VHOST'"
  c_ok "port $PORT:"
  ssh_run "ss -tln 2>/dev/null | grep -q ':$PORT ' && echo '   dinliyor' || echo '   dinlemiyor'"
  c_ok "HTTP yanıtı:"
  ssh_run "curl -s -o /dev/null -w '   %{http_code}\n' -H 'Host: $HOSTNAME_' http://$LOCAL_IP:$PORT/"
  echo
  c_ok "yayın (Cloudflare):"
  curl -s -o /dev/null -w "   https://$HOSTNAME_ -> %{http_code}\n" -m 20 "https://$HOSTNAME_/" || true
  echo
  c_warn "404 dönüyorsa: Cloudflare tunnel ingress kuralı eksik (dashboard'dan yönetiliyor)."
  echo "   Cloudflare Zero Trust → Networks → Tunnels → epix.tr_subdomain → Public hostname ekle:"
  echo "     subdomain: os   domain: epix.tr   service: http://$LOCAL_IP:$PORT"
  exit 0
fi

# ---------------------------------------------------------------- kopyala
c_ok "site dosyaları sunucuya kopyalanıyor"
TMP_TAR="$(mktemp /tmp/epixos-site-XXXXXX.tar.gz)"
tar czf "$TMP_TAR" -C "$SITE" .
scp -q -o BatchMode=yes -i "$SSH_KEY" "$TMP_TAR" "$HOST:/tmp/epixos-site.tar.gz"
rm -f "$TMP_TAR"

# ---------------------------------------------------------------- apt deposu
# dist/apt -> /indir/apt/. İmzalı depo; epixos.list ve anahtarlık da gider.
APT_REPO="$ROOT/dist/apt"
if [[ -d "$APT_REPO" ]]; then
  c_ok "APT deposu kopyalanıyor (dist/apt -> /indir/apt)"
  TMP_APT="$(mktemp /tmp/epixos-apt-XXXXXX.tar.gz)"
  tar czf "$TMP_APT" -C "$APT_REPO" .
  scp -q -o BatchMode=yes -i "$SSH_KEY" "$TMP_APT" "$HOST:/tmp/epixos-apt.tar.gz"
  rm -f "$TMP_APT"
else
  c_warn "dist/apt yok — APT deposu atlanıyor (önce ./scripts/make-repo.sh)"
fi

ssh_run "set -e
  sudo mkdir -p '$REMOTE_DIR'
  # eski sürümü yedekle (ilk 5 yedek tutulur)
  if [ -n \"\$(sudo ls -A '$REMOTE_DIR' 2>/dev/null)\" ]; then
    sudo tar czf '/tmp/epixos-site-backup-\$(date +%Y%m%d-%H%M%S).tar.gz' -C '$REMOTE_DIR' . 2>/dev/null || true
    sudo find /tmp -maxdepth 1 -name 'epixos-site-backup-*.tar.gz' -printf '%T@ %p\n' 2>/dev/null | sort -rn | tail -n +6 | cut -d' ' -f2- | xargs -r sudo rm -f
  fi
  sudo tar xzf /tmp/epixos-site.tar.gz -C '$REMOTE_DIR'
  rm -f /tmp/epixos-site.tar.gz
  # APT deposu
  if [ -f /tmp/epixos-apt.tar.gz ]; then
    sudo rm -rf '$REMOTE_DIR/indir/apt'
    sudo mkdir -p '$REMOTE_DIR/indir/apt'
    sudo tar xzf /tmp/epixos-apt.tar.gz -C '$REMOTE_DIR/indir/apt'
    rm -f /tmp/epixos-apt.tar.gz
    # yanlis yere yazilmis eski kopya (varsa) temizle
    sudo rm -rf '$REMOTE_DIR/apt'
    echo '   apt deposu: '\$(sudo find '$REMOTE_DIR/indir/apt' -type f | wc -l)' dosya'
  fi
  sudo chown -R www-data:www-data '$REMOTE_DIR'
  echo '   dosyalar: '\$(sudo find '$REMOTE_DIR' -type f | wc -l)"

if [[ "$MODE" == "local" ]]; then
  c_ok "dosyalar kopyalandı. Vhost/tunnel adımı atlandı (local mod)."
  exit 0
fi

# ---------------------------------------------------------------- vhost
c_ok "Apache vhost kontrol ediliyor"
ssh_run "set -e
  if [ ! -f /etc/apache2/sites-available/$VHOST ]; then
    sudo tee /etc/apache2/sites-available/$VHOST >/dev/null <<'VHOSTEOF'
# os.epix.tr — epixOS tanitim sayfasi (statik)
# Cloudflare tunel: os.epix.tr -> http://$LOCAL_IP:$PORT
<VirtualHost $LOCAL_IP:$PORT>
    ServerName os.epix.tr
    ServerAlias www.os.epix.tr
    DocumentRoot $REMOTE_DIR
    DirectoryIndex index.html
    <Directory $REMOTE_DIR>
        Options -Indexes +FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>
    <LocationMatch \"\\.(css|js|png|jpg|jpeg|webp|svg|woff2?|ico)\$\">
        Header set Cache-Control \"public, max-age=2592000\"
    </LocationMatch>
    ErrorLog \${APACHE_LOG_DIR}/epixos-error.log
    CustomLog \${APACHE_LOG_DIR}/epixos-access.log combined
</VirtualHost>
VHOSTEOF
    echo '   vhost oluşturuldu'
  else
    echo '   vhost zaten var'
  fi
  grep -q '^Listen $LOCAL_IP:$PORT' /etc/apache2/ports.conf || echo 'Listen $LOCAL_IP:$PORT' | sudo tee -a /etc/apache2/ports.conf >/dev/null
  sudo a2ensite os.epix.tr >/dev/null 2>&1 || true
  sudo apache2ctl configtest 2>&1 | grep -v 'DocumentRoot' | tail -1
  sudo systemctl reload apache2
  echo '   apache reload OK'"

# ---------------------------------------------------------------- doğrula
c_ok "yerel HTTP testi"
ssh_run "for f in / /assets/css/os.css /assets/img/logo.png; do
  printf '   %-26s %s\n' \"\$f\" \"\$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: $HOSTNAME_' http://$LOCAL_IP:$PORT\$f)\"
done"

c_ok "yayın testi (Cloudflare)"
CODE="$(curl -s -o /dev/null -w '%{http_code}' -m 25 "https://$HOSTNAME_/" || echo 000)"
if [[ "$CODE" == "200" ]]; then
  c_ok "https://$HOSTNAME_ yayında (200)"
else
  c_warn "https://$HOSTNAME_ -> HTTP $CODE"
  echo
  echo "   Apache hazır ama Cloudflare tunnel ingress kuralı eksik."
  echo "   Tunnel dashboard'dan yönetiliyor (yerel YAML ezilmiyor)."
  echo "   Yapılacak: Cloudflare Zero Trust → Networks → Tunnels"
  echo "              → epix.tr_subdomain → Public hostname ekle:"
  echo "                Subdomain : os"
  echo "                Domain    : epix.tr"
  echo "                Service   : http://$LOCAL_IP:$PORT"
  echo
  echo "   DNS kaydı zaten oluşturuldu (CNAME os -> tunnel)."
fi
