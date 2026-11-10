import 'package:bili_tv_app/models/play_repeat.dart';
import 'package:bili_tv_app/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

PlayRepeat _r({String? name, int? idx, bool? auto, int? cd}) =>
    PlayRepeat.resolve(
      name: name,
      legacyIndex: idx,
      legacyAutoPlay: auto,
      countdown: cd,
    ).mode;

void main() {
  group('PlayRepeat.resolve 轉換表', () {
    test('舊 pause(0) -> pause', () {
      expect(_r(idx: 0, cd: 5), PlayRepeat.pause);
      expect(_r(idx: 0, cd: 0), PlayRepeat.pause);
    });
    test('舊 singleCycle(2) -> singleCycle', () {
      expect(_r(idx: 2), PlayRepeat.singleCycle);
    });
    test('舊 listCycle(3) -> listCycle', () {
      expect(_r(idx: 3), PlayRepeat.listCycle);
    });
    test('舊 listOrder(1) + 倒數 0 -> playNext', () {
      expect(_r(idx: 1, cd: 0), PlayRepeat.playNext);
    });
    test('舊 listOrder(1) + 倒數 >0 -> countdownNext', () {
      expect(_r(idx: 1, cd: 5), PlayRepeat.countdownNext);
      expect(_r(idx: 1, cd: 15), PlayRepeat.countdownNext);
    });
    test('舊 autoPlayRelated(4) + 倒數 0 -> playNext', () {
      expect(_r(idx: 4, cd: 0), PlayRepeat.playNext);
    });
    test('舊 autoPlayRelated(4) + 倒數 >0 -> countdownNext', () {
      expect(_r(idx: 4, cd: 3), PlayRepeat.countdownNext);
    });
    test('倒數未設定視為預設 5 秒 -> countdownNext', () {
      expect(_r(idx: 1), PlayRepeat.countdownNext);
      expect(_r(idx: 4), PlayRepeat.countdownNext);
    });
    test('新 key 優先於舊值', () {
      expect(_r(name: 'singleCycle', idx: 0, cd: 0), PlayRepeat.singleCycle);
      expect(_r(name: 'playNext', idx: 3), PlayRepeat.playNext);
    });
    test('新 key 無法辨識時退回舊值', () {
      expect(_r(name: 'bogus', idx: 3), PlayRepeat.listCycle);
    });
    test('只有舊 auto_play：false -> pause，true／無 -> countdownNext', () {
      expect(_r(auto: false), PlayRepeat.pause);
      expect(_r(auto: true), PlayRepeat.countdownNext);
      expect(_r(), PlayRepeat.countdownNext);
    });
    test('舊 index 超出範圍時當作沒有舊值', () {
      expect(_r(idx: 9), PlayRepeat.countdownNext);
      expect(_r(idx: -1, auto: false), PlayRepeat.pause);
    });
    test('fromLegacy 只在由 play_repeat 轉換時為 true', () {
      expect(PlayRepeat.resolve(legacyIndex: 3).fromLegacy, isTrue);
      expect(
        PlayRepeat.resolve(name: 'pause', legacyIndex: 3).fromLegacy,
        isFalse,
      );
      expect(PlayRepeat.resolve(legacyAutoPlay: false).fromLegacy, isFalse);
    });
  });

  group('SettingsService', () {
    Future<SharedPreferences> setup(Map<String, Object> values) async {
      SharedPreferences.setMockInitialValues(values);
      final p = await SharedPreferences.getInstance();
      SettingsService.debugSetPrefs(p);
      return p;
    }

    tearDown(() => SettingsService.debugSetPrefs(null));

    test('舊 listOrder + 倒數 0 -> playNext，並寫回新 key', () async {
      final p = await setup({'play_repeat': 1, 'up_next_countdown': 0});
      expect(SettingsService.playRepeat, PlayRepeat.playNext);
      expect(p.getString('play_end_mode'), 'playNext');
      // 倒數 0 正規化為 5
      expect(SettingsService.upNextCountdown, 5);
    });

    test('舊 play_repeat 轉換後，改倒數不影響結果', () async {
      await setup({'play_repeat': 4, 'up_next_countdown': 10});
      expect(SettingsService.playRepeat, PlayRepeat.countdownNext);
      await SettingsService.setUpNextCountdown(15);
      expect(SettingsService.playRepeat, PlayRepeat.countdownNext);
    });

    test('寫入後讀回，存的是名稱', () async {
      final p = await setup({});
      await SettingsService.setPlayRepeat(PlayRepeat.listCycle);
      expect(p.getString('play_end_mode'), 'listCycle');
      expect(SettingsService.playRepeat, PlayRepeat.listCycle);
    });

    test('什麼都沒設定 -> countdownNext', () async {
      await setup({});
      expect(SettingsService.playRepeat, PlayRepeat.countdownNext);
    });

    test('倒數選項不含 0；讀到 0 當作 5', () async {
      await setup({'up_next_countdown': 0});
      expect(SettingsService.upNextCountdownOptions, [3, 5, 10, 15]);
      expect(SettingsService.upNextCountdown, 5);
    });
  });
}
