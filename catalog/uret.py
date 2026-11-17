#!/usr/bin/env python3
"""
epixOS katalog üretici — TEK KAYNAK'tan iki çıktı.

  catalog/katalog.json
        ├──> dist/epix-market            (terminal komutu, gömülü veri)
        ├──> site/market/index.html      (web mağazası)

Neden üretici betik: katalog elle iki yerde tutulursa kaçınılmaz olarak
birbirinden ayrışır ve kullanıcı sitede gördüğü komutu çalıştıramaz.
Tek kaynak + üretim = sitenin gösterdiği her komut gerçekten çalışır.

Kullanım:
    ./catalog/uret.py              # ikisini de üret
    ./catalog/uret.py --kontrol    # sadece doğrula (CI için)

Katalog bozuksa GÜRÜLTÜLÜ hata verir ve hiçbir şey yazmaz.
"""
from __future__ import annotations

import html
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
KATALOG = ROOT / "catalog" / "katalog.json"
KOMUT_CIKTI = ROOT / "dist" / "epix-market"
SITE_CIKTI = ROOT / "site" / "market" / "index.html"
SABLON = ROOT / "catalog" / "epix-market.sh.in"
GUI_SABLON = ROOT / "catalog" / "epix-market-gui.py.in"
GUI_CIKTI = ROOT / "dist" / "epix-market-gui"          # kabuk sarıcı (755)
GUI_PY_CIKTI = ROOT / "dist" / "epix-market-gui.py"   # GTK3 arayüzü (644)


def hata(mesaj: str, *ayrinti: str) -> None:
    print(f"\033[1;31mHATA:\033[0m {mesaj}", file=sys.stderr)
    for a in ayrinti:
        print(f"  {a}", file=sys.stderr)
    sys.exit(1)


