#!/usr/bin/env bash
# epixOS ISO üretici — live-build'e bağımlı değil.
#
# Akış:
#   1) debootstrap ile temiz kök dosya sistemi
#   2) paket listelerinden apt kurulumu
#   3) chroot hook'ları (marka, hafiflik, dil)
#   4) casper (Ubuntu canlı sistem) + initramfs
#   5) mksquashfs -> casper/filesystem.squashfs
#   6) grub-mkrescue -> BIOS + UEFI hibrit ISO
#
# Neden live-build değil: Ubuntu deposundaki live-build 3.0~a57 (2012) UEFI üretemiyor.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ISO_CFG="$ROOT/iso/config"
BUILD="$ROOT/build"
CHROOT="$BUILD/chroot"
ISOTREE="$BUILD/isottree"
DIST="$ROOT/dist"
CACHE="$BUILD/cache"

_get() { sed -n "s/^$1=//p" "$ROOT/VERSION" 2>/dev/null | head -1; }
VERSION="$(_get EPIX_VERSION)";   VERSION="${VERSION:-0.1}"
RELEASE="$(_get EPIX_RELEASE)";   RELEASE="${RELEASE:-2026.11}"
CODENAME="$(_get EPIX_CODENAME)"; CODENAME="${CODENAME:-kavak}"
TARGET_RAM="$(_get EPIX_TARGET_RAM_MB)"; TARGET_RAM="${TARGET_RAM:-2048}"
ARCH="${EPIX_ARCH:-amd64}"
SUITE="${EPIX_SUITE:-noble}"
MIRROR="${EPIX_MIRROR:-http://archive.ubuntu.com/ubuntu}"
SECMIRROR="${EPIX_SECMIRROR:-http://security.ubuntu.com/ubuntu}"
ISO_NAME="epixOS-${VERSION}-${RELEASE}-${ARCH}.iso"
LOG="$DIST/build.log"

c_ok()   { printf '\033[1;32m==>\033[0m %s\n' "$*" | tee -a "$LOG"; }
c_step() { printf '\n\033[1;36m### %s\033[0m\n' "$*" | tee -a "$LOG"; }
c_warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" | tee -a "$LOG"; }
c_err()  { printf '\033[1;31m[X]\033[0m %s\n' "$*" | tee -a "$LOG" >&2; }
die()    { c_err "$*"; exit 1; }

# ---------------------------------------------------------------- ilerleme çubuğu
# Uzun adımlarda "hiçbir şey olmuyor" hissini önler.
# Kullanım:  run_progress "başlık" "komut..."   veya arka planda başlatıp bekle.

BAR_W=40
_pfmt() {  # beklenen saniye -> tahmini kalan
  local el=$1 tot=$2
  local kalan=$(( tot - el )); [[ $kalan -lt 0 ]] && kalan=0
  printf '%d:%02d' $(( kalan/60 )) $(( kalan%60 ))
}
_draw_bar() {  # $1=etiket $2=geçen $3=toplam(tahmin) $4=ek bilgi
  local el=$2 tot=$3 pct filled empty bar
  if [[ $tot -gt 0 ]]; then
    pct=$(( el * 100 / tot )); [[ $pct -gt 100 ]] && pct=100
  else pct=0; fi
  filled=$(( pct * BAR_W / 100 )); [[ $filled -gt $BAR_W ]] && filled=$BAR_W
  empty=$(( BAR_W - filled ))
  bar="$(printf '%*s' "$filled" '' | tr ' ' '#')$(printf '%*s' "$empty" '' | tr ' ' '.')"
  printf '\r  \033[1;36m[%s]\033[0m %3d%%  %s  kalan~%s  %s\033[K' \
    "$bar" "$pct" "$(printf '%d:%02d' $(( el/60 )) $(( el%60 )))" \
    "$(_pfmt "$el" "$tot")" "$4"
}

# Bir arka plan işini çubukla izle:  progress_wait "etiket" PID TAHMIN_SN "ipucu"
progress_wait() {
  local label="$1" pid="$2" est="$3" hint="${4:-}" t0 now el
  t0=$(date +%s)
  while kill -0 "$pid" 2>/dev/null; do
    now=$(date +%s); el=$(( now - t0 ))
    _draw_bar "$label" "$el" "$est" "$hint"
    sleep 1
  done
  now=$(date +%s); el=$(( now - t0 ))
  _draw_bar "$label" "$est" "$est" "bitti"
  printf '\n'
}

# Komutu arka planda çalıştır, çubukla izle.
#   run_progress "etiket" TAHMIN_SN "ipucu" -- komut arg...
run_progress() {
  local label="$1" est="$2" hint="$3"; shift 3
  [[ "${1:-}" == "--" ]] && shift
  "$@" &
  local pid=$!
  local rc=0
  progress_wait "$label" "$pid" "$est" "$hint"
  wait "$pid" || rc=$?
  return $rc
}

[[ $EUID -eq 0 ]] || die "root gerekli: sudo ./scripts/build-iso.sh"
mkdir -p "$DIST" "$CACHE"
: > "$LOG"

# ---------------------------------------------------------------- temizlik tuzağı
MOUNTS=()
cleanup() {
  for m in "${MOUNTS[@]:-}"; do
    mountpoint -q "$m" 2>/dev/null && umount -lf "$m" 2>/dev/null || true
  done
  # ek güvence: MOUNTS boş kalmış olsa bile chroot altında mount bırakma
  for d in dev/pts dev proc sys run; do
    mountpoint -q "$CHROOT/$d" 2>/dev/null && umount -lf "$CHROOT/$d" 2>/dev/null || true
  done
}

# squashfs öncesi son kontrol: chroot altında mount KALMAMALI
verify_clean() {
  local left
  left="$(mount 2>/dev/null | grep -c " $CHROOT/" || true)"
  if [[ "${left:-0}" -gt 0 ]]; then
    c_err "chroot altında hâlâ $left mount var — mksquashfs sonsuz döngüye girer:"
    mount | grep " $CHROOT/" | sed 's/^/    /' >&2
    for d in dev/pts dev proc sys run; do
      mountpoint -q "$CHROOT/$d" 2>/dev/null && umount -lf "$CHROOT/$d" 2>/dev/null || true
    done
    left="$(mount 2>/dev/null | grep -c " $CHROOT/" || true)"
    if [[ "${left:-0}" -gt 0 ]]; then
      c_err "mount'lar sökülemedi — derleme durduruluyor"
      exit 1
    fi
    c_ok "mount'lar temizlendi"
  fi
}
trap cleanup EXIT INT TERM

