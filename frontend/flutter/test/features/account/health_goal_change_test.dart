/// 건강 목표 변경 기록과 알림(#1832) — 회원앱 쪽.
///
/// 담당 트레이너가 목표를 바꾸면 회원에게 알림이 오고, 누르면 MY 건강 목표로 간다.
/// MY 건강 목표 칩 아래에는 누가 언제 바꿨는지 한 줄이 남는다. 목업 서버도 목표
/// 칩이 실제로 바뀐 저장에만 그 기록을 남긴다.
library;

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logger/logger.dart';
import 'package:oncare/core/network/interceptors/local_api_interceptor.dart';
import 'package:oncare/core/points/demo_points_ledger.dart';
import 'package:oncare/core/storage/app_database.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/presentation/focus_change_label.dart';
import 'package:oncare/features/notification/data/repositories/dio_notification_repository.dart';
import 'package:oncare/features/notification/domain/entities/alert_item.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';

Dio _answering(Object? body) {
  final Dio dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
        handler.resolve(
          Response<Object?>(
            requestOptions: options,
            statusCode: 200,
            data: body,
          ),
        );
      },
    ),
  );
  return dio;
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ko');
    await initializeDateFormatting('en');
  });

  test('트레이너가 목표를 바꾼 알림은 MY 건강 목표로 가는 알림이다', () async {
    final repo = DioNotificationRepository(
      _answering(<Object?>[
        <String, Object?>{
          'id': 'n1',
          'title': '건강 목표가 바뀌었어요',
          'body': '김트레이너 트레이너님이 건강 목표를 바꿨어요: 자세 교정',
          'time_ago': '방금',
          'category': 'health_goals',
          'read': false,
          'action': <String, Object?>{
            'label': '목표 보기',
            'target': 'health_goals',
          },
        },
      ]),
    );

    final AlertItem item = (await repo.fetchPage()).single;
    expect(item.action?.target, AlertTarget.healthGoals);
    expect(item.action?.isNavigable, isTrue);
  });

  group('프로필의 마지막 변경', () {
    test('서버가 준 변경자와 시각을 읽는다', () {
      final UserProfile profile = UserProfile.fromJson(<String, Object?>{
        'id': 'u1',
        'name': '지수',
        'email': 'jisu@oncare.com',
        'conditions': '자세 교정',
        'focus_changed_by': 'trainer',
        'focus_changed_at': '2026-09-16T01:30:00Z',
      });
      expect(profile.focusChangedBy, UserProfile.focusChangedByTrainer);
      expect(
        profile.focusChangedAt,
        DateTime.utc(2026, 9, 16, 1, 30).toLocal(),
      );
    });

    test('바꾼 적이 없으면 둘 다 비어 있고 줄을 그리지 않는다', () {
      final UserProfile profile = UserProfile.fromJson(<String, Object?>{
        'id': 'u1',
        'focus_changed_by': null,
        'focus_changed_at': null,
      });
      expect(profile.focusChangedBy, isNull);
      expect(profile.focusChangedAt, isNull);
      expect(
        focusLastChangedLabel(
          lookupAppLocalizations(const Locale('ko')),
          profile,
          locale: 'ko',
        ),
        isNull,
      );
    });

    test('누가 언제 바꿨는지 한 줄로 말한다(ko·en)', () {
      final UserProfile byTrainer = UserProfile(
        id: 'u1',
        name: '지수',
        email: '',
        focusChangedBy: UserProfile.focusChangedByTrainer,
        focusChangedAt: DateTime(2026, 9, 16, 10),
      );
      final UserProfile byMe = UserProfile(
        id: 'u1',
        name: '지수',
        email: '',
        focusChangedBy: UserProfile.focusChangedByMember,
        focusChangedAt: DateTime(2026, 9, 3, 10),
      );
      final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));
      final AppLocalizations en = lookupAppLocalizations(const Locale('en'));

      expect(
        focusLastChangedLabel(ko, byTrainer, locale: 'ko'),
        '마지막 변경: 트레이너 · 9월 16일',
      );
      expect(
        focusLastChangedLabel(ko, byMe, locale: 'ko'),
        '마지막 변경: 나 · 9월 3일',
      );
      expect(
        focusLastChangedLabel(en, byTrainer, locale: 'en'),
        'Last changed by your trainer · Sep 16',
      );
    });
  });

  group('목업 서버', () {
    late AppDatabase db;
    late Dio dio;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
      dio.interceptors.add(
        LocalApiInterceptor(
          db,
          Logger(level: Level.off),
          points: DemoPointsLedger(),
        ),
      );
    });

    tearDown(() async {
      await db.close();
      dio.close();
    });

    Future<Map<String, Object?>> save(Map<String, Object?> body) async {
      final Response<Map<String, Object?>> res = await dio
          .put<Map<String, Object?>>('/users/me/health-goals', data: body);
      return res.data!;
    }

    test('목표 칩이 바뀐 저장만 회원이 바꾼 것으로 남긴다', () async {
      // 데모 회원의 시작 목표(체중 감량·혈압 관리)와 다른 목표로 바꾼다.
      final Map<String, Object?> first = await save(<String, Object?>{
        'conditions': '재활, 자세 교정',
      });
      expect(first['focus_changed_by'], 'member');
      final Object? stamped = first['focus_changed_at'];
      expect(stamped, isA<String>());

      // 수치만 고친 저장, 같은 목표를 순서만 바꾼 저장은 목표 변경이 아니다.
      final Map<String, Object?> numbers = await save(<String, Object?>{
        'daily_calories': 1800,
      });
      expect(numbers['focus_changed_at'], stamped);
      final Map<String, Object?> reordered = await save(<String, Object?>{
        'conditions': '자세 교정, 재활',
      });
      expect(reordered['focus_changed_at'], stamped);
    });
  });
}
