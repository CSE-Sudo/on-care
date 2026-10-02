import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare_trainer/app/router/routes.dart';
import 'package:oncare_trainer/features/auth/domain/entities/signup_consent.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 트레이너 가입·재동의 화면의 동의 묶음. (#2819)
///
/// 예전의 "가입하면 아래 문서에 동의하는 것으로 봅니다" 간주 동의를 대신한다.
/// 모양은 회원 앱과 같은 공용 [AppConsentChecklist] 다. 트레이너는 건강정보 처리
/// 동의가 없다.
///
/// 문서 보기는 화면을 갈아치우지 않고 push 로 연다 — 뒤로 누르면 입력하던 값과
/// 체크가 그대로 남는다(#968). 문서 주소는 세션 없이도, 동의 전에도 열린다.
class TrainerConsentBlock extends StatelessWidget {
  const TrainerConsentBlock({
    super.key,
    required this.checked,
    required this.onChanged,
    this.enabled = true,
  });

  final Set<String> checked;
  final ValueChanged<Set<String>> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    void open(String document) =>
        context.push(AppRoutes.legalDocument(document));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppConsentChecklist(
          enabled: enabled,
          checked: checked,
          onChanged: onChanged,
          allLabel: l.consentAll,
          requiredTag: l.consentRequiredTag,
          optionalTag: l.consentOptionalTag,
          viewLabel: l.consentView,
          items: <AppConsentItem>[
            AppConsentItem(
              id: TrainerSignupConsent.terms,
              label: l.consentTerms,
              required: true,
              onView: () => open(AppRoutes.legalTerms),
            ),
            AppConsentItem(
              id: TrainerSignupConsent.privacy,
              label: l.consentPrivacy,
              required: true,
              onView: () => open(AppRoutes.legalPrivacy),
            ),
            AppConsentItem(
              id: TrainerSignupConsent.age14,
              label: l.consentAge14,
              required: true,
              detail: l.consentAge14Detail,
            ),
            AppConsentItem(
              id: TrainerSignupConsent.marketing,
              label: l.consentMarketing,
              required: false,
            ),
          ],
        ),
        // 버튼이 왜 꺼져 있는지 그 자리에서 말해 준다.
        if (!TrainerSignupConsent.hasAllRequired(checked)) ...<Widget>[
          const SizedBox(height: OnCareSpacing.s8),
          Text(
            l.consentRequiredHint,
            key: const ValueKey<String>('consent-required-hint'),
            style: context.oncare
                .text(OnCareTypography.caption)
                .copyWith(color: OnCareColors.textSecondary),
          ),
        ],
      ],
    );
  }
}
