import 'package:flutter/material.dart';

import 'package:oncare/features/benefits/presentation/benefit_labels.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 프로필 펫 고르기 시트 — 강아지·고양이 중 이름 옆에 달 하나를 고른다. (#2021)
///
/// 사용처의 `프로필 펫 이모지` 교환이 연다. 펫마다 카드를 세우지 않고 항목 하나로
/// 두고, 어느 펫을 달지 여기서 고른다. 고른 값(`dog`·`cat`)을 돌려주고, 확인창과
/// 교환은 사용처 화면이 한다(다른 교환과 같은 자리).
class ProfilePetSheet extends StatelessWidget {
  const ProfilePetSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    final AppLocalizations l = AppLocalizations.of(context);
    return AppSheet(
      key: const Key('profilePetSheet'),
      title: l.myProfilePetSheetTitle,
      child: Row(
        children: <Widget>[
          for (final String kind in kProfilePetKinds)
            Expanded(
              child: InkWell(
                key: ValueKey<String>('profile-pet-$kind'),
                onTap: () => Navigator.of(context).pop(kind),
                borderRadius: OnCareRadius.mdAll,
                child: Padding(
                  padding: const EdgeInsets.all(OnCareSpacing.s8),
                  child: Column(
                    children: <Widget>[
                      AppEmote(
                        id: profilePetEmote(kind)!,
                        size: OnCareSize.emotePick,
                        semanticLabel: l.myProfilePetLabel(
                          profilePetName(l, kind),
                        ),
                      ),
                      const SizedBox(height: OnCareSpacing.s4),
                      Text(
                        profilePetName(l, kind),
                        style: tokens
                            .text(OnCareTypography.body)
                            .copyWith(color: OnCareColors.textPrimary),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
