#!/bin/bash
# epixOS — imzalı APT deposu üret
#
# AMAÇ: kurulu epixOS'lar "apt update && apt upgrade" ile güncellenebilsin.
# Üretilen yapı:
#   dist/apt/dists/stable/main/binary-amd64/Packages{,.gz}
#   dist/apt/dists/stable/Release          (GPG imzalı)
#   dist/apt/dists/stable/InRelease        (gömülü imza)
#   dist/apt/pool/main/<paket>_<surum>_<mimari>.deb
#   dist/apt/epixos-archive-keyring.gpg    (kullanıcıya dagitilir)
#
# Kullanım:  ./scripts/make-repo.sh
# Yayın:     ./scripts/deploy-site.sh   (dist/apt -> /indir/apt/)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
REPO="$DIST/apt"
KEYDIR="$ROOT/.apt-key"          # git'e girmez (.gitignore)
SUITE="stable"
COMP="main"
ARCH="amd64"

# shellcheck disable=SC1091
. "$ROOT/VERSION"
CODENAME_REPO="epixos"

ok()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
inf() { printf '\033[1;36m###\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m[X]\033[0m %s\n' "$*" >&2; }

for c in gpg apt-ftparchive dpkg-deb gzip; do
  command -v "$c" >/dev/null || { err "$c yok"; exit 1; }
done

# ---------------------------------------------------------------- 1) ANAHTAR
inf "1/6 GPG arşiv anahtarı"
mkdir -p "$KEYDIR"; chmod 700 "$KEYDIR"

if [[ ! -f "$KEYDIR/epixos-archive-key.asc" ]]; then
  ok "  yeni anahtar üretiliyor (ed25519, süresiz)"
  GNUPGHOME="$KEYDIR" gpg --batch --quiet --gen-key <<'KEYEOF'
%no-protection
Key-Type: eddsa
Key-Curve: ed25519
Key-Usage: sign
Name-Real: epixOS Archive Signing Key
Name-Email: paket@epix.tr
Expire-Date: 0
%commit
KEYEOF
  GNUPGHOME="$KEYDIR" gpg --armor --export paket@epix.tr > "$KEYDIR/epixos-archive-key.asc"
  ok "  anahtar: $KEYDIR/epixos-archive-key.asc"
else
  ok "  mevcut anahtar kullanılıyor"
fi

KEYID=$(GNUPGHOME="$KEYDIR" gpg --list-keys --with-colons paket@epix.tr | awk -F: '/^fpr:/{print $10; exit}')
[[ -n "$KEYID" ]] || { err "anahtar parmak izi okunamadı"; exit 1; }
ok "  parmak izi: $KEYID"

# ---------------------------------------------------------------- 2) HAVUZ
inf "2/6 paket havuzu"
rm -rf "$REPO"
mkdir -p "$REPO/pool/$COMP" "$REPO/dists/$SUITE/$COMP/binary-$ARCH"

