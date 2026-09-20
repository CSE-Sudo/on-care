import 'package:flutter/material.dart';
import 'package:oncare_trainer/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';

/// 트레이너가 이모티콘을 고르는 창. 고른 id 를 돌려주고 닫는다. (#2020)
///
/// 회원 앱과 달리 **사는 자리가 없다.** 이용권은 회원이 포인트를 쓰는 자리이고,
/// 트레이너에게는 포인트라는 것이 없다. 그림은 두 앱이 함께 보는 [AppEmotes] 다.
Future<String?> showTrainerEmoteSheet(BuildContext context) {
  return showAppSheet<String>(
    context: context,
    builder: (BuildContext _) => const _TrainerEmoteSheet(),
  );
}

class _TrainerEmoteSheet extends StatelessWidget {
  const _TrainerEmoteSheet();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppSheet(
      key: const Key('trainerEmoteSheet'),
      title: l.chatEmoteLabel,
      child: SingleChildScrollView(
        // 묶음으로 나누지 않는다 — 회원 앱의 고르는 창과 같은 한 판이다.
        child: Wrap(
          spacing: OnCareSpacing.s8,
          runSpacing: OnCareSpacing.s8,
          children: <Widget>[
            for (final String id in AppEmotes.all)
              InkWell(
                key: Key('trainer-emote-$id'),
                borderRadius: OnCareRadius.mdAll,
                onTap: () => Navigator.of(context).pop(id),
                child: AppEmote(id: id, size: OnCareSize.emotePick),
              ),
          ],
        ),
      ),
    );
  }
}
