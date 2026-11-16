# epixOS — SSH, Ağ, Donanım ve AI Ajan Katmanı

Bu belge, kurulum anından itibaren geçerli olan 4 katmanı anlatır:

1. **SSH ilk andan açık** — canlı oturum ve kurulum boyunca erişim
2. **WiFi/Ethernet sürücüleri hazır** — internet erişimi ilk açılışta garanti
3. **Uyumsuz donanımda duraksamama** — sürücüsü olmayan aygıt atlanır, açılış devam eder
4. **AI ajan (DeepSeek Harness)** — internet gelince API anahtarı girilir, tüm yönetim prompt ile

---

## 1. SSH ilk andan açık

**Dosya:** `iso/config/hooks/live/0060-epixos-ssh.hook.chroot`
**Paketler:** `iso/config/package-lists/epixos-remote.list.chroot`

| Öğe | Değer |
|---|---|
| Servis | `ssh.service` — **enable** edilmiş, açılışta başlar |
| Port | 22 |
| Kullanıcı | `live` (canlı oturumda şifre boş) |
| root girişi | kapalı (`PermitRootLogin no`) |
| Anahtar girişi | açık (`~live/.ssh/authorized_keys`) |
| DNS ters çözümleme | kapalı (hızlı bağlantı) |
| Host anahtarları | ilk açılışta üretilir, ISO'ya gömülmez |

```bash
# başka makineden
ssh live@<epixos-ip>            # canlı oturumda şifre boş
ssh-copy-id live@<epixos-ip>    # kendi anahtarını ekle
epix-ssh key 'ssh-ed25519 AAAA...'   # veya tek satırda
```

`epix-ssh status` → servis durumu, port, IP'ler, host anahtarı parmak izleri.

> Güvenlik notu: canlı ISO'da `live` şifresiz sudo sahibidir. Bu **canlı oturum** için tasarlandı.
> Kalıcı kurulumda (Aşama 5) `live` kullanıcısı oluşturulmaz; kurulum sihirbazı gerçek kullanıcı ister.

---

## 2. WiFi / Ethernet sürücüleri

**Paket listesi:** `epixos-network.list.chroot`

| Katman | Paketler | Neden |
|---|---|---|
| Ağ yönetimi | `network-manager`, `network-manager-gnome`, `wpasupplicant` | GNOME ağ menüsü |
| Kablosuz | `linux-firmware-intel-wireless`, `-realtek`, `-broadcom-wireless`, `-mediatek` | en yaygın WiFi çipleri |
| Kablolu | çekirdek içi `e1000e`, `r8169`, `igc`, `atlantic` + `linux-firmware-misc` | Intel/Realtek/Aquantia |
| Grafik | `linux-firmware-intel-graphics`, `-amd-graphics`, `-nvidia-graphics` | kurulum ekranı için |
| Mobil | `modemmanager` | USB modem/tethering |
| Teşhis | `iw`, `rfkill`, `ethtool`, `dnsutils`, `pciutils`, `usbutils` | sorun bulma |

**Boyut dengesi:** tüm `linux-firmware` ~630 MB. Seçilmiş alt paketler ~220 MB.
Hepsi gömülü çünkü **internet olmadan AI anahtarı girilemez** — bu yüzden ağ ilk öncelik.

```bash
nmcli device wifi list
nmcli device wifi connect "SSID" password "..."
epix-hw net          # arayüz + sürücü + rfkill özeti
```

---

## 3. Uyumsuz donanımda duraksamama

**Dosya:** `iso/config/hooks/live/0050-epixos-hardware.hook.chroot`

### Sorun
Linux açılışta sürücüsü olmayan bir aygıt için 90 saniyeye kadar bekleyebilir
(`NetworkManager-wait-online`, `systemd-udev-settle`, bozuk udev olayları).
Kurulum/canlı oturum bunun yüzünden "donar" gibi görünür.

### Çözüm — 3 katman

| Katman | Ne yapılır | Dosya |
|---|---|---|
| Bekleyicileri kapat | `NetworkManager-wait-online`, `systemd-udev-settle`, `cloud-init*` maskelenir | hook |
| Zaman aşımlarını kıs | udev `event_timeout=10`, systemd `DefaultDeviceTimeoutSec=10s` | `/etc/udev/udev.conf.d/`, `/etc/systemd/system.conf.d/` |
| Kara liste | sorunlu modül `/etc/epixos/hw-blocklist.conf`'a yazılır, boot'ta uygulanır | `epix-hw-block.service` |

Ayrıca `ModemManager`, `bluetooth`, `cups`, `avahi` gibi donanım bekleyen servisler
canlı oturumda kapalı (kullanıcı isterse açar).

### Araçlar

```bash
epix-hw report            # sürücüsüz aygıtlar + eksik firmware (dmesg) + ağ/sürücü tablosu
epix-hw block r8169       # sorunlu modülü kara listeye al (sonraki açılış)
epix-hw unblock r8169     # geri al
epix-hw apply             # kara listeyi hemen uygula (modprobe -r)
epix-hw net               # ip/nmcli/rfkill özeti
```

Rapor `/var/log/epixos/hw-report.txt` dosyasına yazılır; `epix-hw-report.service`
arka planda bir kez üretir (`epix.nohwreport` çekirdek parametresiyle kapatılır).

