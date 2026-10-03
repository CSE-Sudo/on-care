/// 회원 앱이 결과지를 여는 길 — 자료를 고르고, 목표를 싣고, 파일을 만든다. (#2652)
///
/// 트레이너가 첨부를 보냈으면 그 파일을, 아니면 트레이너 웹과 같은 결과지를 세워
/// 굽는다. 두 갈래가 같은 곳(`loadCoachReportPdf`)에서 갈라져야 대화와 MY 목록이
/// 같은 문서를 연다.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:oncare/core/config/app_config.dart';
import 'package:oncare/core/network/dio_client.dart';
import 'package:oncare/features/account/domain/entities/user_profile.dart';
import 'package:oncare/features/account/presentation/controllers/account_controller.dart';
import 'package:oncare/features/member_coach/data/repositories/chat_pdf_repository.dart';
import 'package:oncare/features/member_coach/data/repositories/member_report_sheet_repository.dart';
import 'package:oncare/features/member_coach/domain/entities/member_coach.dart';
import 'package:oncare/features/member_coach/presentation/controllers/member_report_providers.dart';
import 'package:oncare/features/member_coach/presentation/widgets/coach_report_opener.dart';
import 'package:oncare/features/member_coach/services/member_report_pdf_generator.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_report/oncare_report.dart';

AppConfig _config({required bool useMockApi}) => AppConfig(
  environment: Environment.dev,
  apiBaseUrl: 'http://localhost/v1',
  useMockApi: useMockApi,
);

final DateTime _monday = DateTime(2026, 9, 14);

final ReportSheetInputs _inputs = ReportSheetInputs(
  week: ReportSheetWeekData(
    memberName: '김민수',
    weekStart: _monday,
    sessionsBooked: 1,
    sessionsDone: 1,
    completionAvg: 90,
    sodiumAvg: 1800,
    isCurrentWeek: false,
  ),
);

UserProfile _profile({int? cardio, int? sets, int? stretching}) => UserProfile(
  id: 'user-7d4e9a2c5f18',
  name: '김민수',
  email: 'minsu@oncare.com',
  weeklyCardioMinutes: cardio,
  weeklyStrengthSets: sets,
  weeklyFlexibilityMinutes: stretching,
);

class _StubProfile extends ProfileController {
  _StubProfile(this._value);

  final UserProfile _value;

  @override
  Future<UserProfile> build() async => _value;
}

class _FailingProfile extends ProfileController {
  @override
  Future<UserProfile> build() async => throw Exception('offline');
}

class _RecordingRepository implements MemberReportSheetRepository {
  DateTime? weekStart;
  String? languageCode;
  ReportSheetGoals? goals;
  int calls = 0;

  @override
  Future<ReportSheetInputs> fetch({
    required DateTime weekStart,
    required String languageCode,
    ReportSheetGoals goals = const ReportSheetGoals(),
  }) async {
    calls++;
    this.weekStart = weekStart;
    this.languageCode = languageCode;
    this.goals = goals;
    return _inputs;
  }
}

class _RecordingGenerator extends MemberReportPdfGenerator {
  _RecordingGenerator();

  ReportSheetInputs? inputs;
  MemberReportFeedback? feedback;
  String? language;

  @override
  Future<Uint8List> generate({
    required AppLocalizations l,
    required ReportSheetInputs inputs,
    required MemberReportFeedback feedback,
    DateTime? today,
  }) async {
    this.inputs = inputs;
    this.feedback = feedback;
    language = l.localeName;
    return Uint8List.fromList(<int>[1, 2, 3]);
  }
}

class _FakeChatPdf extends ChatPdfRepository {
  _FakeChatPdf() : super(Dio());

  String? path;

  @override
  Future<Uint8List> download(String path) async {
    this.path = path;
    return Uint8List.fromList(<int>[9, 9]);
  }
}

CoachMessage _notice({CoachAttachment? attachment, String body = '수고하셨어요'}) =>
    CoachMessage(
      id: 'report-1',
      sender: CoachSender.trainer,
      body: body,
      timeLabel: '18:10',
      createdAt: DateTime(2026, 9, 21, 18, 10),
      reportWeekStart: _monday,
      attachment: attachment,
    );

