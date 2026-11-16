# epixOS

[![Sürüm](https://img.shields.io/badge/s%C3%BCr%C3%BCm-0.1%20(2026.11)-16404b)](https://os.epix.tr/indir/)
[![Lisans](https://img.shields.io/badge/lisans-GPL--3.0-16404b)](LICENSE)
[![Mimari](https://img.shields.io/badge/mimari-amd64-16404b)](https://os.epix.tr/indir/)
[![İndir](https://img.shields.io/badge/ISO-indir-c8e83f)](https://os.epix.tr/indir/)

**Türkçe** · [English](README.en.md)

Hafif, hızlı ve AI ile yönetilen Linux dağıtımı. GNOME masaüstü, **2 GB RAM'de akıcı**
çalışma, ilk açılıştan itibaren **açık SSH** ve **DeepSeek Harness** tabanlı bir AI ajanı.

> **İndir:** [os.epix.tr/indir](https://os.epix.tr/indir/) — 1.8 GB, amd64, canlı oturum + kurulum

---

## Özellikler

| | |
|---|---|
| **Hafif** | `gnome-core` tabanlı, boşta ~651 MB RAM. `ubuntu-desktop` değil. |
| **Hızlı** | Hedef ≤ 15 sn açılış. Snap yok, arka plan servisi en az. |
| **AI ajanı** | DeepSeek Harness, `127.0.0.1:3080`. Tüm yönetim prompt ile. |
| **SSH açık** | İlk açılıştan itibaren port 22. Ekransız çalışır (headless). |
| **Wi-Fi hazır** | Broadcom, Intel, Realtek firmware gömülü. |
| **Türkçe** | `tr_TR.UTF-8` varsayılan, `en_US.UTF-8` ikinci. Klavye `tr,us`. |
| **Uyumlu** | Eski donanımda takılmaz; `vga=791` ile Ironlake panelleri çalışır. |

## Sürüm

| | |
|---|---|
| Sürüm | `0.1` |
| Yayın | `2026.11` |
| Kod adı | `kavak` |
| Taban | Ubuntu 24.04 LTS (noble) |
| Çekirdek | Linux `6.8.0-149-generic` |
| Masaüstü | GNOME (`gnome-core`) |
| Tarayıcı | GNOME Web (epiphany) — snap yok |
| Önyükleme | Legacy BIOS (MBR) + UEFI |
| ISO | 1.8 GB · sha256 `c35f0a50fa101bee1682cc2eaaecf7c259ca50c8240b650ec97a98bd3efa26be` |

## Kurulum

Üç adım. Ayrıntılı anlatım: **[os.epix.tr/indir](https://os.epix.tr/indir/)**

### 1. İndir ve doğrula

```bash
curl -LO https://os.epix.tr/indir/epixOS-0.1-2026.11-amd64.iso
sha256sum epixOS-0.1-2026.11-amd64.iso
# c35f0a50fa101bee1682cc2eaaecf7c259ca50c8240b650ec97a98bd3efa26be
```

GitHub Releases üzerinden de indirilebilir:
[github.com/epixcomtr-rgb/epixOS/releases](https://github.com/epixcomtr-rgb/epixOS/releases)

### 2. USB'ye yaz

```bash
# Linux / macOS — /dev/sdX yerine kendi USB'ni yaz (rakam olmasın)
sudo dd if=epixOS-0.1-2026.11-amd64.iso of=/dev/sdX bs=4M status=progress oflag=sync
sync
```

Windows'ta [Rufus](https://rufus.ie/): bölüm şeması **MBR**, hedef **BIOS**,
"ISO Image mode".

### 3. Aç ve kur

USB'den önyükle (`F12`), GRUB menüsünde **epixOS — Canlı Oturum** seç.
Canlı oturumda hiçbir şey diske yazılmaz. Beğenirsen masaüstündeki
**epixOS Kur** simgesiyle diske kur.

## Depodan derleme

```bash
git clone https://github.com/epixcomtr-rgb/epixOS.git
cd epixOS

./build.sh setup      # gerekli araçlar (sudo)
./build.sh config     # paket listeleri + marka
./build.sh build      # ISO -> dist/epixOS-0.1-2026.11-amd64.iso
./build.sh run        # QEMU'da aç (2 GB RAM)
./scripts/verify-iso.sh   # derleme sonrası denetim
```

Derleme `sudo` ister, ~12 GB geçici alan kullanır, 30–60 dk sürer.
İlk `debootstrap` sonrası `build/chroot/.bootstrap-done` varsa tekrar atlanır.

## Depo yapısı

```
epixOS/
├── build.sh                 # setup / config / build / run / validate / clean
├── VERSION                  # 0.1, 2026.11, kavak
├── scripts/
│   ├── build-iso.sh         # debootstrap + casper + mksquashfs + grub-mkrescue
│   ├── verify-iso.sh        # derleme sonrası otomatik denetim (vga=791 dahil)
│   └── deploy-site.sh       # os.epix.tr yayına alma
├── iso/config/
│   ├── hooks/live/          # 6 chroot hook (donanım, SSH, marka, hafiflik, AI, teşhis)
│   ├── package-lists/       # 180 paket, 6 liste
│   └── includes.chroot/     # dconf, duvar kağıdı, .desktop
├── branding/                # logo + duvar kağıdı (SVG)
├── site/                    # os.epix.tr (statik)
└── docs/                    # 7 doküman: özet, mimari, ISO, GNOME, geliştirme, kararlar, SSH/AI
```

## Belgeler

| Dosya | İçerik |
|---|---|
| [docs/00-OZET.md](docs/00-OZET.md) | Kendi işletim sistemini yapmak: katmanlar, yol haritası |
| [docs/01-MIMARI.md](docs/01-MIMARI.md) | Klasörlerin görevleri |
| [docs/02-ISO-URETIMI.md](docs/02-ISO-URETIMI.md) | ISO üretimi + sık karşılaşılan hatalar |
| [docs/03-GNOME-HAFIF.md](docs/03-GNOME-HAFIF.md) | Hafif GNOME ayarları |
| [docs/04-GELISTIRME.md](docs/04-GELISTIRME.md) | Geliştirici araçları katmanı |
| [docs/05-KARARLAR.md](docs/05-KARARLAR.md) | Verilen kararlar, elenen seçenekler, donanım kanıtı |
| [docs/06-SSH-AG-DONANIM-AI.md](docs/06-SSH-AG-DONANIM-AI.md) | SSH, ağ/sürücü, donanım atlama, AI ajan |

## Donanım notu: eski Intel panelleri

Bazı eski Intel ekran kartlarında (Ironlake ve öncesi, örn. Lenovo B560)
çekirdek paneli devralırken sinyal üretmez: X 1366x768 kurar, GNOME çizer,
arka ışık %100 olur — **ama ekran siyah kalır**.

Çözüm: `vga=791` (1024x768x16 VESA framebuffer) kernel komut satırında.
epixOS bunu GRUB'da ve `/etc/default/grub.d/99-epixos.cfg` içinde gönderir.
`scripts/verify-iso.sh` bu parametrenin ISO'da olduğunu denetler.
Ayrıntılı kanıt zinciri: [docs/05-KARARLAR.md](docs/05-KARARLAR.md).

## Mevcut kurulumu güncelleme

ISO'yu yeniden kurmadan düzeltmeleri almak için `epixos-base` paketi:

```bash
# ISO'yu yeniden derledikten sonra paketi üret
sudo ./scripts/make-deb.sh
# -> dist/epixos-base_<sürüm>_all.deb

# hedef makinede
sudo dpkg -i epixos-base_*.deb
sudo apt -f install     # eksik bağımlılık varsa
```

Paket şunları taşır: yardımcı komutlar (`epix`, `epix-ssh`, `epix-hw`,
`epix-doctor`, `epix-ai`, …), `vga=791` GRUB ayarı, `nouveau` kara listesi ve
`epix-backlight.service`. `postinst` çalışırken GRUB ve initramfs'i yeniler.

> **Dikkat:** `postinst` içindeki `update-initramfs` çağrısı çekirdek sürümünü
> açıkça belirtir. Parametresiz çağrı, `/boot/vmlinuz-epixos` dosyasını gerçek
> çekirdek sanıp bozuk initramfs üretir ve sistemi açılmaz hale getirir.

## Katkı

```bash
git checkout -b ozellik/yeni-sey
# değiştir, derle, doğrula
./scripts/verify-iso.sh
git commit -m "feat: ..."
```

ISO'yu değiştiren her commit `verify-iso.sh` çıktısını PR'a eklemeli.

## Lisans

GPL-3.0. Ubuntu/Debian paketleri kendi lisanslarını taşır.

---

**Epix Software House** · [epix.tr](https://epix.tr/) · [os.epix.tr](https://os.epix.tr/)
