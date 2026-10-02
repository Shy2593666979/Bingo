const assetRoot = '../../apps/mobile/assets/images/';
const roles = [
  {id:'girlfriend',name:'甜甜',type:'女朋友',description:'亲密、体贴的女性伴侣',image:'girlfriend.png',unread:2,traits:[['主动关心','heart'],['温柔体贴','leaf'],['甜蜜互动','heart']]},
  {id:'boyfriend',name:'暖暖',type:'男朋友',description:'亲密、可靠的男性伴侣',image:'boyfriend.png',unread:0,traits:[['安心陪伴','shield'],['耐心倾听','chat'],['鼓励支持','star']]},
  {id:'colleague',name:'小周',type:'同事',description:'可靠且有边界感的工作伙伴',image:'colleague.png',unread:3,traits:[['工作搭子','coffee'],['思路梳理','bulb'],['高效协作','shield']]},
  {id:'teacher',name:'小田老师',type:'老师',description:'耐心讲解并帮助用户成长',image:'teacher.png',unread:0,traits:[['耐心讲解','book'],['成长引导','sprout'],['答疑解惑','bulb']]},
  {id:'parent',name:'文清',type:'家长',description:'关心生活并提供稳重建议',image:'parent.png',unread:1,traits:[['生活关怀','coffee'],['暖心叮嘱','heart'],['沉稳可靠','shield']]},
  {id:'child',name:'星星',type:'小朋友',description:'自然活泼的孩子角色',image:'child.png',unread:0,traits:[['阳光开朗','star'],['有趣好聊','chat'],['一起成长','sprout']]}
];
const profile = {nickname:'小雨',gender:'不愿透露',birthday:'2000-01-01',avatar:assetRoot+'bingo_logo.png'};
const histories = new Map();
const screen = document.getElementById('screen');
const footer = document.getElementById('footer');
let route = {page:'login'};
let navigation = [];
let query = '';
let toastTimer;
const escapeHtml = value => String(value).replace(/[&<>"']/g, character => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[character]));
const icon = name => name === 'user'
  ? '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="7" r="4"/><path d="M4 22v-3a8 8 0 0 1 16 0v3"/></svg>'
  : `<svg aria-hidden="true"><use href="#${name}"/></svg>`;
const portrait = () => `<div class="user-picture"><img src="${escapeHtml(profile.avatar)}" alt="用户头像"></div>`;
function notify(message) {
  const toast = document.getElementById('toast');
  toast.textContent = message;
  toast.classList.add('visible');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => toast.classList.remove('visible'), 2200);
}
function navigate(page, roleId) {
  navigation.push(route);
  route = {page,roleId};
  render();
}
function back() {
  route = navigation.pop() || {page:'roles'};
  render();
}
function root(page) {
  navigation = [];
  route = {page};
  render();
}
function header(title, action = '') {
  return `<div class="flow-status">09:41 · Bingo</div><header class="page-header"><button class="back-button" data-action="back" aria-label="返回">‹ 返回</button><h2>${title}</h2>${action || '<span class="page-spacer"></span>'}</header>`;
}
function shell(title, content, action = '') {
  screen.innerHTML = `<div class="flow-page">${header(title,action)}${content}</div>`;
}
function rootFooter(active) {
  footer.innerHTML = `${active === 'roles' ? `<button class="create" data-action="create">${icon('plus')}创建角色</button>` : ''}<nav class="root-nav" aria-label="主导航"><button class="${active === 'roles' ? 'active' : ''}" data-action="roles">${icon('chat')}角色</button><button class="${active === 'me' ? 'active' : ''}" data-action="me">${icon('user')}我的</button></nav>`;
}
function traits(role) {
  return `<div class="traits">${role.traits.map(([label,symbol]) => `<span class="trait ${symbol}">${icon(symbol)}${escapeHtml(label)}</span>`).join('')}</div>`;
}
function roleCard(role) {
  return `<article class="card" tabindex="0" data-action="detail" data-role="${role.id}" aria-label="查看${escapeHtml(role.name)}详情"><div class="card-main"><img class="avatar" src="${assetRoot+role.image}" alt="${escapeHtml(role.name)}头像"><div class="card-info"><div class="card-heading"><h3>${escapeHtml(role.name)}</h3><div class="enter-wrap"><button class="enter" data-action="chat" data-role="${role.id}">${icon('chat')}进入</button>${role.unread ? `<span class="unread" aria-label="${role.unread}条演示未读">${role.unread}</span>` : ''}</div></div><p class="subtitle">${escapeHtml(role.type)} · ${escapeHtml(role.description)}</p></div></div>${traits(role)}</article>`;
}
function renderCards() {
  const filtered = roles.filter(role => [role.name,role.type,role.description,...role.traits.map(trait=>trait[0])].join(' ').includes(query.trim()));
  document.getElementById('cards').innerHTML = filtered.map(roleCard).join('') || '<p class="empty">没有匹配的角色</p>';
}
function messages(role) {
  if (!histories.has(role.id)) histories.set(role.id,[
    {mine:false,text:'今天过得怎么样？想聊天的时候，我就在这里。'},
    {mine:true,text:'今天有点累。'},
    {mine:false,text:'先休息一下吧，不用急着把所有事都做完。'}
  ]);
  return histories.get(role.id);
}
function bubbles(role, preview = false) {
  const entries = preview ? messages(role).slice(-4) : messages(role);
  return entries.map(message => `<div class="bubble-row ${message.mine && !preview ? 'mine' : ''}"><img src="${message.mine ? escapeHtml(profile.avatar) : assetRoot+role.image}" alt="${message.mine ? '用户' : escapeHtml(role.name)}头像"><div class="bubble">${escapeHtml(message.text)}</div></div>`).join('');
}
function menu(label, action, symbol, detail = '') {
  return `<button class="menu-row" data-action="${action}">${icon(symbol)}<span>${label}</span><small>${detail}</small><b>›</b></button>`;
}
function wheels() {
  const date = profile.birthday.split('-').map(Number);
  const now = new Date();
  const options = (first,last,current,suffix) => Array.from({length:last-first+1},(_,index)=>first+index).map(value=>`<option value="${value}" ${value===current?'selected':''}>${value}${suffix}</option>`).join('');
  return `<div class="date-wheel"><select name="year" size="5" aria-label="出生年份">${options(1900,now.getFullYear(),date[0],'年')}</select><select name="month" size="5" aria-label="出生月份">${options(1,12,date[1],'月')}</select><select name="day" size="5" aria-label="出生日期">${options(1,31,date[2],'日')}</select></div>`;
}
function render() {
  footer.className = 'bottom flow-footer';
  footer.innerHTML = '';
  footer.hidden = false;
  screen.scrollTop = 0;
  const role = roles.find(candidate => candidate.id === route.roleId);
  switch (route.page) {
    case 'login':
    case 'register': {
      const register = route.page === 'register';
      screen.innerHTML = `<div class="flow-page"><div class="flow-status">09:41 · Bingo</div><div class="welcome"><img src="${assetRoot}bingo_logo.png" alt="Bingo"><h1>${register ? '很高兴认识你' : '欢迎回来'}</h1><p>找一位懂你的伙伴<br>让每一次对话都有温度</p></div><form id="auth-form"><label class="field">手机号<input type="tel" autocomplete="off" placeholder="演示：13800000000" required></label><label class="field">密码<input type="password" autocomplete="off" placeholder="仅演示，不保存密码" required minlength="8"></label>${register ? '<label class="field">确认密码<input type="password" autocomplete="off" placeholder="再次输入演示密码" required minlength="8"></label>' : '<button class="link" type="button" data-action="recover">忘记密码？</button>'}<label class="legal"><input type="checkbox" required>我已阅读并同意 <a href="#" data-action="policy">用户协议</a> 和 <a href="#" data-action="policy">隐私政策</a></label><button class="primary">${register ? '注册并继续' : '登录'}</button></form><p class="nav-tip">${register ? '已有账号？' : '还没有账号？'}<button class="link" data-action="${register ? 'login' : 'register'}">${register ? '去登录' : '去注册'}</button></p><button class="secondary" data-action="demo">快速体验全部页面</button><p class="quiet">这是本地 HTML 原型，请勿填写真实账号或密码。</p></div>`;
      footer.hidden = true;
      break;
    }
    case 'profile':
    case 'onboarding': {
      const onboarding = route.page === 'onboarding';
      shell(onboarding ? '完善个人资料' : '个人资料', `<form id="profile-form">${portrait()}<label class="avatar-label">更换头像<input type="file" id="avatar-input" accept="image/*"></label><div class="panel"><label class="field">用户昵称<input name="nickname" value="${onboarding ? '' : escapeHtml(profile.nickname)}" maxlength="30" placeholder="希望我们怎么称呼你" required></label><label class="field">用户性别</label><div class="gender">${['男','女','不愿透露'].map(gender=>`<button type="button" class="${profile.gender===gender?'selected':''}" data-action="gender" data-gender="${gender}">${gender}</button>`).join('')}</div><label class="field">用户生日${wheels()}</label></div><p class="quiet">首次填写用户资料，不在这里设置助手名称、角色或性格。</p><button class="primary">${onboarding ? '完成，开始体验' : '保存资料'}</button></form>`);
      footer.hidden = true;
      break;
    }
    case 'roles':
      screen.innerHTML = `<div class="top"><div class="status"><span>09:41</span><div class="status-icons">${icon('wifi')}${icon('battery')}</div></div><header class="header"><div class="brand"><img src="${assetRoot}bingo_logo.png" alt="Bingo"></div><label class="search">${icon('search')}<input id="role-search" value="${escapeHtml(query)}" placeholder="搜索伙伴" aria-label="搜索伙伴"></label></header></div><div class="content"><div id="cards"></div></div>`;
      renderCards();
      rootFooter('roles');
      break;
    case 'detail':
      shell('角色详情', `<section class="panel"><div class="details-hero"><img src="${assetRoot+role.image}" alt="${role.name}"><div><h2>${role.name}</h2><p>${role.type}</p></div></div>${traits(role)}<p class="quiet">${escapeHtml(role.description)}</p></section><div class="panel stats"><div>角色类型<strong>${role.type}</strong></div><div>最近对话<strong>${messages(role).length} 条</strong></div></div><section class="panel"><h3 class="preview-title">最近对话</h3>${bubbles(role,true)}<p class="quiet">对话内容为原型演示。</p></section>`);
      footer.innerHTML = `<button class="create" data-action="chat" data-role="${role.id}">${icon('chat')}进入聊天</button>`;
      break;
    case 'chat':
      role.unread = 0;
      shell(role.name, `<div class="chat-day">今天 · 演示对话</div><div id="chat-messages">${bubbles(role)}</div>`, `<button class="page-action" data-action="detail" data-role="${role.id}">详情</button>`);
      footer.innerHTML = '<form class="composer" id="chat-form"><button type="button" data-action="voice" aria-label="语音输入">语音</button><input id="chat-input" placeholder="和 TA 说点什么…" maxlength="500" aria-label="聊天消息" required><button>发送</button></form><p class="chat-notice">原型回复，仅用于体验交互</p>';
      break;
    case 'me':
      screen.innerHTML = `<div class="flow-page"><div class="flow-status">09:41 · Bingo</div><header class="page-header"><span class="page-spacer"></span><h2>我的</h2><span class="page-spacer"></span></header><section class="me-hero">${portrait()}<h2>${escapeHtml(profile.nickname)}</h2><p>${profile.gender} · ${profile.birthday}</p><button class="link" data-action="profile">编辑个人资料 ›</button></section><div class="menu-group">${menu('个人资料','profile','user')}${menu('账号与安全','security','shield')}${menu('应用设置','settings','tune')}${menu('帮助与反馈','help','chat')}${menu('关于 Bingo','about','book','设计预览')}</div><p class="quiet">账号和应用设置统一放在「我的」，不出现在角色页面。</p></div>`;
      rootFooter('me');
      break;
    case 'settings':
      shell('应用设置', `<div class="menu-group"><label class="menu-row">${icon('chat')}<span>消息通知</span><input class="toggle" type="checkbox" checked aria-label="消息通知"></label><label class="menu-row">${icon('chat')}<span>来电提醒</span><input class="toggle" type="checkbox" checked aria-label="来电提醒"></label><label class="menu-row">${icon('book')}<span>通话字幕</span><input class="toggle" type="checkbox" checked aria-label="通话字幕"></label></div><div class="menu-group">${menu('隐私与协议','policy','shield')}${menu('清理缓存','cache','book','演示 12.6 MB')}${menu('连接状态','connection','sprout','原型演示')}</div><p class="quiet">开关仅改变本页面的演示状态，不修改手机系统静音、震动或其他系统设置。</p>`);
      break;
    case 'security':
      shell('账号与安全', `<div class="menu-group">${menu('修改密码','password','shield')}${menu('密码找回信息','recovery-info','book','已配置（演示）')}</div><button class="secondary" data-action="logout">退出登录</button><p class="quiet">所有账号状态都是虚构演示，不连接实际账号服务。</p>`);
      break;
    case 'recover':
    case 'password':
      shell(route.page==='recover'?'找回密码':'修改密码', `<form id="security-form"><div class="panel">${route.page==='recover'?'<label class="field">手机号<input placeholder="请输入演示手机号" required></label><label class="field">用户昵称<input placeholder="请输入演示昵称" required></label><label class="field">生日<input type="date" required></label><label class="field">恢复码<input placeholder="演示恢复码" required></label>':'<label class="field">当前密码<input type="password" placeholder="演示密码，不保存" required></label>'}<label class="field">新密码<input type="password" placeholder="仅做页面演示" minlength="8" required></label></div><button class="primary">确认（演示）</button><p class="quiet">不要输入真实密码，此页面不会提交到服务器。</p></form>`);
      break;
    case 'create':
      shell('创建新角色', `<form id="create-form"><div class="panel"><label class="field">角色昵称<input name="name" placeholder="为新伙伴取个名字" maxlength="30" required></label><label class="field">角色设定<textarea name="description" placeholder="TA 是怎样的伙伴？" maxlength="200" required></textarea></label><p class="quiet">默认头像使用 Bingo Logo。头像裁剪、录音复刻等细节可在后续设计中单独展开。</p></div><button class="primary">创建角色（演示）</button></form>`);
      break;
    default:
      shell('页面预览','<p class="quiet">返回继续体验其他页面。</p>');
  }
}
document.addEventListener('click', event => {
  const control = event.target.closest('[data-action]');
  if (!control) return;
  event.preventDefault();
  const action = control.dataset.action;
  if(action==='back')back();
  else if(action==='roles'||action==='me')root(action);
  else if(action==='demo')root('roles');
  else if(action==='gender'){
    profile.gender=control.dataset.gender;
    document.querySelectorAll('.gender button').forEach(button=>button.classList.toggle('selected',button.dataset.gender===profile.gender));
  } else if(action==='logout')root('login');
  else if(['help','about','policy','cache','connection','voice','recovery-info'].includes(action)){
    const notices={help:'帮助与反馈页面入口（演示）',about:'Bingo · 用户流程设计预览',policy:'用户协议 / 隐私政策文档入口（演示）',cache:'缓存清理仅演示，未删除任何文件',connection:'HTML 原型不连接后端',voice:'此处展示语音输入入口，不录音', 'recovery-info':'找回信息展示入口；不会显示真实恢复码'};
    notify(notices[action]);
  } else navigate(action,control.dataset.role);
});
document.addEventListener('keydown',event=>{
  const card=event.target.closest('article.card');
  if(card&&event.target===card&&(event.key==='Enter'||event.key===' ')){
    event.preventDefault();navigate('detail',card.dataset.role);
  }
});
document.addEventListener('input',event=>{
  if(event.target.id==='role-search'){query=event.target.value;renderCards();}
});
document.addEventListener('change',event=>{
  if(event.target.id==='avatar-input'){
    const file=event.target.files[0];
    if(!file)return;
    if(!file.type.startsWith('image/')||file.size>10*1024*1024){notify('请选择 10 MB 以下的图片');return;}
    if(profile.avatar.startsWith('blob:'))URL.revokeObjectURL(profile.avatar);
    profile.avatar=URL.createObjectURL(file);
    document.querySelector('.user-picture img').src=profile.avatar;
  }
});
document.addEventListener('submit',event=>{
  event.preventDefault();
  const form=event.target;
  if(form.id==='auth-form')navigate('onboarding');
  if(form.id==='profile-form'){
    const data=new FormData(form);
    const year=Number(data.get('year')),month=Number(data.get('month')),day=Number(data.get('day'));
    const date=new Date(year,month-1,day);
    if(date.getFullYear()!==year||date.getMonth()!==month-1||date.getDate()!==day||date>new Date()){
      notify('请选择有效生日');return;
    }
    const nickname=data.get('nickname').trim();
    if(!nickname){notify('请输入昵称');return;}
    profile.nickname=nickname;
    profile.birthday=`${year}-${String(month).padStart(2,'0')}-${String(day).padStart(2,'0')}`;
    if(route.page==='onboarding')root('roles');else back();
    notify('个人资料已更新（仅当前预览）');
  }
  if(form.id==='chat-form'){
    const input=document.getElementById('chat-input');
    const content=input.value.trim();
    if(!content)return;
    const role=roles.find(candidate=>candidate.id===route.roleId);
    messages(role).push({mine:true,text:content},{mine:false,text:'我在听。你可以慢慢说，我们一起把今天的心情理一理。（演示回复）'});
    document.getElementById('chat-messages').innerHTML=bubbles(role);
    input.value='';
    screen.scrollTop=screen.scrollHeight;
  }
  if(form.id==='security-form'){notify('验证流程仅演示，未修改密码');}
  if(form.id==='create-form'){
    const data=new FormData(form);
    const name=data.get('name').trim(),description=data.get('description').trim();
    if(!name||!description){notify('请输入昵称和设定');return;}
    roles.push({id:'custom-'+roles.length,name,type:'自定义角色',description,image:'bingo_logo.png',unread:0,traits:[['善于倾听','chat'],['温柔陪伴','heart']]});
    root('roles');notify('新角色已加入（仅当前预览）');
  }
});
render();
