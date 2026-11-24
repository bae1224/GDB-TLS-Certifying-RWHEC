(() => {
  const buttons = document.querySelectorAll('[data-language]');
  function setLanguage(language) {
    document.documentElement.lang = language;
    buttons.forEach(button => button.setAttribute('aria-pressed', String(button.dataset.language === language)));
    document.title = language === 'ko' ? 'RWHEC 해의 TLS 최적성 인증 · 인하대학교' : 'Grouped Deletion Bounds · RWHEC';
    try { localStorage.setItem('rwhec-language', language); } catch {}
  }
  let initial = 'ko';
  try { if (localStorage.getItem('rwhec-language') === 'en') initial = 'en'; } catch {}
  setLanguage(initial);
  buttons.forEach(button => button.addEventListener('click', () => setLanguage(button.dataset.language)));
})();
