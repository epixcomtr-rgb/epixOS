#!/bin/bash
# epixOS — tema paketi üretir: epixos-tema
#
# NEDEN AYRI PAKET:
#   ISO'yu her tema değişikliği için yeniden derlemek (~9 dk + 1.9 GB)
#   yerine paketi depoya koyuyoruz. Kullanıcı `apt upgrade` ile alır.
#
# İÇERİK:
#   - GTK teması (Yaru tabanlı, marka renkleriyle)
#   - GNOME Shell teması (top bar, panel, bildirim)
#   - duvar kağıtları (açık + koyu + sade)
#   - dconf drop-in (renkler, fontlar, davranış)
#   - ikon vurguları
#
# Renk paleti GERÇEK logodan örneklendi (PIL ile sayıldı):
#   lime  #e2ff5e   navy  #16404b   deep  #0e2a31
#   lime-dark #b8d93a  (gölge tonu)
#
# Kullanım: sudo ./scripts/make-theme-deb.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
WORK="$ROOT/build/theme-deb"

_get() { sed -n "s/^$1=//p" "$ROOT/VERSION" 2>/dev/null | head -1; }
EPIX_VERSION="$(_get EPIX_VERSION)";   EPIX_VERSION="${EPIX_VERSION:-0.1}"
EPIX_RELEASE="$(_get EPIX_RELEASE)";   EPIX_RELEASE="${EPIX_RELEASE:-2026.11}"
EPIX_CODENAME="$(_get EPIX_CODENAME)"; EPIX_CODENAME="${EPIX_CODENAME:-kavak}"

PKG="epixos-tema"
VER="${EPIX_VERSION}.${EPIX_RELEASE//./}"
ARCH="all"
OUT="$DIST/${PKG}_${VER}_${ARCH}.deb"

# marka renkleri
LIME="#e2ff5e"
LIME_DARK="#b8d93a"
NAVY="#16404b"
DEEP="#0e2a31"
NAVY_LIGHT="#1a4a56"

