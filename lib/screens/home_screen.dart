import 'package:bili_tv_app/utils/zh_toast.dart';
import 'package:bili_tv_app/widgets/zh_material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:bili_tv_app/models/video.dart';
import 'home/home_tab.dart';
import 'home/history_tab.dart';
import 'home/search_tab.dart';
import 'home/search/search_keyboard_view.dart' show SearchImeBackGuard;
import 'home/profile/profile_tab.dart';
import 'home/settings/settings_view.dart';
import 'home/dynamic_tab.dart';
import 'home/live_tab.dart';
import '../widgets/tv_focusable_item.dart';
import '../services/auth_service.dart';
import '../services/settings_service.dart';
import '../services/update_service.dart';
import '../services/crash_report_service.dart';
import '../widgets/error_report_dialog.dart';

/// 主頁框架 - 完全按照 animeone_tv_app 的方式
class HomeScreen extends StatefulWidget {
  final List<Video>? preloadedVideos;

  const HomeScreen({super.key, this.preloadedVideos});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _selectedTabIndex = 1; // 預設選中首頁
  DateTime? _lastBackPressed;
  DateTime? _backFromSearchHandled; // 防止搜尋鍵盤返回鍵重複處理

  // Tab 順序: 搜尋、首頁、動態、直播、歷史、個人、設定
  final List<String> _tabIcons = [
    'assets/icons/search.svg',
    'assets/icons/home.svg',
    'assets/icons/dynamic.svg',
    'assets/icons/live.svg',
    'assets/icons/history.svg',
    'assets/icons/user.svg',
    'assets/icons/settings.svg',
  ];

  late List<FocusNode> _sideBarFocusNodes;

  // 用於訪問 SearchTab 狀態
  final GlobalKey<SearchTabState> _searchTabKey = GlobalKey<SearchTabState>();
  // 用於訪問 HomeTab 狀態 (重新整理功能)
  final GlobalKey<HomeTabState> _homeTabKey = GlobalKey<HomeTabState>();
  // 動態和歷史記錄 Tab - 每次切換時重新整理
  final GlobalKey<DynamicTabState> _dynamicTabKey =
      GlobalKey<DynamicTabState>();
  final GlobalKey<HistoryTabState> _historyTabKey =
      GlobalKey<HistoryTabState>();
  // 直播、個人、設定 Tab
  final GlobalKey<LiveTabState> _liveTabKey = GlobalKey<LiveTabState>();
  final GlobalKey<ProfileTabState> _profileTabKey =
      GlobalKey<ProfileTabState>();
  final GlobalKey<SettingsViewState> _settingsKey =
      GlobalKey<SettingsViewState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    UpdateService.startAuto();
    _sideBarFocusNodes = List.generate(
      _tabIcons.length,
      (index) => FocusNode(),
    );

