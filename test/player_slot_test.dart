import 'package:bili_tv_app/services/player_slot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('序列取得：釋放後下一個才取得', () async {
    final slot = PlayerSlot();
    final t1 = await slot.acquire(cancelled: () => false);
    expect(t1, isNotNull);
    expect(slot.busy, true);
    Object? t2;
    final f = slot.acquire(cancelled: () => false).then((t) => t2 = t);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(t2, isNull);
    slot.release(t1);
    await f;
    expect(t2, isNotNull);
    expect(slot.busy, true);
  });

  test('等待中取消回 null', () async {
    final slot = PlayerSlot();
    final t1 = await slot.acquire(cancelled: () => false);
    var cancel = false;
    final f = slot.acquire(cancelled: () => cancel);
    cancel = true;
    slot.release(t1);
    expect(await f, isNull);
    expect(slot.busy, false);
  });

  test('重複 release 與非持有者 release 無效', () async {
    final slot = PlayerSlot();
    final t1 = await slot.acquire(cancelled: () => false);
    slot.release(Object());
    expect(slot.busy, true);
    slot.release(t1);
    expect(slot.busy, false);
    final t2 = await slot.acquire(cancelled: () => false);
    slot.release(t1); // 舊 token 不得釋放新持有者
    expect(slot.busy, true);
    slot.release(t2);
    expect(slot.busy, false);
  });

  test('maxWait 逾時強制取得', () async {
    final slot = PlayerSlot();
    final t1 = await slot.acquire(cancelled: () => false);
    final t2 = await slot.acquire(
      cancelled: () => false,
      maxWait: const Duration(milliseconds: 50),
    );
    expect(t2, isNotNull);
    expect(identical(t1, t2), false);
    slot.release(t1); // 舊持有者已失效
    expect(slot.busy, true);
    slot.release(t2);
    expect(slot.busy, false);
  });
}
