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
Canlı oturumda hiçbir şey diske yazılmaz.

Beğenirsen uygulama menüsünden **epixOS Kur**'u aç (ya da terminalde
`epix-install`). Calamares kurulum asistanı disk bölümlendirme, kullanıcı
hesabı, dil/klavye ve GRUB kurulumunu yapar. Kurulum sırasında:

- **Dil ve klavye:** Türkçe seçili gelir
- **Disk:** mevcut bölümleri koruyabilir ya da silip kurabilirsin
- **GRUB:** UEFI ve BIOS ikisi de desteklenir

> **Ironlake uyarısı:** Kurulum sonrası `vga=791` çekirdek parametresi
> `grub.cfg`'ye yazılır. Bu adım atlanırsa eski Intel ekran kartlarında
> ekran siyah kalır. Koruma `epix-grub-guard` modülünde; atlanamaz.

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

## Uygulama mağazası

İki yerde, **tek kaynaktan** beslenen bir katalog var:

| Yer | Ne |
|---|---|
| https://os.epix.tr/market | web mağazası — açıklama, boyut, kopyalanabilir kurulum komutu |
| `epix-market` | terminal komutu — aynı katalog, ağ gerekmez |

Tek kaynak: `catalog/katalog.json`. Bir uygulamayı oraya ekleyince
**ikisi birden** güncellenir:

```bash
./catalog/uret.py          # dist/epix-market + site/market/index.html üret
./catalog/uret.py --kontrol # sadece doğrula (bozuk JSON'da gürültülü hata)
```

> **Neden üretici betik:** katalog iki yerde elle tutulsaydı kaçınılmaz
> olarak ayrışırdı ve sitede gösterilen komut çalışmazdı. Üretici,
> kategori kimliği ve paket adı tekrarlarını da denetler.

### Grafik arayüz

```bash
epix-market-gui                # veya uygulama menüsünden "epixOS Mağaza"
```

GTK3 arayüzü: kategori sütunu, canlı arama, kart başına **Kur** / **Kaldır**
düğmesi, kurulu durumu otomatik tespit. Kurulum görünür bir uçbirimde
çalışır (`pkexec` ile yetki ister) — ilerlemeyi görürsün.

> **Neden gnome-software değil:** mağaza uygulaması ~120 MB bellek
> kullanır; 2 GB hedefli bir dağıtımda bu lüks değil. Bu arayüz aynı
> kataloğu okur ve ~35 MB kullanır. `python3-gi` + GTK3 zaten GNOME ile
> gelir, ek bağımlılık yok.

`python3`/GTK eksikse başlatıcı sessizce ölmez; ne kuracağını söyler ve
terminal sürümüne yönlendirir.

### Terminalde

```bash
epix-market                    # kategori özeti
epix-market liste              # tüm uygulamalar
epix-market liste grafik       # tek kategori
epix-market ara fotoğraf       # ad / açıklama / etiket araması
epix-market bilgi gimp         # detay + kurulum komutu
epix-market kur gimp vlc       # kur (sudo)
```

`epix-market` **`epixos-base`** paketiyle gelir. Katalog komutun içine
gömülüdür; `epix-market liste` için internet gerekmez.

### Kataloğa uygulama eklemek

`catalog/katalog.json` içindeki `uygulamalar` dizisine bir kayıt ekle:

```json
{
  "ad": "gimp",
  "paket": "gimp",
  "kategori": "grafik",
  "epix": false,
  "baslik": "GIMP",
  "aciklama": "Güçlü ve ücretsiz fotoğraf düzenleyici…",
  "boyut_mb": 95,
  "etiketler": ["fotoğraf", "resim", "düzenleme"]
}
```

Sonra `./catalog/uret.py && ./scripts/deploy-site.sh`.

> **Kural:** `paket` alanı noble (Ubuntu 24.04) depolarında **gerçekten
> var olmalı**. Olmayan paket yazmak, kullanıcıya çalışmayan komut
> vermek demektir. `apt-cache policy <paket>` ile doğrula.

## Tema ve modüller (APT deposu)

ISO'yu **yeniden derlemeden** tema ve modül güncellemesi alabilirsin.
Depo imzalıdır; paketlerin gerçekten epixOS'tan geldiği kriptografik
olarak doğrulanır.

**Tek seferlik kurulum:**

```bash
curl -fsSL https://os.epix.tr/indir/apt/epixos-archive-keyring.gpg \
  | sudo tee /usr/share/keyrings/epixos-archive-keyring.gpg >/dev/null
curl -fsSL https://os.epix.tr/indir/apt/epixos.list \
  | sudo tee /etc/apt/sources.list.d/epixos.list >/dev/null
sudo apt update
```

**Tema:**

```bash
sudo apt install epixos-tema
epix-tema --liste        # kurulu duvar kağıtları + etkin tema
epix-tema                # temayı yeniden uygula
```

Tema paketi şunları içerir: GTK3/GTK4 renk katmanı, GNOME Shell vurguları,
üç duvar kağıdı (koyu / açık / sade), dconf drop-in ve `epix-tema` komutu.
Renkler gerçek logodan örneklendi: lime `#e2ff5e`, navy `#16404b`,
deep `#0e2a31`.

> **Not:** GNOME Shell'in `gnome-shell.css` dosyasını kullanması için
> *User Themes* uzantısı gerekir. Uzantı yokken marka vurgusu GTK
> tarafında (uygulamalar, düğmeler, seçim) görünür — bu bilinçli bir
> tercih, uzantıyı zorla kurmak kırılganlık getirir.

**Paket üretimi (geliştirici):**

```bash
sudo ./scripts/make-theme-deb.sh   # -> dist/epixos-tema_<sürüm>_all.deb
sudo ./scripts/make-repo.sh        # depo indeksini yenile
./scripts/deploy-site.sh           # os.epix.tr/indir/apt/ altına yayınla
```

Paket `postinst`'i `dconf update` çağırır ve `/etc/dconf/profile/user`
yoksa oluşturur — ikisi olmadan yazılan ayarlar hiç okunmaz.

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
