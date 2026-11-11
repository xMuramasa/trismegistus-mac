/* ---------- 18: search (trismegistus-mac #76, hermes-relay #34) ---------- */
const SR_Q = 'android';
const SR_TITLE_HIT = {id:'androidapp', title:'Android app', time:'6 d', src:'app', preview:'Phone check list for the S21: pairing, chat, approvals', tags:[]};
// Real hits for "android" from Hermes' index (2026-11-11), newest first, one card per conversation.
const SR_HITS = [
  {title:'Workflow refiner', src:'app', time:'15:44', n:5, snip:'…plus Docker images for Swift, Gradle/JDK and the <mark>Android</mark> build. Not installed: Rust, Elixir, Deno, Java, or any C compiler…',
   more:['…2. trismegistus-mac and trismegistus-<mark>android</mark>: the protocol sync scripts and the contract-test path. 3. hermes-dispatch…']},
  {title:'Swift app', src:'app', time:'13:43', n:11, pinned:true, snip:'…trismegistus#28 (P1): push notifications to the <mark>Android</mark> app through ntfy. The <mark>Android</mark> app has its own items waiting for a check…',
   more:['…card titles are 800 weight in capitals (SWIFT APP, <mark>ANDROID</mark> APP), and the headings 900. That’s poster or comic lettering…']},
  {title:'linkedin larp', src:'app', time:'14:25', n:1, snip:'…cross-platform/dev breadth: Swift/Xcode on macOS, <mark>Android</mark>, self-hosted tooling across a Mac/Linux/<mark>Android</mark> setup…', more:[]},
  {title:'lab maintenance', src:'app', time:'Tue', n:1, snip:'…gradle and the two <mark>Android</mark> build images, because trismegistus-<mark>android</mark> and tablet-kiosk build with them…', more:[]},
  {title:'Trismegistus', src:'app', time:'Mon', n:5, snip:'…computer use, and an iOS/<mark>Android</mark> companion that pings you when an agent needs you and lets you reply from the phone…',
   more:['…dispatch profiles are missing for trismegistus-<mark>android</mark> and endfield-dotfiles, the board has no tab for tablet-kiosk…']},
  {title:'Android app', src:'app', time:'6 d', n:9, sel:true, snip:'…a hidden phone the size of your S21 FE, using the <mark>Android</mark> 37 image <mark>Android</mark> Studio had already installed. Your own emulators…',
   more:['…MEDIA:/home/muramasa/Projects/trismegistus-<mark>android</mark>/design/review-2026-11-05/compare-1.jpg…']},
  {title:'Endfield library', src:'app', time:'6 d', n:1, snip:'…or Phone (412×892). I added a phone size so the <mark>Android</mark> drafts can use it too. The numbers come straight from the app’s background code…', more:[]},
  {title:'Daily news', src:'cron', time:'7 d', n:2, snip:'…Google ships <mark>Android</mark> 17 QPR2 to Pixels; Samsung’s One UI 9 beta adds…', more:[]},
];
function srCard(h, sel) {
  return `<button class="row mc-row sr-card ${sel ? 'is-sel is-strong' : ''}" type="button">
    ${mcEmblem(h.src)}<span class="mc-div" aria-hidden="true"></span>
    <span class="mc-body">
      <span class="mc-title"><span class="t">${esc(h.title)}</span>${h.pinned ? `<span class="pin">${ic('pin')}</span>` : ''}</span>
      <span class="sr-snip">${h.snip}</span>
    </span>
    <span class="mc-side"><span class="mc-time num">${esc(h.time)}</span><span class="sr-n num">${h.n} ${h.n === 1 ? 'hit' : 'hits'}</span></span>
  </button>`;
}
function srGroup(h, sel) {
  const lines = [h.snip, ...h.more].slice(0, 2);
  return `<div class="sr-grp ${sel ? 'is-sel' : ''}">
    <div class="sr-gh">${mcEmblem(h.src)}<span class="t">${esc(h.title)}</span><span class="n num">${h.n}</span></div>
    ${lines.map((l, i) => `<button class="sr-line ${sel && i === 0 ? 'is-cur' : ''}" type="button"><span class="tm num">${i === 0 ? esc(h.time) : ''}</span><span class="s">${l}</span></button>`).join('')}
    ${h.n > lines.length ? `<button class="sr-more" type="button">${h.n - lines.length} more in this conversation</button>` : ''}
  </div>`;
}
const SR_HEAD = (n, extra = '') => `<div class="mg"><span class="ms" aria-hidden="true">${ic('search')}</span><span class="ml">In messages</span><span class="mn num">${n} conversations</span>${extra}</div>`;
function srList(win, mode, opts = {}) {
  const lc = win.querySelector('.lc-scroll'), input = win.querySelector('.lc-search input');
  input.value = opts.q != null ? opts.q : SR_Q;
  input.setAttribute('value', input.value);
  win.querySelector('.lc-search').classList.add('sr-on');
  const title = missionHead('Conversations', 1) + missionRow(SR_TITLE_HIT, null);
  let body = '';
  if (mode === 'cards') body = SR_HEAD(SR_HITS.length) + SR_HITS.map(h => srCard(h, h.sel && opts.sel)).join('');
  else body = SR_HEAD(SR_HITS.length) + SR_HITS.map(h => srGroup(h, h.sel && opts.sel)).join('');
  lc.innerHTML = title + body;
  const t = win.querySelector('.lc-title');
  if (t) t.innerHTML = `<span class="lbl3">// Search</span><span class="big">${SR_HITS.length + 1}</span>`;
}
const FINDBAR = (q, count, extra = '') => `<div class="fb" role="search">
  <label class="fld">${ic('search')}<input type="text" value="${esc(q)}" placeholder="Find in conversation" aria-label="Find in conversation">${q ? `<span class="x" aria-hidden="true">${ic('cross')}</span>` : ''}</label>
  <span class="cnt num ${count === 'No matches' ? 'none' : ''}">${count}</span>
  <button class="ib" type="button" aria-label="Previous match" data-tip="Previous  ⇧↩"><span class="flip">${ic('chev')}</span></button>
  <button class="ib" type="button" aria-label="Next match" data-tip="Next  ↩">${ic('chev')}</button>
  ${extra}<span class="fsp"></span><span class="hint"><kbd>esc</kbd>close</span>
</div>`;
function srDetail(win, opts = {}) {
  const dt = win.querySelector('.dt');
  const t1 = dt.querySelector('.dt-ttl .t1 .od-truncate'), t2 = dt.querySelector('.dt-ttl .t2');
  if (t1) t1.textContent = 'Android app';
  if (t2) t2.textContent = 'Trismegistus · 150 messages · last activity 6 d';
  const pin = dt.querySelector('.dt-ttl .t1 svg'); if (pin) pin.remove();
  dt.querySelector('.dt-rule').insertAdjacentHTML('afterend', FINDBAR(SR_Q, '3 of 9'));
  dt.querySelector('.dt-scroll .col').innerHTML = `
    <div class="who num">You // 5 Nov 18:02</div><div class="you">can you test the phone layout without my phone? i'm out</div>
    <div class="who num">Hermes // 5 Nov 18:09</div><div class="hermes"><p>Yes. I started a hidden emulator on optiplex and ran the build on it, so nothing on your side changed.</p></div>
    <div class="who num">You // 5 Nov 18:31</div><div class="you">which phone did you use?</div>
    <div class="who num">Hermes // 5 Nov 18:33</div><div class="hermes hit-msg"><p>A hidden phone the size of your S21 FE, using the <mark>Android</mark> 37 image <mark class="cur">Android</mark> Studio had already installed. Your own emulators are untouched.</p>
      <p>The chat, the approval sheet and the image picker all fit; the composer wraps at the same width as on your phone.</p></div>
    <div class="who num">You // 5 Nov 18:40</div><div class="you">nice, send me the screenshots</div>
    <div class="who num">Hermes // 5 Nov 18:41</div><div class="hermes"><p>Here they are, next to the drafts: MEDIA:/home/muramasa/Projects/trismegistus-<mark>android</mark>/design/review-2026-11-05/compare-1.jpg</p></div>`;
  dt.querySelector('.composer .col').innerHTML = `<div class="runline"><span>Idle</span><span class="tm">last run 6 d</span>
      <span class="hints"><span><kbd>↩</kbd>send</span><span class="x"><kbd>⌘K</kbd>conversations</span></span></div>
    <div class="inrow"><button class="ib ib-clip" type="button" aria-label="Attach">${ic('clip')}</button>
      <input type="text" placeholder="Message Hermes" aria-label="Message Hermes">
      <button class="btn btn-ink" type="button">Send ${ic('arrow')}</button></div>`;
  const sc = dt.querySelector('.dt-scroll'); sc.scrollTop = 0;
}
function searchView(win, v) {
  win.classList.add('mcw', 'srw');
  if (v === 's1') srList(win, 'cards');
  else if (v === 's2') srList(win, 'groups');
  else if (v === 's3') { srList(win, 'cards', {sel: true}); srDetail(win); }
  win.querySelectorAll('.lc .row.is-sel').forEach(r => { if (!r.classList.contains('sr-card')) r.classList.remove('is-sel'); });
}
function searchStates() {
  const win = document.createElement('div');
  win.className = 'win skin-a3 win-states mcw srw';
  win.style.setProperty('--w', '1000px');
  const card = (h, sel) => `<div class="sr-col">${srCard(h, sel)}</div>`;
  const cell = (cap, body) => `<div class="st-cell"><div class="cap">${cap}</div>${body}</div>`;
  win.innerHTML = `${contours(1000, 1122)}<div class="st-grid">
    <div class="st-left">
      ${cell('Searching · after 2 characters and a 300 ms pause; title matches show at once',
        `<label class="lc-search sr-on">${ic('search')}<input type="search" value="andr" autocomplete="off"><span class="spin" aria-hidden="true"></span></label>
         ${missionHead('Conversations', 1)}<div class="sr-col">${missionRow(SR_TITLE_HIT, null)}</div>
         ${SR_HEAD('…')}<div class="sr-note">Searching messages…</div>`)}
      ${cell('One character · titles only, as today',
        `<label class="lc-search">${ic('search')}<input type="search" value="a" autocomplete="off"><kbd>⌘K</kbd></label>
         <div class="sr-note">Type one more character to search inside messages.</div>`)}
      ${cell('No message says it',
        `${SR_HEAD('0')}<div class="sr-note">No message in any conversation says “zebra”.</div>`)}
      ${cell('Agents helper down · the titles still filter',
        `${SR_HEAD('—')}<div class="sr-note warn">Searching inside messages needs the agents helper on optiplex.<code>systemctl --user start trismegistus-agents</code></div>`)}
      ${cell('More than 50 hits · the newest 50; a narrower query finds older ones',
        `${card(SR_HITS[1])}<div class="sr-note">Showing the newest 50 matches. Add a word to narrow it.</div>`)}
    </div>
    <div class="st-right">
      ${cell('⌘F in the open conversation · empty', FINDBAR('', ''))}
      ${cell('Typing · every match in the loaded transcript, the current one solid', FINDBAR('emulator', '1 of 4'))}
      ${cell('No matches', FINDBAR('zebra', 'No matches'))}
      ${cell('Opened from a search hit older than the loaded messages', FINDBAR('android', 'Loading earlier messages…'))}
      ${cell('Marks in the transcript · others light, the current solid with an ink underline, its message with the yellow edge',
        `<div class="col sr-demo"><div class="who num">Hermes // 5 Nov 18:33</div><div class="hermes hit-msg"><p>A hidden phone the size of your S21 FE, using the <mark>Android</mark> 37 image <mark class="cur">Android</mark> Studio had already installed.</p></div>
         <div class="who num">You // 5 Nov 18:40</div><div class="you">does it run the <mark>android</mark> 36 image too?</div></div>`)}
    </div></div>`;
  return win;
}

