// 글이 들어 있는 폴더. 비공개 페이지는 이 값을 다른 폴더로 바꿔서 씁니다.
let POSTS_DIR = window.BLOG_DIR || 'posts/';

// 글을 새로 올렸을 때 방문자에게 옛 목록이 보이지 않도록,
// 서버에 바뀐 게 있는지 항상 확인하고 받아 옵니다. (바뀐 게 없으면 캐시를 그대로 씁니다)
const fetchFresh = (url) => fetch(url, { cache: 'no-cache' });

/* ---------- 테마 ---------- */

(function initTheme() {
  const saved = localStorage.getItem('theme');
  if (saved) document.documentElement.dataset.theme = saved;
  document.addEventListener('click', (e) => {
    if (!e.target.closest('.theme-toggle')) return;
    const dark = document.documentElement.dataset.theme === 'dark'
      || (!document.documentElement.dataset.theme && matchMedia('(prefers-color-scheme: dark)').matches);
    const next = dark ? 'light' : 'dark';
    document.documentElement.dataset.theme = next;
    localStorage.setItem('theme', next);
  });
})();

/* ---------- 마크다운 ---------- */

function escapeHtml(s) {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function inline(text) {
  const codes = [];
  let s = escapeHtml(text).replace(/`([^`]+)`/g, (m, c) => '@@CODE' + (codes.push(c) - 1) + '@@');
  // 주소 안에 괄호가 들어가는 경우(예: 파일이름(4))까지 받아 주려고 괄호 짝을 한 번 허용합니다.
  const url = '((?:[^()\\s]|\\([^()\\s]*\\))+)';
  s = s.replace(new RegExp('!\\[([^\\]]*)\\]\\(' + url + '\\)', 'g'), '<img src="$2" alt="$1" loading="lazy">');
  s = s.replace(new RegExp('\\[([^\\]]+)\\]\\(' + url + '\\)', 'g'), '<a href="$2">$1</a>');
  s = s.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
  s = s.replace(/\*([^*]+)\*/g, '<em>$1</em>');
  s = s.replace(/~~([^~]+)~~/g, '<del>$1</del>');
  s = s.replace(/ {2}$/gm, '<br>');
  return s.replace(/@@CODE(\d+)@@/g, (m, i) => '<code>' + codes[i] + '</code>');
}

/* 영상 넣기
   본문에 아래처럼 한 줄만 있으면 재생기로 바뀝니다.
     https://youtu.be/XXXXXXXX          (유튜브 주소 그대로)
     https://drive.google.com/file/d/...  (구글 드라이브 공유 링크)
     assets/영상.mp4                     (블로그 폴더에 넣은 영상 파일)
   앞에 ::video 를 붙여도 됩니다. */
function videoEmbed(line) {
  const raw = line.trim().replace(/^::video\s+/, '').replace(/^<(.+)>$/, '$1');
  if (/\s/.test(raw) || !raw) return '';

  const frame = (src, title) =>
    `<div class="video"><iframe src="${escapeHtml(src)}" title="${title}" loading="lazy" allowfullscreen
      allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"></iframe></div>`;

  let m = raw.match(/^https?:\/\/(?:www\.)?(?:youtube\.com\/(?:watch\?(?:.*&)?v=|embed\/|shorts\/|live\/)|youtu\.be\/)([\w-]{6,})/);
  if (m) return frame(`https://www.youtube.com/embed/${m[1]}?rel=0`, '유튜브 영상');

  m = raw.match(/^https?:\/\/(?:www\.)?vimeo\.com\/(\d+)/);
  if (m) return frame(`https://player.vimeo.com/video/${m[1]}`, '비메오 영상');

  m = raw.match(/^https?:\/\/drive\.google\.com\/file\/d\/([\w-]+)/);
  if (m) return frame(`https://drive.google.com/file/d/${m[1]}/preview`, '구글 드라이브 영상');

  if (/\.(mp4|webm|ogv|mov|m4v)(\?.*)?$/i.test(raw) && !/^https?:\/\/[^/]*youtube/.test(raw)) {
    return `<div class="video is-file"><video src="${escapeHtml(raw)}" controls preload="metadata" playsinline></video></div>`;
  }

  return '';
}

