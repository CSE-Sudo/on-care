import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/features/reports/data/report_send_log.dart';
import 'package:oncare_trainer/features/reports/data/repositories/report_repository.dart';
import 'package:oncare_trainer/features/reports/domain/member_report_history.dart';

export 'package:oncare_trainer/features/reports/domain/member_report_history.dart';

/// 회원별 지난 리포트 화면이 들고 있는 것 — 지금까지 불러온 줄과 다음 쪽. (#2394)
class MemberReportHistoryState {
  /// Creates a state.
  const MemberReportHistoryState({
    required this.items,
    this.nextBefore,
    this.loadingMore = false,
    this.loadMoreFailed = false,
  });

  /// 불러온 줄, 최신 주부터.
  final List<MemberReportHistoryItem> items;

  /// 다음 쪽 커서. 더 없으면 null.
  final DateTime? nextBefore;

  /// `더 보기` 를 불러오는 중이다 — 버튼을 두 번 눌러 같은 쪽이 두 번 붙지
  /// 않게 한다.
  final bool loadingMore;

  /// 마지막 `더 보기` 가 실패했다. 이미 불러온 줄은 그대로 둔다.
  final bool loadMoreFailed;

  /// 더 불러올 쪽이 있는가.
  bool get hasMore => nextBefore != null;

  /// 가장 오래된 불러온 주. 없으면 null.
  DateTime? get oldestLoaded => items.isEmpty ? null : items.last.weekStart;

  /// 바꾼 사본.
  MemberReportHistoryState copyWith({
    List<MemberReportHistoryItem>? items,
    DateTime? nextBefore,
    bool clearNextBefore = false,
    bool? loadingMore,
    bool? loadMoreFailed,
  }) => MemberReportHistoryState(
    items: items ?? this.items,
    nextBefore: clearNextBefore ? null : (nextBefore ?? this.nextBefore),
    loadingMore: loadingMore ?? this.loadingMore,
    loadMoreFailed: loadMoreFailed ?? this.loadMoreFailed,
  );
}

/// 한 회원의 지난 리포트를 쪽 단위로 읽는다. (#2394)
///
/// 첫 쪽은 화면이 열릴 때, 다음 쪽은 [loadMore] 로 읽는다. `autoDispose` 다 —
/// 화면을 다시 열 때마다 새로 물어, 다른 탭이나 기기에서 보낸 것도 그때
/// 들어온다.
class MemberReportHistoryController
    extends AutoDisposeFamilyAsyncNotifier<MemberReportHistoryState, String> {
  @override
  Future<MemberReportHistoryState> build(String arg) async {
    final MemberReportHistoryPage page = await ref
        .watch(reportRepositoryProvider)
        .memberReportHistory(clientId: arg);
    return MemberReportHistoryState(
      items: page.items,
      nextBefore: page.nextBefore,
    );
  }

  /// 다음 쪽을 불러와 뒤에 붙인다. 더 없거나 이미 불러오는 중이면 아무것도
  /// 하지 않는다.
  ///
  /// 실패해도 이미 불러온 줄은 지우지 않는다 — 화면 전체를 실패로 바꾸면
  /// 방금까지 읽던 목록이 사라진다. [MemberReportHistoryState.loadMoreFailed]
  /// 로만 알린다.
  Future<void> loadMore() async {
    final MemberReportHistoryState? current = state.valueOrNull;
    if (current == null || !current.hasMore || current.loadingMore) return;
    state = AsyncData<MemberReportHistoryState>(
      current.copyWith(loadingMore: true, loadMoreFailed: false),
    );
    try {
      final MemberReportHistoryPage page = await ref
          .read(reportRepositoryProvider)
          .memberReportHistory(clientId: arg, before: current.nextBefore);
      final Set<DateTime> seen = <DateTime>{
        for (final MemberReportHistoryItem item in current.items)
          item.weekStart,
      };
      state = AsyncData<MemberReportHistoryState>(
        MemberReportHistoryState(
          items: <MemberReportHistoryItem>[
            ...current.items,
            for (final MemberReportHistoryItem item in page.items)
              if (!seen.contains(item.weekStart)) item,
          ],
          nextBefore: page.nextBefore,
        ),
      );
    } catch (_) {
      state = AsyncData<MemberReportHistoryState>(
        current.copyWith(loadingMore: false, loadMoreFailed: true),
      );
    }
  }
}

/// 저장소에서 읽은 한 회원의 지난 리포트. (#2394)
final memberReportHistoryProvider = AsyncNotifierProvider.autoDispose
    .family<MemberReportHistoryController, MemberReportHistoryState, String>(
      MemberReportHistoryController.new,
    );

/// 화면이 그리는 지난 리포트 — [memberReportHistoryProvider] 에 이번 세션에
/// 보낸 기록([reportSendLogProvider])을 얹는다. (#2394)
///
/// 같은 주는 세션 기록이 이긴다([mergeMemberHistory]) — 방금 보낸 리포트가
/// 서버에서 돌아오기 전에도 목록 맨 위에 선다. 불러오는 중·실패는 그대로
/// 넘긴다.
final memberReportHistoryViewProvider = Provider.autoDispose
    .family<AsyncValue<MemberReportHistoryState>, String>((ref, clientId) {
      final AsyncValue<MemberReportHistoryState> fetched = ref.watch(
        memberReportHistoryProvider(clientId),
      );
      final Map<String, ReportSendRecord> session = ref.watch(
        reportSendLogProvider,
      );
      return fetched.whenData(
        (MemberReportHistoryState s) => s.copyWith(
          items: mergeMemberHistory(
            fetched: s.items,
            session: session,
            clientId: clientId,
            oldestLoaded: s.hasMore ? s.oldestLoaded : null,
          ),
        ),
      );
    });
