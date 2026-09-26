import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oncare_trainer/core/errors/app_error.dart';
import 'package:oncare_trainer/core/utils/server_message.dart';
import 'package:oncare_trainer/features/clients/data/repositories/client_coach_repository.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 담당 회원에 대해 AI 에게 묻는 시트를 연다. (#497)
Future<void> showClientCoachSheet(
  BuildContext context, {
  required String memberId,
  required String clientName,
}) {
  return showAppDialog<void>(
    context: context,
    builder: (_) =>
        _ClientCoachSheet(memberId: memberId, clientName: clientName),
  );
}

/// AI 코칭 상담 — 이 회원에 대해 묻고, 근거와 함께 답을 받는다.
///
/// 탭이 아니라 시트인 이유: 트레이너가 상시로 보는 화면이 아니라 판단이 필요할
/// 때 한 번 여는 도구다. 대상이 l.coachSheetThisClient이라 고객 상세에서 연다.
///
/// 대화를 이어 가지 않는다 — 서버 엔드포인트가 무상태이고, 회원 앱의 대화
/// 저장(#274)과는 별개 도메인이다. 한 번에 한 질문으로 충분하다.
class _ClientCoachSheet extends ConsumerStatefulWidget {
  const _ClientCoachSheet({required this.memberId, required this.clientName});

  final String memberId;
  final String clientName;

  @override
  ConsumerState<_ClientCoachSheet> createState() => _ClientCoachSheetState();
}

class _ClientCoachSheetState extends ConsumerState<_ClientCoachSheet> {
  final TextEditingController _question = TextEditingController();
  bool _asking = false;
  bool _restoring = true;
  // 최신 답변 하나가 아니라 스레드를 들고 있다(#588). 서버가 문답을 저장하므로
  // 시트를 닫았다 열어도 이어지고, 후속 질문도 앞 문답을 근거로 답한다.
  final List<ClientCoachTurn> _turns = <ClientCoachTurn>[];
  String? _error;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    try {
      final List<ClientCoachTurn> rows = await ref
          .read(clientCoachRepositoryProvider)
          .history(memberId: widget.memberId);
      if (!mounted) return;
      setState(() {
        _turns
          ..clear()
          ..addAll(rows);
        _restoring = false;
      });
    } catch (_) {
      // 복원 실패는 조용히 넘긴다 — 새로 물어보는 건 여전히 되므로, 시트를 열자마자
      // 오류를 띄우면 할 수 있는 일까지 막힌 것처럼 보인다.
      if (!mounted) return;
      setState(() => _restoring = false);
    }
  }

  Future<void> _ask() async {
    final String message = _question.text.trim();
    // 빈 질문은 서버도 400 이다. 왕복할 이유가 없다.
    if (message.isEmpty || _asking || _restoring) return;

    setState(() {
      _asking = true;
      _error = null;
    });
    try {
      final ClientCoachAnswer answer = await ref
          .read(clientCoachRepositoryProvider)
          .ask(memberId: widget.memberId, message: message);
      if (!mounted) return;
      setState(() {
        _turns
          ..add(ClientCoachTurn(isTrainer: true, content: message))
          ..add(
            ClientCoachTurn(
              isTrainer: false,
              content: answer.reply,
              sources: answer.sources,
            ),
          );
        // 보낸 질문은 지운다 — 남겨 두면 다음 질문을 쓸 때마다 지워야 하고,
        // 방금 물은 내용은 이미 위 스레드에 남아 있다.
        _question.clear();
        _asking = false;
      });
    } on AppError catch (e) {
      if (!mounted) return;
      final AppLocalizations l = AppLocalizations.of(context);
      setState(() {
        // 서버가 준 사유가 있으면 그대로(서버 문구의 다국어는 별건), 없으면
        // 오류 종류에 맞는 문구를 화면이 붙인다. (#501)
        final fallback = switch (e) {
          NotFoundError() => l.coachNotMyClient,
          ValidationError() => l.coachDemoUnavailable,
          _ => l.coachAskFailed,
        };
        _error = serverDetailOr(l, e.message, fallback);
        _asking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return AppDialog(
      title: l.coachSheetTitle(widget.clientName),
      size: AppDialogSize.medium,
      // 닫기는 하단 [닫기] 한 곳이다 — 답을 기다리는 동안에는 그 버튼이 잠긴다.
      showClose: false,
      footer: AppButtonPair(
        cancelLabel: l.actionClose,
        onCancel: _asking ? null : () => Navigator.of(context).pop(),
        confirmLabel: _turns.isEmpty ? l.coachSheetAsk : l.coachSheetAskAgain,
        onConfirm: _asking || _restoring ? null : _ask,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            l.coachSheetSubtitle,
            style: tokens
                .text(OnCareTypography.bodySmall)
                .copyWith(color: OnCareColors.textSecondary),
          ),
          if (_restoring) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s16),
            const Center(child: AppLoading.inline()),
          ],
          // 스레드를 입력칸 위에 둔다 — 대화는 위에서 아래로 읽고, 새로 쓰는
          // 칸은 항상 같은 자리(맨 아래)에 있어야 찾지 않는다.
          for (final ClientCoachTurn turn in _turns) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s16),
            _Turn(turn: turn),
            if (turn.sources.isNotEmpty) ...<Widget>[
              const SizedBox(height: OnCareSpacing.s8),
              Text(
                l.coachSheetSources,
                style: tokens
                    .text(OnCareTypography.strong(OnCareTypography.caption))
                    .copyWith(color: OnCareColors.textTertiary),
              ),
              const SizedBox(height: OnCareSpacing.s4),
              for (final String source in turn.sources)
                Text(
                  '· $source',
                  style: tokens
                      .text(OnCareTypography.bodySmall)
                      .copyWith(color: OnCareColors.textSecondary),
                ),
            ],
          ],
          const SizedBox(height: OnCareSpacing.s16),
          AppTextField(
            controller: _question,
            hint: l.coachSheetHint,
            maxLines: 3,
            maxLength: 1000,
            enabled: !_asking && !_restoring,
            onSubmitted: (_) => _ask(),
          ),
          if (_asking) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s16),
            const Center(child: AppLoading.inline()),
          ],
          if (_error != null) ...<Widget>[
            const SizedBox(height: OnCareSpacing.s16),
            AppBanner(tone: AppBannerTone.danger, title: _error!),
          ],
        ],
      ),
    );
  }
}

/// 스레드의 문답 한 칸 — 옅은 브랜드 채움 구획.
///
/// 질문(트레이너)은 강조 굵기의 보조색, 답(AI)은 본문 검정으로 나눈다. 둘 다
/// 같은 구획이라 한 쌍으로 읽힌다.
class _Turn extends StatelessWidget {
  const _Turn({required this.turn});

  final ClientCoachTurn turn;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final TextStyle style = turn.isTrainer
        ? tokens
              .text(OnCareTypography.strong(OnCareTypography.body))
              .copyWith(color: OnCareColors.textSecondary)
        : tokens
              .text(OnCareTypography.body)
              .copyWith(color: OnCareColors.textPrimary);
    return AppTile(child: Text(turn.content, style: style));
  }
}
