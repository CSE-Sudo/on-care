import 'package:flutter_test/flutter_test.dart';

import 'package:oncare_trainer/features/consultations/data/dtos/consultation_dtos.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations_ko.dart';

/// 라벨 기대값은 로케일을 명시해 읽는다.
final AppLocalizationsKo _ko = AppLocalizationsKo();

Map<String, Object?> _json({
  Object? memberName = '김민수',
  Object? goal = 'weight_loss',
  Object? purpose = 'chronic',
  Object? detail,
  Object? date = '2026-08-12',
  Object? slot = 'evening',
  Object? message = '  상담 부탁드립니다.  ',
  Object? status = 'pending',
  Object? note,
}) => <String, Object?>{
  'id': 'consult-1',
  'member_id': 'user-1',
  'member_name': memberName,
  'exercise_goal': goal,
  'health_purpose_type': purpose,
  'health_purpose_detail': detail,
  'preferred_date': date,
  'preferred_time_slot': slot,
  'message': message,
  'status': status,
  'decision_note': note,
};

void main() {
  test('maps the request into display-ready labels', () {
    final request = consultationRequestFromJson(_json());

    expect(request.id, 'consult-1');
    expect(request.memberId, 'user-1');
    expect(request.memberName, '김민수');
    expect(request.goalCode, 'weight_loss');
    expect(request.purposeCode, 'chronic');
    expect(request.preferredDate, DateTime(2026, 8, 12));
    expect(request.preferredTimeCode, 'evening');
    expect(request.isPending, isTrue);
  });

  test('trims free text and collapses blanks to null', () {
    final request = consultationRequestFromJson(
      _json(message: '   ', detail: '  혈압 관리  '),
    );

    // A whitespace-only note would otherwise render an empty quote block.
    expect(request.message, isNull);
    expect(request.purposeDetail, '혈압 관리');
  });

  test('an unknown enum code survives to the UI, not a blank', () {
    final request = consultationRequestFromJson(_json(goal: 'sports_rehab'));

    // 엔티티는 코드를 그대로 들고, 라벨 변환은 화면에서 한다. 모르는 코드는
    // 원문으로 떨어져 트레이너가 읽을 무언가가 남는다. (#501)
    expect(request.goalCode, 'sports_rehab');
    expect(label(exerciseGoalLabels(_ko), request.goalCode), 'sports_rehab');
  });

  test('운동 목표를 회원 앱과 같은 문구로 읽는다 (#1992)', () {
    // 회원이 온보딩에서 고르는 건강 목표와 상담 운동 목표가 같은 목록이 됐다.
    // 트레이너가 보는 문구도 같아야 같은 것인지 알 수 있다.
    final Map<String, String> labels = exerciseGoalLabels(_ko);
    expect(labels['weight_loss'], '체중 감량');
    expect(labels['strength'], '근력 향상');
    // 예전에는 이 표만 `체력 증진` 이라 세 화면이 세 이름으로 불렀다.
    expect(labels['fitness'], '체력 강화');
    expect(labels['posture'], '자세 교정');
    expect(labels['rehab'], '재활');
    expect(labels['eating'], '식습관 개선');
    expect(labels['exercise_habit'], '운동 습관');
    expect(labels['blood_pressure'], '혈압 관리');
    expect(labels['other'], '기타');
  });

  test('없앤 건강 관리 선택지도 저장된 그대로 보여준다 (#1992)', () {
    // 이미 접수된 요청은 백필하지 않는다 — `기타` 로 뭉개면 트레이너가 보던
    // 목표가 다른 말로 바뀐다.
    final request = consultationRequestFromJson(_json(goal: 'health'));

    expect(request.goalCode, 'health');
    expect(label(exerciseGoalLabels(_ko), request.goalCode), '건강 관리');
  });

  test('a missing member name comes through empty, not as Korean text', () {
    final request = consultationRequestFromJson(_json(memberName: null));

    // 대체 문구('알 수 없는 회원')는 화면이 자기 로케일로 붙인다 — DTO 가
    // 한국어를 박아 두면 영어 로케일에서 그 문구만 한국어로 남는다. (#501)
    expect(request.memberName, isEmpty);
  });

  test('an unparseable date does not throw', () {
    // One malformed row must not blank the whole inbox.
    final request = consultationRequestFromJson(_json(date: 'not-a-date'));

    expect(request.preferredDate, DateTime.fromMillisecondsSinceEpoch(0));
  });

  test('carries the decision note', () {
    final request = consultationRequestFromJson(
      _json(status: 'rejected', note: '정원이 찼어요'),
    );

    expect(request.isPending, isFalse);
    expect(request.decisionNote, '정원이 찼어요');
  });
}
