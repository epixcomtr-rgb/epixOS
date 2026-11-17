/* ==========================================================================
   epixOS — mağaza etkileşimi
   Süzgeç + arama + kopyalama. Çerçeve yok, bağımlılık yok.
   JS kapalıysa sayfa yine çalışır: tüm kartlar ve komutlar görünür,
   yalnızca süzme/kopyalama düğmeleri devre dışı kalır.
   ========================================================================== */
(function () {
  'use strict';

  var grid = document.getElementById('mk-grid');
  if (!grid) return;

  var kartlar = Array.prototype.slice.call(grid.querySelectorAll('.mk-card'));
  var cipler = Array.prototype.slice.call(
    document.querySelectorAll('#mk-chips .mk-chip')
  );
  var araKutu = document.getElementById('mk-ara');
  var sayac = document.getElementById('mk-sayac');
  var bos = document.getElementById('mk-bos');
  var sifirla = document.getElementById('mk-sifirla');

  var aktifKat = 'hepsi';
  var sorgu = '';

  /* ------------------------------------------------------------ süzme */
  function uygula() {
    var gorunen = 0;

    kartlar.forEach(function (kart) {
      var katUyar = aktifKat === 'hepsi' || kart.dataset.kat === aktifKat;
      var araUyar = !sorgu || kart.dataset.arama.indexOf(sorgu) !== -1;
      var goster = katUyar && araUyar;

      kart.hidden = !goster;
      if (goster) gorunen++;
    });

    if (sayac) {
      sayac.textContent = gorunen + ' uygulama';
    }
    if (bos) {
      bos.hidden = gorunen !== 0;
    }
  }

  /* ------------------------------------------------------------ çipler */
  cipler.forEach(function (cip) {
    cip.addEventListener('click', function () {
      cipler.forEach(function (c) {
        c.classList.remove('is-on');
        c.setAttribute('aria-pressed', 'false');
      });
      cip.classList.add('is-on');
      cip.setAttribute('aria-pressed', 'true');
      aktifKat = cip.dataset.kat || 'hepsi';
      uygula();
    });

    // Başlangıç durumunu erişilebilirlik için bildir
    cip.setAttribute('aria-pressed', cip.classList.contains('is-on') ? 'true' : 'false');
  });

  /* ------------------------------------------------------------ arama */
  if (araKutu) {
    araKutu.addEventListener('input', function () {
      // Türkçe küçük harfe çevirme: 'I' -> 'ı' olmalı, yoksa "ISO"
      // araması "ıso" ile eşleşmez.
      sorgu = araKutu.value.trim().toLocaleLowerCase('tr-TR');
      uygula();
    });
  }

  if (sifirla) {
    sifirla.addEventListener('click', function () {
      if (araKutu) araKutu.value = '';
      sorgu = '';
      aktifKat = 'hepsi';
      cipler.forEach(function (c, i) {
        c.classList.toggle('is-on', i === 0);
        c.setAttribute('aria-pressed', i === 0 ? 'true' : 'false');
      });
      uygula();
      if (araKutu) araKutu.focus();
    });
  }

  /* ------------------------------------------------------------ kopyala */
  function kopyala(metin) {
    // clipboard API yalnızca güvenli bağlamda (https) çalışır
    if (navigator.clipboard && navigator.clipboard.writeText) {
      return navigator.clipboard.writeText(metin);
    }
    // Yedek yol: gizli textarea + execCommand
    return new Promise(function (resolve, reject) {
      var ta = document.createElement('textarea');
      ta.value = metin;
      ta.setAttribute('readonly', '');
      ta.style.position = 'fixed';
      ta.style.top = '-1000px';
      document.body.appendChild(ta);
      ta.select();
      try {
        document.execCommand('copy') ? resolve() : reject();
      } catch (e) {
        reject(e);
      } finally {
        document.body.removeChild(ta);
      }
    });
  }

  document.addEventListener('click', function (e) {
    var dugme = e.target.closest('.mk-copy');
    if (!dugme) return;

    var metin = dugme.dataset.kopya;
    if (!metin) return;

    kopyala(metin).then(function () {
      var ikon = dugme.querySelector('.ms');
      var eskiIkon = ikon ? ikon.textContent : '';
      dugme.classList.add('is-done');
      if (ikon) ikon.textContent = 'check';
      dugme.setAttribute('aria-label', 'Kopyalandı');

      setTimeout(function () {
        dugme.classList.remove('is-done');
        if (ikon) ikon.textContent = eskiIkon;
        dugme.setAttribute('aria-label', 'Kurulum komutunu kopyala');
      }, 1600);
    }).catch(function () {
      // Kopyalama başarısız — komutu seçip kullanıcıya göster
      var kod = dugme.parentElement.querySelector('code');
      if (kod) {
        var aralik = document.createRange();
        aralik.selectNodeContents(kod);
        var secim = window.getSelection();
        secim.removeAllRanges();
        secim.addRange(aralik);
      }
    });
  });

  /* ------------------------------------------------------------ başlat */
  uygula();
})();
