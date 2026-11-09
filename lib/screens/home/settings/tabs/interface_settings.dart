import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:flutter/services.dart';
import '../../../../services/settings_service.dart';
import '../../../../core/focus/focus_navigation.dart';
import '../widgets/setting_toggle_row.dart';
import '../widgets/setting_dropdown_row.dart';
import '../../../../utils/app_restart.dart';
import '../../../../services/card_preview_service.dart';

class InterfaceSettings extends StatefulWidget {
  final VoidCallback onMoveUp;
  final FocusNode? sidebarFocusNode;

  const InterfaceSettings({
    super.key,
    required this.onMoveUp,
    this.sidebarFocusNode,
  });

  @override
  State<InterfaceSettings> createState() => _InterfaceSettingsState();
}

class _InterfaceSettingsState extends State<InterfaceSettings> {
  // 分區排序相關
  List<String> _categoryOrder = [];
  int _selectedCategoryOrderIndex = 0;
  bool _isDragging = false;
  late List<FocusNode> _categoryOrderFocusNodes;
  late List<FocusNode> _categoryToggleFocusNodes; // 分區開關焦點

  // 直播分區排序相關
  List<String> _liveCategoryOrder = [];
  int _selectedLiveCategoryOrderIndex = 0;
  bool _isLiveDragging = false;
  late List<FocusNode> _liveCategoryOrderFocusNodes;
  late List<FocusNode> _liveCategoryToggleFocusNodes;

  static const categoryLabels = {
    'recommend': '推薦',
    'popular': '熱門',
    'anime': '番劇',
    'movie': '影視',
    'game': '遊戲',
    'knowledge': '知識',
    'tech': '科技',
    'music': '音樂',
    'dance': '舞蹈',
    'life': '生活',
    'food': '美食',
    'douga': '動畫',
  };

  @override
  void initState() {
    super.initState();
    _loadCategoryOrder();
  }

