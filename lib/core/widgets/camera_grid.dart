import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../telemetry/sample.dart';
import '../theme/app_colors.dart';

/// Four camera slots match the product layout; absent data stays explicitly empty.
class CameraGrid extends StatelessWidget {
  const CameraGrid({super.key, required this.frames, this.fps});
  final Map<String, CameraFrame> frames;
  final double Function(String)? fps;

  @override
  Widget build(BuildContext context) {
    Widget tile(String name) => _CameraTile(
      key: ValueKey(name),
      label: cameraLabels[name]!,
      frame: frames[name],
      fps: fps?.call(name),
    );
    return Column(
      children: [
        Expanded(flex: 145, child: tile('cam_head')),
        const SizedBox(height: 8),
        Expanded(
          flex: 85,
          child: Row(
            children: [
              for (final name in ['cam_left', 'cam_right', 'cam_chest']) ...[
                if (name != 'cam_left') const SizedBox(width: 8),
                Expanded(child: tile(name)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _CameraTile extends StatelessWidget {
  const _CameraTile({super.key, required this.label, this.frame, this.fps});
  final String label;
  final CameraFrame? frame;
  final double? fps;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: ColoredBox(
      color: const Color(0xff101820),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (frame != null)
            FrameImage(frame: frame!)
          else
            const Center(
              child: Text(
                '等待画面',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ),
          Positioned(
            left: 8,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              color: Colors.black54,
              child: Text(
                '$label${fps == null ? '' : ' · ${fps!.toStringAsFixed(0)} fps'}',
                style: const TextStyle(fontSize: 12, color: Colors.white),
              ),
            ),
          ),
          Positioned(
            right: 2,
            top: 2,
            child: IconButton(
              tooltip: '放大$label',
              icon: const Icon(Icons.fullscreen, size: 20),
              onPressed: frame == null
                  ? null
                  : () => showDialog<void>(
                      context: context,
                      builder: (context) => Dialog.fullscreen(
                        backgroundColor: Colors.black,
                        child: Stack(
                          children: [
                            Positioned.fill(child: FrameImage(frame: frame!)),
                            Positioned(
                              right: 16,
                              top: 16,
                              child: FilledButton.icon(
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(Icons.fullscreen_exit),
                                label: const Text('退出全屏'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Only one decode runs at a time; updates replace the pending frame.
class FrameImage extends StatefulWidget {
  const FrameImage({super.key, required this.frame});
  final CameraFrame frame;
  @override
  State<FrameImage> createState() => _FrameImageState();
}

class _FrameImageState extends State<FrameImage> {
  ui.Image? _image;
  CameraFrame? _pending;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(FrameImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.frame, widget.frame)) _schedule();
  }

  void _schedule() {
    _pending = widget.frame;
    if (!_busy) unawaited(_decode());
  }

  Future<void> _decode() async {
    _busy = true;
    while (mounted && _pending != null) {
      final frame = _pending!;
      _pending = null;
      ui.Codec? codec;
      try {
        codec = await ui.instantiateImageCodec(frame.bytes);
        final decoded = await codec.getNextFrame();
        if (!mounted) {
          decoded.image.dispose();
          break;
        }
        final old = _image;
        setState(() => _image = decoded.image);
        if (old != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
        }
      } catch (_) {
        /* Keep the last valid frame when a packet is corrupt. */
      } finally {
        codec?.dispose();
      }
    }
    _busy = false;
  }

  @override
  void dispose() {
    _pending = null;
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RawImage(
    image: _image,
    fit: BoxFit.contain,
    filterQuality: FilterQuality.low,
  );
}
