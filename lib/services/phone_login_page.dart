/// 手機輔助登入網頁（由 LocalServer 在 GET /login 提供）
///
/// 一律用 textContent 寫入內容，不使用 innerHTML。
/// 極驗載入方式照 PiliPlus 的 GeetestWebviewDialog。
const String phoneLoginPageHtml = r'''<!DOCTYPE html>
<html lang="zh-TW">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="referrer" content="no-referrer">
<title>電視登入</title>
<style>
*{box-sizing:border-box}
body{margin:0;padding:16px;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;background:#f4f5f7;color:#222}
.wrap{max-width:480px;margin:0 auto}
h1{font-size:20px;color:#fb7299;margin:4px 0 12px}
.warn{background:#fff4e5;border:1px solid #f5c26b;color:#7a4b00;padding:10px 12px;border-radius:8px;font-size:14px;line-height:1.5;margin-bottom:12px}
.warn p{margin:0 0 4px}.warn p:last-child{margin:0}
.card{background:#fff;border-radius:12px;padding:16px;box-shadow:0 1px 4px rgba(0,0,0,.08)}
.tabs{display:flex;gap:8px;margin-bottom:14px}
.tab{flex:1;padding:10px 0;border:0;border-radius:8px;background:#eceef1;color:#444;font-size:15px}
.tab.active{background:#fb7299;color:#fff}
label{display:block;font-size:13px;color:#666;margin:10px 0 4px}
input,select,textarea{width:100%;padding:11px 12px;font-size:16px;border:1px solid #ccd0d5;border-radius:8px;background:#fff;color:#222}
textarea{min-height:110px;resize:vertical}
.row{display:flex;gap:8px}.row select{width:40%}.row input{flex:1}
.btn{display:block;width:100%;margin-top:14px;padding:12px;border:0;border-radius:8px;background:#fb7299;color:#fff;font-size:16px}
.btn.sec{background:#eceef1;color:#333}
.btn:disabled{opacity:.5}
#msg{margin-top:12px;font-size:14px;line-height:1.5;min-height:20px;word-break:break-word}
#msg.err{color:#d93025}#msg.ok{color:#1a8a3a}
.hidden{display:none}
.ok-box{text-align:center;padding:24px 8px;font-size:18px;color:#1a8a3a}
.hint{font-size:13px;color:#666;line-height:1.5}
a{color:#fb7299}
details{margin:10px 0;border:1px solid #e1e4e8;border-radius:8px;padding:0 10px}
summary{padding:10px 0;font-size:15px;font-weight:600;color:#444}
.step{margin:0 0 18px}
.step p{margin:0 0 8px;font-size:14px;line-height:1.6}
.step img{display:block;max-width:100%;width:320px;height:auto;margin:0 auto;border:1px solid #ccd0d5;border-radius:8px}
.em{color:#d93025;font-weight:700}
</style>
</head>
<body>
<div class="wrap">
  <h1>登入電視上的 App</h1>
  <div class="warn">
    <p>請確認手機與電視連接同一個 Wi-Fi。</p>
    <p>密碼會經由區網傳到電視，請只在自己家的 Wi-Fi 使用。</p>
  </div>
  <div class="card">
    <div id="done" class="ok-box hidden"></div>
    <div id="main">
      <div id="tabs" class="tabs">
        <button class="tab active" data-tab="pwd" type="button">密碼</button>
        <button class="tab" data-tab="sms" type="button">簡訊</button>
        <button class="tab" data-tab="cookie" type="button">Cookie</button>
      </div>

      <div id="p-pwd">
        <label for="user">帳號（手機號碼或信箱）</label>
        <input id="user" type="text" autocomplete="username" autocapitalize="off">
        <label for="pass">密碼</label>
        <input id="pass" type="password" autocomplete="current-password">
        <button id="b-pwd" class="btn" type="button">登入</button>
      </div>

      <div id="p-sms" class="hidden">
        <label for="cid">國碼與手機號碼</label>
        <div class="row">
          <select id="cid">
            <option value="886">+886 台灣</option>
            <option value="86">+86 中國大陸</option>
            <option value="852">+852 香港</option>
            <option value="853">+853 澳門</option>
            <option value="81">+81 日本</option>
            <option value="60">+60 馬來西亞</option>
            <option value="65">+65 新加坡</option>
            <option value="1">+1 美國／加拿大</option>
          </select>
          <input id="tel" type="tel" inputmode="tel" autocomplete="tel-national">
        </div>
        <button id="b-smssend" class="btn" type="button">傳送驗證碼</button>
        <div id="smscode" class="hidden">
          <label for="code">簡訊驗證碼</label>
          <input id="code" type="text" inputmode="numeric" autocomplete="one-time-code">
          <button id="b-smslogin" class="btn" type="button">登入</button>
        </div>
      </div>

      <div id="p-cookie" class="hidden">
        <div id="ck-tip" class="hint">iPhone 無法用這個方式（Safari 不允許讀取登入用的 Cookie），請改用 Android 手機操作，或在電視上試試「改用網頁版掃碼」</div>
        <p class="hint">全程用手機完成，大約 10 分鐘。需要 Firefox 瀏覽器和 Cookie-Editor 附加元件（第一次使用才要安裝）。</p>
        <details id="g1">
          <summary>第一段：第一次使用，安裝 Firefox 與 Cookie-Editor</summary>
          <div class="step"><p><b>1.</b> 本頁先不要關。按手機的主畫面鍵，打開「Play 商店」，搜尋「Firefox」，按「安裝」。安裝完成後按「開啟」。</p><img data-guide="01" alt="步驟 1 截圖" loading="lazy"></div>
          <div class="step"><p><b>2.</b> Firefox 歡迎畫面按「繼續」。問要不要設為預設瀏覽器時按「取消」，下一頁按「現在不要」，就會看到 Firefox 首頁。</p><img data-guide="02" alt="步驟 2 截圖" loading="lazy"></div>
          <div class="step"><p><b>3.</b> 按 Firefox 的「⋮」選單，選「擴充套件」。</p><img data-guide="03" alt="步驟 3 截圖" loading="lazy"></div>
          <div class="step"><p><b>4.</b> 擴充套件清單拉到最下面，按「尋找更多擴充套件」。</p><img data-guide="04" alt="步驟 4 截圖" loading="lazy"></div>
          <div class="step"><p><b>5.</b> 在網站上方的搜尋框輸入「Cookie-Editor」，點第一個結果（餅乾圖示、作者 cgagnier）。頁面上「未經 Mozilla 主動檢查」的提醒是一般說明，可以繼續。</p><img data-guide="05" alt="步驟 5 截圖" loading="lazy"></div>
          <div class="step"><p><b>6.</b> 按「新增至 Firefox」。</p><img data-guide="06" alt="步驟 6 截圖" loading="lazy"></div>
          <div class="step"><p><b>7.</b> 跳出「安裝 Cookie-Editor」時按「新增」，看到「已安裝」再按「確定」。這個權限是讀取網站 Cookie 必需的，用完可以移除。</p><img data-guide="07" alt="步驟 7 截圖" loading="lazy"></div>
        </details>
        <details id="g2">
          <summary>第二段：登入 B 站並複製 Cookie</summary>
          <div class="step"><p><b>8.</b> 在 Firefox 網址列輸入「m.bilibili.com」打開 B 站，按右上角的頭像圖示。</p><img data-guide="08" alt="步驟 8 截圖" loading="lazy"></div>
          <div class="step"><p><b>9.</b> 出現「已在APP内登录？」時，不要按打開 App，按下方的「其他方式登录」。</p><img data-guide="09" alt="步驟 9 截圖" loading="lazy"></div>
          <div class="step"><p><b>10.</b> 用手機號碼簡訊登入（國碼可改成 +886），或按「账号密码登录」改用帳號密碼。出現滑塊或圖形驗證時照畫面完成。</p><img data-guide="10" alt="步驟 10 截圖" loading="lazy"></div>
          <div class="step"><p><b>11.</b> 登入後回到 B 站首頁，右上角變成自己的頭像就表示登入成功。</p><img data-guide="11" alt="步驟 11 截圖" loading="lazy"></div>
          <div class="step"><p><b>12.</b> 按「⋮」選單，點「擴充套件」右邊的箭頭展開，再按「Cookie-Editor」。</p><img data-guide="12" alt="步驟 12 截圖" loading="lazy"></div>
          <div class="step"><p><b>13.</b> Cookie-Editor 畫面是英文：按下方的「Export」，再選「Header String」。看到「Cookies exported to clipboard as Header String」就是已複製。上方若出現「Buy me a coffee」橫幅，按「Not interested」關掉即可。</p><img data-guide="13" alt="步驟 13 截圖" loading="lazy"></div>
        </details>
        <details id="g3" open>
          <summary>第三段：貼上並登入</summary>
          <div class="step"><p><b>14.</b> 按手機的「最近使用的應用程式」鍵（或從底部往上滑並停住），左右滑動找到開著本頁的瀏覽器（例如 Chrome），點它切回來。</p><img data-guide="14" alt="步驟 14 截圖" loading="lazy"></div>
          <div class="step"><p><b>15.</b> 在本頁點「Cookie」分頁，長按下方的輸入框，選「貼上」，再按「登入」。</p><img data-guide="15" alt="步驟 15 截圖" loading="lazy"></div>
          <div class="step"><p><b>16.</b> 本頁顯示「登入成功，可以關閉這個網頁」，電視也會進入已登入的畫面。之後可以移除 Cookie-Editor，但<strong class="em">請不要在 Firefox 登出 B 站</strong>：登出會讓這組 Cookie 失效，電視也會跟著被登出。</p><img data-guide="16" alt="步驟 16 截圖" loading="lazy"></div>
        </details>
        <label for="ck">貼上 Cookie（需含 SESSDATA、bili_jct、DedeUserID）</label>
        <textarea id="ck" autocapitalize="off" spellcheck="false"></textarea>
        <p class="hint">Cookie 登入不支援投幣，其他功能正常。</p>
        <button id="b-cookie" class="btn" type="button">登入</button>
      </div>
    </div>

    <div id="captcha" class="hidden">
      <p class="hint">請完成滑塊驗證。若沒有跳出驗證視窗，請按下方按鈕。</p>
      <button id="b-gee" class="btn sec" type="button">重新開啟驗證</button>
    </div>

    <div id="risk" class="hidden">
      <p>本次登入需要驗證手機號</p>
      <p class="hint">手機號碼：<span id="risk-tel"></span></p>
      <p class="hint hidden" id="risk-link-row">詳細說明：<a id="risk-link" target="_blank" rel="noopener noreferrer"></a></p>
      <button id="b-risksend" class="btn sec" type="button">傳送驗證碼</button>
      <label for="riskcode">簡訊驗證碼</label>
      <input id="riskcode" type="text" inputmode="numeric" autocomplete="one-time-code">
      <button id="b-riskverify" class="btn" type="button">確認</button>
    </div>

    <div id="msg"></div>
  </div>
</div>
<script>
(function(){
  var NET_ERR='無法連到電視，請確認手機與電視在同一個 Wi-Fi';
  var DEAD_ERR='連結已失效，請回到電視重新掃描 QR 碼';
  var token=new URLSearchParams(location.search).get('t')||'';
  var busy=false, dead=false, geeKey='', timer=null, lastStep='';
  var $=function(id){return document.getElementById(id)};

  function show(id,on){$(id).classList.toggle('hidden',!on)}
  function setMsg(text,cls){var m=$('msg');m.textContent=text||'';m.className=cls||''}

  function api(path,body){
    var opt=body===undefined?{method:'GET'}:{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)};
    return fetch(path+'?t='+encodeURIComponent(token),opt).then(function(r){
      if(r.status===403){dead=true;setMsg(DEAD_ERR,'err');stopPoll();throw new Error('dead')}
      if(!r.ok){throw new Error('http')}
      return r.json();
    });
  }
  function call(path,body){
    if(busy||dead)return;
    busy=true;setBtns(true);
    api(path,body).then(apply).catch(function(e){
      if(e&&e.message==='dead')return;
      setMsg(e&&e.message==='http'?'操作失敗，請稍後再試':NET_ERR,'err');
    }).then(function(){busy=false;setBtns(false)});
  }
  function setBtns(d){
    var bs=document.querySelectorAll('.btn');
    for(var i=0;i<bs.length;i++)bs[i].disabled=d;
  }

  // Cookie 教學：圖片、UA 判斷
  var ua=navigator.userAgent||'';
  var isIos=/iPhone|iPad|iPod/.test(ua)||(/Macintosh/.test(ua)&&navigator.maxTouchPoints>1);
  var guideImgs=document.querySelectorAll('img[data-guide]');
  for(var gi=0;gi<guideImgs.length;gi++){(function(im){
    im.onerror=function(){im.style.display='none'};
    im.src='/login/guide/'+im.getAttribute('data-guide')+'.webp?t='+encodeURIComponent(token);
  })(guideImgs[gi])}
  if(isIos){
    $('ck-tip').className='warn';
    for(var di=1;di<=3;di++){
      var dt=$('g'+di);dt.removeAttribute('open');
      var sm=dt.querySelector('summary');sm.textContent=sm.textContent+'（僅限 Android）';
    }
  }else if(/Firefox/.test(ua)){
    var s1=$('g1').querySelector('summary');s1.textContent=s1.textContent+'（已完成可略過）';
  }

  // 分頁
  var tabs=document.querySelectorAll('.tab');
  function selectTab(name){
    for(var i=0;i<tabs.length;i++)tabs[i].classList.toggle('active',tabs[i].getAttribute('data-tab')===name);
    show('p-pwd',name==='pwd');show('p-sms',name==='sms');show('p-cookie',name==='cookie');
  }
  for(var i=0;i<tabs.length;i++){(function(t){t.addEventListener('click',function(){selectTab(t.getAttribute('data-tab'))})})(tabs[i])}

  $('b-pwd').addEventListener('click',function(){
    var u=$('user').value.trim(),p=$('pass').value;
    if(!u||!p){setMsg('請輸入帳號與密碼','err');return}
    call('/api/login/password',{username:u,password:p});
    $('pass').value='';
  });
  $('b-smssend').addEventListener('click',function(){
    var tel=$('tel').value.trim();
    if(!tel){setMsg('請輸入手機號碼','err');return}
    call('/api/login/sms/send',{cid:parseInt($('cid').value,10),tel:tel});
  });
  $('b-smslogin').addEventListener('click',function(){
    var c=$('code').value.trim();
    if(!c){setMsg('請輸入簡訊驗證碼','err');return}
    call('/api/login/sms/login',{code:c});
  });
  $('b-cookie').addEventListener('click',function(){
    var c=$('ck').value.trim();
    if(!c){setMsg('請貼上 Cookie','err');return}
    call('/api/login/cookie',{cookie:c});
  });
  $('b-risksend').addEventListener('click',function(){call('/api/login/risk/verify',{code:''})});
  $('b-riskverify').addEventListener('click',function(){
    var c=$('riskcode').value.trim();
    if(!c){setMsg('請輸入簡訊驗證碼','err');return}
    call('/api/login/risk/verify',{code:c});
  });
  $('b-gee').addEventListener('click',function(){geeKey='';if(window.__lastState)startGeetest(window.__lastState)});

  // 只有 https://*.bilibili.com 才做成連結
  function safeBiliUrl(u){
    try{var x=new URL(u);
      if(x.protocol==='https:'&&(x.hostname==='bilibili.com'||/\.bilibili\.com$/.test(x.hostname)))return x.href;
    }catch(e){}
    return '';
  }

  // 極驗：照 PiliPlus 的載入方式
  var geeScriptState=0; // 0 未載入, 1 載入中, 2 已載入, -1 失敗
  var geeWaiters=[];
  function loadGeeScript(cb){
    if(geeScriptState===2){cb();return}
    geeWaiters.push(cb);
    if(geeScriptState===1)return;
    geeScriptState=1;
    var s=document.createElement('script');
    s.src='https://static.geetest.com/static/js/fullpage.0.0.0.js';
    s.onload=function(){geeScriptState=2;var w=geeWaiters;geeWaiters=[];w.forEach(function(f){f()})};
    s.onerror=function(){geeScriptState=-1;geeWaiters=[];setMsg('驗證碼載入失敗','err')};
    document.body.appendChild(s);
  }
  function startGeetest(st){
    var gt=st.gt,challenge=st.challenge;
    if(!gt||!challenge)return;
    var C,S,T,t,ts=Date.now();
    T=function(){
      if(C&&S&&!t){
        t=Geetest(C).onSuccess(function(){
          var v=t.getValidate();
          if(!v){setMsg('驗證失敗，請重試','err');return}
          call('/api/login/captcha',{challenge:v.geetest_challenge,validate:v.geetest_validate,seccode:v.geetest_seccode});
        }).onError(function(){setMsg('驗證碼發生錯誤，請按「重新開啟驗證」','err')})
          .onClose(function(){});
        t.onReady(function(){t.verify()});
      }
    };
    window['geetest_'+ts]=function(d){
      if(!d||d.status!=='success'){setMsg('驗證碼載入失敗','err');return}
      C=Object.assign({gt:gt,challenge:challenge,offline:false,new_captcha:true,product:'bind',width:'100%',https:true,protocol:'https://'},d.data);
      T();
    };
    loadGeeScript(function(){S=1;T()});
    var g=document.createElement('script');
    g.src='https://api.geetest.com/gettype.php?gt='+encodeURIComponent(gt)+'&callback=geetest_'+ts;
    g.onerror=function(){setMsg('驗證碼載入失敗','err')};
    document.body.appendChild(g);
  }

  function apply(st){
    window.__lastState=st;
    var step=st.step||'input';
    var isErr=step==='error';
    var msg=st.message||'';
    if(step==='done'){
      show('main',false);show('captcha',false);show('risk',false);show('done',true);
      $('done').textContent='登入成功，可以關閉這個網頁';
      setMsg('');stopPoll();return;
    }
    show('done',false);
    show('main',step==='input'||step==='error'||step==='smsSent'||step==='working');
    show('captcha',step==='captcha');
    show('risk',step==='riskSms');
    show('smscode',step==='smsSent');
    if(step==='smsSent')selectTab('sms');
    if(step==='riskSms'){
      $('risk-tel').textContent=st.hideTel||'';
      var link=st.url?safeBiliUrl(st.url):'';
      show('risk-link-row',!!link);
      if(link){$('risk-link').href=link;$('risk-link').textContent=link}
    }
    if(step==='captcha'){
      var key=(st.gt||'')+'|'+(st.challenge||'');
      if(key!==geeKey){geeKey=key;startGeetest(st)}
    }else{geeKey=''}
    if(step==='working')setMsg('處理中…','');
    else if(msg||step!==lastStep||isErr)setMsg(msg,isErr?'err':'');
    lastStep=step;
  }

  function poll(){
    if(busy||dead)return;
    api('/api/login/state').then(function(st){if(!busy)apply(st)}).catch(function(e){
      if(e&&e.message==='dead')return;
      if(!busy)setMsg(e&&e.message==='http'?'操作失敗，請稍後再試':NET_ERR,'err');
    });
  }
  function stopPoll(){if(timer){clearInterval(timer);timer=null}}
  if(!token){dead=true;setMsg(DEAD_ERR,'err')}
  else{poll();timer=setInterval(poll,1500)}
})();
</script>
</body>
</html>
''';
