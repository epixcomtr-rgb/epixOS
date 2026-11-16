# Kararlar ve Açık Sorular

## Verilen kararlar

| # | Karar | Gerekçe | Tarih |
|---|---|---|---|
| 1 | Taban: **Ubuntu 24.04 LTS (noble)** | GNOME + sürücü olgunluğu, 5 yıl destek, geniş paket havuzu | 2026-11-15 |
| 2 | Üretim: **kendi ISO üreticisi** (`debootstrap` + `casper` + `mksquashfs` + `grub-mkrescue`) | Ubuntu deposundaki `live-build` 3.0~a57 (2012) UEFI üretemiyor; kendi hattımız hem BIOS hem UEFI verir, tam kontrol | 2026-11-15 |
| 3 | Masaüstü: **GNOME (`gnome-core`) + hafif varsayılanlar** | Kullanıcı isteği + 2 GB RAM hedefi | 2026-11-15 |
| 4 | Mimari: **amd64** (x86_64) | Hedef donanım; arm64 sonra | 2026-11-15 |
| 5 | Önyükleme: **UEFI + BIOS (hibrit GRUB)** | Eski ve yeni donanım | 2026-11-15 |
| 6 | Tarayıcı: **epiphany-browser** | Ubuntu'da `firefox` snap'e yönlendiriyor; canlı ISO'da snap kırılgan | 2026-11-15 |
| 7 | Çekirdek: önce Ubuntu çekirdeği, **Aşama 3'te kendi derlememiz** | Risk yönetimi | 2026-11-15 |
| 8 | Kurulum sihirbazı: **Calamares** (Aşama 5) | Ubuntu Installer'dan bağımsız, özelleştirilebilir | 2026-11-15 |
| 9 | **Sürüm şeması: `0.1` + tarih `2026.11`** | Sürüm ilerlemesi (0.1→1.0) ve yayın tarihi ikisi de görünsün | 2026-11-15 |
| 10 | **ISO adı:** `epixOS-0.1-2026.11-amd64.iso` | Sürüm + yayın + mimari tek bakışta | 2026-11-15 |
| 11 | **Dil: TR birincil, EN ikincil** | `LANG=tr_TR.UTF-8`, `LANGUAGE=tr_TR:tr:en_US:en`, klavye `tr,us` (Alt+Shift), iki dil paketi de gömülü | 2026-11-15 |
| 12 | **Hedef donanım: 2 GB RAM** | zram (ram/2), swappiness=100, purge katmanı, animasyon kapalı, journal volatile | 2026-11-15 |
| 13 | **Kod adı: `kavak`** | 0.1 sürümünün kod adı | 2026-11-15 |
| 14 | **SSH ilk andan açık** | Kurulum/uzaktan yönetim gereksinimi; `live` kullanıcısı, şifre boş, root kapalı | 2026-11-15 |
| 15 | **WiFi/Ethernet firmware gömülü** | İnternet olmadan AI anahtarı girilemez → ağ ilk öncelik | 2026-11-15 |
| 16 | **Uyumsuz donanımda duraksamama** | wait-online/settle maskeli, udev 10s, `epix-hw block` | 2026-11-15 |
| 17 | **AI ajan: DeepSeek Harness (`dsh`)** | MIT, açık kaynak, web+CLI, çoklu sağlayıcı, ajan sistemi yönetebilir | 2026-11-15 |
| 18 | **Node.js 24 `/opt/node24`'e** | DSH Node ≥24.9 ister; apt'teki 18 yetmez, apt bozulmaz | 2026-11-15 |
| 19 | **API anahtarı ISO'ya gömülmez** | ISO'yu indiren herkes anahtarı okurdu; kullanıcı ilk açılışta girer | 2026-11-15 |
| 20 | **Persistence (kalıcılık) YOK** | Doğrudan diske kurulum yapılacak; USB'yi yazma ömrü/hız/güvenlik yükü alınmaz | 2026-11-15 |
| 21 | Kalıcı veri **gerçek kurulumla** sağlanır | `casper-rw` yerine normal disk bölümü; `apt upgrade` çalışır, tam hız | 2026-11-15 |
| 22 | **`vga=791` zorunlu** | Intel Ironlake (B560, 8086:0046) paneli bu parametre olmadan sinyal üretmiyor; X/GNOME çalışsa bile ekran siyah kalıyor. Pardus 25 de aynı makinede bunu kullanıyor | 2026-11-16 |
| 23 | **`nouveau` kara listede** | Optimus makinede hayalet `VGA-1-2` çıkışı masaüstünü 2390x768'e genişletiyor; 2 GB RAM'de ikinci sürücü gereksiz | 2026-11-16 |
| 24 | **Disk bölümlemede tablo değişmez** | Windows bölümü `mkfs.ext4` ile `/home` yapıldı; `sfdisk`/MBR'ye dokunulmadı → sıfır GRUB riski | 2026-11-16 |

## Kapalı sorular (karara bağlandı)

| Soru | Karar |
|---|---|
| Ad ve marka | Paket/dosya adlarında `epixos`, görünen ad **`epixOS`** ✅ |
| Sürüm | **`0.1` + `2026.11`** ✅ |
| Dil | **TR varsayılan, EN ikinci** (klavye Alt+Shift) ✅ |
| Hedef donanım | **2 GB RAM'de akıcı** ✅ |
| Kalıcılık | **Yok** — Aşama 5'te doğrudan diske kurulum ✅ |
| AI anahtarı koruması | USB'ye yazılmayacak; kurulumda kullanıcı hesabına bağlı kalacak ✅ |

