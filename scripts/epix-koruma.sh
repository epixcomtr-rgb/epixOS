#!/bin/bash
# epixOS — GÜNCELLEME KORUMALARI
#
# Bu betik iki somut riski kapatır:
#
# RİSK 1: "apt-get autoremove" GNOME masaüstünü söker.
#   Canlı ISO --no-install-recommends ile kurulduğu için apt, masaüstünün
#   parçalarını "artık gerekli değil" sayıyor. Gerçek çıktı (B560):
#     apache2-bin appstream gir1.2-webkit2-4.1 grilo-plugins gvfs-fuse
#     libgtksourceview-4-0 libfolks26 ... (GNOME bileşenleri)
#   Çözüm: masaüstü çekirdeğini "manual" işaretle + epixOS paketlerini hold.
#
# RİSK 2: "update-grub" vga=791 parametresini düşürür.
#   /etc/default/grub.d/ dosyaları /etc/default/grub'u EZER. 99-epixos.cfg
#   içinde vga=791 yoksa yeni grub.cfg'siz kalır → Ironlake panelinde SİYAH EKRAN.
#   Çözüm: 99-epixos.cfg'de vga=791'i garanti et + update-grub sonrası doğrula.
#
# Ayrıca: /boot/vmlinuz-epixos gerçek kopya olduğu için parametresiz
# "update-initramfs -u" bozuk initramfs üretir (69 MB -> 26 MB). Bu betik
# doğru çağrımı epix-update içine gömer.
set -euo pipefail

ok()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
inf() { printf '\033[1;36m###\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m[X]\033[0m %s\n' "$*" >&2; }

# ================================================================ 1) GRUB
inf "1/4 GRUB: vga=791 garantisi"

GRUBD=/etc/default/grub.d/99-epixos.cfg
mkdir -p /etc/default/grub.d

if [[ -f "$GRUBD" ]] && ! grep -qs 'vga=791' "$GRUBD"; then
  # GRUB_CMDLINE_LINUX_DEFAULT satırı varsa güncelle, yoksa ekle
  if grep -qs '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUBD"; then
    sed -i 's|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT="quiet splash vga=791 console=tty0"|' "$GRUBD"
  else
    printf 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash vga=791 console=tty0"\n' >> "$GRUBD"
  fi
  ok "  $GRUBD içine vga=791 eklendi"
elif [[ -f "$GRUBD" ]]; then
  ok "  $GRUBD zaten vga=791 içeriyor"
else
  cat > "$GRUBD" <<'EOF'
# epixOS — kalıcı GRUB ayarları
GRUB_TIMEOUT=10
GRUB_TIMEOUT_STYLE=menu
GRUB_DISTRIBUTOR="epixOS"
# vga=791 = 1024x768x16 VESA framebuffer.
# Intel Ironlake (8086:0046, ör. Lenovo B560) paneli bu parametre olmadan
# sinyal üretmiyor: X çalışır, GNOME çizer, ekran SİYAH kalır. KALDIRMAYIN.
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash vga=791 console=tty0"
GRUB_CMDLINE_LINUX=""
GRUB_GFXMODE=1024x768
GRUB_GFXPAYLOAD_LINUX=keep
GRUB_PRELOAD_MODULES="part_msdos ext2 all_video gfxterm vbe vga"
EOF
  ok "  $GRUBD oluşturuldu"
fi

# ================================================================ 2) AUTOREMOVE KORUMASI
inf "2/4 GNOME masaüstü autoremove'a karşı korunuyor"

# Masaüstü çekirdeğini manual işaretle: autoremove bunlara dokunamaz.
DESKTOP_PKGS=(
  gnome-core gnome-shell gnome-session gdm3
  gnome-control-center gnome-terminal nautilus
  xserver-xorg xserver-xorg-core xserver-xorg-video-intel
  yaru-theme-gnome-shell yaru-theme-gtk yaru-theme-icon
  ubuntu-dock gnome-shell-extension-ubuntu-dock
  epiphany-browser
)
MARKED=0
for p in "${DESKTOP_PKGS[@]}"; do
  if dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q "install ok installed"; then
    apt-mark manual "$p" >/dev/null 2>&1 && MARKED=$((MARKED+1))
  fi
done
ok "  $MARKED paket manual işaretlendi"

# epixOS paketlerini hold: upgrade sırasında otomatik kaldırılmasın
for p in epixos-base; do
  if dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q "install ok installed"; then
    apt-mark hold "$p" >/dev/null 2>&1 || true
    ok "  $p hold (kaldırılmasın)"
  fi
done

# ================================================================ 3) EPIX-UPDATE ARACI
inf "3/4 epix-update aracı"

cat > /usr/local/bin/epix-update <<'SH'
#!/bin/sh
# epix-update — güvenli güncelleme
#
# Neden düz "apt upgrade" değil:
#   1. update-grub vga=791'i düşürebilir -> Ironlake panelinde siyah ekran
#   2. update-initramfs -u parametresiz çağrılırsa bozuk initramfs (69->26 MB)
#   3. apt autoremove masaüstü bileşenlerini sökebilir
# Bu araç her adımı doğrular ve geri dönüş bilgisi verir.
set -e

WP_CMD="quiet splash vga=791 console=tty0"

say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn(){ printf '\033[1;33m[!]\033[0m %s\n' "$*"; }

case "${1:-}" in
  --help|-h)
    cat <<EOF
