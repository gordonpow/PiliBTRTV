/// 手機查看錯誤報告的網頁（行動版）。
/// 報告文字一律用 textContent 放進頁面，不使用 innerHTML。
const String reportPageHtml = r'''<!DOCTYPE html>
<html lang="zh-TW">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta name="referrer" content="no-referrer">
<title>PiliBTRTV 錯誤報告</title>
<style>
  * { box-sizing: border-box; }
  body { margin: 0; padding: 16px; background: #1a1a1a; color: #eee;
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; }
  h1 { font-size: 20px; color: #fb7299; margin: 0 0 8px; }
  p.tip { font-size: 14px; line-height: 1.5; color: #bbb; margin: 0 0 12px; }
  .row { display: flex; gap: 10px; margin-bottom: 12px; }
  button { flex: 1; padding: 14px 8px; border: 0; border-radius: 8px;
    background: #fb7299; color: #fff; font-size: 16px; }
  button.alt { background: #444; }
  button.gh { background: #2da44e; }
  p.hint { font-size: 13px; color: #999; margin: 0 0 12px; }
  #msg { min-height: 22px; font-size: 14px; color: #8fdc8f; margin-bottom: 8px; }
  #msg.err { color: #ff8a8a; }
  pre { margin: 0; padding: 12px; background: #000; border-radius: 8px;
    font-size: 11px; line-height: 1.4; white-space: pre-wrap; word-break: break-all; }
  textarea { position: fixed; left: -9999px; top: 0; opacity: 0; }
</style>
</head>
<body>
<h1>錯誤報告</h1>
<p class="tip">把內容貼到 Threads 私訊或 GitHub issue 給開發者。內容已去除帳號與憑證等個人資料。</p>
<div class="row">
  <button id="copyBtn">複製全部</button>
  <button id="dlBtn" class="alt">下載 .txt</button>
</div>
<div class="row">
  <button id="ghBtn" class="gh">在 GitHub 回報</button>
</div>
<p class="hint">需要在手機上登入 GitHub 才能送出 issue</p>
<div id="msg"></div>
<pre id="report">載入中…</pre>
<script>
(function () {
  var token = new URLSearchParams(location.search).get('t') || '';
  var reportEl = document.getElementById('report');
  var msgEl = document.getElementById('msg');
  var text = '';

  function say(s, isErr) {
    msgEl.textContent = s;
    msgEl.className = isErr ? 'err' : '';
  }

  function legacyCopy(s) {
    var ta = document.createElement('textarea');
    ta.value = s;
    document.body.appendChild(ta);
    ta.focus();
    ta.select();
    ta.setSelectionRange(0, s.length);
    var ok = false;
    try { ok = document.execCommand('copy'); } catch (e) { ok = false; }
    document.body.removeChild(ta);
    return ok;
  }

  function copyAll() {
    if (!text) { say('報告尚未載入', true); return; }
    function fallback() {
      if (legacyCopy(text)) say('已複製全部內容');
      else say('複製失敗，請長按內容手動選取，或改用下載', true);
    }
    if (navigator.clipboard && window.isSecureContext) {
      navigator.clipboard.writeText(text).then(
        function () { say('已複製全部內容'); }, fallback);
    } else {
      fallback();
    }
  }

  var LOG_MARK = '== 最近 log ==';
  // 網址太長 GitHub 會回 500／414（登入後瀏覽器帶的 Cookie 也算在請求標頭內），保留餘量
  var MAX_URL = 3500;
  var BASE = 'https://github.com/gordonpow/PiliBTRTV/issues/new';

  function buildIssueUrl(report) {
    var m = /^版本: (.*)$/m.exec(report);
    var title = m ? '[錯誤報告] ' + m[1].trim() : '[錯誤報告]';
    var NL = String.fromCharCode(10);
    var head = '請描述發生了什麼事（做了什麼操作、預期與實際結果）：' + NL + NL + NL + '---' + NL + NL;
    function make(rep, note) {
      var body = head + (note ? note + NL + NL : '') + '```text' + NL + rep + NL + '```' + NL;
      return BASE + '?title=' + encodeURIComponent(title) +
        '&body=' + encodeURIComponent(body);
    }
    var full = make(report, '');
    if (full.length <= MAX_URL) return full;
    var note = 'log 已截斷，完整報告已複製到剪貼簿，可以貼在下方';
    var idx = report.indexOf(LOG_MARK);
    var first = idx >= 0 ? report.substring(0, idx) : report;
    var lines = idx >= 0 ? report.substring(idx + LOG_MARK.length).split(NL) : [];
    var head1 = first + (idx >= 0 ? LOG_MARK + NL : '');
    var kept = [];
    // 從最後一行往前加，直到網址超過上限
    for (var i = lines.length - 1; i >= 0; i--) {
      if (lines[i] === '') continue;
      kept.unshift(lines[i]);
      if (make(head1 + kept.join(NL), note).length > MAX_URL) {
        kept.shift();
        break;
      }
    }
    return make(head1 + kept.join(NL), note);
  }

  function openGithub() {
    if (!text) { say('報告尚未載入', true); return; }
    copyAll();
    window.open(buildIssueUrl(text), '_blank', 'noopener');
  }

  function download() {
    if (!text) { say('報告尚未載入', true); return; }
    try {
      var blob = new Blob([text], { type: 'text/plain;charset=utf-8' });
      var a = document.createElement('a');
      a.href = URL.createObjectURL(blob);
      a.download = 'PiliBTRTV-report.txt';
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      say('已開始下載');
    } catch (e) {
      say('下載失敗，請改用複製', true);
    }
  }

  document.getElementById('copyBtn').addEventListener('click', copyAll);
  document.getElementById('ghBtn').addEventListener('click', openGithub);
  document.getElementById('dlBtn').addEventListener('click', download);

  fetch('/api/report?t=' + encodeURIComponent(token), { cache: 'no-store' })
    .then(function (r) {
      if (!r.ok) throw new Error(String(r.status));
      return r.text();
    })
    .then(function (t) {
      text = t;
      reportEl.textContent = t;
    })
    .catch(function () {
      reportEl.textContent = '無法載入報告：連結錯誤或已過期，請回到電視重新產生。';
      say('連結錯誤或已過期', true);
    });
})();
</script>
</body>
</html>
''';
