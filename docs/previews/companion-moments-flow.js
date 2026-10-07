const icon = name => `<svg class="icon" aria-hidden="true"><use href="#${name}"/></svg>`;
const escapeText = value => String(value).replace(/[&<>"']/g, character => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[character]));
const avatar = '<img class="avatar" src="assets/ui-kit/girlfriend.png" alt="甜甜">';
const flows = {
  focus:{title:'一起专注',steps:['聊天入口','设置专注','专注进行中','暂停休息','完成回顾','回到聊天'],notes:['加号第二行增加新功能，原有入口不变。','选择场景与时长，开始后进入独立计时页。','伙伴安静陪伴，不持续发消息干扰你。','暂停保留剩余时间，可以继续或提前结束。','专注结束后展示本次回顾与伙伴鼓励。','结果变成聊天卡片，伙伴回应接在下面。'],clicks:['点「一起专注」。','点「开始一起专注」。','点「暂停一下」或「预览专注完成」。','点「继续专注」返回计时，或结束本次专注。','点「回到聊天，分享这次专注」。','点「再专注一次」重新设置。']},
  promise:{title:'小约定',steps:['聊天入口','写下约定','约定已创建','等待提醒','伙伴提醒','完成反馈'],notes:['约定自动关联当前聊天伙伴。','填写小事、提醒时间和事后关心开关。','创建后有明确确认页，而不是只有 Toast。','查看待提醒约定，支持重新编辑。','提醒出现在伙伴聊天里，支持完成、推迟或跳过。','展示用户反馈及伙伴回应，让关心有后续。'],clicks:['点「小约定」。','点「和甜甜约好了」。','点「查看这个约定」。','点「模拟提醒到达」。','点「我完成啦」「晚点提醒我」或「今天先不做了」。','点「再约一件小事」。']},
  sleep:{title:'陪我入睡',steps:['聊天入口','选择陪伴','正在陪伴','调整定时','晚安结束','聊天记录'],notes:['从加号进入，不默认发起电话。','选择故事、聊天或安静陪伴，使用当前伙伴音色。','独立播放界面，展示头像、文案、暂停与停止按钮。','陪伴中也可以调整停止时间。','结束后不要求用户继续回复，安心放下手机。','留下一张陪伴记录，方便以后再次开始。'],clicks:['点「陪我入睡」。','点「陪我慢慢入睡」。','点暂停、调整定时，或停止陪伴。','选时长，点「应用并继续陪伴」。','点「回到聊天」。','点「下次还听这个」。']},
  diary:{title:'今日小记',steps:['聊天入口','写今天的小事','分享给伙伴','伙伴回应','小记列表','小记详情'],notes:['从聊天发起，小记也有自己的列表。','选心情、记录一件事，内容带入后续页面。','展示发出的小记卡片与伙伴回应等待态。','伙伴在卡片之后回应，小记不是孤立的备忘录。','列表展示自己的记录，点击查看全文。','看到原文、心情和伙伴回应，可以回到这段聊天。'],clicks:['点「今日小记」。','点「记下来，分享给甜甜」。','点「预览伙伴回应」。','点「查看我的小记」。','点击今天的小记卡片。','点「回到这段聊天」或「再写一篇」。']},
};
let feature='focus', step=0, theme='a';
const state={
  focus:{activity:'学习',minutes:25,seconds:1500,running:false,quiet:true},
  promise:{title:'明晚一起散步十分钟',day:'明天',time:'21:00',care:true,outcome:'completed',postponed:false},
  sleep:{mode:'睡前故事',minutes:20,paused:false,paragraph:0},
  diary:{mood:'还不错',text:'今天下班路上绕远了一点，看到晚霞特别好看。虽然有点累，但这一刻觉得今天也没那么糟。'},
};
const phone=document.getElementById('phone');
const today=new Intl.DateTimeFormat('zh-CN',{month:'long',day:'numeric'}).format(new Date());
function chips(values,current,field,suffix=''){return `<div class="chips">${values.map(value=>`<button class="chip" data-field="${field}" data-value="${escapeText(value)}" aria-pressed="${current===value}">${escapeText(value)}${suffix}</button>`).join('')}</div>`;}
function action(label,command,secondary=false,symbol=''){return `<button class="action ${secondary?'secondary':''}" data-action="${command}">${symbol?icon(symbol):''}${label}</button>`;}
function hero(text){return `<div class="hero">${avatar}<div><p>${text}</p><small>甜甜 · 你的陪伴伙伴</small></div></div>`;}
function incoming(text){return `<div class="incoming">${avatar}<div class="bubble">${text}</div></div>`;}
function composer(){return `<div class="spacer"></div><div class="composer">${icon('voice')}<span>输入消息</span><button class="icon-button" data-action="entry" aria-label="打开加号菜单">${icon('plus')}</button></div>`;}
function messageCard(title,text,footer=''){return `<div class="outgoing"><strong>${title}</strong><p>${text}</p><small>${footer}</small></div>`;}
function entry(){return `<div class="chat-date">今天 21:08</div>${incoming('今天想做点什么？我陪你一起。')}${composer()}<div class="menu">${[['photo','相册'],['camera','相机'],['call','电话'],['point','位置'],...Object.entries(flows).map(([name,flow])=>[name,flow.title])].map(([name,label],index)=>`<button class="${index>=4?'new':''} ${name===feature?'selected':''}" data-menu="${name}"><span class="tile">${icon(name)}</span>${label}</button>`).join('')}</div>`;}
function formatTime(seconds){return `${String(Math.floor(seconds/60)).padStart(2,'0')}:${String(seconds%60).padStart(2,'0')}`;}
function focusScreen(){
 const data=state.focus;
 if(step===1)return `<p class="kicker">把时间留给眼前的事</p><h2>这一会儿，我陪你。</h2><p class="sub">不着急，一次只做好一件事。</p>${hero('你安心忙，我不打扰你。结束了，记得来找我。')}<div class="label">想专注做什么</div>${chips(['学习','工作','阅读'],data.activity,'activity')}<div class="label">这次专注多久</div>${chips([25,45,60],data.minutes,'minutes',' 分钟')}<label class="row"><span>安静陪伴<small>过程中不主动发消息</small></span><input data-input="quiet" type="checkbox" ${data.quiet?'checked':''}></label><div class="row"><span>结束后的鼓励<small>使用当前伙伴性格和声音</small></span>${icon('heart')}</div>${action('开始一起专注','start-focus',false,'play')}`;
 if(step===2||step===3)return `<div class="center"><div class="badge">${icon('focus')}${escapeText(data.activity)} · ${step===3?'暂时休息':'专注进行中'}</div><h2>${step===3?'歇一下也没关系。':'现在，只做这一件事。'}</h2><div class="timer"><div><strong id="countdown">${formatTime(data.seconds)}</strong><small>剩余专注时间</small></div></div>${hero(step===3?'休息一下吧，我还在。准备好了我们再继续。':'你忙你的，不用回复我。我就在这里。')}<p class="tiny">${step===3?'计时已暂停，继续时保留剩余时间。':'本页倒计时演示，不触发手机后台任务。'}</p>${action(step===3?'继续专注':'暂停一下',step===3?'resume-focus':'pause-focus',false,step===3?'play':'pause')}${action('结束本次专注','finish-focus',true)}<button class="text-button" data-action="finish-focus">预览专注完成后的页面</button></div>`;
 if(step===4)return `<div class="center"><div class="round">${icon('check')}</div><p class="kicker">这一段时间，有人在陪你</p><h2>认真了一小会儿，<br>已经很棒了。</h2></div><div class="metrics"><div class="metric"><strong>${data.minutes} 分钟</strong><span>演示完成时长</span></div><div class="metric"><strong>${escapeText(data.activity)}</strong><span>本次专注场景</span></div></div>${hero('辛苦啦！先起来伸个懒腰，喝口水。你今天又往前走了一小步。')}${action('回到聊天，分享这次专注','next',false,'heart')}<button class="text-button" data-action="restart">再专注一次</button>`;
 return `<div class="chat-date">今天</div>${messageCard('一起专注',`${escapeText(data.activity)} · ${data.minutes} 分钟<br>甜甜陪我完成了这次专注。`,'专注记录 · 演示')}${incoming('认真做完一件事的你，值得被夸一下。现在放松一小会儿吧。')}<button class="text-button" data-action="restart">再专注一次</button>${composer()}`;
}
function promiseScreen(){
 const data=state.promise,title=escapeText(data.title),when=`${data.day} ${escapeText(data.time)}${data.postponed?' · 已推迟十五分钟':''}`;
 if(step===1)return `<p class="kicker">有人记得的小事</p><h2>我们约好一件小事。</h2>${hero('不用是什么大目标。散散步、早点睡，都可以。')}<label class="label" for="promise-title">想和甜甜约好什么</label><input id="promise-title" class="field" data-input="title" maxlength="60" value="${title}" placeholder="写下一件想做的小事"><div class="label">提醒日期</div>${chips(['今天','明天','后天'],data.day,'day')}<label class="label" for="promise-time">提醒时间</label><input id="promise-time" class="field" data-input="time" type="time" value="${escapeText(data.time)}"><label class="row"><span>完成后再关心一下<small>问问做完感觉怎么样</small></span><input data-input="care" type="checkbox" ${data.care?'checked':''}></label>${action('和甜甜约好了','save-promise',false,'promise')}<div class="error" role="alert"></div>`;
 if(step===2)return `<div class="center"><div class="round">${icon('check')}</div><h2>好，约好了。</h2><p class="sub">这件小事，甜甜也放在心上了。</p></div><div class="card"><div class="badge">${icon('promise')}待提醒</div><h3>${title}</h3><p>${when}</p><div class="meta"><span>提醒伙伴：甜甜</span><span>${data.care?'事后关心已开启':'仅到时提醒'}</span></div></div>${hero('我记住啦。到时候轻轻提醒你，咱们一起把这件小事做好。')}${action('查看这个约定','next')}`;
 if(step===3)return `<div class="badge">${icon('promise')}等待提醒</div><h2>我们的下一件小事</h2><p class="sub">不催你，只在约好的时间出现。</p><div class="card"><h3>${title}</h3><p>${when}</p><div class="meta"><span>甜甜提醒你</span><span>${data.care?'之后会再关心':'不追加询问'}</span></div></div>${hero('现在先安心做自己的事吧，约定的时间我会出现。')}${action('模拟提醒到达','next',false,'promise')}${action('修改这个约定','restart',true)}<p class="tiny">设计预览，不会设置实际手机提醒。</p>`;
 if(step===4)return `<div class="chat-date">约定的时间到了</div>${incoming(`还记得我们的小约定吗？「${title}」现在可以开始啦。我陪着你。`)}<div class="card"><div class="badge">${icon('promise')}我们的约定</div><h3>${title}</h3><p>${when}</p>${action('我完成啦','complete-promise',false,'check')}${action('晚点提醒我','postpone-promise',true)}<button class="text-button" data-action="skip-promise">今天先不做了</button></div>${composer()}`;
 return `<div class="chat-date">小约定 · 反馈</div>${messageCard(data.outcome==='completed'?'小约定已完成':'这次先放一放',title,when)}${incoming(data.outcome==='completed'?'说到做到的你，好棒。'+(data.care?'做完感觉怎么样？想听听你的感受。':'先好好歇一会儿吧。'):'没关系，不需要每次都做到。照顾好自己，我们下次再约。')}${action('再约一件小事','restart',false,'promise')}${composer()}`;
}
const sleepParagraphs=['窗外的声音渐渐轻了下来。你把今天的忙碌放在门外，慢慢躺好。现在不用赶路，也不用证明什么。','想象一间亮着小灯的屋子。窗帘轻轻摇着，一杯温水就在手边。有人陪着你，今晚可以安心一点。','如果脑海里还跑着很多事情，也没关系。先把肩膀放松一点，慢慢呼吸。明天的事情，我们明天再想。'];
function sleepScreen(){
 const data=state.sleep;
 if(step===1)return `<p class="kicker">今晚，也有人轻声陪你</p><h2>慢慢睡，不用着急。</h2>${hero('今天辛苦啦。把手机的声音调舒服一点，我们慢慢放松。')}<div class="label">想怎样被陪伴</div>${chips(['睡前故事','轻声聊天','安静陪着'],data.mode,'mode')}<div class="row"><span>伙伴声音<small>使用甜甜当前的音色</small></span>${icon('voice')}</div><div class="label">多久后自动停止</div>${chips([10,20,30],data.minutes,'minutes',' 分钟')}${action('陪我慢慢入睡','next',false,'sleep')}<p class="tiny">这是播放器设计演示，不播放实际声音。</p>`;
 if(step===2)return `<div class="center"><div class="badge">${icon('sleep')}${escapeText(data.mode)} · ${data.paused?'已暂停':'陪伴中'}</div><img class="playing-avatar" src="assets/ui-kit/girlfriend.png" alt="甜甜"><h2>今晚，我在这里。</h2><p class="sub">甜甜的声音 · ${data.minutes} 分钟后停止</p><div class="waves ${data.paused?'paused':''}">${'<i></i>'.repeat(13)}</div><div class="transcript">${data.mode==='安静陪着'?'不需要说什么。放松肩膀，慢慢呼吸，我在这里陪着你。':sleepParagraphs[data.paragraph]}</div>${action(data.paused?'继续陪伴':'暂停一下','toggle-sleep',false,data.paused?'play':'pause')}<div class="pair">${action('调整定时','sleep-settings',true)}${action('停止陪伴','finish-sleep',true)}</div><button class="text-button" data-action="next-paragraph">看看下一段陪伴文案</button><p class="tiny">波形仅为设计示意，没有实际音频。</p></div>`;
 if(step===3)return `<p class="kicker">播放中也能轻松修改</p><h2>什么时候安静停下？</h2><p class="sub">不需要一直看着手机，舒服就好。</p><div class="round">${icon('sleep')}</div><div class="label">新的停止时间</div>${chips([10,20,30],data.minutes,'minutes',' 分钟')}<div class="card"><h3>${data.minutes} 分钟后自动停止</h3><p>继续使用${escapeText(data.mode)}陪伴。到时停止声音，不再发起电话或唤醒你。</p></div>${action('应用并继续陪伴','apply-sleep',false,'check')}${action('预览定时结束','finish-sleep',true)}`;
 if(step===4)return `<div class="center"><div class="round">${icon('sleep')}</div><p class="kicker">今晚的陪伴结束了</p><h2>晚安，<br>愿你睡个好觉。</h2><p class="sub">${escapeText(data.mode)}已经停止。<br>接下来不用回复，也不用继续看手机。</p></div>${hero('今天就到这里吧。剩下的事，明天再说。晚安。')}${action('回到聊天','next')}${action('再陪我一会儿','resume-sleep',true)}`;
 return `<div class="chat-date">睡前陪伴</div>${messageCard('陪我入睡',`${escapeText(data.mode)} · ${data.minutes} 分钟定时<br>使用甜甜的声音陪伴。`,'陪伴已结束 · 演示记录')}${incoming('晚安啦，希望你醒来时，心情也轻一点。')}<button class="text-button" data-action="restart">下次还听这个</button>${composer()}`;
}
function diaryCard(){return messageCard('今日小记',escapeText(state.diary.text),`${today} · ${escapeText(state.diary.mood)}`);}
function diaryReply(){return '今天虽然有点累，但你还是愿意留住一个小小的瞬间。谢谢你分享给我，愿意再说说当时的感觉吗？';}
function diaryScreen(){
 const data=state.diary;
 if(step===1)return `<p class="kicker">${today} · 只写一点点也很好</p><h2>今天，有什么想留下？</h2><p class="sub">不是作业，也不用写得漂亮。</p><div class="label">此刻的心情</div>${chips(['很开心','还不错','有点累','想被抱抱'],data.mood,'mood')}<label class="label" for="diary-text">今天的一件小事</label><textarea id="diary-text" data-input="text" maxlength="1000">${escapeText(data.text)}</textarea>${hero('真实就很好。写下来，我会认真看。')}${action('记下来，分享给甜甜','save-diary',false,'diary')}<div class="error" role="alert"></div>`;
 if(step===2)return `<div class="chat-date">今天</div>${diaryCard()}${incoming('甜甜正在认真看你的小记…')}${action('预览伙伴回应','next',false,'heart')}<p class="tiny">等待态仅为演示；没有实际调用 AI。</p>${composer()}`;
 if(step===3)return `<div class="chat-date">今天</div>${diaryCard()}${incoming(diaryReply())}${action('查看我的小记','next',false,'diary')}${composer()}`;
 if(step===4)return `<p class="kicker">属于你的生活片段</p><h2>我的小记</h2><p class="sub">今天的你，也值得被记住。</p><button class="list-card" data-action="next"><small>${today} · ${escapeText(data.mood)}</small><h3>${escapeText(data.text)}</h3><span>甜甜已回应 · 查看详情</span></button><p class="tiny">这里只展示本次预览内容，不读取你的真实记录。</p>${action('再写一篇','restart',false,'plus')}`;
 return `<div class="badge">${icon('diary')}${today} · ${escapeText(data.mood)}</div><h2>今天的一小片</h2><div class="card"><p style="white-space:pre-wrap;color:var(--ink)">${escapeText(data.text)}</p></div><div class="label">甜甜的回应</div>${hero(diaryReply())}${action('回到这段聊天','diary-chat',false,'heart')}${action('再写一篇','restart',true)}`;
}
function go(destination){step=Math.max(0,Math.min(5,destination));state.focus.running=feature==='focus'&&step===2;render();}
function render(){
 const flow=flows[feature],chat=step===0||(feature==='focus'&&step===5)||(feature==='promise'&&step>=4)||(feature==='sleep'&&step===5)||(feature==='diary'&&[2,3].includes(step));
 phone.className=`phone theme-${theme}`;
 phone.innerHTML=`<div class="status"><span>21:08</span><small>5G　▰</small></div><div class="appbar"><button class="icon-button" data-action="back" aria-label="返回上一页">${icon('back')}</button><strong>${chat?'甜甜':flow.title}</strong><button class="icon-button" data-action="entry" aria-label="回到聊天入口">${icon(chat?'plus':feature)}</button></div><div class="screen ${chat?'chat':''}">${step===0?entry():({focus:focusScreen,promise:promiseScreen,sleep:sleepScreen,diary:diaryScreen}[feature])()}</div><div class="home-indicator"></div>`;
 document.querySelectorAll('[data-feature]').forEach(button=>button.setAttribute('aria-pressed',String(button.dataset.feature===feature)));
 document.querySelectorAll('[data-theme]').forEach(button=>button.setAttribute('aria-pressed',String(button.dataset.theme===theme)));
 document.getElementById('steps').innerHTML=flow.steps.map((label,index)=>`<button data-step="${index}" ${index===step?'aria-current="step"':''}><span class="number">${index+1}</span>${label}</button>`).join('');
 document.getElementById('page-number').textContent=`${step+1} / 6`;
 document.getElementById('previous').disabled=step===0;document.getElementById('next').disabled=step===5;
 document.getElementById('guide').innerHTML=`<div class="step-label">${flow.title} / PAGE ${String(step+1).padStart(2,'0')}</div><h2>${flow.steps[step]}</h2><p class="description">${flow.notes[step]}</p><div class="guide-card"><h3>你可以点什么</h3><p>${flow.clicks[step]}</p></div><div class="guide-card"><h3>点击之后怎么展示</h3><p>${step<5?`下一步是「${flow.steps[step+1]}」。手机里的按钮可以前进、返回或分支操作，不只是提示文字。`:'已经到流程末页，可以返回前面的页面，或从头重新体验。'}</p></div><div class="guide-card"><h3>当前是设计演示</h3><p>伙伴：甜甜 · 配色 ${theme.toUpperCase()}<br>不会实际提醒、播放声音或发送内容。</p></div><button class="restart" data-action="entry">从聊天入口重新看</button>`;
}
document.getElementById('previous').addEventListener('click',()=>go(step-1));document.getElementById('next').addEventListener('click',()=>go(step+1));
phone.addEventListener('input',event=>{const field=event.target.dataset.input;if(field)state[feature][field]=event.target.type==='checkbox'?event.target.checked:event.target.value;});
document.addEventListener('click',event=>{
 const button=event.target.closest('button');if(!button)return;
 if(button.dataset.feature){feature=button.dataset.feature;go(0);return;}
 if(button.dataset.theme){theme=button.dataset.theme;render();return;}
 if(button.dataset.step){go(Number(button.dataset.step));return;}
 if(button.dataset.menu){if(flows[button.dataset.menu]){feature=button.dataset.menu;go(1);}return;}
 if(button.dataset.field){const field=button.dataset.field;state[feature][field]=field==='minutes'?Number(button.dataset.value):button.dataset.value;if(feature==='focus'&&field==='minutes')state.focus.seconds=state.focus.minutes*60;render();return;}
 switch(button.dataset.action){
  case 'entry':go(0);break;case 'back':go(step-1);break;case 'next':go(step+1);break;case 'restart':go(1);break;
  case 'start-focus':state.focus.seconds=state.focus.minutes*60;go(2);break;case 'pause-focus':go(3);break;case 'resume-focus':go(2);break;case 'finish-focus':go(4);break;
  case 'save-promise':if(!state.promise.title.trim()||!state.promise.time)phone.querySelector('.error').textContent='写下一件小事，再选择提醒时间吧。';else{state.promise.postponed=false;go(2);}break;
  case 'complete-promise':state.promise.outcome='completed';go(5);break;case 'skip-promise':state.promise.outcome='skipped';go(5);break;
  case 'postpone-promise':{
   const [hours,minutes]=state.promise.time.split(':').map(Number);
   const total=hours*60+minutes+15;
   state.promise.time=`${String(Math.floor(total/60)%24).padStart(2,'0')}:${String(total%60).padStart(2,'0')}`;
   if(total>=1440)state.promise.day={'今天':'明天','明天':'后天','后天':'三天后'}[state.promise.day]||'三天后';
   state.promise.postponed=true;go(3);break;
  }
  case 'toggle-sleep':state.sleep.paused=!state.sleep.paused;render();break;case 'sleep-settings':go(3);break;case 'apply-sleep':state.sleep.paused=false;go(2);break;case 'finish-sleep':go(4);break;case 'resume-sleep':state.sleep.paused=false;go(2);break;case 'next-paragraph':state.sleep.paragraph=(state.sleep.paragraph+1)%sleepParagraphs.length;render();break;
  case 'save-diary':if(!state.diary.text.trim())phone.querySelector('.error').textContent='先写一点今天的小事吧。';else go(2);break;case 'diary-chat':go(3);break;
 }
});
setInterval(()=>{if(!state.focus.running)return;state.focus.seconds=Math.max(0,state.focus.seconds-1);const countdown=document.getElementById('countdown');if(countdown)countdown.textContent=formatTime(state.focus.seconds);if(!state.focus.seconds)go(4);},1000);
go(0);
