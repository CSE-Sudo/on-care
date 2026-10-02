import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare_trainer/features/auth/domain/entities/signup_consent.dart';
import 'package:oncare_trainer/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare_trainer/features/auth/presentation/widgets/trainer_consent_block.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 로그인 뒤 동의 화면. (#2819)
///
/// 동의가 남은 계정 — 동의 절차가 생기기 전에 가입한 계정, 소셜 로그인으로
/// 처음 들어온 계정, 문서 버전이 올라간 계정 — 이 다른 화면보다 먼저 거친다.
/// 라우터 가드가 동의가 끝날 때까지 이 화면에 붙들고, 끝나면 대시보드로 보낸다.
/// 동의하지 않을 길로 로그아웃을 둔다.
class TrainerConsentPage extends ConsumerStatefulWidget {
  const TrainerConsentPage({super.key});

  @override
  ConsumerState<TrainerConsentPage> createState() => _TrainerConsentPageState();
}

class _TrainerConsentPageState extends ConsumerState<TrainerConsentPage> {
  Set<String> _checked = <String>{};
  bool _saving = false;

  bool get _ready => TrainerSignupConsent.hasAllRequired(_checked);

  Future<void> _submit() async {
    if (_saving || !_ready) return;
    final AppLocalizations l = AppLocalizations.of(context);
    setState(() => _saving = true);
    try {
      await ref
          .read(sessionControllerProvider.notifier)
          .submitConsents(TrainerSignupConsent.toPayload(_checked));
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppToast(context, l.consentPageFailed, type: AppToastType.error);
      return;
    }
    // 성공하면 가드가 이 화면을 걷어 낸다. 남았다면(문서 버전이 그사이 올랐다)
    // 다시 체크할 수 있게 연다.
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _signOut() async {
    if (_saving) return;
    await ref.read(sessionControllerProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppAuthLayout(
      title: l.consentPageTitle,
      subtitle: l.consentPageSubtitle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TrainerConsentBlock(
            checked: _checked,
            enabled: !_saving,
            onChanged: (Set<String> next) => setState(() => _checked = next),
          ),
          const SizedBox(height: OnCareSpacing.s20),
          AppButton(
            key: const ValueKey<String>('consent-submit'),
            label: l.consentPageAction,
            onPressed: _ready ? _submit : null,
            loading: _saving,
            size: OnCareButtonSize.large,
            fullWidth: true,
          ),
          const SizedBox(height: OnCareSpacing.s8),
          Center(
            child: AppButton(
              key: const ValueKey<String>('consent-sign-out'),
              label: l.mySignOut,
              onPressed: _saving ? null : _signOut,
              variant: AppButtonVariant.text,
              size: OnCareButtonSize.small,
            ),
          ),
        ],
      ),
    );
  }
}
