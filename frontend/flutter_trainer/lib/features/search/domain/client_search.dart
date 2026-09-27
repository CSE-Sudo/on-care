import 'package:oncare_trainer/shared/models/chat_preview.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';

/// How many matches the 고객 검색 dropdown shows at once. A picker, not a
/// second roster — anything past this is better found on the 고객 tab.
const int clientSearchLimit = 6;

/// Clients matching [query], best match first.
///
/// Ranked rather than merely filtered: a trainer typing 김 wants 김민수
/// before someone whose *goal* happens to contain 김. Three tiers — name
/// prefix, name substring, goal substring — and the incoming order
/// (coaching priority) breaks ties inside a tier, so the same query on
/// the same roster always resolves to the same list.
///
/// A blank query matches nothing. The dropdown is opened by typing, and
/// returning the whole roster would turn a picker into a list the
/// trainer has to read.
List<TrainerClient> searchClients(
  List<TrainerClient> clients,
  String query, {
  int limit = clientSearchLimit,
}) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) return const <TrainerClient>[];

  final ranked = <({int tier, int order, TrainerClient client})>[];
  for (var i = 0; i < clients.length; i++) {
    final client = clients[i];
    final name = client.name.toLowerCase();
    final relatedRecords = <String>[
      client.goal,
      // 미리보기 코드(`@emote`)는 회원의 말이 아니다.
      if (!ChatPreviewCode.isCode(client.lastMessage)) client.lastMessage,
      client.lastRoutine,
    ].join('\n').toLowerCase();
    final tier = name.startsWith(normalized)
        ? 0
        : name.contains(normalized)
        ? 1
        : relatedRecords.contains(normalized)
        ? 2
        : -1;
    if (tier < 0) continue;
    ranked.add((tier: tier, order: i, client: client));
  }

  // `List.sort` is not stable in Dart, so the roster position is an
  // explicit tiebreaker rather than something we hope survives.
  ranked.sort((a, b) {
    final byTier = a.tier.compareTo(b.tier);
    return byTier != 0 ? byTier : a.order.compareTo(b.order);
  });

  return <TrainerClient>[for (final match in ranked.take(limit)) match.client];
}
