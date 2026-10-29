(() => {
  const reduced = window.matchMedia('(prefers-reduced-motion: reduce)');
  const track = document.querySelector('[data-story]');
  const staticMode = () => reduced.matches || innerHeight < 580;
  const pages = [...document.querySelectorAll('[data-story-page]')];
  const visuals = [...document.querySelectorAll('[data-story-visual]')];
  const controls = [...document.querySelectorAll('[data-story-jump]')];
  let current = -1;
  let scheduled = false;
  const select = index => {
    if (index === current) return;
    current = index;
    pages.forEach((node, i) => {
      node.classList.toggle('is-active', i === index);
      node.setAttribute('aria-hidden', String(!staticMode() && i !== index));
    });
    visuals.forEach((node, i) => {
      node.classList.toggle('is-active', i === index);
      node.inert = !staticMode() && i !== index;
      node.setAttribute('aria-hidden', String(!staticMode() && i !== index));
    });
    controls.forEach((node, i) => node.setAttribute('aria-pressed', String(i === index)));
  };
  const update = () => {
    scheduled = false;
    if (!track) return;
    document.documentElement.classList.toggle('story-ready', !staticMode());
    if (staticMode()) { current = -1; select(0); return; }
    const rect = track.getBoundingClientRect();
    const stickyTop = innerWidth <= 760 ? 66 : 74;
    const distance = Math.max(1, rect.height - (innerHeight - stickyTop));
    const progress = Math.min(0.9999, Math.max(0, (stickyTop - rect.top) / distance));
    select(Math.floor(progress * pages.length));
  };
  const schedule = () => {
    if (!scheduled) { scheduled = true; requestAnimationFrame(update); }
  };
  addEventListener('scroll', schedule, {passive:true});
  addEventListener('resize', schedule, {passive:true});
  reduced.addEventListener('change', () => { current = -1; schedule(); });
  const jumpTo = index => {
    if (!track || index < 0 || index >= pages.length) return;
    if (staticMode()) {
      pages[index].scrollIntoView({block:'start', behavior:'auto'});
      return;
    }
    const top = innerWidth <= 760 ? 66 : 74;
    const distance = Math.max(1, track.offsetHeight - (innerHeight - top));
    const destination = scrollY + track.getBoundingClientRect().top - top + distance * (index + 0.18) / pages.length;
    scrollTo({top:destination, behavior:reduced.matches ? 'auto' : 'smooth'});
  };
  controls.forEach((button, index) => button.addEventListener('click', () => jumpTo(index)));
  document.querySelectorAll('a[href="#dock-preview"]').forEach(link => link.addEventListener('click', event => {
    event.preventDefault();
    history.pushState(null, '', '#dock-preview');
    jumpTo(4);
  }));
  addEventListener('hashchange', () => { if (location.hash === '#dock-preview') jumpTo(4); });
  addEventListener('load', () => { if (location.hash === '#dock-preview') jumpTo(4); }, {once:true});
  document.documentElement.classList.toggle('story-ready', !staticMode());
  reduced.addEventListener('change', () => document.documentElement.classList.toggle('story-ready', !staticMode()));
  update();

  // Reveal only below-the-fold content. Text remains visible if JS is unavailable.
  if ('IntersectionObserver' in window && !reduced.matches) {
    document.documentElement.classList.add('motion-ready');
    const observer = new IntersectionObserver(entries => {
      entries.forEach(entry => {
        if (entry.isIntersecting) { entry.target.classList.add('is-visible'); observer.unobserve(entry.target); }
      });
    }, {threshold:0.08});
    document.querySelectorAll('[data-reveal]').forEach(node => observer.observe(node));
  }

  const dialog = document.getElementById('image-preview');
  const image = document.getElementById('preview-image');
  const title = document.getElementById('image-preview-title');
  const close = document.getElementById('preview-close');
  const size = document.getElementById('preview-size');
  let opener = null;
  const closePreview = () => dialog.close();
  document.querySelectorAll('[data-image-preview]').forEach(button => button.addEventListener('click', () => {
    const original = button.querySelector('img');
    if (!dialog || !original) return;
    opener = button;
    image.src = original.currentSrc || original.src;
    image.alt = original.alt;
    title.textContent = button.dataset.title || '界面预览';
    dialog.classList.remove('is-original');
    size.setAttribute('aria-pressed', 'false');
    size.textContent = '原始尺寸';
    document.body.classList.add('preview-open');
    dialog.showModal();
    close.focus();
  }));
  close.addEventListener('click', closePreview);
  dialog.addEventListener('click', event => { if (event.target === dialog) closePreview(); });
  dialog.addEventListener('close', () => {
    document.body.classList.remove('preview-open');
    image.removeAttribute('src');
    if (opener) opener.focus({preventScroll:true});
  });
  size.addEventListener('click', () => {
    const original = dialog.classList.toggle('is-original');
    size.setAttribute('aria-pressed', String(original));
    size.textContent = original ? '适应窗口' : '原始尺寸';
  });
})();