c_ok()   { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
c_step() { printf '\n\033[1;36m### %s\033[0m\n' "$*"; }
c_warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()    { printf '\033[1;31m[X]\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || exec sudo -E "$0" "$@"

c_step "1/5 çalışma dizini"
rm -rf "$WORK"
mkdir -p "$WORK/DEBIAN" \
         "$WORK/usr/share/themes" \
         "$WORK/usr/share/backgrounds/epixos" \
         "$WORK/usr/share/epixos/tema" \
         "$WORK/etc/dconf/db/local.d" \
         "$WORK/etc/profile.d" \
         "$WORK/usr/local/bin"
c_ok "$WORK"

# ================================================================ 2) GTK TEMASI
c_step "2/5 GTK teması (epixos-dark)"

GTKDIR="$WORK/usr/share/themes/epixOS-dark"
# Yalnız gerçekten dosya koyduğumuz dizinler açılır. Boş dizin bırakmak
# paketi şişirir ve "tema neden cinnamon içeriyor?" sorusunu doğurur.
mkdir -p "$GTKDIR/gtk-3.0" "$GTKDIR/gtk-4.0" "$GTKDIR/gnome-shell"

# Yaru'yu taban alır (varsa @import ile); yoksa kendi renklerimiz geçerli.
# Yaru'ya bağımlı OLMAMAK için renkleri doğrudan tanımlıyoruz.
cat > "$GTKDIR/gtk-3.0/gtk.css" <<GTKEOF
/* epixOS — GTK3 teması
 *
 * Palet (gerçek logodan):
 *   lime      $LIME
 *   lime-dark $LIME_DARK
 *   navy      $NAVY
 *   navy-ışık $NAVY_LIGHT
 *   deep      $DEEP
 *
 * NOT: Yaru-dark'ı @import ETMİYORUZ — o paket kurulu olmayabilir ve
 * @import başarısız olursa GTK hiç tema yüklemez (uygulamalar beyaz kalır).
 * Bu yüzden yalnız renk ve vurgu katmanını tanımlıyoruz; geri kalanı
 * GTK'nın kendi varsayılanı + GNOME'un dark modu sağlar.
 */

@define-color epix_lime        $LIME;
@define-color epix_lime_dark   $LIME_DARK;
@define-color epix_navy        $NAVY;
@define-color epix_navy_light  $NAVY_LIGHT;
@define-color epix_deep        $DEEP;

/* Pencere ve zemin renkleri: bunlar tanımlanmazsa GTK varsayılan
 * (beyaz/siyah) zemini kullanır ve tema "yarım" görünür.
 * Ekran görüntüsüyle doğrulandı: düğme/çubuk lime oluyordu ama
 * pencere zemini siyahtı. */
@define-color theme_bg_color        #16232a;
@define-color theme_fg_color        #e8f1f2;
@define-color theme_base_color      #11272e;
@define-color theme_text_color      #e8f1f2;
@define-color insensitive_bg_color  #1d333a;
@define-color insensitive_fg_color  #7f9599;

@define-color theme_selected_bg_color  @epix_lime;
@define-color theme_selected_fg_color  @epix_navy;
@define-color accent_color             @epix_lime;
@define-color accent_bg_color          @epix_lime;
@define-color accent_fg_color          @epix_navy;

/* Seçim ve vurgu */
selection {
  background-color: @epix_lime;
  color: @epix_navy;
}

/* Düğmeler: önerilen eylem (Kur, Kaydet) marka limi */
button.suggested-action {
  background-image: none;
  background-color: @epix_lime;
  color: @epix_navy;
  font-weight: 600;
  border-color: @epix_lime_dark;
}

button.suggested-action:hover {
  background-color: @epix_lime_dark;
}

button.suggested-action:active {
  background-color: shade(@epix_lime_dark, 0.92);
}

/* Yıkıcı eylem kırmızı kalır (marka rengi DEĞİL — güvenlik ipucu) */
button.destructive-action {
  background-image: none;
}

/* İlerleme çubuğu marka limi */
progressbar progress,
progressbar > trough > progress {
  background-color: @epix_lime;
  background-image: none;
}

/* Pencere zemini */
window, .background {
  background-color: @theme_bg_color;
  color: @theme_fg_color;
}

headerbar {
  background-image: none;
  background-color: @epix_deep;
  color: @theme_fg_color;
  border-bottom: 1px solid rgba(226, 255, 94, 0.12);
}

/* Girdi alanları */
entry, textview, spinbutton {
  background-color: @theme_base_color;
  color: @theme_text_color;
  border: 1px solid #235561;
}

/* Placeholder (ipucu) metni: tanımlanmazsa GTK varsayılanı kullanır ve
 * koyu zeminde okunmaz — ölçüldü: arama kutusunda ipucu hiç
 * görünmüyordu, yalnız büyüteç ikonu vardı. GTK3'te `entry` üzerinde
 * placeholder rengi `placeholder_text_color` ile verilir; ayrıca
 * Gtk.Entry'nin PlaceholderText düğümü için doğrudan kural yazılır. */
entry placeholder,
entry > placeholder,
entry.placeholder {
  color: #7f9599;
}

@define-color placeholder_text_color #7f9599;

entry:focus {
  border-color: @epix_lime;
}

/* Odak halkası */
*:focus {
  outline-color: alpha(@epix_lime, 0.7);
}

/* Seçili liste satırı */
row:selected,
list row:selected,
.view:selected {
  background-color: alpha(@epix_lime, 0.22);
  color: inherit;
}

/* Bağlantılar */
link, *:link {
  color: @epix_lime_dark;
}

/* Sekme vurgusu */
notebook > header > tabs > tab:checked {
  box-shadow: inset 0 -3px 0 0 @epix_lime;
}
GTKEOF

# GTK4: adwaita adını koruyup renk katmanı ekliyoruz
cat > "$GTKDIR/gtk-4.0/gtk.css" <<GTK4EOF
/* epixOS — GTK4 / libadwaita renk katmanı
 *
 * DÜRÜST NOT: libadwaita /usr/share/themes/<ad>/gtk-4.0/gtk.css DOSYASINI
 * OKUMAZ (tema desteğini bilinçli olarak kaldırdı). Vurgu rengini
 * değiştirmenin tek yolu kullanıcı CSS'idir:
 *     ~/.config/gtk-4.0/gtk.css   ->  @define-color accent_bg_color ...
 * `epix-tema` komutu bu dosyayı yazar. Bu dosya pakette yalnızca
 * referans amacıyla duruyor.
 *
 * Aşağıdaki :root { --accent-color } YAKLAŞIMI ÇALIŞMAZ — gerçek
 * ölçüimde hesap makinesinin "=" düğmesi turuncu kaldı (GNOME 46,
 * libadwaita 1.5). */

/* Yıkıcı eylem varsayılan kırmızıda kalır */
GTK4EOF

cat > "$GTKDIR/index.theme" <<IDXEOF
[Desktop Entry]
Type=X-GNOME-Metatheme
Name=epixOS-dark
Comment=epixOS marka teması (lime/navy)
Encoding=UTF-8

[X-GNOME-Metatheme]
GtkTheme=epixOS-dark
MetacityTheme=epixOS-dark
IconTheme=Yaru
CursorTheme=Yaru
ButtonLayout=appmenu:minimize,maximize,close
IDXEOF

c_ok "GTK3 + GTK4"

# ================================================================ 3) SHELL TEMASI
c_step "3/5 GNOME Shell teması"

cat > "$GTKDIR/gnome-shell/gnome-shell.css" <<SHEOF
/* epixOS — GNOME Shell teması
 * Yalnız marka vurgularını tanımlar; geri kalanı varsayılan kalır
 * (tam shell teması bakım yükü getirir ve sürüm kırılganlığı yaratır). */

stage {
  font-family: Ubuntu, Cantarell, sans-serif;
}

/* Üst çubuk: deep zemin, lime vurgu */
#panel {
  background-color: rgba(14, 42, 49, 0.96);
  border-bottom: 1px solid rgba(226, 255, 94, 0.12);
}

#panel .panel-button:hover {
  background-color: rgba(22, 64, 75, 0.9);
}