bind_mounts() {
  for d in dev dev/pts proc sys run; do
    mkdir -p "$CHROOT/$d"
    if mountpoint -q "$CHROOT/$d"; then
      # DİKKAT: ÖNCEDEN takılı mount'lar da listeye EKLENMELİ.
      # Aksi halde cleanup bunları sökmez ve mksquashfs /proc'u okumaya
      # çalışıp sonsuz döngüye girer (4 TB okuma, ilerleme yok).
      MOUNTS+=("$CHROOT/$d")
    else
      mount --bind "/$d" "$CHROOT/$d" 2>/dev/null || mount -t proc proc "$CHROOT/proc" 2>/dev/null || true
      MOUNTS+=("$CHROOT/$d")
    fi
  done
}

# ================================================================ 1) BOOTSTRAP
c_step "1/7 debootstrap — $SUITE $ARCH"
if [[ -f "$CHROOT/.bootstrap-done" ]]; then
  c_ok "chroot zaten hazır, atlanıyor"
else
  rm -rf "$CHROOT"
  mkdir -p "$CHROOT"
  c_ok "temel sistem indiriliyor (~2-3 dk, çubuk sabit kalabilir — debootstrap sessiz çalışır)"
  debootstrap --arch="$ARCH" --variant=minbase \
    --components=main,restricted,universe,multiverse \
    --include=ca-certificates,apt-utils,gnupg,locales \
    "$SUITE" "$CHROOT" "$MIRROR" > "$BUILD/debootstrap.log" 2>&1 &
  DB_PID=$!
  t0=$(date +%s)
  while kill -0 "$DB_PID" 2>/dev/null; do
    now=$(date +%s); el=$(( now - t0 ))
    done_pkgs=$(grep -c '^Setting up' "$BUILD/debootstrap.log" 2>/dev/null || true)
    [[ -z "$done_pkgs" ]] && done_pkgs=0
    printf '\r  \033[1;36m[[0m geçen %d:%02d  \033[1;36m][0m  %s paket kuruldu\033[K' \
      $(( el/60 )) $(( el%60 )) "$done_pkgs"
    sleep 2
  done
  DB_RC=0; wait "$DB_PID" || DB_RC=$?
  printf '\r  bootstrap bitti (%s paket)\033[K\n' "$done_pkgs"
  if [[ $DB_RC -ne 0 ]]; then
    c_err "debootstrap başarısız:"; tail -20 "$BUILD/debootstrap.log" >&2; exit 1
  fi
  touch "$CHROOT/.bootstrap-done"
  c_ok "bootstrap tamam"
fi

# ================================================================ 2) KAYNAKLAR
c_step "2/7 apt kaynakları ve paket listeleri"
cat > "$CHROOT/etc/apt/sources.list" <<EOF
deb $MIRROR $SUITE main restricted universe multiverse
deb $MIRROR $SUITE-updates main restricted universe multiverse
deb $SECMIRROR $SUITE-security main restricted universe multiverse
EOF
cat > "$CHROOT/etc/apt/apt.conf.d/99epixos" <<'EOF'
APT::Install-Recommends "false";
APT::Install-Suggests "false";
Acquire::Retries "3";
Acquire::Languages "none";
Dpkg::Options { "--force-confdef"; "--force-confold"; };
EOF
cp /etc/resolv.conf "$CHROOT/etc/resolv.conf" 2>/dev/null || true

