import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oncare_trainer/app/app_theme.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/features/coaching/data/repositories/trainer_program_template_repository.dart';
import 'package:oncare_trainer/features/coaching/domain/program_template.dart';
import 'package:oncare_trainer/features/coaching/presentation/widgets/program_template_dialog.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';

/// 템플릿 저장 중 `AppError` 가 아닌 예외도 창 아래 안내로 받는다 (#2896).

/// 저장할 때 [error] 를 던지는 저장소.
class _ThrowingTemplateRepository implements TrainerProgramTemplateRepository {
  _ThrowingTemplateRepository(this.error);

  final Object error;
  int calls = 0;

  @override
  bool get supportsEditing => true;

  @override
  Future<List<ProgramTemplate>> list() async => const <ProgramTemplate>[];

  @override
  Future<ProgramTemplate> create({
    required String name,
    required String goal,
    required List<TemplateExercise> exercises,
  }) async {
    calls++;
    throw error;
  }

  @override
  Future<ProgramTemplate> update(
    String id, {
    required String name,
    required String goal,
    required List<TemplateExercise> exercises,
  }) async {
    calls++;
    throw error;
  }

  @override
  Future<void> delete(String id) async {}
}

/// 정해 둔 본문을 200 으로 돌려주는 가짜 서버.
class _FixedServer implements HttpClientAdapter {
  _FixedServer(this.body);

  final String body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    body,
    200,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}

DioTrainerProgramTemplateRepository _dioRepo(String body) =>
    DioTrainerProgramTemplateRepository(
      Dio(BaseOptions(baseUrl: 'http://test.local'))
        ..httpClientAdapter = _FixedServer(body),
    );

const List<TemplateExercise> _exercises = <TemplateExercise>[
  TemplateExercise(name: '걷기', minutes: 20, type: '유산소'),
];

Future<void> _pumpDialog(
  WidgetTester tester,
  TrainerProgramTemplateRepository repository,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        trainerProgramTemplateRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        locale: const Locale('ko'),
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: ProgramTemplateDialog()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _fillAndSave(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey<String>('template-name')),
    '내 블록',
  );
  await tester.enterText(find.byType(TextField).at(2), '걷기');
  await tester.tap(find.byKey(const ValueKey<String>('template-save')));
  await tester.pumpAndSettle();
}

void main() {
  group('템플릿 저장 창 (#2896)', () {
    testWidgets('일반 예외가 나도 창 아래에 실패 안내가 서고 창은 닫히지 않는다', (tester) async {
      final repository = _ThrowingTemplateRepository(
        StateError('local storage unavailable'),
      );
      await _pumpDialog(tester, repository);

      await _fillAndSave(tester);

      expect(repository.calls, 1);
      expect(
        find.byKey(const ValueKey<String>('template-save-error')),
        findsOneWidget,
      );
      expect(find.text('템플릿을 저장하지 못했어요. 다시 시도해 주세요'), findsOneWidget);
      expect(find.byType(ProgramTemplateDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('해석 오류(FormatException)도 같은 안내다', (tester) async {
      await _pumpDialog(
        tester,
        _ThrowingTemplateRepository(const FormatException('bad json')),
      );

      await _fillAndSave(tester);

      expect(find.text('템플릿을 저장하지 못했어요. 다시 시도해 주세요'), findsOneWidget);
    });

    testWidgets('실패 뒤 저장 버튼이 다시 살아난다', (tester) async {
      final repository = _ThrowingTemplateRepository(StateError('boom'));
      await _pumpDialog(tester, repository);

      await _fillAndSave(tester);
      await tester.tap(find.byKey(const ValueKey<String>('template-save')));
      await tester.pumpAndSettle();

      expect(repository.calls, 2);
    });
  });

  group('실서버 템플릿 저장소 (#2896)', () {
    test('응답에 id 가 없으면 만들기가 ServerError 로 올라온다', () async {
      final repo = _dioRepo(jsonEncode(<String, Object?>{'name': '내 블록'}));

      await expectLater(
        repo.create(name: '내 블록', goal: '', exercises: _exercises),
        throwsA(isA<ServerError>()),
      );
    });

    test('응답 모양이 어긋나면 고치기도 ServerError 로 올라온다', () async {
      final repo = _dioRepo(
        jsonEncode(<String, Object?>{'id': 7, 'name': '내 블록'}),
      );

      await expectLater(
        repo.update('tpl-1', name: '내 블록', goal: '', exercises: _exercises),
        throwsA(isA<ServerError>()),
      );
    });

    test('정상 응답은 그대로 읽는다', () async {
      final repo = _dioRepo(
        jsonEncode(<String, Object?>{
          'id': 'tpl-9',
          'name': '내 블록',
          'goal': '',
          'exercises': <Object?>[],
        }),
      );

      final saved = await repo.create(
        name: '내 블록',
        goal: '',
        exercises: _exercises,
      );

      expect(saved.id, 'tpl-9');
    });
  });
}
