import 'package:flutter/material.dart';
import 'package:oncare_trainer/app/app_icons.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 세션에 남긴 글 상자.
///
/// 아이콘 + 제목 + 본문 구조라 [AppBanner] 로 그린다. 제목은 PT 면 회원에게
/// 가는 `트레이너 피드백`, 상담이면 트레이너만 보는 `상담 메모` 다(#2574).
/// 메모지 표시다 — 주의가 아니므로 경고 톤으로 올리지 않는다(#690).
class SessionNoteBox extends StatelessWidget {
  const SessionNoteBox({
    super.key,
    required this.note,
    this.consultation = false,
  });

  final String note;

  /// 상담 일정의 글인가 — 제목을 `상담 메모` 로 부른다.
  final bool consultation;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppBanner(
      icon: AppIcons.note,
      title: consultation ? l.schedConsultNote : l.schedNote,
      message: note,
    );
  }
}

/// 아직 메모가 없는 상담 세션의 자리. (#988)
///
/// 상담은 운동 프로그램을 짜는 자리가 아니라 **무슨 이야기를 나눴는지** 를 적는
/// 자리다. 프로그램이 없다는 안내([SessionNoPlanBox])를 그대로 쓰면, 짜야 할
/// 프로그램이 밀려 있는 것처럼 읽힌다.
///
/// `메모 추가` 는 이 설명과 나란히, 박스 오른쪽에 선다. 예전에는 아래
/// 동작 줄의 다른 동작들과 섞여 있어, "상담은 메모로 남긴다" 는
/// 이 설명과 그 동작을 잇는 자리가 따로 없었다.
class SessionNoNoteBox extends StatelessWidget {
  /// Creates the empty-note hint.
  const SessionNoNoteBox({super.key, required this.onAdd});

  /// 메모를 처음 적는 자리를 연다.
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    return AppTile(
      key: const ValueKey<String>('session-no-note'),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  l.schedNoNote,
                  style: tokens
                      .text(OnCareTypography.label)
                      .copyWith(color: OnCareColors.textSecondary),
                ),
                const SizedBox(height: OnCareSpacing.s2),
                Text(
                  l.schedNoteOnlyHint,
                  style: tokens
                      .text(OnCareTypography.caption)
                      .copyWith(color: OnCareColors.textTertiary),
                ),
              ],
            ),
          ),
          const SizedBox(width: OnCareSpacing.s8),
          // 키는 이 자리 전체에 둔다 — `session_manage_row.dart` 편집 메뉴의
          // `메모` 항목과 같은 키라, 테스트가 이름을 그 자손(여기서는 툴팁)에서
          // 찾는 방식(`noteActionLabel`)을 그대로 쓸 수 있다.
          AppIconButton(
            key: const ValueKey<String>('session-edit-note-chip'),
            icon: AppIcons.note,
            tooltip: l.schedAddConsultNote,
            variant: AppIconButtonVariant.tonal,
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}