# paket listeleri
PKGS=""
for f in "$ISO_CFG"/package-lists/*.list.chroot; do
  [[ -f "$f" ]] || continue
  PKGS="$PKGS $(awk '!/^[[:space:]]*#/ && NF {print $1}' "$f" | tr '\n' ' ')"
done
# canlı sistem + çekirdek + initramfs için zorunlu ekler
# NOT: buradaki her paket "apt-cache show" ile DOĞRULANIR (aşağıda).
EXTRA_PKGS=(casper discover laptop-detect os-prober
            initramfs-tools initramfs-tools-bin linux-generic kbd console-setup
            plymouth plymouth-themes ubuntu-keyring systemd-sysv sudo
            whiptail dialog squashfs-tools openssh-server)
PKGS="$PKGS ${EXTRA_PKGS[*]}"

echo "$PKGS" | tr ' ' '\n' | awk 'NF' | sort -u > "$BUILD/packages.list"

# ---- paket adı doğrulaması: derlemeyi 30 dk sonra patlatmak yerine hemen dur ----
c_ok "paket adları doğrulanıyor ($(wc -l < "$BUILD/packages.list") paket)"
BAD=()
while IFS= read -r pkg; do
  [[ -z "$pkg" ]] && continue
  apt-cache show "$pkg" >/dev/null 2>&1 || BAD+=("$pkg")
done < "$BUILD/packages.list"

if [[ ${#BAD[@]} -gt 0 ]]; then
  c_err "şu paket(ler) apt'te bulunamadı:"
  printf '      - %s\n' "${BAD[@]}" | tee -a "$LOG"
  c_err "derleme durduruldu. Listeyi düzelt: iso/config/package-lists/*.list.chroot"
  c_err "veya build-iso.sh içindeki EXTRA_PKGS."
  exit 1
fi
c_ok "tüm paket adları geçerli"

# ================================================================ 3) KURULUM
c_step "3/7 apt-get install (uzun sürebilir)"
bind_mounts
chroot "$CHROOT" env DEBIAN_FRONTEND=noninteractive LC_ALL=C \
  apt-get update 2>&1 | tee -a "$LOG" | tail -3

INSTALL_LOG="$BUILD/install.log"
: > "$INSTALL_LOG"
PKG_TOTAL=$(grep -c . "$BUILD/packages.list" 2>/dev/null || echo 0)

# apt ilerlemesi: kaç paket kuruldu / toplam
apt_monitor() {
  local log="$1" total="$2" t0 now el done_n pct filled empty bar est
  local last_pct=0 last_el=0
  t0=$(date +%s)
  while :; do
    # `|| true` ZORUNLU: grep -c eşleşme yoksa exit 1 döner, pipefail + set -e
    # izleyiciyi öldürür.
    done_n=$(grep -c '^Setting up ' "$log" 2>/dev/null || true)
    [[ -z "$done_n" ]] && done_n=0
    if [[ "$total" -gt 0 ]]; then
      pct=$(( done_n * 100 / total )); [[ $pct -gt 99 ]] && pct=99
    else pct=0; fi
    now=$(date +%s); el=$(( now - t0 ))
    # Kalan süre yalnızca paket sayısı DEĞİŞTİĞİNDE yeniden hesaplanır,
    # aksi halde sayaç yukarı doğru kaçar (test: 0:00 -> 0:09).
    if [[ $pct -gt 3 ]] && [[ "$pct" != "$last_pct" ]]; then
      est=$(( el * 100 / pct )); last_pct=$pct; last_el=$el
    elif [[ "$last_pct" -gt 0 ]]; then
      est=$(( last_el * 100 / last_pct ))
    else est=$(( el + 400 )); fi
    [[ $est -lt $el ]] && est=$el
    filled=$(( pct * 40 / 100 )); [[ $filled -gt 40 ]] && filled=40
    empty=$(( 40 - filled ))
    bar="$(printf '%*s' "$filled" '' | tr ' ' '#')$(printf '%*s' "$empty" '' | tr ' ' '.')"
    printf '\r  \033[1;36m[%s]\033[0m %3d%%  %d/%d paket  geçen %d:%02d  ~%s kaldı\033[K' \
      "$bar" "$pct" "$done_n" "$total" $(( el/60 )) $(( el%60 )) "$(_pfmt "$el" "$est")"
    [[ -f "$log.done" ]] && break
    sleep 1
  done
  printf '\r  \033[1;36m[%s]\033[0m 100%%  %d paket kuruldu\033[K\n' \
    "$(printf '%*s' 40 '' | tr ' ' '#')" "$done_n"
}

apt_monitor "$INSTALL_LOG" "$PKG_TOTAL" &
APT_MON=$!
set +e
chroot "$CHROOT" env DEBIAN_FRONTEND=noninteractive LC_ALL=C \
     apt-get install -y --no-install-recommends $(cat "$BUILD/packages.list" | tr '\n' ' ') \
     > "$INSTALL_LOG" 2>&1
APT_RC=$?
set -e
: > "$INSTALL_LOG.done"
wait "$APT_MON" 2>/dev/null || true
rm -f "$INSTALL_LOG.done"

if [[ $APT_RC -ne 0 ]]; then
  c_err "paket kurulumu başarısız — son 40 satır:"
  tail -40 "$INSTALL_LOG" >&2
  exit 1
fi
c_ok "paketler kuruldu ($(grep -c '^Setting up' "$INSTALL_LOG") paket)"

# ---- KRİTİK GÜVENCE: X sunucusu ----
# gdm3 xserver-xorg'u yalnızca "Recommends" olarak istiyor ve biz
# --no-install-recommends kullanıyoruz. Sonuç: GDM açılıyor, X bulamıyor,
# EKRAN SİYAH KALIYOR (ne hata ne ilerleme). Bu yüzden açıkça kuruyoruz.
if ! chroot "$CHROOT" test -x /usr/lib/xorg/Xorg; then
  c_warn "X sunucusu yok — xserver-xorg kuruluyor (gdm3 Recommends ile gelmiyor)"
  chroot "$CHROOT" env DEBIAN_FRONTEND=noninteractive LC_ALL=C \
    apt-get install -y --no-install-recommends \
    xserver-xorg xserver-xorg-core xserver-xorg-input-all \
    xserver-xorg-video-all xinit x11-xserver-utils x11-xkb-utils \
    >> "$INSTALL_LOG" 2>&1 || c_warn "X sunucusu kurulamadı (ağ?)"
fi
if chroot "$CHROOT" test -x /usr/lib/xorg/Xorg; then
  c_ok "X sunucusu hazır ($(chroot "$CHROOT" ls /usr/lib/xorg/modules/drivers 2>/dev/null | wc -l) sürücü modülü)"
else
  c_err "X sunucusu KURULAMADI — bu ISO'da masaüstü açılmaz!"
  X_MISSING=1
fi

# ================================================================ 4) CHROOT AYARLARI
c_step "4/7 sistem ayarları ve hook'lar"

export EPIX_VERSION EPIX_RELEASE="$RELEASE" EPIX_CODENAME="$CODENAME" EPIX_TARGET_RAM_MB="$TARGET_RAM"

# hostname / hosts
echo "epixos" > "$CHROOT/etc/hostname"
cat > "$CHROOT/etc/hosts" <<'EOF'
127.0.0.1 localhost epixos
127.0.1.1 epixos
::1       localhost ip6-localhost ip6-loopback
EOF

# canlı sistem kimliği (casper)
# DİKKAT: BUILD_SYSTEM "Ubuntu" veya "Debian" OLMALI.
# casper-helpers bu değere bakıp MP_QUIET="-q" ayarlıyor; başka bir değerde
# MP_QUIET="" olur ve casper'daki `modprobe "${MP_QUIET}" -b overlay` çağrısı
# boş argüman yüzünden başarısız olup "no support found" panic'i verir.
# Görünen ad FLAVOUR ile belirlenir (marka buradan gelir).
cat > "$CHROOT/etc/casper.conf" <<'EOF'
export USERNAME="live"
export USERFULLNAME="epixOS Live"
export HOST="epixos"
export BUILD_SYSTEM="Ubuntu"
export FLAVOUR="epixOS"
EOF

# dconf / includes.chroot kopyala
if [[ -d "$ISO_CFG/includes.chroot" ]]; then
  c_ok "includes.chroot kopyalanıyor"
  cp -a "$ISO_CFG/includes.chroot/." "$CHROOT/"
fi

# marka dosyaları (build.sh sync_branding ile geldi)
mkdir -p "$CHROOT/usr/share/epixos" "$CHROOT/usr/share/backgrounds/epixos" \
         "$CHROOT/usr/share/icons/hicolor/scalable/apps"
[[ -f "$ROOT/branding/pixmaps/logo.svg" ]] && {
  cp -f "$ROOT/branding/pixmaps/logo.svg" "$CHROOT/usr/share/epixos/logo.svg"
  cp -f "$ROOT/branding/pixmaps/logo.svg" "$CHROOT/usr/share/icons/hicolor/scalable/apps/epixos-logo.svg"
}
[[ -f "$ROOT/branding/pixmaps/wallpaper-default.svg" ]] && \
  cp -f "$ROOT/branding/pixmaps/wallpaper-default.svg" \
        "$CHROOT/usr/share/backgrounds/epixos/epixos-default.svg"

# hook'lar (sıralı)
for h in "$ISO_CFG"/hooks/live/*.hook.chroot; do
  [[ -f "$h" ]] || continue
  c_ok "hook: $(basename "$h")"
  if ! cp "$h" "$CHROOT/tmp/epix-hook.sh"; then
    die "hook kopyalanamadı: $h"
  fi
  chmod +x "$CHROOT/tmp/epix-hook.sh"
  if ! chroot "$CHROOT" env DEBIAN_FRONTEND=noninteractive \
        EPIX_VERSION="$VERSION" EPIX_RELEASE="$RELEASE" \
        EPIX_CODENAME="$CODENAME" EPIX_TARGET_RAM_MB="$TARGET_RAM" \
        /tmp/epix-hook.sh 2>&1 | tee -a "$LOG" | sed 's/^/    /'; then
    c_warn "hook hata verdi (${h##*/}) — devam ediliyor"
  fi
  rm -f "$CHROOT/tmp/epix-hook.sh"
