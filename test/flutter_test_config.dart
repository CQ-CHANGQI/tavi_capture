import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// 测试环境没有中文字体：把 macOS 自带的 Arial Unicode 装成 Roboto，
/// 这样 golden 图和真机渲染接近。
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  const path = '/System/Library/Fonts/Supplemental/Arial Unicode.ttf';
  final file = File(path);
  if (file.existsSync()) {
    final bytes = file.readAsBytesSync();
    for (final family in const ['Roboto', 'Ahem']) {
      final loader = FontLoader(family)
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
    }
  }
  await testMain();
}
