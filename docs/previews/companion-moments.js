const icons = name => `<svg class="icon" aria-hidden="true"><use href="#${name}"/></svg>`;
const definitions = {
  menu: { title: '陪你做点小事', subtitle: '聊天之外，也有一些小小的陪伴。', message: '想做点什么？我陪你一起。' },
  focus: { title: '一起专注', subtitle: '把这一小段时间，留给眼前的事。', message: '你安心做自己的事，我在这里等你。' },
  promise: { title: '小约定', subtitle: '一些小事，有人惦记就不一样。', message: '说好的小事，我会记得。' },
  sleep: { title: '陪我入睡', subtitle: '今天辛苦啦，慢慢放松下来。', message: '不用急着睡着，我会轻声陪着你。' },
  diary: { title: '今日小记', subtitle: '不用写很多，一件小事也值得被记住。', message: '今天有什么想留住的小瞬间？' },
};
const states = Object.fromEntries(['a','b','c'].map(variant => [variant, {
  feature: 'focus', minutes: 25, seconds: 1500, running: false, activity: '学习',
  sleepMode: '睡前故事', sleepTime: 20, mood: '还不错', diary: '', title: '',
}]));
let selectedFeature = 'focus';
const today = new Intl.DateTimeFormat('zh-CN', { month: 'long', day: 'numeric', weekday: 'long' }).format(new Date());
function tomorrowTime() {
  const date = new Date();
  date.setDate(date.getDate() + 1);
  date.setHours(21,0,0,0);
  const pad = number => String(number).padStart(2,'0');
  return `${date.getFullYear()}-${pad(date.getMonth()+1)}-${pad(date.getDate())}T21:00`;
}
function formatTime(seconds) {
  return `${String(Math.floor(seconds/60)).padStart(2,'0')}:${String(seconds%60).padStart(2,'0')}`;
}
function chips(values, selected, group, format = value => value) {
  return `<div class="chips">${values.map(value => `<button class="chip" data-group="${group}" data-value="${value}" aria-pressed="${selected === value}">${format(value)}</button>`).join('')}</div>`;
}
function hero(feature) {
  const message = {focus:'我不打扰你，结束了记得来找我。',promise:'不是任务清单，是我们的小约定。',sleep:'今晚让我陪着你，把心放轻一点。',diary:'想分享的、想吐槽的，都可以说给我听。'}[feature];
  return `<div class="hero"><img class="avatar" src="assets/ui-kit/girlfriend.png" alt="甜甜"><div><p>${message}</p><small>甜甜 · 按伙伴性格陪伴</small></div></div>`;
}
function content(variant) {
  const state = states[variant];
  switch (state.feature) {
    case 'menu': {
      const items = [['photo','相册'],['camera','相机'],['call','电话'],['point','位置'],['focus','一起专注'],['promise','小约定'],['sleep','陪我入睡'],['diary','今日小记']];
      return `<div class="menu-grid">${items.map(([icon,label],index) => `${index === 4 ? '<div class="menu-separator"></div>' : ''}<button class="menu-item ${index >= 4 ? 'new' : ''}" data-open="${icon}" aria-label="${label}"><span class="tile">${icons(icon)}</span>${label}</button>`).join('')}</div><div class="promise-note">新功能放在第二行，原来的四个入口不变。<br>选择一件小事，让甜甜陪你一起。</div>`;
    }
    case 'focus':
      return `${hero('focus')}<div class="chips" aria-label="专注场景">${['学习','工作','阅读'].map(value => `<button class="chip" data-group="activity" data-value="${value}" aria-pressed="${state.activity === value}">${value}</button>`).join('')}</div><div class="timer ${state.running ? 'running' : ''}"><strong data-timer>${formatTime(state.seconds)}</strong><span data-timer-label>${state.running ? '甜甜正在安静陪你' : '留一点时间，给自己'}</span></div>${chips([25,45,60],state.minutes,'minutes',value => `${value} 分钟`)}<div class="field-label">陪伴方式</div><div class="focus-settings"><div class="setting">${icons('leaf')}<div><b>安静陪伴</b><small>期间不主动打扰</small></div></div><div class="setting">${icons('heart')}<div><b>结束鼓励</b><small>按伙伴性格回应</small></div></div></div><button class="primary" data-action="focus">${icons(state.running ? 'pause' : 'play')}<span>${state.running ? '暂停一下' : state.seconds !== state.minutes*60 ? '继续专注' : '开始一起专注'}</span></button><button class="secondary" data-action="reset">重新开始计时</button>`;
    case 'promise':
      return `${hero('promise')}<label class="field-label" for="promise-${variant}">我们约好做什么</label><input class="text-input" id="promise-${variant}" data-input="title" maxlength="60" placeholder="例如：明晚一起散步十分钟"><div class="field-label">也可以从一件小事开始</div>${chips(['早点休息','出门走走','读几页书'],'','promise-title')}<label class="field-label" for="date-${variant}">什么时候提醒我</label><input class="text-input" id="date-${variant}" type="datetime-local" value="${state.date || tomorrowTime()}" data-input="date"><label class="line-option" for="care-${variant}"><span>之后再关心一下<small>　问问完成得怎么样</small></span><input id="care-${variant}" type="checkbox" checked></label><div class="promise-note">到时间，由甜甜用自己的方式提醒你。<br>这里仅预览，不创建实际提醒。</div><button class="primary" data-action="promise">${icons('promise')}和甜甜约好了</button>`;
    case 'sleep':
      return `${hero('sleep')}<div class="sleep-orbit">${icons('sleep')}</div><div class="field-label">今晚想怎样被陪伴</div>${chips(['睡前故事','轻声聊天','安静陪着'],state.sleepMode,'sleepMode')}<div class="sound-row"><span class="sound-name">${icons('voice')}甜甜的声音</span><small>使用当前伙伴音色</small></div><div class="field-label">多久后自动停止</div>${chips([10,20,30],state.sleepTime,'sleepTime',value => `${value} 分钟`)}<button class="primary" data-action="sleep">${icons('sleep')}陪我慢慢入睡</button><p class="fine">演示不播放声音。实际功能可手动结束，或定时停止。</p>`;
    case 'diary':
      return `<div class="journal-date">${icons('diary')}<div><b>${today}</b><small>把今天的一小片，留在这里</small></div></div><div class="field-label">此刻的心情</div>${chips(['很开心','还不错','有点累','想被抱抱'],state.mood,'mood')}<label class="field-label" for="diary-${variant}">今天想记住的一件事</label><textarea id="diary-${variant}" data-input="diary" maxlength="1000" placeholder="今天喝到了一杯很好喝的咖啡。\n或者，今天有点累，但我还是认真过完了。"></textarea><div class="hero" style="margin:15px 0 0"><img class="avatar" src="assets/ui-kit/girlfriend.png" alt="甜甜"><div><p>不用写得好，真实就很好。</p><small>甜甜会认真听，也会回应你</small></div></div><button class="primary" data-action="diary">${icons('diary')}记下来，分享给甜甜</button><p class="fine">仅在预览页展示示例，不会保存或发送。</p>`;
  }
}
function render(variant) {
  const state = states[variant];
  const definition = definitions[state.feature];
  const phone = document.querySelector(`[data-phone="${variant}"]`);
  phone.innerHTML = `<div class="status"><span>21:08</span><small>5G　▰</small></div><div class="chat-header"><button class="plain-icon" aria-label="返回菜单" data-action="menu">${icons('back')}</button><strong>甜甜</strong><button class="plain-icon" aria-label="语音通话演示" data-action="unavailable">${icons('call')}</button></div><div class="chat-background"><div class="time">今天 21:08</div><div class="incoming"><img class="avatar" src="assets/ui-kit/girlfriend.png" alt="甜甜"><div class="bubble">${definition.message}</div></div><div class="composer"><button class="plain-icon" aria-label="语音输入演示" data-action="unavailable">${icons('voice')}</button><span class="fake-input">输入消息</span><button class="plain-icon" aria-label="打开加号菜单" data-action="menu">${icons('plus')}</button></div></div><section class="sheet" aria-label="${definition.title}"><div class="handle"></div><div class="sheet-head"><h2>${definition.title}</h2><button class="plain-icon" aria-label="返回加号菜单" data-action="menu">${icons('close')}</button></div><p class="subtitle">${definition.subtitle}</p>${content(variant)}<div class="toast" role="status" aria-live="polite"></div></section>`;
  for (const key of ['title','diary']) {
    const field = phone.querySelector(`[data-input="${key}"]`);
    if (field) field.value = state[key];
  }
}
function notice(variant, text) {
  document.querySelector(`[data-phone="${variant}"] .toast`).textContent = text;
}
function openFeature(feature) {
  selectedFeature = feature;
  document.querySelectorAll('[data-feature]').forEach(button => button.setAttribute('aria-pressed',String(button.dataset.feature === feature)));
  Object.keys(states).forEach(variant => { states[variant].feature = feature; render(variant); });
}
document.querySelectorAll('[data-feature]').forEach(button => button.addEventListener('click',() => openFeature(button.dataset.feature)));
document.querySelectorAll('[data-view]').forEach(button => button.addEventListener('click',() => {
  const view = button.dataset.view;
  document.querySelectorAll('[data-view]').forEach(option => option.setAttribute('aria-pressed',String(option === button)));
  document.getElementById('comparison').classList.toggle('focus',view !== 'all');
  document.querySelectorAll('[data-variant]').forEach(variant => { variant.hidden = view !== 'all' && variant.dataset.variant !== view; });
}));
document.querySelectorAll('[data-phone]').forEach(phone => {
  const variant = phone.dataset.phone;
  const state = states[variant];
  phone.addEventListener('input',event => {
    if (event.target.dataset.input) state[event.target.dataset.input] = event.target.value;
  });
  phone.addEventListener('click',event => {
    const button = event.target.closest('button');
    if (!button) return;
    if (button.dataset.open) {
      if (definitions[button.dataset.open]) openFeature(button.dataset.open);
      else notice(variant,'原有功能入口，本页不打开相册、相机、电话或定位。');
      return;
    }
    if (button.dataset.group) {
      const group = button.dataset.group;
      const value = button.dataset.value;
      if (group === 'promise-title') state.title = { '早点休息':'今晚十一点前放下手机，早点休息', '出门走走':'明晚一起出门走走，散步十分钟', '读几页书':'明晚一起读十分钟的书' }[value];
      else if (group === 'minutes') {
        state.minutes = Number(value); state.seconds = state.minutes*60; state.running = false;
      } else state[group] = group === 'sleepTime' ? Number(value) : value;
      render(variant);
      return;
    }
    switch (button.dataset.action) {
      case 'menu': openFeature('menu'); break;
      case 'unavailable': notice(variant,'这是设计预览，不会拨打电话或开启录音。'); break;
      case 'focus': state.running = !state.running; render(variant); break;
      case 'reset': state.running = false; state.seconds = state.minutes*60; render(variant); break;
      case 'promise': {
        const title = state.title.trim();
        const date = phone.querySelector('[data-input="date"]').value;
        if (!title) { notice(variant,'先写下一件我们约好做的小事吧。'); break; }
        if (!date || new Date(date).getTime() <= Date.now()) { notice(variant,'选一个未来的提醒时间吧。'); break; }
        notice(variant,`示例回应：好呀，约好了。到时候我会提醒你「${title}」。本次不会创建实际提醒。`);
        break;
      }
      case 'sleep': notice(variant,`入睡界面示例：已选择${state.sleepMode}，${state.sleepTime}分钟后停止。甜甜：今晚不用想那么多啦，我在呢。此预览没有播放音频。`); break;
      case 'diary': {
        if (!state.diary.trim()) { notice(variant,'写一点今天的事情，再分享给甜甜吧。'); break; }
        notice(variant,'示例回应：谢谢你把今天的一小片分享给我。你的心情和小事，我都愿意认真听。内容仅停留在本页。');
        break;
      }
    }
  });
});
setInterval(() => {
  Object.entries(states).forEach(([variant,state]) => {
    if (!state.running) return;
    state.seconds = Math.max(0,state.seconds-1);
    if (!state.seconds) state.running = false;
    if (state.feature !== 'focus') return;
    const phone = document.querySelector(`[data-phone="${variant}"]`);
    phone.querySelector('[data-timer]').textContent = formatTime(state.seconds);
    if (!state.seconds) {
      render(variant);
      notice(variant,'专注结束啦。甜甜：认真做了一小段时间，已经很棒了。起来喝口水吧。');
    }
  });
},1000);
openFeature(selectedFeature);
