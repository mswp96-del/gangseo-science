/* 강서중 과학수업 · 글쓰기 앱
   같은 화면이 두 가지 방식으로 동작합니다.

   1) 내 컴퓨터 모드 — 글쓰기.bat 으로 열었을 때.
      write-server.ps1 이 posts 폴더에 파일을 쓰고, [올리기]가 git push 까지 합니다.
   2) 인터넷 모드 — 블로그 주소(github.io)에서 열었을 때. 휴대폰도 됩니다.
      GitHub 토큰으로 글을 바로 저장합니다. 토큰은 이 기기 안에만 저장됩니다.
*/

(() => {
  'use strict';

  const $ = (sel) => document.querySelector(sel);
  const $$ = (sel) => Array.from(document.querySelectorAll(sel));

  const el = {
    badge: $('.mode-badge'),
    title: $('#f-title'),
    date: $('#f-date'),
    category: $('#f-category'),
    catList: $('#category-list'),
    tags: $('#f-tags'),
    summary: $('#f-summary'),
    body: $('#f-body'),
    uploads: $('.upload-list'),
    editingLabel: $('.editing-label'),
    draftState: $('.draft-state'),
    preview: $('.preview'),
    previewBody: $('.preview-body'),
    publishHint: $('.publish-hint'),
    manage: $('.post-manage'),
    listState: $('.list-state'),
    count: $('.post-count'),
    toast: $('.toast'),
    tokenModal: $('.token-modal'),
    tokenInput: $('.token-input'),
  };

  const state = {
    mode: 'unknown',      // 'local' | 'github'
    site: 'https://mswp96-del.github.io/gangseo-science/',
    editingFile: null,    // 수정 중인 글 파일 이름
    posts: [],
    busy: false,
  };

  /* ---------- 잔심부름 ---------- */

  const today = () => new Date().toISOString().slice(0, 10);

  function toast(message, isError) {
    el.toast.textContent = message;
    el.toast.classList.toggle('error', !!isError);
    el.toast.hidden = false;
    clearTimeout(toast.timer);
    toast.timer = setTimeout(() => { el.toast.hidden = true; }, isError ? 7000 : 3500);
  }

  function busy(on, label) {
    state.busy = on;
    $$('.actions .btn').forEach((b) => { b.disabled = on; });
    if (on && label) toast(label);
  }

  // 파일 이름에 쓸 수 없는 글자를 정리합니다. (한글은 그대로 둡니다)
  function slugify(text) {
    return (text || '무제')
      .trim()
      .replace(/[\\/:*?"<>|#%&{}$!'@+`=]/g, '')
      .replace(/\s+/g, '-')
      .replace(/-{2,}/g, '-')
      .replace(/^[-.]+|[-.]+$/g, '')
      .slice(0, 60) || '무제';
  }

  const utf8ToBase64 = (text) => {
    const bytes = new TextEncoder().encode(text);
    let bin = '';
    bytes.forEach((b) => { bin += String.fromCharCode(b); });
    return btoa(bin);
  };

  const fileToBase64 = (file) => new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result).split(',')[1]);
    reader.onerror = () => reject(new Error('파일을 읽지 못했습니다.'));
    reader.readAsDataURL(file);
  });

  /* ---------- 글 만들기 / 읽기 ---------- */

  function currentFileName() {
    const date = el.date.value || today();
    return `${date}-${slugify(el.title.value)}.md`;
  }

  function buildMarkdown() {
    const front = [
      '---',
      `title: ${el.title.value.trim()}`,
      `date: ${el.date.value || today()}`,
      `category: ${el.category.value.trim()}`,
      `tags: ${el.tags.value.trim()}`,
      `summary: ${el.summary.value.trim()}`,
      '---',
      '',
    ].join('\n');
    return front + el.body.value.replace(/\s*$/, '') + '\n';
  }

  function fillForm(post) {
    el.title.value = post.title || '';
    el.date.value = post.date || today();
    el.category.value = post.category || '';
    el.tags.value = (post.tags || []).join(', ');
    el.summary.value = post.summary || '';
    el.body.value = (post.body || '').replace(/^\n+/, '');
    el.uploads.innerHTML = '';
  }

  function newPost() {
    state.editingFile = null;
    fillForm({ date: today(), category: el.category.value });
    el.editingLabel.textContent = '새 글';
    el.title.focus();
    saveDraft();
  }

  /* ---------- 임시 저장 ---------- */

  const DRAFT_KEY = 'gangseo-write-draft';

  function saveDraft() {
    const draft = {
      editingFile: state.editingFile,
      title: el.title.value,
      date: el.date.value,
      category: el.category.value,
      tags: el.tags.value,
      summary: el.summary.value,
      body: el.body.value,
      at: Date.now(),
    };
    try { localStorage.setItem(DRAFT_KEY, JSON.stringify(draft)); } catch (e) { /* 용량 초과 무시 */ }
    const time = new Date().toLocaleTimeString('ko-KR', { hour: '2-digit', minute: '2-digit' });
    el.draftState.textContent = `임시저장 ${time}`;
  }

  function restoreDraft() {
    let draft;
    try { draft = JSON.parse(localStorage.getItem(DRAFT_KEY) || 'null'); } catch (e) { draft = null; }
    if (!draft || (!draft.title && !draft.body)) return false;
    state.editingFile = draft.editingFile || null;
    el.title.value = draft.title || '';
    el.date.value = draft.date || today();
    el.category.value = draft.category || '';
    el.tags.value = draft.tags || '';
    el.summary.value = draft.summary || '';
    el.body.value = draft.body || '';
    el.editingLabel.textContent = state.editingFile ? `수정 중 · ${state.editingFile}` : '쓰던 글 (임시저장)';
    el.draftState.textContent = '쓰던 글을 불러왔습니다';
    return true;
  }

  /* ---------- 저장소: 내 컴퓨터 모드 ---------- */

  async function localApi(path, payload) {
    const res = await fetch(`api/${path}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload || {}),
    });
    const data = await res.json().catch(() => ({ ok: false, error: '응답을 읽지 못했습니다.' }));
    if (!res.ok || !data.ok) throw new Error(data.error || `저장 실패 (${res.status})`);
    return data;
  }

  /* ---------- 저장소: 인터넷(GitHub) 모드 ---------- */

  const gh = {
    owner: (location.hostname.match(/^([^.]+)\.github\.io$/) || [, 'mswp96-del'])[1],
    repo: (location.pathname.split('/').filter((s) => s && !s.includes('.'))[0] || 'gangseo-science'),
    branch: 'main',

    get token() { return localStorage.getItem('gangseo-gh-token') || ''; },
    set token(v) {
      if (v) localStorage.setItem('gangseo-gh-token', v);
      else localStorage.removeItem('gangseo-gh-token');
    },

    async call(path, options = {}) {
      if (!gh.token) throw new Error('NO_TOKEN');
      const res = await fetch(`https://api.github.com/repos/${gh.owner}/${gh.repo}${path}`, {
        ...options,
        headers: {
          Accept: 'application/vnd.github+json',
          Authorization: `Bearer ${gh.token}`,
          'X-GitHub-Api-Version': '2022-11-28',
          ...(options.headers || {}),
        },
      });
      if (res.status === 401 || res.status === 403) throw new Error('열쇠(토큰)가 없거나 권한이 모자랍니다. 오른쪽 위 배지를 눌러 다시 등록해 주세요.');
      if (res.status === 404 && options.method !== 'GET' && options.method) throw new Error('저장소를 찾지 못했습니다. 토큰이 이 저장소에 접근할 수 있는지 확인해 주세요.');
      if (!res.ok && res.status !== 404) {
        const detail = await res.json().catch(() => ({}));
        throw new Error(detail.message || `GitHub 오류 (${res.status})`);
      }
      if (res.status === 404) return null;
      return res.status === 204 ? null : res.json();
    },

    async sha(path) {
      const info = await gh.call(`/contents/${encodeURI(path)}?ref=${gh.branch}`, { method: 'GET' });
      return info && info.sha ? info.sha : null;
    },

    async put(path, base64, message) {
      const sha = await gh.sha(path);
      return gh.call(`/contents/${encodeURI(path)}`, {
        method: 'PUT',
        body: JSON.stringify({ message, content: base64, branch: gh.branch, ...(sha ? { sha } : {}) }),
      });
    },

    async remove(path, message) {
      const sha = await gh.sha(path);
      if (!sha) return null;
      return gh.call(`/contents/${encodeURI(path)}`, {
        method: 'DELETE',
        body: JSON.stringify({ message, sha, branch: gh.branch }),
      });
    },

    // posts 폴더를 훑어 index.json 을 다시 만듭니다. (컴퓨터 모드에서는 update-index.ps1 이 하는 일)
    async refreshIndex() {
      const items = await gh.call(`/contents/posts?ref=${gh.branch}`, { method: 'GET' }) || [];
      const names = items
        .filter((f) => f.type === 'file' && f.name.endsWith('.md'))
        .map((f) => f.name)
        .sort()
        .reverse();
      const json = `[\n${names.map((n) => '  ' + JSON.stringify(n)).join(',\n')}\n]\n`;
      await gh.put('posts/index.json', utf8ToBase64(names.length ? json : '[]\n'), '목록 갱신');
      return names.length;
    },
  };

  /* ---------- 저장 · 삭제 · 올리기 ---------- */

  async function savePost({ publish }) {
    if (!el.title.value.trim()) { toast('제목을 적어 주세요.', true); el.title.focus(); return; }
    if (!el.body.value.trim()) { toast('본문이 비어 있습니다.', true); el.body.focus(); return; }

    const file = currentFileName();
    const oldFile = state.editingFile && state.editingFile !== file ? state.editingFile : null;
    const content = buildMarkdown();

    try {
      busy(true, '저장하는 중…');

      if (state.mode === 'local') {
        await localApi('save', { file, content, oldFile });
        if (publish) {
          const result = await localApi('publish', {});
          el.publishHint.innerHTML = result.changed
            ? `올렸습니다. 1분쯤 뒤 <a href="${state.site}" target="_blank" rel="noopener">블로그</a>에서 보입니다.`
            : '바뀐 내용이 없어 올릴 것이 없었습니다.';
          toast(result.changed ? '인터넷에 올렸습니다.' : '바뀐 내용이 없습니다.');
        } else {
          el.publishHint.innerHTML = `내 컴퓨터에 저장했습니다. <a href="index.html" target="_blank">미리보기</a> 로 확인하고, 다 되면 [인터넷에 올리기]를 누르세요.`;
          toast('저장했습니다. (아직 인터넷에는 안 올라갔습니다)');
        }
      } else {
        await gh.put(`posts/${file}`, utf8ToBase64(content), `글 저장: ${el.title.value.trim()}`);
        if (oldFile) await gh.remove(`posts/${oldFile}`, `이름 바뀐 글 정리: ${oldFile}`);
        await gh.refreshIndex();
        el.publishHint.innerHTML = `올렸습니다. 1분쯤 뒤 <a href="${state.site}" target="_blank" rel="noopener">블로그</a>에서 보입니다.`;
        toast('인터넷에 올렸습니다.');
      }

      state.editingFile = file;
      el.editingLabel.textContent = `수정 중 · ${file}`;
      saveDraft();
      loadPostList();
    } catch (err) {
      if (err.message === 'NO_TOKEN') openTokenModal();
      else toast(err.message, true);
    } finally {
      busy(false);
    }
  }

  async function deletePost(file, title) {
    if (!confirm(`「${title}」 글을 지울까요?\n\n지운 글은 되돌릴 수 없습니다.`)) return;
    try {
      busy(true, '지우는 중…');
      if (state.mode === 'local') {
        await localApi('delete', { file });
        await localApi('publish', {});
      } else {
        await gh.remove(`posts/${file}`, `글 삭제: ${title}`);
        await gh.refreshIndex();
      }
      if (state.editingFile === file) newPost();
      toast('글을 지웠습니다.');
      loadPostList();
    } catch (err) {
      if (err.message === 'NO_TOKEN') openTokenModal();
      else toast(err.message, true);
    } finally {
      busy(false);
    }
  }

  /* ---------- 사진 · 영상 넣기 ---------- */

  function assetFolder() {
    return `assets/post-${slugify(el.title.value || today())}`;
  }

  function insertAtCursor(text) {
    const ta = el.body;
    const start = ta.selectionStart ?? ta.value.length;
    const end = ta.selectionEnd ?? ta.value.length;
    const before = ta.value.slice(0, start);
    const after = ta.value.slice(end);
    const pad = (s, side) => (!s || /\n\n$/.test(s) || (side === 'after' && /^\n\n/.test(s)) ? '' : '\n');
    ta.value = before + pad(before) + text + '\n' + pad(after, 'after') + after;
    const pos = (before + pad(before) + text).length + 1;
    ta.focus();
    ta.setSelectionRange(pos, pos);
    saveDraft();
    renderPreview();
  }

  function chip(name, cls) {
    const span = document.createElement('span');
    span.className = `upload-chip ${cls || ''}`;
    span.textContent = name;
    el.uploads.appendChild(span);
    return span;
  }

  let uploadSeq = 0;

  async function uploadFiles(files) {
    const list = Array.from(files);
    if (!list.length) return;
    if (!el.title.value.trim()) { toast('사진을 넣기 전에 제목을 먼저 적어 주세요. (사진 폴더 이름에 씁니다)', true); return; }

    for (const file of list) {
      const isVideo = /^video\//.test(file.type) || /\.(mp4|webm|mov|m4v)$/i.test(file.name);
      const isImage = /^image\//.test(file.type) || /\.(jpg|jpeg|png|gif|webp|svg|avif)$/i.test(file.name);

      // 사진·영상만 받습니다. (문서를 끌어다 놓으면 깨진 그림이 되므로)
      if (!isVideo && !isImage) {
        chip(`${file.name} — 사진·영상이 아님`, 'error');
        toast(`${file.name} 은 사진도 영상도 아니라 넣지 않았습니다. 글 내용이라면 본문 칸에 붙여넣어 주세요.`, true);
        continue;
      }

      const limit = state.mode === 'local' ? 100 : 20;
      if (file.size > limit * 1024 * 1024) {
        chip(`${file.name} — ${limit}MB 넘어 건너뜀`, 'error');
        toast(`${file.name} 은 ${limit}MB가 넘어 올릴 수 없습니다. ${isVideo ? '유튜브에 올린 뒤 주소를 넣어 주세요.' : '사진 크기를 줄여 주세요.'}`, true);
        continue;
      }

      const ext = (file.name.match(/\.([a-z0-9]+)$/i) || [, 'jpg'])[1].toLowerCase();
      const name = `${isVideo ? 'video' : 'fig'}-${++uploadSeq}-${Date.now().toString(36).slice(-4)}.${ext}`;
      const folder = assetFolder();
      const path = `${folder}/${name}`;
      const mark = chip(`${file.name} 올리는 중…`, 'pending');

      try {
        const base64 = await fileToBase64(file);
        if (state.mode === 'local') {
          await localApi('upload', { folder, name, base64 });
        } else {
          await gh.put(path, base64, `${isVideo ? '영상' : '사진'} 추가: ${name}`);
        }
        mark.className = 'upload-chip';
        mark.textContent = `✓ ${file.name}`;
        insertAtCursor(isVideo ? path : `![${file.name.replace(/\.[^.]+$/, '')}](${path})`);
      } catch (err) {
        mark.className = 'upload-chip error';
        mark.textContent = `✗ ${file.name}`;
        toast(err.message === 'NO_TOKEN' ? '먼저 열쇠(토큰)를 등록해 주세요.' : err.message, true);
        if (err.message === 'NO_TOKEN') openTokenModal();
        return;
      }
    }
  }

  function pickFiles(accept, multiple) {
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = accept;
    input.multiple = !!multiple;
    input.addEventListener('change', () => uploadFiles(input.files));
    input.click();
  }

  // 영상 넣기 — 주소 붙여넣기 또는 파일 고르기
  function videoRow() {
    const old = $('.video-row');
    if (old) { old.remove(); return; }

    const row = document.createElement('div');
    row.className = 'video-row editor-toolbar';
    row.innerHTML = `
      <input class="video-url" type="url" placeholder="유튜브·드라이브 영상 주소를 붙여넣으세요"
        style="flex:1;min-width:12rem;padding:.35rem .6rem;border:1px solid var(--border);border-radius:7px;background:var(--bg);color:var(--text);font:inherit;font-size:.85rem">
      <button type="button" class="mini accent video-insert">넣기</button>
      <button type="button" class="mini video-file">영상 파일 고르기</button>`;
    $('.editor-toolbar').after(row);
    const input = row.querySelector('.video-url');
    input.focus();

    const insert = () => {
      const url = input.value.trim();
      if (!url) return;
      if (!videoEmbed(url)) { toast('유튜브·비메오·구글 드라이브 주소이거나 mp4 주소여야 합니다.', true); return; }
      insertAtCursor(url);
      row.remove();
      toast('영상을 넣었습니다. 미리보기로 확인해 보세요.');
    };
    row.querySelector('.video-insert').addEventListener('click', insert);
    input.addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); insert(); } });
    row.querySelector('.video-file').addEventListener('click', () => { row.remove(); pickFiles('video/*', false); });
  }

  /* ---------- 미리보기 ---------- */

  function renderPreview() {
    if (el.preview.hidden) return;
    el.previewBody.innerHTML = markdown(el.body.value || '_(본문이 비어 있습니다)_');
  }

  /* ---------- 올린 글 목록 ---------- */

  async function loadPostList() {
    try {
      const posts = await loadPosts();
      state.posts = posts;
      el.count.textContent = posts.length;

      const cats = Array.from(new Set(posts.map((p) => p.category).filter(Boolean)));
      el.catList.innerHTML = cats.map((c) => `<option value="${c}">`).join('');

      el.listState.hidden = true;
      el.manage.innerHTML = posts.map((p) => `
        <div class="manage-item" data-file="${encodeURIComponent(p.file)}">
          <div class="manage-main">
            <strong>${escapeHtml(p.title)}</strong>
            <span>${escapeHtml(p.date || '')} · ${escapeHtml(p.category || '분류 없음')}</span>
          </div>
          <button type="button" class="mini act-edit">고치기</button>
          <a class="mini" href="post.html?p=${encodeURIComponent(p.file)}" target="_blank">보기</a>
          <button type="button" class="mini danger act-delete">지우기</button>
        </div>`).join('') || '<p class="list-state">아직 올린 글이 없습니다.</p>';
    } catch (err) {
      el.listState.hidden = false;
      el.listState.textContent = `글 목록을 불러오지 못했습니다: ${err.message}`;
    }
  }

  function editPost(file) {
    const post = state.posts.find((p) => p.file === file);
    if (!post) return;
    state.editingFile = file;
    fillForm(post);
    el.editingLabel.textContent = `수정 중 · ${file}`;
    saveDraft();
    switchTab('edit');
    renderPreview();
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  /* ---------- 토큰 창 ---------- */

  function openTokenModal() {
    el.tokenModal.hidden = false;
    el.tokenInput.value = gh.token;
    el.tokenInput.focus();
  }

  /* ---------- 탭 ---------- */

  function switchTab(name) {
    $$('.write-tabs .tab').forEach((t) => t.classList.toggle('active', t.dataset.tab === name));
    $('.panel-edit').hidden = name !== 'edit';
    $('.panel-list').hidden = name !== 'list';
  }

  /* ---------- 시작 ---------- */

  async function detectMode() {
    try {
      const res = await fetch('api/mode', { cache: 'no-store' });
      const data = await res.json();
      if (data && data.mode === 'local') {
        state.mode = 'local';
        if (data.site) state.site = data.site;
        el.badge.textContent = '내 컴퓨터';
        el.badge.title = '글은 내 컴퓨터 posts 폴더에 저장되고, [인터넷에 올리기]를 눌러야 블로그에 반영됩니다.';
        return;
      }
    } catch (e) { /* 인터넷 모드 */ }

    state.mode = 'github';
    el.badge.textContent = gh.token ? '인터넷 (열쇠 등록됨)' : '인터넷 · 열쇠 필요';
    el.badge.classList.toggle('warn', !gh.token);
    el.badge.title = '누르면 GitHub 열쇠(토큰)를 등록·변경할 수 있습니다.';
    $('.save-only').hidden = true;
    $('.repo-name').textContent = `${gh.owner}/${gh.repo}`;
    $('.publish').textContent = '블로그에 올리기';
    if (!gh.token) openTokenModal();
  }

  function bind() {
    $('.year').textContent = new Date().getFullYear();

    $$('.write-tabs .tab').forEach((t) => t.addEventListener('click', () => switchTab(t.dataset.tab)));
    $('.new-post').addEventListener('click', () => { if (confirm('지금 쓰던 내용을 지우고 새 글을 시작할까요?')) newPost(); });
    $('.publish').addEventListener('click', () => savePost({ publish: true }));
    $('.save-only').addEventListener('click', () => savePost({ publish: false }));
    $('.add-photo').addEventListener('click', () => pickFiles('image/*', true));
    $('.add-video').addEventListener('click', videoRow);

    $('.preview-toggle').addEventListener('click', () => {
      el.preview.hidden = !el.preview.hidden;
      $('.preview-toggle').textContent = el.preview.hidden ? '미리보기' : '미리보기 닫기';
      renderPreview();
    });

    // 서식 버튼
    const wraps = {
      h: (s) => `## ${s || '소제목'}`,
      b: (s) => `**${s || '굵은 글씨'}**`,
      ul: (s) => (s || '항목').split('\n').map((l) => `- ${l}`).join('\n'),
      ol: (s) => (s || '항목').split('\n').map((l, i) => `${i + 1}. ${l}`).join('\n'),
      quote: (s) => `> ${s || '메모'}`,
      table: () => '| 구분 | 내용 |\n| --- | --- |\n|  |  |',
    };
    $$('[data-md]').forEach((btn) => btn.addEventListener('click', () => {
      const ta = el.body;
      const sel = ta.value.slice(ta.selectionStart, ta.selectionEnd);
      insertAtCursor(wraps[btn.dataset.md](sel));
    }));

    // 입력 → 임시저장 · 미리보기
    let timer;
    ['input', 'change'].forEach((evt) => {
      [el.title, el.date, el.category, el.tags, el.summary, el.body].forEach((input) => {
        input.addEventListener(evt, () => {
          clearTimeout(timer);
          timer = setTimeout(() => { saveDraft(); renderPreview(); }, 400);
        });
      });
    });

    // 끌어다 놓기
    el.body.addEventListener('dragover', (e) => { e.preventDefault(); el.body.classList.add('dragover'); });
    el.body.addEventListener('dragleave', () => el.body.classList.remove('dragover'));
    el.body.addEventListener('drop', (e) => {
      e.preventDefault();
      el.body.classList.remove('dragover');
      if (e.dataTransfer.files.length) uploadFiles(e.dataTransfer.files);
    });

    // 목록에서 고치기 · 지우기
    el.manage.addEventListener('click', (e) => {
      const item = e.target.closest('.manage-item');
      if (!item) return;
      const file = decodeURIComponent(item.dataset.file);
      if (e.target.closest('.act-edit')) editPost(file);
      if (e.target.closest('.act-delete')) deletePost(file, item.querySelector('strong').textContent);
    });

    // 토큰
    el.badge.addEventListener('click', () => { if (state.mode === 'github') openTokenModal(); });
    $('.token-save').addEventListener('click', () => {
      gh.token = el.tokenInput.value.trim();
      el.tokenModal.hidden = true;
      el.badge.textContent = gh.token ? '인터넷 (열쇠 등록됨)' : '인터넷 · 열쇠 필요';
      el.badge.classList.toggle('warn', !gh.token);
      toast(gh.token ? '열쇠를 저장했습니다. 이제 글을 올릴 수 있습니다.' : '열쇠를 지웠습니다.');
    });
    $('.token-cancel').addEventListener('click', () => { el.tokenModal.hidden = true; });
    $('.token-forget').addEventListener('click', () => {
      gh.token = '';
      el.tokenInput.value = '';
      el.badge.textContent = '인터넷 · 열쇠 필요';
      el.badge.classList.add('warn');
      toast('이 기기에서 열쇠를 지웠습니다.');
    });

    window.addEventListener('beforeunload', (e) => {
      if (!state.busy) return;
      e.preventDefault();
      e.returnValue = '';
    });
  }

  async function start() {
    bind();
    el.date.value = today();
    await detectMode();
    if (!restoreDraft()) newPost();
    loadPostList();
  }

  start();
})();