    // 可以在這裡做一些初始化，但不再強制請求 sidebar 焦點
    // 而是等待 HomeTab 載入完成後請求內容焦點
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 確保 Highlight 策略正確
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      _checkCrashReport();
    });
  }

  // 檢查上次是否有未確認的閃退紀錄
  void _checkCrashReport() {
    Future.delayed(const Duration(seconds: 2), () async {
      if (!mounted) return;
      final crash = await CrashReportService.lastCrash();
      if (crash == null || !mounted) return;
      final ts = crash['timestamp'];
      try {
        final crashSection = CrashReportService.format(crash);
        await showErrorReportDialog(context, crashSection: crashSection);
      } finally {
        if (ts is num) {
          await CrashReportService.ack(ts.toInt());
        }
      }
    });
  }

  // 啟用焦點系統
  void _activateFocusSystem() {
    if (!mounted) return;

    // 強制設定高亮策略為傳統模式 (TV 模式)
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;

    final currentFocusNode = _sideBarFocusNodes[_selectedTabIndex];
    if (!currentFocusNode.hasFocus) {
      currentFocusNode.requestFocus();
    }

    // 首頁載入完成後，延遲後臺預載入動態和歷史記錄
    _preloadOtherTabs();
  }

  // 後臺預載入動態和歷史記錄
  void _preloadOtherTabs() {
    // 延遲 500ms 後開始預載入，避免影響首頁渲染
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      // 預載入動態頁面（如果使用者已登入）
      if (AuthService.isLoggedIn) {
        _dynamicTabKey.currentState?.refresh();
      }
    });

    // 再延遲 1 秒後預載入歷史記錄
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      // 預載入歷史記錄（如果使用者已登入）
      if (AuthService.isLoggedIn) {
        _historyTabKey.currentState?.refresh();
      }
    });

    // 預載入直播
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (!mounted) return;
      _liveTabKey.currentState?.refresh();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) UpdateService.startAuto();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (var node in _sideBarFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _handleSideBarTap(int index) {
    // 如果已經在當前標籤，點選重新整理
    if (index == _selectedTabIndex) {
      if (index == 1) {
        _homeTabKey.currentState?.refreshCurrentCategory();
      } else if (index == 2) {
        _dynamicTabKey.currentState?.refresh();
      } else if (index == 3) {
        _liveTabKey.currentState?.refresh();
      } else if (index == 4) {
        _historyTabKey.currentState?.refresh();
      } else if (index == 5) {
        _profileTabKey.currentState?.refresh();
      }
      return;
    }

    setState(() => _selectedTabIndex = index);
    _sideBarFocusNodes[index].requestFocus();

    // 動態和歷史記錄、直播標籤: 切換時也重新整理
    if (index == 2) {
      _dynamicTabKey.currentState?.refresh();
    } else if (index == 3) {
      _liveTabKey.currentState?.refresh();
    } else if (index == 4) {
      _historyTabKey.currentState?.refresh();
    }
  }

  void _refreshCurrentTab() {
    setState(() {});
    // 登入後重新載入各分頁；原本只刷新畫面，分頁仍保留登入前的空資料。
    _homeTabKey.currentState?.refreshCurrentCategory();
    _dynamicTabKey.currentState?.refresh();
    _historyTabKey.currentState?.refresh();
    _liveTabKey.currentState?.refresh();
    _profileTabKey.currentState?.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        // 搜尋的系統鍵盤（IME）開啟或剛關閉：返回鍵只用來關閉鍵盤
        if ((_selectedTabIndex == 0 || _selectedTabIndex == 6) &&
            SearchImeBackGuard.shouldSwallowBack()) {
          return;
        }

        // 檢查是否剛剛被搜尋鍵盤的返回鍵處理過
        if (_backFromSearchHandled != null &&
            DateTime.now().difference(_backFromSearchHandled!) <
                const Duration(milliseconds: 200)) {
          return; // 已被處理，忽略
        }

        // 只有在主頁標籤 (index=1) 才顯示退出提示
        // 搜尋標籤需要特殊處理：結果介面返回鍵盤，鍵盤返回主頁
        if (_selectedTabIndex == 0) {
          // 搜尋標籤
          final handled = _searchTabKey.currentState?.handleBack() ?? false;
          if (!handled) {
            // 鍵盤介面 → 回主頁
            setState(() => _selectedTabIndex = 1);
            _sideBarFocusNodes[1].requestFocus();
          }
          return;
        }

        if (_selectedTabIndex == 5 &&
            (_profileTabKey.currentState?.handleBack() ?? false)) {
          // 登入畫面 → 回個人頁
          return;
        }

        if (_selectedTabIndex == 6 &&
            (_settingsKey.currentState?.handleBack() ?? false)) {
          // 設定搜尋 → 回設定分類
          return;
        }

        if (_selectedTabIndex != 1) {
          // 其他標籤（動態、直播、歷史、個人、設定）按返回鍵都回到主頁
          setState(() => _selectedTabIndex = 1);
          _sideBarFocusNodes[1].requestFocus();
          return;
        }

        // 主頁標籤：按兩次退出
        final now = DateTime.now();
        if (_lastBackPressed == null ||
            now.difference(_lastBackPressed!) > const Duration(seconds: 2)) {
          _lastBackPressed = now;

          showZhToast(
            msg: '再按一次返回鍵退出應用',
            toastLength: Toast.LENGTH_SHORT,
            gravity: ToastGravity.CENTER,
            backgroundColor: Colors.black.withValues(alpha: 0.7),
            textColor: Colors.white,
            fontSize: 18.0,
          );
        } else {
          // 退出前清理快取
          await SettingsService.clearImageCache();
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 左側邊欄
            Expanded(
              flex: 8,
              child: Container(
                // 撐滿整個高度：側邊欄外包 SingleChildScrollView 後，
                // 背景色只會跟內容一樣高，底部會露出主畫面底色
                height: double.infinity,
                color: const Color(0xFF1E1E1E),
                padding: const EdgeInsets.only(top: 40),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: List.generate(_tabIcons.length, (index) {
                      final isUserTab = index == 5; // 個人頁（頭像）
                      final isSettingsTab = index == 6;
                      final avatarUrl = isUserTab && AuthService.isLoggedIn
                          ? AuthService.face
                          : null;

                      final item = TvFocusableItem(
                        iconPath: _tabIcons[index],
                        avatarUrl: avatarUrl,
                        isSelected: _selectedTabIndex == index,
                        focusNode: _sideBarFocusNodes[index],
                        onFocus: () {
                          // 焦點移動時只切換標籤頁；歷史分頁另外在背景靜默更新，
                          // 才看得到剛看過的影片（不清空列表、不搶焦點）
                          setState(() => _selectedTabIndex = index);
                          if (index == 4) {
                            _historyTabKey.currentState?.refreshSilently();
                          }
                        },
                        onTap: () => _handleSideBarTap(index), // 按確定鍵才重新整理
                        // 使用者標籤按右鍵導航到設定分類標籤
                        onMoveRight: index == 3
                            ? () {
                                _liveTabKey.currentState?.focusFirstItem();
                              }
                            : isUserTab
                            ? () =>
                                  _profileTabKey.currentState?.focusFirstItem()
                            : isSettingsTab
                            ? () => _settingsKey.currentState
                                  ?.focusFirstCategory()
                            : null,
                      );
                      if (!isSettingsTab) return item;
                      // 設定入口：有新版本時顯示紅點
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          item,
                          Positioned(
                            top: 8,
                            right: 10,
                            child: IgnorePointer(
                              child: ValueListenableBuilder<UpdateInfo?>(
                                valueListenable: UpdateService.available,
                                builder: (_, info, _) => info == null
                                    ? const SizedBox.shrink()
                                    : Container(
                                        width: 10,
                                        height: 10,
                                        decoration: const BoxDecoration(
                                          color: Colors.red,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ],
                      );
                    }),
                  ),
                ),
              ),
            ),
            // 右側內容區
            Expanded(flex: 92, child: _buildRightContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildRightContent() {
    // 使用 IndexedStack 保持所有 Tab 狀態，避免切換時重新載入
    return IndexedStack(
      index: _selectedTabIndex,
      children: [
        // 0: 搜尋
        SearchTab(
          key: _searchTabKey,
          sidebarFocusNode: _sideBarFocusNodes[0],
          onBackToHome: () {
            _backFromSearchHandled = DateTime.now(); // 記錄處理時間
            setState(() => _selectedTabIndex = 1);
            _sideBarFocusNodes[1].requestFocus();
          },
        ),
        // 1: 首頁
        HomeTab(
          key: _homeTabKey,
          sidebarFocusNode: _sideBarFocusNodes[1],
          onFirstLoadComplete: _activateFocusSystem,
          preloadedVideos: widget.preloadedVideos,
        ),
        // 2: 動態
        DynamicTab(
          key: _dynamicTabKey,
          sidebarFocusNode: _sideBarFocusNodes[2],
          isVisible: _selectedTabIndex == 2,
        ),
        // 3: 直播
        LiveTab(
          key: _liveTabKey,
          sidebarFocusNode: _sideBarFocusNodes[3],
          isVisible: _selectedTabIndex == 3,
        ),
        // 4: 歷史
        HistoryTab(
          key: _historyTabKey,
          sidebarFocusNode: _sideBarFocusNodes[4],
          isVisible: _selectedTabIndex == 4,
        ),
        // 5: 個人
        ProfileTab(
          key: _profileTabKey,
          sidebarFocusNode: _sideBarFocusNodes[5],
          isVisible: _selectedTabIndex == 5,
          onLoginSuccess: _refreshCurrentTab,
          onLogout: () async {
            await AuthService.logout();
            if (!mounted) return;
            _refreshCurrentTab();
            setState(() {});
          },
        ),
        // 6: 設定
        SettingsView(
          key: _settingsKey,
          sidebarFocusNode: _sideBarFocusNodes[6],
        ),
      ],
    );
  }
}
