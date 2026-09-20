/// 채팅 이모티콘 목록 — 회원 앱과 트레이너 웹이 같은 값을 본다. (#2020)
///
/// 그림은 이 패키지의 `assets/emotes/<id>.png` 다. **id 는 메시지에 실려 서버에
/// 저장되는 값이라 바꾸지 않는다** — 바꾸면 지난 대화의 이모티콘이 빈칸이 된다.
/// 묶음 이름은 앱의 현지화 문구가 맡는다(패키지에는 문구가 없다).
library;

import 'package:flutter/widgets.dart';

import 'package:oncare_ui/src/tokens/sizes.dart';

/// 한 묶음.
@immutable
class AppEmotePack {
  const AppEmotePack(this.id, this.emotes);

  /// `owoon`·`legday` … 앱이 이 값으로 묶음 이름 문구를 고른다.
  final String id;
  final List<String> emotes;
}

/// 이모티콘 목록. 화면에 서는 순서 그대로다.
abstract final class AppEmotes {
  static const List<AppEmotePack> packs = <AppEmotePack>[
    AppEmotePack('owoon', <String>['oni_owoon', 'oni_gains', 'oni_onfire', 'oni_pr', 'oni_did_it', 'oni_drenched']),
    AppEmotePack('legday', <String>['oni_help', 'oni_shaky', 'oni_one_more', 'oni_sore', 'oni_crawl', 'oni_soul_out']),
    AppEmotePack('diet', <String>['oni_cheat', 'oni_breast', 'oni_held_back', 'oni_midnight', 'oni_water', 'oni_protein']),
    AppEmotePack('coach', <String>['oni_yes_coach', 'oni_thanks', 'oni_see_you', 'oni_got_it', 'oni_late', 'oni_best']),
    AppEmotePack('condition', <String>['oni_great', 'oni_tired', 'oni_sleepy', 'oni_stiff', 'oni_hurts', 'oni_recover']),
    AppEmotePack('react', <String>['oni_lets_go', 'oni_can_do', 'oni_rest', 'oni_tomorrow', 'oni_agree', 'oni_lol']),
    AppEmotePack('dog', <String>['dog_walked', 'dog_woof', 'dog_snack', 'dog_wag', 'dog_sleepy', 'dog_praise', 'dog_owoon', 'dog_love', 'dog_cool', 'dog_hehe', 'dog_sulky', 'dog_run']),
    AppEmotePack('cat', <String>['cat_owoon', 'cat_meh', 'cat_lying', 'cat_churu', 'cat_knead', 'cat_whatever', 'cat_hiss', 'cat_crush', 'cat_chic', 'cat_hide', 'cat_stretch', 'cat_king']),
  ];

  /// 모든 id — 서버가 보낸 값이 우리가 아는 것인지 볼 때 쓴다.
  static final Set<String> all = <String>{
    for (final AppEmotePack pack in packs) ...pack.emotes,
  };

  static bool has(String id) => all.contains(id);

  static String assetOf(String id) => 'assets/emotes/$id.png';
}

/// 이모티콘 한 장. 말풍선 안(작게)과 고르는 창(크게) 모두 이 위젯을 쓴다.
///
/// 모르는 id 는 빈 자리로 둔다 — 앱보다 새로운 이모티콘이 담긴 지난 대화를 열어도
/// 화면이 깨지지 않는다. 대신 글로 읽어 주는 이름([semanticLabel])은 보내는 쪽이
/// 넘긴다.
class AppEmote extends StatelessWidget {
  const AppEmote({
    super.key,
    required this.id,
    this.size = OnCareSize.emoteBubble,
    this.semanticLabel,
  });

  final String id;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    if (!AppEmotes.has(id)) return SizedBox.square(dimension: size);
    return Image.asset(
      AppEmotes.assetOf(id),
      package: 'oncare_ui',
      width: size,
      height: size,
      semanticLabel: semanticLabel,
    );
  }
}
