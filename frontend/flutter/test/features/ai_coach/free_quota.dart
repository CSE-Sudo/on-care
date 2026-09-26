import 'package:oncare/features/ai_coach/domain/entities/ai_chat_quota.dart';

/// 테스트 저장소 대역이 돌려주는 기본 한도 — 무료가 넉넉히 남은 날. (#2145, #2217)
const AiChatQuota kFreeQuota = AiChatQuota(
  freeLimit: 5,
  freeLeft: 5,
  paidLimit: 10,
  paidLeft: 10,
  cost: 50,
  balance: 0,
  next: AiChatNext.free,
);
