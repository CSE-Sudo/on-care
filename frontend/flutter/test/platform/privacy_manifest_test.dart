import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/observability/error_reporter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// iOS 개인정보 매니페스트가 실제 수집과 맞는지(#2823, #3053).
///
/// 오류 수집 SDK 를 넣고도 충돌·진단 데이터를 신고하지 않아 App Store 개인정보
/// 라벨과 실제가 어긋났다. 의존성·SDK 설정과 매니페스트를 대조해, 한쪽만 바뀌면
/// 여기서 실패하게 한다.
class _CollectedType {
  const _CollectedType({
    required this.type,
    required this.linked,
    required this.tracking,
    required this.purposes,
  });

  final String type;
  final bool? linked;
  final bool? tracking;
  final List<String> purposes;
}

void main() {
  const String manifestPath = 'ios/Runner/PrivacyInfo.xcprivacy';
  final String raw = File(manifestPath).readAsStringSync();
  final String manifest = raw.replaceAll(
    RegExp(r'<!--.*?-->', dotAll: true),
    '',
  );
  final String pubspec = File('pubspec.yaml').readAsStringSync();

  bool? boolAfter(String body, String key) {
    final RegExpMatch? m = RegExp(
      '<key>${RegExp.escape(key)}</key>\\s*<(true|false)/>',
    ).firstMatch(body);
    return m == null ? null : m.group(1) == 'true';
  }

  /// [key] 다음 배열의 안쪽. 배열 안에 배열이 들어 있어도(수집 항목마다 목적 배열)
  /// 짝이 맞는 닫는 태그까지 읽는다 — 가장 가까운 `</array>` 에서 끊으면 첫 항목의
  /// 목적 배열에서 멈춘다.
  String arrayAfter(String body, String key) {
    final RegExpMatch? m = RegExp(
      '<key>${RegExp.escape(key)}</key>\\s*(<array/>|<array>)',
    ).firstMatch(body);
    expect(m, isNotNull, reason: '$key 가 없다');
    if (m!.group(1) == '<array/>') return '';
    final RegExp tag = RegExp('<array/>|<array>|</array>');
    int depth = 1;
    for (final RegExpMatch t in tag.allMatches(body, m.end)) {
      if (t.group(0) == '<array>') depth++;
      if (t.group(0) == '</array>') depth--;
      if (depth == 0) return body.substring(m.end, t.start);
    }
    fail('$key 배열이 닫히지 않았다');
  }

  List<_CollectedType> collected() {
    final String body = arrayAfter(manifest, 'NSPrivacyCollectedDataTypes');
    return <_CollectedType>[
      for (final RegExpMatch d in RegExp(
        r'<dict>(.*?)</dict>',
        dotAll: true,
      ).allMatches(body))
        _CollectedType(
          type: RegExp(
            r'<key>NSPrivacyCollectedDataType</key>\s*<string>([^<]+)</string>',
          ).firstMatch(d.group(1)!)!.group(1)!,
          linked: boolAfter(d.group(1)!, 'NSPrivacyCollectedDataTypeLinked'),
          tracking: boolAfter(
            d.group(1)!,
            'NSPrivacyCollectedDataTypeTracking',
          ),
          purposes: <String>[
            for (final RegExpMatch s
                in RegExp(r'<string>([^<]+)</string>').allMatches(
                  arrayAfter(d.group(1)!, 'NSPrivacyCollectedDataTypePurposes'),
                ))
              s.group(1)!,
          ],
        ),
    ];
  }

  _CollectedType? find(String type) {
    for (final _CollectedType t in collected()) {
      if (t.type == 'NSPrivacyCollectedDataType$type') return t;
    }
    return null;
  }

  bool dependsOn(String package) =>
      RegExp('^  $package:', multiLine: true).hasMatch(pubspec);

  SentryFlutterOptions sentryOptions() {
    final SentryFlutterOptions options = SentryFlutterOptions();
    configureSentryOptions(
      options,
      const AppConfig(
        environment: Environment.prod,
        apiBaseUrl: 'https://api.example.invalid/v1',
        useMockApi: false,
        sentryDsn: 'https://publickey@o0.ingest.example.invalid/1',
      ),
    );
    return options;
  }

  test('추적하지 않고 추적 도메인이 없다', () {
    expect(boolAfter(manifest, 'NSPrivacyTracking'), isFalse);
    expect(arrayAfter(manifest, 'NSPrivacyTrackingDomains').trim(), isEmpty);
  });

  test('모든 수집 항목에 Linked·Tracking·Purposes 가 있고 Tracking 은 false', () {
    final List<_CollectedType> types = collected();
    expect(types, isNotEmpty);
    for (final _CollectedType t in types) {
      expect(t.linked, isNotNull, reason: '${t.type} Linked');
      expect(t.tracking, isFalse, reason: '${t.type} Tracking');
      expect(t.purposes, isNotEmpty, reason: '${t.type} Purposes');
    }
  });

  test('같은 유형을 두 번 신고하지 않는다', () {
    final List<String> names = <String>[
      for (final _CollectedType t in collected()) t.type,
    ];
    expect(names.toSet(), hasLength(names.length));
  });

  test('sentry_flutter 를 쓰면 충돌 데이터를 신고한다', () {
    expect(dependsOn('sentry_flutter'), isTrue);
    expect(find('CrashData'), isNotNull);
  });

  test('세션 추적이 켜져 있으면 기타 진단 데이터를 신고한다', () {
    if (sentryOptions().enableAutoSessionTracking) {
      expect(find('OtherDiagnosticData'), isNotNull);
    } else {
      expect(find('OtherDiagnosticData'), isNull);
    }
  });

  test('진단 항목은 계정과 연결하지 않는다', () {
    expect(find('CrashData')!.linked, isFalse);
    expect(find('OtherDiagnosticData')!.linked, isFalse);
  });

  test('진단이 계정과 연결되지 않는 근거 — Sentry 는 개인 식별 정보를 싣지 않는다', () {
    final SentryFlutterOptions options = sentryOptions();
    expect(options.sendDefaultPii, isFalse);
    expect(options.attachScreenshot, isFalse);
    expect(options.beforeSend, isNotNull);
  });

  test('lib 어디에서도 Sentry 사용자를 설정하지 않는다', () {
    final RegExp setUser = RegExp(r'SentryUser\(|\.setUser\(');
    final List<String> hits = <String>[];
    for (final File f
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((File f) => f.path.endsWith('.dart'))) {
      if (setUser.hasMatch(f.readAsStringSync())) hits.add(f.path);
    }
    expect(hits, isEmpty);
  });

  test('계정 항목은 계정과 연결한다', () {
    for (final String type in <String>['Name', 'EmailAddress', 'UserID']) {
      expect(find(type), isNotNull, reason: type);
      expect(find(type)!.linked, isTrue, reason: type);
    }
  });

  test('상담·예약 신청 내용(기타 사용자 콘텐츠)을 계정과 연결해 신고한다', () {
    expect(find('OtherUserContent'), isNotNull);
    expect(find('OtherUserContent')!.linked, isTrue);
  });

  test('geolocator 를 쓰면 위치를 신고한다', () {
    if (dependsOn('geolocator')) {
      expect(find('PreciseLocation') ?? find('CoarseLocation'), isNotNull);
    }
  });
}
