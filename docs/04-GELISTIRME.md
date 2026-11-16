# Geliştirme Katmanı (Aşama 2–3)

epixOS'un ayırt edici tarafı "hafif GNOME" olacak; amaç kullanıcıyı **yazılım geliştirmeye hazır** teslim etmek.
Bu yüzden geliştirici araçları **varsayılan ISO'ya değil, ayrı paket listesine** yazılır:

```
iso/config/package-lists/epixos-dev.list.chroot   → ISO'da hazır gelir (hafif seçim)
scripts/install-devtools.sh                        → kullanıcı isterse kurar (ağır seçim)
```

## 1. ISO'ya gömülen hafif set (~600 MB)

| Araç | Neden |
|---|---|
| `git`, `curl`, `wget`, `ca-certificates` | temel |
| `build-essential`, `pkg-config`, `cmake`, `meson`, `ninja-build` | C/C++ derleme |
| `python3`, `python3-pip`, `python3-venv` | Python |
| `gdb`, `strace`, `ltrace`, `valgrind` | hata ayıklama |
| `vim`, `nano`, `tmux` | terminal |
| `ripgrep`, `fd-find`, `jq`, `tree`, `htop`, `git-lfs` | günlük iş |
| `shellcheck`, `clang-format` | kalite |

## 2. İsteğe bağlı ağır set (`scripts/install-devtools.sh`)

Docker/Podman, Node.js (nvm), Rust (rustup), Go, Java (OpenJDK), Android SDK, VS Code (deb), Flatpak.
Bunlar ISO'yu şişirir; kullanıcı isterse tek komutla kurar.

```bash
sudo ./scripts/install-devtools.sh --all
sudo ./scripts/install-devtools.sh --rust --node --docker
```

## 3. epixOS'a özgü olması gerekenler

| Fikir | Açıklama | Aşama |
|---|---|---|
| `epix` CLI | `epix update`, `epix install`, `epix info` — apt sarmalayıcı, Türkçe çıktı | 2 |
| `epixos-welcome` | İlk açılışta hoş geldin ekranı: dil, tarayıcı, geliştirici seti seçimi | 2 |
| Hazır dotfiles | `~/.config` şablonları (bash/zsh, git, tmux) | 3 |
| `epixos-kernel` | Kendi `.config`'imizle derlenmiş çekirdek | 3 |
| `epixos-repo` | Kendi APT depomuz | 4 |

## 4. Kendi çekirdeğimizi derlemek (Aşama 3 — planlanan)

```bash
# 1. Kaynak
apt source linux-image-$(uname -r)      # veya kernel.org tarball
# 2. Kullanıcının çalışan ayarını temel al
cp /boot/config-$(uname -r) kernel/config-amd64
# 3. Değiştir
make olddefconfig
#    -> epixOS farkları: BBR tcp, zstd, fq_codel, ntfs3, sched_ext (opsiyonel),
#       -O2 + ThinLTO, debug sembolleri kapalı, gereksiz sürücüler modül olarak
# 4. Derle (16 çekirdek -> ~10-20 dk)
make -j16 deb-pkg LOCALVERSION=-epix
# 5. Çıktı: ../linux-image-*_amd64.deb  -> epixos-kernel olarak yeniden adlandır
```

Neden Ubuntu çekirdeği ile başlıyoruz: sürücü kapsamı geniş, DKMS/secure-boot akışı çalışıyor.
İlk kendi derlememizde **sadece birkaç ayar** değiştirilir (hız/güvenlik/sürücü), sonra kademeli olarak küçültülür.

## 5. Test altyapısı

| Araç | Kullanım |
|---|---|
| `qemu-system-x86_64` | ISO smoke test |
| `systemd-nspawn -D iso/chroot` | chroot içinde hata ayıklama |
| `docker` | paket derleme izolasyonu |
| GitHub Actions (ileride) | her push'ta ISO üretimi + sha256 |

## 6. Kod kalitesi

- `shellcheck scripts/*.sh build.sh` → her commit öncesi
- ISO üretimi tekrarlanabilir olmalı: `apt` snapshot tarihi `auto/config` içinde sabitlenir
- Sürüm numarası tek kaynaktan: `VERSION` dosyası → `os-release` + ISO adı + `epixos-release` paketi