def yukle() -> dict:
    if not KATALOG.is_file():
        hata(f"katalog bulunamadı: {KATALOG}")

    try:
        veri = json.loads(KATALOG.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        # Bozuk JSON'da hangi satır olduğunu söyle — elle düzenlemede şart
        hata(
            "katalog JSON'u bozuk",
            f"satır {e.lineno}, sütun {e.colno}: {e.msg}",
            f"dosya: {KATALOG}",
        )

    # ---------------------------------------------------------- doğrulama
    kategoriler = veri.get("kategoriler")
    uygulamalar = veri.get("uygulamalar")
    if not isinstance(kategoriler, list) or not kategoriler:
        hata("'kategoriler' boş veya dizi değil")
    if not isinstance(uygulamalar, list) or not uygulamalar:
        hata("'uygulamalar' boş veya dizi değil")

    kimlikler = set()
    for k in kategoriler:
        for alan in ("id", "ad", "aciklama"):
            if not k.get(alan):
                hata(f"kategori alanı eksik: {alan}", json.dumps(k, ensure_ascii=False))
        if k["id"] in kimlikler:
            hata(f"kategori kimliği tekrarlı: {k['id']}")
        if not re.fullmatch(r"[a-z0-9-]+", k["id"]):
            hata(f"kategori kimliği yalnızca a-z, 0-9, - içermeli: {k['id']}")
        kimlikler.add(k["id"])

    paketler = set()
    for a in uygulamalar:
        for alan in ("ad", "paket", "kategori", "baslik", "aciklama"):
            if not a.get(alan):
                hata(f"uygulama alanı eksik: {alan}", json.dumps(a, ensure_ascii=False))
        if a["kategori"] not in kimlikler:
            hata(
                f"bilinmeyen kategori: {a['kategori']}",
                f"uygulama: {a['paket']}",
                f"geçerli: {', '.join(sorted(kimlikler))}",
            )
        if a["paket"] in paketler:
            hata(f"paket adı tekrarlı: {a['paket']}")
        paketler.add(a["paket"])
        # Sekme ve yeni satır gömülü katalog biçimini bozar
        for alan, deger in a.items():
            if isinstance(deger, str) and ("\t" in deger or "\n" in deger):
                hata(f"'{alan}' alanında sekme/satır sonu var: {a['paket']}")

    return veri


def katalog_satirlari(veri: dict) -> list[str]:
    """epix-market'ın okuduğu sekmeyle ayrılmış biçim."""
    kategoriler = {k["id"]: k["ad"] for k in veri["kategoriler"]}
    satirlar = []
    for a in veri["uygulamalar"]:
        boyut = a.get("boyut_mb", 0)
        # 0 ve boş -> boş metin (komut "boyut" satırını atlar)
        boyut_s = "" if not boyut else f"{boyut:g}"
        satirlar.append(
            "\t".join(
                [
                    a["kategori"],
                    kategoriler[a["kategori"]],
                    a["paket"],
                    a["baslik"],
                    boyut_s,
                    "1" if a.get("epix") else "0",
                    " ".join(a.get("etiketler", [])),
                    a["aciklama"],
                ]
            )
        )
    return satirlar


def komut_uret(veri: dict) -> None:
    if not SABLON.is_file():
        hata(f"şablon bulunamadı: {SABLON}")

    sablon = SABLON.read_text(encoding="utf-8")

    # SADECE heredoc gövdesindeki yer tutucu değiştirilmeli. Şablonun
    # yorumlarında da "@KATALOG@" geçiyor ("@KATALOG@ yerine ...");
    # naive str.replace() yorumu da kataloğun tamamıyla doldurup kabuğu
    # bozuyordu — "epixos: not found", "Syntax error: ( unexpected".
    # Bu yüzden yer tutucuyu heredoc sınırları içinde arıyoruz.
    desen = re.compile(
        r"(<<'KATALOG_EOF'\n)@KATALOG@(\nKATALOG_EOF)", re.MULTILINE
    )
    if not desen.search(sablon):
        hata(
            "şablonda heredoc içinde @KATALOG@ bulunamadı",
            "beklenen biçim: <<'KATALOG_EOF' satırından sonra tek başına @KATALOG@",
            str(SABLON),
        )

    gomulu = "\n".join(katalog_satirlari(veri))
    cikti = desen.sub(lambda m: m.group(1) + gomulu + m.group(2), sablon, count=1)

    KOMUT_CIKTI.parent.mkdir(parents=True, exist_ok=True)
    KOMUT_CIKTI.write_text(cikti, encoding="utf-8")
    KOMUT_CIKTI.chmod(0o755)
    print(f"  \033[32m==>\033[0m {KOMUT_CIKTI.relative_to(ROOT)}  "
          f"({len(veri['uygulamalar'])} uygulama)")


def gui_uret(veri: dict) -> None:
    """GTK3 arayüzü — katalog yine gömülü, aynı biçim."""
    if not GUI_SABLON.is_file():
        hata(f"GUI şablonu bulunamadı: {GUI_SABLON}")

    sablon = GUI_SABLON.read_text(encoding="utf-8")

    # SADECE `HAM_KATALOG = """@KATALOG@"""` içindeki yer tutucu.
    # Şablonun yorumunda da "@KATALOG@" geçiyor; naive replace() onu da
    # kataloğun tamamıyla doldurup Python'u bozar (epix-market.sh'te
    # birebir aynı hata yaşandı).
    desen = re.compile(r'(HAM_KATALOG = """)@KATALOG@(""")')
    if not desen.search(sablon):
        hata(
            "GUI şablonunda HAM_KATALOG içinde @KATALOG@ bulunamadı",
            'beklenen biçim: HAM_KATALOG = """@KATALOG@"""',
            str(GUI_SABLON),
        )

    gomulu = "\n".join(katalog_satirlari(veri))
    # lambda: gomulu içindeki \1 gibi dizilerin geri referans sayılmaması için
    cikti = desen.sub(lambda m: m.group(1) + gomulu + m.group(2), sablon, count=1)

    # Python sözdizimini ÜRETİM ANINDA doğrula: bozuk bir arayüz
    # kullanıcıya "açılmıyor" olarak yansır, sebebi görünmez.
    try:
        compile(cikti, str(GUI_CIKTI), "exec")
    except SyntaxError as e:
        hata(
            "üretilen GUI betiği geçersiz Python",
            f"satır {e.lineno}: {e.msg}",
            "şablon: catalog/epix-market-gui.py.in",
        )

    GUI_CIKTI.parent.mkdir(parents=True, exist_ok=True)
    GUI_PY_CIKTI.write_text(cikti, encoding="utf-8")
    GUI_PY_CIKTI.chmod(0o644)

    # Kabuk sarmalayıcı: python3 veya GTK yoksa SESSİZCE ölmesin.
    #
    # NEDEN: --no-install-recommends ile kurulan minimal sistemlerde
    # python3 hiç yok (ölçüldü: debootstrap minbase + epixos-base).
    # O durumda "#! /usr/bin/env python3" satırı "No such file or
    # directory" verir ve .desktop kısayoluna tıklayan kullanıcı hiçbir
    # şey görmez. Sarmalayıcı durumu anlatıp terminal sürümüne yönlendirir.
    sarmalayici = """#!/bin/sh
# epix-market-gui — epixOS Mağaza başlatıcı
#
# Gerçek arayüz /usr/lib/epixos/epix-market-gui.py dosyasındadır.
# Bu sarmalayıcı, eksik bağımlılık durumunda SESSİZCE ölmek yerine
# ne yapılacağını söyler (minimal kurulumlarda python3 olmayabilir).
set -u

PY=/usr/lib/epixos/epix-market-gui.py

if [ ! -f "$PY" ]; then
  echo "epix-market-gui: arayüz dosyası bulunamadı: $PY" >&2
  echo "  Yeniden kur: sudo apt install --reinstall epixos-base" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  cat >&2 <<'MSG'
epix-market-gui: python3 bulunamadı.

Grafik arayüz için gerekli:
    sudo apt install python3 python3-gi gir1.2-gtk-3.0

Terminal sürümü her zaman çalışır:
    epix-market            (kategori özeti)
    epix-market liste      (tüm uygulamalar)
MSG
  exit 1
fi

# GTK3 bağlantısı var mı? Yoksa anlaşılır mesaj ver.
if ! python3 -c 'import gi; gi.require_version("Gtk","3.0")' >/dev/null 2>&1; then
  cat >&2 <<'MSG'
epix-market-gui: GTK3 bağlantıları eksik.

    sudo apt install python3-gi gir1.2-gtk-3.0

Terminal sürümü: epix-market
MSG
  exit 1
fi

exec python3 "$PY" "$@"
"""
    GUI_CIKTI.write_text(sarmalayici, encoding="utf-8")
    GUI_CIKTI.chmod(0o755)

    print(f"  \033[32m==>\033[0m {GUI_CIKTI.relative_to(ROOT)}  (başlatıcı)")
    print(f"  \033[32m==>\033[0m {GUI_PY_CIKTI.relative_to(ROOT)}  "
          f"({len(veri['uygulamalar'])} uygulama, GTK3)")


def site_uret(veri: dict) -> None:
    e = html.escape
    kat_liste = veri["kategoriler"]
    uygulamalar = veri["uygulamalar"]

    # Kategoriye göre grupla
    gruplar: dict[str, list[dict]] = {k["id"]: [] for k in kat_liste}
    for a in uygulamalar:
        gruplar[a["kategori"]].append(a)

    # ---------- kategori düğmeleri (süzgeç)
    dugmeler = ['<button class="mk-chip is-on" data-kat="hepsi" type="button">'
                f'Hepsi <span class="mk-n">{len(uygulamalar)}</span></button>']
    for k in kat_liste:
        n = len(gruplar[k["id"]])
        dugmeler.append(
            f'<button class="mk-chip" data-kat="{e(k["id"])}" type="button">'
            f'{e(k["ad"])} <span class="mk-n">{n}</span></button>'
        )

    # ---------- kartlar
    kartlar = []
    for a in uygulamalar:
        kat_ad = next(k["ad"] for k in kat_liste if k["id"] == a["kategori"])
        boyut = a.get("boyut_mb", 0)
        boyut_html = (
            f'<span class="mk-meta-item"><span class="ms" aria-hidden="true">download</span>'
            f'~{boyut:g} MB</span>' if boyut else ""
        )
        epix_rozet = (
            '<span class="mk-badge mk-badge--epix">epixOS</span>'
            if a.get("epix") else ""
        )
        etiketler = "".join(
            f'<span class="mk-tag">{e(t)}</span>' for t in a.get("etiketler", [])
        )
        # data-arama: arama kutusunun eşleştirdiği metin (küçük harfe çevrilir)
        arama = " ".join(
            [a["baslik"], a["paket"], a["aciklama"], " ".join(a.get("etiketler", []))]
        ).lower()
        kartlar.append(f"""
        <article class="mk-card" data-kat="{e(a['kategori'])}" data-arama="{e(arama)}">
          <div class="mk-card-top">
            <h3>{e(a['baslik'])}</h3>
            {epix_rozet}
          </div>
          <p class="mk-cat">{e(kat_ad)}</p>
          <p class="mk-desc">{e(a['aciklama'])}</p>
          <div class="mk-meta">
            <code class="mk-pkg">{e(a['paket'])}</code>
            {boyut_html}
          </div>
          <div class="mk-tags">{etiketler}</div>
          <div class="mk-cmd">
            <code>sudo apt install {e(a['paket'])}</code>
            <button class="mk-copy" type="button"
                    data-kopya="sudo apt install {e(a['paket'])}"
                    aria-label="{e(a['paket'])} kurulum komutunu kopyala">
              <span class="ms" aria-hidden="true">content_copy</span>
            </button>
          </div>
        </article>""")

    # ---------- depo kurulumu bloğu (epixOS paketleri için şart)
    depo_blok = """
      <div class="mk-notice">
        <span class="ms" aria-hidden="true">info</span>
        <div>
          <p><b>epixOS paketleri için önce depo gerekir.</b> Bir kez kurulur:</p>
          <div class="mk-cmd mk-cmd--wide">
            <code>curl -fsSL https://os.epix.tr/indir/epix-depo-kur.sh | sudo sh</code>
            <button class="mk-copy" type="button"
                    data-kopya="curl -fsSL https://os.epix.tr/indir/epix-depo-kur.sh | sudo sh"
                    aria-label="Depo kurulum komutunu kopyala">
              <span class="ms" aria-hidden="true">content_copy</span>
            </button>
          </div>
        </div>
      </div>"""

    sayfa = f"""<!DOCTYPE html>
<html lang="tr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Uygulama mağazası — epixOS</title>
<meta name="description" content="epixOS uygulama kataloğu: {len(uygulamalar)} uygulama, açıklamaları ve kurulum komutları. Tek komutla kur, terminalde epix-market ile de gez.">
<meta name="theme-color" content="#0e2a31">
<link rel="canonical" href="https://os.epix.tr/market/">
<link rel="icon" href="/assets/img/favicon.png" type="image/png">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter+Tight:wght@500;600;700;800&family=Inter:wght@400;500;600&display=swap">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Material+Symbols+Outlined:opsz,wght,FILL,GRAD@20..48,300..600,0..1,0&display=swap">
<link rel="stylesheet" href="/assets/css/tx.css">
<link rel="stylesheet" href="/assets/css/os.css">
<link rel="stylesheet" href="/assets/css/market.css">
<meta property="og:type" content="website">
<meta property="og:title" content="Uygulama mağazası — epixOS">
<meta property="og:description" content="{len(uygulamalar)} uygulama, açıklamaları ve kurulum komutları.">
<meta property="og:url" content="https://os.epix.tr/market/">
<meta property="og:image" content="https://os.epix.tr/assets/img/og.png">
</head>
<body>

<a class="skip" href="#main">İçeriğe geç</a>

<header class="site-header" id="siteHeader">
  <div class="wrap nav">
    <a class="brand" href="https://epix.tr/" aria-label="Epix ana sayfa">
      <img src="/assets/img/logo.png" alt="Epix Software House" width="436" height="238"/>
    </a>
    <ul class="menu">
      <li><a href="/">Genel bakış</a></li>
      <li><a href="/indir/">İndir</a></li>
      <li><a href="/market/" aria-current="page">Mağaza</a></li>
      <li><a href="/surum-notlari/">Sürüm notları</a></li>
      <li><a href="/#ozellikler">Özellikler</a></li>
      <li><a href="https://epix.tr/iletisim">İletişim</a></li>
    </ul>
    <div class="nav-cta">
      <a class="btn btn-primary btn-sm" href="/indir/">
        <span class="ms" aria-hidden="true">download</span>İndir
      </a>
    </div>
    <button class="burger" type="button" aria-label="Menü" aria-expanded="false" id="burger">
      <span></span><span></span><span></span>
    </button>
  </div>
</header>

<main id="main">

  <section class="os-hero mk-hero">
    <div class="wrap">
      <nav class="crumbs" aria-label="Konum">
        <a href="/">epixOS</a><span aria-hidden="true">/</span><span>Mağaza</span>
      </nav>
      <h1>Uygulama mağazası</h1>
      <p class="lead">
        {len(uygulamalar)} uygulama, ne işe yaradıkları ve kurulum komutları.
        Beğendiğini seç, komutu kopyala, terminale yapıştır.
        Terminali seviyorsan hepsi <code>epix-market</code> içinde de var.
      </p>
      <div class="mk-hero-actions">
        <a class="btn btn-primary" href="#katalog">
          <span class="ms" aria-hidden="true">grid_view</span>Kataloğa bak
        </a>
        <a class="btn btn-ghost" href="/indir/">
          <span class="ms" aria-hidden="true">download</span>epixOS indir
        </a>
      </div>
    </div>
  </section>

  <section class="os-section" id="katalog">
    <div class="wrap">

      <div class="mk-toolbar">
        <div class="mk-search">
          <span class="ms" aria-hidden="true">search</span>
          <input type="search" id="mk-ara" placeholder="Uygulama ara: fotoğraf, video, pdf…"
                 aria-label="Uygulama ara" autocomplete="off">
        </div>
        <p class="mk-sayac" id="mk-sayac" aria-live="polite">{len(uygulamalar)} uygulama</p>
      </div>

      <div class="mk-chips" id="mk-chips" role="group" aria-label="Kategori süzgeci">
        {"".join(dugmeler)}
      </div>

      {depo_blok}

      <div class="mk-grid" id="mk-grid">
        {"".join(kartlar)}
      </div>

      <p class="mk-bos" id="mk-bos" hidden>
        Aramanla eşleşen uygulama yok. Farklı bir kelime dene ya da
        <button class="mk-link" type="button" id="mk-sifirla">süzgeçleri temizle</button>.
      </p>

    </div>
  </section>

  <section class="os-section os-alt" id="terminal">
    <div class="wrap">
      <div class="os-head">
        <h2>Terminali mi seviyorsun?</h2>
        <p class="lead">Aynı katalog <code>epix-market</code> komutunda da var — ağ gerekmez.</p>
      </div>
      <div class="mk-term">
        <div class="mk-term-bar">
          <span class="mk-dot"></span><span class="mk-dot"></span><span class="mk-dot"></span>
          <span class="mk-term-title">epix-market</span>
        </div>
        <pre class="mk-term-body"><code><span class="mk-p">$</span> epix-market
  epixos            3 uygulama
  internet          3 uygulama
  ofis              4 uygulama
  grafik            4 uygulama
  medya             5 uygulama
  gelistirme        3 uygulama
  sistem            5 uygulama

<span class="mk-p">$</span> epix-market bilgi gimp
<span class="mk-c">GIMP</span>
Grafik ve fotoğraf

Güçlü ve ücretsiz fotoğraf düzenleyici. Katmanlar, fırçalar…

  paket      : gimp
  boyut      : yaklaşık 95 MB indirme
  kaynak     : Ubuntu deposu
  durum      : kurulu değil

  <span class="mk-k">Kurulum:</span>
    sudo apt install gimp

<span class="mk-p">$</span> epix-market kur gimp vlc</code></pre>
      </div>
      <p class="mk-term-not">
        <code>epix-market</code> komutu <code>epixos-base</code> paketiyle gelir.
        Gelmiyorsa: <code>sudo apt install --reinstall epixos-base</code>
      </p>
    </div>
  </section>

</main>

<footer class="site-footer">
  <div class="wrap">
    <div class="f-grid">
      <div class="f-brand">
        <img src="/assets/img/logo.png" alt="Epix Software House" width="436" height="238"/>
        <p>Hafif, hızlı ve AI ile yönetilen Linux dağıtımı.</p>
      </div>
      <div class="f-col">
        <h4>epixOS</h4>
        <a href="/">Genel bakış</a>
        <a href="/indir/">İndir</a>
        <a href="/market/">Mağaza</a>
        <a href="/surum-notlari/">Sürüm notları</a>
        <a href="/#ozellikler">Özellikler</a>
        <a href="/#sss">SSS</a>
      </div>
      <div class="f-col">
        <h4>Epix</h4>
        <a href="https://epix.tr/">Ana sayfa</a>
        <a href="https://epix.tr/iletisim">İletişim</a>
        <a href="https://hub.epix.tr/giris">Epix Hub</a>
      </div>
      <div class="f-col">
        <h4>Sürüm</h4>
        <a href="/surum-notlari/#teknik">epixOS 0.1</a>
        <a href="/surum-notlari/">2026.11 — kavak</a>
        <a href="/surum-notlari/">amd64</a>
      </div>
    </div>
    <div class="f-bottom">
      <span>&copy; <span id="yil">2026</span> Epix Software House. epixOS açık kaynak bir projedir.</span>
      <span>GPL-3.0 · <a href="https://github.com/epixcomtr-rgb/epixOS" rel="noopener">GitHub</a></span>
    </div>
  </div>
</footer>

"""

    # ---- footer altındaki betikler ayrı string: f-string içinde
    # JavaScript süslü parantezleri kaçırma cehennemine girmemek için.
    sayfa += """<script src="/assets/js/market.js" defer></script>
<script>
/* Burger menü — indir/ sayfasındaki ile aynı davranış */
(function () {
  var y = document.getElementById('yil');
  if (y) y.textContent = new Date().getFullYear();

  var burger = document.getElementById('burger');
  var menu = document.querySelector('.menu');
  if (burger && menu) {
    burger.addEventListener('click', function () {
      var open = menu.classList.toggle('open');
      burger.setAttribute('aria-expanded', open ? 'true' : 'false');
    });
    menu.querySelectorAll('a').forEach(function (a) {
      a.addEventListener('click', function () {
        menu.classList.remove('open');
        burger.setAttribute('aria-expanded', 'false');
      });
    });
  }
})();
</script>
</body>
</html>
"""



    SITE_CIKTI.parent.mkdir(parents=True, exist_ok=True)
    SITE_CIKTI.write_text(sayfa, encoding="utf-8")
    print(f"  \033[32m==>\033[0m {SITE_CIKTI.relative_to(ROOT)}  "
          f"({len(uygulamalar)} kart)")


def main() -> None:
    veri = yukle()
    print("\033[1;36m### epixOS katalog üretimi\033[0m")

    if "--kontrol" in sys.argv:
        print(f"  \033[32m✓\033[0m katalog geçerli: "
              f"{len(veri['kategoriler'])} kategori, "
              f"{len(veri['uygulamalar'])} uygulama")
        return

    komut_uret(veri)
    gui_uret(veri)
    site_uret(veri)

    print(f"\n  sonraki adım: ./scripts/deploy-site.sh   (siteyi yayınlar)")
    print(f"  komutu sisteme kurmak için: sudo ./scripts/make-deb.sh\n")


if __name__ == "__main__":
    main()
