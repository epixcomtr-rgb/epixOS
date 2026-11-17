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
# Varyant yapisi: her varyantin kendi chroot'u var (build/<varyant>/chroot).
# Tek chroot paylasilirsa headless derlemesi masaustu chroot'una GNOME
# birakir. Varsayilan desktop; EPIX_VARIANT ile degistirilebilir.
VARIANT="${EPIX_VARIANT:-desktop}"
CHROOT="$ROOT/build/$VARIANT/chroot"
if [[ ! -d "$CHROOT" ]]; then
  echo "HATA: chroot yok: $CHROOT" >&2
  echo "  mevcut: $(ls -d "$ROOT"/build/*/chroot 2>/dev/null | sed 's|.*/build/||;s|/chroot||' | tr '\n' ' ')" >&2
  exit 1
fi
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
mkdir -p "$BUILD/usr/share/backgrounds/epixos"
mkdir -p "$BUILD/usr/share/icons/hicolor/scalable/apps"
mkdir -p "$BUILD/etc/xdg/autostart"
mkdir -p "$BUILD/etc/dconf/db/local.d"

inf "2/5 dosyalar chroot'tan kopyalanıyor"

# ---- yardımcı araçlar (kullanıcı komutları)
for f in epix epix-ai epix-ai-gui epix-ssh epix-hw epix-doctor epix-rescue epix-boot-log epix-memory-check epix-update; do
  src="$CHROOT/usr/local/bin/$f"
  if [[ -f "$src" ]]; then
    install -m 755 "$src" "$BUILD/usr/local/bin/$f"
    ok "  $f"
  else
    err "  $f YOK — atlandı"
  fi
done

# ---- epix-market: catalog/katalog.json'dan uretilir (tek kaynak).
# Chroot'tan DEGIL, dogrudan katalogdan alinir; boylece ISO derlemesi
# beklemeden katalog guncellenebilir.
if [[ ! -f "$ROOT/dist/epix-market" ]]; then
  err "dist/epix-market YOK — once ./catalog/uret.py calistir"
  exit 1
fi
install -m 755 "$ROOT/dist/epix-market" "$BUILD/usr/local/bin/epix-market"
n=$(awk -F'\t' 'NF>=8' "$ROOT/dist/epix-market" | wc -l)
ok "  epix-market ($n katalog kaydi)"

# ---- epix-market-gui: ayni katalogun GTK3 arayuzu.
# gnome-software ~120 MB bellek kullanir; bu ~35 MB. 2 GB hedefi icin onemli.
if [[ ! -f "$ROOT/dist/epix-market-gui" ]] || [[ ! -f "$ROOT/dist/epix-market-gui.py" ]]; then
  err "dist/epix-market-gui{,.py} YOK — once ./catalog/uret.py calistir"
  exit 1
fi

# Kabuk baslatici PATH'te
install -m 755 "$ROOT/dist/epix-market-gui" "$BUILD/usr/local/bin/epix-market-gui"

# Gercek GTK3 arayuzu /usr/lib/epixos/ altinda.
# NEDEN ayri: baslatici, python3/GTK eksikse anlasilir mesaj verir.
# Dogrudan /usr/local/bin'e python betigi koymak, minimal kurulumda
# "No such file or directory" ile sessiz olum demek.
mkdir -p "$BUILD/usr/lib/epixos"
install -m 644 "$ROOT/dist/epix-market-gui.py" "$BUILD/usr/lib/epixos/epix-market-gui.py"
ok "  epix-market-gui (GTK3) + baslatici"

# Masaustu kisayolu: uygulama menusunde gorunur
mkdir -p "$BUILD/usr/share/applications"
cat > "$BUILD/usr/share/applications/epix-market.desktop" <<'DESKEOF'
[Desktop Entry]
Type=Application
Version=1.0
Name=epixOS Mağaza
Name[en]=epixOS Store
GenericName=Uygulama Mağazası
GenericName[en]=Application Store
Comment=Uygulamaları keşfet ve kur
Comment[en]=Browse and install applications
Exec=epix-market-gui
Icon=system-software-install
Terminal=false
Categories=System;PackageManager;GTK;
Keywords=magaza;market;uygulama;kur;install;store;
StartupNotify=true
DESKEOF
chmod 644 "$BUILD/usr/share/applications/epix-market.desktop"
ok "  epix-market.desktop (menü kısayolu)"

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

