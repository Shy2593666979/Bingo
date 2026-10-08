const palettes = [
  { id: 'a', name: '雾感鼠尾草', mood: '柔和 · 延续品牌', note: '不再用浓绿撑起整页。灰绿只留给操作，伙伴卡片与聊天背景更轻。', recommendation: '最接近现有 Bingo，改动自然。' },
  { id: 'b', name: '晴空蓝', mood: '清爽 · 更轻盈', note: '用低饱和蓝替代绿色主色，保留暖一点的白。轻快，但不会像工具软件。', recommendation: '想明显改变现在的绿色，推荐这套。' },
  { id: 'c', name: '奶油杏', mood: '温暖 · 松弛感', note: '奶油底色、杏色气泡、柔棕按钮。强调亲近与安心，不靠鲜艳颜色营造温暖。', recommendation: '适合更偏日常陪伴的氛围。' },
  { id: 'd', name: '雾紫', mood: '安静 · 有个性', note: '很浅的紫灰背景，让角色头像更突出。主按钮压低饱和度，避免糖果色堆叠。', recommendation: '更年轻，也与其他陪伴应用拉开区别。' },
  { id: 'e', name: '纸白青灰', mood: '克制 · 更耐看', note: '让界面退后一步：纸白为主，青灰为辅。用层次、间距和线条替代大面积颜色。', recommendation: '最中性，长期看不容易腻。' }
];
const pages = [['space', '陪伴空间'], ['chat', '聊天'], ['my', '我的'], ['records', '陪伴记录'], ['editor', '创建伙伴'], ['login', '登录']];
const asset = name => `assets/ui-kit/${name}.png`;
const icon = name => `<svg class="icon" aria-hidden="true"><use href="#${name}"/></svg>`;
const status = '<div class="status"><span>9:41</span><svg viewBox="0 0 43 12" aria-hidden="true"><path d="M0 8h3v4H0zM5 5h3v7H5zM10 2h3v10h-3zM15 0h3v12h-3z"/><rect x="24" y="2" width="16" height="8" rx="2" fill="none" stroke="currentColor"/><rect x="26" y="4" width="12" height="4" rx="1"/><path d="M41 4h2v4h-2z"/></svg></div>';
const topbar = (name, back = 'space', right = '') => `<div class="topbar"><button class="icon-button" data-page="${back}" aria-label="返回">${icon('back')}</button><h2>${name}</h2>${right || '<span></span>'}</div>`;
const partners = [
  ['甜甜', 'girlfriend', '女朋友 · 关心生活，温柔陪伴', [['heart', '主动关心'], ['leaf', '温柔体贴'], ['chat', '陪伴聊天']], '3'],
  ['暖暖', 'boyfriend', '男朋友 · 亲密、可靠的男性伴侣', [['shield', '安心陪伴'], ['chat', '耐心倾听'], ['sun', '鼓励支持']], ''],
  ['小周', 'colleague', '同事 · 可靠且有边界感的工作伙伴', [['clock', '工作搭子'], ['sun', '思路梳理'], ['shield', '高效协作']], ''],
  ['小田老师', 'teacher', '老师 · 耐心讲解，陪你慢慢成长', [['records', '耐心讲解'], ['leaf', '成长引导'], ['sun', '答疑解惑']], '']
];
const traits = entries => `<div class="traits">${entries.map(([symbol, text]) => `<span class="trait">${icon(symbol)}${text}</span>`).join('')}</div>`;
function space() {
  return `<div class="content"><header class="space-head"><div><h2>陪伴空间</h2><p>在这里，慢慢聊~</p></div><button class="avatar-button" data-page="my" aria-label="打开我的"><img src="${asset('bingo_logo')}" alt="我的头像"></button></header>${partners.map(([name, avatar, desc, features, unread]) => `<article class="partner"><div class="partner-main"><img class="portrait" src="${asset(avatar)}" alt="${name}"><div class="partner-identity"><h3>${name}</h3><p class="desc">${desc}</p></div><button class="enter" data-page="chat" data-partner="${name}">${icon('chat')}进入</button></div>${traits(features)}${unread ? `<span class="unread" aria-label="${unread}条未读">${unread}</span>` : ''}</article>`).join('')}</div><div class="bottom-action"><button class="primary" data-page="editor">${icon('plus')}创建伙伴</button></div>`;
}
function chat(phone) {
  const name = phone.dataset.partner || '甜甜';
  const partner = partners.find(item => item[0] === name) || partners[0];
  const menu = [['photo', '相册'], ['photo', '相机'], ['chat', '电话'], ['pin', '位置'], ['clock', '一起专注'], ['heart', '小约定'], ['moon', '陪我入睡'], ['edit', '今日小记']];
  return `${topbar(name, 'space', `<button class="icon-button" data-speaker aria-pressed="false" aria-label="开启朗读">${icon('speaker')}</button>`)}<div class="content"><p class="time">今天 16:32</p><div class="message user"><div class="bubble">今天有点累，想找你聊聊。</div></div><div class="message"><img src="${asset(partner[1])}" alt="${name}"><div class="bubble">我在呢。</div></div><div class="message"><img src="${asset(partner[1])}" alt="${name}"><div class="bubble">先放松一下，不急着做什么。<br>今天最让你累的是哪件事？</div></div><div class="message user"><div class="bubble">工作好多，终于忙完啦。</div></div><div class="message"><img src="${asset(partner[1])}" alt="${name}"><div class="bubble">辛苦啦，今晚就慢一点吧。</div></div></div><div class="composer"><button class="icon-button" data-notice="录音样式预览，不会访问麦克风" aria-label="录音">${icon('mic')}</button><input aria-label="输入消息" placeholder="输入消息"><button class="icon-button" data-menu aria-expanded="true" aria-label="展开或收起菜单">${icon('plus')}</button></div><div class="menu">${menu.map(([symbol, text]) => `<button data-notice="${text}入口样式预览"><span>${icon(symbol)}</span>${text}</button>`).join('')}</div>`;
}
function my() {
  return `${topbar('我的')}<div class="content"><div class="profile"><img src="${asset('bingo_logo')}" alt="用户头像"><h3>小雨</h3><p>女 · 2000年6月18日</p></div><div class="group">${[
    ['user', '个人资料', '头像、昵称、性别和生日', 'data-notice="个人资料入口样式预览"'],
    ['records', '陪伴记录', '小记、约定、专注和入睡记录', 'data-page="records"'],
    ['gear', '应用设置', '账号安全、通话字幕和连接状态', 'data-notice="应用设置入口样式预览"']
  ].map(([symbol, title, subtitle, action]) => `<button class="setting-row" ${action}><span class="row-symbol">${icon(symbol)}</span><div><b>${title}</b><small>${subtitle}</small></div>${icon('next')}</button>`).join('')}</div></div>`;
}
function records() {
  return `${topbar('陪伴记录', 'my')}<div class="content"><div class="record-intro">${icon('records')}<div><b>一起度过的小小日常</b><p>把那些认真生活的瞬间，好好留下。</p></div></div><div class="local-tabs">${['小记', '约定', '专注', '入睡'].map((name, index) => `<button data-record="${name}" aria-pressed="${index === 0}">${name}</button>`).join('')}</div><div class="record-list">${recordCards('小记')}</div></div>`;
}
function recordCards(type) {
  const data = {
    '小记': ['edit', '还不错', '今天终于把积压的工作做完了。回家的路上吹了吹风，心情也轻了很多。', '和甜甜聊了聊，一整天的疲惫好像也没那么重了。'],
    '约定': ['heart', '早点休息', '今晚 22:30，放下手机，给自己留一点安静的时间。', '周末去公园走走，不着急，只是一起晒晒太阳。'],
    '专注': ['clock', '一起专注了 25 分钟', '完成了今天最重要的那件小事。', '一起读了 20 分钟的书，慢慢来，也很好。'],
    '入睡': ['moon', '听故事，慢慢入睡', '和甜甜一起听了 10 分钟的睡前故事。', '今天的故事在月光下收尾，好好休息。']
  }[type];
  return `<p class="section-label">今天 · 10月8日</p><article class="record-card"><header>${icon(data[0])}<b>${data[1]}</b><span>16:40</span></header><p>${data[2]}</p><footer><img src="${asset('girlfriend')}" alt="甜甜">和甜甜</footer></article><p class="section-label">昨天 · 10月7日</p><article class="record-card"><header>${icon(data[0])}<b>${type === '小记' ? '很开心' : data[1]}</b><span>20:12</span></header><p>${data[3]}</p><footer><img src="${asset('girlfriend')}" alt="甜甜">和甜甜</footer></article>`;
}
function editor() {
  return `${topbar('创建伙伴')}<div class="content editor"><div class="editor-head"><img src="${asset('bingo_logo')}" alt="默认伙伴头像"><button class="soft-button" data-notice="上传图片按钮配色预览">${icon('photo')}上传图片</button></div><div class="field"><label>伙伴昵称</label><div class="field-wrap"><input aria-label="伙伴昵称" placeholder="给伙伴起个名字"></div></div><div class="field"><label>伙伴角色</label><div class="field-wrap"><input aria-label="伙伴角色" placeholder="可以设定角色，也可以留空"></div></div><div class="field"><label>伙伴设定</label><textarea aria-label="伙伴设定" placeholder="写下你期待的相处方式"></textarea></div><p class="form-section">${icon('leaf')}陪伴特征</p>${traits([['heart', '安心陪伴'], ['chat', '耐心倾听'], ['sun', '积极温暖']])}<p class="form-section">${icon('speaker')}伙伴声音</p><div class="field-wrap"><img width="22" height="22" src="${asset('girlfriend')}" alt="甜甜音色"><select aria-label="伙伴声音"><option>甜甜</option><option>暖暖</option><option>小周</option><option>小田老师</option><option>文清</option><option>星星</option></select></div><button class="soft-button" data-notice="录制声音入口样式预览">${icon('mic')}录制我的声音</button></div><div class="bottom-action"><button class="primary" data-notice="创建按钮预览，不会保存伙伴">创建伙伴</button></div>`;
}
function login() {
  return `<div class="content"><div class="login-hero"><img src="${asset('bingo_logo')}" alt="Bingo"><h2>有个人，<br>陪你慢慢聊。</h2><p>欢迎回到 Bingo，你的陪伴空间。</p></div><div class="field"><label>手机号</label><div class="field-wrap">${icon('user')}<input type="tel" aria-label="手机号" placeholder="请输入手机号"></div></div><div class="field"><label>密码</label><div class="field-wrap">${icon('lock')}<input type="password" aria-label="密码" placeholder="请输入密码"></div></div><button class="forgot" data-notice="忘记密码入口样式预览">忘记密码？</button><button class="primary" data-page="space">登录</button><label class="agreement"><input type="checkbox" aria-label="同意协议"><span>我已阅读并同意 <button type="button" data-notice="用户协议预览">用户协议</button> 和 <button type="button" data-notice="隐私政策预览">隐私政策</button></span></label><p class="register">还没有账号？<button data-notice="注册使用同套主按钮与输入框配色">去注册</button></p></div>`;
}
const renderers = { space, chat, my, records, editor, login };
function render(phone, page) {
  phone.dataset.page = page;
  phone.innerHTML = `${status}<div class="screen">${renderers[page](phone)}</div><div class="homebar"></div>`;
}
document.querySelector('.page-tabs').innerHTML = pages.map(([id, label], index) => `<button data-global-page="${id}" aria-pressed="${index === 0}">${label}</button>`).join('');
document.querySelector('.variants').innerHTML = palettes.map(palette => `<article class="variant" data-theme="${palette.id}"><header class="variant-heading"><span class="letter">${palette.id.toUpperCase()}</span><b>${palette.name}</b><small>${palette.mood}</small></header><div class="swatches" aria-hidden="true"><span></span><span></span><span></span><span></span></div><div class="phone" aria-label="方案${palette.id.toUpperCase()}预览"></div><p class="description">${palette.note}<br><b>${palette.recommendation}</b></p></article>`).join('');
document.querySelectorAll('.phone').forEach(phone => render(phone, 'space'));
document.querySelector('#filter').addEventListener('change', event => {
  document.querySelectorAll('.variant').forEach(variant => { variant.hidden = event.target.value !== 'all' && event.target.value !== variant.dataset.theme; });
});
document.addEventListener('click', event => {
  const button = event.target.closest('button');
  if (!button) return;
  if (button.dataset.globalPage) {
    document.querySelectorAll('[data-global-page]').forEach(item => item.setAttribute('aria-pressed', String(item === button)));
    document.querySelectorAll('.phone').forEach(phone => render(phone, button.dataset.globalPage));
    return;
  }
  const phone = button.closest('.phone');
  if (!phone) return;
  if (button.dataset.page) {
    if (button.dataset.partner) phone.dataset.partner = button.dataset.partner;
    render(phone, button.dataset.page);
  } else if (button.hasAttribute('data-menu')) {
    const menu = phone.querySelector('.menu');
    menu.hidden = !menu.hidden;
    button.setAttribute('aria-expanded', String(!menu.hidden));
  } else if (button.dataset.record) {
    phone.querySelectorAll('[data-record]').forEach(item => item.setAttribute('aria-pressed', String(item === button)));
    phone.querySelector('.record-list').innerHTML = recordCards(button.dataset.record);
  } else if (button.hasAttribute('data-speaker')) {
    const enabled = button.getAttribute('aria-pressed') !== 'true';
    button.setAttribute('aria-pressed', String(enabled));
    button.setAttribute('aria-label', enabled ? '关闭朗读' : '开启朗读');
    notice(phone, enabled ? '自动朗读已开启（样式预览）' : '自动朗读已关闭');
  } else if (button.dataset.notice) notice(phone, button.dataset.notice);
});
const timers = new WeakMap();
function notice(phone, text) {
  clearTimeout(timers.get(phone));
  phone.querySelector('.notice')?.remove();
  const element = document.createElement('div');
  element.className = 'notice';
  element.setAttribute('role', 'status');
  element.textContent = text;
  phone.append(element);
  timers.set(phone, setTimeout(() => element.remove(), 2200));
}
