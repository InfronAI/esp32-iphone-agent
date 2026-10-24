/** Records the actual embedded dashboard with synthetic data. No device/API access. */
const fs=require('node:fs');
const path=require('node:path');
const {spawnSync}=require('node:child_process');
const args=process.argv.slice(2);
if(args.length && (args.length!==2 || args[0]!=='--lang'))throw Error('Usage: node record-demo.cjs [--lang en|zh-CN]');
const language=args[1]||'zh-CN',suffix=language==='en'?'.en':'';
const localize=require('./localize.cjs').createLocalizer(language);
const root=path.resolve(__dirname,'../..'),out=path.join(root,'docs/demo'),work=path.join(root,'build/demo');
fs.mkdirSync(out,{recursive:true});fs.mkdirSync(work,{recursive:true});
const {chromium}=require('playwright');

const html=localize(fs.readFileSync(path.join(root,'hardware/hid_bridge/src/cloud/control_page.h'),'utf8').split('R"HTML(')[1].split(')HTML";')[0]);
const icons=fs.readFileSync(path.join(root,'hardware/hid_bridge/src/cloud/control_icons.h'),'utf8');
const icon=Buffer.from(icons.split('CLOUD_ICON_PNG[] PROGMEM = {')[1].split('};')[0].match(/0x[0-9a-f]{2}/g).map(Number));
const escape=s=>s.replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;');
function phone(screen){
 const names=screen==='wifi'?['Wi-Fi','Infron Demo  ✓','其他网络','选择网络…']:screen==='settings'?['设置','Wi-Fi    Infron Demo','蓝牙','电池','通用']:['主屏幕','设置','时钟','日历','天气'];
 return `<svg xmlns="http://www.w3.org/2000/svg" width="334" height="720"><rect width="334" height="720" fill="#ededf1"/><text x="22" y="38" font-family="sans-serif" font-size="18">09:41</text><text x="256" y="38" font-family="sans-serif" font-size="16">70%</text><text x="22" y="110" font-family="sans-serif" font-size="32" font-weight="bold">${names[0]}</text>${names.slice(1).map((n,i)=>`<rect x="18" y="${150+i*72}" width="298" height="62" rx="12" fill="white"/><text x="36" y="${189+i*72}" font-family="sans-serif" font-size="19">${escape(n)}</text>`).join('')}<text x="167" y="615" text-anchor="middle" font-family="sans-serif" font-size="15" fill="#666">模拟手机画面 · 非真机录像</text><rect x="122" y="690" width="90" height="5" rx="3" fill="#333"/></svg>`;
}
function card(title,subtitle,body){return `<!doctype html><html lang="zh-CN"><meta charset="utf-8"><style>*{box-sizing:border-box}body{margin:0;background:#f6f7fb;color:#18202c;font:20px/1.7 -apple-system,BlinkMacSystemFont,sans-serif;padding:92px 100px}h1{font-size:50px;line-height:1.2;letter-spacing:-1px;margin:12px 0 24px}p{color:#546073;max-width:1080px}.tag{color:#356fe6;font-weight:650;letter-spacing:2px}.flow{display:flex;gap:16px;align-items:center;margin:45px 0}.box{padding:24px;background:white;border:1px solid #dfe5ef;border-radius:18px;font-size:22px}.note{padding:20px 26px;border-radius:18px;background:#e9eef8;font-size:19px}</style><div class="tag">ESP32 IPHONE AGENT · INFRONAI</div><h1>${title}</h1><p>${subtitle}</p>${body}</html>`;}
const intro=card('从一个 Goal，开始持续观察与行动','手机发送镜像，ESP32 解码并调用视觉模型；网页展示每一轮的输入、决策与结果。','<div class="flow"><div class="box">iPhone<br>屏幕镜像</div>→<div class="box">ESP32-S3<br>Goal 循环</div>⇄<div class="box">云端视觉 API<br>下一步决策</div></div><div class="note">本片录制真实网页界面，手机屏幕、进展与结果使用模拟数据。<br>不连接真实设备、不调用收费模型、不发送 HID。</div>');
const outro=card('观察 → 决策 → 操作 → 验证','已实现短期记忆、进展判断、有限重试、卡住重规划和完成复核。','<div class="flow"><div class="box">6 步历史</div><div class="box">20 次动作</div><div class="box">40 轮决策</div><div class="box">10 分钟上限</div></div><div class="note">真实验证：固件烧录、解码对照、云端格式、控制台与停止机制。<br>待验证：手机 USB HID 完整闭环与最终端到端延迟。<br>完整源码、安装手册与硬件清单：github.com/InfronAI/esp32-iphone-agent</div>');
(async()=>{
 const browser=await chromium.launch({headless:true,...(process.env.CHROME_PATH?{executablePath:process.env.CHROME_PATH}:{})});
 const ctx=await browser.newContext({viewport:{width:1440,height:900},deviceScaleFactor:1});
 const page=await ctx.newPage();let frame='home',status={state:'idle',detail:'',running:false,steps:0,ip:'192.168.1.50',wifi_ssid:'Infron Demo LAN',usb:'ok',phone_usb_confirmed:true,airplay:2,video:'',frame_age_ms:50,calibrated:true,span_w:420,span_h:894,time_synced:true,uptime_ms:10000,trace_revision:0,video_width:334,video_height:720,queue_ms:0,decode_ms:100,jpeg_ms:100,pipeline_ms:200,jpeg_quality:90,harness:{}};
 let trace={revision:0,run_id:0,started_ms:1000,goal:'',dropped:0,events:[]},config={endpoint:'https://vision.example/v1/chat/completions',model:'your-vision-model',key_set:true};
 const notes=[],began=Date.now(),errors=[];
 // Capture PNG frames so system encoder/color-range differences cannot wash out the UI.
 const framesDir=path.join(work,'frames-'+Date.now());fs.mkdirSync(framesDir,{recursive:true});
 const frames=[];page.on('pageerror',e=>errors.push(e.message));
 function event(kind,title,detail,step=status.steps){const e={id:++trace.revision,at_ms:1000+trace.revision*1200,step,kind,title,detail,duration_ms:kind==='decision'?1800:0};trace.events.push(e);status.trace_revision=trace.revision;}
 await page.route('**/*',async route=>{
  const u=new URL(route.request().url());if(u.hostname!=='demo.test')throw Error('External request forbidden: '+u.hostname);
  if(u.pathname==='/intro'||u.pathname==='/outro')return route.fulfill({contentType:'text/html',body:localize(u.pathname==='/intro'?intro:outro)});
  if(u.pathname==='/')return route.fulfill({contentType:'text/html',body:html});
  if(u.pathname.endsWith('.png')||u.pathname==='/favicon.ico')return route.fulfill({contentType:'image/png',body:icon});
  if(u.pathname==='/api/health')return route.fulfill({json:{service:'esp32-agent',wifi_connected:true}});
  if(route.request().headers().authorization!=='Bearer DEMO-TOKEN')return route.fulfill({status:401,body:'Control token required'});
  if(u.pathname==='/api/status'){status.uptime_ms+=100;return route.fulfill({json:localize(status)});}
  if(u.pathname==='/api/trace')return route.fulfill({json:localize(trace)});
  if(u.pathname==='/api/snapshot')return route.fulfill({contentType:'image/svg+xml',headers:{'X-Frame-Age-Ms':'50','X-Frame-At-Ms':String(Date.now())},body:localize(phone(frame))});
  if(u.pathname==='/api/config')return route.fulfill({json:config});
  if(u.pathname==='/api/start'){
   trace={revision:0,run_id:1,started_ms:1000,goal:route.request().postDataJSON().goal,dropped:0,events:[]};status={...status,running:true,state:'starting',steps:0,harness:{}};event('input','收到任务',trace.goal,0);return route.fulfill({body:'ok'});
  }
  if(u.pathname==='/api/stop'){status={...status,running:false,state:'stopped',detail:'已停止；迟到的模型响应不会再执行。',harness:{...status.harness,phase:'stopped'}};event('stop','stopped',status.detail);return route.fulfill({body:'ok'});}
  throw Error('Demo does not implement '+u.pathname);
 });
 async function caption(title,text){
  title=localize(title);text=localize(text);
  notes.push({at:((Date.now()-began)/1000).toFixed(2),title,text});
  await page.evaluate(({title,text,watermark})=>{let badge=document.getElementById('demo-watermark');if(!badge){badge=document.createElement('div');badge.id='demo-watermark';badge.style.cssText='position:fixed;top:8px;left:50%;transform:translateX(-50%);z-index:99999;background:#172238;color:white;font:600 13px -apple-system,sans-serif;padding:8px 16px;border-radius:30px;pointer-events:none';document.body.append(badge);}badge.textContent=watermark;let el=document.getElementById('demo-caption');if(!el){el=document.createElement('div');el.id='demo-caption';el.style.cssText='position:fixed;bottom:10px;left:32px;right:32px;z-index:99999;border-radius:14px;background:rgba(18,27,43,.96);color:white;padding:14px 22px;font:16px/1.6 -apple-system,sans-serif;box-shadow:0 8px 28px #0003;pointer-events:none';document.body.append(el);}el.replaceChildren();const h=document.createElement('strong');h.textContent=title+'  ';h.style.color='#9ec5ff';const p=document.createElement('span');p.textContent=text;el.append(h,p);},{title,text,watermark:localize('界面与任务模拟演示 · 非真机 HID 操控录像')});
 }
 async function hold(ms){const end=Date.now()+ms;do{const file=path.join(framesDir,String(frames.length).padStart(5,'0')+'.png');if(language==='en'){const visible=await page.evaluate(()=>document.body.innerText+' '+[...document.querySelectorAll('input,textarea')].map(el=>el.value).join(' '));if(/\p{Script=Han}/u.test(visible))throw Error('Chinese text in English recording');}await page.screenshot({path:file});frames.push({file,at:Date.now()});await page.waitForTimeout(120);}while(Date.now()<end);}
 try{
  await page.goto('http://demo.test/intro');await caption('01 · 架构','ESP32 独立执行循环，iPhone App 与网页负责配置、任务和监控。');await hold(6500);
  await page.goto('http://demo.test/');await caption('02 · 先登录，再看真实状态','演示令牌为 DEMO-TOKEN；这里没有任何真实设备凭据。');await hold(1500);await page.locator('#token').fill('DEMO-TOKEN');await hold(1000);await page.locator('#connect').click();await page.waitForSelector('#dashboard:not([hidden])');await hold(2500);
  await caption('03 · 首屏同时看画面和进展','左侧监控，右侧执行详情；清晰优先，默认每 5 秒刷新。');await hold(5500);
  await page.locator('#task-form').scrollIntoViewIfNeeded();await caption('04 · 从示例快速开始','12 个常用只读目标，网页另有无需 HID 的“读懂当前屏幕”。');await hold(4500);
  await page.locator('#goal').fill(localize('打开设置的 Wi-Fi 页面，告诉我当前连接的网络名称。只查看，不修改设置。'));await hold(1500);await Promise.all([page.waitForResponse(r=>new URL(r.url()).pathname==='/api/start'),page.locator('#start').click()]);await page.evaluate(()=>scrollTo(0,0));
  const rounds=[{n:1,frame:'home',obs:'主屏幕可见设置入口',summary:'尚未到达目标页面',subgoal:'打开设置',expected:'出现设置列表',action:{action:'tap',x:.24,y:.3}},
   {n:2,frame:'settings',obs:'设置页面可见 Wi-Fi 入口',summary:'已打开设置',subgoal:'进入 Wi-Fi 页面',expected:'显示当前已连接的网络',action:{action:'tap',x:.5,y:.26}}];
  for(const r of rounds){frame=r.frame;status={...status,state:'thinking',steps:r.n-1,harness:{phase:'decide',round:r.n,round_limit:40,actions:r.n-1,action_limit:20,summary:r.summary,subgoal:r.subgoal,expected:r.expected,observation:r.obs,feedback:'',verifying:false}};event('request','发送画面与目标',`模拟输入：原始 Goal + 当前截图 + 最近动作记录\n子目标：${r.subgoal}`,r.n);event('decision','模型观察与动作选择',JSON.stringify({...r.action,observation:r.obs,summary:r.summary,subgoal:r.subgoal,expected:r.expected,progress:r.n===1?'unknown':'advanced',reason:'依据当前画面，进入目标信息所在页面。'}),r.n);await caption('05 · Goal 驱动下一步','每轮结合新画面、最近动作与预期结果，选择一个动作。');await hold(2800);status.state='acting';status.steps=r.n;status.harness.phase='act';event('action','执行选定动作',JSON.stringify(r.action));await hold(2400);status.state='thinking';status.harness.phase='observe';event('action_result','HID 已确认，等待画面验证','模拟命令确认；尚不能视为目标完成。');await hold(2400);}
  frame='wifi';status={...status,state:'thinking',harness:{...status.harness,phase:'verify',round:3,summary:'Wi-Fi 页面显示当前网络 Infron Demo',subgoal:'复核已读取的网络名称',expected:'新截图仍显示同一连接状态',verifying:true}};event('verify','候选完成，等待新画面复核','模拟观察：已连接 Infron Demo；需要另一张新图再确认。');await caption('06 · 完成也要验证','HID 确认不是成功；候选完成后，再取一张新画面复核整个 Goal。');await hold(5000);
  status={...status,state:'done',running:false,detail:'当前连接的 Wi-Fi 名称：Infron Demo。未修改设置。',harness:{...status.harness,phase:'done',round:4,verifying:false}};event('result','done',status.detail);await hold(2800);await page.screenshot({path:path.join(out,'poster'+suffix+'.jpg'),type:'jpeg',quality:85});await hold(2000);
  await caption('07 · 再发一个目标，演示异常分支','以下使用新的模拟任务，展示卡住后的处理，不是已完成任务继续操作。');
  await page.locator('#task-form').scrollIntoViewIfNeeded();await page.locator('#goal').fill(localize('回到主屏幕，然后打开设置。只导航，不修改配置。'));await hold(1800);await Promise.all([page.waitForResponse(r=>new URL(r.url()).pathname==='/api/start'),page.locator('#start').click()]);await page.evaluate(()=>scrollTo(0,0));
  event('action','执行选定动作','{"action":"home"}',1);event('observe','验证结果','模拟结果：画面没有改变。',1);event('action','执行选定动作','{"action":"home"}',2);event('observe','验证结果','模拟结果：画面仍未改变，阻止继续重复。',2);
  status={...status,running:true,state:'thinking',steps:2,detail:'检测到动作没有取得进展，正在调整策略。',harness:{...status.harness,phase:'replan',round:3,round_limit:40,summary:'演示另一条异常分支：重复动作没有改变页面',subgoal:'选择其他路径或报告阻塞',feedback:'不会持续重复无效点击。'}};event('replan','调整执行策略','模拟分支：重复无效动作被拦截，先重新规划。');await caption('07 · 卡住重规划，随时可停止','有限重试和执行上限防止无限循环；用户停止优先于迟到响应。');await hold(4000);await page.locator('#stop').click();await hold(3500);
  await page.getByRole('button',{name:localize('云端模型配置'),exact:true}).click();await caption('08 · 两端共用云端配置','Endpoint、模型和 Key 保存在板子；演示使用 example 域名，不发送网络请求。');await hold(4500);await page.locator('[data-action="close"]').click();
  await page.goto('http://demo.test/outro');await caption('09 · 可公开、可复现','模拟素材随源码发布；真机 HID 闭环需要主机转接器、镜像和指针校准。');await hold(6500);
  if(errors.length)throw Error(errors.join('\n'));
  await ctx.close();
  const concat=path.join(framesDir,'frames.txt');
  fs.writeFileSync(concat,frames.map((f,i)=>`file '${path.basename(f.file)}'\nduration ${((frames[i+1]?.at??f.at+120)-f.at)/1000}\n`).join('')+`file '${path.basename(frames.at(-1).file)}'\n`);
  const enc=spawnSync(process.env.DEMO_FFMPEG||'ffmpeg',['-y','-v','error','-f','concat','-safe','0','-i',concat,'-r','25','-c:v','libx264','-preset','medium','-crf','23','-pix_fmt','yuv420p','-movflags','+faststart','-an',path.join(out,'demo'+suffix+'.mp4')],{stdio:'inherit'});if(enc.status!==0)throw Error('ffmpeg conversion failed');
  fs.writeFileSync(path.join(out,'chapters'+suffix+'.json'),JSON.stringify({kind:'simulated-ui-demo',language,demo_labels_localized:language==='en',real_hid:false,real_model_requests:false,chapters:notes},null,2)+'\n');
  console.log(language+': Demo generated; all phone frames and responses are synthetic; no device/API/HID calls.');
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
