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
