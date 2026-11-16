# epixOS Imager

epixOS ISO'sunu USB'ye yazan ve **ilk açılışta hazır gelecek ayarları** gömen
masaüstü aracı. Raspberry Pi Imager'ın epixOS karşılığı.

Ubuntu / Debian üzerinde çalışır (GTK4 + PyGObject, Python 3).

## Neden var

Klasik `dd` ile USB yazdıktan sonra canlı oturumda her seferinde elle
kullanıcı açmak, Wi-Fi şifresi girmek, SSH açmak gerekiyordu. Bu araç
bunları yazma anında ayarlıyor:

| Ayar | Sonuç |
|---|---|
| Kullanıcı adı + şifre | Açılışta hesap hazır, sudo çalışır |
| Wi-Fi (SSID + şifre) | Açılışta otomatik bağlanır — **ekran gerekmez** |
| SSH açık | `sshd` açılışta başlar, port 22 |
| SSH açık anahtarı | Parolasız giriş (isteğe bağlı) |
| Hostname | Ağda `epixos-b560.local` gibi görünür |

Bu, Pi gibi **ekransız (headless)** kullanımı mümkün kılar: USB'yi yaz,
karta tak, aç, `ssh epix@<ip>` ile bağlan.

## Kurulum

```bash
# bağımlılıklar (Ubuntu'da genelde kurulu)
sudo apt install python3-gi gir1.2-gtk-4.0 gir1.2-adw-1 \
                 openssl dosfstools util-linux

# çalıştır
chmod +x epix-imager
./epix-imager
```

Kurulu sistemde `/usr/local/bin/epix-imager` olarak da bulunabilir.

## Kullanım (GUI)

1. **Kalıp** → `epixOS-0.1-2026.11-amd64.iso` seç
2. **Hedef USB** → *Yenile*'ye bas, listeden USB'yi seç
3. **Özelleştirme**
   - Kullanıcı adı (varsayılan `epix`)
   - Şifre
   - Hostname
   - SSH açık (varsayılan açık)
   - SSH açık anahtarı (isteğe bağlı)
   - Wi-Fi ağ adı + şifresi
4. **USB'ye yaz** → onay → bekle

## Kullanım (CLI)

```bash
# aygıtları listele
./epix-imager --list

# yaz
sudo ./epix-imager \
  --iso epixOS-0.1-2026.11-amd64.iso \
  --dev /dev/sdb \
  --user epix \
  --password 'guclu-sifre' \
  --hostname epixos-b560 \
  --ssh \
  --wifi-ssid 'VODAFONE_UK3647' \
  --wifi-password 'wifi-sifresi'
```

`--yes` ile onay sormaz (otomasyon için).

## Nasıl çalışıyor

### 1. ISO yazma
`dd if=<iso> of=<dev> bs=4M conv=fsync` — Raspberry Pi Imager'ın yaptığı gibi
ham yazma. İlerleme `/proc/<pid>/io` üzerinden okunur.

### 2. Yapılandırmayı nereye koyuyor

epixOS ISO'su `grub-mkrescue` ile üretiliyor ve **GPT** taşıyor:

```
p1  112 KB   Gap0
p2  2.8 MB   EFI boot partition (vfat)
p3  1.7 GB   HFSPLUS  ← ISO içeriği (EPIXOS_2026_11)
p4  300 KB   Gap1
```

GPT'ye yeni bölüm eklemek **denendi ve vazgeçildi**: primary header,
partition entry array ve backup tablosunun birlikte taşınması gerekiyor;
`sgdisk` bu düzende bölümleri kaybetti ve GPT bozuldu.

**Seçilen çözüm:** ISO'nun bittiği sektörden sonra, diskin kalan boşluğuna
kendi başlıklı bir blob yazmak. Bölüm tablosuna **hiç dokunulmaz**, dolayısıyla
önyükleme garanti korunur.

```
Blob biçimi (sektör hizalı):
   0   8B   "EPIXCFG1"        sihir
   8   4B   sürüm             uint32
  12   4B   yük boyutu        uint32
  16   4B   crc32             uint32
  20  12B   ayır
  32   N    tar arşivi        epix-setup.conf, user-password.crypt,
                              wifi.nmconnection, authorized_keys, OKUBENI.txt
```

Konum: ISO'nun bittiği sektörden sonraki ilk 2048-hizalı sektör.
Yazma sonrası **geri okuma ile doğrulanır**.

### 3. İlk açılışta uygulama

`epix-setup` (ISO içinde `/usr/local/bin/`) `epix-setup.service` ile
`sysinit.target` aşamasında çalışır — yani **masaüstünden, SSH'tan ve
NetworkManager'dan önce**:

1. Canlı ortam diski bulunur (`/cdrom`, `/run/casper/cdrom`, …)
2. Diskin sonundan geriye 1 MiB adımlarla `EPIXCFG1` imzası aranır
3. Bulunursa tar açılır, ayarlar okunur
4. Uygulanır: kullanıcı, parola, sudo, hostname, SSH anahtarı,
   Wi-Fi profili (`autoconnect=true`), `sshd` etkin
5. `/var/lib/epix-setup/applied` işareti konur — oturum içinde tekrar çalışmaz

USB yoksa veya blob bozuksa **açılış engellenmez** (`ExecStart=-…`),
normal canlı oturum devam eder.

## Güvenlik notları

- Parola USB'de **crypt özeti** (`$6$…`, SHA-512) olarak durur, düz metin değil.
- Wi-Fi şifresi `nmconnection` içinde düz metindir (NetworkManager böyle saklar).
  USB'yi kaybederseniz Wi-Fi şifrenizi değiştirin.
- SSH parola girişi varsayılan **açık** (kullanıcı şifresiyle). Yalnızca anahtar
  kullanmak için `--no-ssh` veya parolasız bırakın.
- `epix-setup-applied` işareti **USB'de değil, canlı sistemde** tutulur —
  çünkü canlı ISO her açılışta sıfırlanır.

## Sorun giderme

**"EPIXCFG1 bloğu yok"**
Yapılandırma yazılmamış. `--wifi-ssid` gibi en az bir ayar vererek yeniden yaz.

**Wi-Fi bağlanmadı**
Canlı oturumda `nmcli device status` ve `journalctl -u epix-setup` bak.
Bazı Broadcom kartları (B560'taki BCM4313 gibi) için `brcmsmac` firmware
gerekir — epixOS'ta gömülü.

**Blob'u sonradan değiştirmek**
USB'yi tekrar yazmak gerekmez; ama blob ikili formatta. En kolayı
`epix-imager` ile yeniden yazmak (1.8 GB, ~2 dk).

**SSH bağlanamıyorum**
`epix-update check` yerine canlı oturumda `systemctl status ssh` ve
`ss -tlnp | grep :22`. `epix-setup` SSH'ı `sysinit.target`'te başlatır.

## Test

```bash
# loop cihazında sahte USB ile uçtan uca test
sudo ./test-imager.sh
```

Bu, gerçek USB'ye dokunmadan: ISO yazımı, blob yerleşimi, geri okuma,
tar içeriği ve önyükleme bütünlüğünü (MBR imzası, GPT header'ları, bölüm
tablosunun değişmediği) doğrular.

## Lisans

GPL-3.0 — epixOS ile aynı.
