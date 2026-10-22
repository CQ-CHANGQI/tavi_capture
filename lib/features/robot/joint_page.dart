import 'package:flutter/material.dart';

import '../../core/ros/joint_state_feed.dart';
import '../../core/ros/ros_bridge_client.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/modal_panel.dart';
import '../../core/widgets/status_pill.dart';
import '../takes/widgets/joint_chart.dart';

/// 机械臂六轴实时角度，数据来自 rosbridge（默认 ws://机器人IP:9090）。
class JointPage extends StatefulWidget {
  const JointPage({super.key, this.client});

  /// 测试时注入；正常按当前机器人 IP 新建连接。
  final RosBridgeClient? client;

  @override
  State<JointPage> createState() => _JointPageState();
}

class _JointPageState extends State<JointPage> {
  late final RosBridgeClient _client;
  late final JointStateFeed _feed;

  @override
  void initState() {
    super.initState();
    _client =
        widget.client ??
        RosBridgeClient(Uri.parse('ws://${appState.robotIp}:$rosBridgePort'));
    _feed = JointStateFeed(_client)..start();
  }

  @override
  void dispose() {
    _feed.dispose();
    _client.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ModalPanel(
        title: '机械臂 · 实时关节',
        width: 680,
        onClose: () => Navigator.maybePop(context),
        child: AnimatedBuilder(
          animation: _feed,
          builder: (context, _) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _statusRow(),
                const SizedBox(height: 12),
                if (_feed.positions.isEmpty)
                  _emptyHint()
                else
                  for (var i = 0; i < _feed.names.length; i++)
                    _axisRow(i, _feed.degrees[i]),
                const SizedBox(height: 12),
                SizedBox(
                  height: 140,
                  width: double.infinity,
                  child: JointChart(series: _feed.history, progress: 1),
                ),
                if (_client.lastError != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _client.lastError!,
                    style: const TextStyle(fontSize: 12, color: AppColors.bad),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _statusRow() {
    final (text, color) = switch (_feed.status) {
      RosBridgeStatus.open => ('已连接', AppColors.ok),
      RosBridgeStatus.connecting => ('连接中', AppColors.warn),
      RosBridgeStatus.reconnecting => ('重连中', AppColors.warn),
      RosBridgeStatus.idle || RosBridgeStatus.closed => ('未连接', AppColors.muted),
    };
    final stamp = _feed.lastStampNanos;
    final skew = _feed.clockSkewMillis;

    return Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        StatusPill(text: text, color: color),
        Text(
          'ws://${_client.uri.host}:${_client.uri.port}${_feed.topic}',
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
        if (_feed.rateHz > 0)
          Text(
            '${_feed.rateHz.toStringAsFixed(1)} Hz',
            style: const TextStyle(fontSize: 12, color: AppColors.ink),
          ),
        if (stamp != null)
          Text(
            '时钟差 ${skew ?? '—'} ms',
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        if (_feed.revision > 0)
          Text(
            '${_feed.names.length} 轴 · 已收 ${_feed.revision} 帧',
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
      ],
    );
  }

  Widget _emptyHint() {
    final open = _feed.status == RosBridgeStatus.open;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.input,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        open
            ? '已连上 rosbridge，但 ${_feed.topic} 还没消息。用 ros2 topic echo '
                  '${_feed.topic} 确认 topic 名和发布端是否在发。'
            : '正在连接 rosbridge。确认机器人上已启动 rosbridge_websocket，'
                  '端口 ${_client.uri.port} 可达。',
        style: const TextStyle(fontSize: 13, height: 1.5, color: AppColors.muted),
      ),
    );
  }

  Widget _axisRow(int index, double degree) {
    final ratio = ((degree + 180) / 360).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Text(
              'J${index + 1}',
              style: const TextStyle(fontSize: 13, color: AppColors.muted),
            ),
          ),
          Expanded(
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              color: AppColors.brand,
              backgroundColor: AppColors.input,
            ),
          ),
          SizedBox(
            width: 72,
            child: Text(
              '${degree.toStringAsFixed(1)}°',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.ink,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
