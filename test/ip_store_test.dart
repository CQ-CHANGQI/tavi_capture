import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tavi_capture/core/ip_store.dart';

void main() {
  test('保存并读回机器人 IP', () async {
    final dir = Directory.systemTemp.createTempSync('tavi_ip_store');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = IpStore(path: '${dir.path}/ip.json');

    expect(await store.load(), isNull);
    await store.save('192.168.13.4');
    expect(await store.load(), '192.168.13.4');
  });

  test('文件损坏时当作没存过', () async {
    final dir = Directory.systemTemp.createTempSync('tavi_ip_store');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/ip.json';
    File(path).writeAsStringSync('not json');
    expect(await IpStore(path: path).load(), isNull);
  });
}
