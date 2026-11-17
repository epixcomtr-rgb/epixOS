#!/usr/bin/env bash
# epixOS build driver
# Kullanım: ./build.sh {setup|config|build|all|run|clean|iso|shell|help}
set -euo pipefail

EPIX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISO_DIR="$EPIX_ROOT/iso"
DIST_DIR="$EPIX_ROOT/dist"
_ver() { sed -n "s/^$1=//p" "$EPIX_ROOT/VERSION" 2>/dev/null | head -1; }
VERSION="$(_ver EPIX_VERSION)";     VERSION="${VERSION:-0.1}"
RELEASE="$(_ver EPIX_RELEASE)";     RELEASE="${RELEASE:-2026.11}"
CODENAME="$(_ver EPIX_CODENAME)";   CODENAME="${CODENAME:-kavak}"
TARGET_RAM="$(_ver EPIX_TARGET_RAM_MB)"; TARGET_RAM="${TARGET_RAM:-2048}"
ARCH="amd64"
FULL_VERSION="${VERSION} (${RELEASE})"
ISO_NAME="epixOS-${VERSION}-${RELEASE}-${ARCH}.iso"

c_ok()   { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
c_warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
c_err()  { printf '\033[1;31m[X]\033[0m %s\n' "$*" >&2; }

need_root() {
  if [[ $EUID -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
      exec sudo -E "$0" "$@"
    else
      c_err "Bu komut root/sudo gerektirir."; exit 1
    fi
  fi
}

cmd_setup() {
  c_ok "Gerekli araçlar kuruluyor (sudo isteyecek)"
  local pkgs=(debootstrap xorriso mtools dosfstools squashfs-tools
              grub-pc-bin grub-efi-amd64-bin grub-common
              qemu-system-x86 qemu-utils ovmf
              rsync cpio gzip xz-utils zstd ca-certificates curl wget
              gnupg git shellcheck dconf-cli libglib2.0-bin)
  apt-get update
  apt-get install -y --no-install-recommends "${pkgs[@]}"
  c_ok "Kurulum tamam."
  for c in debootstrap mksquashfs grub-mkrescue xorriso; do
    printf '    %-16s %s\n' "$c" "$(command -v "$c" || echo 'EKSİK')"
  done
}

sync_branding() {
  local inc="$ISO_DIR/config/includes.chroot"
  c_ok "Marka dosyaları includes.chroot içine kopyalanıyor"
  mkdir -p "$inc/usr/share/epixos" "$inc/usr/share/backgrounds/epixos" \
           "$inc/usr/share/icons/hicolor/scalable/apps"
  cp -f "$EPIX_ROOT"/branding/pixmaps/logo.svg            "$inc/usr/share/epixos/logo.svg"
  cp -f "$EPIX_ROOT"/branding/pixmaps/logo.svg            "$inc/usr/share/icons/hicolor/scalable/apps/epixos-logo.svg"
  cp -f "$EPIX_ROOT"/branding/pixmaps/wallpaper-default.svg "$inc/usr/share/backgrounds/epixos/epixos-default.svg"
  printf '%s\n' "$FULL_VERSION" > "$inc/usr/share/epixos/version"
  printf 'release=%s\nversion=%s\ncodename=%s\ntarget_ram_mb=%s\n' \
    "$RELEASE" "$VERSION" "$CODENAME" "$TARGET_RAM" > "$inc/usr/share/epixos/build-info"
}

cmd_config() {
  c_ok "Yapılandırma hazırlanıyor — epixOS $FULL_VERSION"
  sync_branding
  mkdir -p "$EPIX_ROOT/build" "$DIST_DIR"
  c_ok "Paket listeleri:"
  local n=0 f
  for f in "$ISO_DIR"/config/package-lists/*.list.chroot; do
    local c; c="$(awk '!/^[[:space:]]*#/ && NF' "$f" | wc -l)"
    printf '    %-46s %3s paket\n' "$(basename "$f")" "$c"
    n=$((n+c))
  done
  c_ok "toplam $n paket + canlı sistem ekleri"
  echo
  c_ok "Katmanlar:"
  local layers=(
    "SSH|ilk andan açık (epix-ssh + sshd enable)"
    "Ağ/sürücü|WiFi+Ethernet firmware gömülü (epix-hw net)"
    "Donanım|uyumsuz aygıt atlanır, açılış DURMAZ"
    "AI ajan|DeepSeek Harness + API anahtarı (epix-ai)"
  )
  local l
  for l in "${layers[@]}"; do
    printf '    %-10s %s\n' "${l%%|*}" "${l#*|}"
  done
}

cmd_build() {
  mkdir -p "$DIST_DIR"
  c_ok "Derleme başlıyor: epixOS $FULL_VERSION ($ARCH)"
  c_warn "İlk derleme 30–60 dk sürer, ~12 GB geçici alan kullanır."
  if [[ $EUID -ne 0 ]]; then
    c_ok "root yetkisi isteniyor (sudo -A)"
    exec sudo -A -E "$EPIX_ROOT/scripts/build-iso.sh"
  fi
  exec "$EPIX_ROOT/scripts/build-iso.sh"
}

cmd_run() {
  local iso="$DIST_DIR/$ISO_NAME"
  [[ -f "$iso" ]] || { c_err "ISO yok: $iso — önce ./build.sh build"; exit 1; }
  local ram="${EPIX_RAM:-$TARGET_RAM}"
  local accel=()
  [[ -w /dev/kvm ]] && accel=(-enable-kvm -cpu host)
  c_ok "QEMU başlatılıyor — ${ram} MB RAM (hedef $TARGET_RAM MB), 4 vCPU"
  c_warn "2 GB hedef testi: EPIX_RAM=2048 ./build.sh run"
  local ovmf_code=/usr/share/OVMF/OVMF_CODE.fd
  if [[ -f $ovmf_code ]]; then
    [[ -f /tmp/epix-os-vars.fd ]] || cp /usr/share/OVMF/OVMF_VARS.fd /tmp/epix-os-vars.fd 2>/dev/null || : > /tmp/epix-os-vars.fd
    qemu-system-x86_64 "${accel[@]}" -m "$ram" -smp 4 \
      -drive if=pflash,format=raw,readonly=on,file="$ovmf_code" \
      -drive if=pflash,format=raw,file=/tmp/epix-os-vars.fd \
      -cdrom "$iso" -boot d -vga std
  else
    c_warn "OVMF bulunamadı (ovmf paketi) — BIOS modunda başlatılıyor"
    qemu-system-x86_64 "${accel[@]}" -m "$ram" -smp 4 -cdrom "$iso" -boot d -vga std
  fi
}

cmd_shell() {
  local ch="$EPIX_ROOT/build/chroot"
  [[ -d "$ch" ]] || { c_err "chroot yok (önce build)"; exit 1; }
  c_ok "chroot içine giriliyor (çıkmak için exit)"
  need_root shell
  chroot "$ch" /bin/bash -i
}

cmd_clean() {
  c_ok "Derleme çıktısı temizleniyor"
  if [[ $EUID -eq 0 ]]; then
    rm -rf "$EPIX_ROOT/build"
  else
    sudo -A rm -rf "$EPIX_ROOT/build"
  fi
  c_ok "Temiz. Kaynak dosyalar (iso/, branding/, VERSION) korundu."
  [[ -d "$DIST_DIR" ]] && ls -la "$DIST_DIR" || true
}

cmd_version() {
  echo "epixOS $FULL_VERSION ($ARCH, hedef RAM ${TARGET_RAM} MB)"
  echo "ISO: dist/$ISO_NAME"
}

cmd_validate() {
  c_ok "Paket listeleri denetleniyor (apt-cache)"
  local missing=0 t
  while IFS= read -r pkg; do
    [[ -z "$pkg" || "$pkg" == \#* ]] && continue
    t="$(echo "$pkg" | tr -d '[:space:]')"
    if apt-cache show "$t" >/dev/null 2>&1; then :; else
      c_warn "bulunamadı: $t"; missing=$((missing+1))
    fi
  done < <(cat "$ISO_DIR"/config/package-lists/*.list.chroot)

  # build-iso.sh içindeki EXTRA_PKGS de denetlenir (burada hata çıkarsa derleme de patlar)
  local extras
  extras="$(sed -n '/^EXTRA_PKGS=(/,/)/p' "$EPIX_ROOT/scripts/build-iso.sh" | tr -d '()' | sed 's/EXTRA_PKGS=//')"
  for t in $extras; do
    if apt-cache show "$t" >/dev/null 2>&1; then :; else
      c_err "build-iso.sh EXTRA_PKGS: bulunamadı -> $t"; missing=$((missing+1))
    fi
  done

  [[ $missing -eq 0 ]] && c_ok "Tüm paketler mevcut" || c_err "$missing paket bulunamadı (derleme patlar)"

  c_ok "Dosya bütünlüğü"
  for f in "$ISO_DIR/auto/config" "$ISO_DIR"/config/hooks/live/*.hook.chroot; do
    bash -n "$f" 2>/dev/null || sh -n "$f" || { c_err "sözdizimi hatası: $f"; missing=$((missing+1)); }
  done
  python3 - <<'PYEOF'
import xml.dom.minidom as m, glob, sys
bad=0
for f in glob.glob("branding/pixmaps/*.svg")+glob.glob("iso/config/includes.chroot/usr/share/epixos/*.svg"):
    try: m.parse(f)
    except Exception as e: print("SVG hata:", f, e); bad=1
sys.exit(bad)
PYEOF
  c_ok "dconf anahtarları derleniyor"
  if command -v dconf >/dev/null 2>&1; then
    local tmp; tmp="$(mktemp -d)"
    cp -r "$ISO_DIR/config/includes.chroot/etc/dconf/db/local.d" "$tmp/" 2>/dev/null || true
    if [[ -d "$tmp/local.d" ]]; then
      if dconf compile "$tmp/out.db" "$tmp/local.d" 2>"$tmp/err"; then
        c_ok "dconf: geçerli ($(grep -h -c '^\[' "$tmp/local.d"/*.d/* "$tmp/local.d"/[0-9]* 2>/dev/null | paste -sd+ | bc) bölüm)"
      else
        c_err "dconf hatası:"; cat "$tmp/err"
      fi
    fi
    rm -rf "$tmp"
  else
    c_warn "dconf kurulu değil — dconf denetimi atlandı (libdconf-cli)"
  fi
  c_ok "Denetim bitti"
}

cmd_iso() {
  [[ -d "$DIST_DIR" ]] && { c_ok "dist/:"; ls -la "$DIST_DIR"; } || c_warn "Henüz ISO üretilmedi"
  [[ -d "$EPIX_ROOT/build" ]] && { c_ok "build/ (geçici):"; du -sh "$EPIX_ROOT/build" 2>/dev/null; } || true
}

case "${1:-help}" in
  setup)  cmd_setup ;;
  config) cmd_config ;;
  build)  cmd_build ;;
  headless) EPIX_VARIANT=headless cmd_build ;;
  desktop)  EPIX_VARIANT=desktop  cmd_build ;;
  all)    cmd_config; cmd_build ;;
  run)    cmd_run ;;
  shell)  cmd_shell ;;
  validate|check) cmd_validate ;;
  version) cmd_version ;;
  clean)  cmd_clean ;;
  iso|ls) cmd_iso ;;
  help|-h|--help|*)
    cat <<EOF
epixOS build driver — sürüm $FULL_VERSION

  ./build.sh setup    Gerekli araçları kur (sudo)
  ./build.sh config   Paket listelerini/markayı hazırla (derleme öncesi)
  ./build.sh build    ISO derle                 -> dist/$ISO_NAME
  ./build.sh all      config + build
  ./build.sh run      ISO'yu QEMU'da test et
  ./build.sh shell    chroot içine gir (hata ayıklama)
  ./build.sh clean    Derleme çıktısını sil
  ./build.sh version  Sürüm bilgisi
  ./build.sh validate Paket/dosya denetimi (derlemeden önce önerilir)
  ./build.sh iso      Üretilen dosyaları listele

  VARYANTLAR (EPIX_VARIANT ortam degiskeni):
    EPIX_VARIANT=desktop   GNOME + Calamares kurulum asistani (~1.9 GB) [varsayilan]
    EPIX_VARIANT=headless  SSH + Wi-Fi, ekran yok, Pi4 benzeri (~500 MB)

  Ornekler:
    ./build.sh build                          # masaustu ISO
    EPIX_VARIANT=headless ./build.sh build    # headless ISO
    ./build.sh headless                       # kisayol (ayni is)

  NOT: her varyantin chroot'u AYRIDIR (build/desktop, build/headless).
  Biri digerini bozmaz; ikisi de onbellekte kalir.
EOF
    ;;
esac
