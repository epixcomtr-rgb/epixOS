# epixOS — Kendi Linux Sürümümüzü Nasıl Yaparız? (Özet)

## 1. "Kendi işletim sistemimizi yapmak" ne demek?

Linux'ta 3 ayrı iş var ve karıştırılmaması gerekiyor:

| İş | Ne yapılır | Zorluk | Süre |
|---|---|---|---|
| **A. Çekirdek (kernel)** | Linux kaynak kodunu kendi `.config` dosyamızla derlemek, sürücü/yama eklemek | Orta | Saatler |
| **B. Dağıtım (distro)** | Çekirdek + kullanıcı alanı (glibc, systemd, GNOME, paket yöneticisi) + marka + kurulum aracı | Zor | Haftalar–aylar |
| **C. Sıfırdan (LFS)** | Her şeyi kaynaktan elle derlemek | Çok zor | Aylar |

**Önerimiz:** B yolunu seçiyoruz ve Ubuntu LTS tabanını kullanıyoruz.
Gerekçe: GNOME, PipeWire, Wayland, güvenlik yamaları ve sürücü desteği hazır gelir;
biz enerjimizi **marka, hafiflik, varsayılan ayarlar, geliştirici deneyimi ve kendi çekirdeğimiz** üzerine harcarız.
Bu, Ubuntu/Mint/Zorin/Pop!_OS gibi gerçek dağıtımların da izlediği yoldur.

"A"'yı B'den sonra yaparız (Aşama 3): kendi `.config`'imizle derlenmiş `epixOS-kernel` paketi.
C yoluna (LFS) girmek GNOME ile birlikte pratikte aylar sürer; istenirse ayrı bir "eğitim hattı" olarak sonra açılır.

## 2. Bir ISO'nun katmanları

```
┌──────────────────────────────────────────────────────────┐
│ Önyükleme: GRUB / systemd-boot → vmlinuz + initrd.img     │
├──────────────────────────────────────────────────────────┤
│ initramfs: kök dosya sistemini bulur, squashfs'i bağlar   │
├──────────────────────────────────────────────────────────┤
│  filesystem.squashfs: SALT-OKUNUR kök dosya sistemi            │
│   ├── /usr  GNOME, uygulamalar        (salt-okunur)       │
│   ├── /etc  varsayılan ayarlarımız    (kopyalanır)        │
│   └── /var  çalışma anında yazılır    (tmpfs / overlay)   │
├──────────────────────────────────────────────────────────┤
│ Üst katman: ISO kalıbı (xorriso/GRUB) + marka + canlı oturum│
└──────────────────────────────────────────────────────────┘
```

Yani bir ISO = **önyükleme yükleyicisi + çekirdek + initramfs + sıkıştırılmış kök dosya sistemi + canlı oturum betikleri**.

## 3. Üretim araçları — hangisi?

| Araç | Ne yapar | Bizim için |
|---|---|---|
| **live-build** | Debian/Ubuntu tabanlı canlı ISO üretir, paket listesi + hook mantığı | ✅ **Seçilen** |
| debootstrap / mmdebstrap | Boş bir kök dosya sistemi kurar (live-build bunu kullanır) | ✅ dolaylı |
| archiso | Arch için aynı iş | ❌ (taban Ubuntu) |
| Calamares | Grafik kurulum sihirbazı (ISO → disk) | ✅ Aşama 5 |
| xorriso / squashfs-tools | ISO kalıbı ve sıkıştırılmış fs | ✅ dolaylı |
| QEMU | ISO'yu disk yazmadan test etme | ✅ test |

## 4. Yol haritası (aşamalar)

| Aşama | Hedef | Çıktı | Durum |
|---|---|---|---|
| **0** | İskelet: klasörler, yapılandırma, doküman | bu depo | ✅ tamam |
| **1** | Sade Ubuntu tabanlı canlı ISO (terminal açılıyor) | `epixOS-0.1.iso` | yapı hazır, derleme bekliyor |
| **2** | GNOME masaüstü + hafif varsayılanlar + marka | `epixOS-0.2.iso` | |
| **3** | Kendi çekirdeğimiz: özel `.config`, `epixOS-kernel` paketi | `epixOS-kernel_*.deb` | |
| **4** | Kendi APT depomuz + imzalama, `epixOS-archive-keyring` | `repo.epixos` | |
| **5** | Disk kurulumu (Calamares) — **kalıcı kullanım buradan** | kurulabilir ISO | |
| **6** | Sürüm, imajlar, güncelleme kanalı | `epixOS 1.0` | |

