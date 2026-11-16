# epixOS — Mimari ve Depo Yapısı

```
epixOS/
├── build.sh                 # tek giriş noktası: setup / config / build / run / clean
├── README.md
├── docs/                    # plan ve kararlar
├── iso/
│   ├── auto/
│   │   └── config           # live-build yapılandırması (lb config'in okuduğu dosya)
│   └── config/
│       ├── package-lists/   # ISO'ya girecek paketler (katman katman)
│       │   ├── epixos-base.list.chroot
│       │   ├── epixos-gnome.list.chroot
│       │   └── epixos-dev.list.chroot
│       ├── hooks/live/      # chroot içinde çalışan betikler (marka, servis, dconf)
│       └── includes.chroot/ # ISO kök dosya sistemine aynen kopyalanan dosyalar
├── branding/pixmaps/        # logo, duvar kağıdı, plymouth teması
├── site/                    # os.epix.tr tanıtım sayfası
├── scripts/                 # yardımcı betikler (çekirdek derleme, depo imzalama, site yayını)
└── dist/                    # üretilen ISO'lar (git'e girmez)
```

## Katman mantığı

| Katman | Dosya | Ne zaman devreye girer |
|---|---|---|
| Paket seçimi | `config/package-lists/*.list.chroot` | derleme sırasında (debootstrap + apt) |
| Sistem ayarları | `config/hooks/live/*.hook.chroot` | paketler kurulduktan sonra, chroot içinde |
| Hazır dosyalar | `config/includes.chroot/**` | en sonda kök fs'e kopyalanır |
| Önyükleme metni | `auto/config` (`--bootappend-live`) | ISO üretilirken |
| Marka | `includes.chroot/usr/share/epixos/` + hook | canlı oturumda görünür |

## Neden `includes.chroot` + hook birlikte?

- `includes.chroot` **hazır dosya** içindir (duvar kağıdı, dconf anahtarları, .desktop).
- `hook` **çalıştırılabilir mantık** içindir (`dconf update`, `os-release` düzenleme, kullanıcı/grup ayarı).
- Aynı dosyayı ikisine birden koymak sıralama hatasına yol açar; kural: *statik dosya → includes, işlem → hook*.

## Aşama 3'te eklenecekler

```
kernel/
├── config-amd64             # kendi .config dosyamız
├── patches/                 # epixOS yamaları
└── build-kernel.sh          # deb üretir: epixos-kernel_<ver>_amd64.deb
scripts/
├── make-repo.sh             # reprepro/aptly ile kendi APT depomuz
└── sign-release.sh          # Release/InRelease imzalama
```