## Açık sorular

5. **Lisans**: GPL-2.0 / MIT karışımı kabul mü, depo lisansı ne olacak?
6. **İmzalama anahtarı**: ISO ve depo için GPG anahtarı senin adına mı üretilsin?
7. **Plymouth açılış animasyonu** 0.1'de olsun mu, 0.2'ye mi kalsın?
8. **Calamares yerine kendi kurulum aracımız mı?** Calamares hızlı ama görünümü bize tam uymuyor.

## Kalıcılık neden elendi (kayıt)

| Konu | Canlı + persistence | Gerçek kurulum (seçilen) |
|---|---|---|
| Hız | USB + squashfs + overlay | Tam disk hızı |
| Güncelleme | Yeni ISO yazmak gerekir | `apt upgrade` |
| API anahtarı | USB'de düz metin (şifreleme yoksa) | Kullanıcı hesabında, LUKS mümkün |
| USB ömrü | Sürekli yazma flash'ı yorar | Disk |
| Karmaşıklık | `casper-rw` bölümü + menü girdisi + test yüzeyi | Standart kurulum |

Canlı oturum yine var: ISO **denemek/teşhis** için RAM'de çalışır, kalıcı kullanım için diske kurulur.

## Teknik bilinen riskler

| Risk | Etki | Azaltma |
|---|---|---|
| Ubuntu deposu değişirse tekrar üretim bozulur | Orta | `auto/config` yerine `build-iso.sh` içinde `EPIX_SUITE`/`EPIX_MIRROR` sabitlenir |
| Canlı oturumda snap gerekirse | Orta | snapd maskeli; tarayıcı epiphany |
| Kendi çekirdeğimiz secure-boot imzası olmadan çalışmaz | Yüksek | MOK ile imzalama veya secure-boot kapalı talimatı |
| ISO boyu 2.3 GB hedefini aşmak | Orta | `--no-install-recommends`, xz, `linux-firmware` seçilmiş alt paketler (~630 MB yerine ~220 MB) |
| Türkçe çeviri eksikleri | Düşük | `language-pack-tr` + `language-pack-gnome-tr` |
| Canlı oturumda `live` şifresiz sudo | Orta | Sadece canlı ISO için; kalıcı kurulumda `live` kullanıcısı oluşturulmaz |
| **`vga=791` unutulursa ekran siyah** | Yüksek | `GRUB_CMDLINE_LINUX_DEFAULT` + `build-iso.sh` ikisinde de sabit; menüde 5 girdi |

## Gerçek donanım kanıtı: siyah ekran (B560, 2026-11-16)

Bu bölüm ileride aynı hataya düşmemek için tutuluyor.

**Belirti:** Kurulu sistemde X (1366x768) ve `gnome-shell` çalışıyor, `gdm`/`accounts-daemon` aktif,
backlight %100 (`bl_power=0`), `LVDS-1` `connected`+`enabled`, DPMS `On` — ama ekran tamamen siyah.

**Kanıt zinciri:**

| Ölçüm | Sonuç | Anlamı |
|---|---|---|
| `dd if=/dev/fb0` örnek pikseller | `RGB(46,52,54)` | GNOME koyu arka planı **gerçekten çiziliyor** |
| `glxinfo -B` | `Mesa Intel(R) HD Graphics (ILK)` | Sürücü çalışıyor |
| `eglinfo` | `OpenGL core profile renderer: NVA8` | EGL aktif |
| `/sys/kernel/debug/dri/0/i915_display_info` | `pipe A: enable=yes, active=yes` | Pipe açık |
| Ekran | Siyah | Kalan tek katman: panel/modez |

**Kök neden:** kernel komut satırında `vga=791` (1024x768x16 VESA framebuffer) yok.
Bu parametre olmadan kernel paneli i915'e devrederken LVDS başlatma sırası bozuluyor.

**Çözüm:** `vga=791 console=tty0` → aynı donanımda masaüstü anında geldi.
`GRUB_GFXPAYLOAD_LINUX=keep` de eklendi (menü grafik modu çekirdeğe devredilsin).

**Referans:** Pardus 25.0 bu makinede `vga=791 noswap splash quiet` ile sorunsuz çalışıyor.

**Elenen yanlış teşhisler** (hepsi denendi, hiçbiri çözmedi):
`nomodeset` (KMS'i kapatıp kötüleştirdi) · `i915.modeset=0` · hayalet `VGA-1-2` (Optimus;
`vga=791` sonrası hâlâ 2 monitör görünüyor ama ekran ÇALIŞIYOR) · backlight/inverter ·
fbcon `dummy device` · VESA X sürücüsü zorlaması · `accounts-daemon` (`vga=791` sonrası da gerekli değil).

## Kayıt tutma kuralı

Yeni bir karar alındığında bu dosyaya satır eklenir (tarih + gerekçe).
Elenen seçenekler "neden elendi" tablosuyla birlikte kaydedilir ki ileride aynı tartışma tekrarlanmasın.
