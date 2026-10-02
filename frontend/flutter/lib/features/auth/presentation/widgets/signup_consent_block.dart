import 'package:flutter/material.dart';

import 'package:oncare/features/auth/domain/signup_consent.dart';
import 'package:oncare/features/my_health/presentation/widgets/my_flows.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 회원 가입·재동의 화면의 동의 묶음. (#2819)
///
/// 항목과 문구만 이 앱이 정하고 모양은 공용 [AppConsentChecklist] 를 쓴다.
/// 건강정보 처리 동의는 개인정보 수집·이용과 **분리한 별도 체크**다.
///
/// 문서 보기는 MY 탭에서 여는 그 문서 화면([LegalDocumentPage])을 띄운다 —
/// 본문을 두 벌 두지 않는다. 라우터 주소(`/my-health/settings/...`)로 가지 않고
/// 화면을 바로 쌓는 이유: 가입 중에는 로그아웃 상태라 그 주소가 로그인 화면으로
/// 되돌려지고, 재동의 중에는 동의 화면 밖이라 다시 동의 화면으로 되돌려진다.
/// 건강정보 처리 항목도 처리방침을 연다 — 건강정보를 어떻게 다루는지는 처리방침에
/// 적혀 있다.
class SignupConsentBlock extends StatelessWidget {
  const SignupConsentBlock({
    super.key,
    required this.checked,
    required this.onChanged,
    this.enabled = true,
  });

  final Set<String> checked;
  final ValueChanged<Set<String>> onChanged;
  final bool enabled;

  static void _open(BuildContext context, String document) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LegalDocumentPage(document: document),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final bool missing = !SignupConsent.hasAllRequired(checked);
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
              id: SignupConsent.terms,
              label: l.consentTerms,
              required: true,
              onView: () => _open(context, 'terms'),
            ),
            AppConsentItem(
              id: SignupConsent.privacy,
              label: l.consentPrivacy,
              required: true,
              onView: () => _open(context, 'privacy'),
            ),
            AppConsentItem(
              id: SignupConsent.health,
              label: l.consentHealth,
              required: true,
              detail: l.consentHealthDetail,
              onView: () => _open(context, 'privacy'),
            ),
            AppConsentItem(
              id: SignupConsent.age14,
              label: l.consentAge14,
              required: true,
              detail: l.consentAge14Detail,
            ),
            AppConsentItem(
              id: SignupConsent.marketing,
              label: l.consentMarketing,
              required: false,
            ),
          ],
        ),
        // 버튼이 왜 꺼져 있는지 그 자리에서 말해 준다.
        if (missing) ...<Widget>[
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
