// PiliBTRTV／PiliBTR 一鍵回報：接收 App 的 POST，寄信到開發者信箱。
// payload 的 app 欄位分辨來源（PiliBTR 會送 "PiliBTR"；沒有時視為 PiliBTRTV）。
// 部署：執行身分必須是「我」，存取權「所有人」。步驟見 README.md。

// 收件信箱；留空則寄給部署者自己（Session.getEffectiveUser）
const TO = '';
const MAX_RAW_CHARS = 1000000;
const PER_INSTALL_PER_HOUR = 5;
const GLOBAL_PER_HOUR = 30;

function doPost(e) {
  const lock = LockService.getScriptLock();
  try {
    const raw = e && e.postData ? e.postData.contents : '';
    if (raw.length > MAX_RAW_CHARS) return out({ ok: false, error: 'size' });
    const d = JSON.parse(raw);

    const id = String(d.id || '');
    if (!/^[A-Z0-9]{6}$/.test(id)) return out({ ok: false, error: 'bad_id' });

    lock.waitLock(5000);
    const cache = CacheService.getScriptCache();

    // 去重：同一編號重送不再寄信
    if (cache.get('id_' + id)) return out({ ok: true, id: id, dup: true });

    const bucket = Math.floor(Date.now() / 3600000);
    const installKey = 'n_' + bucket + '_' +
      String(d.installId || 'unknown').replace(/[^A-Za-z0-9]/g, '').slice(0, 32);
    const globalKey = 'g_' + bucket;
    const n = Number(cache.get(installKey) || 0);
    const g = Number(cache.get(globalKey) || 0);
    if (n >= PER_INSTALL_PER_HOUR || g >= GLOBAL_PER_HOUR) {
      return out({ ok: false, error: 'rate' });
    }
    if (MailApp.getRemainingDailyQuota() < 1) {
      return out({ ok: false, error: 'quota' });
    }

    const to = TO || Session.getEffectiveUser().getEmail();
    const app = s(d.app) || 'PiliBTRTV';
    const subject = '[' + app + ' 回報 ' + id + '] ' + s(d.category) + '｜' +
      s(d.version) + '｜' + s(d.device);
    const body = [
      'App：' + app,
      '回報編號：' + id,
      '類型：' + s(d.category),
      '版本：' + s(d.version),
      '裝置：' + s(d.device),
      'Android：' + s(d.android),
      '安裝 ID：' + s(d.installId),
      '',
      '完整報告見附件。'
    ].join('\n');
    MailApp.sendEmail({
      to: to,
      subject: subject,
      body: body,
      attachments: [
        Utilities.newBlob(String(d.report || ''), 'text/plain', 'report-' + id + '.txt')
      ]
    });

    cache.put(installKey, String(n + 1), 3600);
    cache.put(globalKey, String(g + 1), 3600);
    cache.put('id_' + id, '1', 21600);
    return out({ ok: true, id: id });
  } catch (err) {
    return out({ ok: false, error: 'server' });
  } finally {
    try { lock.releaseLock(); } catch (x) {}
  }
}

// 瀏覽器直接開網址時的簡單回應（檢查部署是否公開）
function doGet() {
  return out({ ok: true, service: 'PiliBTR report' });
}

function s(v) {
  return String(v == null ? '' : v).slice(0, 80).replace(/[\r\n]/g, ' ');
}

function out(o) {
  return ContentService.createTextOutput(JSON.stringify(o))
    .setMimeType(ContentService.MimeType.JSON);
}