#panel .panel-button:active,
#panel .panel-button:checked,
#panel .panel-button:focus {
  background-color: rgba(226, 255, 94, 0.18);
  color: #e2ff5e;
}

#panel .clock-display {
  color: #e2ff5e;
  font-weight: 600;
}

/* Genel bakış arama kutusu */
.search-entry {
  border: 1px solid rgba(226, 255, 94, 0.35);
  caret-color: #e2ff5e;
}

.search-entry:focus {
  border-color: #e2ff5e;
  box-shadow: 0 0 0 2px rgba(226, 255, 94, 0.25);
}

/* Seçili uygulama ikonu */
.app-well-app:checked .overview-icon,
.app-well-app:active .overview-icon {
  background-color: rgba(226, 255, 94, 0.2);
  border: 1px solid #e2ff5e;
}

/* Çalışma alanı göstergesi */
.workspace-indicator:checked {
  background-color: #e2ff5e;
}

/* Bildirimler */
.notification-banner {
  border: 1px solid rgba(226, 255, 94, 0.25);
  background-color: rgba(22, 64, 75, 0.97);
}

.notification-banner:hover {
  border-color: #e2ff5e;
}

/* Takvim / hızlı ayarlar */
.quick-settings,
.calendar {
  background-color: rgba(14, 42, 49, 0.98);
}

.quick-toggle:checked,
.quick-toggle:active {
  background-color: rgba(226, 255, 94, 0.2);
  color: #e2ff5e;
}

/* Anahtar (switch) açıkken lime */
.toggle-switch:checked {
  background-color: #e2ff5e;
}
SHEOF
# DÜRÜST NOT: GNOME Shell, /usr/share/themes/<ad>/gnome-shell/gnome-shell.css
# dosyasını KENDİLİĞİNDEN yüklemez; bunun için kullanıcı teması uzantısı
# (User Themes) gerekir. Bu dosya, uzantı kurulduğunda devreye girer.
# Uzantı YOKKEN GNOME Shell varsayılan Adwaita temasını kullanır ve
# marka vurgusu yalnız GTK tarafında (uygulamalar, düğmeler) görünür.
# Bu bilinçli bir tercih: uzantıyı zorla kurmak kırılganlık getirir.
c_ok "gnome-shell.css (User Themes uzantısıyla etkin)"

# ================================================================ 4) DUYAR KAGITLARI
c_step "4/5 duvar kağıtları"

