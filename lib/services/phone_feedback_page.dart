/// 手機回報網頁（由 LocalServer 在 GET /feedback 提供）
///
/// 一律用 textContent 寫入內容，不使用 innerHTML。
/// 送出失敗時保留輸入的文字，讓使用者可以再送一次。
const String phoneFeedbackPageHtml = r'''<!DOCTYPE html>
<html lang="zh-TW">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="referrer" content="no-referrer">
<title>回報問題／建議</title>
<style>
*{box-sizing:border-box}
body{margin:0;padding:16px;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;background:#f4f5f7;color:#222}
.wrap{max-width:480px;margin:0 auto}
h1{font-size:20px;color:#fb7299;margin:4px 0 12px}
.card{background:#fff;border-radius:12px;padding:16px;box-shadow:0 1px 4px rgba(0,0,0,.08)}
.types{display:flex;gap:8px;margin-bottom:12px}
.types label{flex:1;display:flex;align-items:center;justify-content:center;gap:6px;padding:10px 0;border-radius:8px;background:#eceef1;color:#444;font-size:15px}
.types input{margin:0}
textarea{display:block;width:100%;min-height:160px;padding:11px 12px;font-size:16px;border:1px solid #ccd0d5;border-radius:8px;background:#fff;color:#222;resize:vertical}
.count{text-align:right;font-size:12px;color:#888;margin-top:4px}
.btn{display:block;width:100%;margin-top:12px;padding:12px;border:0;border-radius:8px;background:#fb7299;color:#fff;font-size:16px}
.btn:disabled{opacity:.5}
#msg{margin-top:12px;font-size:14px;line-height:1.5;min-height:20px;word-break:break-word}
#msg.err{color:#d93025}#msg.ok{color:#1a8a3a}
.hint{font-size:13px;color:#666;line-height:1.5;margin:0 0 12px}
</style>
</head>
<body>
<div class="wrap">
  <h1>回報問題／建議</h1>
  <div class="card">
    <p class="hint">請確認手機與電視連接同一個 Wi-Fi。「問題」會一併附上診斷報告；「建議」只附上文字、App 版本與裝置型號。</p>
    <div class="types">
      <label><input type="radio" name="type" value="issue" checked>問題</label>
      <label><input type="radio" name="type" value="suggestion">建議</label>
    </div>
    <textarea id="text" maxlength="2000" placeholder="請輸入內容（最多 2000 字）"></textarea>
    <div class="count"><span id="cnt">0</span> / 2000</div>
    <button id="send" class="btn" type="button">送出</button>
    <div id="msg"></div>
  </div>
</div>
<script>
(function(){
  var token = new URLSearchParams(location.search).get('t') || '';
  var text = document.getElementById('text');
  var cnt = document.getElementById('cnt');
  var btn = document.getElementById('send');
  var msg = document.getElementById('msg');
  var finished = false;

  function show(t, cls){ msg.textContent = t; msg.className = cls || ''; }
  function selectedType(){
    var r = document.querySelector('input[name="type"]:checked');
    return r ? r.value : 'issue';
  }
  text.addEventListener('input', function(){ cnt.textContent = String(text.value.length); });

  btn.addEventListener('click', function(){
    if (finished) return;
    var value = text.value.trim();
    if (!value) { show('請先輸入內容', 'err'); return; }
    btn.disabled = true;
    show('送出中…');
    fetch('/api/feedback?t=' + encodeURIComponent(token), {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({type: selectedType(), text: value})
    }).then(function(res){
      if (res.status === 403) {
        finished = true;
        show('連結已失效，請在電視上重新產生 QR 碼', 'err');
        return null;
      }
      return res.json().catch(function(){ return null; });
    }).then(function(data){
      if (data === null && finished) return;
      if (data && data.ok) {
        finished = true;
        text.disabled = true;
        show('已送出，回報編號 ' + String(data.id || '') + '。謝謝你的回饋！', 'ok');
        return;
      }
      // 失敗：保留輸入的文字，可以再送一次
      btn.disabled = false;
      show((data && data.error) ? String(data.error) : '送出失敗，請稍後再試', 'err');
    }).catch(function(){
      btn.disabled = false;
      show('無法連線到電視，請確認手機與電視在同一個 Wi-Fi', 'err');
    });
  });
})();
</script>
</body>
</html>
''';
