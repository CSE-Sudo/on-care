import 'package:oncare_trainer/features/coaching/data/dtos/routine_suggestion_dtos.dart';
import 'package:oncare_trainer/features/coaching/domain/entities/routine_suggestion.dart';

/// 데모 회원별 AI 개인운동 후보 — 한국어. (#2668)
///
/// 예전에는 모든 회원이 같은 세 건·같은 근거 문구였다. 김민수의 세 건
/// (`MockTrainerRoutineSuggestionRepository.seedFor`)은 그대로 두고, 나머지
/// 회원은 그 회원의 목표·기록(`seed_clients.dart` 의 이력 완료율·대화)을 숫자로
/// 말하는 후보를 둔다. 서버 `routine_suggestion_service` 와 같은 말투다.
///
/// 예전처럼 회원마다 세 건이고, 그중 하나는 근력이다 — 개인운동 단계의 세트·
/// 횟수·중량 칸이 어느 회원을 열어도 보여야 한다(#1321).
///
/// 이미 배정된 개인 운동(그 회원의 `aiRoutine`)과 겹치지 않는 운동만 둔다 —
/// 같은 운동이 "아직 안 보낸 후보" 와 "이미 보낸 것" 으로 두 번 나오면 안 된다
/// (#1170). [demoMemberSuggestionsEn] 과 id·시간·유형·세트·근거가 같다.
const Map<String, List<RoutineSuggestion>> demoMemberSuggestionsKo =
    <String, List<RoutineSuggestion>>{
      'seed-client-2': <RoutineSuggestion>[
        RoutineSuggestion(
          id: 'demo-suggestion-2-step-up',
          name: '스텝업',
          minutes: 12,
          type: '근력',
          sets: 3,
          reps: 12,
          weight: 0,
          reason:
              '최근 AI 개인운동 완료율이 100%·67%로 잘 따라오고 있어요. 스쿼트와 다른 각도로 하체를 채우기 좋아요.',
          evidence: <String>[RoutineEvidence.recentRecord],
        ),
        RoutineSuggestion(
          id: 'demo-suggestion-2-weekend-cycle',
          name: '주말 가벼운 사이클',
          minutes: 30,
          type: '유산소',
          reason: '주말 기록이 비어 있어요. 부담 없는 유산소 하나로 주말 흐름을 이어 가기 좋아요.',
          evidence: <String>[RoutineEvidence.lowCardio],
        ),
        RoutineSuggestion(
          id: 'demo-suggestion-2-hamstring-stretch',
          name: '햄스트링 스트레칭',
          minutes: 10,
          type: '스트레칭',
          reason: '인터벌 런닝과 스쿼트가 이어지는 주예요. 허벅지 뒤쪽을 풀어 회복을 돕기 좋아요.',
          evidence: <String>[RoutineEvidence.recentRecord],
        ),
      ],
      'seed-client-3': <RoutineSuggestion>[
        RoutineSuggestion(
          id: 'demo-suggestion-3-light-circuit',
          name: '가벼운 전신 순환',
          minutes: 15,
          type: '근력',
          sets: 2,
          reps: 10,
          weight: 0,
          reason: '최근 AI 개인운동 완료율이 33%·0%예요. 무게를 낮춘 짧은 순환으로 다시 시작하기 좋아요.',
          evidence: <String>[RoutineEvidence.recentRecord],
        ),
        RoutineSuggestion(
          id: 'demo-suggestion-3-brisk-walk',
          name: '빠르게 걷기',
          minutes: 20,
          type: '유산소',
          reason: '최근 운동이 모두 근력이에요. 짧은 유산소로 회복을 돕기 좋아요.',
          evidence: <String>[
            RoutineEvidence.strengthHeavy,
            RoutineEvidence.lowCardio,
          ],
        ),
        RoutineSuggestion(
          id: 'demo-suggestion-3-chest-shoulder-stretch',
          name: '가슴·어깨 스트레칭',
          minutes: 10,
          type: '스트레칭',
          reason: '벤치프레스 위주의 상체 운동이 많아요. 가슴과 어깨 앞쪽을 풀어 두기 좋아요.',
          evidence: <String>[RoutineEvidence.strengthHeavy],
        ),
      ],
      'seed-client-4': <RoutineSuggestion>[
        RoutineSuggestion(
          id: 'demo-suggestion-4-bird-dog',
          name: '버드독',
          minutes: 10,
          type: '근력',
          sets: 3,
          reps: 10,
          weight: 0,
          reason: '최근 PT 에서 코어 재활을 이어 가기로 했어요. 골반 안정화 다음 단계로 좋아요.',
          evidence: <String>[RoutineEvidence.recentPtFeedback],
        ),
        RoutineSuggestion(
          id: 'demo-suggestion-4-water-walk',
          name: '수중 걷기',
          minutes: 20,
          type: '유산소',
          reason: '이번 주 완료율이 0%에서 100%로 회복 중이에요. 관절 부담이 적은 유산소로 흐름을 이어 가기 좋아요.',
          evidence: <String>[RoutineEvidence.recentRecord],
        ),
        RoutineSuggestion(
          id: 'demo-suggestion-4-cat-cow',
          name: '고양이-소 자세',
          minutes: 8,
          type: '스트레칭',
          reason: '코어 재활을 이어 가는 중이에요. 척추를 부드럽게 움직여 몸을 풀어 두기 좋아요.',
          evidence: <String>[RoutineEvidence.recentPtFeedback],
        ),
      ],
      'seed-client-5': <RoutineSuggestion>[
        RoutineSuggestion(
          id: 'demo-suggestion-5-tempo-run',
          name: '템포 러닝',
          minutes: 25,
          type: '유산소',
          reason: '최근 AI 개인운동을 모두 100% 마쳤어요. 장거리 러닝 사이에 템포 구간을 더해 강도를 올리기 좋아요.',
          evidence: <String>[RoutineEvidence.recentRecord],
        ),
        RoutineSuggestion(
          id: 'demo-suggestion-5-single-leg-deadlift',
          name: '싱글 레그 데드리프트',
          minutes: 12,
          type: '근력',
          sets: 3,
          reps: 10,
          weight: 8,
          reason: '유산소 비중이 높아요. 한 발 근력으로 러닝 자세를 받쳐 주기 좋아요.',
          evidence: <String>[RoutineEvidence.recentRecord],
        ),
        RoutineSuggestion(
          id: 'demo-suggestion-5-foam-roll',
          name: '폼롤러 이완',
          minutes: 10,
          type: '스트레칭',
          reason: '러닝 거리가 길어요. 종아리와 허벅지를 폼롤러로 풀어 회복을 돕기 좋아요.',
          evidence: <String>[RoutineEvidence.recentRecord],
        ),
      ],
      'seed-client-6': <RoutineSuggestion>[
        RoutineSuggestion(
          id: 'demo-suggestion-6-weekend-bike',
          name: '주말 아침 자전거 인터벌',
          minutes: 20,
          type: '유산소',
          reason: '평일 개인운동은 100%인데 주말은 0%예요. 주말 아침 짧은 유산소로 흐름을 잡기 좋아요.',
          evidence: <String>[RoutineEvidence.recentRecord],
        ),
        RoutineSuggestion(
          id: 'demo-suggestion-6-kettlebell-swing',
          name: '케틀벨 스윙',
          minutes: 12,
          type: '근력',
          sets: 3,
          reps: 15,
          weight: 8,
          reason: '체중 감량이 목표예요. 전신을 쓰는 근력 운동으로 소모량을 늘리기 좋아요.',
          evidence: <String>[RoutineEvidence.recentRecord],
        ),
        RoutineSuggestion(
          id: 'demo-suggestion-6-lower-body-stretch',
          name: '하체 스트레칭',
          minutes: 10,
          type: '스트레칭',
          reason: '평일 서킷이 꾸준해요. 하체를 풀어 주말까지 흐름을 이어 가기 좋아요.',
          evidence: <String>[RoutineEvidence.recentRecord],
        ),
      ],
      'seed-client-7': <RoutineSuggestion>[
        RoutineSuggestion(
          id: 'demo-suggestion-7-wall-alignment',
          name: '벽 자세 정렬',
          minutes: 10,
          type: '스트레칭',
          reason: '아직 운동 기록이 없어요. 첫 주에는 자세 기준선을 잡는 가벼운 동작이 좋아요.',
          evidence: <String>[RoutineEvidence.recentRecord],
        ),
        RoutineSuggestion(
          id: 'demo-suggestion-7-glute-bridge',
          name: '글루트 브리지',
          minutes: 10,
          type: '근력',
          sets: 3,
          reps: 12,
          weight: 0,
          reason: '첫 주라 부담 없는 맨몸 근력으로 엉덩이·허리 기준선을 잡기 좋아요.',
          evidence: <String>[RoutineEvidence.recentRecord],
        ),
        RoutineSuggestion(
          id: 'demo-suggestion-7-easy-walk',
          name: '가벼운 걷기',
          minutes: 15,
          type: '유산소',
          reason: '아직 운동 기록이 없어요. 짧은 걷기로 몸을 움직이는 습관부터 들이기 좋아요.',
          evidence: <String>[RoutineEvidence.lowCardio],
        ),
      ],
      'seed-client-8': <RoutineSuggestion>[
        RoutineSuggestion(
          id: 'demo-suggestion-8-knee-to-chest',
          name: '누워서 무릎 당기기',
          minutes: 10,
          type: '스트레칭',
          reason: '대화에서 허리 통증을 말했어요. 허리에 부담 없이 풀어 주는 동작이 좋아요.',
          evidence: <String>[RoutineEvidence.recentRecord],
        ),
        RoutineSuggestion(
          id: 'demo-suggestion-8-indoor-cycle',
          name: '실내 자전거',
          minutes: 15,
          type: '유산소',
          reason: '혈압 관리가 목표인데 최근 완료율이 20%·33%예요. 앉아서 하는 짧은 유산소로 부담을 낮추기 좋아요.',
          evidence: <String>[
            RoutineEvidence.bloodPressureGoal,
            RoutineEvidence.recentRecord,
          ],
        ),
        RoutineSuggestion(
          id: 'demo-suggestion-8-wall-push-up',
          name: '벽 푸시업',
          minutes: 8,
          type: '근력',
          sets: 2,
          reps: 10,
          weight: 0,
          reason: '혈압 관리가 목표라 숨을 참지 않는 가벼운 상체 근력이 좋아요.',
          evidence: <String>[RoutineEvidence.bloodPressureGoal],
        ),
      ],
      'seed-client-9': <RoutineSuggestion>[
        RoutineSuggestion(
          id: 'demo-suggestion-9-stair-climb',
          name: '5분 계단 오르기',
          minutes: 5,
          type: '유산소',
          reason: '최근 완료율이 25%·33%예요. 퇴근길 5분이면 이어 가기 쉬워요.',
          evidence: <String>[RoutineEvidence.recentRecord],
        ),
        RoutineSuggestion(
          id: 'demo-suggestion-9-desk-stretch',
          name: '책상 앞 흉추 스트레칭',
          minutes: 5,
          type: '스트레칭',
          reason: '앉아 있는 시간이 길어요. 업무 중 짧게 등 위쪽을 풀어 주기 좋아요.',
          evidence: <String>[RoutineEvidence.recentRecord],
        ),
        RoutineSuggestion(
          id: 'demo-suggestion-9-chair-squat',
          name: '의자 스쿼트',
          minutes: 5,
          type: '근력',
          sets: 2,
          reps: 10,
          weight: 0,
          reason: '최근 완료율이 25%·33%예요. 집에서 5분이면 끝나는 하체 근력으로 이어 가기 좋아요.',
          evidence: <String>[RoutineEvidence.recentRecord],
        ),
      ],
      'seed-client-10': <RoutineSuggestion>[
        RoutineSuggestion(
          id: 'demo-suggestion-10-band-side-step',
          name: '미니 밴드 사이드 스텝',
          minutes: 10,
          type: '근력',
          sets: 3,
          reps: 12,
          weight: 0,
          reason: '완료율이 67%에서 100%로 올라가고 있어요. 무릎을 받쳐 줄 엉덩이 근력을 더하기 좋아요.',
          evidence: <String>[RoutineEvidence.recentRecord],
        ),
        RoutineSuggestion(
          id: 'demo-suggestion-10-flat-walk',
          name: '평지 걷기',
          minutes: 20,
          type: '유산소',
          reason: '무릎 재활 중이에요. 경사 없는 길을 걸어 유산소를 조금씩 늘리기 좋아요.',
          evidence: <String>[RoutineEvidence.lowCardio],
        ),
        RoutineSuggestion(
          id: 'demo-suggestion-10-hamstring-stretch',
          name: '햄스트링 스트레칭',
          minutes: 10,
          type: '스트레칭',
          reason: '레그 익스텐션으로 앞쪽을 쓰는 만큼 허벅지 뒤쪽을 풀어 균형을 맞추기 좋아요.',
          evidence: <String>[RoutineEvidence.recentRecord],
        ),
      ],
      'seed-client-11': <RoutineSuggestion>[
        RoutineSuggestion(
          id: 'demo-suggestion-11-rowing',
          name: '로잉 머신 인터벌',
          minutes: 15,
          type: '유산소',
          reason: '완료율이 목표선 근처에서 오르내려요. 새 자극으로 정체 구간을 바꾸기 좋아요.',
          evidence: <String>[RoutineEvidence.recentRecord],
        ),
        RoutineSuggestion(
          id: 'demo-suggestion-11-goblet-squat',
          name: '고블릿 스쿼트',
          minutes: 12,
          type: '근력',
          sets: 3,
          reps: 10,
          weight: 12,
          reason: '지금 프로그램은 상체 위주예요. 하체 근력을 함께 채우기 좋아요.',
          evidence: <String>[RoutineEvidence.recentRecord],
        ),
        RoutineSuggestion(
          id: 'demo-suggestion-11-hip-stretch',
          name: '고관절 스트레칭',
          minutes: 10,
          type: '스트레칭',
          reason: '새 자극을 더하는 만큼 고관절을 풀어 회복을 챙기기 좋아요.',
          evidence: <String>[RoutineEvidence.recentRecord],
        ),
      ],
      'seed-client-12': <RoutineSuggestion>[
        RoutineSuggestion(
          id: 'demo-suggestion-12-short-walk',
          name: '10분 동네 걷기',
          minutes: 10,
          type: '유산소',
          reason: '3주째 운동 기록이 없어요. 아주 짧은 걷기로 복귀를 시작하기 좋아요.',
          evidence: <String>[RoutineEvidence.recentRecord],
        ),
        RoutineSuggestion(
          id: 'demo-suggestion-12-wall-push-up',
          name: '벽 푸시업',
          minutes: 8,
          type: '근력',
          sets: 2,
          reps: 10,
          weight: 0,
          reason: '3주 쉬었어요. 벽에 기대는 가벼운 근력으로 다시 시작하기 좋아요.',
          evidence: <String>[RoutineEvidence.recentRecord],
        ),
        RoutineSuggestion(
          id: 'demo-suggestion-12-foam-roll',
          name: '폼롤러 이완',
          minutes: 10,
          type: '스트레칭',
          reason: '복귀 첫 주예요. 몸을 풀어 두면 다음 운동이 덜 부담스러워요.',
          evidence: <String>[RoutineEvidence.recentRecord],
        ),
      ],
      'seed-client-13': <RoutineSuggestion>[
        RoutineSuggestion(
          id: 'demo-suggestion-13-incline-walk',
          name: '인클라인 걷기',
          minutes: 15,
          type: '유산소',
          reason: '최근 운동이 대부분 근력이에요. 가벼운 유산소로 회복을 돕기 좋아요.',
          evidence: <String>[
            RoutineEvidence.strengthHeavy,
            RoutineEvidence.lowCardio,
          ],
        ),
        RoutineSuggestion(
          id: 'demo-suggestion-13-romanian-deadlift',
          name: '루마니안 데드리프트',
          minutes: 15,
          type: '근력',
          sets: 4,
          reps: 8,
          weight: 60,
          reason: '하체 볼륨을 늘리는 중이에요. 몸 뒤쪽 근육을 함께 채우기 좋아요.',
          evidence: <String>[RoutineEvidence.strengthHeavy],
        ),
        RoutineSuggestion(
          id: 'demo-suggestion-13-hip-stretch',
          name: '고관절 스트레칭',
          minutes: 10,
          type: '스트레칭',
          reason: '하체 볼륨이 커요. 고관절을 풀어 다음 스쿼트를 준비하기 좋아요.',
          evidence: <String>[RoutineEvidence.strengthHeavy],
        ),
      ],
      'seed-client-14': <RoutineSuggestion>[
        RoutineSuggestion(
          id: 'demo-suggestion-14-after-dinner-walk',
          name: '저녁 식후 걷기',
          minutes: 20,
          type: '유산소',
          reason: '운동은 잘 지키고 있어요. 나트륨이 높은 날에는 식후 걷기로 균형을 잡기 좋아요.',
          evidence: <String>[RoutineEvidence.recentRecord],
        ),
        RoutineSuggestion(
          id: 'demo-suggestion-14-kettlebell-deadlift',
          name: '케틀벨 데드리프트',
          minutes: 12,
          type: '근력',
          sets: 3,
          reps: 12,
          weight: 12,
          reason: '운동을 잘 지키고 있어요. 전신 서킷에 뒤쪽 근육을 더해 균형을 맞추기 좋아요.',
          evidence: <String>[RoutineEvidence.recentRecord],
        ),
        RoutineSuggestion(
          id: 'demo-suggestion-14-hamstring-stretch',
          name: '햄스트링 스트레칭',
          minutes: 10,
          type: '스트레칭',
          reason: '러닝머신과 서킷을 꾸준히 해요. 허벅지 뒤쪽을 풀어 회복을 돕기 좋아요.',
          evidence: <String>[RoutineEvidence.recentRecord],
        ),
      ],
      'seed-client-15': <RoutineSuggestion>[
        RoutineSuggestion(
          id: 'demo-suggestion-15-morning-stretch',
          name: '5분 아침 스트레칭',
          minutes: 5,
          type: '스트레칭',
          reason: '운동 기록이 하루뿐이에요. 매일 할 수 있는 짧은 동작으로 습관을 만들기 좋아요.',
          evidence: <String>[RoutineEvidence.recentRecord],
        ),
        RoutineSuggestion(
          id: 'demo-suggestion-15-glute-bridge',
          name: '글루트 브리지',
          minutes: 10,
          type: '근력',
          sets: 3,
          reps: 12,
          weight: 0,
          reason: '기록이 하루뿐이에요. 누워서 하는 가벼운 근력으로 부담 없이 이어 가기 좋아요.',
          evidence: <String>[RoutineEvidence.recentRecord],
        ),
        RoutineSuggestion(
          id: 'demo-suggestion-15-short-walk',
          name: '10분 걷기',
          minutes: 10,
          type: '유산소',
          reason: '매일 할 수 있는 짧은 걷기로 습관을 만들기 좋아요.',
          evidence: <String>[RoutineEvidence.lowCardio],
        ),
      ],
    };