# Koyu (varsayılan) zaten var; açık varyant ve sade varyant üret
gen_wallpaper() {
  # $6 = motif opaklığı, $7 = wordmark opaklığı, $8 = ızgara opaklığı
  # AÇIK varyantta düşük kontrast sorunu yaşandı: navy (#16404b) soluk
  # zeminde kayboluyordu (ekran görüntüsüyle doğrulandı). Bu yüzden
  # opaklıklar varyanta göre ayarlanabilir.
  local out="$1" bg_from="$2" bg_to="$3" accent="$4" wordmark="$5"
  local motif_op="${6:-0.85}" wm_op="${7:-1}" grid_op="${8:-0.045}"
  cat > "$out" <<WLEOF
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1920 1080"
     preserveAspectRatio="xMidYMid slice">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0.35" y2="1">
      <stop offset="0%" stop-color="$bg_from"/>
      <stop offset="100%" stop-color="$bg_to"/>
    </linearGradient>
    <radialGradient id="haze" cx="0.5" cy="0.42" r="0.55">
      <stop offset="0%" stop-color="$accent" stop-opacity="0.20"/>
      <stop offset="60%" stop-color="$accent" stop-opacity="0.05"/>
      <stop offset="100%" stop-color="$accent" stop-opacity="0"/>
    </radialGradient>
    <filter id="soft"><feGaussianBlur stdDeviation="18"/></filter>
  </defs>

  <rect width="1920" height="1080" fill="url(#bg)"/>
  <rect width="1920" height="1080" fill="url(#haze)"/>

  <!-- X motifi: logodaki iki çapraz ışın -->
  <g opacity="$motif_op">
    <path d="M 660 240 L 1260 840" stroke="$accent" stroke-width="26"
          stroke-linecap="round" opacity="0.9"/>
    <path d="M 660 840 L 1260 240" stroke="$accent" stroke-width="26"
          stroke-linecap="round" opacity="0.9"/>
  </g>

  <!-- yumuşak ışık halesi -->
  <circle cx="960" cy="540" r="180" fill="$accent" opacity="0.10"
          filter="url(#soft)"/>

  <!-- ufuk yayları -->
  <g fill="none" stroke="$accent" stroke-opacity="$grid_op" stroke-width="1.5">
    <path d="M 0 900 Q 960 700 1920 900"/>
    <path d="M 0 960 Q 960 770 1920 960"/>
    <path d="M 0 1020 Q 960 840 1920 1020"/>
  </g>

  <!-- ızgara -->
  <g stroke="$accent" stroke-opacity="$grid_op" stroke-width="1">
    <path d="M 0 135 H 1920 M 0 270 H 1920 M 0 405 H 1920
             M 0 540 H 1920 M 0 675 H 1920 M 0 810 H 1920 M 0 945 H 1920"/>
    <path d="M 240 0 V 1080 M 480 0 V 1080 M 720 0 V 1080
             M 960 0 V 1080 M 1200 0 V 1080 M 1440 0 V 1080 M 1680 0 V 1080"/>
  </g>

  <!-- wordmark -->
  <text x="120" y="960" font-family="Ubuntu, Cantarell, sans-serif"
        font-size="58" font-weight="700" fill="$accent"
        opacity="$wm_op" letter-spacing="2">$wordmark</text>
  <text x="122" y="1002" font-family="Ubuntu, Cantarell, sans-serif"
        font-size="19" fill="$accent" opacity="$wm_op"
        letter-spacing="4">${EPIX_VERSION} · ${EPIX_RELEASE} · ${EPIX_CODENAME^^}</text>

  <!-- vinyet -->
  <rect width="1920" height="1080" fill="none"
        stroke="#000000" stroke-opacity="0.35" stroke-width="140"/>
</svg>
WLEOF
}

gen_wallpaper "$WORK/usr/share/backgrounds/epixos/epixos-dark.svg" \
  "$DEEP" "$NAVY" "$LIME" "epixOS"
# AÇIK varyant: vurgu NAVY olmalı (lime açık zeminde görünmez) ve
# opaklıklar yüksek tutulmalı — düşük opaklıkta motif kayboluyordu.
gen_wallpaper "$WORK/usr/share/backgrounds/epixos/epixos-light.svg" \
  "#f7fafb" "#dae5e8" "$NAVY" "epixOS" 1 1 0.10
