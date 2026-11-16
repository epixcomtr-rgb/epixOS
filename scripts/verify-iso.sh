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
echo "==> hatırlatma: gerçek test için  ./build.sh run   (EPIX_RAM=2048)"
