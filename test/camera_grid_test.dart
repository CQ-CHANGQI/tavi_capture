import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tavi_capture/ui/camera.dart';

void main() {
  testWidgets('相机网格 2×2 且掉线显示无画面', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 300,
            child: CameraGrid(images: {}, dead: {'cam_left'}),
          ),
        ),
      ),
    );

    expect(find.byType(CameraTile), findsNWidgets(4));
    expect(find.text('左腕 · 无画面'), findsOneWidget);
    expect(find.text('主视角'), findsOneWidget);
    expect(find.text('右腕'), findsOneWidget);
    expect(find.text('全景'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
