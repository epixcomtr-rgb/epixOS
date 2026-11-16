#!/bin/bash
# epix-imager uctan uca test — loop cihazi sahte USB
# Gercek USB'ye dokunmadan tum akisi ve epix-setup okumasini dogrular.
set -e
WORK=/tmp/imitest
IMG=$WORK/usb.img
SIZE_MB=2600

echo "=== 1) SAHTE USB ($SIZE_MB MB) ==="
mkdir -p "$WORK"; rm -f "$IMG"
truncate -s ${SIZE_MB}M "$IMG"
LOOP=$(sudo losetup --find --show --partscan "$IMG")
sudo partprobe "$LOOP" 2>/dev/null || true
sleep 2
echo "  loop: $LOOP"
TB=$(sudo sgdisk --print "$LOOP" 2>/dev/null | grep -E "^\s+[0-9]" | sha256sum | cut -c1-16)
cleanup() { sudo losetup -d "$LOOP" 2>/dev/null || true; }
trap cleanup EXIT

echo
echo "=== 2) IMAGER YAZIYOR ==="
cd /home/aykut-altunoluk/epixOS/tools/epix-imager
sudo ./epix-imager \
  --iso /home/aykut-altunoluk/epixOS/dist/epixOS-0.1-2026.11-amd64.iso \
  --dev "$LOOP" \
  --user epix --password 5373726 --hostname epixos-test \
  --ssh --wifi-ssid TESTNET --wifi-password test1234 \
  --yes 2>&1 | grep -vE "^  yazılıyor" | tail -10

echo
echo "=== 3) BOLUM TABLOSU DEGISTI MI ==="
sudo partprobe "$LOOP" 2>/dev/null || true
TA=$(sudo sgdisk --print "$LOOP" 2>/dev/null | grep -E "^\s+[0-9]" | sha256sum | cut -c1-16)
echo "  once : $TB"
echo "  sonra: $TA"
[ "$TB" = "$TA" ] && echo "  ✓ DEGISMEDI (onyukleme korundu)" || echo "  ✗ DEGISTI"

echo
echo "=== 4) BLOB'U BUL VE OKU (epix-setup mantigi) ==="
TOTAL=$(sudo blockdev --getsz "$LOOP")
seek=$(( (TOTAL - 2048) / 2048 * 2048 ))
FOUND=""
for i in $(seq 1 64); do
  magic=$(sudo dd if="$LOOP" bs=512 skip=$seek count=1 status=none 2>/dev/null | dd bs=1 count=8 status=none 2>/dev/null || true)
  if [ "$magic" = "EPIXCFG1" ]; then FOUND=$seek; break; fi
  seek=$(( seek - 2048 ))
done

if [ -z "$FOUND" ]; then echo "  ✗ blob bulunamadi"; exit 1; fi
echo "  ✓ blob: sektor $FOUND"

PSIZE=$(sudo dd if="$LOOP" bs=1 skip=$(( FOUND*512 + 12 )) count=4 status=none 2>/dev/null | od -An -tu4 | tr -d ' \n')
echo "  yuk boyutu: $PSIZE bayt"

sudo dd if="$LOOP" bs=1 skip=$(( FOUND*512 + 32 )) count=$PSIZE status=none 2>/dev/null > "$WORK/payload.tar"
echo "  --- tar icerigi ---"
tar -tf "$WORK/payload.tar" | sed 's/^/    /'
rm -rf "$WORK/cfg"; mkdir -p "$WORK/cfg"
tar -xf "$WORK/payload.tar" -C "$WORK/cfg"

echo
echo "  --- epix-setup.conf ---"
grep -vE "^#|^$" "$WORK/cfg/epix-setup.conf" | sed 's/^/    /'
echo "  --- wifi ---"
grep -E "^(ssid|psk)=" "$WORK/cfg/wifi.nmconnection" | sed 's/^/    /'
echo "  --- parola ozeti ---"
head -c 30 "$WORK/cfg/user-password.crypt" | sed 's/^/    /'; echo "..."

echo
echo "=== 5) ONYUKLEME ==="
MAGIC=$(sudo dd if="$LOOP" bs=1 skip=510 count=2 status=none 2>/dev/null | xxd -p)
echo "  MBR imza: $MAGIC $([ "$MAGIC" = "55aa" ] && echo '✓' || echo '✗')"
GRUBTXT=$(sudo dd if="$LOOP" bs=512 count=1 status=none 2>/dev/null | strings | grep -c GRUB || true)
echo "  MBR'de GRUB: $GRUBTXT"
LABEL=$(sudo blkid -s LABEL -o value ${LOOP}p3 2>/dev/null)
echo "  ISO bolumu etiketi: ${LABEL:-?}"

echo
echo "=== TEST TAMAM ==="
