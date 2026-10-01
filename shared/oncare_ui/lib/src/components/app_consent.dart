import 'package:flutter/material.dart';

import 'package:oncare_ui/src/components/app_button.dart';
import 'package:oncare_ui/src/components/app_surfaces.dart';
import 'package:oncare_ui/src/theme/oncare_tokens.dart';
import 'package:oncare_ui/src/tokens/colors.dart';
import 'package:oncare_ui/src/tokens/density.dart';
import 'package:oncare_ui/src/tokens/radius.dart';
import 'package:oncare_ui/src/tokens/spacing.dart';
import 'package:oncare_ui/src/tokens/typography.dart';

/// 동의 목록의 한 줄. (#2819)
///
/// 문구는 앱이 자기 로케일로 넣는다 — 이 패키지에는 번역이 없다.
@immutable
class AppConsentItem {
  const AppConsentItem({
    required this.id,
    required this.label,
    required this.required,
    this.detail,
    this.onView,
  });

  /// 항목 식별자. 서버에 보내는 값과 같은 철자를 쓴다(`terms`·`health` …).
  final String id;

  /// 무엇에 동의하는지. 앞에 [AppConsentChecklist.requiredTag] /
  /// [AppConsentChecklist.optionalTag] 가 붙는다.
  final String label;

  /// 체크해야만 다음으로 갈 수 있는 항목인가.
  final bool required;

  /// 라벨 아래 작은 글씨 — 이 항목이 무엇을 다루는지 한 줄로 알린다.
  final String? detail;

  /// 문서 보기. 있으면 줄 끝에 [AppConsentChecklist.viewLabel] 버튼이 선다.
  final VoidCallback? onView;
}

/// 가입·재동의 화면의 동의 목록 — `전체 동의` 와 항목별 체크. (#2819)
///
/// 두 앱(회원 가입·트레이너 가입·로그인 뒤 재동의)이 같은 모양을 쓴다. 상태는
/// 들고 있지 않는다 — 체크된 항목 집합([checked])을 받고 바뀐 집합을
/// [onChanged] 로 돌려준다. 필수 항목이 모두 체크됐는지는 부르는 쪽이 보고
/// 다음 버튼을 켠다.
///
/// `전체 동의` 는 **선택 항목까지** 모두 켜고 끈다. 모든 항목이 켜져 있을 때만
/// 체크된 것으로 보인다.
class AppConsentChecklist extends StatelessWidget {
  const AppConsentChecklist({
    super.key,
    required this.items,
    required this.checked,
    required this.onChanged,
    required this.allLabel,
    required this.requiredTag,
    required this.optionalTag,
    this.viewLabel,
    this.enabled = true,
  });

  final List<AppConsentItem> items;
  final Set<String> checked;
  final ValueChanged<Set<String>> onChanged;

  /// `전체 동의` 줄의 문구.
  final String allLabel;

  /// 필수 항목 앞에 붙는 꼬리표(`[필수]`).
  final String requiredTag;

  /// 선택 항목 앞에 붙는 꼬리표(`[선택]`).
  final String optionalTag;

  /// 문서 보기 버튼의 문구. 없으면 [AppConsentItem.onView] 가 있어도 버튼을
  /// 세우지 않는다.
  final String? viewLabel;

  /// 요청 중에는 끈다 — 보내는 사이 체크를 바꾸면 보낸 값과 화면이 달라진다.
  final bool enabled;

  bool get _allChecked =>
      items.isNotEmpty &&
      items.every((AppConsentItem i) => checked.contains(i.id));

  void _toggleAll() {
    onChanged(
      _allChecked
          ? <String>{}
          : <String>{for (final AppConsentItem i in items) i.id},
    );
  }

  void _toggle(String id) {
    final Set<String> next = Set<String>.of(checked);
    if (!next.remove(id)) next.add(id);
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return Container(
      key: const ValueKey<String>('consent-checklist'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: OnCareSpacing.s8,
        vertical: OnCareSpacing.s4,
      ),
      decoration: BoxDecoration(
        color: OnCareColors.surfaceCard,
        borderRadius: OnCareRadius.mdAll,
        border: Border.all(color: OnCareColors.lineSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _CheckRow(
            key: const ValueKey<String>('consent-all'),
            value: _allChecked,
            enabled: enabled,
            onTap: _toggleAll,
            label: allLabel,
            labelStyle: tokens
                .text(OnCareTypography.strong(OnCareTypography.body))
                .copyWith(color: OnCareColors.textPrimary),
          ),
          const AppDivider(),
          for (final AppConsentItem item in items)
            _CheckRow(
              key: ValueKey<String>('consent-${item.id}'),
              value: checked.contains(item.id),
              enabled: enabled,
              onTap: () => _toggle(item.id),
              label:
                  '${item.required ? requiredTag : optionalTag} ${item.label}',
              labelStyle: tokens
                  .text(OnCareTypography.bodySmall)
                  .copyWith(color: OnCareColors.textPrimary),
              detail: item.detail,
              trailing: item.onView == null || viewLabel == null
                  ? null
                  : AppButton(
                      key: ValueKey<String>('consent-view-${item.id}'),
                      label: viewLabel!,
                      onPressed: enabled ? item.onView : null,
                      variant: AppButtonVariant.text,
                      size: OnCareButtonSize.small,
                    ),
            ),
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    super.key,
    required this.value,
    required this.enabled,
    required this.onTap,
    required this.label,
    required this.labelStyle,
    this.detail,
    this.trailing,
  });

  final bool value;
  final bool enabled;
  final VoidCallback onTap;
  final String label;
  final TextStyle labelStyle;
  final String? detail;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: OnCareRadius.smAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: OnCareSpacing.s2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 무엇에 동의하는지 이름 없이 `checkbox, not checked` 만 들려서는
            // 안 된다 — 라벨을 함께 읽힌다(#1942 와 같은 이유).
            // 체크 칸을 제 노드로 세운다(container). 그러지 않으면 옆 글자와
            // 한 노드로 합쳐져 라벨이 두 번 이어 붙은 채 읽힌다. 체크 칸
            // 안쪽 의미는 이 노드 하나로 대신한다.
            Semantics(
              container: true,
              checked: value,
              enabled: enabled,
              label: label,
              onTap: enabled ? onTap : null,
              excludeSemantics: true,
              child: Checkbox(
                value: value,
                onChanged: enabled ? (_) => onTap() : null,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                activeColor: tokens.brand.primary,
              ),
            ),
            const SizedBox(width: OnCareSpacing.s4),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: OnCareSpacing.s8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // 이름은 체크 칸 노드 하나로 둔다 — 같은 말이 두 번
                    // 읽히지 않게.
                    ExcludeSemantics(child: Text(label, style: labelStyle)),
                    if (detail != null) ...<Widget>[
                      const SizedBox(height: OnCareSpacing.s2),
                      Text(
                        detail!,
                        style: tokens
                            .text(OnCareTypography.caption)
                            .copyWith(color: OnCareColors.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}
