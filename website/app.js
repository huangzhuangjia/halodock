(() => {
  const endpoint = 'https://api.github.com/repos/huangzhuangjia/halodock/releases/latest';
  const safeAsset = (asset) => {
    try {
      const url = new URL(asset.browser_download_url);
      return asset.name.endsWith('-macos-arm64.dmg') && url.protocol === 'https:' &&
        url.hostname === 'github.com' && url.pathname.startsWith('/huangzhuangjia/halodock/releases/download/');
    } catch { return false; }
  };
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 8000);
  fetch('./release.json', {cache: 'no-cache', signal: controller.signal})
    .then(response => response.ok ? response : fetch(endpoint, {headers: {'Accept': 'application/vnd.github+json'}, signal: controller.signal}))
    .then(response => { if (!response.ok) throw new Error('Release unavailable'); return response.json(); })
    .then(release => {
      if (release.draft || release.prerelease || typeof release.tag_name !== 'string') return;
      document.getElementById('release-version').textContent = release.tag_name;
      const asset = Array.isArray(release.assets) ? release.assets.find(safeAsset) : null;
      if (asset) document.querySelectorAll('.download-link').forEach(link => { link.href = asset.browser_download_url; });
    })
    .catch(() => { /* The visible Releases link remains usable when API requests fail. */ })
    .finally(() => clearTimeout(timeout));
})();

// Keep the frosted navigation readable when it overlaps the product content.
(() => {
  const navigation = document.querySelector('.nav-wrap');
  const syncNavigation = () => navigation.classList.toggle('is-scrolled', window.scrollY > 12);
  syncNavigation();
  window.addEventListener('scroll', syncNavigation, {passive:true});
})();

// Preview real light/dark screenshots without changing the visitor's system theme.
(() => {
  const stage = document.querySelector('.product-stage');
  const preview = stage.querySelector('.stage-app > img');
  const buttons = stage.querySelectorAll('[data-preview-theme]');
  buttons.forEach(button => button.addEventListener('click', () => {
    const dark = button.dataset.previewTheme === 'dark';
    preview.src = dark ? './assets/panel-dark.png' : './assets/panel.png';
    preview.alt = `HaloDock ${dark ? '深色' : '浅色'}实际界面：系统状态与快捷操作`;
    stage.classList.toggle('preview-dark', dark);
    buttons.forEach(item => item.setAttribute('aria-pressed', String(item === button)));
  }));
})();
