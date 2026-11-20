// Ninho site: header state, theme toggle shared with the app, and reveal on scroll.
(function () {
  var root = document.documentElement;
  root.classList.add('js');
  requestAnimationFrame(function () {
    requestAnimationFrame(function () { root.classList.add('loaded'); });
  });

  // Header gets a background once the page scrolls.
  var top = document.querySelector('[data-top]');
  function onScroll() { top.classList.toggle('scrolled', window.scrollY > 8); }
  onScroll();
  window.addEventListener('scroll', onScroll, { passive: true });

  // Theme. The app (shared_preferences on the web) keeps it under
  // flutter.ninho.theme as a JSON string, so both stay in sync.
  var media = window.matchMedia('(prefers-color-scheme: dark)');
  function current() {
    return root.dataset.theme || (media.matches ? 'dark' : 'light');
  }
  function paint() {
    var meta = document.querySelectorAll('meta[name="theme-color"]');
    var color = current() === 'dark' ? '#221e2d' : '#fff2ea';
    meta.forEach(function (m) { m.setAttribute('content', color); });
  }
  document.querySelector('[data-theme-toggle]').addEventListener('click', function () {
    var next = current() === 'dark' ? 'light' : 'dark';
    root.dataset.theme = next;
    try { localStorage.setItem('flutter.ninho.theme', JSON.stringify(next)); } catch (e) {}
    paint();
  });
  if (root.dataset.theme) paint();

  // Sections fade up as they enter; siblings in a grid come in one after another.
  var items = document.querySelectorAll('[data-reveal]');
  if (!('IntersectionObserver' in window)) {
    items.forEach(function (el) { el.classList.add('seen'); });
    return;
  }
  items.forEach(function (el) {
    var parent = el.parentElement;
    var siblings = parent ? parent.querySelectorAll(':scope > [data-reveal]') : [];
    var index = Array.prototype.indexOf.call(siblings, el);
    if (index > 0) el.style.setProperty('--d', Math.min(index, 5) * 0.08 + 's');
  });
  var io = new IntersectionObserver(function (entries) {
    entries.forEach(function (entry) {
      if (!entry.isIntersecting) return;
      entry.target.classList.add('seen');
      io.unobserve(entry.target);
    });
  }, { rootMargin: '0px 0px -10% 0px', threshold: 0.12 });
  items.forEach(function (el) { io.observe(el); });
})();
