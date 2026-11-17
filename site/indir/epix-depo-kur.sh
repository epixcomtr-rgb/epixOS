#!/bin/sh
# epixOS — imzalı APT deposunu bu makineye tanıt
#
# Ne yapar:
#   1. Depo imza anahtarını /usr/share/keyrings/ altına kurar
#   2. /etc/apt/sources.list.d/epixos.list dosyasını yazar
#   3. `apt update` çalıştırır
#
# Sonrasında: sudo apt install epixos-tema
#
# Kullanım:
#   curl -fsSL https://os.epix.tr/indir/epix-depo-kur.sh | sudo sh
set -eu

KEYRING=/usr/share/keyrings/epixos-archive-keyring.gpg
LIST=/etc/apt/sources.list.d/epixos.list
BASE=https://os.epix.tr/indir/apt

if [ "$(id -u)" -ne 0 ]; then
  echo "HATA: bu betik root olarak çalışmalı." >&2
  echo "  curl -fsSL https://os.epix.tr/indir/epix-depo-kur.sh | sudo sh" >&2
  exit 1
fi

echo "==> epixOS deposu kuruluyor"

# --- araçlar
if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
  echo "HATA: curl veya wget gerekli." >&2
  exit 1
fi
get() {
  if command -v curl >/dev/null 2>&1; then curl -fsSL "$1"; else wget -qO- "$1"; fi
}

# --- 1) anahtar
mkdir -p /usr/share/keyrings
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT INT TERM

if ! get "$BASE/epixos-archive-keyring.gpg" > "$TMP" 2>/dev/null; then
  echo "HATA: anahtar indirilemedi ($BASE/epixos-archive-keyring.gpg)" >&2
  echo "  Ağ bağlantısını kontrol et." >&2
  exit 1
fi

# Anahtar gerçekten GPG anahtarı mı (boş/HTML hata sayfası olmasın)
if ! gpg --show-keys --with-colons "$TMP" >/dev/null 2>&1; then
  echo "HATA: indirilen dosya geçerli bir GPG anahtarı değil." >&2
  echo "  Sunucu HTML hata sayfası döndürmüş olabilir." >&2
  exit 1
fi
install -m 644 "$TMP" "$KEYRING"
echo "    anahtar: $KEYRING"

# --- 2) kaynak satırı
cat > "$LIST" <<EOF
# epixOS — tema ve modül güncellemeleri (os.epix.tr)
deb [signed-by=$KEYRING] $BASE stable main
EOF
chmod 644 "$LIST"
echo "    kaynak : $LIST"

# --- 3) apt update
echo "==> paket listesi güncelleniyor"
if ! apt-get update -o Dir::Etc::sourcelist="$LIST" \
                    -o Dir::Etc::sourceparts=/dev/null \
                    -o APT::Get::List-Cleanup=0 2>&1 | tail -5; then
  echo "UYARI: apt update başarısız oldu, tam güncelleme denenecek" >&2
  apt-get update || true
fi

# --- doğrulama
if apt-cache policy epixos-tema 2>/dev/null | grep -q 'Candidate: [0-9]'; then
  echo ""
  echo "TAMAM. Kurulabilir paketler:"
  apt-cache policy epixos-tema 2>/dev/null | sed -n '1,2p' | sed 's/^/    /'
  echo ""
  echo "  Tema için : sudo apt install epixos-tema && epix-tema"
else
  echo ""
  echo "UYARI: depo eklendi ama epixos-tema görünmüyor." >&2
  echo "  Elle kontrol: sudo apt update && apt-cache policy epixos-tema" >&2
  exit 1
fi
