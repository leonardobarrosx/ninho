// Ninho gift list: a family's layette, shared at /lista/<slug>. Visitors pick items, whole or in part, pay the
// family by Pix (static BR Code: QR and copia e cola) and then record the gift so the family can confirm it.
// Every value from the list is set as text, never as HTML.
(function () {
  'use strict';
  var api = (window.NINHO_API_URL || '').replace(/\/$/, '');
  var params = new URLSearchParams(location.search);
  var slug = (location.pathname.match(/^\/lista\/([^/]+)/) || [])[1] || params.get('l') || 'exemplo';
  slug = decodeURIComponent(slug).toLowerCase();
  var example = !api || slug === 'exemplo';
  var $ = function (id) { return document.getElementById(id); };
  var list = null;
  var cart = {}; // goal id -> cents
  var free = 0;
  var pixCode = '';

  var brl = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' });
  function money(cents) { return brl.format(cents / 100); }
  function parseMoney(text) {
    var s = String(text || '').replace(/[R$\s]/g, '');
    if (s.indexOf(',') >= 0) s = s.replace(/\./g, '').replace(',', '.');
    if (!/^\d+(\.\d{1,2})?$/.test(s)) return null;
    var parts = s.split('.');
    return parseInt(parts[0], 10) * 100 + (parts[1] ? parseInt((parts[1] + '0').slice(0, 2), 10) : 0);
  }
  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  }

  // ---- Pix BR Code (EMV QR Code, static) ----
  function field(id, value) { return id + String(value.length).padStart(2, '0') + value; }
  function ascii(text, max) {
    return String(text || '').normalize('NFD').replace(/[̀-ͯ]/g, '')
      .replace(/[^A-Za-z0-9 .\-]/g, '').trim().toUpperCase().slice(0, max);
  }
  function crc16(payload) {
    var crc = 0xffff;
    for (var i = 0; i < payload.length; i++) {
      crc ^= payload.charCodeAt(i) << 8;
      for (var j = 0; j < 8; j++) crc = crc & 0x8000 ? (crc << 1) ^ 0x1021 : crc << 1;
      crc &= 0xffff;
    }
    return crc.toString(16).toUpperCase().padStart(4, '0');
  }
  function pix(key, name, city, cents) {
    var payload = field('00', '01') +
      field('26', field('00', 'br.gov.bcb.pix') + field('01', key.trim())) +
      field('52', '0000') + field('53', '986') +
      field('54', (cents / 100).toFixed(2)) +
      field('58', 'BR') + field('59', ascii(name, 25) || 'RECEBEDOR') + field('60', ascii(city, 15) || 'BRASIL') +
      field('62', field('05', '***')) + '6304';
    return payload + crc16(payload);
  }
  window.ninhoPix = pix; // For tests.

  // ---- Pictures for items without a photo, by category ----
  var icons = {
    quarto: 'M4 10h16v8H4zM4 10V6M20 10V6M8 10v8M12 10v8M16 10v8M3 18h18',
    passeio: 'M4 11h13a5 5 0 0 1-5 5H9a5 5 0 0 1-5-5zM4 11a7 7 0 0 1 7-7v7M17 11l1.6-5H21M8 18a1.5 1.5 0 1 0 0 3a1.5 1.5 0 1 0 0-3M14 18a1.5 1.5 0 1 0 0 3a1.5 1.5 0 1 0 0-3',
    banho: 'M4 12h16v2a5 5 0 0 1-5 5H9a5 5 0 0 1-5-5zM6 12V6a2 2 0 0 1 4 0M7 19l-1 2M17 19l1 2',
    alimentacao: 'M10 3h4M9.5 6h5l1 3v10a2 2 0 0 1-2 2h-3a2 2 0 0 1-2-2V9zM9 12h6',
    roupas: 'M8 4l4 2 4-2 4 4-3 3v9H7v-9L4 8z',
    presente: 'M4 9h16v4H4zM6 13h12v8H6zM12 9v12M12 9C9 9 7 4 10 4c2 0 2 5 2 5s0-5 2-5c3 0 1 5-2 5'
  };
  function iconFor(category) {
    var c = (category || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
    if (/quarto|berco|sono|move/.test(c)) return icons.quarto;
    if (/passeio|carrinho|carro|transporte/.test(c)) return icons.passeio;
    if (/banho|higiene/.test(c)) return icons.banho;
    if (/aliment|mamada|amament/.test(c)) return icons.alimentacao;
    if (/roupa|enxoval|vestu/.test(c)) return icons.roupas;
    return icons.presente;
  }
  function picture(item) {
    var box = el('div', 'pic');
    if (item.image_url && /^https:\/\//.test(item.image_url)) {
      var img = el('img');
      img.src = item.image_url;
      img.alt = '';
      img.loading = 'lazy';
      img.referrerPolicy = 'no-referrer';
      img.onerror = function () { box.replaceChildren(placeholder(item)); box.classList.add('empty'); };
      box.appendChild(img);
    } else {
      box.classList.add('empty');
      box.appendChild(placeholder(item));
    }
    return box;
  }
  function placeholder(item) {
    var ns = 'http://www.w3.org/2000/svg';
    var svg = document.createElementNS(ns, 'svg');
    svg.setAttribute('viewBox', '0 0 24 24');
    svg.setAttribute('aria-hidden', 'true');
    var path = document.createElementNS(ns, 'path');
    path.setAttribute('d', iconFor(item.category));
    svg.appendChild(path);
    return svg;
  }

  // ---- Items ----
  function given(item) { return Math.max(0, item.total_cents - item.needed_cents); }
  function render() {
    var grid = $('itens');
    grid.replaceChildren();
    if (!list.items.length) {
      grid.appendChild(el('p', 'empty-list', 'Todos os itens já foram presenteados. Obrigado por lembrar da família!'));
    }
    list.items.forEach(function (item, i) {
      var done = item.needed_cents <= 0;
      var card = el('article', 'item' + (done ? ' done' : '') + (cart[item.id] ? ' chosen' : ''));
      card.style.setProperty('--i', i);
      card.style.setProperty('--tilt', ((i % 3) - 1) * 1.6 + 'deg');
      card.appendChild(picture(item));
      var body = el('div', 'body');
      if (item.category) body.appendChild(el('span', 'cat', item.category));
      body.appendChild(el('h3', null, item.title + (item.quantity > 1 ? ' · ' + item.quantity + ' un.' : '')));
      if (list.show_prices) {
        body.appendChild(el('p', 'price', money(item.total_cents)));
      }
      if (given(item) > 0 || done) {
        var bar = el('div', 'bar');
        bar.setAttribute('role', 'img');
        var pct = Math.round(given(item) * 100 / item.total_cents);
        bar.setAttribute('aria-label', pct + '% presenteado');
        var fill = el('span');
        fill.style.width = pct + '%';
        bar.appendChild(fill);
        body.appendChild(bar);
        body.appendChild(el('p', 'left', done ? 'Já presenteado ♥' :
          list.show_prices ? 'Faltam ' + money(item.needed_cents) : pct + '% já presenteado'));
      }
      if (!done) body.appendChild(chooser(item));
      card.appendChild(body);
      grid.appendChild(card);
    });
    updateCart();
  }

  function chooser(item) {
    var box = el('div', 'choose');
    var chosen = cart[item.id];
    var main = el('button', 'btn ' + (chosen ? 'btn-chosen' : 'btn-primary'), chosen ? 'Escolhido · ' + money(chosen) : 'Presentear');
    main.type = 'button';
    main.setAttribute('aria-pressed', chosen ? 'true' : 'false');
    main.setAttribute('aria-label', (chosen ? 'Tirar ' : 'Presentear ') + item.title);
    main.onclick = function () {
      if (cart[item.id]) delete cart[item.id]; else cart[item.id] = item.needed_cents;
      render();
    };
    box.appendChild(main);
    if (chosen && list.allow_partial) {
      var parts = el('div', 'parts');
      parts.setAttribute('role', 'group');
      parts.setAttribute('aria-label', 'Quanto de ' + item.title);
      [[1, 'Tudo'], [0.5, 'Metade'], [0.25, 'Um quarto']].forEach(function (p) {
        var cents = Math.max(100, Math.round(item.needed_cents * p[0] / 100) * 100);
        if (p[0] < 1 && cents >= item.needed_cents) return;
        if (p[0] === 1) cents = item.needed_cents;
        var b = el('button', 'chip' + (chosen === cents ? ' on' : ''), p[1]);
        b.type = 'button';
        b.setAttribute('aria-pressed', chosen === cents ? 'true' : 'false');
        b.onclick = function () { cart[item.id] = cents; render(); };
        parts.appendChild(b);
      });
      var other = el('input', 'chip-input');
      other.inputMode = 'decimal';
      other.placeholder = 'Outro valor';
      other.setAttribute('aria-label', 'Outro valor para ' + item.title);
      other.onchange = function () {
        var v = parseMoney(other.value);
        if (v == null || v < 100 || v > item.needed_cents) {
          toast('Escolha um valor entre R$ 1,00 e ' + money(item.needed_cents) + '.');
          other.value = '';
          return;
        }
        cart[item.id] = v;
        render();
      };
      parts.appendChild(other);
      box.appendChild(parts);
    }
    return box;
  }

  function total() {
    return Object.keys(cart).reduce(function (s, k) { return s + cart[k]; }, 0) + free;
  }
  function updateCart() {
    var n = Object.keys(cart).length + (free ? 1 : 0);
    $('carrinho').hidden = n === 0;
    document.body.classList.toggle('has-cart', n > 0);
    $('carrinho-total').textContent = money(total());
    $('carrinho-itens').textContent = n === 1 ? '1 presente escolhido' : n + ' presentes escolhidos';
  }

  // ---- Paying ----
  function summary() {
    var ul = $('resumo');
    ul.replaceChildren();
    list.items.forEach(function (item) {
      if (!cart[item.id]) return;
      var li = el('li');
      li.appendChild(el('span', null, item.title));
      li.appendChild(el('b', null, money(cart[item.id])));
      ul.appendChild(li);
    });
    if (free) {
      var li = el('li');
      li.appendChild(el('span', null, 'Valor livre'));
      li.appendChild(el('b', null, money(free)));
      ul.appendChild(li);
    }
    var t = el('li', 'sum');
    t.appendChild(el('span', null, 'Total'));
    t.appendChild(el('b', null, money(total())));
    ul.appendChild(t);
  }
  function step(id) {
    ['passo-nome', 'passo-pix', 'passo-obrigado'].forEach(function (s) { $(s).hidden = s !== id; });
  }
  $('continuar').onclick = function () {
    summary();
    step('passo-nome');
    $('pagar').showModal();
  };
  $('nome-form').onsubmit = function (e) {
    e.preventDefault();
    if (!$('nome').value.trim()) return;
    pixCode = pix(list.pix_key, list.pix_name, list.pix_city, total());
    var qr = qrcode(0, 'M');
    qr.addData(pixCode);
    qr.make();
    $('qr').innerHTML = qr.createSvgTag({ cellSize: 6, margin: 2, scalable: true });
    $('valor-pix').textContent = money(total());
    $('recebedor').textContent = 'Para ' + list.pix_name;
    $('copia').value = pixCode;
    step('passo-pix');
  };
  $('copiar').onclick = function () {
    var done = function () { toast('Código copiado. Cole no app do banco, na opção Pix copia e cola.'); };
    if (navigator.clipboard) {
      navigator.clipboard.writeText(pixCode).then(done, function () { $('copia').select(); document.execCommand('copy'); done(); });
    } else { $('copia').select(); document.execCommand('copy'); done(); }
  };
  $('enviei').onclick = function () {
    var button = $('enviei');
    button.disabled = true;
    var body = {
      name: $('nome').value.trim(),
      message: $('mensagem').value.trim(),
      items: Object.keys(cart).map(function (k) { return { goal_id: k, amount_cents: cart[k] }; }),
      free_cents: free
    };
    var sent = example ? Promise.resolve() : fetch(api + '/v1/public/lists/' + encodeURIComponent(slug), {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body)
    }).then(function (r) {
      if (r.ok) return;
      return r.json().catch(function () { return {}; }).then(function (j) { throw new Error(j.error || 'Não deu para registrar agora. Tente de novo.'); });
    });
    sent.then(function () {
      list.items.forEach(function (item) {
        if (cart[item.id]) item.needed_cents = Math.max(0, item.needed_cents - cart[item.id]);
      });
      cart = {};
      free = 0;
      $('obrigado-titulo').textContent = 'Obrigado, ' + body.name.split(' ')[0] + '!';
      step('passo-obrigado');
      render();
    }, function (err) {
      toast(err.message);
    }).finally(function () { button.disabled = false; });
  };
  $('livre-form').onsubmit = function (e) {
    e.preventDefault();
    var v = parseMoney($('livre-valor').value);
    if (v == null || v < 100 || v > 5000000) { toast('Digite um valor a partir de R$ 1,00.'); return; }
    free = v;
    $('livre-valor').value = '';
    toast('Valor livre de ' + money(v) + ' adicionado.');
    updateCart();
  };

  var toastTimer;
  function toast(text) {
    var t = $('aviso');
    t.textContent = text;
    t.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { t.classList.remove('show'); }, 3600);
  }

  // ---- Loading ----
  function show(data) {
    list = data;
    var template = params.get('modelo') || data.template;
    var palette = params.get('cor') || data.palette;
    document.body.dataset.template = /^(cards|polaroid|lista|minimal)$/.test(template) ? template : 'cards';
    document.body.dataset.palette = /^(pessego|menta|ceu|lavanda|areia|rosa|oliva|mar)$/.test(palette) ? palette : 'pessego';
    document.title = data.title + ' · Lista de presentes';
    $('titulo').textContent = data.title;
    // Baby names the title does not already say, such as twins when the title names the parents.
    var missing = (data.babies || []).filter(function (n) { return data.title.indexOf(n) < 0; });
    if (missing.length) {
      $('bebes').textContent = 'Com amor para ' + (missing.length === 1 ? missing[0] :
        missing.slice(0, -1).join(', ') + ' e ' + missing[missing.length - 1]);
      $('bebes').hidden = false;
    }
    if (data.message) { $('recado').textContent = data.message; $('recado').hidden = false; }
    var left = daysUntil(data.event_date);
    if (left !== null && left >= 0) {
      $('contagem').textContent = left === 0 ? 'O chá de bebê é hoje!' :
        left === 1 ? 'Falta 1 dia para o chá de bebê' : 'Faltam ' + left + ' dias para o chá de bebê';
      $('contagem').hidden = false;
    }
    $('como').hidden = false;
    $('livre').hidden = false;
    document.body.classList.remove('loading');
    render();
  }
  // Whole days from today, in the guest's own calendar, to a YYYY-MM-DD date. Null without a date.
  function daysUntil(date) {
    var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(date || '');
    if (!m) return null;
    var now = new Date();
    var today = Date.UTC(now.getFullYear(), now.getMonth(), now.getDate());
    return Math.round((Date.UTC(+m[1], +m[2] - 1, +m[3]) - today) / 864e5);
  }
  function fail(text) {
    document.body.classList.remove('loading');
    $('titulo').textContent = 'Lista não encontrada';
    $('erro').textContent = text;
    $('erro').hidden = false;
  }
  if (example) {
    show(window.NINHO_EXAMPLE_LIST || exampleList());
  } else {
    fetch(api + '/v1/public/lists/' + encodeURIComponent(slug)).then(function (r) {
      if (r.status === 404) throw new Error('Confira o link com a família. Esta lista pode ter sido despublicada.');
      if (!r.ok) throw new Error('Não deu para carregar a lista agora. Tente de novo em instantes.');
      return r.json();
    }).then(show, function (e) { fail(e.message); });
  }

  function inDays(n) {
    var d = new Date(Date.now() + n * 864e5);
    return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
  }
  function exampleList() {
    return {
      title: 'Enxoval do papai Pedro e da mamãe Ana',
      message: 'A Maria e o João chegam em março e a gente está montando o cantinho deles com muito carinho. Qualquer ajuda, inteira ou um pedacinho, já deixa tudo mais leve. Obrigado por fazer parte!',
      template: 'cards', palette: 'pessego', event_date: inDays(45), show_prices: true, allow_partial: true,
      pix_key: 'ana.pedro@exemplo.com', pix_name: 'Ana Souza', pix_city: 'Recife',
      babies: ['Maria', 'João'],
      items: [
        { id: '1', title: 'Berço multifuncional com colchão', category: 'Quarto', quantity: 1, image_url: '', total_cents: 138990, needed_cents: 88990 },
        { id: '2', title: 'Carrinho de passeio compacto', category: 'Passeio', quantity: 1, image_url: '', total_cents: 174990, needed_cents: 174990 },
        { id: '3', title: 'Banheira com suporte', category: 'Banho', quantity: 1, image_url: '', total_cents: 15990, needed_cents: 0 },
        { id: '4', title: 'Bodies de algodão', category: 'Roupas', quantity: 12, image_url: '', total_cents: 35880, needed_cents: 23880 },
        { id: '5', title: 'Kit de mamadeiras', category: 'Alimentação', quantity: 2, image_url: '', total_cents: 18980, needed_cents: 18980 },
        { id: '6', title: 'Cadeirinha para o carro', category: 'Passeio', quantity: 1, image_url: '', total_cents: 89990, needed_cents: 89990 }
      ]
    };
  }
})();
