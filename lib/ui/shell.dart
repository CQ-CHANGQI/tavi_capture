import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/models.dart';
import '../core/scope.dart';
import '../core/theme.dart';
import '../screens/collect.dart';
import '../screens/done.dart';
import '../screens/home.dart';
import '../screens/library.dart';
import '../screens/modals.dart';
import '../screens/review.dart';
import '../screens/setup.dart';
import '../screens/tasks.dart';

/// 一个 Scaffold + 顶栏 + 当前页面 + 弹层，对应原型的 `.tablet`。
class Shell extends StatelessWidget {
  const Shell({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final page = switch (app.screen) {
      ScreenId.setup => const SetupScreen(),
      ScreenId.home => const HomeScreen(),
      ScreenId.tasks => const TasksScreen(),
      ScreenId.done => const DoneScreen(),
      ScreenId.library => const LibraryScreen(),
      ScreenId.collect => const CollectScreen(),
      ScreenId.review => const ReviewScreen(),
    };
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
          return;
        }
        if (app.screen != ScreenId.home && app.screen != ScreenId.setup) {
          app.go(ScreenId.home);
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  const TopBar(),
                  Expanded(child: page),
                ],
              ),
              const ModalHost(),
              const _ToastView(),
            ],
          ),
        ),
      ),
    );
  }
}

class TopBar extends StatelessWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: const BoxDecoration(
        color: C.topBar,
        border: Border(bottom: BorderSide(color: C.line)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 820;
          final canMove =
              app.robotOk &&
              app.screen != ScreenId.collect &&
              app.screen != ScreenId.library &&
              app.screen != ScreenId.review;
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
              if (!compact)
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
                      '数据采集',
                      style: TextStyle(fontSize: 13, color: C.muted),
                    ),
                  ],
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: _chips(app),
                    ),
                  ),
                ),
              ),
              if (!compact) ...[
                AppButton(
                  '手动控制',
                  kind: BtnKind.ghost,
                  height: 36,
                  fontSize: 14,
                  onPressed: canMove
                      ? () => app.openModal(ModalKind.move)
                      : null,
                ),
                const SizedBox(width: 8),
                AppButton(
                  '设置',
                  kind: BtnKind.ghost,
                  height: 36,
                  fontSize: 14,
                  onPressed: () => app.openModal(ModalKind.settings),
                ),
                const SizedBox(width: 8),
              ] else
                PopupMenuButton<String>(
                  tooltip: '菜单',
                  color: C.panel2,
                  onSelected: (value) {
                    switch (value) {
                      case 'move':
                        app.openModal(ModalKind.move);
                      case 'settings':
                        app.openModal(ModalKind.settings);
                      case 'login':
                        app.openModal(ModalKind.login);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'move',
                      enabled: canMove,
                      child: const Text('手动控制'),
                    ),
                    const PopupMenuItem(value: 'settings', child: Text('设置')),
                    const PopupMenuItem(value: 'login', child: Text('切换账号')),
                  ],
                ),
              _PersonButton(compact: compact),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _chips(AppState app) {
    if (!app.robotOk) {
      return [
        _ChipTap(
          onTap: () => app.openModal(ModalKind.settings),
          child: const StatusChip('未连接机器人 · 点击设置', tone: ChipTone.bad),
        ),
      ];
    }
    final chips = <Widget>[
      if (app.screen == ScreenId.collect) ...[
        StatusChip(
          app.vrOk ? 'VR在线' : 'VR未连接',
          tone: app.vrOk ? ChipTone.ok : ChipTone.bad,
        ),
        StatusChip(
          app.gripperOk ? '夹爪就绪' : '夹爪未连接',
          tone: app.gripperOk ? ChipTone.ok : ChipTone.bad,
        ),
      ],
      StatusChip(
        app.armOk ? '双臂就绪' : '双臂未启动',
        tone: app.armOk ? ChipTone.ok : ChipTone.bad,
      ),
      if (app.screen == ScreenId.collect)
        StatusChip(
          app.camOk ? '相机正常' : '设备异常',
          tone: app.camOk ? ChipTone.ok : ChipTone.bad,
        ),
      StatusChip(
        app.baseOk ? '底盘就绪' : '底盘未启动',
        tone: app.baseOk ? ChipTone.ok : ChipTone.bad,
      ),
      StatusChip(
        app.storageText,
        tone: !app.storageOk
            ? ChipTone.bad
            : app.storageWarn
            ? ChipTone.warn
            : ChipTone.ok,
      ),
    ];
    return [
      for (var i = 0; i < chips.length; i++) ...[
        if (i > 0) const SizedBox(width: 6),
        chips[i],
      ],
    ];
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

class _PersonButton extends StatelessWidget {
  const _PersonButton({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final name = app.currentUser ?? '未登录';
    return InkWell(
      onTap: () {
        if (app.recording) {
          app.toast('采集中不能切换人员');
          return;
        }
        app.openModal(ModalKind.login);
      },
      borderRadius: BorderRadius.circular(99),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: C.panel2,
              child: Text(
                name.characters.last,
                style: const TextStyle(fontSize: 15, color: Colors.white),
              ),
            ),
            if (!compact) ...[
              const SizedBox(width: 8),
              Text(
                name,
                style: const TextStyle(fontSize: 15, color: C.softInk),
              ),
              const Icon(Icons.expand_more, size: 16, color: C.muted),
            ],
          ],
        ),
      ),
    );
  }
}

class _ToastView extends StatelessWidget {
  const _ToastView();

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