gen_wallpaper "$WORK/usr/share/backgrounds/epixos/epixos-sade.svg" \
  "$DEEP" "$DEEP" "$LIME" "epixOS" 0.9 1 0.03

# ISO'da kullanılan varlıkları da pakete koy: ISO güncellenmeden
# tema güncellemesi alınabilsin (tek kaynak: branding/pixmaps/).
for f in logo.svg wallpaper-default.svg; do
  if [[ -f "$ROOT/branding/pixmaps/$f" ]]; then
    cp -f "$ROOT/branding/pixmaps/$f" "$WORK/usr/share/backgrounds/epixos/$f"
    c_ok "  branding/$f"
  fi
done

c_ok "epixos-dark.svg, epixos-light.svg, epixos-sade.svg"

# ================================================================ 5) DCONF + META
c_step "5/5 dconf, sürüm, DEBIAN"

# Drop-in: 50- ile başlar, 00-epix-defaults'ten SONRA okunur (sıralı).
# Böylece kullanıcının temel dosyadaki düzenlemeleri korunur.
cat > "$WORK/etc/dconf/db/local.d/50-epixos-tema" <<DCEOF
# epixOS tema paketi — dconf drop-in
#
# Sıralama: 00-epix-defaults (temel) -> 50-epixos-tema (bu dosya)
# dconf dosyaları sözlü sırayla okunur; 50 daha sonra geldiği için
# buradaki değerler temel dosyayı EZER. Kullanıcı kendi
# ~/.config/dconf/user dosyasında yine de değiştirebilir (kilitli değil).

[org/gnome/desktop/interface]
gtk-theme='epixOS-dark'
color-scheme='prefer-dark'
# accent-color KULLANILMAZ: GNOME 47+ ozelligi. epixOS GNOME 46
# kullaniyor ve bu anahtar "boyle bir anahtar yok" hatasi veriyor
# (olculdu). Vurgu rengi GTK temasindaki @define-color ile saglanir.

[org/gnome/desktop/background]
picture-uri='file:///usr/share/backgrounds/epixos/epixos-dark.svg'
picture-uri-dark='file:///usr/share/backgrounds/epixos/epixos-dark.svg'
picture-options='zoom'
primary-color='#0e2a31'
secondary-color='#16404b'

[org/gnome/desktop/screensaver]
picture-uri='file:///usr/share/backgrounds/epixos/epixos-dark.svg'
primary-color='#0e2a31'
secondary-color='#16404b'

[org/gnome/desktop/wm/preferences]
theme='epixOS-dark'
button-layout='appmenu:minimize,maximize,close'

[org/gnome/shell]
# Marka vurgusu için tema adı (kullanıcı tema eklentisi kurduysa)
favorite-apps=['epix-install.desktop','org.gnome.Nautilus.desktop','org.gnome.Terminal.desktop','org.gnome.Epiphany.desktop','org.gnome.TextEditor.desktop']
DCEOF

echo "${EPIX_VERSION} (${EPIX_RELEASE}) ${EPIX_CODENAME} — tema" \
  > "$WORK/usr/share/epixos/tema/version"

