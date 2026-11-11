// This is a generated file - do not edit.
//
// Generated from bilibili/community/service/dm/v1.proto.
//
// 精簡版：只保留 DmView 需要的 DmViewReq／DmViewReply／VideoSubtitle／
// SubtitleItem；DmViewReply 其餘欄位由 protobuf 當未知欄位略過。
// 欄位編號取自 PiliPlus 的 v1.pb.dart。

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

class SubtitleType extends $pb.ProtobufEnum {
  static const SubtitleType CC = SubtitleType._(0, _omitEnumNames ? '' : 'CC');
  static const SubtitleType AI = SubtitleType._(1, _omitEnumNames ? '' : 'AI');

  static const $core.List<SubtitleType> values = <SubtitleType>[CC, AI];

  static final $core.List<SubtitleType?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 1);
  static SubtitleType? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const SubtitleType._(super.value, super.name);
}

const $core.bool _omitEnumNames = $core.bool.fromEnvironment(
  'protobuf.omit_enum_names',
);

class DmViewReq extends $pb.GeneratedMessage {
  factory DmViewReq({
    $fixnum.Int64? pid,
    $fixnum.Int64? oid,
    $core.int? type,
    $core.String? spmid,
    $core.int? isHardBoot,
    $core.String? contextExt,
  }) {
    final result = DmViewReq._();
    if (pid != null) result.pid = pid;
    if (oid != null) result.oid = oid;
    if (type != null) result.type = type;
    if (spmid != null) result.spmid = spmid;
    if (isHardBoot != null) result.isHardBoot = isHardBoot;
    if (contextExt != null) result.contextExt = contextExt;
    return result;
  }

  DmViewReq._();

  factory DmViewReq.fromBuffer(
    $core.List<$core.int> data, [
    $pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY,
  ]) =>
      DmViewReq()..mergeFromBuffer(data, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
    _omitMessageNames ? '' : 'DmViewReq',
    package: const $pb.PackageName(
      _omitMessageNames ? '' : 'bilibili.community.service.dm.v1',
    ),
    createEmptyInstance: DmViewReq.$_createMessage,
  )
    ..aInt64(1, _omitFieldNames ? '' : 'pid')
    ..aInt64(2, _omitFieldNames ? '' : 'oid')
    ..aI(3, _omitFieldNames ? '' : 'type')
    ..aOS(4, _omitFieldNames ? '' : 'spmid')
    ..aI(5, _omitFieldNames ? '' : 'isHardBoot')
    ..aOS(6, _omitFieldNames ? '' : 'contextExt')
    ..hasRequiredFields = false;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DmViewReq clone() => deepCopy();

  static DmViewReq $_createMessage() => DmViewReq._();
  @$core.override
  DmViewReq createEmptyInstance() => DmViewReq._();
  static DmViewReq getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DmViewReq>(DmViewReq.$_createMessage);
  static DmViewReq? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get pid => $_getI64(0);
  @$pb.TagNumber(1)
  set pid($fixnum.Int64 value) => $_setInt64(0, value);

  @$pb.TagNumber(2)
  $fixnum.Int64 get oid => $_getI64(1);
  @$pb.TagNumber(2)
  set oid($fixnum.Int64 value) => $_setInt64(1, value);

  @$pb.TagNumber(3)
  $core.int get type => $_getIZ(2);
  @$pb.TagNumber(3)
  set type($core.int value) => $_setSignedInt32(2, value);

  @$pb.TagNumber(4)
  $core.String get spmid => $_getSZ(3);
  @$pb.TagNumber(4)
  set spmid($core.String value) => $_setString(3, value);

  @$pb.TagNumber(5)
  $core.int get isHardBoot => $_getIZ(4);
  @$pb.TagNumber(5)
  set isHardBoot($core.int value) => $_setSignedInt32(4, value);

  @$pb.TagNumber(6)
  $core.String get contextExt => $_getSZ(5);
  @$pb.TagNumber(6)
  set contextExt($core.String value) => $_setString(5, value);
}

class DmViewReply extends $pb.GeneratedMessage {
  factory DmViewReply({VideoSubtitle? subtitle}) {
    final result = DmViewReply._();
    if (subtitle != null) result.subtitle = subtitle;
    return result;
  }

  DmViewReply._();

  factory DmViewReply.fromBuffer(
    $core.List<$core.int> data, [
    $pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY,
  ]) =>
      DmViewReply()..mergeFromBuffer(data, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
    _omitMessageNames ? '' : 'DmViewReply',
    package: const $pb.PackageName(
      _omitMessageNames ? '' : 'bilibili.community.service.dm.v1',
    ),
    createEmptyInstance: DmViewReply.$_createMessage,
  )
    ..aOM<VideoSubtitle>(
      3,
      _omitFieldNames ? '' : 'subtitle',
      subBuilder: VideoSubtitle.$_createMessage,
    )
    ..hasRequiredFields = false;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DmViewReply clone() => deepCopy();

  static DmViewReply $_createMessage() => DmViewReply._();
  @$core.override
  DmViewReply createEmptyInstance() => DmViewReply._();
  static DmViewReply getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DmViewReply>(
        DmViewReply.$_createMessage,
      );
  static DmViewReply? _defaultInstance;

