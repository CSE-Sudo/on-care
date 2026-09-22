import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare_trainer/features/clients/domain/entities/member_health_profile.dart';
import 'package:oncare_trainer/shared/services/client_repository.dart';

/// 고객의 건강 프로필 — 그래프가 견주는 **회원 목표**의 출처다(#2156, #2157).
///
/// 회원 앱은 식단·운동 그래프의 목표선을 MY 프로필에서 읽는다(#1139). 트레이너
/// 화면이 코드 상수를 쓰면 회원이 목표를 1,800kcal 로 바꿔도 트레이너는 2,000kcal
/// 선을 보고, 회원 폰에서 초과인 날이 트레이너 화면에서는 안쪽으로 읽힌다.
///
/// 프로필 편집 대화상자가 저장한 뒤 이 provider 를 무효화한다 — 트레이너가 고친
/// 목표가 바로 그래프에 반영된다.
final memberHealthProfileProvider = FutureProvider.autoDispose
    .family<MemberHealthProfile, String>(
      (ref, clientId) =>
          ref.watch(clientRepositoryProvider).fetchHealthProfile(clientId),
    );
