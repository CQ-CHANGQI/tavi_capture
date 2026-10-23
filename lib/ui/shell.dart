import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/app_state.dart';
import '../core/models.dart';
import '../core/scope.dart';
import '../core/theme.dart';
import '../router/app_routes.dart';
import '../screens/modals.dart';

/// 所有页面共用的外壳：顶栏 + 当前路由页面 + 弹层 + toast。
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (app.modal != null) {
          if (app.recoverKind == 'drop') {
            app.resolveDrop(false);
          } else {
            app.closeModal();
          }
        }
        // 三个模式页不给系统返回键。
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  TopBar(location: location),
                  Expanded(child: child),
                ],
              ),
              ModalHost(),
              const ToastView(),
            ],
          ),
        ),
      ),
    );
  }
}

class TopBar extends StatelessWidget {
  const TopBar({super.key, required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final mode = AppRoutes.modeOf(location) ?? app.mode;
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: const BoxDecoration(
        color: C.topBar,
        border: Border(bottom: BorderSide(color: C.line)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 900;
          return Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xff1677ff),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'T',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              if (!compact) ...[
                const Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tavi Capture',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      '端侧数据采集',
                      style: TextStyle(fontSize: 13, color: C.muted),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ModeTabs(app: app, current: mode),
                      const SizedBox(width: 12),
                      ..._chips(app, mode),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AppButton(
                '设置',
                kind: BtnKind.ghost,
                height: 36,
                fontSize: 14,
                onPressed: () => app.openModal(ModalKind.settings),
              ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _chips(AppState app, PageMode mode) {
    if (!app.robotOk) {
      return [
        _ChipTap(
          onTap: () => app.openModal(ModalKind.settings),
          child: const StatusChip('未连接机器人 · 点击设置', tone: ChipTone.bad),
        ),
      ];
    }

    final chips = <Widget>[
      if (mode == PageMode.collect) ...[
        _tone(app.vrOk, 'VR'),
        _tone(app.gripperOk, '夹爪'),
      ],
      _tone(app.armServiceOk, '双臂'),
      if (mode == PageMode.collect) _tone(app.camOk, '相机'),
      _tone(app.baseServiceOk, '底盘'),
      StatusChip(
        app.storageText,
        tone: switch (app.storageLevel) {
          StorageLevel.ok => ChipTone.ok,
          StorageLevel.warn => ChipTone.warn,
          StorageLevel.low => ChipTone.bad,
        },
        tooltip: '机载存储 · ${app.storageText}',
      ),
    ];
    return [
      for (var i = 0; i < chips.length; i++) ...[
        if (i > 0) const SizedBox(width: 6),
        chips[i],
      ],
    ];
  }

  Widget _tone(bool ok, String label) => StatusChip(
    label,
    tone: ok ? ChipTone.ok : ChipTone.off,
    tooltip: '$label · ${ok ? '已就绪' : '未启动'}',
  );
}

class _ModeTabs extends StatelessWidget {
  const _ModeTabs({required this.app, required this.current});

  final AppState app;
  final PageMode current;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: C.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < PageMode.values.length; i++) ...[
            if (i > 0) const VerticalDivider(width: 1, color: C.line),
            _tab(context, PageMode.values[i]),
          ],
        ],
      ),
    );
  }

  Widget _tab(BuildContext context, PageMode mode) {
    final inactive = app.recording || !app.robotOk;
    final active = app.robotOk && !inactive && current == mode;
    return InkWell(
      onTap: inactive
          ? null
          : () async {
              final switched = await app.switchMode(mode);
              if (!context.mounted) return;
              if (switched) {
                context.go(AppRoutes.forMode(mode));
              } else if (app.mode == PageMode.review &&
                  current != PageMode.review) {
                context.go(AppRoutes.review);
              }
            },
      borderRadius: BorderRadius.circular(7),
      child: Opacity(
        opacity: inactive ? 0.45 : 1,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          color: active ? C.brand : Colors.transparent,
          child: Text(
            mode.label,
            style: TextStyle(
              fontSize: 15,
              color: active ? Colors.white : C.muted,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

class _ChipTap extends StatelessWidget {
  const _ChipTap({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(99),
    child: child,
  );
}

class ToastView extends StatelessWidget {
  const ToastView({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final message = app.toastMessage;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 22,
      child: IgnorePointer(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          child: message == null
              ? const SizedBox.shrink()
              : Container(
                  key: ValueKey(message),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xff10291c),
                    border: Border.all(color: const Color(0xff246243)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    message,
                    style: const TextStyle(
                      fontSize: 15,
                      color: Color(0xffb7ebc9),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
