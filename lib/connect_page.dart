import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'connect_state.dart';
import 'services/ping_service.dart';
import 'widgets/ip_input.dart';
import 'widgets/top_bar.dart';

/// ping 一个 IP：返回 null 表示通，返回字符串表示失败原因。
///
/// 抽成函数类型是为了测试时可以传假实现，不用真的联网。
typedef PingCheck = Future<String?> Function(String ip);

/// 首屏：连接机器人。
/// 点“重新连接”会真的去 ping 输入的 IP。
class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key, this.ping = PingService.ping});

  final PingCheck ping;

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  // 还没做 IP 持久化，先把原型里的默认地址写死；等做设置页再存本地。
  String _ip = '192.168.1.21';
  ConnectState _state = ConnectState.failed;
  String? _error = '还没有连接机器人。填好 IP 后点「重新连接」，会 ping 这个地址。';

  bool get _ipValid {
    final parts = _ip.split('.');
    return parts.length == 4 &&
        parts.every((part) {
          final value = int.tryParse(part);
          return value != null && value >= 0 && value <= 255;
        });
  }

  Future<void> _connect() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final ip = _ip;

    if (!_ipValid) {
      setState(() {
        _state = ConnectState.failed;
        _error = 'IP 地址格式不正确。四段都要填写，每段 0–255。';
      });
      return;
    }

    setState(() {
      _state = ConnectState.connecting;
      _error = null;
    });

    // 真的去 ping。返回 null 表示通，返回字符串表示失败原因。
    // 以后换成机器人的健康检查接口时，只改 PingService 或这里注入的函数。
    String? error;
    try {
      error = await widget.ping(ip);
    } catch (e) {
      // 万一实现里抛异常，也要回到失败态，不能一直卡在“连接中”。
      error = 'ping $ip 时出错：$e';
    }

    if (!mounted) {
      return; // 异步回来时页面可能已经关了。
    }

    setState(() {
      if (error == null) {
        _state = ConnectState.connected;
      } else {
        _state = ConnectState.failed;
        _error = error;
      }
    });
  }

  void _todo(String name) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$name页面还没做'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  String get _title {
    if (_state == ConnectState.connected) {
      return '机器人已连接';
    }
    if (_state == ConnectState.connecting) {
      return '正在连接';
    }
    return '无法连接机器人';
  }

  String get _description {
    if (_state == ConnectState.connected) {
      return 'ping 通了。登录和首页还没做，先停在这一页验证连接。';
    }
    if (_state == ConnectState.connecting) {
      return '正在 ping $_ip，最多等 1 秒。连上之前顶栏不展示设备状态。';
    }
    return '点「重新连接」会先 ping 这个 IP，ping 通就算连接成功。连上之前顶栏不展示 VR / 相机 / 底盘。';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            TopBar(
              state: _state,
              onSettings: () => _todo('设置'),
              onDevices: _state == ConnectState.connected
                  ? () => _todo('设备状态')
                  : null,
              onMove: _state == ConnectState.connected
                  ? () => _todo('底盘移动')
                  : null,
              onLogin: () => _todo('登录'),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 900;
                  final padding = wide ? 36.0 : 20.0;
                  final minHeight = constraints.maxHeight - padding * 2;

                  return SingleChildScrollView(
                    padding: EdgeInsets.all(padding),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: minHeight > 0 ? minHeight : 0,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1000),
                          child: wide ? _wideLayout() : _narrowLayout(),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 平板/桌面：左边标题，右边卡片，和原型一致。
  Widget _wideLayout() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 360, child: _headline()),
        const SizedBox(width: 48),
        SizedBox(width: 420, child: _connectCard()),
      ],
    );
  }

  /// 手机/窄窗口：上下排，避免横向溢出。
  Widget _narrowLayout() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: _headline(),
        ),
        const SizedBox(height: 24),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SizedBox(width: double.infinity, child: _connectCard()),
        ),
      ],
    );
  }

  Widget _headline() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _title,
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: AppColors.ink,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _description,
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.muted,
            height: 1.6,
          ),
        ),
      ],
    );
  }

  Widget _connectCard() {
    final connecting = _state == ConnectState.connecting;
    final connected = _state == ConnectState.connected;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.panel,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '机器人 IP',
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          const SizedBox(height: 6),
          IpInput(
            initialIp: _ip,
            enabled: !connecting,
            onChanged: (ip) => _ip = ip,
            onSubmitted: _connect,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: FilledButton(
              onPressed: connecting ? null : _connect,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brand,
                disabledBackgroundColor: const Color(0x663B82C4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                connecting
                    ? '正在连接…'
                    : connected
                    ? '保存并连接'
                    : '重新连接',
                style: const TextStyle(fontSize: 15),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _statusBox(),
        ],
      ),
    );
  }

  Widget _statusBox() {
    if (_state == ConnectState.connecting) {
      return _box(
        color: AppColors.input,
        borderColor: AppColors.line,
        child: Text(
          '正在连接 $_ip …',
          style: const TextStyle(fontSize: 13, color: Color(0xFFD5E2EF)),
        ),
      );
    }

    if (_state == ConnectState.connected) {
      return _box(
        color: const Color(0xFF10291C),
        borderColor: const Color(0xFF246243),
        child: Text(
          '已连接 $_ip',
          style: const TextStyle(fontSize: 13, color: Color(0xFFB7EBC9)),
        ),
      );
    }

    return _box(
      color: AppColors.badBg,
      borderColor: AppColors.badLine,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '连不上 $_ip',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Color(0xFFFFB4AE),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _error ?? '',
            style: const TextStyle(
              fontSize: 13,
              height: 1.55,
              color: AppColors.badInk,
            ),
          ),
        ],
      ),
    );
  }

  Widget _box({
    required Color color,
    required Color borderColor,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}