# Kolaylık komutu: temayı yeniden uygula
cat > "$WORK/usr/local/bin/epix-tema" <<'TEOF'
#!/bin/sh
# epixOS temasını yeniden uygula (dconf drop-in'i etkinleştir).
# Kullanım: epix-tema [--liste|--uygula]
set -e
case "${1:-}" in
  --liste|-l)
    echo "Kurulu epixOS duvar kağıtları:"
    ls -1 /usr/share/backgrounds/epixos/*.svg 2>/dev/null | sed 's|.*/|  |'
    echo
    echo "Etkin tema: $(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null)"
    echo "Renk duzeni: $(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null)"
    ;;
  *)
    # DİKKAT: burada `sudo` ÇAĞRILMAZ. epix-tema normal kullanıcı olarak
    # koşar; `sudo dconf update` interaktif şifre sorar ve betik sonsuza
    # kadar bekler (gerçek ölçümde 400 saniye askıda kaldı). Derlenmiş
    # veritabanını zaten paketin postinst'i root olarak güncelliyor.
    if command -v dconf >/dev/null 2>&1; then
      dconf update 2>/dev/null || true
    fi
    if command -v gsettings >/dev/null 2>&1; then
      gsettings set org.gnome.desktop.interface gtk-theme 'epixOS-dark' 2>/dev/null || true
      gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
      for k in picture-uri picture-uri-dark; do
        gsettings set org.gnome.desktop.background "$k" \
          'file:///usr/share/backgrounds/epixos/epixos-dark.svg' 2>/dev/null || true
      done
      gsettings set org.gnome.desktop.background picture-options 'zoom' 2>/dev/null || true
      gsettings set org.gnome.desktop.background primary-color '#0e2a31' 2>/dev/null || true
      gsettings set org.gnome.desktop.background secondary-color '#16404b' 2>/dev/null || true
      gsettings set org.gnome.desktop.wm.preferences theme 'epixOS-dark' 2>/dev/null || true
    fi
    # GTK4/libadwaita: vurgu rengi YALNIZCA kullanıcı CSS'i ile değişir.
    # Kendi bloğumuzu işaretleriz; kullanıcının elle eklediği satırlar korunur.
    GTK4_DIR="$HOME/.config/gtk-4.0"
    GTK4_CSS="$GTK4_DIR/gtk.css"
    mkdir -p "$GTK4_DIR" 2>/dev/null || true
    if [ -f "$GTK4_CSS" ] && grep -q 'epixOS-tema-baslangic' "$GTK4_CSS" 2>/dev/null; then
      sed -i '/epixOS-tema-baslangic/,/epixOS-tema-bitis/d' "$GTK4_CSS" 2>/dev/null || true
    fi
    if [ -w "$GTK4_DIR" ]; then
      cat >> "$GTK4_CSS" <<'CSSBLOCK'
/* epixOS-tema-baslangic */
@define-color accent_bg_color #e2ff5e;
@define-color accent_fg_color #16404b;
@define-color accent_color #e2ff5e;
@define-color window_bg_color #16232a;
@define-color window_fg_color #e8f1f2;
@define-color view_bg_color #11272e;
@define-color view_fg_color #e8f1f2;
/* epixOS-tema-bitis */
CSSBLOCK
      echo "  GTK4 vurgu dosyası: $GTK4_CSS"
    fi

    echo "epixOS teması uygulandı (lime #e2ff5e / navy #16404b)"
    echo "Değişiklikler için oturumu kapatıp açman gerekebilir."
    ;;
esac
TEOF
chmod 755 "$WORK/usr/local/bin/epix-tema"

# --- DEBIAN kontrol dosyası
SIZE="$(du -sk "$WORK/usr" "$WORK/etc" "$WORK/usr/local" 2>/dev/null | awk '{s+=$1} END {print s}')"
cat > "$WORK/DEBIAN/control" <<CTLEOF
Package: ${PKG}
Version: ${EPIX_VERSION}~${EPIX_RELEASE}
Section: x11
Priority: optional
Architecture: ${ARCH}
Installed-Size: ${SIZE:-120}
Depends: dconf-cli, dconf-gsettings-backend | gsettings-backend, libglib2.0-bin
Recommends: gnome-shell, gnome-themes-extra
Maintainer: epixOS Project <dev@epix.tr>
Homepage: https://os.epix.tr/
Description: epixOS marka teması (lime/navy)
 GTK3/GTK4 ve GNOME Shell için epixOS kurumsal teması.
 .
 Renkler gerçek logodan örneklendi: lime #e2ff5e, navy #16404b,
 deep #0e2a31. Duvar kağıtları (koyu/açık/sade), dconf drop-in ve
 epix-tema komutunu içerir.
 .
 ISO'yu yeniden kurmadan tema güncellemesi almak için tasarlandı.
CTLEOF

# conffiles: kullanıcı düzenlemesi korunsun
cat > "$WORK/DEBIAN/conffiles" <<'CNFEOF'
/etc/dconf/db/local.d/50-epixos-tema
CNFEOF

# --- postinst
cat > "$WORK/DEBIAN/postinst" <<'PSTEOF'
#!/bin/sh
set -e