shopt -s nullglob
DEBS=("$DIST"/*.deb)
if [[ ${#DEBS[@]} -eq 0 ]]; then
  err "dist/ içinde .deb yok — önce ./scripts/make-deb.sh"
  exit 1
fi
for d in "${DEBS[@]}"; do
  cp -f "$d" "$REPO/pool/$COMP/"
  ok "  $(basename "$d")"
done
shopt -u nullglob

# ---------------------------------------------------------------- 3) INDEKS
inf "3/6 Packages indeksi"
( cd "$REPO" && dpkg-scanpackages --multiversion --arch "$ARCH" pool/$COMP \
    > "dists/$SUITE/$COMP/binary-$ARCH/Packages" 2>/dev/null )
gzip -9 -kf "$REPO/dists/$SUITE/$COMP/binary-$ARCH/Packages"
ok "  $(grep -c '^Package:' "$REPO/dists/$SUITE/$COMP/binary-$ARCH/Packages") paket indekslendi"

# by-hash: içerik-adresli kopyalar (SHA256 ile adlandırılmış).
#
# NEDEN GEREKLİ: APT, Release'teki hash ile indirdiği dosyayı karşılaştırır.
# Cloudflare/eski vekil önbelleği eski sürümü sunarsa hash tutmaz ve depo
# HİÇ çalışmaz. Ölçüldü: "File has unexpected size (975 != 979)" — depo
# 8 farklı denemede tamamen kullanılamaz durumdaydı.
#
# by-hash ile APT dosyayı /by-hash/SHA256/<hash> yolundan ister. Yol
# içeriğe bağlı olduğu için eski önbellek girdisi ASLA yanlış içerik
# döndüremez: ya doğru dosya gelir ya da 404 (APT düz yola düşer).
inf "3b/6 by-hash kopyaları"
# APT indeksleri by-hash altında SHA512 ile ister (Release'te en güçlü
# hash hangisiyse onu kullanır). Yalnızca SHA256 koymak YETMEZ: APT
# /by-hash/SHA512/<hash> ister, 404 alır ve düz yola düşer — düz yol da
# önbellekteki eski dosyayı döndürünce "File has unexpected size" hatası
# geri gelir. Üç algoritmayı da yazıyoruz.
BYHASH_DIR="$REPO/dists/$SUITE/$COMP/binary-$ARCH/by-hash"
for alg in SHA256 SHA512 SHA1 MD5Sum; do
  mkdir -p "$BYHASH_DIR/$alg"
done
for f in Packages Packages.gz; do
  src="$REPO/dists/$SUITE/$COMP/binary-$ARCH/$f"
  [[ -f "$src" ]] || continue
  h256=$(sha256sum "$src" | cut -d' ' -f1)
  h512=$(sha512sum "$src" | cut -d' ' -f1)
  h1=$(sha1sum   "$src" | cut -d' ' -f1)
  hmd5=$(md5sum  "$src" | cut -d' ' -f1)
  cp -f "$src" "$BYHASH_DIR/SHA256/$h256"
  cp -f "$src" "$BYHASH_DIR/SHA512/$h512"
  cp -f "$src" "$BYHASH_DIR/SHA1/$h1"
  cp -f "$src" "$BYHASH_DIR/MD5Sum/$hmd5"
  ok "  by-hash x4 ($f)"
done

# ---------------------------------------------------------------- 4) RELEASE
inf "4/6 Release dosyası"
( cd "$REPO/dists/$SUITE" && apt-ftparchive \
    -o APT::FTPArchive::Release::Origin="epixOS" \
    -o APT::FTPArchive::Release::Label="epixOS" \
    -o APT::FTPArchive::Release::Suite="$SUITE" \
    -o APT::FTPArchive::Release::Codename="$CODENAME_REPO" \
    -o APT::FTPArchive::Release::Architectures="$ARCH" \
    -o APT::FTPArchive::Release::Components="$COMP" \
    -o APT::FTPArchive::Release::Description="epixOS ${EPIX_VERSION} (${EPIX_RELEASE}) ${EPIX_CODENAME} paket deposu" \
    release . > Release.tmp )

# Acquire-By-Hash: apt-ftparchive bu alanı YAZMIYOR. Elle ekliyoruz ve
# MUTLAKA imzadan ÖNCE ekliyoruz — sonra eklersek imza geçersiz olur.
#
# Bu alan APT'ye "indeksleri /by-hash/SHA256/<hash> yolundan iste" der.
# Yol içeriğe bağlı olduğu için eski önbellek girdisi asla yanlış içerik
# döndüremez. Cloudflare önbelleği depoyu tamamen kullanılamaz hale
# getiriyordu ("File has unexpected size (975 != 979)").
{
  printf 'Acquire-By-Hash: yes\n'
  cat "$REPO/dists/$SUITE/Release.tmp"
} > "$REPO/dists/$SUITE/Release"
rm -f "$REPO/dists/$SUITE/Release.tmp"

ok "  $(grep -cE '^(MD5Sum|SHA256):' "$REPO/dists/$SUITE/Release") bölüm"
grep -q '^Acquire-By-Hash: yes' "$REPO/dists/$SUITE/Release" \
  && ok "  Acquire-By-Hash: yes" \
  || err "  Acquire-By-Hash yazılamadı"

# ---------------------------------------------------------------- 5) IMZA
inf "5/6 GPG imza"
GNUPGHOME="$KEYDIR" gpg --batch --yes --quiet --default-key "$KEYID" \
  --clearsign -o "$REPO/dists/$SUITE/InRelease" "$REPO/dists/$SUITE/Release"
GNUPGHOME="$KEYDIR" gpg --batch --yes --quiet --default-key "$KEYID" \
  --armor --detach-sign -o "$REPO/dists/$SUITE/Release.gpg" "$REPO/dists/$SUITE/Release"

# kullanıcıya dagitilacak anahtarlık
GNUPGHOME="$KEYDIR" gpg --export "$KEYID" > "$REPO/epixos-archive-keyring.gpg"
ok "  InRelease + Release.gpg + epixos-archive-keyring.gpg"

# ---------------------------------------------------------------- 6) DOGRULA
inf "6/6 doğrulama"
# İmza doğrulaması: BAŞARISIZ olursa derleme durmalı. Sessizce geçen
# bir imza hatası, depoyu tüm kullanıcılar için kullanılamaz yapar.
if GNUPGHOME="$KEYDIR" gpg --verify "$REPO/dists/$SUITE/InRelease" 2>&1 \
     | grep -qE "Good signature|iyi \[|İmza iyi"; then
  ok "  InRelease imzası doğrulandı"
else
  err "  InRelease imza doğrulaması BAŞARISIZ"
  exit 1
fi

cat > "$REPO/epixos.list" <<LIST
# epixOS paket deposu — /etc/apt/sources.list.d/epixos.list olarak kurulur
deb [signed-by=/usr/share/keyrings/epixos-archive-keyring.gpg] https://os.epix.tr/indir/apt $SUITE $COMP
LIST

echo
ok "depo hazır: $REPO"
echo "  boyut : $(du -sh "$REPO" | cut -f1)"
echo "  dosya : $(find "$REPO" -type f | wc -l)"
echo
echo "  yapı:"
find "$REPO" -type f | sed "s|$REPO/|    |" | sort | head -12
echo
echo "  sonraki adım: ./scripts/deploy-site.sh   (depoyu os.epix.tr/indir/apt/ altına yayınlar)"
echo
echo "  kullanıcı tarafı (tek seferlik):"
echo "    curl -fsSL https://os.epix.tr/indir/apt/epixos-archive-keyring.gpg \\"
echo "      | sudo tee /usr/share/keyrings/epixos-archive-keyring.gpg >/dev/null"
echo "    curl -fsSL https://os.epix.tr/indir/apt/epixos.list \\"
echo "      | sudo tee /etc/apt/sources.list.d/epixos.list >/dev/null"
echo "    sudo apt update && sudo apt upgrade"
echo
echo "  anahtar parmak izi: $KEYID"