epix-update — epixOS güvenli güncelleme

  epix-update            güncelle (doğrulamalı)
  epix-update check      sadece durum raporu
  epix-update fix-grub   vga=791'i GRUB'a geri yaz ve grub.cfg'yi yenile
  epix-update --help     bu yardım

Yaptıkları: apt update, apt upgrade (autoremove YOK), GRUB ve initramfs
doğrulaması, sorun varsa uyarı.
EOF
    exit 0 ;;
  check)
    say "GRUB"
    if grep -qs 'vga=791' /etc/default/grub.d/99-epixos.cfg 2>/dev/null; then
      echo "  ✓ 99-epixos.cfg vga=791 içeriyor"
    else
      echo "  ✗ 99-epixos.cfg vga=791 İÇERMİYOR — 'epix-update fix-grub' çalıştır"
    fi
    n=$(grep -c 'vga=791' /boot/grub/grub.cfg 2>/dev/null || echo 0)
    if [ "$n" -ge 1 ]; then
      echo "  ✓ grub.cfg: $n girdide vga=791"
    else
      echo "  ✗ grub.cfg'de vga=791 YOK — 'epix-update fix-grub' çalıştır"
    fi
    say "initramfs"
    sz=$(stat -c %s /boot/initrd.img-epixos 2>/dev/null || echo 0)
    if [ "$sz" -gt 40000000 ]; then
      echo "  ✓ initrd.img-epixos: $sz bayt"
    else
      echo "  ✗ initrd.img-epixos: $sz bayt — BOZUK (40 MB altı)"
      echo "    düzelt: sudo update-initramfs -u -k \$(ls /boot/vmlinuz-*-generic | sed 's|.*/vmlinuz-||' | sort -V | tail -1)"
      echo "    sonra:  sudo cp /boot/initrd.img-<sürüm> /boot/initrd.img-epixos"
    fi
    say "disk"
    df -h / /home 2>/dev/null | tail -2 | sed 's/^/  /'
    exit 0 ;;
  fix-grub)
    say "vga=791 GRUB'a yazılıyor"
    sed -i 's|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT="'"$WP_CMD"'"|' \
      /etc/default/grub.d/99-epixos.cfg 2>/dev/null || \
      echo 'GRUB_CMDLINE_LINUX_DEFAULT="'"$WP_CMD"'"' >> /etc/default/grub.d/99-epixos.cfg
    if command -v update-grub >/dev/null 2>&1; then
      update-grub >/dev/null 2>&1 || true
    elif command -v grub-mkconfig >/dev/null 2>&1; then
      grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1 || true
    fi
    n=$(grep -c 'vga=791' /boot/grub/grub.cfg 2>/dev/null || echo 0)
    if [ "$n" -ge 1 ]; then
      say "✓ grub.cfg güncellendi ($n girdi)"
    else
      warn "grub.cfg'de hâlâ vga=791 yok — elle kontrol et"
    fi
    exit 0 ;;
esac

say "1/5 apt update"
apt-get update -qq

say "2/5 apt upgrade (autoremove YOK)"
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y \
  -o Dpkg::Options::="--force-confold"

say "3/5 GRUB doğrulaması"
NEED_FIX=0
grep -qs 'vga=791' /etc/default/grub.d/99-epixos.cfg 2>/dev/null || NEED_FIX=1
[ "$(grep -c 'vga=791' /boot/grub/grub.cfg 2>/dev/null || echo 0)" -ge 1 ] || NEED_FIX=1
if [ "$NEED_FIX" = "1" ]; then
  warn "vga=791 eksik — geri yazılıyor"
  epix-update fix-grub
else
  echo "  ✓ vga=791 yerinde"
fi

say "4/5 initramfs doğrulaması"
KVER=$(ls /boot/vmlinuz-*-generic 2>/dev/null | sed 's|.*/vmlinuz-||' | sort -V | tail -1)
sz=$(stat -c %s /boot/initrd.img-epixos 2>/dev/null || echo 0)
if [ "$sz" -lt 40000000 ] && [ -n "$KVER" ]; then
  warn "initrd.img-epixos bozuk ($sz bayt) — düzeltiliyor"
  update-initramfs -u -k "$KVER" >/dev/null 2>&1 || true
  cp -f "/boot/initrd.img-$KVER" /boot/initrd.img-epixos 2>/dev/null || true
  echo "  ✓ yenilendi: $(stat -c %s /boot/initrd.img-epixos) bayt"
else
  echo "  ✓ initrd.img-epixos: $sz bayt"
fi

say "5/5 bitti"
echo
echo "  Yeniden başlatmak için: sudo reboot"
echo "  Sorun olursa:           epix-update check"
SH
chmod 755 /usr/local/bin/epix-update
ok "  /usr/local/bin/epix-update"

# ================================================================ 4) DOGRULAMA
inf "4/4 doğrulama"
echo "  99-epixos.cfg : $(grep -qs 'vga=791' /etc/default/grub.d/99-epixos.cfg && echo 'vga=791 ✓' || echo 'EKSİK')"
echo "  grub.cfg      : $(grep -c 'vga=791' /boot/grub/grub.cfg 2>/dev/null || echo 0) girdi"
echo "  hold          : $(apt-mark showhold 2>/dev/null | tr '\n' ' ' || echo yok)"
echo "  manual        : $(apt-mark showmanual 2>/dev/null | wc -l) paket"
echo
ok "koruma tamam"
echo
echo "  Güncelleme:  sudo epix-update"
echo "  Durum:       epix-update check"
echo "  GRUB onar:   sudo epix-update fix-grub"