## 5. Sürüm kimliği

```
epixOS 0.1 (2026.11) — kod adı: kavak
ISO:    epixOS-0.1-2026.11-amd64.iso
Volume: EPIXOS_2026_11
```

- `0.1` → ürün sürümü (0.2, 0.3 … 1.0 diye ilerler)
- `2026.11` → yayın dönemi (her ay/yıl etiketi ayrı yayın)
- Tek kaynak: `VERSION` dosyası → `build.sh` → `iso/auto/config` → hook'lar → `/etc/os-release`

## 6. "Hafif" ne demek? — 2 GB RAM hedefi

- `gnome` meta paketi değil **`gnome-core`** → gereksiz uygulamalar (oyunlar, haritalar, hava durumu) gelmez
- Snap zorunluluğu yok: tarayıcı olarak **GNOME Web (epiphany)** veya apt ile Chromium tercih edilir
  (Ubuntu'da `firefox` paketi snap'e yönlendirir — canlı ISO'da snap kurmak kırılgandır)
- Animasyonlar ve arama sağlayıcıları kısılır, `dconf` ile sistem geneli varsayılan yazılır
- systemd servislerinden gereksizler kapatılır, `gnome-software` yerine `apt`/`flatpak` isteğe bağlı
- **2 GB RAM'de akıcı**: zram (ram/2, zstd), swappiness=100, purge katmanı, journal volatile
- **Dil**: TR birincil + EN ikincil, klavye `tr,us` (Alt+Shift)
- Hedef: boşta **≤ 850 MB RAM** (2 GB makinede), ISO **≤ 2.3 GB**

## 6.5 Kurulum anı katmanları

| Katman | Ne | Komut |
|---|---|---|
| **SSH** | sshd enable, ilk andan erişim, anahtar/şifre | `epix-ssh status` |
| **Ağ** | WiFi+Ethernet firmware gömülü, NM hazır | `epix-hw net`, `nmcli` |
| **Donanım** | sürücüsüz aygıt atlanır, açılış DURMAZ | `epix-hw report/block` |
| **AI ajan** | DeepSeek Harness, API anahtarı, prompt ile yönetim | `epix-ai key/start` |

Detay: `docs/06-SSH-AG-DONANIM-AI.md`

## 7. Gerçekçi beklenti ve riskler

- İlk ISO 1–2 saatte çıkar; **çalışan, markalı, kurulabilir bir dağıtım** ise haftalar sürer.
- Ubuntu tabanı demek: paket uyumluluğu hazır, ama bizim depolarımız Ubuntu'nun üstüne biner → sürüm çakışmalarını biz yönetiriz.
- Çekirdek derlemek kolay, **çekirdeği güncel tutmak** zahmetlidir (Aşama 3'te otomasyon yazacağız).
- Tüm derleme işlemleri `sudo` gerektirir; her adımda geri alınabilir olması için `chroot` içinde çalışırız, ana sisteme dokunmayız.

## 8. Bu makinede mevcut durum

| Gereksinim | Durum |
|---|---|
| Ana sistem | Ubuntu 24.04.5 LTS, çekirdek 7.0.0-42-generic ✅ |
| Disk boş alanı | ~152 GB (kök bölümde) ✅ |
| RAM / CPU | 33 GB / 16 çekirdek ✅ |
| `live-build`, `debootstrap` | ❌ kurulu değil → `./build.sh setup` |
| `xorriso`, `squashfs-tools` | kısmen (`mksquashfs` var) → `setup` tamamlar |
| `qemu-system-x86_64` | ✅ var |
| `docker`, `systemd-nspawn` | ✅ var (izole deneme için alternatif) |

Sonraki adım: `docs/02-ISO-URETIMI.md` → `./build.sh setup && ./build.sh all`.
