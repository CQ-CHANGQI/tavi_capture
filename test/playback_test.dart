import 'package:flutter_test/flutter_test.dart';
import 'package:tavi_capture/core/models.dart';
import 'package:tavi_capture/core/playback.dart';

void main() {
  test('全部模式同时画指令和状态', () {
    final track = JointTrack()
      ..add('left_joint1/position', 1, isCommand: true)
      ..add('left_joint1/position', 2, isCommand: false);

    final all = track.curves(JointMode.all);
    expect(all, hasLength(2));
    expect(all.map((curve) => curve.name), containsAll(['J1 · 指令', 'J1 · 状态']));

    final command = track.curves(JointMode.command);
    expect(command, hasLength(1));
    expect(command.single.name, 'J1');
  });
}