# ---- marka varlıkları: duvar kağıdı + simge
# Palet kurumsal logodan: lime #e2ff5e, navy #16404b, deep #0e2a31.
# Eski camgobegi (#22d3ee) duvar kağıdı marka disiydi.
if [[ -f "$CHROOT/usr/share/backgrounds/epixos/epixos-default.svg" ]]; then
  install -m 644 "$CHROOT/usr/share/backgrounds/epixos/epixos-default.svg" \
    "$BUILD/usr/share/backgrounds/epixos/epixos-default.svg"
  ok "  duvar kağıdı (epixos-default.svg)"
else
  err "  duvar kağıdı YOK — atlandı"
fi

if [[ -f "$CHROOT/usr/share/icons/hicolor/scalable/apps/epixos-logo.svg" ]]; then
  install -m 644 "$CHROOT/usr/share/icons/hicolor/scalable/apps/epixos-logo.svg" \
    "$BUILD/usr/share/icons/hicolor/scalable/apps/epixos-logo.svg"
  ok "  simge (epixos-logo.svg)"
fi

# ---- DPMS / ekran kararması
# B560 gibi eski panel+inverter kombinasyonlarında DPMS "off" sonrası ekran
# geri gelmeyebiliyor: kullanıcı masaüstünde ama ekran siyah.
if [[ -f "$CHROOT/etc/xdg/autostart/epixos-no-dpms.desktop" ]]; then
  install -m 644 "$CHROOT/etc/xdg/autostart/epixos-no-dpms.desktop" \
    "$BUILD/etc/xdg/autostart/epixos-no-dpms.desktop"
  ok "  /etc/xdg/autostart/epixos-no-dpms.desktop"
fi

# dconf: güç/ekran ayarları + duvar kağıdı renkleri
# Tam dosya yerine drop-in veriyoruz ki kullanıcının kendi dconf düzenlemeleri
# 00-epix-defaults içinde kalmasın; bu dosya 50- ile sonra okunur.
cat > "$BUILD/etc/dconf/db/local.d/50-epixos-power" <<'DCONF'
# epixOS — ekran kararması ve güç yönetimi
# Eski panellerde DPMS off sonrası ekran geri gelmeyebiliyor.
[org/gnome/settings-daemon/plugins/power]
idle-dim=false
sleep-inactive-ac-type='nothing'
sleep-inactive-battery-type='nothing'

[org/gnome/desktop/screensaver]
lock-enabled=false
idle-activation-enabled=false

[org/gnome/desktop/session]
idle-delay=uint32 0

[org/gnome/desktop/background]
picture-uri='file:///usr/share/backgrounds/epixos/epixos-default.svg'
picture-uri-dark='file:///usr/share/backgrounds/epixos/epixos-default.svg'
picture-options='zoom'
primary-color='#0e2a31'
secondary-color='#16404b'
DCONF
chmod 644 "$BUILD/etc/dconf/db/local.d/50-epixos-power"
ok "  /etc/dconf/db/local.d/50-epixos-power"

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
Recommends: xserver-xorg, gnome-core, python3-gi, gir1.2-gtk-3.0
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

# dconf sistem veritabanını yenile (duvar kağıdı + güç ayarları)
# Yapılmasaydı 50-epixos-power dosyası yazılır ama okunmazdı.
if command -v dconf >/dev/null 2>&1; then
    dconf update >/dev/null 2>&1 || true
    echo "epixos-base: dconf güncellendi"
fi

# icon cache (simge değiştiyse)
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor >/dev/null 2>&1 || true
fi

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
    # dconf veritabanını bu dosya olmadan yeniden derle
    if command -v dconf >/dev/null 2>&1; then
        dconf update >/dev/null 2>&1 || true
    fi
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