**Hiçbir durumda açılış durmaz:** bir sürücü yüklenemezse çekirdek uyarı yazar, udev olayı
zaman aşımına düşer, sistem açılmaya devam eder.

---

## 4. AI ajan — DeepSeek Harness (`dsh`)

**Dosya:** `iso/config/hooks/live/0300-epixos-ai.hook.chroot`

### Neden DeepSeek Harness
- Açık kaynak (MIT), Cordis tabanlı "her şey eklenti" mimarisi
- Web arayüzü (`http://127.0.0.1:3080`) + CLI
- Model sağlayıcıları: DeepSeek, Anthropic, OpenAI, Moonshot/Kimi, Z.ai/GLM, **OpenAI-uyumlu özel uç noktalar**
- Ajan dosya okur/yazar, komut çalıştırır, plan tutar, iş devreder → **kurulumun kendisini de yönetebilir**

### Akış

```
açılış → internet (WiFi/Ethernet otomatik)
      → epix-ai key sk-...        (API anahtarı, 0600)
      → epix-ai test              (DeepSeek API doğrulama)
      → epix-ai start             (servis + web arayüzü)
      → http://127.0.0.1:3080     (veya ağdan http://<ip>:3080)
      → prompt: "epixOS'u güncelle, GNOME ayarlarını yap, ..."
```

### Node.js
DSH **Node ≥ 24.9** ister; Ubuntu noble'da Node 18 var.
Bu yüzden `nodejs.org` resmî tarball'ı **sha256 doğrulanarak** `/opt/node24` içine kurulur
(apt'e dokunmaz, sistem Node'u ile çakışmaz). `PATH` → `/etc/profile.d/epixos-node.sh`.

### API anahtarı nereye yazılır

DSH'nin kendi kimlik deposu, **tek doğru yer**:

```yaml
# /opt/epixos/dsh/.credentials.yaml   (0600, sadece sahibi okur)
version: 1

refs:
  DEEPSEEK_API_KEY: sk-...
```

`epix-ai key` bunu güvenli biçimde yazar (mevcut `records:` kayıtlarını bozmadan).
Ayrıca servis ve CLI için `/etc/epixos/ai.env` (0600) güncellenir.

> Önemli: anahtar **ISO'ya gömülmez**. Gömülü olsaydı ISO'yu indiren herkes anahtarı okurdu.
> Kullanıcı ilk açılışta kendisi girer — bu hem güvenli hem de çoklu kullanıcı için doğru.

### Sağlayıcılar

```bash
epix-ai provider     # desteklenen ortam değişkenlerini listeler
sudo nano /etc/epixos/ai.env
epix-ai restart
```

Örnek — yerel Ollama (OpenAI-uyumlu):
```yaml
# $DSH_HOME/profiles/web/cordis.patch.yml
- id: llm-pi-ai
  config:
    providers:
      local-ollama:
        apiKeyEnv: OLLAMA_KEY
        api: openai-completions
        baseURL: http://127.0.0.1:11434/v1
        models:
          - id: qwen2.5-coder:14b
```

### Komutlar

| Komut | İş |
|---|---|
| `epix-ai status` | node / dsh / anahtar / servis / internet durumu |
| `epix-ai setup` | internet + node + dsh kontrol ve kurulum |
| `epix-ai key sk-...` | anahtarı kaydet (0600) |
| `epix-ai test` | DeepSeek API'sinde doğrula |
| `epix-ai start` / `stop` / `restart` | servis yönetimi |
| `epix-ai logs [n]` | son log satırları |
| `epix-ai web` | web arayüzü ön planda |
| `epix-ai shell` | `dsh` CLI |
| `epix-ai-gui` | masaüstünden grafik kurulum (zenity) |

### Servis
`epix-ai.service` → `dsh web --no-open --port 3080`, `live` kullanıcısı olarak,
`ConditionPathExists=/opt/node24/bin/node` (node yoksa başlamaz, sistem açılışını engellemez).
`epix-ai-autostart.service` → internet gelince ve anahtar varsa ajanı otomatik başlatır.

### Güvenlik
- Kimlik dosyası `0600`; DSH başka kullanıcının okuyabildiği dosyayı **reddeder**
- Web arayüzü varsayılan `127.0.0.1` — ağdan erişim için `DSH_WEB_HOST`/`--host` bilinçli açılır
- `epix-ai status` anahtarın kendisini asla göstermez (yalnızca "kayıtlı [DEEPSEEK_API_KEY]")

---

## Önyükleme sırası (hook'lar)

| Sıra | Hook | İş |
|---|---|---|
| 0050 | `epixos-hardware` | donanım atlama, `epix-hw`, udev/systemd zaman aşımları |
| 0060 | `epixos-ssh` | sshd enable, `epix-ssh`, motd |
| 0100 | `epixos-branding` | os-release, live kullanıcı, GDM, `epix`, ilk açılış |
| 0200 | `epixos-light` | GNOME purge, zram, sysctl, dil/klavye |
| 0300 | `epixos-ai` | Node 24, dsh, `epix-ai`, servisler, GUI |

## Kurulum sonrası ilk 3 dakika

```bash
epix-ssh status            # IP'yi öğren
epix-hw report             # donanım sorunu var mı
nmcli device wifi list     # ağ
epix-ai setup              # internet + node + dsh
epix-ai key sk-...         # anahtar
epix-ai start              # ajan
# tarayıcı: http://127.0.0.1:3080
```
