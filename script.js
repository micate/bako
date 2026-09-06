(() => {
  const menuButton = document.querySelector('.menu-button');
  const navLinks = document.querySelector('.nav-links');

  menuButton?.addEventListener('click', () => {
    const open = navLinks.classList.toggle('open');
    menuButton.setAttribute('aria-expanded', String(open));
  });

  navLinks?.addEventListener('click', (event) => {
    if (event.target.closest('a')) {
      navLinks.classList.remove('open');
      menuButton?.setAttribute('aria-expanded', 'false');
    }
  });

  document.querySelectorAll('[data-delay]').forEach((element) => {
    element.style.setProperty('--delay', `${element.dataset.delay}ms`);
  });

  const reveal = new IntersectionObserver((entries, observer) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) {
        entry.target.classList.add('visible');
        observer.unobserve(entry.target);
      }
    });
  }, { threshold: 0.12 });

  document.querySelectorAll('.reveal').forEach((element) => reveal.observe(element));

  // appcast.xml 与网站同源，由发布工作流持续更新。读取它可让下载按钮自动指向最新版。
  fetch('appcast.xml', { cache: 'no-cache' })
    .then((response) => {
      if (!response.ok) throw new Error('Appcast unavailable');
      return response.text();
    })
    .then((text) => {
      const xml = new DOMParser().parseFromString(text, 'application/xml');
      const item = xml.querySelector('item');
      const enclosure = item?.querySelector('enclosure');
      const version = item?.getElementsByTagNameNS('*', 'shortVersionString')[0]?.textContent
        || item?.querySelector('title')?.textContent;
      const downloadURL = enclosure?.getAttribute('url');

      if (version) {
        document.querySelectorAll('.version-label').forEach((label) => {
          label.textContent = `v${version.trim().replace(/^v/, '')}`;
        });
      }
      if (downloadURL) {
        document.querySelectorAll('.download-link').forEach((link) => {
          link.href = downloadURL;
        });
      }
    })
    .catch(() => {
      // HTML 中保留了可用的版本和下载地址，无网络或 XML 异常时仍可正常下载。
    });
})();
