#!/usr/bin/env bash
# epixOS — derleme çıktısından sonra otomatik denetim.
# Kullanım: ./scripts/verify-iso.sh [dist/epixOS-*.iso]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ISO="${1:-$(ls -1t "$ROOT"/dist/*.iso 2>/dev/null | head -1 || true)}"
[[ -f "$ISO" ]] || { echo "ISO bulunamadı. Önce ./build.sh build" >&2; exit 1; }

echo "==> ISO: $ISO"
echo "    boyut: $(du -h "$ISO" | cut -f1)"

echo
echo "==> sha256 (kayıtla karşılaştır)"
sha256sum "$ISO"

echo
echo "==> ISO yapısı"
xorriso -indev "$ISO" -find / -maxdepth 2 2>/dev/null | head -30 || true

echo
echo "==> önyükleme bilgisi"
xorriso -indev "$ISO" -report_el_torito as_mkisofs 2>/dev/null | head -15 || true

echo
echo "==> squashfs kök dosya sistemi"
command -v unsquashfs >/dev/null && {
  tmp="$(mktemp -d)"
  xorriso -osirrox on -indev "$ISO" -extract /live/filesystem.squashfs "$tmp/fs.squashfs" 2>/dev/null || true
  if [[ -f "$tmp/fs.squashfs" ]]; then
    unsquashfs -l "$tmp/fs.squashfs" >/dev/null 2>&1 && echo "    squashfs ok"
    unsquashfs -cat "$tmp/fs.squashfs" etc/os-release 2>/dev/null | head -5
  fi
  rm -rf "$tmp"
}

echo
# ── vga=791 / GRUB parametre denetimi (B560 Ironlake siyah ekran dersi) ─────
# vga=791 yoksa Intel Ironlake paneli sinyal üretmez: X/GNOME çalışır ama
# ekran siyah kalır. Bu denetim o hatanın sessizce geri gelmesini engeller.
echo "==> vga=791 parametresi"
tmpg="$(mktemp -d)"
xorriso -osirrox on -indev "$ISO" -extract /boot/grub/grub.cfg "$tmpg/grub.cfg" 2>/dev/null || true
if [[ -f "$tmpg/grub.cfg" ]]; then
  vga_n=$(grep -c 'vga=791' "$tmpg/grub.cfg" 2>/dev/null || echo 0)
  if [[ "$vga_n" -ge 1 ]]; then
    echo "    ✓ vga=791 bulundu ($vga_n girdi)"
  else
    echo "    ✗ UYARI: vga=791 YOK — Intel Ironlake'te ekran siyah kalabilir" >&2
  fi
  nomodeset_n=$(grep -c '^ *linux.*nomodeset' "$tmpg/grub.cfg" 2>/dev/null || echo 0)
  [[ "$nomodeset_n" -gt 0 ]] && echo "    ℹ $nomodeset_n girdide nomodeset var (yalnızca Uyumluluk Modu olmalı)"
  gfxpl=$(grep -c 'gfxpayload=keep' "$tmpg/grub.cfg" 2>/dev/null || echo 0)
  [[ "$gfxpl" -ge 1 ]] && echo "    ✓ gfxpayload=keep var" || echo "    ℹ gfxpayload=keep yok"
else
  echo "    ℹ /boot/grub/grub.cfg ISO içinde bulunamadı"
fi
rm -rf "$tmpg"

# casper.conf BUILD_SYSTEM — yanlışsa /cow format 'overlay' hatası verir
echo
echo "==> casper.conf"
tmpc="$(mktemp -d)"
xorriso -osirrox on -indev "$ISO" -extract /casper/initrd.img "$tmpc/initrd.img" 2>/dev/null || true
if [[ -f "$tmpc/initrd.img" ]]; then
  echo "    initrd: $(stat -c %s "$tmpc/initrd.img" 2>/dev/null) bayt"
  if lsinitramfs "$tmpc/initrd.img" 2>/dev/null | grep -q 'conf/conf.d/casper'; then
    echo "    ✓ casper yapılandırması initrd içinde"
  fi
fi
rm -rf "$tmpc"

echo
echo "==> hatırlatma: gerçek test için  ./build.sh run   (EPIX_RAM=2048)"
