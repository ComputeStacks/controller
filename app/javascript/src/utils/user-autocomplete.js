// Autocomplete for a user picker. Markup:
//
//   <div class="user-autocomplete" data-url="/admin/users/autocomplete" data-fixed='[{"id":"system","label":"System"}]'>
//     <input type="hidden" name="...">   <- submitted value (user id, or a fixed option's id)
//     <input type="text">                <- what the admin types; never submitted
//     <ul class="dropdown-menu"></ul>
//   </div>
//
// Typing clears the hidden value, so text that was never picked from the list filters on nothing.

function setupUserAutocomplete(root) {
  const hidden = root.querySelector('input[type=hidden]');
  const text = root.querySelector('input[type=text]');
  const menu = root.querySelector('.dropdown-menu');
  const fixed = JSON.parse(root.dataset.fixed || '[]');
  let items = [];
  let active = -1;
  let timer = null;
  let seq = 0;

  const isOpen = () => root.classList.contains('open');
  const close = () => { root.classList.remove('open'); active = -1; };

  function render(list, emptyText) {
    items = list;
    active = list.length ? 0 : -1;
    menu.replaceChildren();
    if (!list.length) {
      const li = document.createElement('li');
      li.className = 'disabled';
      const a = document.createElement('a');
      a.textContent = emptyText;
      li.appendChild(a);
      menu.appendChild(li);
    }
    list.forEach((item, i) => {
      const li = document.createElement('li');
      if (i === active) li.className = 'active';
      const a = document.createElement('a');
      a.href = '#';
      a.textContent = item.label;
      // mousedown, not click: it fires before the input's blur closes the menu.
      a.addEventListener('mousedown', (e) => { e.preventDefault(); pick(i); });
      li.appendChild(a);
      menu.appendChild(li);
    });
    root.classList.add('open');
  }

  function highlight(i) {
    active = i;
    menu.querySelectorAll('li').forEach((li, n) => li.classList.toggle('active', n === i));
  }

  function pick(i) {
    const item = items[i];
    if (!item) return;
    hidden.value = item.id;
    text.value = item.label;
    close();
  }

  function search() {
    const q = text.value.trim();
    const fixedMatches = fixed.filter((f) => f.label.toLowerCase().includes(q.toLowerCase()));
    if (q.length < 2 && !/^\d+$/.test(q)) {
      render(fixedMatches, 'Type at least 2 characters');
      return;
    }
    const mine = ++seq;
    fetch(`${root.dataset.url}?q=${encodeURIComponent(q)}`, { headers: { Accept: 'application/json' }, credentials: 'same-origin' })
      .then((r) => (r.ok ? r.json() : []))
      .then((users) => { if (mine === seq) render(fixedMatches.concat(users), 'No matches'); })
      .catch(() => { if (mine === seq) render(fixedMatches, 'Search failed'); });
  }

  text.addEventListener('input', () => {
    hidden.value = '';
    clearTimeout(timer);
    timer = setTimeout(search, 200);
  });
  text.addEventListener('focus', search);
  text.addEventListener('blur', () => {
    close();
    if (hidden.value === '') text.value = '';
  });
  text.addEventListener('keydown', (e) => {
    if (!isOpen()) return;
    if (e.key === 'ArrowDown') { e.preventDefault(); highlight(Math.min(active + 1, items.length - 1)); }
    else if (e.key === 'ArrowUp') { e.preventDefault(); highlight(Math.max(active - 1, 0)); }
    else if (e.key === 'Enter') { if (active >= 0) { e.preventDefault(); pick(active); } }
    else if (e.key === 'Escape') { close(); }
  });
}

window.addEventListener('load', () => {
  document.querySelectorAll('.user-autocomplete').forEach(setupUserAutocomplete);
});