/// [demoMemberSuggestionsKo] 의 영어판. id·시간·유형·세트·근거는 같고 이름·
/// 사유만 다르다.
const Map<String, List<RoutineSuggestion>>
demoMemberSuggestionsEn = <String, List<RoutineSuggestion>>{
  'seed-client-2': <RoutineSuggestion>[
    RoutineSuggestion(
      id: 'demo-suggestion-2-step-up',
      name: 'Step-up',
      minutes: 12,
      type: '근력',
      sets: 3,
      reps: 12,
      weight: 0,
      reason:
          'Recent personal exercises were 100% and 67% complete. Step-ups '
          'load the legs from a different angle than squats.',
      evidence: <String>[RoutineEvidence.recentRecord],
    ),
    RoutineSuggestion(
      id: 'demo-suggestion-2-weekend-cycle',
      name: 'Easy weekend cycling',
      minutes: 30,
      type: '유산소',
      reason:
          'Weekends have no records. One easy cardio workout keeps the '
          'weekend going.',
      evidence: <String>[RoutineEvidence.lowCardio],
    ),
    RoutineSuggestion(
      id: 'demo-suggestion-2-hamstring-stretch',
      name: 'Hamstring stretch',
      minutes: 10,
      type: '스트레칭',
      reason:
          'Interval runs and squats run back to back this week. Loosening the hamstrings aids recovery.',
      evidence: <String>[RoutineEvidence.recentRecord],
    ),
  ],
  'seed-client-3': <RoutineSuggestion>[
    RoutineSuggestion(
      id: 'demo-suggestion-3-light-circuit',
      name: 'Light full-body circuit',
      minutes: 15,
      type: '근력',
      sets: 2,
      reps: 10,
      weight: 0,
      reason:
          'Recent personal exercises were 33% and 0% complete. A short, '
          'lighter circuit is an easier restart.',
      evidence: <String>[RoutineEvidence.recentRecord],
    ),
    RoutineSuggestion(
      id: 'demo-suggestion-3-brisk-walk',
      name: 'Brisk walk',
      minutes: 20,
      type: '유산소',
      reason:
          'Recent workouts were all strength. A short cardio workout '
          'helps recovery.',
      evidence: <String>[
        RoutineEvidence.strengthHeavy,
        RoutineEvidence.lowCardio,
      ],
    ),
    RoutineSuggestion(
      id: 'demo-suggestion-3-chest-shoulder-stretch',
      name: 'Chest & shoulder stretch',
      minutes: 10,
      type: '스트레칭',
      reason:
          'Upper-body work is mostly bench press. Opening the chest and front shoulders helps.',
      evidence: <String>[RoutineEvidence.strengthHeavy],
    ),
  ],
  'seed-client-4': <RoutineSuggestion>[
    RoutineSuggestion(
      id: 'demo-suggestion-4-bird-dog',
      name: 'Bird dog',
      minutes: 10,
      type: '근력',
      sets: 3,
      reps: 10,
      weight: 0,
      reason:
          'At the last PT we agreed to keep up core rehab. A good next '
          'step after pelvic stabilization.',
      evidence: <String>[RoutineEvidence.recentPtFeedback],
    ),
    RoutineSuggestion(
      id: 'demo-suggestion-4-water-walk',
      name: 'Water walking',
      minutes: 20,
      type: '유산소',
      reason:
          'Completion is recovering from 0% to 100% this week. '
          'Low-impact cardio keeps the momentum.',
      evidence: <String>[RoutineEvidence.recentRecord],
    ),
    RoutineSuggestion(
      id: 'demo-suggestion-4-cat-cow',
      name: 'Cat-cow',
      minutes: 8,
      type: '스트레칭',
      reason:
          'Core rehab is ongoing. Gentle spinal movement keeps the back loose.',
      evidence: <String>[RoutineEvidence.recentPtFeedback],
    ),
  ],
  'seed-client-5': <RoutineSuggestion>[
    RoutineSuggestion(
      id: 'demo-suggestion-5-tempo-run',
      name: 'Tempo run',
      minutes: 25,
      type: '유산소',
      reason:
          'Recent personal exercises were all 100% complete. Tempo '
          'segments between long runs raise the intensity.',
      evidence: <String>[RoutineEvidence.recentRecord],
    ),
    RoutineSuggestion(
      id: 'demo-suggestion-5-single-leg-deadlift',
      name: 'Single-leg deadlift',
      minutes: 12,
      type: '근력',
      sets: 3,
      reps: 10,
      weight: 8,
      reason:
          'Cardio dominates the plan. Single-leg strength steadies the '
          'running stride.',
      evidence: <String>[RoutineEvidence.recentRecord],
    ),
    RoutineSuggestion(
      id: 'demo-suggestion-5-foam-roll',
      name: 'Foam rolling',
      minutes: 10,
      type: '스트레칭',
      reason:
          'Running volume is high. Rolling the calves and thighs aids recovery.',
      evidence: <String>[RoutineEvidence.recentRecord],
    ),
  ],
  'seed-client-6': <RoutineSuggestion>[
    RoutineSuggestion(
      id: 'demo-suggestion-6-weekend-bike',
      name: 'Weekend morning bike intervals',
      minutes: 20,
      type: '유산소',
      reason:
          'Weekday workouts are 100% but weekends are 0%. A short '
          'weekend-morning cardio workout holds the rhythm.',
      evidence: <String>[RoutineEvidence.recentRecord],
    ),
    RoutineSuggestion(
      id: 'demo-suggestion-6-kettlebell-swing',
      name: 'Kettlebell swing',
      minutes: 12,
      type: '근력',
      sets: 3,
      reps: 15,
      weight: 8,
      reason:
          'Weight loss is the goal. A full-body strength move raises '
          'energy use.',
      evidence: <String>[RoutineEvidence.recentRecord],
    ),
    RoutineSuggestion(
      id: 'demo-suggestion-6-lower-body-stretch',
      name: 'Lower-body stretch',
      minutes: 10,
      type: '스트레칭',
      reason:
          'Weekday circuits are steady. A lower-body stretch keeps the rhythm into the weekend.',
      evidence: <String>[RoutineEvidence.recentRecord],
    ),
  ],
  'seed-client-7': <RoutineSuggestion>[
    RoutineSuggestion(
      id: 'demo-suggestion-7-wall-alignment',
      name: 'Wall posture alignment',
      minutes: 10,
      type: '스트레칭',
      reason:
          'No workout records yet. Light moves that set a posture '
          'baseline suit the first week.',
      evidence: <String>[RoutineEvidence.recentRecord],
    ),
    RoutineSuggestion(
      id: 'demo-suggestion-7-glute-bridge',
      name: 'Glute bridge',
      minutes: 10,
      type: '근력',
      sets: 3,
      reps: 12,
      weight: 0,
      reason:
          'First week — a light bodyweight move sets a glute and lower-back baseline.',
      evidence: <String>[RoutineEvidence.recentRecord],
    ),
    RoutineSuggestion(
      id: 'demo-suggestion-7-easy-walk',
      name: 'Easy walk',
      minutes: 15,
      type: '유산소',
      reason:
          'No workout records yet. A short walk starts the habit of moving.',
      evidence: <String>[RoutineEvidence.lowCardio],
    ),
  ],
  'seed-client-8': <RoutineSuggestion>[
    RoutineSuggestion(
      id: 'demo-suggestion-8-knee-to-chest',
      name: 'Supine knee-to-chest',
      minutes: 10,
      type: '스트레칭',
      reason:
          'Lower-back pain came up in chat. A stretch that eases the back '
          'without load fits.',
      evidence: <String>[RoutineEvidence.recentRecord],
    ),
    RoutineSuggestion(
      id: 'demo-suggestion-8-indoor-cycle',
      name: 'Indoor cycling',
      minutes: 15,
      type: '유산소',
      reason:
          'Blood pressure is a goal, but recent completion was 20% and '
          '33%. Short seated cardio lowers the barrier.',
      evidence: <String>[
        RoutineEvidence.bloodPressureGoal,
        RoutineEvidence.recentRecord,
      ],
    ),
    RoutineSuggestion(
      id: 'demo-suggestion-8-wall-push-up',
      name: 'Wall push-up',
      minutes: 8,
      type: '근력',
      sets: 2,
      reps: 10,
      weight: 0,
      reason:
          'Blood pressure is a goal, so light upper-body work without breath-holding fits.',
      evidence: <String>[RoutineEvidence.bloodPressureGoal],
    ),
  ],
  'seed-client-9': <RoutineSuggestion>[
    RoutineSuggestion(
      id: 'demo-suggestion-9-stair-climb',
      name: '5-minute stair climb',
      minutes: 5,
      type: '유산소',
      reason:
          'Recent completion was 25% and 33%. Five minutes on the way '
          'home is easy to keep.',
      evidence: <String>[RoutineEvidence.recentRecord],
    ),
    RoutineSuggestion(
      id: 'demo-suggestion-9-desk-stretch',
      name: 'Desk thoracic stretch',
      minutes: 5,
      type: '스트레칭',
      reason:
          'Long hours of sitting. A short break at the desk loosens the '
          'upper back.',
      evidence: <String>[RoutineEvidence.recentRecord],
    ),
    RoutineSuggestion(
      id: 'demo-suggestion-9-chair-squat',
      name: 'Chair squat',
      minutes: 5,
      type: '근력',
      sets: 2,
      reps: 10,
      weight: 0,
      reason:
          'Recent completion was 25% and 33%. A five-minute lower-body move at home keeps it going.',
      evidence: <String>[RoutineEvidence.recentRecord],
    ),
  ],
  'seed-client-10': <RoutineSuggestion>[
    RoutineSuggestion(
      id: 'demo-suggestion-10-band-side-step',
      name: 'Mini-band side step',
      minutes: 10,
      type: '근력',
      sets: 3,
      reps: 12,
      weight: 0,
      reason:
          'Completion is rising from 67% to 100%. Glute work supports the '
          'knee.',
      evidence: <String>[RoutineEvidence.recentRecord],
    ),
    RoutineSuggestion(
      id: 'demo-suggestion-10-flat-walk',
      name: 'Flat-ground walk',
      minutes: 20,
      type: '유산소',
      reason:
          'Knee rehab is ongoing. Walking on flat ground adds cardio gradually.',
      evidence: <String>[RoutineEvidence.lowCardio],
    ),
    RoutineSuggestion(
      id: 'demo-suggestion-10-hamstring-stretch',
      name: 'Hamstring stretch',
      minutes: 10,
      type: '스트레칭',
      reason:
          'Leg extensions work the front, so stretching the back of the thigh keeps balance.',
      evidence: <String>[RoutineEvidence.recentRecord],
    ),
  ],
  'seed-client-11': <RoutineSuggestion>[
    RoutineSuggestion(
      id: 'demo-suggestion-11-rowing',
      name: 'Rowing intervals',
      minutes: 15,
      type: '유산소',
      reason:
          'Completion hovers around the target line. A new stimulus can '
          'break the plateau.',
      evidence: <String>[RoutineEvidence.recentRecord],
    ),
    RoutineSuggestion(
      id: 'demo-suggestion-11-goblet-squat',
      name: 'Goblet squat',
      minutes: 12,
      type: '근력',
      sets: 3,
      reps: 10,
      weight: 12,
      reason:
          'The current plan leans on the upper body. Add lower-body '
          'strength alongside.',
      evidence: <String>[RoutineEvidence.recentRecord],
    ),
    RoutineSuggestion(
      id: 'demo-suggestion-11-hip-stretch',
      name: 'Hip stretch',
      minutes: 10,
      type: '스트레칭',
      reason: 'With new stimulus added, loosening the hips supports recovery.',
      evidence: <String>[RoutineEvidence.recentRecord],
    ),
  ],
  'seed-client-12': <RoutineSuggestion>[
    RoutineSuggestion(
      id: 'demo-suggestion-12-short-walk',
      name: '10-minute neighborhood walk',
      minutes: 10,
      type: '유산소',
      reason:
          'No workout records for 3 weeks. A very short walk is an easy '
          'way back.',
      evidence: <String>[RoutineEvidence.recentRecord],
    ),
    RoutineSuggestion(
      id: 'demo-suggestion-12-wall-push-up',
      name: 'Wall push-up',
      minutes: 8,
      type: '근력',
      sets: 2,
      reps: 10,
      weight: 0,
      reason:
          'Three weeks off. A light wall-supported move is an easy restart.',
      evidence: <String>[RoutineEvidence.recentRecord],
    ),
    RoutineSuggestion(
      id: 'demo-suggestion-12-foam-roll',
      name: 'Foam rolling',
      minutes: 10,
      type: '스트레칭',
      reason: 'First week back. Loosening up makes the next workout easier.',
      evidence: <String>[RoutineEvidence.recentRecord],
    ),
  ],
  'seed-client-13': <RoutineSuggestion>[
    RoutineSuggestion(
      id: 'demo-suggestion-13-incline-walk',
      name: 'Incline walk',
      minutes: 15,
      type: '유산소',
      reason:
          'Recent workouts are mostly strength. Light cardio aids '
          'recovery.',
      evidence: <String>[
        RoutineEvidence.strengthHeavy,
        RoutineEvidence.lowCardio,
      ],
    ),
    RoutineSuggestion(
      id: 'demo-suggestion-13-romanian-deadlift',
      name: 'Romanian deadlift',
      minutes: 15,
      type: '근력',
      sets: 4,
      reps: 8,
      weight: 60,
      reason:
          'Lower-body volume is going up. Round it out with the posterior '
          'chain.',
      evidence: <String>[RoutineEvidence.strengthHeavy],
    ),
    RoutineSuggestion(
      id: 'demo-suggestion-13-hip-stretch',
      name: 'Hip stretch',
      minutes: 10,
      type: '스트레칭',
      reason:
          'Lower-body volume is high. Loosening the hips prepares for the next squat day.',
      evidence: <String>[RoutineEvidence.strengthHeavy],
    ),
  ],
  'seed-client-14': <RoutineSuggestion>[
    RoutineSuggestion(
      id: 'demo-suggestion-14-after-dinner-walk',
      name: 'After-dinner walk',
      minutes: 20,
      type: '유산소',
      reason:
          'Workouts are on track. A walk after high-sodium dinners helps '
          'balance.',
      evidence: <String>[RoutineEvidence.recentRecord],
    ),
    RoutineSuggestion(
      id: 'demo-suggestion-14-kettlebell-deadlift',
      name: 'Kettlebell deadlift',
      minutes: 12,
      type: '근력',
      sets: 3,
      reps: 12,
      weight: 12,
      reason:
          'Workouts are on track. Adding the posterior chain balances the full-body circuit.',
      evidence: <String>[RoutineEvidence.recentRecord],
    ),
    RoutineSuggestion(
      id: 'demo-suggestion-14-hamstring-stretch',
      name: 'Hamstring stretch',
      minutes: 10,
      type: '스트레칭',
      reason:
          'Treadmill and circuits are steady. Loosening the hamstrings aids recovery.',
      evidence: <String>[RoutineEvidence.recentRecord],
    ),
  ],
  'seed-client-15': <RoutineSuggestion>[
    RoutineSuggestion(
      id: 'demo-suggestion-15-morning-stretch',
      name: '5-minute morning stretch',
      minutes: 5,
      type: '스트레칭',
      reason:
          'Only one day of workouts recorded. A short daily move builds '
          'the habit.',
      evidence: <String>[RoutineEvidence.recentRecord],
    ),
    RoutineSuggestion(
      id: 'demo-suggestion-15-glute-bridge',
      name: 'Glute bridge',
      minutes: 10,
      type: '근력',
      sets: 3,
      reps: 12,
      weight: 0,
      reason:
          'Only one day recorded. A light lying-down strength move is easy to keep up.',
      evidence: <String>[RoutineEvidence.recentRecord],
    ),
    RoutineSuggestion(
      id: 'demo-suggestion-15-short-walk',
      name: '10-minute walk',
      minutes: 10,
      type: '유산소',
      reason: 'A short daily walk builds the habit.',
      evidence: <String>[RoutineEvidence.lowCardio],
    ),
  ],
};