  @override
  void dispose() {
    for (var node in _categoryOrderFocusNodes) {
      node.dispose();
    }
    for (var node in _categoryToggleFocusNodes) {
      node.dispose();
    }
    for (var node in _liveCategoryOrderFocusNodes) {
      node.dispose();
    }
    for (var node in _liveCategoryToggleFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _loadCategoryOrder() {
    _categoryOrder = SettingsService.categoryOrder;
    _categoryOrderFocusNodes = List.generate(
      _categoryOrder.length,
      (_) => FocusNode(),
    );
    _categoryToggleFocusNodes = List.generate(
      _categoryOrder.length,
      (_) => FocusNode(),
    );

    _liveCategoryOrder = SettingsService.liveCategoryOrder;
    _liveCategoryOrderFocusNodes = List.generate(
      _liveCategoryOrder.length,
      (_) => FocusNode(),
    );
    _liveCategoryToggleFocusNodes = List.generate(
      _liveCategoryOrder.length,
      (_) => FocusNode(),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 獲取啟用的分區 (用於排序)
    final enabledOrder = _categoryOrder
        .where((name) => SettingsService.isCategoryEnabled(name))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 啟動動畫開關
        SettingToggleRow(
          label: '啟動動畫',
          subtitle: '啟動應用時顯示動畫，關閉則直接進入主頁',
          value: SettingsService.splashAnimationEnabled,
          isFirst: true, // 第一項，向上返回分類標籤
          onMoveUp: widget.onMoveUp,
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (value) async {
            await SettingsService.setSplashAnimationEnabled(value);
            setState(() {});
          },
        ),
        const SizedBox(height: 16),
        // 播放器時間顯示開關
        SettingToggleRow(
          label: '總是顯示時間',
          subtitle: '播放介面右上角總是顯示當前時間',
          value: SettingsService.alwaysShowPlayerTime,
          autofocus: false,
          onMoveUp: null, // 允許自然向上導航到上一項
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (value) async {
            await SettingsService.setAlwaysShowPlayerTime(value);
            setState(() {});
          },
        ),
        const SizedBox(height: 16),
        // 影片卡片預覽開關
        SettingToggleRow(
          label: '影片卡片預覽',
          subtitle: '游標停在影片卡片上 1 秒，靜音預覽 10 秒',
          value: SettingsService.cardPreview,
          autofocus: false,
          onMoveUp: null,
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (value) async {
            await SettingsService.setCardPreview(value);
            if (!value) CardPreviewService.instance.stopAll();
            setState(() {});
          },
        ),
        const SizedBox(height: 16),
        // 語言（0 跟隨系統、1 繁體中文、2 簡體中文）
        SettingDropdownRow<int>(
          label: '語言',
          subtitle: '切換繁體或簡體中文，重新啟動後生效',
          value: SettingsService.appLanguage,
          items: const [0, 1, 2],
          itemLabel: (v) => switch (v) {
            1 => '繁體中文',
            2 => '簡體中文',
            _ => '跟隨系統',
          },
          onMoveUp: null,
          sidebarFocusNode: widget.sidebarFocusNode,
          onChanged: (value) async {
            if (value == null || value == SettingsService.appLanguage) return;
            await SettingsService.setAppLanguage(value);
            if (!context.mounted) return;
            setState(() {});
            await AppRestart.ask(context);
          },
        ),
        const SizedBox(height: 16),

        // 分區開關
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Text(
                '分區開關 (確認鍵切換)',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 12),
              _buildRestartHint(),
            ],
          ),
        ),
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _categoryOrder.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final catName = _categoryOrder[index];
              final label = categoryLabels[catName] ?? catName;
              final isEnabled = SettingsService.isCategoryEnabled(catName);

              return TvFocusScope(
                pattern: FocusPattern.horizontal,
                focusNode: _categoryToggleFocusNodes[index],
                isFirst: index == 0,
                isLast: index == _categoryOrder.length - 1,
                exitLeft: widget.sidebarFocusNode,
                onSelect: () {
                  SettingsService.toggleCategory(catName, !isEnabled);
                  setState(() {});
                },
                child: Builder(
                  builder: (context) {
                    final focused = Focus.of(context).hasFocus;
                    return Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: isEnabled
                            ? const Color(0xFFfb7299).withValues(alpha: 0.3)
                            : Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: focused
                              ? Colors.white
                              : isEnabled
                              ? const Color(0xFFfb7299)
                              : Colors.transparent,
                          width: focused ? 2 : 1,
                        ),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          color: isEnabled
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.5),
                          fontSize: 12,
                          fontWeight: focused
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 20),
        // 分區排序標題
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Text(
                '分區排序 (僅顯示已啟用)',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 12),
              _buildRestartHint(),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            _isDragging ? '← → 移動位置，確認鍵固定' : '確認鍵選中，← → 移動',
            style: TextStyle(
              color: _isDragging
                  ? const Color(0xFFfb7299)
                  : Colors.white.withValues(alpha: 0.5),
              fontSize: 12,
            ),
          ),
        ),
        SizedBox(
          height: 36,
          child: enabledOrder.isEmpty
              ? Center(
                  child: Text(
                    '請至少啟用一個分區',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                )
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: enabledOrder.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final catName = enabledOrder[index];
                    final label = categoryLabels[catName] ?? catName;
                    final isSelected = index == _selectedCategoryOrderIndex;

                    // 確保 focusNode 索引有效
                    final focusNodeIndex = _categoryOrder.indexOf(catName);
                    if (focusNodeIndex < 0 ||
                        focusNodeIndex >= _categoryOrderFocusNodes.length) {
                      return const SizedBox.shrink();
                    }

                    return Focus(
                      focusNode: _categoryOrderFocusNodes[focusNodeIndex],
                      onFocusChange: (focused) {
                        if (focused && !_isDragging) {
                          setState(() => _selectedCategoryOrderIndex = index);
                        }
                      },
                      onKeyEvent: (node, event) {
                        if (event is KeyUpEvent) {
                          return KeyEventResult.ignored;
                        }

                        if (event is KeyDownEvent &&
                            (event.logicalKey == LogicalKeyboardKey.select ||
                                event.logicalKey == LogicalKeyboardKey.enter)) {
                          setState(() => _isDragging = !_isDragging);
                          return KeyEventResult.handled;
                        }

                        // 阻止向下導航
                        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                          return KeyEventResult.handled;
                        }

                        if (_isDragging) {
                          // 在完整的 _categoryOrder 中找到當前位置
                          final fullIndex = _categoryOrder.indexOf(catName);

                          if (event.logicalKey ==
                                  LogicalKeyboardKey.arrowLeft &&
                              index > 0) {
                            // 找到前一個啟用的分區
                            final prevCat = enabledOrder[index - 1];
                            final prevFullIndex = _categoryOrder.indexOf(
                              prevCat,
                            );

                            // 交換
                            setState(() {
                              _categoryOrder[fullIndex] = prevCat;
                              _categoryOrder[prevFullIndex] = catName;
                              _selectedCategoryOrderIndex = index - 1;
                            });
                            SettingsService.setCategoryOrder(_categoryOrder);
                            // 焦點跟隨到新位置
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              _categoryOrderFocusNodes[prevFullIndex]
                                  .requestFocus();
                            });
                            return KeyEventResult.handled;
                          }
                          if (event.logicalKey ==
                                  LogicalKeyboardKey.arrowRight &&
                              index < enabledOrder.length - 1) {
                            // 找到後一個啟用的分區
                            final nextCat = enabledOrder[index + 1];
                            final nextFullIndex = _categoryOrder.indexOf(
                              nextCat,
                            );

                            // 交換
                            setState(() {
                              _categoryOrder[fullIndex] = nextCat;
                              _categoryOrder[nextFullIndex] = catName;
                              _selectedCategoryOrderIndex = index + 1;
                            });
                            SettingsService.setCategoryOrder(_categoryOrder);
                            // 焦點跟隨到新位置
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              _categoryOrderFocusNodes[nextFullIndex]
                                  .requestFocus();
                            });
                            return KeyEventResult.handled;
                          }
                        }

                        // 上鍵跳轉到分區開關區域
                        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                          // 跳到分區開關的對應位置
                          if (index < _categoryToggleFocusNodes.length) {
                            _categoryToggleFocusNodes[index].requestFocus();
                          } else if (_categoryToggleFocusNodes.isNotEmpty) {
                            _categoryToggleFocusNodes.first.requestFocus();
                          }
                          return KeyEventResult.handled;
                        }

                        if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
                            index == 0) {
                          widget.sidebarFocusNode?.requestFocus();
                          return KeyEventResult.handled;
                        }

                        return KeyEventResult.ignored;
                      },
                      child: Builder(
                        builder: (context) {
                          final focused = Focus.of(context).hasFocus;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: _isDragging && isSelected
                                  ? const Color(0xFFfb7299)
                                  : focused
                                  ? Colors.white.withValues(alpha: 0.2)
                                  : Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: focused
                                  ? Border.all(color: Colors.white, width: 2)
                                  : null,
                            ),
                            child: Text(
                              label,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: focused
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
        ), // End of existing ListView
        const SizedBox(height: 32),
        // ==================== 直播分區設定 ====================
        // 直播分區開關
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Text(
                '直播分區開關 (確認鍵切換)',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 12),
              _buildRestartHint(),
            ],
          ),
        ),
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _liveCategoryOrder.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final catKey = _liveCategoryOrder[index];
              final label =
                  SettingsService.liveCategoryLabels[catKey] ?? catKey;
              final isEnabled = SettingsService.isLiveCategoryEnabled(catKey);

              return TvFocusScope(
                pattern: FocusPattern.horizontal,
                focusNode: _liveCategoryToggleFocusNodes[index],
                onSelect: () {
                  SettingsService.toggleLiveCategory(catKey, !isEnabled);
                  setState(() {});
                },
                child: Builder(
                  builder: (context) {
                    final focused = Focus.of(context).hasFocus;
                    return Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: isEnabled
                            ? const Color(0xFFfb7299).withValues(alpha: 0.3)
                            : Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: focused
                              ? Colors.white
                              : isEnabled
                              ? const Color(0xFFfb7299)
                              : Colors.transparent,
                          width: focused ? 2 : 1,
                        ),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          color: isEnabled
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.5),
                          fontSize: 12,
                          fontWeight: focused
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 20),
        // 直播分區排序標題
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Text(
                '直播分區排序 (僅顯示已啟用)',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 12),
              _buildRestartHint(),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            _isLiveDragging ? '← → 移動位置，確認鍵固定' : '確認鍵選中，← → 移動',
            style: TextStyle(
              color: _isLiveDragging
                  ? const Color(0xFFfb7299)
                  : Colors.white.withValues(alpha: 0.5),
              fontSize: 12,
            ),
          ),
        ),
        SizedBox(
          height: 36,
          child:
              _categoryOrder
                  .where((name) => SettingsService.isLiveCategoryEnabled(name))
                  .isEmpty
              ? Center(
                  child: Text(
                    '請至少啟用一個分區',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                )
              : Builder(
                  builder: (context) {
                    final enabledLiveOrder = _liveCategoryOrder
                        .where(
                          (name) => SettingsService.isLiveCategoryEnabled(name),
                        )
                        .toList();
                    return ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: enabledLiveOrder.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final catKey = enabledLiveOrder[index];
                        final label =
                            SettingsService.liveCategoryLabels[catKey] ??
                            catKey;
                        final isSelected =
                            index == _selectedLiveCategoryOrderIndex;

                        // 確保 focusNode 索引有效
                        final focusNodeIndex = _liveCategoryOrder.indexOf(
                          catKey,
                        );
                        if (focusNodeIndex < 0 ||
                            focusNodeIndex >=
                                _liveCategoryOrderFocusNodes.length) {
                          return const SizedBox.shrink();
                        }

                        return Focus(
                          focusNode:
                              _liveCategoryOrderFocusNodes[focusNodeIndex],
                          onFocusChange: (focused) {
                            if (focused && !_isLiveDragging) {
                              setState(
                                () => _selectedLiveCategoryOrderIndex = index,
                              );
                            }
                          },
                          onKeyEvent: (node, event) {
                            if (event is KeyUpEvent) {
                              return KeyEventResult.ignored;
                            }

                            if (event is KeyDownEvent &&
                                (event.logicalKey ==
                                        LogicalKeyboardKey.select ||
                                    event.logicalKey ==
                                        LogicalKeyboardKey.enter)) {
                              setState(
                                () => _isLiveDragging = !_isLiveDragging,
                              );
                              return KeyEventResult.handled;
                            }

                            if (event.logicalKey ==
                                LogicalKeyboardKey.arrowDown) {
                              return KeyEventResult.handled;
                            }

                            if (_isLiveDragging) {
                              final fullIndex = _liveCategoryOrder.indexOf(
                                catKey,
                              );

                              if (event.logicalKey ==
                                      LogicalKeyboardKey.arrowLeft &&
                                  index > 0) {
                                final prevCat = enabledLiveOrder[index - 1];
                                final prevFullIndex = _liveCategoryOrder
                                    .indexOf(prevCat);

                                setState(() {
                                  _liveCategoryOrder[fullIndex] = prevCat;
                                  _liveCategoryOrder[prevFullIndex] = catKey;
                                  _selectedLiveCategoryOrderIndex = index - 1;
                                });
                                SettingsService.setLiveCategoryOrder(
                                  _liveCategoryOrder,
                                );
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
                                  _liveCategoryOrderFocusNodes[prevFullIndex]
                                      .requestFocus();
                                });
                                return KeyEventResult.handled;
                              }
                              if (event.logicalKey ==
                                      LogicalKeyboardKey.arrowRight &&
                                  index < enabledLiveOrder.length - 1) {
                                final nextCat = enabledLiveOrder[index + 1];
                                final nextFullIndex = _liveCategoryOrder
                                    .indexOf(nextCat);

                                setState(() {
                                  _liveCategoryOrder[fullIndex] = nextCat;
                                  _liveCategoryOrder[nextFullIndex] = catKey;
                                  _selectedLiveCategoryOrderIndex = index + 1;
                                });
                                SettingsService.setLiveCategoryOrder(
                                  _liveCategoryOrder,
                                );
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
                                  _liveCategoryOrderFocusNodes[nextFullIndex]
                                      .requestFocus();
                                });
                                return KeyEventResult.handled;
                              }
                            }

                            // 上鍵跳轉到直播分區開關區域
                            if (event.logicalKey ==
                                LogicalKeyboardKey.arrowUp) {
                              // 跳到分區開關的對應位置
                              if (index <
                                  _liveCategoryToggleFocusNodes.length) {
                                _liveCategoryToggleFocusNodes[index]
                                    .requestFocus();
                              } else if (_liveCategoryToggleFocusNodes
                                  .isNotEmpty) {
                                _liveCategoryToggleFocusNodes.first
                                    .requestFocus();
                              }
                              return KeyEventResult.handled;
                            }

                            return KeyEventResult.ignored;
                          },
                          child: Builder(
                            builder: (context) {
                              final focused = Focus.of(context).hasFocus;
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                alignment: Alignment.center,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: _isLiveDragging && isSelected
                                      ? const Color(0xFFfb7299)
                                      : focused
                                      ? Colors.white.withValues(alpha: 0.2)
                                      : Colors.white.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                  border: focused
                                      ? Border.all(
                                          color: Colors.white,
                                          width: 2,
                                        )
                                      : null,
                                ),
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: focused
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildRestartHint() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFfb7299).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.info_outline, color: Color(0xFFfb7299), size: 16),
          const SizedBox(width: 4),
          Text(
            '修改後需重啟APP生效',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
