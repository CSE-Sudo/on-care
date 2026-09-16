import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// 회원앱 아이콘 글꼴(Material Symbols Rounded)을 시험 화면에 싣는다.
///
/// 시험에서는 글꼴 자산이 번들되지 않아 모든 글자가 네모로 그려진다 — 아이콘이
/// 채워졌는지를 픽셀로 재려면 진짜 가변 글꼴이 있어야 한다. 경로는 `pub get` 이
/// 남긴 `package_config.json` 에서 찾는다.
Future<void> loadMaterialSymbolsRounded() async {
  final File config = File('.dart_tool/package_config.json');
  final Map<String, dynamic> json =
      jsonDecode(config.readAsStringSync()) as Map<String, dynamic>;
  final List<dynamic> packages = json['packages'] as List<dynamic>;
  final Map<String, dynamic> symbols =
      packages.firstWhere(
            (dynamic p) =>
                (p as Map<String, dynamic>)['name'] == 'material_symbols_icons',
          )
          as Map<String, dynamic>;
  // `rootUri` 는 끝의 `/` 가 없을 수 있다 — 붙이지 않으면 마지막 칸이 잘린다.
  final String rootUri = symbols['rootUri'] as String;
  final Uri root = config.absolute.uri.resolve(
    rootUri.endsWith('/') ? rootUri : '$rootUri/',
  );
  final File font = File.fromUri(
    root.resolve('lib/fonts/MaterialSymbolsRounded.ttf'),
  );
  await (FontLoader('packages/material_symbols_icons/MaterialSymbolsRounded')
        ..addFont(
          Future<ByteData>.value(ByteData.sublistView(font.readAsBytesSync())),
        ))
      .load();
}