  @$pb.TagNumber(3)
  VideoSubtitle get subtitle => $_getN(0);
  @$pb.TagNumber(3)
  set subtitle(VideoSubtitle value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasSubtitle() => $_has(0);
  @$pb.TagNumber(3)
  VideoSubtitle ensureSubtitle() => $_ensure(0);
}

class VideoSubtitle extends $pb.GeneratedMessage {
  factory VideoSubtitle({
    $core.String? lan,
    $core.String? lanDoc,
    $core.Iterable<SubtitleItem>? subtitles,
  }) {
    final result = VideoSubtitle._();
    if (lan != null) result.lan = lan;
    if (lanDoc != null) result.lanDoc = lanDoc;
    if (subtitles != null) result.subtitles.addAll(subtitles);
    return result;
  }

  VideoSubtitle._();

  factory VideoSubtitle.fromBuffer(
    $core.List<$core.int> data, [
    $pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY,
  ]) =>
      VideoSubtitle()..mergeFromBuffer(data, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
    _omitMessageNames ? '' : 'VideoSubtitle',
    package: const $pb.PackageName(
      _omitMessageNames ? '' : 'bilibili.community.service.dm.v1',
    ),
    createEmptyInstance: VideoSubtitle.$_createMessage,
  )
    ..aOS(1, _omitFieldNames ? '' : 'lan')
    ..aOS(2, _omitFieldNames ? '' : 'lanDoc')
    ..pPM<SubtitleItem>(
      3,
      _omitFieldNames ? '' : 'subtitles',
      subBuilder: SubtitleItem.$_createMessage,
    )
    ..hasRequiredFields = false;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VideoSubtitle clone() => deepCopy();

  static VideoSubtitle $_createMessage() => VideoSubtitle._();
  @$core.override
  VideoSubtitle createEmptyInstance() => VideoSubtitle._();
  static VideoSubtitle getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<VideoSubtitle>(
        VideoSubtitle.$_createMessage,
      );
  static VideoSubtitle? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get lan => $_getSZ(0);
  @$pb.TagNumber(1)
  set lan($core.String value) => $_setString(0, value);

  @$pb.TagNumber(2)
  $core.String get lanDoc => $_getSZ(1);
  @$pb.TagNumber(2)
  set lanDoc($core.String value) => $_setString(1, value);

  @$pb.TagNumber(3)
  $pb.PbList<SubtitleItem> get subtitles => $_getList(2);
}

class SubtitleItem extends $pb.GeneratedMessage {
  factory SubtitleItem({
    $fixnum.Int64? id,
    $core.String? idStr,
    $core.String? lan,
    $core.String? lanDoc,
    $core.String? subtitleUrl,
    SubtitleType? type,
  }) {
    final result = SubtitleItem._();
    if (id != null) result.id = id;
    if (idStr != null) result.idStr = idStr;
    if (lan != null) result.lan = lan;
    if (lanDoc != null) result.lanDoc = lanDoc;
    if (subtitleUrl != null) result.subtitleUrl = subtitleUrl;
    if (type != null) result.type = type;
    return result;
  }

  SubtitleItem._();

  factory SubtitleItem.fromBuffer(
    $core.List<$core.int> data, [
    $pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY,
  ]) =>
      SubtitleItem()..mergeFromBuffer(data, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
    _omitMessageNames ? '' : 'SubtitleItem',
    package: const $pb.PackageName(
      _omitMessageNames ? '' : 'bilibili.community.service.dm.v1',
    ),
    createEmptyInstance: SubtitleItem.$_createMessage,
  )
    ..aInt64(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'idStr')
    ..aOS(3, _omitFieldNames ? '' : 'lan')
    ..aOS(4, _omitFieldNames ? '' : 'lanDoc')
    ..aOS(5, _omitFieldNames ? '' : 'subtitleUrl')
    ..aE<SubtitleType>(
      7,
      _omitFieldNames ? '' : 'type',
      enumValues: SubtitleType.values,
    )
    ..hasRequiredFields = false;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SubtitleItem clone() => deepCopy();

  static SubtitleItem $_createMessage() => SubtitleItem._();
  @$core.override
  SubtitleItem createEmptyInstance() => SubtitleItem._();
  static SubtitleItem getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SubtitleItem>(
        SubtitleItem.$_createMessage,
      );
  static SubtitleItem? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get id => $_getI64(0);
  @$pb.TagNumber(1)
  set id($fixnum.Int64 value) => $_setInt64(0, value);

  @$pb.TagNumber(2)
  $core.String get idStr => $_getSZ(1);
  @$pb.TagNumber(2)
  set idStr($core.String value) => $_setString(1, value);

  @$pb.TagNumber(3)
  $core.String get lan => $_getSZ(2);
  @$pb.TagNumber(3)
  set lan($core.String value) => $_setString(2, value);

  @$pb.TagNumber(4)
  $core.String get lanDoc => $_getSZ(3);
  @$pb.TagNumber(4)
  set lanDoc($core.String value) => $_setString(3, value);

  @$pb.TagNumber(5)
  $core.String get subtitleUrl => $_getSZ(4);
  @$pb.TagNumber(5)
  set subtitleUrl($core.String value) => $_setString(4, value);

  @$pb.TagNumber(7)
  SubtitleType get type => $_getN(5);
  @$pb.TagNumber(7)
  set type(SubtitleType value) => $_setField(7, value);
}

const $core.bool _omitFieldNames = $core.bool.fromEnvironment(
  'protobuf.omit_field_names',
);
const $core.bool _omitMessageNames = $core.bool.fromEnvironment(
  'protobuf.omit_message_names',
);