case "$1" in
  configure|abort-upgrade|abort-remove|abort-deconfigure)
    # dconf drop-in'i yazıldı ama DERLENMEDİKÇE okunmaz.
    # `dconf update` sistem veritabanını yeniden derler.
    # `dconf update` ZORUNLU: drop-in dosyası yazıldı ama derlenmiş
    # veritabanı (/etc/dconf/db/local) güncellenmezse HİÇBİR ayar okunmaz.
    # `dconf` komutu dconf-cli paketinden gelir (bağımlılıkta).
    if command -v dconf >/dev/null 2>&1; then
      dconf update ||         echo "epixos-tema: uyari: dconf update basarisiz (ayarlar sonraki acilista uygulanir)" >&2
    else
      echo "epixos-tema: uyari: dconf bulunamadi (dconf-cli kurulu degil)" >&2
    fi

    # /etc/dconf/profile/user yoksa oluştur: olmadan sistem veritabanı
    # (system-db:local) hiç okunmaz. epixOS ISO'da bu dosya var ama
    # paket bağımsız kurulduğunda (ör. düz Ubuntu) yok olabilir.
    if [ ! -f /etc/dconf/profile/user ]; then
      mkdir -p /etc/dconf/profile
      printf 'user-db:user\nsystem-db:local\n' > /etc/dconf/profile/user
      chmod 644 /etc/dconf/profile/user
    fi

    # ikon önbelleği (tema ikon eklerse)
    if command -v gtk-update-icon-cache >/dev/null 2>&1; then
      gtk-update-icon-cache -f -t /usr/share/icons/hicolor >/dev/null 2>&1 || true
    fi

    # Oturum açmış kullanıcıların teması hemen değişsin (varsa)
    # DİKKAT: postinst root olarak çalışır; gsettings KULLANICININ
    # dbus oturumuna bağlanmalıdır. Bağlanamazsa sessizce geç.
    for u in $(getent passwd | awk -F: '$3>=1000 && $3<65534 {print $1}'); do
      home=$(getent passwd "$u" | cut -d: -f6)
      [ -d "$home" ] || continue
      uid=$(id -u "$u" 2>/dev/null) || continue
      if [ -S "/run/user/$uid/bus" ]; then
        su -s /bin/sh "$u" -c \
          "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus \
           gsettings set org.gnome.desktop.interface gtk-theme 'epixOS-dark'" \
          >/dev/null 2>&1 || true
        su -s /bin/sh "$u" -c \
          "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus \
           gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'" \
          >/dev/null 2>&1 || true
      fi
    done
    ;;
esac

exit 0
PSTEOF
chmod 755 "$WORK/DEBIAN/postinst"

# --- postrm
cat > "$WORK/DEBIAN/postrm" <<'PSTEOF'
#!/bin/sh
set -e

case "$1" in
  remove|purge)
    # Drop-in silindi; veritabanını yeniden derle ki etkisi kalksın.
    # /etc/dconf/profile/user SİLİNMEZ: başka paketler de kullanabilir
    # ve kullanıcı sistemi onu elle oluşturmuş olabilir.
    if command -v dconf >/dev/null 2>&1; then
      dconf update || true
    fi
    ;;
esac

exit 0
PSTEOF
chmod 755 "$WORK/DEBIAN/postrm"

# --- izinler
find "$WORK" -type d -exec chmod 755 {} +
find "$WORK" -type f -exec chmod 644 {} +
chmod 755 "$WORK/usr/local/bin/epix-tema"
chmod 755 "$WORK/DEBIAN/postinst" "$WORK/DEBIAN/postrm"

# ================================================================ PAKETLE
c_step "paket üretiliyor"
mkdir -p "$DIST"
dpkg-deb --root-owner-group -b "$WORK" "$OUT" >/dev/null
chmod 644 "$OUT"

c_ok "$(basename "$OUT")"
printf '  boyut : %s\n' "$(du -h "$OUT" | cut -f1)"
printf '  sha256: %s\n' "$(sha256sum "$OUT" | cut -d' ' -f1)"
printf '  dosya : %s\n' "$(dpkg-deb -c "$OUT" | grep -vc '^d')"

echo
c_ok "depoyu güncellemek için:  sudo ./scripts/make-repo.sh"
