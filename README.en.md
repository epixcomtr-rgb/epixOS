# epixOS

[![Version](https://img.shields.io/badge/version-0.1%20(2026.11)-16404b)](https://os.epix.tr/indir/)
[![License](https://img.shields.io/badge/license-GPL--3.0-16404b)](LICENSE)
[![Arch](https://img.shields.io/badge/arch-amd64-16404b)](https://os.epix.tr/indir/)
[![Download](https://img.shields.io/badge/ISO-download-c8e83f)](https://os.epix.tr/indir/)

[Türkçe](README.md) · **English**

A lightweight, fast Linux distribution managed by AI. GNOME desktop, smooth on
**2 GB of RAM**, **SSH open from first boot**, and a **DeepSeek Harness** based AI agent.

> **Download:** [os.epix.tr/indir](https://os.epix.tr/indir/) — 1.8 GB, amd64, live session + installer

---

## Features

| | |
|---|---|
| **Light** | Built on `gnome-core`, ~651 MB idle RAM. Not `ubuntu-desktop`. |
| **Fast** | Target ≤ 15 s boot. No snap, minimal background services. |
| **AI agent** | DeepSeek Harness on `127.0.0.1:3080`. Everything managed by prompt. |
| **SSH open** | Port 22 from first boot. Works headless, no screen needed. |
| **Wi-Fi ready** | Broadcom, Intel, Realtek firmware baked in. |
| **Turkish** | `tr_TR.UTF-8` default, `en_US.UTF-8` secondary. Keyboard `tr,us`. |
| **Compatible** | Won't hang on old hardware; `vga=791` fixes Ironlake panels. |

## Release

| | |
|---|---|
| Version | `0.1` |
| Release | `2026.11` |
| Codename | `kavak` |
| Base | Ubuntu 24.04 LTS (noble) |
| Kernel | Linux `6.8.0-149-generic` |
| Desktop | GNOME (`gnome-core`) |
| Browser | GNOME Web (epiphany) — no snap |
| Boot | Legacy BIOS (MBR) + UEFI |
| ISO | 1.8 GB · sha256 `c35f0a50fa101bee1682cc2eaaecf7c259ca50c8240b650ec97a98bd3efa26be` |

## Install

Three steps. Full guide: **[os.epix.tr/indir](https://os.epix.tr/indir/)**

### 1. Download and verify

```bash
curl -LO https://os.epix.tr/indir/epixOS-0.1-2026.11-amd64.iso
sha256sum epixOS-0.1-2026.11-amd64.iso
# c35f0a50fa101bee1682cc2eaaecf7c259ca50c8240b650ec97a98bd3efa26be
```

Also available from GitHub Releases:
[github.com/epixcomtr-rgb/epixOS/releases](https://github.com/epixcomtr-rgb/epixOS/releases)

### 2. Write to USB

```bash
# Linux / macOS — replace /dev/sdX with your USB device (no trailing digit)
sudo dd if=epixOS-0.1-2026.11-amd64.iso of=/dev/sdX bs=4M status=progress oflag=sync
sync
```

On Windows use [Rufus](https://rufus.ie/): partition scheme **MBR**, target
system **BIOS**, "ISO Image mode".

### 3. Boot and install

Boot from the USB (`F12`), pick **epixOS — Live Session** in the GRUB menu.
The live session writes nothing to disk. If you like it, run the
**Install epixOS** icon on the desktop.

## Build from source

```bash
git clone https://github.com/epixcomtr-rgb/epixOS.git
cd epixOS

./build.sh setup      # install required tools (sudo)
./build.sh config     # package lists + branding
./build.sh build      # ISO -> dist/epixOS-0.1-2026.11-amd64.iso
./build.sh run        # boot in QEMU (2 GB RAM)
./scripts/verify-iso.sh   # post-build verification
```

Building requires `sudo`, ~12 GB of scratch space, and 30–60 minutes.
Once `build/chroot/.bootstrap-done` exists, `debootstrap` is skipped on rebuilds.

## Repository layout

```
epixOS/
├── build.sh                 # setup / config / build / run / validate / clean
├── VERSION                  # 0.1, 2026.11, kavak
├── scripts/
│   ├── build-iso.sh         # debootstrap + casper + mksquashfs + grub-mkrescue
│   ├── verify-iso.sh        # post-build verification (incl. vga=791)
│   └── deploy-site.sh       # publish os.epix.tr
├── iso/config/
│   ├── hooks/live/          # 6 chroot hooks (hardware, SSH, branding, light, AI, diagnose)
│   ├── package-lists/       # 180 packages across 6 lists
│   └── includes.chroot/     # dconf, wallpaper, .desktop
├── branding/                # logo + wallpaper (SVG)
├── site/                    # os.epix.tr (static)
└── docs/                    # 7 docs (Turkish): overview, architecture, ISO, GNOME, dev, decisions, SSH/AI
```

## Documentation

The in-depth documentation is currently in Turkish.

| File | Contents |
|---|---|
| [docs/00-OZET.md](docs/00-OZET.md) | Building your own OS: layers, roadmap |
| [docs/01-MIMARI.md](docs/01-MIMARI.md) | What each folder does |
| [docs/02-ISO-URETIMI.md](docs/02-ISO-URETIMI.md) | ISO production + common failures |
| [docs/03-GNOME-HAFIF.md](docs/03-GNOME-HAFIF.md) | Lightweight GNOME tuning |
| [docs/04-GELISTIRME.md](docs/04-GELISTIRME.md) | Developer tooling layer |
| [docs/05-KARARLAR.md](docs/05-KARARLAR.md) | Decisions, rejected options, hardware evidence |
| [docs/06-SSH-AG-DONANIM-AI.md](docs/06-SSH-AG-DONANIM-AI.md) | SSH, networking/drivers, hardware skipping, AI agent |

## Hardware note: old Intel panels

On some older Intel GPUs (Ironlake and earlier, e.g. Lenovo B560) the kernel
never produces a signal when taking over the panel: X sets 1366x768, GNOME
renders, backlight is at 100% — **but the screen stays black**.

Fix: `vga=791` (1024x768x16 VESA framebuffer) on the kernel command line.
epixOS passes it from GRUB and `/etc/default/grub.d/99-epixos.cfg`.
`scripts/verify-iso.sh` asserts the parameter is present in the ISO.
Full evidence chain: [docs/05-KARARLAR.md](docs/05-KARARLAR.md).

## Updating an existing installation

To receive fixes without reinstalling from the ISO, use the `epixos-base` package:

```bash
# after rebuilding the ISO, produce the package
sudo ./scripts/make-deb.sh
# -> dist/epixos-base_<version>_all.deb

# on the target machine
sudo dpkg -i epixos-base_*.deb
sudo apt -f install     # only if dependencies are missing
```

The package ships the helper commands (`epix`, `epix-ssh`, `epix-hw`,
`epix-doctor`, `epix-ai`, …), the `vga=791` GRUB setting, the `nouveau`
blacklist and `epix-backlight.service`. `postinst` refreshes GRUB and initramfs.

> **Caution:** the `update-initramfs` call in `postinst` names the kernel
> version explicitly. Without `-k`, it mistakes `/boot/vmlinuz-epixos` for a real
> kernel, writes a broken initramfs and leaves the system unbootable.

## Contributing

```bash
git checkout -b feature/your-thing
# change, build, verify
./scripts/verify-iso.sh
git commit -m "feat: ..."
```

Any commit that changes the ISO should include `verify-iso.sh` output in the PR.

## License

GPL-3.0. Ubuntu/Debian packages keep their own licenses.

---

**Epix Software House** · [epix.tr](https://epix.tr/) · [os.epix.tr](https://os.epix.tr/)
