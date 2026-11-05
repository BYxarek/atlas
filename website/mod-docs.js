'use strict';
const russian = document.documentElement.lang === 'ru';
const searchBox = document.querySelector('.parameter-search');
const search = document.querySelector('#parameter-search');
const rows = [...document.querySelectorAll('[data-parameter]')];
const status = document.querySelector('#search-status');
if (searchBox && search && status) {
  searchBox.hidden = false;
  function filter() {
    const query = search.value.trim().toLocaleLowerCase();
    let count = 0;
    for (const row of rows) {
      row.hidden = !row.textContent.toLocaleLowerCase().includes(query);
      if (!row.hidden) count += 1;
    }
    status.textContent = russian ? `Показано ${count} из ${rows.length}` : `Showing ${count} of ${rows.length}`;
  }
  search.addEventListener('input', filter);
  function revealAnchor() {
    if (!location.hash.startsWith('#param-')) return;
    const target = document.getElementById(location.hash.slice(1));
    if (target && target.hidden) {
      search.value = '';
      filter();
      target.scrollIntoView();
    }
  }
  window.addEventListener('hashchange', revealAnchor);
  filter();
  revealAnchor();
}
for (const block of document.querySelectorAll('pre')) {
  if (!navigator.clipboard?.writeText) break;
  const code = block.querySelector('code');
  if (!code) continue;
  const button = document.createElement('button');
  button.type = 'button';
  button.className = 'copy-code';
  const label = russian ? 'Копировать' : 'Copy';
  button.textContent = label;
  button.addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(code.textContent);
      button.textContent = russian ? 'Скопировано' : 'Copied';
    } catch {
      button.textContent = russian ? 'Выделите и скопируйте текст' : 'Select and copy the text';
    }
    setTimeout(() => { button.textContent = label; }, 2000);
  });
  block.prepend(button);
}
