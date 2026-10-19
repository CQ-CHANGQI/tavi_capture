import 'package:flutter_test/flutter_test.dart';

import 'package:tavi_capture/core/video/jpeg_frame.dart';
import 'package:tavi_capture/core/video/video_config.dart';

void main() {
  test('JpegFrameParser 切出一张完整 JPEG', () {
    final parser = JpegFrameParser();
    parser.feed([0x00, 0xFF, 0xD8, 0x01, 0x02, 0xFF, 0xD9]);

    final frame = parser.takeFrame();

    expect(frame, isNotNull);
    expect(frame!.sublist(0, 2), [0xFF, 0xD8]);
    expect(frame.sublist(frame.length - 2), [0xFF, 0xD9]);
  });

  test('JpegFrameParser 对不完整帧返回 null', () {
    final parser = JpegFrameParser();
    parser.feed([0xFF, 0xD8, 0x01]);

    expect(parser.takeFrame(), isNull);
  });

  test('MJPEG 地址', () {
    final url = cameraStreamUrl(
      robotIp: '192.168.13.4',
      topic: '/cam1/image',
      width: 960,
      quality: 75,
    );

    expect(
      url,
      'http://192.168.13.4:$videoPort/stream'
      '?topic=/cam1/image&type=mjpeg&width=960&quality=75',
    );
  });
}
