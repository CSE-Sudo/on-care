import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_trainer/shared/models/client_signal.dart';
import 'package:oncare_trainer/shared/models/trainer_client.dart';

/// Roster filters reachable from the URL (`/clients?f=unread`).
///
/// The dashboard's KPI cards deep-link straight into these, so the
/// filter is part of the address rather than page-local state — "답장
/// 필요 3건" and the list it opens are the same claim, and a refresh or
/// a shared link must keep showing it.
enum ClientFilter {
  /// Everyone on the roster.
  all('all'),

  /// Clients with unanswered messages.
  unread('unread'),

  /// `주의 회원` — PT 관리 신호가 하나라도 있는 회원([needsAttention], #2204).
  /// Unanswered messages are [unread], not 주의.
  attention('attention');

  const ClientFilter(this.query);

  /// Value used in the `f` query parameter. **URL 계약이라 번역하지 않는다.**
  final String query;

  /// Chip label in the current locale. (#501)
  String label(AppLocalizations l) => switch (this) {
    ClientFilter.all => l.filterAll,
    ClientFilter.unread => l.dashNeedsReply,
    ClientFilter.attention => l.dashAttentionClients,
  };
}

/// Parses the `f` query parameter; anything unrecognised (including
/// null) falls back to [ClientFilter.all] rather than erroring — a stale
/// bookmark should show the roster, not a broken page.
ClientFilter clientFilterFrom(String? raw) {
  for (final filter in ClientFilter.values) {
    if (filter.query == raw) return filter;
  }
  return ClientFilter.all;
}

/// Applies [filter] to [clients], preserving the incoming order.
List<TrainerClient> applyClientFilter(
  List<TrainerClient> clients,
  ClientFilter filter, {
  required Map<String, int> unread,
}) {
  switch (filter) {
    case ClientFilter.all:
      return clients;
    case ClientFilter.unread:
      return clients.where((c) => (unread[c.id] ?? 0) > 0).toList();
    case ClientFilter.attention:
      return clients.where(needsAttention).toList();
  }
}
