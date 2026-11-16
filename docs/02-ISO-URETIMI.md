# ISO Üretimi — adım adım

**Sürüm:** epixOS `0.1` · yayın `2026.11` · kod adı `kavak` · `epixOS-0.1-2026.11-amd64.iso`

## 0. Ön koşullar (tek sefer)

```bash
cd ~/epixOS
./build.sh setup          # live-build, debootstrap, xorriso, squashfs-tools, qemu
```

Kurulacak araçlar ve görevleri:

| Paket | Görev |
|---|---|
| `live-build` | ISO üretim motoru |
| `debootstrap` | boş kök dosya sistemini kurar |
| `xorriso`, `mtools`, `dosfstools` | ISO kalıbı + EFI önyükleme bölümü |
| `squashfs-tools` | kök fs'i sıkıştırır |
| `qemu-system-x86` | ISO'yu diske yazmadan test eder |

## 1. Yapılandırmayı üret

```bash
./build.sh validate   # paket adları + betik sözdizimi + SVG denetimi
./build.sh config
```

Bu komut `iso/` içinde `lb config` çalıştırır ve `iso/auto/config` dosyasındaki değerleri uygular.

## 2. Derle

```bash
./build.sh build
```

İlk derleme **20–40 dakika** sürer (internet hızına göre), ~3–5 GB geçici alan kullanır.
Süreç: `debootstrap` → paket kurulumu → hook'lar → squashfs → ISO kalıbı.

Bittiğinde:

```
dist/epixOS-0.1-2026.11-amd64.iso
```

## 3. Test et (diske yazmadan)

```bash
./build.sh run            # QEMU, 2 GB RAM (hedef donanım), UEFI
EPIX_RAM=4096 ./build.sh run   # daha rahat deneme için
```

QEMU'da kontrol listesi:

- [ ] GRUB menüsü çıkıyor, "epixOS Live" seçilebiliyor
- [ ] GDM oturum açma ekranı geliyor (`live` kullanıcısı, şifresiz)
- [ ] GNOME masaüstü açılıyor, Türkçe klavye çalışıyor
- [ ] Ağ: `nmcli` ile Wi-Fi/Ethernet
- [ ] `sudo -i` çalışıyor
- [ ] Marka: duvar kağıdı, `hostnamectl`, `/etc/os-release` → `epixOS 0.1`
- [ ] Dil: `locale` → `tr_TR.UTF-8`, İngilizce Ayarlar'dan seçilebiliyor
- [ ] Klavye: Alt+Shift ile TR↔EN geçişi
- [ ] Bellek: `epix-memory-check` → boşta ≤ 850 MB, zram etkin
- [ ] İlk açılış sihirbazı (gnome-initial-setup) çıkmıyor

Gerçek donanımda denemek için:

```bash
sudo dd if=dist/epixOS-0.1-2026.11-amd64.iso of=/dev/sdX bs=8M status=progress oflag=sync
```
(`/dev/sdX` **doğru** aygıt olmalı — yanlış yazma diski siler. USB bellek önerilir.)

## 4. Sık karşılaşılan hatalar

| Hata | Sebep / çözüm |
|---|---|
| `E: Unable to locate package linux-image-generic` | `auto/config` içinde `--mirror-*` Ubuntu arşivini göstermiyor |
| `debootstrap` imza hatası | `--keyring-packages ubuntu-keyring` ekle |
| ISO 4 GB'ı aşıyor | `--compression xz` + `--apt-recommends false` kontrol et |
| GDM açılmıyor, siyah ekran | QEMU'da `-vga virtio` yerine `-vga std` dene; gerçek donanımda sürücü (`mesa`, `firmware-*`) eksik olabilir |
| **Gerçek donanımda X çalışıyor ama ekran siyah** | **`vga=791` eksik.** Intel Ironlake (B560) paneli bu parametre olmadan sinyal üretmiyor. `BOOT_ARGS` içinde `vga=791` olduğunu doğrula; detaylı kanıt: `docs/05-KARARLAR.md` |
| `Configure crtc 0 failed`, `Monitors: 0` | Mode değişimi panelde kurulamıyor; önce `vga=791` ekle, sonra `nomodeset`'i kaldır |
| `lb build` "no space left" | geçici alan: derleme `iso/` içinde yapılır, 10 GB boş alan bırak |
| Snap isteyen paket | `firefox` yerine `epiphany-browser` kullanıyoruz (bkz. `docs/03`) |

## 4.5 Derleme sonrası otomatik denetim

```bash
./scripts/verify-iso.sh
```

ISO boyutu, sha256, El Torito önyükleme kaydı, squashfs ve içindeki `/etc/os-release` değerlerini yazdırır.

## 5. Temizlik

```bash
./build.sh clean          # iso/chroot, iso/binary, iso/cache silinir
```

Yapılandırmayı sıfırlamak için `iso/config` ve `iso/auto` **korunur** — sadece derleme çıktısı silinir.

## 6. Sonraki sürümlerde

| Sürüm | Eklenecek |
|---|---|
| 0.2 | GNOME ince ayarları, marka, plymouth açılış animasyonu |
| 0.3 | `epixos-kernel` deb paketi + `--linux-packages` ile kendi çekirdeğimiz |
| 0.4 | Kendi APT deposu (`dist/repo`) + `epixos-archive-keyring` |
| 0.5 | Calamares kurulum sihirbazı → kurulabilir ISO |
| 1.0 | Kararlı sürüm, imzalı ISO (sha256 + GPG) |