done

# belge temizliği (hafiflik)
rm -rf "$CHROOT"/usr/share/doc/* 2>/dev/null || true
mkdir -p "$CHROOT/usr/share/doc"
rm -rf "$CHROOT"/usr/share/man/* 2>/dev/null || true
rm -rf "$CHROOT"/usr/share/help/* 2>/dev/null || true

# ---- DeepSeek Harness kurulumu (ağ varsa) ----
if [ -x "$CHROOT/opt/node24/bin/node" ]; then
  c_ok "dsh (DeepSeek Harness) kuruluyor — npm global"
  cat > "$CHROOT/etc/epixos/npmrc" <<'NPMRC'
fund=false
audit=false
allow-scripts=node-pty,koffi,@deepseek-ai/dsh-subprocess-local,protobufjs,@google/genai
NPMRC
  if chroot "$CHROOT" env PATH=/opt/node24/bin:/usr/local/bin:/usr/bin:/bin \
       HOME=/root npm_config_userconfig=/etc/epixos/npmrc \
       npm install -g --no-fund --no-audit \
       --allow-scripts=node-pty,koffi,@deepseek-ai/dsh-subprocess-local,protobufjs,@google/genai \
       @deepseek-ai/dsh > "$BUILD/dsh-install.log" 2>&1; then
    chroot "$CHROOT" /opt/node24/bin/node -e 'console.log("dsh:", require("child_process").execSync("dsh --version").toString().trim())' 2>/dev/null \
      | tee -a "$LOG" || c_warn "dsh sürüm okunamadı"
    # node-pty / koffi derleme araçları kalabilir; temizle
    chroot "$CHROOT" sh -c 'rm -rf /root/.npm /root/.cache /tmp/*' 2>/dev/null || true
  else
    c_warn "dsh kurulumu başarısız (ağ/npm) — çalışma anında 'epix-ai install' ile kurulur"
    tail -8 "$BUILD/dsh-install.log" | sed 's/^/    /' >&2
  fi
else
  c_warn "node24 yok — dsh çalışma anında kurulacak (epix-ai setup)"
fi

# dconf veritabanı
if chroot "$CHROOT" command -v dconf >/dev/null 2>&1; then
  chroot "$CHROOT" dconf update 2>&1 | tee -a "$LOG" | sed 's/^/    /' || c_warn "dconf update uyarı verdi"
fi

# ---- katman doğrulaması (SSH / ağ / AI / donanım) ----
c_ok "katmanlar doğrulanıyor"
check_layer() {
  local name="$1"; shift
  if chroot "$CHROOT" sh -c "$*" >/dev/null 2>&1; then
    c_ok "  ✓ $name"
  else
    c_warn "  ✗ $name — EKSİK"
    LAYER_FAIL=$((LAYER_FAIL+1))
  fi
}
LAYER_FAIL=0
check_layer "sshd kurulu"        "command -v sshd || test -x /usr/sbin/sshd"
check_layer "ssh enable"         "test -e /etc/systemd/system/ssh.service.wants/ssh.service -o -e /etc/systemd/system/multi-user.target.wants/ssh.service -o -e /etc/systemd/system/sshd.service.wants/sshd.service"
check_layer "epix-ssh aracı"     "test -x /usr/local/bin/epix-ssh"
check_layer "epix-hw aracı"      "test -x /usr/local/bin/epix-hw"
check_layer "epix-ai aracı"      "test -x /usr/local/bin/epix-ai"
check_layer "epix-ai.service"    "test -f /etc/systemd/system/epix-ai.service"
check_layer "NetworkManager"     "command -v nmcli"
check_layer "X sunucusu (Xorg)"  "test -x /usr/lib/xorg/Xorg"
check_layer "X sürücü modülleri" "test \"\$(ls /usr/lib/xorg/modules/drivers 2>/dev/null | wc -l)\" -gt 0"
check_layer "epix-doctor aracı"  "test -x /usr/local/bin/epix-doctor"
# shell betiklerinin SÖZDİZİMİ doğru olmalı — bozuk profile.d her oturum açılışında
# "hata var" uyarısı üretiyor (yaşandı: heredoc'ta esacfi -> fazladan fi)
check_layer "profile.d sözdizimi" "for f in /etc/profile.d/*.sh; do bash -n \"\$f\" || exit 1; done"
check_layer "epix-rescue aracı"  "test -x /usr/local/bin/epix-rescue"
# NOT: /lib -> usr/lib symlink olduğu için firmware gerçekte usr/lib/firmware altında.
# Ayrıca firmware dosyaları .zst sıkıştırılmış olabilir (iwlwifi-*.ucode.zst).
check_layer "wifi firmware"      "ls /usr/lib/firmware/iwlwifi-* /usr/lib/firmware/rtlwifi /usr/lib/firmware/brcm /usr/lib/firmware/ath10k >/dev/null 2>&1"
check_layer "firmware dosya sayısı (>1000)" "test \"$(find /usr/lib/firmware -type f 2>/dev/null | wc -l)\" -gt 1000"
check_layer "node24 (~200MB)"    "test -x /opt/node24/bin/node"
check_layer "dsh kurulu"         "test -x /opt/node24/lib/node_modules/@deepseek-ai/dsh/lib/bin.js || command -v dsh >/dev/null"
# NOT: $(...) HOST kabuğunda açılır, chroot'ta değil. Bu yüzden iç içe
# komutlar \$ ile kaçırılmalı; aksi halde kontrol chroot dışında hesaplanır
# ve her zaman başarısız olur (yaşandı: anahtar deposu izin yanlış uyarısı).
check_layer "anahtar deposu izin" "test \"\$(stat -c %a /opt/epixos/dsh 2>/dev/null)\" = 700 -o ! -e /opt/epixos/dsh"
check_layer "AI anahtarı gömülü DEĞİL" "! grep -qsE 'sk-[A-Za-z0-9]{20,}' /etc/epixos/ai.env /opt/epixos/dsh/.credentials.yaml 2>/dev/null"
check_layer "casper yapılandırma" "test -f /etc/casper.conf"
check_layer "udev zaman aşımı"   "grep -qs event_timeout /etc/udev/udev.conf.d/50-epixos.conf"
[[ $LAYER_FAIL -eq 0 ]] || c_warn "$LAYER_FAIL katman eksik — ISO üretimi devam ediyor"

# ================================================================ 4b) SSH HOST ANAHTARLARI
# Hook chroot içinde `ssh-keygen -A` çağırıyor ama bazı ortamlarda sessizce atlıyor.
# Burada HOST'ta (root olarak) üretip chroot'a kopyalıyoruz — kesin çözüm.
# Not: canlı ISO için anahtarlar ISO'ya gömülür; kalıcı kurulumda yeniden üretilir.
c_ok "SSH host anahtarları hazırlanıyor"
mkdir -p "$CHROOT/etc/ssh"
KEYTMP="$BUILD/sshkeys"
rm -rf "$KEYTMP"; mkdir -p "$KEYTMP"
for t in ed25519 ecdsa rsa; do
  ssh-keygen -q -t "$t" -N "" -C "epixos@live" -f "$KEYTMP/ssh_host_${t}_key" 2>/dev/null || true
done
if [[ -f "$KEYTMP/ssh_host_ed25519_key" ]]; then
  cp -f "$KEYTMP"/ssh_host_* "$CHROOT/etc/ssh/"
  chmod 600 "$CHROOT"/etc/ssh/ssh_host_*_key
  chmod 644 "$CHROOT"/etc/ssh/ssh_host_*_key.pub
  c_ok "  $(ls -1 "$KEYTMP" | grep -c '_key$') host anahtarı chroot'a kopyalandı"
else
  c_warn "  host anahtarı üretilemedi — servis açılışta üretecek"
fi
rm -rf "$KEYTMP"

# ================================================================ 5) INITRAMFS
c_step "5/7 initramfs (casper dahil)"
KVER="$(ls "$CHROOT"/boot/vmlinuz-*-generic 2>/dev/null | sed 's|.*vmlinuz-||' | sort -V | tail -1 || true)"
[[ -n "$KVER" ]] || die "çekirdek bulunamadı (/boot/vmlinuz-*-generic)"
c_ok "çekirdek: $KVER"

cat > "$CHROOT/etc/initramfs-tools/conf.d/epixos.conf" <<'EOF'
# epixOS: canlı önyükleme için ölçülü initramfs
COMPRESS=zstd
MODULES=most
EOF

# overlayfs çekirdekte modül (=m) — initramfs'e AÇIKÇA eklenmeli.
# casper "modprobe overlay" başarısız olursa panic eder.
for m in overlay squashfs loop; do
  grep -qx "$m" "$CHROOT/etc/initramfs-tools/modules" 2>/dev/null || echo "$m" >> "$CHROOT/etc/initramfs-tools/modules"
done

# güvenlik ağı: hook'a overlay'i zorla ekle (MODULES ayarından bağımsız)
mkdir -p "$CHROOT/etc/initramfs-tools/hooks"
cat > "$CHROOT/etc/initramfs-tools/hooks/epixos-overlay" <<'HOOKEOF'
#!/bin/sh
# epixOS: casper overlayfs için overlay modülünü initramfs'e zorla koy
PREREQ=""
prereqs() { echo "$PREREQ"; }
case "$1" in prereqs) prereqs; exit 0 ;; esac
. /usr/share/initramfs-tools/hook-functions
for m in overlay squashfs loop; do
  manual_add_modules "$m" 2>/dev/null || true
done
exit 0
HOOKEOF
chmod +x "$CHROOT/etc/initramfs-tools/hooks/epixos-overlay"
cat >> "$CHROOT/etc/initramfs-tools/modules" <<'EOF'
# epixOS — canlı ISO için gerekli modüller
overlay
squashfs
loop
vfat
ext4
nls_utf8
nls_cp437
EOF

# initramfs ~60-90 sn sürer, çubukla izle
run_progress "initramfs oluşturuluyor" 75 "casper + overlay modülleri" \
  -- chroot "$CHROOT" update-initramfs -u -k "$KVER" > "$BUILD/initramfs.log" 2>&1 \
  || c_warn "initramfs uyarıları: $(tail -3 "$BUILD/initramfs.log" | tr '\n' ' ')"
[[ -f "$CHROOT/boot/initrd.img-$KVER" ]] || die "initrd üretilemedi"
c_ok "initramfs hazır: $(du -h "$CHROOT/boot/initrd.img-$KVER" | cut -f1)"

# live-boot / casper betikleri initramfs'te mi?
chroot "$CHROOT" bash -c "lsinitramfs /boot/initrd.img-$KVER 2>/dev/null | grep -q 'scripts/casper'" \
  && c_ok "casper initramfs içinde" || c_warn "casper initramfs'te görünmüyor!"

# ================================================================ 6) SQUASHFS
c_step "6/7 squashfs oluşturuluyor (${EPIX_COMP:-xz}, ilerleme aşağıda)"
rm -rf "$ISOTREE"
mkdir -p "$ISOTREE/casper" "$ISOTREE/.disk" "$ISOTREE/boot/grub"

# temizlik: makine kimliği, geçici dosyalar, apt önbelleği
chroot "$CHROOT" apt-get clean 2>/dev/null || true
rm -rf "$CHROOT"/var/lib/apt/lists/* "$CHROOT"/var/cache/apt/archives/*.deb
rm -rf "$CHROOT"/tmp/* "$CHROOT"/var/tmp/* "$CHROOT"/root/.*history 2>/dev/null || true
: > "$CHROOT/etc/machine-id"
# NOT: /etc/ssh/ssh_host_* BURADA SİLİNMEZ.
# Anahtarlar 4b adımında üretiliyor ve canlı ISO'da hazır olması isteniyor
# (ssh.service'in ExecStartPre'si yedek olarak yine üretir).
# Kalıcı kurulumda bu anahtarlar kurulum sırasında yeniden üretilmelidir.
: > "$CHROOT/etc/fstab"

# casper-md5check: canlı önyüklemede 1.8 GB ISO'nun md5'ini hesaplıyor ve
# QEMU ölçümünde 1 dk 46 sn boyunca systemd'yi bloke etti. USB 2.0 + eski CPU'da
# bu 5-15 dakika sürer, ekranda hiçbir şey görünmez -> "siyah ekranda kaldı".
# Bütünlük kontrolü ISO yazıldıktan sonra yapılabilir; önyüklemede gerekmiyor.
# Servisi silmiyoruz; yalnızca önyükleme zincirinden çıkarıyoruz.
# Elle kontrol: sudo systemctl start casper-md5check
rm -f "$CHROOT/etc/systemd/system/multi-user.target.wants/casper-md5check.service" 2>/dev/null || true
rm -f "$CHROOT/etc/systemd/system/local-fs.target.wants/casper-md5check.service" 2>/dev/null || true
find "$CHROOT/etc/systemd/system" -maxdepth 2 -name "casper-md5check.service" -type l -delete 2>/dev/null || true

# plymouth: eski GPU'da grafik modu kuramayınca ekranı tamamen karartıyor.
# Metin tabanlı açılış her donanımda görünür.
if [[ -e "$CHROOT/usr/bin/plymouth" ]]; then
  ln -sf /usr/share/plymouth/themes/text/text.plymouth "$CHROOT/etc/alternatives/default.plymouth" 2>/dev/null || true
fi

cleanup
trap - EXIT INT TERM

verify_clean

# Sıkıştırma seçimi: EPIX_COMP=xz (varsayılan, en küçük) | zstd (hızlı, ~%15 büyük)
# Ölçüm (1068 MB kaynak): xz 82 sn / 248 MB — zstd-19 45 sn / 286 MB
case "${EPIX_COMP:-xz}" in
  zstd)
    SQ_OPTS=(-comp zstd -Xcompression-level 19 -b 1M)
    c_ok "  sıkıştırma: zstd -19 (hızlı mod)"
    ;;
  *)
    SQ_OPTS=(-comp xz -Xbcj x86 -b 1M)
    c_ok "  sıkıştırma: xz (en küçük)"
    ;;
esac

# mksquashfs GERÇEK yüzde basar ("[====-] 3895/3895 100%") ama satırı \r ile
# sildiği için dosyaya yazınca görünmez. Bir izleyici ile yakalayıp çubuk çiziyoruz.
MKSQLOG="$BUILD/mksquashfs.log"
: > "$MKSQLOG"

# İzleyici: log dosyasından son yüzdeyi okur, çubuğu günceller
mksq_monitor() {
  # mksquashfs -percentage her saniye tek bir sayı yazar ("7", "23", "100").
  # Dosyaya yönlendirmede bile akıcı çalışır (ölçüldü: 1,2,7,10,16,21,24,26...).
  local log="$1" t0 now el pct est
  local last_pct=0 last_el=0
  t0=$(date +%s)
  while :; do
    now=$(date +%s); el=$(( now - t0 ))

    # İzleyici ASLA ölmemeli: her komut hata toleranslı olmalı.
    # (grep eşleşme bulamazsa exit 1 döner; pipefail + set -e izleyiciyi öldürür.)
    pct=$(tr '\r' '\n' < "$log" 2>/dev/null | grep -E '^[0-9]{1,3}$' | tail -1 || true)
    [[ -z "$pct" ]] && pct=0
    [[ "$pct" =~ ^[0-9]+$ ]] || pct=0
    [[ "$pct" -gt 100 ]] && pct=100

    # Kalan süre: ilerleme değiştiğinde yeniden hesapla (yoksa sayaç kaçar)
    if [[ "$pct" -gt 3 ]] && [[ "$pct" != "$last_pct" ]]; then
      est=$(( el * 100 / pct )); last_pct=$pct; last_el=$el
    elif [[ "$last_pct" -gt 0 ]]; then
      # son ölçümdeki hızdan kalan süreyi koru
      est=$(( last_el * 100 / last_pct ))
    else
      est=$(( el + 240 ))
    fi
    [[ $est -lt $el ]] && est=$el

    local filled=$(( pct * 40 / 100 ))
    [[ $filled -gt 40 ]] && filled=40; [[ $filled -lt 0 ]] && filled=0
    local bar="$(printf '%*s' "$filled" '' | tr ' ' '#')$(printf '%*s' $(( 40 - filled )) '' | tr ' ' '.')"

    printf '\r  \033[1;36m[%s]\033[0m %3d%%  geçen %d:%02d  ~%s kaldı\033[K' \
      "$bar" "$pct" $(( el/60 )) $(( el%60 )) "$(_pfmt "$el" "$est")"

    [[ -f "$log.done" ]] && break
    sleep 1
  done
  printf '\r  \033[1;36m[%s]\033[0m 100%%  tamamlandı\033[K\n' \
    "$(printf '%*s' 40 '' | tr ' ' '#')"
}

mksq_monitor "$MKSQLOG" &
MON_PID=$!

# /boot squashfs'e DAHİL EDİLMELİ.
# Calamares kurulumundan sonra hedef sistemin /boot/vmlinuz-* ve
# /boot/initrd.img-* dosyalarına ihtiyacı var: `initramfs` modülü
# update-initramfs çağırır, `bootloader` modülü grub-mkconfig ile menü
# üretir. /boot dışlanırsa kurulum "no kernel found" ile durur.
# Maliyet: vmlinuz 15 MB + initrd 70 MB (ISO bütçesi 2.3 GB, rahat).
set +e
mksquashfs "$CHROOT" "$ISOTREE/casper/filesystem.squashfs" \
      "${SQ_OPTS[@]}" -noappend -percentage \
      -no-exports \
      -e .bootstrap-done \
      -e 'dev/*' -e 'proc/*' -e 'sys/*' -e 'run/*' \
      > "$MKSQLOG" 2>&1
MKSQ_RC=$?
set -e
: > "$MKSQLOG.done"
wait "$MON_PID" 2>/dev/null || true
rm -f "$MKSQLOG.done"

if [[ $MKSQ_RC -ne 0 ]]; then
  # Sinyal ile kesildi mi? 128+15=143 (SIGTERM), 128+2=130 (SIGINT/Ctrl+C),
  # 128+9=137 (SIGKILL). Bu durumda "hata" değil, kullanıcı durdurmuştur.
  if [[ $MKSQ_RC -eq 130 || $MKSQ_RC -eq 143 || $MKSQ_RC -eq 137 ]]; then
    c_warn "derleme elle durduruldu (sinyal $((MKSQ_RC-128))) — squashfs yarım kaldı"
    c_warn "yeniden başlatmak için aynı komutu çalıştır; mevcut chroot korunur"
    exit 130
  fi
  c_err "mksquashfs hatası (çıkış kodu $MKSQ_RC):"
  tr '\r' '\n' < "$MKSQLOG" | tail -20 >&2
  exit 1
fi
c_ok "filesystem.squashfs: $(du -h "$ISOTREE/casper/filesystem.squashfs" | cut -f1)"

cp -f "$CHROOT/boot/vmlinuz-$KVER"  "$ISOTREE/casper/vmlinuz"
cp -f "$CHROOT/boot/initrd.img-$KVER" "$ISOTREE/casper/initrd.img"
echo "epixOS ${VERSION} (${RELEASE}) ${CODENAME} - ${ARCH}" > "$ISOTREE/.disk/info"
echo "$(date -u +%Y-%m-%d)" > "$ISOTREE/.disk/mkdate"

# ================================================================ 7) GRUB + ISO
c_step "7/8 GRUB menüsü ve ISO kalıbı"

# ── AÇILIŞ PARAMETRELERİ ────────────────────────────────────────────────
# vga=791 = 1024x768x16 VESA framebuffer.
#
# NEDEN GEREKLİ (B560 / Intel Ironlake 8086:0046 kanıtı):
# Bu parametre olmadan kernel, paneli i915'e devrederken LVDS init sırası
# bozuluyor; X 1366x768 modunu kuruyor, gnome-shell çiziyor (fb0'da
# RGB(46,52,54) doğrulandı), backlight %100 — ama panel fiziksel olarak
# sinyal üretmiyor ve ekran SİYAH kalıyor.
# vga=791 eklendiğinde aynı donanımda masaüstü anında geliyor.
# Pardus 25.0 da bu makinede tam olarak vga=791 kullanıyor.
#
# "quiet splash" KALDIRILDI: eski donanımda plymouth grafik modu
# kuramayınca ekran kararıyor ve sistem donmuş sanılıyor.
BOOT_ARGS="boot=casper verbose showmounts console=tty0 vga=791 locale=tr_TR.UTF-8 console-setup/layoutcode=tr keyboard-configuration/layoutcode=tr keyboard-configuration/variantcode= timezone=Europe/Istanbul hostname=epixos username=live ---"

# GRUB: eski BIOS'larda "gfxmode=auto" grafik modu kuramayınca menü okunamaz
# hale geliyor / ekran kararıyor. Önce metin modunda çalış, gfxterm varsa geç.
cat > "$ISOTREE/boot/grub/grub.cfg" <<EOF
# epixOS ${VERSION} (${RELEASE}) — canlı önyükleme
set default=0
set timeout=10
set timeout_style=menu

set gfxmode=1024x768,800x600,auto
# gfxpayload=keep: menü grafik modunu çekirdeğe devret, mod değişimi paneli bozmasın
set gfxpayload=keep
if loadfont /boot/grub/fonts/unicode.pf2 ; then
    insmod all_video
    insmod gfxterm
    insmod vbe
    insmod vga
    terminal_output gfxterm
fi

# vga=791 = 1024x768x16 VESA framebuffer (B560 Ironlake panel düzeltmesi)
menuentry "epixOS ${VERSION} (${RELEASE}) — Canlı Oturum" {
    linux /casper/vmlinuz $BOOT_ARGS
    initrd /casper/initrd.img
}

menuentry "epixOS ${VERSION} — Ayrıntılı (açılış mesajları)" {
    linux /casper/vmlinuz boot=casper verbose showmounts console=tty0 vga=791 locale=tr_TR.UTF-8 hostname=epixos username=live ---
    initrd /casper/initrd.img
}

menuentry "epixOS ${VERSION} — Güvenli Mod (VESA, hızlandırma yok)" {
    linux /casper/vmlinuz boot=casper verbose showmounts console=tty0 vga=791 nouveau.modeset=0 i915.enable_psr=0 i915.enable_fbc=0 locale=tr_TR.UTF-8 hostname=epixos username=live ---
    initrd /casper/initrd.img
}

menuentry "epixOS ${VERSION} — Uyumluluk Modu (çok eski donanım)" {
    linux /casper/vmlinuz boot=casper verbose showmounts console=tty0 vga=791 nomodeset i915.modeset=0 nouveau.modeset=0 video=1024x768 locale=tr_TR.UTF-8 hostname=epixos username=live ---
    initrd /casper/initrd.img
}

menuentry "epixOS ${VERSION} — Metin Modu (grafik yok)" {
    linux /casper/vmlinuz boot=casper verbose showmounts console=tty0 vga=normal systemd.unit=multi-user.target nomodeset locale=tr_TR.UTF-8 hostname=epixos username=live ---
    initrd /casper/initrd.img
}

menuentry "Yeniden Başlat" { reboot }
menuentry "Kapat" { halt }
EOF

# GRUB marka (logo + renkler)
cat > "$ISOTREE/boot/grub/theme-epixos.cfg" <<'EOF'
set menu_color_normal=cyan/black
set menu_color_highlight=black/cyan
set gfxmode=auto
EOF

( cd "$ISOTREE" && find . -type f -print0 | xargs -0 md5sum > md5sum.txt 2>/dev/null ) || true

rm -f "$DIST/$ISO_NAME"
c_ok "  ISO kalıbı yazılıyor (~1.8 GB, çubuk ilerlemeyi gösterir)"
set +e
grub-mkrescue --compress=xz -o "$DIST/$ISO_NAME" "$ISOTREE" \
     -- -volid "EPIXOS_${RELEASE//./_}" > "$BUILD/mkrescue.log" 2>&1 &
MK_PID=$!
set -e
# ISO dosyası büyüdükçe yüzde hesapla (hedef: chroot boyutu kadar)
TARGET_MB=$(du -sm "$CHROOT" 2>/dev/null | cut -f1); TARGET_MB=$(( TARGET_MB * 55 / 100 ))
[[ "$TARGET_MB" -lt 100 ]] && TARGET_MB=1800
t0=$(date +%s)
while kill -0 "$MK_PID" 2>/dev/null; do
  now=$(date +%s); el=$(( now - t0 ))
  cur=0
  if [[ -f "$DIST/$ISO_NAME" ]]; then
    cur=$(stat -c %s "$DIST/$ISO_NAME" 2>/dev/null || true)
    [[ -z "$cur" ]] && cur=0
  fi
  cur_mb=$(( cur / 1048576 ))
  pct=$(( cur_mb * 100 / TARGET_MB )); [[ $pct -gt 99 ]] && pct=99; [[ $pct -lt 0 ]] && pct=0
  filled=$(( pct * 40 / 100 )); [[ $filled -gt 40 ]] && filled=40
  bar="$(printf '%*s' "$filled" '' | tr ' ' '#')$(printf '%*s' $(( 40 - filled )) '' | tr ' ' '.')"
  if [[ $pct -gt 3 ]]; then est=$(( el * 100 / pct )); else est=$(( el + 200 )); fi
  [[ $est -lt $el ]] && est=$el
  printf '\r  \033[1;36m[%s]\033[0m %3d%%  %d MB  kalan~%s\033[K' \
    "$bar" "$pct" "$cur_mb" "$(_pfmt "$el" "$est")"
  sleep 1
done
MK_RC=0; wait "$MK_PID" || MK_RC=$?
printf '\r  \033[1;36m[%s]\033[0m 100%%  ISO hazır\033[K\n' "$(printf '%*s' 40 '' | tr ' ' '#')"
if [[ $MK_RC -ne 0 ]]; then
  c_err "grub-mkrescue hatası:"; tail -20 "$BUILD/mkrescue.log" >&2; exit 1
fi

( cd "$DIST" && sha256sum "$ISO_NAME" > "$ISO_NAME.sha256" )

# ================================================================ 8) ISO İÇİ DOĞRULAMA
# ISO'nun İÇİNDEKİ initramfs'i açıp casper.conf'u denetler.
# Amaç: BUILD_SYSTEM yanlışsa (-> casper "no support found" panic) USB'ye yazmadan yakalamak.
c_step "8/8 ISO içeriği doğrulanıyor (USB'ye yazmadan önce)"
VERIFY_FAIL=0
TP="$(mktemp -d)"
if xorriso -osirrox on -indev "$DIST/$ISO_NAME" -extract /casper/initrd.img "$TP/initrd.img" 2>/dev/null \
   && [[ -f "$TP/initrd.img" ]]; then
  mkdir -p "$TP/x"
  unmkinitramfs "$TP/initrd.img" "$TP/x" 2>/dev/null || true
  CONF="$(find "$TP/x" -name casper.conf 2>/dev/null | head -1 || true)"
  if [[ -n "$CONF" ]]; then
    BS="$(sed -n 's/.*BUILD_SYSTEM="\([^"]*\)".*/\1/p' "$CONF")"
    if [[ "$BS" == "Ubuntu" || "$BS" == "Debian" ]]; then
      c_ok "  ✓ initramfs casper.conf BUILD_SYSTEM=$BS (MP_QUIET=-q, overlay panic yok)"
    else
      c_err "  ✗ initramfs casper.conf BUILD_SYSTEM='$BS' — BU ISO AÇILMAZ (overlay panic)!"
      VERIFY_FAIL=$((VERIFY_FAIL+1))
    fi
    c_ok "  ✓ casper.conf initramfs içinde"
  else
    c_err "  ✗ initramfs içinde casper.conf YOK — canlı oturum başlamaz"
    VERIFY_FAIL=$((VERIFY_FAIL+1))
  fi
  # overlay modülü initramfs'te mi (herhangi katman)
  if find "$TP/x" -name 'overlay.ko*' 2>/dev/null | grep -q .; then
    c_ok "  ✓ overlay modülü initramfs içinde"
  else
    c_warn "  ✗ overlay modülü initramfs'te yok (casper modprobe başarısız olabilir)"
    VERIFY_FAIL=$((VERIFY_FAIL+1))
  fi
