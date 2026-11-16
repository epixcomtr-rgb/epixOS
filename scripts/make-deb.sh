#!/bin/bash
# epixOS — epixos-base .deb paketi üret
#
# AMAÇ: ISO'yu yeniden yazmadan mevcut kurulumları güncelleyebilmek.
# Hook'ların chroot'a yazdığı dosyaları bir .deb içine paketler; böylece
#   sudo apt upgrade
# ile düzeltmeler (vga=791, nouveau kara liste, accounts-daemon, ...) dağıtılır.
#
# Kullanım:  sudo ./scripts/make-deb.sh
# Çıktı:     dist/epixos-base_<sürüm>_all.deb
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHROOT="$ROOT/build/chroot"
DIST="$ROOT/dist"
BUILD="$ROOT/build/deb"

# shellcheck disable=SC1091
. "$ROOT/VERSION"
VER="${EPIX_VERSION}.${EPIX_RELEASE//./}"
PKG="epixos-base"
ARCH="all"
DEBNAME="${PKG}_${VER}_${ARCH}.deb"

[[ -d "$CHROOT" ]] || { echo "[X] build/chroot yok — önce ./build.sh build" >&2; exit 1; }
command -v dpkg-deb >/dev/null || { echo "[X] dpkg-deb yok" >&2; exit 1; }

ok()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
inf() { printf '\033[1;36m###\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m[X]\033[0m %s\n' "$*" >&2; }

inf "1/5 paket iskeleti hazırlanıyor"
rm -rf "$BUILD"
mkdir -p "$BUILD"/{DEBIAN,usr/local/bin,usr/share/epixos,etc/default/grub.d,etc/modprobe.d,etc/initramfs-tools/conf.d,etc/systemd/system}

inf "2/5 dosyalar chroot'tan kopyalanıyor"

# ---- yardımcı araçlar (kullanıcı komutları)
for f in epix epix-ai epix-ai-gui epix-ssh epix-hw epix-doctor epix-rescue epix-boot-log epix-memory-check; do
  src="$CHROOT/usr/local/bin/$f"
  if [[ -f "$src" ]]; then
    install -m 755 "$src" "$BUILD/usr/local/bin/$f"
    ok "  $f"
  else
    err "  $f YOK — atlandı"
  fi
done

# ---- GPU / açılış düzeltmeleri
# vga=791: B560/Ironlake paneli bu parametre olmadan sinyal üretmiyor.
install -m 644 "$CHROOT/etc/default/grub.d/99-epixos.cfg" \
  "$BUILD/etc/default/grub.d/99-epixos.cfg"
ok "  /etc/default/grub.d/99-epixos.cfg (vga=791)"

# nouveau kara listesi: Optimus makinelerde hayalet VGA çıkışını önler
install -m 644 "$CHROOT/etc/modprobe.d/zz-epixos-gpu-blacklist.conf" \
  "$BUILD/etc/modprobe.d/zz-epixos-gpu-blacklist.conf"
ok "  /etc/modprobe.d/zz-epixos-gpu-blacklist.conf"

# initramfs: NVIDIA sürücüsü girmesin
install -m 644 "$CHROOT/etc/initramfs-tools/conf.d/epixos-gpu.conf" \
  "$BUILD/etc/initramfs-tools/conf.d/epixos-gpu.conf"
ok "  /etc/initramfs-tools/conf.d/epixos-gpu.conf"

# epix-backlight: açılışta parlaklık %100
install -m 644 "$CHROOT/etc/systemd/system/epix-backlight.service" \
  "$BUILD/etc/systemd/system/epix-backlight.service"
ok "  /etc/systemd/system/epix-backlight.service"

# ---- sürüm bilgisi
cat > "$BUILD/usr/share/epixos/version" <<EOF
EPIX_VERSION=$EPIX_VERSION
EPIX_RELEASE=$EPIX_RELEASE
EPIX_CODENAME=$EPIX_CODENAME
EPIX_PACKAGE_BUILD=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

inf "3/5 DEBIAN dizini"

SIZE_KB=$(du -sk --exclude=DEBIAN "$BUILD" | cut -f1)

cat > "$BUILD/DEBIAN/control" <<EOF
Package: $PKG
Version: ${EPIX_VERSION}~${EPIX_RELEASE}
Section: admin
Priority: optional
Architecture: $ARCH
Maintainer: Epix Software House <destek@epix.tr>
Installed-Size: $SIZE_KB
Depends: systemd, openssh-server
Recommends: xserver-xorg, gnome-core
Homepage: https://os.epix.tr
Description: epixOS temel yapılandırma ve araçlar
 epixOS dağıtımının temel katmanı: yardımcı komutlar (epix, epix-ssh,
 epix-hw, epix-doctor, epix-ai), GPU/açılış düzeltmeleri ve ilk açılış
 ayarları.
 .
 Bu paket sayesinde ISO'yu yeniden kurmadan "apt upgrade" ile epixOS
 düzeltmeleri alınabilir.
