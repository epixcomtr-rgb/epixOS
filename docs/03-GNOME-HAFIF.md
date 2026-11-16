# GNOME'u Hafif Tutmak

## 1. Paket seçimi: `gnome` değil `gnome-core`

| Paket | İçerik | RAM/disk etkisi |
|---|---|---|
| `ubuntu-desktop` | Tam Ubuntu masaüstü + snap + gereksiz her şey | ~1.4 GB RAM, 6+ GB disk |
| `gnome` | GNOME'un tamamı (oyunlar, haritalar, hava durumu, takvim...) | ~1.1 GB RAM |
| **`gnome-core`** | Kabuk, GDM, dosya yöneticisi, terminal, ayarlar | **~700–850 MB RAM** ✅ |
| `gnome-session` + elle seçim | En yalın | Daha az ama bakımı zor |

**Karar: `gnome-core` + seçilmiş ekler** (`gnome-tweaks`, `nautilus`, `gnome-terminal`, `gnome-text-editor`).
`gnome-software` (yazılım merkezi) başlangıçta **yok**; paketler `apt` ile kurulur, istenirse sonra eklenir.

## 2. `dconf` ile sistem geneli varsayılanlar

Dosya: `iso/config/includes.chroot/etc/dconf/db/local.d/00-epix-defaults`

Anahtar fikirler:

- Animasyonlar kısılır (`enable-animations=false`) → eski/zayıf GPU'larda akıcılık
- Masaüstü ikonları kapalı, çöp kutusu simgesi yok → daha az çizim
- Arama sağlayıcıları sınırlanır (dosya indeksleme varsayılan kapalı)
- Gece ışığı, dokunmatik yüzey "tap to click", Türkçe klavye varsayılan
- `favorite-apps` = Files, Terminal, Web, Metin Düzenleyici

Uygulamak için `dconf update` **hook içinde** çalışır (`includes.chroot` sadece dosyayı kopyalar):

```bash
dconf update
```

## 3. Servis ve arka plan kısıtlamaları

`hook` içinde kapatılanlar (hafiflik + canlı ISO'da gereksiz):

```bash
systemctl disable bluetooth.service     # istenirse açılır
systemctl disable ModemManager.service
systemctl disable avahi-daemon.service
systemctl mask snapd.service snapd.socket 2>/dev/null || true
apt-get purge -y gnome-software gnome-software-common 2>/dev/null || true
```

> `systemctl` chroot içinde tam çalışmaz; canlı oturumda `systemd` gerçek olduğu için
> bu komutları `disable` olarak bırakmak yeterli (enable/disable dosya sisteminde kalıcıdır).

## 4. Tarayıcı sorunu (önemli)

Ubuntu'da `firefox` paketi artık **snap'e yönlendirir**. Canlı ISO'da snap çalıştırmak kırılgandır.

| Seçenek | Artı | Eksi |
|---|---|---|
| **`epiphany-browser`** (GNOME Web) | GNOME ile tam uyumlu, hafif, apt'te gerçek paket | WebKitGTK, bazı sitelerde uyumsuz |
| `chromium-browser` | Uyumluluk yüksek | Ubuntu'da o da snap'e yönlenebilir |
| Flatpak Firefox | Güncel Firefox | ISO'ya flatpak + runtime ekler (~500 MB) |
| snapd ekle | Resmî Firefox | Canlı oturumda squashfs+squashfs loop, açılışta gecikme |

**Karar (0.2): `epiphany-browser`.** Sonra `flatpak` katmanı isteğe bağlı sunulur.

## 4.5 Dil: TR birincil, EN ikincil

| Katman | Ayar | Dosya |
|---|---|---|
| Sistem | `LANG=tr_TR.UTF-8`, `LANGUAGE=tr_TR:tr:en_US:en` | `/etc/default/locale` |
| Oturum GDM | `Language=tr_TR.UTF-8` | `/var/lib/AccountsService/users/live` |
| Klavye | `tr,us` — Alt+Shift ile geçiş | `/etc/default/keyboard` |
| GNOME girdi | `sources=[('xkb','tr'),('xkb','us')]` | dconf `input-sources` |
| Çeviri paketleri | `language-pack-tr`, `language-pack-gnome-tr`, `-en` varyantları | package-list |

İngilizce'yi tamamen kaldırmıyoruz: kullanıcı GDM'de veya Ayarlar → Bölge ve Dil'den İngilizce'ye geçebilir.
Ters yönde (EN→TR) de çalışır; `locale-gen` iki dili de üretir.

## 4.6 2 GB RAM hedefi — ne yapılıyor?

| Önlem | Kazanç |
|---|---|
| `gnome-core` (ubuntu-desktop değil) | ~500 MB RAM |
| `gnome-software`, `totem`, `baobab`, `yelp`, `tracker-miner` purge | ~250 MB RAM + disk |
| zram (`ram/2`, zstd, öncelik 100) | swap = 1 GB sıkıştırılmış bellek, disk I/O yok |
| `vm.swappiness=100`, `vfs_cache_pressure=150` | zram'ın aktif kullanımı |
| Animasyonlar kapalı, dinamik çalışma alanı kapalı | GPU/CPU tasarrufu |
| `journald` volatile, `RuntimeMaxUse=64M` | disk yazımı yok |
| CUPS, bluetooth, ModemManager, avahi, packagekit maskeli | ~60 MB + açılış süresi |
| `gnome-initial-setup` yok | ilk açılışta sihirbaz yükü yok |
| Belge/man sayfaları hariç (`dpkg path-exclude`) | ~300 MB disk |

Doğrulama: canlı oturumda `epix-memory-check`.

## 5. Ölçüm — "hafif" iddiasını kanıtlamak

ISO'yu QEMU'da açtıktan sonra:

```bash
free -h                            # boşta RAM
systemd-analyze blame | head -20   # açılış süresi
systemd-analyze critical-chain
du -sh /usr                        # disk
dpkg-query -W -f='${Installed-Size}\t${Package}\n' | sort -rn | head -20
```

Hedef değerler (0.2):

| Ölçüt | Hedef | Ubuntu 24.04 referans |
|---|---|---|
| Boşta RAM (2 GB makine) | ≤ 850 MB | ~1.5 GB |
| Boşta RAM (4 GB makine) | ≤ 1.0 GB | ~1.5 GB |
| ISO boyu | ≤ 2.3 GB | 6.0 GB |
| Kurulu disk | ≤ 4.5 GB | 12 GB |
| Açılış (QEMU) | ≤ 15 s | ~20 s |
| 2 GB'ta takılma | olmamalı (zram + purge) | — |

## 6. GNOME'u "bizim" yapan dokunuşlar

1. **Duvar kağıdı + logo**: `branding/pixmaps/` → `/usr/share/backgrounds/epixos/`
2. **GDM teması**: `/etc/gdm3/greeter.dconf-defaults` (arka plan + logo)
3. **Plymouth açılış animasyonu**: `plymouth-theme-epixos` (Aşama 2 sonu)
4. **Renk paleti**: tatlı turkuaz + koyu gri (Accessibility → kontrast uyumlu)
5. **Uzantılar**: yalnızca 1–2 tanesi gömülü (`dash-to-dock` ayarları dconf ile), gerisi kullanıcıya bırakılır