else
  c_warn "  initramfs ISO'dan çıkarılamadı — doğrulama atlandı"
fi
rm -rf "$TP"

# squashfs içeriği: ISO'dan 1.7 GB çıkarmaya GEREK YOK.
# $ISOTREE/casper/filesystem.squashfs ISO'ya yazılan dosyanın kendisidir,
# doğrudan onu okumak hem hızlı hem doğru.
SFS="$ISOTREE/casper/filesystem.squashfs"
if [[ -f "$SFS" ]]; then
  SFS_LIST="$(mktemp)"
  unsquashfs -l "$SFS" > "$SFS_LIST" 2>/dev/null || true
  # casper-md5check önyükleme zincirinde OLMAMALI (dakikalarca siyah ekran).
  # DİKKAT: yalnızca /etc/systemd/system altındaki GERÇEK enable link'lerine bakılır.
  # /var/lib/systemd/deb-systemd-helper-enabled/... dpkg kayıt dosyasıdır, zararsızdır;
  # onu da saymak yanlış alarm veriyordu.
  # `|| true` ZORUNLU: grep eşleşme bulamazsa exit 1 döner; set -e script'i
  # SESSİZCE öldürür. Bu yüzden 8/8 doğrulaması ortada kesiliyordu.
  MD5WANT="$(grep -E "^squashfs-root/etc/systemd/system/.*casper-md5check" "$SFS_LIST" 2>/dev/null || true)"
  if [[ -n "$MD5WANT" ]]; then
    c_warn "  ✗ casper-md5check hâlâ önyüklemede etkin — uzun siyah ekran riski"
    VERIFY_FAIL=$((VERIFY_FAIL+1))
  else
    c_ok "  ✓ casper-md5check önyüklemeden çıkarıldı"
  fi
  if [[ -s "$SFS_LIST" ]]; then
    # ZORUNLU: kök dizinler squashfs'te BULUNMALI.
    # mksquashfs `-e dev` dizinin KENDİSİNİ de hariç tutar; switch_root
    # /root/dev/console açamayınca init exit 1 verir -> panic exitcode=0x00000100.
    for d in /dev /proc /sys /run /tmp; do
      if grep -qx "squashfs-root$d" "$SFS_LIST"; then
        c_ok "  ✓ kök dizin: $d"
      else
        c_warn "  ✗ kök dizin YOK: $d — ISO AÇILMAZ (kernel panic exitcode=0x00000100)"
        VERIFY_FAIL=$((VERIFY_FAIL+1))
      fi
    done
    for f in "/etc/ssh/ssh_host_ed25519_key" "/etc/casper.conf" "/usr/local/bin/epix-ai" \
             "/opt/node24/bin/node" "/etc/systemd/system/epix-ai.service" \
             "/etc/dconf/db/local.d/00-epix-defaults" "/usr/share/backgrounds/epixos/epixos-default.svg" \
             "/usr/lib/xorg/Xorg" "/usr/local/bin/epix-doctor" "/usr/local/bin/epix-rescue" \
             "/usr/bin/epiphany-browser"; do
      if grep -qx "squashfs-root$f" "$SFS_LIST"; then
        c_ok "  ✓ squashfs: $f"
      else
        c_warn "  ✗ squashfs: $f EKSİK"
        VERIFY_FAIL=$((VERIFY_FAIL+1))
      fi
    done
  else
    c_warn "  squashfs listesi okunamadı — içerik doğrulaması atlandı"
  fi
  rm -f "$SFS_LIST"
else
  c_warn "  $SFS yok — içerik doğrulaması atlandı"
fi

if [[ $VERIFY_FAIL -gt 0 ]]; then
  c_err "DOĞRULAMA BAŞARISIZ ($VERIFY_FAIL sorun) — bu ISO'yu USB'ye YAZMAYIN."
  exit 1
fi
c_ok "ISO içeriği doğrulandı — USB'ye yazılabilir"

c_ok "ISO hazır: $DIST/$ISO_NAME ($(du -h "$DIST/$ISO_NAME" | cut -f1))"
c_ok "sha256: $(cut -d' ' -f1 "$DIST/$ISO_NAME.sha256")"
echo
c_warn "Not: 2 GB RAM hedefi için  ./build.sh run  (EPIX_RAM=2048)"
