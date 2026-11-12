/// 目前版本標籤；發佈時以 --dart-define=btr.version=vX.Y.Z-btr.N 覆寫。
const String btrVersion = String.fromEnvironment(
  'btr.version',
  defaultValue: 'v1.2.2-btr.23',
);
