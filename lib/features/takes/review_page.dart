import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/mcap/mcap_frame_loader.dart';
import '../../core/mcap/mcap_http_session.dart';
import '../../core/mcap/mcap_review_index.dart';
import '../../core/models/take.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_page.dart';
import '../../core/widgets/app_panel.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/camera_tile.dart';
import '../../core/widgets/status_pill.dart';
import 'widgets/joint_chart.dart';

/// 数据固定从本地 mock 服务器流式拉取，不再支持本地文件。
const mcapDemoUrl = 'http://192.168.13.4:8090/data.mcap';

/// 回放页：相机 + 双臂关节角 + 播放条。
class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key, required this.take});

  final Take take;

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  double _progress = 0;
  Timer? _timer;
  DateTime? _lastTick;

  McapReviewIndex? _mcap;
  McapFrameLoader? _loader;
  List<List<double>>? _leftSeries;
  List<List<double>>? _rightSeries;
  ui.Image? _leftImage;
  ui.Image? _rightImage;
  int _leftFrameIndex = -1;
  int _rightFrameIndex = -1;
  bool _leftLoading = false;
  bool _rightLoading = false;
  bool _loading = true;
  String? _error;
  int _playhead = 0;

  McapHttpSession? _http;
  bool _downloading = false;
  bool _streamWaiting = false;
  bool _playRequested = false;
  int _loadGeneration = 0;
  int _received = 0;
  int? _total;

  bool get _playing => _timer != null;

  double? get _downloadProgress {
    final total = _total;
    if (total == null || total <= 0) return null;
    return (_received / total).clamp(0.0, 1.0);
  }

  Duration get _duration => _mcap?.duration ?? Duration.zero;

  String get _time {
    final total = _duration.inMilliseconds / 1000;
    final current = _mcap == null
        ? total * _progress
        : ((_playhead - _mcap!.startTime) / 1000000000).clamp(0.0, total);
    return '${_formatClock(current.round())} / ${_formatClock(total.round())}';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadHttp(mcapDemoUrl);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _loader?.close();
    _http?.close();
    _leftImage?.dispose();
    _rightImage?.dispose();
    super.dispose();
  }

  void _stopPlayback() {
    _timer?.cancel();
    _timer = null;
    _lastTick = null;
    _playRequested = false;
    _streamWaiting = false;
    _loader?.close();
    _loader = null;
    _http?.close();
    _http = null;
    final oldLeft = _leftImage;
    final oldRight = _rightImage;
    _leftImage = null;
    _rightImage = null;
    _leftFrameIndex = -1;
    _rightFrameIndex = -1;
    _leftLoading = false;
    _rightLoading = false;
    _downloading = false;
    _received = 0;
    _total = null;
    if (oldLeft != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => oldLeft.dispose());
    }
    if (oldRight != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => oldRight.dispose());
    }
  }

  void _togglePlay() {
    if (_timer != null) {
      _timer!.cancel();
      _playRequested = false;
      _streamWaiting = false;
      setState(() => _timer = null);
      return;
    }

    final index = _mcap;
    if (index == null) return;

    if (_streamWaiting && _playhead >= index.endTime) {
      _playRequested = true;
      showToast(context, '缓冲中，等下载推进');
      return;
    }

    if (_progress >= 1 && !_streamWaiting) {
      _seekTo(0);
    }

    _playRequested = true;
    _streamWaiting = false;
    _lastTick = DateTime.now();
    setState(() {
      _timer = Timer.periodic(const Duration(milliseconds: 33), _tick);
    });
  }

  void _tick(Timer timer) {
    final index = _mcap;
    if (!mounted || index == null) return;
    final now = DateTime.now();
    final delta = now.difference(_lastTick ?? now).inMicroseconds * 1000;
    _lastTick = now;

    var next = _playhead + delta;
    if (next >= index.endTime) {
      if (_http != null && !_http!.isDone) {
        _playhead = index.endTime;
        _progress = _progressAt(_playhead);
        _streamWaiting = true;
        timer.cancel();
        _timer = null;
        setState(() {});
        return;
      }
      next = index.endTime;
      timer.cancel();
      _timer = null;
      _playRequested = false;
    }
    _playhead = next;
    _progress = _progressAt(next);
    _syncFrames();
    setState(() {});
  }

  double _progressAt(int time) {
    final index = _mcap;
    if (index == null) return 0;
    final span = index.endTime - index.startTime;
    if (span <= 0) return 0;
    return ((time - index.startTime) / span).clamp(0.0, 1.0);
  }

  void _seekTo(double value) {
    if (_loading) return;
    final index = _mcap;
    if (index == null) {
      setState(() => _progress = value.clamp(0.0, 1.0));
      return;
    }
    final progress = value.clamp(0.0, 1.0);
    final target =
        index.startTime +
        ((index.endTime - index.startTime) * progress).round();
    _lastTick = DateTime.now();
    _streamWaiting = false;
    setState(() {
      _progress = progress;
      _playhead = target;
    });
    _syncFrames();
  }

  void _syncFrames() {
    final index = _mcap;
    if (index == null || _loader == null) return;

    final left = _frameAt(index.leftFrames, _playhead);
    if (left != _leftFrameIndex) {
      _leftFrameIndex = left;
      if (left >= 0) _loadFrame(left: true, frameIndex: left);
    }

    final right = _frameAt(index.rightFrames, _playhead);
    if (right != _rightFrameIndex) {
      _rightFrameIndex = right;
      if (right >= 0) _loadFrame(left: false, frameIndex: right);
    }
  }

  int _frameAt(List<McapFrameRef> frames, int time) {
    if (frames.isEmpty) return -1;
    var low = 0;
    var high = frames.length - 1;
    var result = 0;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (frames[mid].time <= time) {
        result = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return result;
  }

  Future<void> _loadFrame({required bool left, required int frameIndex}) async {
    final index = _mcap;
    final loader = _loader;
    if (index == null || loader == null) return;
    if (left ? _leftLoading : _rightLoading) return;

    final frames = left ? index.leftFrames : index.rightFrames;
    if (frameIndex < 0 || frameIndex >= frames.length) return;

    if (left) {
      _leftLoading = true;
    } else {
      _rightLoading = true;
    }

    try {
      final image = await loader.load(frames[frameIndex]);
      if (!mounted) {
        image.dispose();
        return;
      }
      final current = left ? _leftFrameIndex : _rightFrameIndex;
      if (current != frameIndex) {
        image.dispose();
        return;
      }
      final old = left ? _leftImage : _rightImage;
      setState(() {
        if (left) {
          _leftImage = image;
        } else {
          _rightImage = image;
        }
      });
      if (old != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      }
    } catch (error) {
      if (mounted) showToast(context, '读帧失败：$error');
    } finally {
      if (left) {
        _leftLoading = false;
      } else {
        _rightLoading = false;
      }
      if (mounted) {
        final current = left ? _leftFrameIndex : _rightFrameIndex;
        if (current != frameIndex) _syncFrames();
      }
    }
  }

  void _applyIndex(McapReviewIndex index) {
    if (!mounted) return;
    if (_mcap == null &&
        index.leftFrames.isEmpty &&
        index.rightFrames.isEmpty &&
        index.leftArm == null &&
        index.rightArm == null) {
      return;
    }
    final first = _mcap == null;
    final playhead = first
        ? index.startTime
        : _playhead.clamp(index.startTime, index.endTime).toInt();
    setState(() {
      _mcap = index;
      _leftSeries = index.leftArm?.series;
      _rightSeries = index.rightArm?.series;
      _playhead = playhead;
      _progress = _progressAt(playhead);
      _loading = false;
      _error = null;
      if (_http?.isDone ?? false) _downloading = false;
    });
    _syncFrames();

    if (_streamWaiting &&
        _playRequested &&
        index.endTime > playhead &&
        _timer == null) {
      _streamWaiting = false;
      _lastTick = DateTime.now();
      setState(() {
        _timer = Timer.periodic(const Duration(milliseconds: 33), _tick);
      });
    }
  }

  Future<void> _loadHttp(String url) async {
    _stopPlayback();
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _downloading = true;
      _error = null;
      _mcap = null;
      _leftSeries = null;
      _rightSeries = null;
      _progress = 0;
      _playhead = 0;
    });

    try {
      final session = await McapHttpSession.start(
        url,
        onProgress: (received, total) {
          if (!mounted || generation != _loadGeneration) return;
          setState(() {
            _received = received;
            _total = total;
            if (_mcap == null) _loading = true;
          });
        },
        onIndex: (index) {
          if (!mounted || generation != _loadGeneration) return;
          _applyIndex(index);
        },
        onError: (error) {
          if (!mounted || generation != _loadGeneration) return;
          setState(() {
            _loading = false;
            _downloading = false;
            _error = '$error';
          });
        },
      );
      if (!mounted || generation != _loadGeneration) {
        session.close();
        return;
      }
      final loader = McapFrameLoader(session.cachePath);
      setState(() {
        _http = session;
        _loader = loader;
        _loading = _mcap == null;
      });
      if (session.latestIndex != null) {
        _applyIndex(session.latestIndex!);
      }
      _syncFrames();

      unawaited(
        session.done.then((_) {
          if (!mounted || generation != _loadGeneration) return;
          setState(() {
            _downloading = false;
            _loading = false;
            if (session.isDone) _streamWaiting = false;
          });
          _syncFrames();
        }),
      );
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _downloading = false;
        _error = '$error';
      });
    }
  }

  void _toggleValid() {
    setState(() => widget.take.valid = !widget.take.valid);
    showToast(context, widget.take.valid ? '已标记为有效' : '已标记为无效');
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      showDevices: true,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;

            return Column(
              children: [
                Expanded(
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(flex: 155, child: _cameraPanel()),
                            const SizedBox(width: 10),
                            Expanded(flex: 78, child: _jointColumn()),
                          ],
                        )
                      : SingleChildScrollView(
                          child: Column(
                            children: [
                              SizedBox(height: 300, child: _cameraPanel()),
                              const SizedBox(height: 10),
                              SizedBox(height: 260, child: _jointColumn()),
                            ],
                          ),
                        ),
                ),
                const SizedBox(height: 10),
                _playBar(),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    SizedBox(
                      width: 160,
                      child: AppButton(
                        widget.take.valid ? '标记无效' : '标记有效',
                        kind: widget.take.valid
                            ? AppButtonKind.danger
                            : AppButtonKind.success,
                        onPressed: _toggleValid,
                      ),
                    ),
                    SizedBox(
                      width: 160,
                      child: AppButton(
                        '返回列表',
                        kind: AppButtonKind.secondary,
                        onPressed: () => Navigator.maybePop(context),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _cameraPanel() {
    return AppPanel(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '回放 · ${_formatClock(_duration.inSeconds)}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFB7C8DA),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              StatusPill(
                text: widget.take.valid ? '有效' : '无效',
                color: widget.take.valid ? AppColors.ok : AppColors.bad,
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 64,
                child: AppButton(
                  '重连',
                  kind: AppButtonKind.secondary,
                  height: 32,
                  fontSize: 12,
                  onPressed: _loading ? null : () => _loadHttp(mcapDemoUrl),
                ),
              ),
            ],
          ),
          if (_downloading) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: _downloadProgress,
                      minHeight: 3,
                      backgroundColor: AppColors.muted,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.brand,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _downloadProgress == null
                      ? '下载中'
                      : '下载 ${(_downloadProgress! * 100).round()}%',
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Expanded(child: _cameraBody()),
        ],
      ),
    );
  }

  Widget _cameraBody() {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.brand,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _downloading ? '连接 / 解析 MCAP…' : '解析 MCAP…',
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              color: AppColors.bad,
              size: 28,
            ),
            const SizedBox(height: 8),
            const Text(
              'MCAP 服务连接失败',
              style: TextStyle(fontSize: 13, color: AppColors.ink),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _error!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: AppColors.muted),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: 96,
              child: AppButton(
                '重试',
                kind: AppButtonKind.secondary,
                height: 32,
                fontSize: 12,
                onPressed: () => _loadHttp(mcapDemoUrl),
              ),
            ),
          ],
        ),
      );
    }

    if (_mcap != null) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: CameraTile(label: '左腕', image: _leftImage),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: CameraTile(label: '右腕', image: _rightImage),
          ),
        ],
      );
    }

    return Column(
      children: [
        const Expanded(flex: 145, child: CameraTile(label: '主视角')),
        const SizedBox(height: 8),
        const Expanded(
          flex: 85,
          child: Row(
            children: [
              Expanded(child: CameraTile(label: '左腕')),
              SizedBox(width: 8),
              Expanded(child: CameraTile(label: '右腕')),
            ],
          ),
        ),
      ],
    );
  }

  Widget _jointColumn() {
    return Column(
      children: [
        Expanded(
          child: AppPanel(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '左臂关节角',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFB7C8DA),
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: JointChart(series: _leftSeries, progress: _progress),
                ),
                const SizedBox(height: 6),
                JointLegend(count: _leftSeries?.length ?? 7),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: AppPanel(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '右臂关节角',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFB7C8DA),
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: JointChart(series: _rightSeries, progress: _progress),
                ),
                const SizedBox(height: 6),
                JointLegend(count: _rightSeries?.length ?? 7),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _playBar() {
    return AppPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          AppButton(
            _playing
                ? '暂停'
                : _streamWaiting
                ? '缓冲中'
                : '播放',
            kind: AppButtonKind.secondary,
            onPressed: (_loading || _mcap == null) ? null : _togglePlay,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _SeekBar(value: _progress, onSeek: _seekTo),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 108,
            child: Text(
              _time,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 14, color: AppColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatClock(int seconds) {
  final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
  final secs = (seconds % 60).toString().padLeft(2, '0');
  return '$minutes:$secs';
}

class _SeekBar extends StatelessWidget {
  const _SeekBar({required this.value, required this.onSeek});

  final double value;
  final ValueChanged<double> onSeek;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        void seek(Offset position) {
          final ratio = (position.dx / constraints.maxWidth)
              .clamp(0.0, 1.0)
              .toDouble();
          onSeek(ratio);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => seek(details.localPosition),
          onHorizontalDragUpdate: (details) => seek(details.localPosition),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 10,
              child: Stack(
                children: [
                  Container(color: AppColors.muted),
                  FractionallySizedBox(
                    widthFactor: value.clamp(0.0, 1.0),
                    child: Container(color: AppColors.ok),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