function markdown(src) {
  const lines = src.replace(/\r\n/g, '\n').split('\n');
  const out = [];
  let i = 0;

  const collect = (test) => {
    const buf = [];
    while (i < lines.length && test(lines[i])) buf.push(lines[i++]);
    return buf;
  };

  while (i < lines.length) {
    const line = lines[i];

    if (!line.trim()) { i++; continue; }

    if (/^```/.test(line)) {
      const lang = line.slice(3).trim();
      i++;
      const body = collect((l) => !/^```/.test(l));
      i++;
      out.push(`<pre><code${lang ? ` class="lang-${lang}"` : ''}>${escapeHtml(body.join('\n'))}</code></pre>`);
      continue;
    }

    const heading = line.match(/^(#{1,6})\s+(.*)$/);
    if (heading) {
      const level = heading[1].length;
      out.push(`<h${level}>${inline(heading[2])}</h${level}>`);
      i++;
      continue;
    }

    if (/^(-{3,}|\*{3,})\s*$/.test(line)) { out.push('<hr>'); i++; continue; }

    const video = videoEmbed(line);
    if (video) { out.push(video); i++; continue; }

    if (/^>\s?/.test(line)) {
      const body = collect((l) => /^>\s?/.test(l)).map((l) => l.replace(/^>\s?/, ''));
      out.push(`<blockquote>${markdown(body.join('\n'))}</blockquote>`);
      continue;
    }

    // 목록 항목 아래에 들여쓴 줄은 그 항목에 이어 붙입니다. (번호가 끊기지 않도록)
    const listItems = (marker) => collect((l) => marker.test(l) || /^\s{2,}\S/.test(l))
      .reduce((items, l) => {
        if (marker.test(l)) items.push(l.replace(marker, ''));
        else if (items.length) items[items.length - 1] += '\n' + l.trim();
        return items;
      }, [])
      .map((t) => `<li>${inline(t)}</li>`)
      .join('');

    if (/^\s*[-*+]\s+/.test(line)) {
      out.push(`<ul>${listItems(/^\s*[-*+]\s+/)}</ul>`);
      continue;
    }

    if (/^\s*\d+[.)]\s+/.test(line)) {
      out.push(`<ol>${listItems(/^\s*\d+[.)]\s+/)}</ol>`);
      continue;
    }

    if (/^\|.*\|\s*$/.test(line)) {
      const rows = collect((l) => /^\|.*\|\s*$/.test(l))
        .map((l) => l.trim().replace(/^\||\|$/g, '').split('|').map((c) => c.trim()));
      // 구분선은 --- 뿐 아니라 :-: :-- --: 같은 정렬 표시도 인식합니다.
      const alignRow = rows[1] && rows[1].every((c) => /^:?-+:?$/.test(c)) ? rows.splice(1, 1)[0] : null;
      const cell = (tag, cells) => `<tr>${cells.map((c, n) => {
        const a = alignRow && alignRow[n];
        const style = a && a.endsWith(':') ? (a.startsWith(':') ? ' style="text-align:center"' : ' style="text-align:right"') : '';
        return `<${tag}${style}>${inline(c)}</${tag}>`;
      }).join('')}</tr>`;
      const head = alignRow ? `<thead>${cell('th', rows.shift())}</thead>` : '';
      out.push(`<div class="table-scroll"><table>${head}<tbody>${rows.map((r) => cell('td', r)).join('')}</tbody></table></div>`);
      continue;
    }

    const para = collect((l) => l.trim() && !/^(```|#{1,6}\s|>|\||\s*[-*+]\s|\s*\d+[.)]\s|-{3,}\s*$)/.test(l) && !videoEmbed(l));
    out.push(`<p>${inline(para.join('\n'))}</p>`);
  }

  return out.join('\n');
}

/* ---------- 글 데이터 ---------- */

function parsePost(raw, file) {
  const meta = { file, title: file.replace(/\.md$/, ''), date: '', category: '', tags: [], summary: '' };
  let body = raw.replace(/^﻿/, '');

  const fm = body.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n?/);
  if (fm) {
    body = body.slice(fm[0].length);
    for (const line of fm[1].split(/\r?\n/)) {
      const kv = line.match(/^(\w+)\s*:\s*(.*)$/);
      if (!kv) continue;
      const [, key, value] = kv;
      if (key === 'tags') meta.tags = value.split(',').map((t) => t.trim()).filter(Boolean);
      else if (key in meta) meta[key] = value.trim();
    }
  }

  meta.body = body;
  if (!meta.summary) {
    const first = body.split(/\n\s*\n/).find((b) => b.trim() && !/^[#>`|-]/.test(b.trim())) || '';
    meta.summary = first.replace(/[*`\[\]]/g, '').trim().slice(0, 120);
  }
  return meta;
}

async function loadPosts() {
  const files = await fetchFresh(`${POSTS_DIR}index.json`).then((r) => {
    if (!r.ok) throw new Error(`posts/index.json (${r.status})`);
    return r.json();
  });
  const posts = await Promise.all(files.map(async (file) => {
    const raw = await fetchFresh(POSTS_DIR + file).then((r) => {
      if (!r.ok) throw new Error(`${file} (${r.status})`);
      return r.text();
    });
    return parsePost(raw, file);
  }));
  return posts.sort((a, b) => (b.date || '').localeCompare(a.date || ''));
}

function formatDate(value) {
  if (!value) return '';
  const d = new Date(value);
  return isNaN(d) ? value : `${d.getFullYear()}년 ${d.getMonth() + 1}월 ${d.getDate()}일`;
}

function fail(container, err) {
  container.innerHTML = `<p class="state error">글을 불러오지 못했습니다.<br><small>${escapeHtml(err.message)}</small><br>
    <small>HTML 파일을 더블클릭해서 열면 브라우저 보안 정책 때문에 실패합니다. <code>serve.ps1</code>로 실행해 보세요.</small></p>`;
}

/* ---------- 목록 페이지 ---------- */

async function renderIndex() {
  const yearEl = document.querySelector('.year');
  if (yearEl) yearEl.textContent = new Date().getFullYear();
  const list = document.querySelector('.post-list');
  const search = document.querySelector('.search');
  const catBox = document.querySelector('.categories');

  let posts;
  try {
    posts = await loadPosts();
  } catch (err) {
    fail(list, err);
    return;
  }

  let activeCategory = '전체';

  const categories = ['전체', ...new Set(posts.map((p) => p.category).filter(Boolean))];
  catBox.innerHTML = categories
    .map((c) => `<button type="button" class="chip${c === '전체' ? ' active' : ''}" data-cat="${escapeHtml(c)}">${escapeHtml(c)}</button>`)
    .join('');

  function draw() {
    const q = search.value.trim().toLowerCase();
    const shown = posts.filter((p) => {
      if (activeCategory !== '전체' && p.category !== activeCategory) return false;
      if (!q) return true;
      return [p.title, p.summary, p.category, p.tags.join(' '), p.body].join(' ').toLowerCase().includes(q);
    });

    if (!shown.length) {
      list.innerHTML = '<p class="state">조건에 맞는 글이 없습니다.</p>';
      return;
    }

    // 비공개 페이지에서는 글 주소에도 폴더를 붙여, 본문도 같은 폴더에서 읽게 합니다.
    const dirParam = window.BLOG_DIR ? `&dir=${encodeURIComponent(window.BLOG_DIR)}` : '';

    list.innerHTML = shown.map((p) => `
      <article class="card">
        <a class="card-link" href="post.html?p=${encodeURIComponent(p.file)}${dirParam}">
          <div class="card-meta">
            ${p.category ? `<span class="tag cat">${escapeHtml(p.category)}</span>` : ''}
            <time>${formatDate(p.date)}</time>
          </div>
          <h2>${escapeHtml(p.title)}</h2>
          <p class="excerpt">${escapeHtml(p.summary)}</p>
          ${p.tags.length ? `<div class="tags">${p.tags.map((t) => `<span class="tag">#${escapeHtml(t)}</span>`).join('')}</div>` : ''}
        </a>
      </article>`).join('');
  }

  search.addEventListener('input', draw);
  catBox.addEventListener('click', (e) => {
    const chip = e.target.closest('.chip');
    if (!chip) return;
    activeCategory = chip.dataset.cat;
    catBox.querySelectorAll('.chip').forEach((c) => c.classList.toggle('active', c === chip));
    draw();
  });

  draw();
}

/* ---------- 본문 페이지 ---------- */

async function renderPost() {
  const yearEl = document.querySelector('.year');
  if (yearEl) yearEl.textContent = new Date().getFullYear();
  const article = document.querySelector('.post');
  const params = new URLSearchParams(location.search);
  const file = params.get('p');

  // 비공개 글이면 그 폴더에서 읽습니다.
  if (params.get('dir')) POSTS_DIR = params.get('dir');

  if (!file) {
    article.innerHTML = '<p class="state">주소에 글 정보가 없습니다.</p>';
    return;
  }

  try {
    const raw = await fetchFresh(POSTS_DIR + file).then((r) => {
      if (!r.ok) throw new Error(`${file} (${r.status})`);
      return r.text();
    });
    const post = parsePost(raw, file);
    document.title = `${post.title} · 강서중 과학수업`;
    article.innerHTML = `
      <header class="post-head">
        <div class="card-meta">
          ${post.category ? `<span class="tag cat">${escapeHtml(post.category)}</span>` : ''}
          <time>${formatDate(post.date)}</time>
        </div>
        <h1>${escapeHtml(post.title)}</h1>
        ${post.tags.length ? `<div class="tags">${post.tags.map((t) => `<span class="tag">#${escapeHtml(t)}</span>`).join('')}</div>` : ''}
      </header>
      <div class="post-body">${markdown(post.body)}</div>`;
  } catch (err) {
    fail(article, err);
  }
}