void main() {
  final AppLocalizations ko = lookupAppLocalizations(const Locale('ko'));
  final AppLocalizations en = lookupAppLocalizations(const Locale('en'));

  group('어디서 읽는가', () {
    test('데모면 트레이너 웹 데모와 같은 규칙의 저장소다', () {
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(_config(useMockApi: true)),
        ],
      );
      addTearDown(container.dispose);
      expect(
        container.read(memberReportSheetRepositoryProvider),
        isA<DemoMemberReportSheetRepository>(),
      );
    });

    test('실서버면 회원 본인 리포트 엔드포인트를 읽는 저장소다', () {
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          appConfigProvider.overrideWithValue(_config(useMockApi: false)),
          dioProvider.overrideWithValue(Dio()),
        ],
      );
      addTearDown(container.dispose);
      expect(
        container.read(memberReportSheetRepositoryProvider),
        isA<DioMemberReportSheetRepository>(),
      );
    });
  });

  group('주간 운동 목표', () {
    test('정하지 않았으면 트레이너 웹과 같은 권장값이다', () {
      final ReportSheetGoals goals = reportSheetGoalsOf(null);
      expect(goals.weeklyCardioMinutes, kReportWeeklyCardioMinutes);
      expect(goals.weeklyStrengthSets, kReportWeeklyStrengthSets);
      expect(goals.weeklyStretchingMinutes, kReportWeeklyStretchingMinutes);
    });

    test('MY 에서 정한 목표를 유형마다 그 단위로 싣는다', () {
      final ReportSheetGoals goals = reportSheetGoalsOf(
        _profile(cardio: 200, sets: 12, stretching: 30),
      );
      expect(goals.weeklyCardioMinutes, 200);
      expect(goals.weeklyStrengthSets, 12);
      expect(goals.weeklyStretchingMinutes, 30);
    });

    test('비어 있는 칸만 권장값으로 채운다', () {
      final ReportSheetGoals goals = reportSheetGoalsOf(_profile(sets: 9));
      expect(goals.weeklyCardioMinutes, kReportWeeklyCardioMinutes);
      expect(goals.weeklyStrengthSets, 9);
      expect(goals.weeklyStretchingMinutes, kReportWeeklyStretchingMinutes);
    });
  });

  group('결과지 자료 읽기', () {
    test('그 주·언어·회원 목표를 저장소에 넘긴다', () async {
      final _RecordingRepository repository = _RecordingRepository();
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          memberReportSheetRepositoryProvider.overrideWithValue(repository),
          profileProvider.overrideWith(
            () => _StubProfile(_profile(cardio: 120)),
          ),
        ],
      );
      addTearDown(container.dispose);

      final ReportSheetInputs inputs = await loadMemberReportSheet(
        container.read,
        weekStart: _monday,
        languageCode: 'en',
      );

      expect(inputs, same(_inputs));
      expect(repository.weekStart, _monday);
      expect(repository.languageCode, 'en');
      expect(repository.goals!.weeklyCardioMinutes, 120);
    });

    test('프로필을 못 읽어도 권장 목표로 결과지를 세운다', () async {
      final _RecordingRepository repository = _RecordingRepository();
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          memberReportSheetRepositoryProvider.overrideWithValue(repository),
          profileProvider.overrideWith(_FailingProfile.new),
        ],
      );
      addTearDown(container.dispose);

      await loadMemberReportSheet(
        container.read,
        weekStart: _monday,
        languageCode: 'ko',
      );
      expect(repository.goals!.weeklyCardioMinutes, kReportWeeklyCardioMinutes);
    });

    test('누를 때마다 새로 읽는다 — 오늘 더한 기록이 늦게 닿지 않게', () async {
      final _RecordingRepository repository = _RecordingRepository();
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          memberReportSheetRepositoryProvider.overrideWithValue(repository),
          profileProvider.overrideWith(() => _StubProfile(_profile())),
        ],
      );
      addTearDown(container.dispose);

      for (int i = 0; i < 2; i++) {
        await loadMemberReportSheet(
          container.read,
          weekStart: _monday,
          languageCode: 'ko',
        );
      }
      expect(repository.calls, 2);
    });
  });

  group('리포트 파일 만들기', () {
    late _RecordingRepository repository;
    late _RecordingGenerator generator;
    late _FakeChatPdf chatPdf;
    late ProviderContainer container;

    setUp(() {
      repository = _RecordingRepository();
      generator = _RecordingGenerator();
      chatPdf = _FakeChatPdf();
      container = ProviderContainer(
        overrides: <Override>[
          memberReportSheetRepositoryProvider.overrideWithValue(repository),
          memberReportPdfGeneratorProvider.overrideWithValue(generator),
          chatPdfRepositoryProvider.overrideWithValue(chatPdf),
          profileProvider.overrideWith(() => _StubProfile(_profile())),
        ],
      );
    });

    tearDown(() => container.dispose());

    test('첨부가 있으면 트레이너가 보낸 그 파일을 연다', () async {
      final CoachReportPdf pdf = await loadCoachReportPdf(
        container.read,
        l: ko,
        message: _notice(
          attachment: const CoachAttachment(
            kind: CoachAttachmentKind.pdf,
            fileName: '주간리포트_김민수.pdf',
            fileId: 'f1',
            fileSize: 2,
            downloadPath: '/chat/files/f1',
          ),
        ),
        weekStart: _monday,
      );

      expect(pdf.bytes, <int>[9, 9]);
      expect(pdf.fileName, '주간리포트_김민수.pdf');
      expect(chatPdf.path, '/chat/files/f1');
      expect(repository.calls, 0, reason: '보낸 파일이 있으면 다시 세우지 않는다');
      expect(generator.inputs, isNull);
    });

    test('첨부가 없으면 트레이너 웹과 같은 결과지를 세워 굽는다', () async {
      final CoachReportPdf pdf = await loadCoachReportPdf(
        container.read,
        l: ko,
        message: _notice(),
        weekStart: _monday,
      );

      expect(pdf.bytes, <int>[1, 2, 3]);
      expect(pdf.fileName, ko.coachReportPdfFileName('2026-09-14'));
      expect(repository.weekStart, _monday);
      expect(generator.inputs, same(_inputs));
    });

    test('트레이너가 함께 보낸 글이 트레이너 피드백 칸에 실린다', () async {
      await loadCoachReportPdf(
        container.read,
        l: ko,
        message: _notice(body: '다음 주는 하체 위주로 가요'),
        weekStart: _monday,
      );
      expect(generator.feedback!.text, '다음 주는 하체 위주로 가요');
      expect(generator.feedback!.title, isNull);
    });

    test('화면 언어로 자료와 문서를 만든다', () async {
      final CoachReportPdf pdf = await loadCoachReportPdf(
        container.read,
        l: en,
        message: _notice(),
        weekStart: _monday,
      );
      expect(repository.languageCode, 'en');
      expect(generator.language, 'en');
      expect(pdf.fileName, en.coachReportPdfFileName('2026-09-14'));
    });

    test('자료를 못 읽으면 던진다 — 부르는 쪽이 안내를 띄운다', () async {
      final ProviderContainer broken = ProviderContainer(
        overrides: <Override>[
          memberReportSheetRepositoryProvider.overrideWithValue(
            _ThrowingRepository(),
          ),
          memberReportPdfGeneratorProvider.overrideWithValue(generator),
          profileProvider.overrideWith(() => _StubProfile(_profile())),
        ],
      );
      addTearDown(broken.dispose);

      await expectLater(
        loadCoachReportPdf(
          broken.read,
          l: ko,
          message: _notice(),
          weekStart: _monday,
        ),
        throwsStateError,
      );
      expect(generator.inputs, isNull);
    });
  });
}

class _ThrowingRepository implements MemberReportSheetRepository {
  @override
  Future<ReportSheetInputs> fetch({
    required DateTime weekStart,
    required String languageCode,
    ReportSheetGoals goals = const ReportSheetGoals(),
  }) async => throw StateError('offline');
}