EOF

# ---- postinst: vga=791 kalıcı + initramfs yenileme
cat > "$BUILD/DEBIAN/postinst" <<'POSTINST'
#!/bin/sh
set -e

# /etc/default/grub ana dosyası boşsa vga=791'i oraya da yaz.
# (Ubuntu varsayılanı grub.d/ kullanır; biz ikisini de garanti ediyoruz.)
if [ -f /etc/default/grub ]; then
    if ! grep -qs 'vga=791' /etc/default/grub; then
        # GRUB_CMDLINE_LINUX_DEFAULT satırını güncelle veya ekle
        if grep -qs '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub; then
            sed -i 's|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT="quiet splash vga=791 console=tty0"|' /etc/default/grub
        else
            printf '\nGRUB_CMDLINE_LINUX_DEFAULT="quiet splash vga=791 console=tty0"\n' >> /etc/default/grub
        fi
        echo "epixos-base: vga=791 /etc/default/grub dosyasına eklendi"
    fi
fi

# epix-backlight servisini etkinleştir
systemctl enable epix-backlight.service >/dev/null 2>&1 || true

# initramfs: nouveau kara listesi initramfs'te de geçerli olsun
#
# ÖNEMLİ: "update-initramfs -u" PARAMETRESİZ çağrılmamalı.
# epixOS'ta /boot/vmlinuz-epixos ve /boot/initrd.img-epixos sembolik/çoğaltılmış
# dosyalar var. Parametresiz çağrı update-initramfs'in bunları gerçek çekirdek
# sanmasına yol açıyor: "depmod: ERROR: Bad version passed epixos" ve
# 26 MB'lik BOZUK bir initramfs üretiyor (gerçek boyut 69 MB).
# Bu, kurulu sistemi bir sonraki açılışta açılmaz hale getirir.
# Çözüm: gerçek çekirdek sürümünü açıkça ver ve -epixos kopyasını yenile.
if command -v update-initramfs >/dev/null 2>&1; then
    KVER=$(ls /boot/vmlinuz-*-generic 2>/dev/null | sed 's|.*/vmlinuz-||' | sort -V | tail -1)
    if [ -n "$KVER" ]; then
        update-initramfs -u -k "$KVER" >/dev/null 2>&1 || true
        # /boot/initrd.img-epixos kopyasını gerçek initramfs'ten tazele
        if [ -s "/boot/initrd.img-$KVER" ]; then
            cp -f "/boot/initrd.img-$KVER" /boot/initrd.img-epixos 2>/dev/null || true
        fi
        echo "epixos-base: initramfs yenilendi ($KVER)"
    fi
fi

# GRUB menüsünü yenile (vga=791 yeni çekirdeğe de geçsin)
if command -v update-grub >/dev/null 2>&1; then
    update-grub >/dev/null 2>&1 || true
fi

exit 0
POSTINST
chmod 755 "$BUILD/DEBIAN/postinst"

# ---- prerm/postrm: servisi kapat
cat > "$BUILD/DEBIAN/postrm" <<'POSTRM'
#!/bin/sh
set -e
if [ "$1" = "remove" ] || [ "$1" = "purge" ]; then
    systemctl disable epix-backlight.service >/dev/null 2>&1 || true
fi
exit 0
POSTRM
chmod 755 "$BUILD/DEBIAN/postrm"

inf "4/5 konffiles — kullanıcı değişiklikleri korunur"
cat > "$BUILD/DEBIAN/conffiles" <<'CONF'
/etc/default/grub.d/99-epixos.cfg
/etc/modprobe.d/zz-epixos-gpu-blacklist.conf
CONF

inf "5/5 .deb üretiliyor"
mkdir -p "$DIST"
rm -f "$DIST/$DEBNAME"
dpkg-deb --root-owner-group -Zxz --build "$BUILD" "$DIST/$DEBNAME" >/dev/null

ok "paket hazır: dist/$DEBNAME ($(du -h "$DIST/$DEBNAME" | cut -f1))"
echo
echo "  içerik:"
dpkg-deb -c "$DIST/$DEBNAME" 2>/dev/null | awk '{print "    "$6}' | grep -v '/$' | head -25
echo
echo "  kurmak için:  sudo dpkg -i $DEBNAME && sudo apt -f install"
echo "  kaldırmak:    sudo apt remove epixos-base"
