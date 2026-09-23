import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;
import 'package:oncare/app/app_icons.dart';
import 'package:oncare/app/router/routes.dart';
import 'package:oncare/core/utils/clock.dart';
import 'package:oncare/core/utils/wire_date.dart';
import 'package:oncare/features/auth/presentation/controllers/session_controller.dart';
import 'package:oncare/features/diet/domain/entities/diet_analysis.dart';
import 'package:oncare/features/diet/domain/entities/diet_analysis_failure.dart';
import 'package:oncare/features/diet/domain/entities/diet_day.dart';
import 'package:oncare/features/diet/domain/entities/food_nutrition_suggestion.dart';
import 'package:oncare/features/diet/domain/entities/meal_photo.dart';
import 'package:oncare/features/diet/presentation/controllers/diet_controller.dart';
import 'package:oncare/features/diet/presentation/widgets/meal_photo_view.dart';
import 'package:oncare/features/my_health/presentation/points_reward.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare_ui/oncare_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// A single logged food item, with the per-food nutrition shown on the meal
/// card (all nutrition defaults to 0 for draft rows in the edit sheet).
///
/// 끼니 단위 탄단지는 이 값들의 합계로 만들어진다(`local_api_interceptor` 의
/// `_sumMacro`). 그래서 수정 화면이 이 필드를 하나라도 흘리면 저장한 순간
/// 그 끼니의 영양 정보가 통째로 0 이 된다(#1853).
class DietFood {
  const DietFood(
    this.name,
    this.kcal, {
    this.amountG,
    this.sodiumMg = 0,
    this.sugarG = 0,
    this.carbsG = 0,
    this.proteinG = 0,
    this.fatG = 0,
    this.source = FoodSource.estimate,
  });
  final String name;
  final int kcal;

  /// 먹은 양(g). 나머지 영양이 이 양을 재고 나온 값이라, 수정 화면은 이 칸
  /// 하나로 여섯 값을 함께 움직인다(#1876). 모르면 null 이다 — [FoodItem.amountG]
  /// 에 적어 둔 것과 같은 이유로 0 이 아니다.
  final double? amountG;
  final int sodiumMg;
  final double sugarG;
  final double carbsG;
  final double proteinG;
  final double fatG;

  /// 위 영양이 어디서 왔나(#2105). 수정 화면이 음식마다 따라가다 저장할 때
  /// 그대로 싣는다 — 버리면 손대지 않은 음식까지 서버 기본값으로 덮인다.
  final FoodSource source;
}

/// A nutrient chip on a meal card (`over` = above the daily target → red).
class DietTag {
  const DietTag(this.label, {this.over = false});
  final String label;
  final bool over;
}

/// One meal in the daily log. [id] is the backend entry id (null for a
/// not-yet-persisted draft) and is required to edit or delete the entry.
class DietMeal {
  const DietMeal({
    required this.mealType,
    required this.date,
    required this.time,
    required this.total,
    required this.emoji,
    required this.thumbBg,
    required this.items,
    required this.tags,
    required this.sodium,
    required this.sugar,
    this.carbsG = 0,
    this.proteinG = 0,
    this.fatG = 0,
    this.aiComment = '',
    this.photoAsset,
    this.photoUrl,
    this.id,
  });

  final MealType mealType;

  /// 이 기록이 놓인 날(시각 없는 날짜). 식단 상세에서 날짜를 고치는 기준이다
  /// (#1947).
  ///
  /// `DietEntry` 에는 날짜가 없다 — 서버가 날짜별로 묶어 내려주므로 날짜는 그
  /// 목록을 **어느 날로 불렀는가** 에서 온다. 그래서 끼니를 옮기는 매퍼가
  /// 반드시 받아 오도록 필수로 둔다 — 빠뜨린 자리를 오늘로 채우면 지난 날의
  /// 기록이 상세에서 오늘로 보인다.
  final DateTime date;
  final String time;
  final int total;
  final String emoji;
  final Color thumbBg;
  final List<DietFood> items;
  final List<DietTag> tags;
  final int sodium;
  final double sugar;

  /// 그 끼니의 탄·단·지(g). 끼니 카드 아래에 한 줄로 작게 적는다 (#1170) —
  /// 하루 합계는 영양 요약 카드가 말하지만, 어느 끼니가 그 합계를 만들었는지는
  /// 끼니 단위로 봐야 알 수 있다. 트레이너 화면의 같은 카드와 짝이다.
  final double carbsG;
  final double proteinG;
  final double fatG;

  /// Short per-meal AI feedback line shown under the food breakdown.
  final String aiComment;

  /// Bundled photo asset for the thumbnail; null falls back to [emoji].
  final String? photoAsset;

  /// API path of the photo the member uploaded (#699). Wins over
  /// [photoAsset] when present.
  final String? photoUrl;
  final String? id;
}

/// Localized meal-type badge label. The API `meal_type` string is always
/// derived from [MealType.name], never from this display label.
String mealBadge(AppLocalizations l, MealType t) => switch (t) {
  MealType.breakfast => l.dietMealBreakfast,
  MealType.lunch => l.dietMealLunch,
  MealType.dinner => l.dietMealDinner,
  MealType.snack => l.dietMealSnack,
  MealType.lateNight => l.dietMealLateNight,
};

/// Best-guess meal type for a new entry, based on the current time of day.
///
/// 21시 이후는 야식이다(#1988). 그전에는 그 자리가 간식이었는데, 밤늦게 먹은
/// 것과 낮의 간식이 한 칸에 섞여 코칭에서 갈라 보이지 않았다.
///
/// 간식에는 시간대를 주지 않는다. 어느 시간대를 떼어 주더라도 그 시간에 먹은
/// 끼니가 매번 간식으로 찍혀 회원이 고쳐야 한다 — 간식은 끼니 사이에 먹는
/// 것이지 특정 시각에 먹는 것이 아니다. 회원이 상세에서 직접 고른다.
String _currentMealType() {
  final int h = nowKst().hour;
  if (h < 11) return MealType.breakfast.name;
  if (h < 15) return MealType.lunch.name;
  if (h < 21) return MealType.dinner.name;
  return MealType.lateNight.name;
}

/// 오늘(KST)의 날짜. 시각은 버린다.
DateTime _todayKst() {
  final DateTime now = nowKst();
  return DateTime(now.year, now.month, now.day);
}

/// 기록 날짜를 화면 언어로 — `2026년 9월 16일`.
String _recordDateLabel(BuildContext context, DateTime date) =>
    DateFormat.yMMMd(Localizations.localeOf(context).toString()).format(date);

/// 역할 글자 + 색. 크기·굵기 숫자는 적지 않는다(#1690).
TextStyle _text(BuildContext context, TextStyle role, Color color) =>
    context.oncare.text(role).copyWith(color: color);

/// 줄이 바뀌지 않는 공백(U+00A0).
const String _nbsp = '\u00A0';

/// 폭 없는 줄바꿈 금지 문자(U+2060 WORD JOINER).
const String _wordJoiner = '\u2060';

/// 한 덩어리로 읽혀야 하는 글자를 줄이 바뀌지 않게 잇는다.
///
/// 공백만 붙는 공백으로 바꾸면 모자라다 — 한국어는 음절 사이 어디서든 줄이
/// 바뀌어 `그래놀` / `라 토핑` 처럼 갈렸다. 글자 사이마다 폭 없는 줄바꿈 금지
/// 문자를 끼운다.
String _keepTogether(String text) => text
    .replaceAll(' ', _nbsp)
    .runes
    .map(String.fromCharCode)
    .join(_wordJoiner);

/// 그램 수치 한 줄. 소수 첫째 자리까지만, 정수는 콤마만 — 칼로리·나트륨 행과
/// 같은 서식이다. 당류와 탄·단·지가 이 함수를 같이 쓴다(#1564).
String _gramsText(double grams) => grams == grams.roundToDouble()
    ? NumberFormat('#,###').format(grams)
    : NumberFormat('#,##0.#').format(grams);

/// 입력 칸에 적는 g — 읽기용 [_gramsText] 와 달리 **자릿점을 넣지 않는다.**
///
/// 칸에 `1,640` 이 적히면 `double.tryParse` 가 null 을 돌려주어, 눈에는 보이는데
/// 읽을 수는 없는 값이 된다(숫자만 받는 입력기는 이미 적힌 글자를 걸러 주지
/// 않는다). 큰 1회 섭취량과 비례 환산으로 커진 값이 실제로 네 자리에 닿는다.
String _gramsFieldText(double grams) {
  final double rounded = (grams * 10).roundToDouble() / 10;
  return rounded == rounded.roundToDouble()
      ? rounded.toStringAsFixed(0)
      : rounded.toStringAsFixed(1);
}

/// 하단 내비·`+` 버튼 위에 뜨도록 루트 내비게이터에서 연다(#791). 탭 페이지는
/// 자기 내비게이터를 따로 갖고 있어, 그 안에서 열면 하단 바가 시트 위로 올라온다.
BuildContext _rootContext(BuildContext context) =>
    Navigator.of(context, rootNavigator: true).context;

// ─────────────────────────────────────────────────── 식단 추가하기 ──

/// 고른 사진과 끼니. 사진 선택 시트가 닫히면서 부르는 쪽에 넘긴다.
typedef DietPickedPhoto = ({MealPhoto photo, String mealType});

/// Opens the short photo-source choice as a content-sized bottom sheet.
///
/// **기록이 저장되면 true.** 하단 `+` 로 연 흐름이 저장 성공에만 식단 탭으로
/// 옮겨 가려면, 취소·권한 거부·분석 실패와 저장 성공을 구분해야 한다(#1434).
Future<bool> showDietAddSheet(BuildContext context) async {
  final Object? choice = await showAppSheet<Object>(
    context: _rootContext(context),
    builder: (BuildContext ctx) => const _DietAddSheet(),
  );
  if (!context.mounted) return false;
  // 다음 화면은 사진 선택 시트가 **닫힌 뒤** 열린다 — 두 시트가 겹치면 뒤엣
  // 것이 스크림 위로 비친다.
  return switch (choice) {
    final DietPickedPhoto picked => showDietResultSheet(
      context,
      picked.photo,
      picked.mealType,
    ),
    _DietAddChoice.manual => openDietManualAddPage(context),
    _ => false,
  };
}

/// 사진 선택 시트가 사진 말고 돌려주는 것. 머리의 `+ 직접 추가` 다(#2151).
enum _DietAddChoice { manual }

/// Photo-source choice for 식단 추가.
///
/// Owns the picker outcome so a failure can be shown *inside* the sheet: a
/// toast would sit apart from this sheet, and the sheet staying open is what
/// lets the user retry (or open Settings) without restarting the flow.
/// Cancelling the camera/gallery is not a failure — nothing is shown.
class _DietAddSheet extends ConsumerStatefulWidget {
  const _DietAddSheet();

  @override
  ConsumerState<_DietAddSheet> createState() => _DietAddSheetState();
}

class _DietAddSheetState extends ConsumerState<_DietAddSheet> {
  MealPhotoFailure? _failure;

  /// Guards a second tap while the OS picker is up — image_picker rejects a
  /// concurrent request with `multiple_request`.
  bool _picking = false;

  Future<void> _pickAndAnalyze(MealPhotoSource source) async {
    if (_picking) return;
    setState(() {
      _picking = true;
      _failure = null;
    });
    final NavigatorState navigator = Navigator.of(context);

    final MealPhoto? photo;
    try {
      photo = await ref.read(mealPhotoPickerProvider).pick(source);
    } on MealPhotoException catch (error) {
      _settle(error.failure);
      return;
    } on Object {
      _settle(MealPhotoFailure.readFailed);
      return;
    }
    // `navigator.mounted` is still true after this sheet is dismissed, so it
    // can't tell us whether the route we're about to pop is ours. Only this
    // State being mounted proves the sheet is still up — without the check a
    // dismiss during the OS picker would pop the page underneath instead.
    if (!mounted) return;
    _settle(null);
    if (photo == null) return; // user cancelled

    // 고른 사진을 부르는 쪽에 넘기고 닫힌다 — 결과 시트는 그쪽이 연다. 이
    // 시트가 직접 열면 부르는 쪽 future 가 결과보다 먼저 끝나, 저장 성공을
    // 알 방법이 없다(#1434).
    navigator.pop((photo: photo, mealType: _currentMealType()));
  }

  void _settle(MealPhotoFailure? failure) {
    if (!mounted) return;
    setState(() {
      _picking = false;
      _failure = failure;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final MealPhotoFailure? failure = _failure;
    final MealPhotoChoiceLayout layout = ref.watch(
      mealPhotoChoiceLayoutProvider,
    );
    return AppSheet(
      key: const Key('dietAddSheet'),
      title: l.dietAddSheetTitle,
      subtitle: l.dietAddSheetSubtitle,
      // 닫기는 끌어내리기 하나로 둔다 — 비운 X 자리에 사진 없이 적는 문을
      // 둔다(#2151). 모양은 수정 화면의 `+ 음식 추가` 와 같다.
      showClose: false,
      trailing: AppButton(
        key: const Key('dietManualAddButton'),
        label: l.dietManualAdd,
        leadingIcon: AppIcons.add,
        variant: AppButtonVariant.text,
        size: OnCareButtonSize.small,
        // OS 사진 선택기가 떠 있는 동안에는 막는다 — 그 사이 시트를 닫으면
        // 고른 사진이 돌아올 자리가 없다.
        onPressed: _picking
            ? null
            : () => Navigator.of(context).pop(_DietAddChoice.manual),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (failure != null) ...<Widget>[
            _PhotoFailureNotice(failure: failure),
            const SizedBox(height: OnCareSpacing.s12),
          ],
          Column(
            key: const Key('dietAddOptions'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (layout == MealPhotoChoiceLayout.systemMenu)
                // 웹: 브라우저가 보관함·촬영·파일을 묻는 메뉴를 스스로 띄운다.
                // 앱에 촬영을 따로 두면 그 메뉴의 `사진 찍기`와 겹친다(#1433).
                _SourceOption(
                  icon: AppIcons.image,
                  title: l.dietAddPhoto,
                  subtitle: l.dietAddPhotoSub,
                  onTap: () => _pickAndAnalyze(MealPhotoSource.gallery),
                )
              else ...<Widget>[
                _SourceOption(
                  icon: AppIcons.image,
                  title: l.dietPickPhoto,
                  subtitle: l.dietPickPhotoSub,
                  onTap: () => _pickAndAnalyze(MealPhotoSource.gallery),
                ),
                const SizedBox(height: OnCareSpacing.s12),
                _SourceOption(
                  icon: AppIcons.camera,
                  title: l.dietTakePhoto,
                  subtitle: l.dietTakePhotoSub,
                  onTap: () => _pickAndAnalyze(MealPhotoSource.camera),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// In-sheet explanation of why the photo couldn't be used. Only a permanent
/// iOS denial offers Settings; retryable denials and policy restrictions do
/// not send the user somewhere that cannot fix them.
class _PhotoFailureNotice extends StatefulWidget {
  const _PhotoFailureNotice({required this.failure});

  final MealPhotoFailure failure;

  @override
  State<_PhotoFailureNotice> createState() => _PhotoFailureNoticeState();
}

class _PhotoFailureNoticeState extends State<_PhotoFailureNotice> {
  /// Settings wouldn't open — fall back to telling the user the manual path.
  /// A tap that silently does nothing reads as a broken app (#507).
  bool _openSettingsFailed = false;

  bool get _isPermanentlyDenied =>
      widget.failure == MealPhotoFailure.cameraPermissionPermanentlyDenied ||
      widget.failure == MealPhotoFailure.photoPermissionPermanentlyDenied;

  /// Only iOS has a URL that lands on this app's permission screen;
  /// elsewhere the message alone has to do.
  bool get _canOpenAppSettings =>
      _isPermanentlyDenied &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.iOS;

  String _message(AppLocalizations l) => switch (widget.failure) {
    MealPhotoFailure.cameraPermissionDenied => l.dietCameraPermissionDenied,
    MealPhotoFailure.cameraPermissionPermanentlyDenied =>
      l.dietCameraPermissionPermanentlyDenied,
    MealPhotoFailure.cameraPermissionRestricted =>
      l.dietPhotoPermissionRestricted,
    MealPhotoFailure.photoPermissionDenied => l.dietPhotoPermissionDenied,
    MealPhotoFailure.photoPermissionPermanentlyDenied =>
      l.dietPhotoPermissionPermanentlyDenied,
    MealPhotoFailure.photoPermissionRestricted =>
      l.dietPhotoPermissionRestricted,
    MealPhotoFailure.unsupportedFormat => l.dietPhotoUnsupportedFormat,
    MealPhotoFailure.tooLarge => l.dietPhotoTooLarge,
    MealPhotoFailure.readFailed => l.dietPhotoLoadError,
  };

  Future<void> _openSettings() async {
    bool opened = false;
    try {
      // `app-settings:` is a system scheme, so the platform default mode is
      // what lands on this app's permission screen (no external webview).
      opened = await launchUrl(Uri.parse('app-settings:'));
    } on Object {
      opened = false;
    }
    if (!mounted || opened) return;
    setState(() => _openSettingsFailed = true);
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AppBanner(
      key: const Key('dietPhotoFailureNotice'),
      tone: AppBannerTone.danger,
      title: _message(l),
      message: _openSettingsFailed ? l.dietOpenSettingsFailed : null,
      actionLabel: _canOpenAppSettings ? l.dietOpenSettings : null,
      onAction: _canOpenAppSettings ? _openSettings : null,
    );
  }
}

class _SourceOption extends StatelessWidget {
  const _SourceOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return AppCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: AppListRow(
        title: title,
        subtitle: subtitle,
        // 아이콘 배경은 두지 않는다 — 칸 크기만 남겨 글줄 정렬을 지킨다(#1781).
        leading: SizedBox.square(
          dimension: tokens.density.iconButton,
          child: AppIcon(
            icon,
            size: OnCareSize.iconLarge,
            color: tokens.brand.primary,
          ),
        ),
        trailing: const AppIcon(
          AppIcons.chevronRight,
          size: OnCareSize.iconMedium,
          color: OnCareColors.textTertiary,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────── 분석 완료 ──

/// AI analysis result sheet shown after picking a photo.
/// Runs the real `POST /diet/analyze` on the picked [photo] and shows the
/// recognised foods + nutrition. The backend persists the entry as part of
/// analysis, so a successful result refreshes [dietTodayProvider].
/// 결과 시트. `저장` 까지 마치면 true — 저장된 기록을 확인할 준비가 됐다는
/// 뜻이다(#1434).
Future<bool> showDietResultSheet(
  BuildContext context,
  MealPhoto photo,
  String mealType,
) async {
  final bool? done = await showAppSheet<bool>(
    // 하단 바·+ 버튼이 시트 위로 올라오지 않도록 루트에 올린다. 식단 추가 시트와
    // 같은 규칙이다 — 둘이 같은 층에 있어야 한다(#791).
    context: _rootContext(context),
    builder: (BuildContext ctx) =>
        _ResultSheet(photo: photo, mealType: mealType),
  );
  return done ?? false;
}

class _ResultSheet extends ConsumerStatefulWidget {
  const _ResultSheet({required this.photo, required this.mealType});
  final MealPhoto photo;
  final String mealType;

  @override
  ConsumerState<_ResultSheet> createState() => _ResultSheetState();
}

class _ResultSheetState extends ConsumerState<_ResultSheet>
    with _FoodEditing<_ResultSheet> {
  DietAnalysisResult? _result;
  bool _loading = true;
  DietAnalysisFailure? _failure;

  /// 이 기록이 놓인 날. 분석은 저장한 시각의 날짜로 남기므로 처음은 늘 오늘이고,
  /// 지난 식사의 사진이면 `날짜 변경` 으로 실제로 먹은 날로 옮긴다(#1241).
  ///
  /// 날짜는 식단 상세처럼 따로 옮긴다(#1947) — 사진을 올린 자리에서 가장 흔히
  /// 고치는 것이 날짜라, 연필을 거치게 하지 않는다. 끼니·음식은 헤더 연필이
  /// 이 시트 안에 여는 수정 모드에서 고친다(#2097).
  late DateTime _date = _todayKst();

  /// 날짜를 옮기는 중. 두 번 눌러 같은 기록을 두 날짜로 보내지 않게 막는다.
  bool _movingDate = false;

  /// 헤더 연필로 연 수정 모드(#2097). 시트를 떠나지 않고 이 자리에서 끼니·
  /// 음식·영양을 고친 뒤 `저장` 한다 — 아래 `저장` 을 두고 다른 화면으로
  /// 넘어가면, 저장하지 않은 줄 알았던 기록의 수정 화면이 열리는 셈이다.
  bool _editing = false;

  /// 수정 모드에서 고른 끼니. 연필을 누를 때 [_meal] 에서 시작한다.
  late MealType _type = _meal;

  /// 고친 값을 보내거나 기록을 지우는 중. 버튼과 시트 닫기를 막는다.
  bool _saving = false;

  bool get _failed => _failure != null;

  // One key per capture, reused across retries so a lost response followed by
  // 「다시 시도」 doesn't record the same meal twice (server dedupes on it).
  late final String _idempotencyKey =
      'diet-${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(this)}';

  @override
  void initState() {
    super.initState();
    _run();
  }

  /// 분석 중 화면을 최소한 이만큼은 보여 준다.
  ///
  /// 데모(로컬 인터셉터)와 캐시된 재시도는 응답이 즉시 온다. 그대로 두면
  /// 결과가 촬영 직후 튀어나와 AI 가 무엇을 했는지 보이지 않는다(#1564).
  /// 실제 분석이 더 걸리면 기다린 만큼이 그대로 노출 시간이라 이 값은
  /// 아무 일도 하지 않는다 — 늦추는 것이 아니라 바닥을 깔아 두는 값이다.
  static const Duration _minAnalyzingDelay = Duration(milliseconds: 2200);

  Future<void> _run() async {
    setState(() {
      _loading = true;
      _failure = null;
    });
    final Stopwatch elapsed = Stopwatch()..start();
    try {
      final DietAnalysisResult result = await ref
          .read(dietRepositoryProvider)
          .analyze(
            photo: widget.photo,
            mealType: widget.mealType,
            idempotencyKey: _idempotencyKey,
          );
      if (!mounted) return;
      // analyze() already persisted the entry → refresh the day's summary/list.
      ref.invalidate(dietTodayProvider);
      // 저장과 함께 포인트도 적립됐다 — MY 잔액을 다시 읽는다(#1786).
      refreshPointsBalance(ref);
      // 기간 뷰(이번 주·전체)는 오늘을 dietByDateProvider 로 읽는다.
      // 같이 비우지 않으면 끼니를 바꿔도 기간 막대만 옛 값에 머문다.
      ref.invalidate(dietByDateProvider(nowKst()));
      await _holdAnalyzing(elapsed);
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      // 실패도 같은 바닥을 쓴다 — 즉시 튀어나오는 실패 문구는 사진을 보지도
      // 않고 거절한 것처럼 읽힌다.
      await _holdAnalyzing(elapsed);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failure = DietAnalysisFailure.fromError(error);
      });
    }
  }

  /// [_minAnalyzingDelay] 에서 이미 지난 만큼을 뺀 나머지를 기다린다.
  Future<void> _holdAnalyzing(Stopwatch elapsed) {
    final Duration left = _minAnalyzingDelay - elapsed.elapsed;
    if (left <= Duration.zero) return Future<void>.value();
    return Future<void>.delayed(left);
  }

  /// 인식 결과를 이 시트 안에서 고치기 시작한다. (#1564, #2097)
  ///
  /// 예전에는 시트를 닫고 저장된 기록의 식단 상세로 넘어갔다. 시트 아래에
  /// `저장` 이 서 있는데 연필이 저장 뒤의 화면을 여니, 회원에게는 저장하지도
  /// 않은 기록이 이미 저장돼 있는 것으로 보였다.
  void _beginEdit() {
    final DietAnalysisResult? r = _result;
    if (r == null || r.entryId.isEmpty) return;
    final List<DietFood> foods = <DietFood>[
      for (final RecognizedFood f in r.foods)
        DietFood(
          f.name,
          f.calories,
          amountG: f.amountG,
          sodiumMg: f.sodiumMg,
          sugarG: f.sugarG,
          carbsG: f.carbsG,
          proteinG: f.proteinG,
          fatG: f.fatG,
          source: f.source,
        ),
    ];
    setState(() {
      _editing = true;
      _type = _meal;
      _loadFoods(foods);
      _carbsRecorded = _carbsOf(foods) > 0;
    });
  }

  /// 고친 값을 버리고 분석 결과 보기로 돌아간다. 시트는 닫지 않는다 — 고치다
  /// 그만둔 것이지 기록을 그만둔 것이 아니다.
  void _cancelEdit() => setState(() => _editing = false);

  /// 고친 끼니·음식을 기록에 반영하고 시트를 닫는다. (#2097)
  ///
  /// 기록은 분석 때 이미 저장돼 있으므로 새로 만들지 않고 그 기록을 고친다.
  /// 식단 상세의 `저장` 과 같은 요청이다.
  Future<void> _saveEdit() async {
    final DietAnalysisResult? r = _result;
    if (r == null || r.entryId.isEmpty || _saving) return;
    final List<FoodItem> foods = _foodPayload();
    // 음식을 모두 지웠다면 빈 끼니를 남기는 대신 기록을 지울지 묻는다 —
    // 식단 상세와 같다.
    if (foods.isEmpty) {
      await _deleteEmptied(r.entryId);
      return;
    }
    if (!_validateFoods()) return;

    final AppLocalizations l = AppLocalizations.of(context);
    setState(() => _saving = true);
    try {
      await _saveFoods(id: r.entryId, mealType: _type, foods: foods);
      if (!mounted) return;
      ref.invalidate(dietTodayProvider);
      ref.invalidate(dietByDateProvider(nowKst()));
      // 날짜를 옮겨 둔 기록이면 그 날도 비운다.
      ref.invalidate(dietByDateProvider(_date));
      _finish();
    } on Object catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppToast(context, l.dietSaveFailed, type: AppToastType.error);
    }
  }

  /// 음식을 모두 지우고 저장했을 때 — 기록을 지울지 묻고, 지우면 시트를 닫는다.
  Future<void> _deleteEmptied(String id) async {
    final AppLocalizations l = AppLocalizations.of(context);
    final bool ok = await showAppConfirmDialog(
      context: context,
      title: l.dietDeleteTitle,
      message: l.dietDeleteWhenEmpty,
      confirmLabel: l.dietDelete,
      cancelLabel: l.dietCancel,
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.read(dietRepositoryProvider).deleteEntry(id);
      if (!mounted) return;
      // 지운 끼니의 적립은 회수된다 — MY 잔액을 다시 읽는다(#1786).
      refreshPointsBalance(ref);
      ref.invalidate(dietTodayProvider);
      ref.invalidate(dietByDateProvider(nowKst()));
      ref.invalidate(dietByDateProvider(_date));
      final AppToastHost toast = AppToastHost.of(context);
      // 지웠으니 식단 탭으로 옮겨 갈 기록이 없다 — `false` 로 닫는다.
      Navigator.of(context).pop(false);
      toast.show(l.dietDeleted, type: AppToastType.success);
    } on Object catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppToast(context, l.dietDeleteFailed, type: AppToastType.error);
    }
  }

  /// 기록 날짜만 따로 옮긴다. (#1241, #1947)
  ///
  /// 분석이 끝난 시점에 기록은 이미 서버에 남아 있다. 그래서 고른 즉시 옮긴다 —
  /// 시트를 닫는 방법이 여럿인데, 저장을 한 버튼에만 걸어 두면 화면에 보이는
  /// 날짜와 실제로 남은 날짜가 갈린다. 식단 상세의 `날짜 변경` 과 같은 동작이다.
  Future<void> _pickDate() async {
    final DietAnalysisResult? result = _result;
    if (result == null || result.entryId.isEmpty || _movingDate) return;
    final DateTime today = _todayKst();
    final DateTime? picked = await showAppDatePicker(
      context: context,
      initialDate: _date,
      // 지난 식사는 얼마든지 올릴 수 있지만, 앞날의 식사는 아직 먹지 않았다.
      firstDate: DateTime(today.year - 1),
      lastDate: today,
      showClose: false,
    );
    if (picked == null || !mounted) return;
    final DateTime chosen = DateTime(picked.year, picked.month, picked.day);
    if (chosen == _date) return;

    final AppLocalizations l = AppLocalizations.of(context);
    final DateTime previous = _date;
    setState(() => _movingDate = true);
    try {
      await ref
          .read(dietRepositoryProvider)
          .updateEntry(id: result.entryId, date: wireDate(chosen));
      if (!mounted) return;
      setState(() {
        _date = chosen;
        _movingDate = false;
      });
      // 떠난 날과 도착한 날을 모두 비운다 — 한쪽만 비우면 합계가 두 날에
      // 겹쳐 보이거나 어느 쪽에서도 보이지 않는다.
      ref.invalidate(dietTodayProvider);
      ref.invalidate(dietByDateProvider(previous));
      ref.invalidate(dietByDateProvider(chosen));
      showAppToast(
        context,
        l.dietRecordDateMoved(_recordDateLabel(context, chosen)),
        type: AppToastType.success,
      );
    } on Object catch (_) {
      if (!mounted) return;
      setState(() => _movingDate = false);
      showAppToast(context, l.dietRecordDateFailed, type: AppToastType.error);
    }
  }

  /// 이 기록이 들어갈 끼니. `widget.mealType` 은 사진을 고른 시각으로 추측한
  /// 값이다(`_currentMealType`). 저장한 뒤 끼니 카드가 아침·점심·저녁·간식·야식
  /// 중 어디에 붙을지가 여기서 정해지므로, 저장 전에 보여 준다(#1897).
  MealType get _meal => MealType.values.firstWhere(
    (MealType m) => m.name == widget.mealType,
    orElse: () => MealType.snack,
  );

  /// Sends the user back to the source picker. The photo they have can't be
  /// analysed, so "다시 시도" would just fail again — the useful next step is
  /// choosing a different one.
  void _pickAnother() {
    final NavigatorState navigator = Navigator.of(context);
    navigator.pop();
    unawaited(showDietAddSheet(navigator.context));
  }

  /// Takes an expired session back to sign-in.
  ///
  /// Signing out *is* the navigation: `appRouterProvider` refreshes the guard
  /// on every session change, and `sessionRedirect` sends a signed-out user
  /// to `/auth/sign-in`. Pushing that route directly would not work — while
  /// the session still reads as authenticated the guard bounces anyone off
  /// the auth routes back to the dashboard. Clearing the dead token is also
  /// the point: it is what made the request fail.
  Future<void> _signInAgain() async {
    // Read before popping; this State is gone right after.
    final NavigatorState navigator = Navigator.of(context);
    final SessionController session = ref.read(
      sessionControllerProvider.notifier,
    );
    navigator.pop();
    await session.signOut();
  }

  /// 저장은 분석 때 이미 끝났다 — 시트를 `true` 로 닫고 알린다.
  void _finish() {
    final AppLocalizations l = AppLocalizations.of(context);
    // 시트가 닫힌 뒤에도 토스트를 띄울 수 있는 자리를 먼저 잡아 둔다. 내비게이터
    // 자신의 context 는 그 내비게이터의 오버레이보다 위라, 거기서 오버레이를 찾으면
    // 바깥 내비게이터가 없는 화면에서 실패한다 — 닫기 전에 손잡이를 잡는다.
    final AppToastHost toast = AppToastHost.of(context);
    Navigator.of(context).pop(true);
    toast.show(
      l.dietSaved,
      type: AppToastType.success,
      // 받은 포인트가 있으면 ★ +50P 가 반짝인다. 한도를 넘었으면 저장 알림만.
      rewardLabel: pointsRewardLabel(l, _result?.points),
    );
  }

  String _failureMessage(AppLocalizations l, DietAnalysisFailure failure) =>
      switch (failure) {
        DietAnalysisFailure.unsupportedFormat =>
          l.dietAnalysisUnsupportedFormat,
        DietAnalysisFailure.badRequest => l.dietAnalysisBadRequest,
        DietAnalysisFailure.unauthorized => l.dietAnalysisUnauthorized,
        DietAnalysisFailure.notImplemented => l.dietAnalysisNotImplemented,
        // 502 and transport failures share the "try again shortly" wording —
        // from the user's side both are "it broke, not your photo".
        DietAnalysisFailure.recognitionFailed ||
        DietAnalysisFailure.temporary => l.dietAnalysisFailedBody,
      };

  /// The button only offers a retry when one can actually succeed; otherwise
  /// it moves the user to the step that can (a different photo), or just
  /// closes when nothing in this sheet will help.
  VoidCallback _failureAction(DietAnalysisFailure failure) {
    if (failure.canRetry) return _run;
    return switch (failure) {
      DietAnalysisFailure.unsupportedFormat ||
      DietAnalysisFailure.badRequest => _pickAnother,
      DietAnalysisFailure.unauthorized => () => unawaited(_signInAgain()),
      _ => () => Navigator.of(context).pop(),
    };
  }

  String _failureActionLabel(AppLocalizations l, DietAnalysisFailure failure) {
    if (failure.canRetry) return l.actionRetry;
    return switch (failure) {
      DietAnalysisFailure.unsupportedFormat ||
      DietAnalysisFailure.badRequest => l.dietAnalysisPickAnother,
      DietAnalysisFailure.unauthorized => l.dietAnalysisSignIn,
      _ => l.dietAnalysisClose,
    };
  }

  /// `_result == null` without a classified failure shouldn't happen, but
  /// treating it as temporary keeps a retry available instead of a dead end.
  DietAnalysisFailure get _shownFailure =>
      _failure ?? DietAnalysisFailure.temporary;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final Widget sheet = AppSheet(
      title: _loading
          ? l.dietAnalyzing
          : _failed
          ? l.dietAnalysisFailed
          : l.dietAnalysisDone,
      subtitle: l.dietAiNutritionResult,
      // 닫기는 아래 `취소` 버튼 하나로 모은다 — 머리의 X 와 둘이 있으면 같은
      // 일을 하는 자리가 화면에 둘이다(#1564).
      showClose: false,
      // 이 시트는 AI 가 읽은 결과를 말한다 — 홈의 `오늘의 AI 통합 조언` 과
      // 같은 아바타를 써서 두 화면이 같은 목소리로 읽히게 한다(#1897).
      leading: const OniAvatar(size: OnCareSize.avatarMedium),
      // 연필은 닫기 X 가 비워 둔 헤더 우측에 둔다. 인식된 음식 줄에 있던 것을
      // 올렸다 — 시트 전체가 "AI 가 읽은 것"이고 연필은 그것을 고치는 문이라,
      // 음식 한 줄보다 머리 쪽이 걸린 범위와 맞는다(#1897).
      trailing: _editButton(l),
      // 버튼을 바닥에 고정하면 코멘트 마지막 줄을 덮는다(#1897). 스크롤 끝으로
      // 보내 다 읽은 뒤에 나오게 한다 — #1432 의 "시트 안에서만 스크롤"은
      // 그대로다.
      pinFooter: false,
      footer: _footer(l),
      child: _body(),
    );
    // 고친 값을 보내는 동안에는 끌어내려 닫지 못하게 한다.
    return PopScope(canPop: !_saving, child: sheet);
  }

  /// 인식된 데이터를 고치는 문. 헤더 우측에 놓이므로 결과가 있을 때만
  /// 만든다 — 분석 중이거나 실패한 시트에는 고칠 것이 없다. 이미 고치는
  /// 중이면 감춘다 — 식단 상세의 연필과 같다.
  Widget? _editButton(AppLocalizations l) {
    final DietAnalysisResult? r = _result;
    if (_loading || _failed || _editing || r == null || r.entryId.isEmpty) {
      return null;
    }
    // 식단 상세가 연필을 쓰므로 여기서도 연필이다 — 같은 곳으로 가는 문이
    // 화면마다 다른 모양이면 다른 동작으로 읽힌다(#1864).
    return AppIconButton(
      key: const Key('diet-result-edit'),
      icon: AppIcons.edit,
      tooltip: l.actionEdit,
      size: AppIconButtonSize.small,
      onPressed: _beginEdit,
    );
  }

  Widget? _footer(AppLocalizations l) {
    if (_loading) return null;
    if (_failed || _result == null) {
      final DietAnalysisFailure failure = _shownFailure;
      return AppButton(
        key: const Key('dietAnalysisFailureAction'),
        label: _failureActionLabel(l, failure),
        onPressed: _failureAction(failure),
        fullWidth: true,
      );
    }
    // [취소] 왼쪽, [저장] 오른쪽 — 앱의 모든 하단 두 버튼과 같은 순서다(#1690).
    if (_editing) {
      // 수정 모드의 `취소` 는 고친 값만 버리고 시트에 남는다. `저장` 은 고친
      // 값을 보낸 뒤 닫는다.
      return AppButtonPair(
        cancelLabel: l.dietCancel,
        onCancel: _saving ? null : _cancelEdit,
        confirmLabel: l.dietSave,
        onConfirm: _saving ? null : () => unawaited(_saveEdit()),
      );
    }
    return AppButtonPair(
      cancelLabel: l.dietCancel,
      // 저장은 이미 끝났고, 이 버튼은 시트를 닫기만 한다.
      onCancel: () => Navigator.of(context).pop(),
      confirmLabel: l.dietSave,
      onConfirm: _finish,
    );
  }

  Widget _body() {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    if (_loading) {
      return Column(
        key: const Key('diet-result-analyzing'),
        children: <Widget>[
          const AppLoading(placement: AppStatePlacement.card),
          Text(
            l.dietAnalyzingBody,
            textAlign: TextAlign.center,
            style: _text(
              context,
              OnCareTypography.body,
              OnCareColors.textPrimary,
            ),
          ),
        ],
      );
    }
    if (_failed || _result == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: OnCareSpacing.s20),
        child: Text(
          _failureMessage(l, _shownFailure),
          key: const Key('dietAnalysisFailureBody'),
          textAlign: TextAlign.center,
          style: _text(
            context,
            OnCareTypography.body,
            OnCareColors.textPrimary,
          ),
        ),
      );
    }

    final DietAnalysisResult r = _result!;
    final String recognized = r.foods
        .map((RecognizedFood f) => f.name)
        .join(' · ');
    // 수정 중에는 합계가 고치는 음식을 곧바로 따라온다 — 식단 상세와 같다.
    // 보기에서는 서버가 준 합계를 그대로 적는다.
    final String kcal = _editing ? '$_total' : '${r.totalCalories}';
    final double carbs = _editing ? _carbs : r.totalCarbsG;
    final double sugar = _editing ? _sugar : r.totalSugarG;
    final double protein = _editing ? _protein : r.totalProteinG;
    final double fat = _editing ? _fat : r.totalFatG;
    final int sodium = _editing ? _sodium : r.totalSodiumMg;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // 수정 모드에서는 `인식된 음식` 을 감추고, 음식별 수정 칸이 아래
        // 기록 날짜·끼니 다음에 선다(#2097). 식단 상세의 수정 모드처럼
        // "언제·어느 끼니" 를 먼저 두고 "무엇을 먹었나" 를 그 아래에 둔다.
        if (!_editing) ...<Widget>[
          // 이 시트에서 강조할 것은 AI 가 무엇으로 읽었는지 하나다 — 거기에만
          // 옅은 브랜드 채움을 준다. `0389e572` 가 걷어낸 것은 구획을 여럿
          // 쌓아 카드가 온통 옅은 파랑이 되는 것이고, 그 커밋이 남긴 규칙은
          // "바탕은 강조인 것만"이다. 그래서 박스는 여기 하나뿐이다(#1897).
          AppTile(
            key: const Key('diet-result-recognized'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  l.dietRecognizedFood,
                  style: _text(
                    context,
                    OnCareTypography.strong(OnCareTypography.caption),
                    tokens.brand.primary,
                  ),
                ),
                const SizedBox(height: OnCareSpacing.s4),
                // 음식마다 이름 옆에 AI 가 읽은 **양**을 보조색으로 붙인다(#1964).
                // 영양은 모두 이 양으로 환산되므로, 양이 틀리면 칼로리·탄단지가
                // 함께 틀린다 — 저장 전 이 자리에서 보여야 머리의 연필로 바로
                // 고칠 수 있다. 식단 탭 끼니 카드·식단 상세와 같은 자리·같은
                // 모양이다. 양을 모르는 음식은 이름만 적는다(0g 은 안 먹었다).
                Text.rich(
                  key: const Key('diet-result-recognized-foods'),
                  TextSpan(
                    children: recognized.isEmpty
                        ? <InlineSpan>[TextSpan(text: l.dietNoRecognizedFood)]
                        : <InlineSpan>[
                            for (
                              int i = 0;
                              i < r.foods.length;
                              i++
                            ) ...<InlineSpan>[
                              if (i > 0) const TextSpan(text: ' · '),
                              // 한 음식의 이름과 양은 줄이 바뀌어도 붙어 있다 —
                              // 이름 안·이름과 양 사이를 붙는 공백으로 잇고, 줄은
                              // ` · ` 에서만 바뀐다. `그래놀라` / `토핑 50g` 처럼
                              // 한 음식이 두 줄로 갈리면 다른 음식처럼 읽힌다.
                              TextSpan(text: _keepTogether(r.foods[i].name)),
                              if (r.foods[i].amountG case final double grams)
                                TextSpan(
                                  text: _keepTogether(
                                    '$_nbsp${_gramsText(grams)}${l.dietUnitG}',
                                  ),
                                  style: OnCareTypography.numeric(
                                    _text(
                                      context,
                                      OnCareTypography.caption,
                                      OnCareColors.textSecondary,
                                    ),
                                  ),
                                ),
                            ],
                          ],
                  ),
                  style: _text(
                    context,
                    OnCareTypography.titleSmall,
                    OnCareColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: OnCareSpacing.s12),
        ],
        // 기록 날짜와 끼니. 날짜는 `날짜 변경` 으로 여기서 바로 따로 옮기고
        // (#1241, #1947), 끼니·음식은 헤더 연필이 여는 수정 모드에서 고친다
        // (#2097) — 식단 상세의 `식사 정보` 카드와 같은 나눔이다.
        //
        // 식단 상세의 `식사 정보` 카드와 같은 두 줄이다 — 한 줄에 `날짜 · 끼니`
        // 로 붙여 두면 끼니가 날짜의 꼬리처럼 읽혀, 이 기록이 어느 끼니로
        // 들어가는지(#1897) 눈에 덜 띈다. 두 값이 같은 자리에서 시작하도록
        // 라벨 열 폭을 맞춘다. 시각은 두지 않는다(#1989) — `time_label` 은
        // 계속 저장되지만 그리지 않는다.
        //
        // 위아래가 모두 구획이라 이 줄만 맨바닥이면 라벨이 `인식된 음식`·
        // `칼로리` 보다 한 칸 왼쪽에서 시작한다. 같은 구획에 넣어 시작하는
        // 자리를 맞춘다(#1864).
        AppTile(
          tone: AppTileTone.none,
          child: Table(
            columnWidths: const <int, TableColumnWidth>{
              0: IntrinsicColumnWidth(),
              1: FlexColumnWidth(),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: <TableRow>[
              TableRow(
                children: <Widget>[
                  _InfoLabel(l.dietRecordDate),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          _recordDateLabel(context, _date),
                          key: const Key('diet-result-date'),
                          style: _text(
                            context,
                            OnCareTypography.strong(OnCareTypography.bodySmall),
                            OnCareColors.textPrimary,
                          ),
                        ),
                      ),
                      // 날짜를 옮기는 동안 버튼이 spinner 로 바뀐다. 자리를
                      // 잡아 두지 않으면 줄 높이가 내려앉아 라벨과 값이 함께
                      // 튄다 — 두 상태가 같은 높이를 쓴다(#1864).
                      SizedBox(
                        height: tokens.density.buttonHeight(
                          OnCareButtonSize.small,
                        ),
                        child: Center(
                          child: _movingDate
                              ? const AppLoading.inline()
                              : AppButton(
                                  key: const Key('diet-result-date-change'),
                                  label: l.dietRecordDateChange,
                                  onPressed: () => unawaited(_pickDate()),
                                  variant: AppButtonVariant.text,
                                  size: OnCareButtonSize.small,
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const TableRow(
                children: <Widget>[
                  SizedBox(height: OnCareSpacing.s8),
                  SizedBox(height: OnCareSpacing.s8),
                ],
              ),
              TableRow(
                children: <Widget>[
                  _InfoLabel(l.dietMealKind),
                  if (_editing)
                    _MealTypeChips(
                      key: const Key('diet-result-meal'),
                      selected: _type,
                      onSelected: (MealType t) => setState(() => _type = t),
                    )
                  else
                    Align(
                      key: const Key('diet-result-meal'),
                      alignment: Alignment.centerLeft,
                      child: AppTag(
                        label: mealBadge(l, _meal),
                        tone: AppTagTone.brand,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: OnCareSpacing.s12),
        if (_editing) ...<Widget>[
          _foodsEditor(l),
          const SizedBox(height: OnCareSpacing.s12),
        ],
        Text(
          l.dietNutritionResult,
          style: _text(
            context,
            OnCareTypography.label,
            OnCareColors.textSecondary,
          ),
        ),
        const SizedBox(height: OnCareSpacing.s8),
        // 탄단지가 기준이다 — 식단 상세의 영양 정보와 같은 순서로 읽힌다.
        // 당류는 탄수화물의 일부라 바로 아래에 들여 붙이고, 나트륨은
        // 탄단지가 아니라 맨 끝이다(#1864).
        Column(
          key: const Key('diet-result-nutrition'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _ResultRow(label: l.dietCalories, value: kcal, unit: l.unitKcal),
            const SizedBox(height: OnCareSpacing.s8),
            _ResultRow(
              label: l.homeMacroCarbs,
              value: _gramsText(carbs),
              unit: l.dietUnitG,
            ),
            const SizedBox(height: OnCareSpacing.s8),
            _ResultRow(
              label: l.dietSugar,
              // 서버가 준 double 을 그대로 문자열로 만들면 29.497999999999998
              // 이 찍힌다 — 칼로리·나트륨과 같은 서식으로 맞춘다(#1564).
              value: _gramsText(sugar),
              unit: l.dietUnitG,
              sub: true,
            ),
            const SizedBox(height: OnCareSpacing.s8),
            _ResultRow(
              label: l.homeMacroProtein,
              value: _gramsText(protein),
              unit: l.dietUnitG,
            ),
            const SizedBox(height: OnCareSpacing.s8),
            _ResultRow(
              label: l.homeMacroFat,
              value: _gramsText(fat),
              unit: l.dietUnitG,
            ),
            const SizedBox(height: OnCareSpacing.s8),
            _ResultRow(
              label: l.dietSodium,
              value: '$sodium',
              unit: l.dietUnitMg,
            ),
          ],
        ),
      ],
    );
  }

  /// 수정 모드의 `먹은 음식` 구획 — 음식마다 이름·내용량·영양 칸과, 음식을
  /// 더하는 버튼. 칸은 식단 상세의 수정 모드와 같은 편집기다(#2097).
  Widget _foodsEditor(AppLocalizations l) {
    return Column(
      key: const Key('diet-result-foods-editor'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                l.dietEatenFood,
                style: _text(
                  context,
                  OnCareTypography.label,
                  OnCareColors.textSecondary,
                ),
              ),
            ),
            AppButton(
              key: const Key('diet-result-add-food'),
              label: l.dietAddFood,
              leadingIcon: AppIcons.add,
              variant: AppButtonVariant.text,
              size: OnCareButtonSize.small,
              onPressed: _addFood,
            ),
          ],
        ),
        Text(
          l.dietEditFoodHint,
          style: _text(
            context,
            OnCareTypography.caption,
            OnCareColors.textSecondary,
          ),
        ),
        const SizedBox(height: OnCareSpacing.s8),
        for (int i = 0; i < _foods.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: OnCareSpacing.s8),
          _foodEditor(i),
        ],
      ],
    );
  }
}

/// 분석 결과의 영양 한 줄. 식단 상세의 [_NutrientRow] 와 같은 구성이고,
/// 숫자만 브랜드 색이다 — 여기 값은 아직 저장 전이라 고친 값이 아니다.
class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.label,
    required this.value,
    required this.unit,
    this.sub = false,
  });

  /// 한 칸 들여쓰는 폭. 하위 항목이 상위 항목 라벨보다 안쪽에서 시작해야
  /// `당류` 가 `탄수화물` 에 딸린 값으로 읽힌다 — 식단 상세와 같은 값이다.
  static const double _subIndent = 16;

  final String label;
  final String value;
  final String unit;

  /// 바로 위 항목의 하위 값인가 — 들여쓰고 앞에 `↳` 를 붙인다.
  final bool sub;

  @override
  Widget build(BuildContext context) {
    final OnCareTokens tokens = context.oncare;
    return AppTile(
      tone: AppTileTone.none,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: <Widget>[
          if (sub) ...<Widget>[
            const SizedBox(width: _subIndent),
            Text(
              '↳',
              style: _text(
                context,
                OnCareTypography.bodySmall,
                OnCareColors.textTertiary,
              ),
            ),
            const SizedBox(width: OnCareSpacing.s4),
          ],
          Expanded(
            child: Text(
              label,
              style: _text(
                context,
                OnCareTypography.strong(OnCareTypography.body),
                OnCareColors.textPrimary,
              ),
            ),
          ),
          Text(
            value,
            style: OnCareTypography.numeric(
              _text(context, OnCareTypography.titleSmall, tokens.brand.primary),
            ),
          ),
          const SizedBox(width: OnCareSpacing.s4),
          Text(
            unit,
            style: _text(
              context,
              OnCareTypography.bodySmall,
              OnCareColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────── 식사 수정 ──

/// Opens meal details as a full page above the member tab shell.
Future<void> openMealDetailPage(BuildContext context, DietMeal meal) {
  final String? id = meal.id;
  if (id == null) return Future<void>.value();
  return context.push<void>(AppRoutes.dietEntryDetailPath(id), extra: meal);
}

/// Full-page meal editor. [initialMeal] makes the first transition immediate;
/// when a web URL is refreshed, the same meal is restored from today's data.
class DietMealDetailPage extends ConsumerStatefulWidget {
  const DietMealDetailPage({
    super.key,
    required this.entryId,
    this.initialMeal,
  });

  final String entryId;
  final DietMeal? initialMeal;

  @override
  ConsumerState<DietMealDetailPage> createState() => _DietMealDetailPageState();
}

class _DietMealDetailPageState extends ConsumerState<DietMealDetailPage> {
  /// 오늘 목록에서 한 번 찾은 끼니. 찾은 뒤로는 목록을 다시 보지 않는다.
  ///
  /// 분석 완료 시트의 연필은 [DietMealDetailPage.initialMeal] 없이 이 화면을
  /// 연다. 여기서 날짜를 어제로 옮기면 오늘 목록에서 그 기록이 빠지므로,
  /// 목록을 계속 따라가면 방금 옮긴 화면이 `불러오지 못했어요` 로 바뀐다
  /// (#1947).
  DietMeal? _found;

  /// 오늘 목록에서 찾았으니 날짜는 오늘이다.
  DietMeal _fromEntry(DietEntry entry) => DietMeal(
    id: entry.id,
    mealType: entry.mealType,
    date: _todayKst(),
    time: entry.timeLabel,
    total: entry.totalCalories,
    emoji: '',
    thumbBg: OnCareColors.surfaceInput,
    photoAsset: entry.photoAsset,
    photoUrl: entry.photoUrl,
    aiComment: entry.aiComment,
    // 웹에서 새로고침해 들어오면 `initialMeal` 없이 이 경로로 복원된다 —
    // 여기서도 영양을 하나도 흘리지 않아야 저장 뒤에 합계가 남는다(#1853).
    items: <DietFood>[
      for (final FoodItem food in entry.foods)
        DietFood(
          food.name,
          food.calories,
          amountG: food.amountG,
          sodiumMg: food.sodiumMg,
          sugarG: food.sugarG,
          carbsG: food.carbsG,
          proteinG: food.proteinG,
          fatG: food.fatG,
          source: food.source,
        ),
    ],
    tags: const <DietTag>[],
    sodium: entry.sodiumMg,
    sugar: entry.sugarG,
    carbsG: entry.carbsG,
    proteinG: entry.proteinG,
    fatG: entry.fatG,
  );

  @override
  Widget build(BuildContext context) {
    final DietMeal? supplied = widget.initialMeal;
    if (supplied != null && supplied.id == widget.entryId) {
      return _MealEditSheet(meal: supplied);
    }
    final DietMeal? found = _found;
    if (found != null) return _MealEditSheet(meal: found);

    final AppLocalizations l = AppLocalizations.of(context);
    return ref
        .watch(dietTodayProvider)
        .when(
          data: (DietDay day) {
            for (final DietEntry entry in day.entries) {
              if (entry.id == widget.entryId) {
                // 빌드 중에 setState 하지 않는다 — 한 번 기억해 두고 같은
                // 값으로 그린다. 다음 빌드부터는 위에서 곧장 돌아간다.
                return _MealEditSheet(meal: _found = _fromEntry(entry));
              }
            }
            return _MealDetailUnavailable(message: l.dietLoadError);
          },
          loading: () => const Scaffold(
            backgroundColor: OnCareColors.surfaceCard,
            body: AppLoading(),
          ),
          error: (_, _) => _MealDetailUnavailable(message: l.dietLoadError),
        );
  }
}

class _MealDetailUnavailable extends StatelessWidget {
  const _MealDetailUnavailable({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OnCareColors.surfaceCard,
      appBar: AppTopBar(title: ''),
      body: AppEmptyState(title: message, icon: AppIcons.error),
    );
  }
}

/// 끼니의 음식 목록을 고치는 편집기. 식단 상세의 수정 모드와 분석 완료
/// 시트의 수정 모드가 함께 쓴다(#2097).
///
/// 음식별 입력 칸, 섭취량 비례 환산(#1876), 공공 DB 제안(#1896), 당류 검사
/// (#1869), 영양 출처(#2105), 탄단지를 따라가는 열량(#2106), 이름을 바꾸면
/// 그 음식의 값(#2107)이 여기 모여 있다. 두 화면이 따로 들고 있으면 한쪽만
/// 고쳐져 같은 음식이 화면마다 다르게 고쳐진다.
///
/// 처음 값은 [_loadFoods] 로 깐다.
mixin _FoodEditing<W extends ConsumerStatefulWidget> on ConsumerState<W> {
  List<DietFood> _foods = <DietFood>[];

  /// 음식 줄마다 하나씩. 컨트롤러를 줄 위젯이 아니라 시트가 들고 있어야
  /// 한 자 칠 때마다 새로 만들어지지 않는다 — 새로 만들면 커서가 맨 앞으로
  /// 튄다. 목록 순서와 1:1 로 붙어 다닌다(#1844).
  final List<_FoodEditors> _editors = <_FoodEditors>[];

  /// 음식마다 당류가 그 음식의 탄수화물을 넘지 않는지 본다(#1869). 당류는
  /// 탄수화물의 일부라 그보다 클 수 없고, 서버도 같은 값을 422 로 거절한다
  /// (#1863) — 앱이 먼저 막지 않으면 다 적고 저장을 누른 뒤에야 어느 칸이
  /// 문제인지 모르는 실패 토스트만 뜬다.
  ///
  /// 줄 번호가 아니라 [_FoodEditors] 를 키로 쓴다. 음식을 지우면 아래 줄의
  /// 번호가 당겨지므로, 번호로 기억해 두면 엉뚱한 줄에 빨간 글씨가 남는다.
  late AppFieldErrors<_FoodEditors> _sugarErrors = AppFieldErrors<_FoodEditors>(
    _checkSugar,
  );

  /// 이름 칸을 벗어나면 공공 DB 를 찾는다(#1896). 줄이 지워지거나 순서가 밀려도
  /// 어긋나지 않도록 **자리(index)가 아니라 그 줄 자체**를 붙잡는다.
  _FoodEditors _watchName(_FoodEditors e) {
    e.nameFocus.addListener(() {
      if (!e.nameFocus.hasFocus) unawaited(_lookupNutrition(e));
    });
    return e;
  }

  /// 이 끼니에 탄수화물이 적혀 있었나 — 저장된 값 기준이다(#1893).
  ///
  /// 탄수화물 0 은 두 가지다. 인식기가 그 값을 못 준 옛 기록의 0 과, 회원이
  /// 방금 지운 0. 앞은 봐주지 않으면 그 기록을 영영 고칠 수 없고, 뒤는
  /// 봐주면 탄수화물을 지워 검사를 피할 수 있다. 서버도 `entry.carbs_g` 로
  /// 같은 판단을 하므로, 저장에 성공할 때마다 함께 갱신한다.
  bool _carbsRecorded = false;

  double _carbsOf(List<DietFood> foods) =>
      foods.fold<double>(0, (double a, DietFood f) => a + f.carbsG);

  /// 편집기를 [foods] 로 새로 깐다. 처음 열 때와 `취소` 로 되돌릴 때 쓴다.
  ///
  /// setState 는 부르지 않는다 — 부르는 쪽이 제 상태와 함께 한 번에 바꾼다.
  /// 버리는 컨트롤러는 그 줄이 트리에서 물러난 다음 프레임에 버린다.
  void _loadFoods(List<DietFood> foods) {
    final List<_FoodEditors> stale = List<_FoodEditors>.of(_editors);
    _foods = List<DietFood>.of(foods);
    _editors
      ..clear()
      ..addAll(<_FoodEditors>[
        for (final DietFood f in _foods) _watchName(_FoodEditors.of(f)),
      ]);
    // 접었다 다시 펴면 오류도 처음부터다 — 저장을 누른 적 없는 화면에
    // 빨간 글씨가 먼저 서 있으면 안 된다(#1784).
    _sugarErrors = AppFieldErrors<_FoodEditors>(_checkSugar);
    if (stale.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final _FoodEditors e in stale) {
        e.dispose();
      }
    });
  }

  int get _total => _foods.fold(0, (int a, DietFood f) => a + f.kcal);

  // 영양 합계는 저장된 끼니가 아니라 지금 화면의 음식에서 낸다. 서버도 같은
  // 규칙으로 합치므로(`_sumMacro`), 음식을 고치면 저장 전에도 합계가 따라와야
  // 한 화면에 서로 다른 숫자가 남지 않는다(#1856).
  double _sumOf(double Function(DietFood) pick) =>
      _foods.fold<double>(0, (double a, DietFood f) => a + pick(f));

  double get _carbs => _sumOf((DietFood f) => f.carbsG);
  double get _protein => _sumOf((DietFood f) => f.proteinG);
  double get _fat => _sumOf((DietFood f) => f.fatG);
  double get _sugar => _sumOf((DietFood f) => f.sugarG);
  int get _sodium => _foods.fold(0, (int a, DietFood f) => a + f.sodiumMg);

  @override
  void dispose() {
    for (final _FoodEditors e in _editors) {
      e.dispose();
    }
    super.dispose();
  }

  /// 빈 칸과 알아볼 수 없는 글자는 0 으로 읽는다 — 칸을 비워 지우는 것이
  /// 0 을 적는 것과 같은 뜻이 되게.
  static int _asInt(TextEditingController c) =>
      int.tryParse(c.text.trim()) ?? 0;
  static double _asDouble(TextEditingController c) =>
      double.tryParse(c.text.trim()) ?? 0;

  /// 섭취량 칸의 값. 여기서만 빈 칸이 0 이 아니라 **null** 이다 — 0g 을 먹었다는
  /// 기록은 없고, 0 은 비례 환산의 분모가 될 수도 없다.
  static double? _asAmount(TextEditingController c) {
    final double? grams = double.tryParse(c.text.trim());
    return (grams != null && grams > 0) ? grams : null;
  }

  /// 지금 그 음식 칸에 적힌 값을 비례 환산의 기준으로 세운다.
  ///
  /// 회원이 영양 칸을 직접 고쳤다는 것은 "이 양에서는 이 값이 맞다" 고 말한
  /// 것이다. 그러니 다음 섭취량 변경은 분석이 준 값이 아니라 회원이 고친 값에서
  /// 비례해야 한다. 섭취량 칸이 비어 있으면 기준 없이 둔다.
  void _captureBasis(int index) {
    final _FoodEditors e = _editors[index];
    final double? amount = _asAmount(e.amount);
    e.basis = amount == null
        ? null
        : _FoodBasis(
            amountG: amount,
            kcal: _asInt(e.kcal),
            carbsG: _asDouble(e.carbs),
            sugarG: _asDouble(e.sugar),
            proteinG: _asDouble(e.protein),
            fatG: _asDouble(e.fat),
            sodiumMg: _asInt(e.sodium),
          );
  }

  /// 당류 칸에 보일 오류 문구. 맞으면 null 이다.
  ///
  /// 서버의 `_sugar_exceeds_carbs` 와 같은 규칙이다(#1893). 앱이 더 엄격하면
  /// 서버가 받아 주는 값을 저장할 수 없고, 더 느슨하면 다 적고 저장을 누른
  /// 뒤에야 어느 칸이 문제인지 모르는 실패 토스트만 뜬다.
  String? _checkSugar(_FoodEditors e) {
    final double carbs = _asDouble(e.carbs);
    // 같은 값은 통과한다 — 전부 당인 음식이 있다.
    if (_asDouble(e.sugar) <= carbs) return null;
    // 탄수화물 0 을 어떻게 볼지는 [_carbsRecorded] 가 정한다. 이 끼니에
    // 탄수화물이 처음부터 없었다면 인식기가 그 값을 못 준 기록이라 봐주고
    // (#1877), 회원이 방금 0 으로 바꾼 0 은 적은 값으로 본다.
    if (carbs <= 0 && !_carbsRecorded) return null;
    return AppLocalizations.of(context).dietSugarOverCarbs;
  }

  /// 그 음식의 입력 칸을 모두 읽어 `_foods` 에 반영한다. 한 칸만 바뀌어도
  /// 전부 다시 읽는 편이 칸마다 따로 갈래를 두는 것보다 흘릴 값이 없다.
  /// 매 글자마다 부르는 이유는 아래 총 칼로리와 영양 정보 합계가 입력을
  /// 곧바로 따라와야 하기 때문이다.
  ///
  /// [rebase] 는 지금 값을 비례 환산의 새 기준으로 삼을지다. 영양 칸을 직접
  /// 고쳤을 때는 그래야 하고, 섭취량이 움직여 값이 따라온 직후에는 안 된다 —
  /// 거기서 기준을 다시 세우면 원본 대신 방금 반올림된 값에서 다음 곱셈이
  /// 시작된다([_FoodBasis]).
  void _syncFood(int index, {bool rebase = true}) {
    final _FoodEditors e = _editors[index];
    if (rebase) _captureBasis(index);
    setState(() {
      _foods = <DietFood>[..._foods]
        ..[index] = DietFood(
          e.name.text,
          _asInt(e.kcal),
          amountG: _asAmount(e.amount),
          sodiumMg: _asInt(e.sodium),
          sugarG: _asDouble(e.sugar),
          carbsG: _asDouble(e.carbs),
          proteinG: _asDouble(e.protein),
          fatG: _asDouble(e.fat),
          source: e.source,
        );
    });
  }

  /// 영양 칸 하나를 손으로 고쳤을 때. 그 음식의 값은 이제 **회원이 적은 값**이다
  /// (#2105) — 분석이나 공공 DB 가 준 숫자가 아니니 출처를 [FoodSource.member]
  /// 로 바꾼다. 탄단지를 고친 결과로 열량이 따라온 것도 마찬가지다.
  ///
  /// [kcal] 은 열량 칸을, [macro] 는 탄수화물·단백질·지방 칸을 고쳤다는 뜻이다.
  /// 당류·나트륨은 둘 다 아니다 — 열량에 들어가지 않는다(당류는 탄수화물의 일부).
  void _editNutrient(int index, {bool kcal = false, bool macro = false}) {
    final _FoodEditors e = _editors[index];
    // 열량을 직접 적었으면 그 음식은 이번 편집 동안 자동 반영을 멈춘다(#2106).
    // 라벨 값을 옮겨 적는 중이면, 칸을 어느 순서로 적든 라벨 열량이 남아야 한다.
    if (kcal) e.kcalPinned = true;
    if (macro) _followKcal(e);
    e
      ..source = FoodSource.member
      ..edits += 1
      // 값을 손으로 고쳤으니 "DB 값으로 바꿨어요 · 되돌리기" 는 낡았고, "값을
      // 확인해 주세요" 는 할 일을 했다.
      ..notice = null;
    _syncFood(index);
  }

  /// 탄단지가 바뀐 **만큼만** 열량을 움직인다. (#2106)
  ///
  /// `새 열량 = 기준 열량 + 4×Δ탄수화물 + 4×Δ단백질 + 9×Δ지방`. 4·4·9 로 새로
  /// 계산해 덮지 않는 이유는 공공 DB 열량이 식품마다 다른 에너지 환산계수를 써서다
  /// — 삼겹살 구운것은 100g 484kcal 인데 4·4·9 로는 462kcal 다. 새로 계산하면
  /// 지방만 줄였는데도 성분표가 알던 몫이 함께 사라진다.
  ///
  /// 기준은 한 글자마다 다시 세우지 않는다([_EnergyBasis]).
  void _followKcal(_FoodEditors e) {
    if (e.kcalPinned || e.fillOnly) return;
    e.kcal.text = _FoodEditors.intText(
      e.energy.kcalFor(
        carbsG: _asDouble(e.carbs),
        proteinG: _asDouble(e.protein),
        fatG: _asDouble(e.fat),
      ),
    );
  }

  /// 섭취량 칸이 바뀌었을 때 — 영양 여섯 값이 같은 비율로 따라온다. (#1876)
  ///
  /// 공공 영양 DB 는 100g 기준이고 서버 보정이 그 양으로 환산해 둔 값이 지금
  /// 칸에 적혀 있다. 그러니 양이 바뀌었을 때 필요한 것은 DB 재조회가 아니라
  /// 곱셈 한 번이다 — `새 값 = 기준 값 × (새 양 / 기준 양)`.
  void _syncAmount(int index) {
    final _FoodEditors e = _editors[index];
    final _FoodBasis? basis = e.basis;
    if (basis == null) {
      // 양을 모르던 음식이다. 지금 적어 넣은 값이 기준이 될 뿐, 영양은
      // 그대로 둔다 — 모르던 양을 적었다고 영양이 튀면 적기가 무서워진다.
      _syncFood(index);
      return;
    }
    final double? amount = _asAmount(e.amount);
    if (amount != null) {
      final double factor = amount / basis.amountG;
      e.kcal.text = _FoodEditors.intText((basis.kcal * factor).round());
      e.carbs.text = _FoodEditors.gramText(basis.carbsG * factor);
      e.sugar.text = _FoodEditors.gramText(basis.sugarG * factor);
      e.protein.text = _FoodEditors.gramText(basis.proteinG * factor);
      e.fat.text = _FoodEditors.gramText(basis.fatG * factor);
      e.sodium.text = _FoodEditors.intText((basis.sodiumMg * factor).round());
      // 방금 곱해 적은 한 벌은 서로 맞는 값이다 — 이어서 탄단지를 고치면 열량은
      // 이 값에서 바뀐 만큼 움직여야 한다(#2106).
      e.energy = e.readEnergy();
    }
    // 칸을 비웠을 때는 영양을 건드리지 않는다. 양을 적지 않겠다는 뜻이지 아무
    // 것도 안 먹었다는 뜻이 아니다. 기준도 그대로 두어, 다시 적으면 처음 그
    // 한 벌에서 비례한다 — 지우고 고쳐 쓰는 동안 값이 조금씩 어긋나지 않는다.
    //
    // 출처는 그대로다(#2105). 양만 바꾼 음식은 여전히 DB × 양이고, 추정은
    // 추정 × 양이다. 다만 "DB 값으로 바꿨어요 · 되돌리기" 는 거둔다 — 되돌리면
    // 방금 적은 양까지 되돌아가 버린다.
    if (e.notice is _FilledFromDb) e.notice = null;
    _syncFood(index, rebase: false);
  }

  /// 이름 칸을 벗어났을 때 공공 영양 DB 를 찾는다. (#1896, #2107)
  ///
  /// 이름을 **바꿨다면** 칸의 값은 이제 다른 음식의 것이다. 옛 음식의 값이 새
  /// 이름 아래 조용히 남는 것이 가장 부정확하므로, 찾은 결과에 따라 셋으로 나눈다.
  ///
  /// - **같은 음식**이 DB 에 있으면(이름·별칭·표기 변형이 같다) 곧바로 그 값으로
  ///   채우고 "무엇으로 바꿨는지 · 되돌리기" 를 띄운다. 되돌릴 수 있어야 손으로
  ///   바로잡아 둔 값이 소리 없이 사라지지 않는다 — #1896 이 제안만 하던 까닭이다.
  /// - **비슷한 음식**만 있으면(이름 끝말로 붙었다) 제안만 한다. 끝말로 붙은 값은
  ///   틀린 경우가 많아 회원이 보고 골라야 한다(서버 `matcher.find_in_rows`).
  /// - 없으면 값은 두고 확인해 달라고 말한다.
  ///
  /// 이름을 바꾸지 않고 칸만 드나들었으면 예전처럼 제안만 한다. 조회가 도는 사이
  /// 회원이 영양 칸을 고쳤으면 그 값이 이긴다 — 덮지 않고 제안으로 남긴다.
  ///
  /// 지금 적힌 양을 함께 보낸다 — 그 양의 값이어야 회원이 "내가 먹은 만큼" 을
  /// 보게 된다. 사진 속 그릇의 양은 이름이 바뀌어도 같다. 양이 없으면 서버가 그
  /// 음식의 1회 섭취량으로 답한다.
  Future<void> _lookupNutrition(_FoodEditors e) async {
    final String name = e.name.text.trim();
    if (name.isEmpty) {
      // 이름을 지웠는데 아까 제안이 남아 있으면 그게 무엇의 제안인지 알 수 없다.
      if (e.suggestion != null || e.lookedUpName != null || e.notice != null) {
        setState(() {
          e.suggestion = null;
          e.lookedUpName = null;
          e.notice = null;
        });
      }
      return;
    }
    if (name == e.lookedUpName) return;
    e.lookedUpName = name;
    final bool renamed = name != e.valuesName;
    final int editsBefore = e.edits;
    FoodNutritionSuggestion? found;
    bool failed = false;
    try {
      found = await ref
          .read(dietRepositoryProvider)
          .lookupFoodNutrition(name: name, amountG: _asAmount(e.amount));
    } on Object {
      // 조회가 실패해도 수정과 저장은 그대로 된다. 찾기는 거들 뿐이라
      // 여기서 막을 이유가 없다.
      failed = true;
    }
    // 그 사이 이름이 또 바뀌었거나 그 줄이 지워졌으면 이 응답은 낡은 값이다.
    final int index = _editors.indexOf(e);
    if (!mounted || e.lookedUpName != name || index < 0) return;
    if (!renamed) {
      setState(() => e.suggestion = found);
      return;
    }
    // 여기부터 칸의 값은 새 이름의 것으로 본다 — 같은 이름으로 다시 드나들어도
    // 이름 변경으로 세지 않는다.
    e.valuesName = name;
    if (found != null && found.exact && e.edits == editsBefore) {
      _fillFrom(index, found, announce: true);
      return;
    }
    setState(() {
      e
        ..suggestion = found
        // 옛 음식의 값이 새 이름 아래 남았다 — 공공 DB 나 분석이 이 이름에 대해
        // 말한 숫자가 아니다(#2105).
        ..source = FoodSource.member
        // 없다는 것을 알 때만 말한다. 조회가 실패했으면 없는 음식인지 모른다.
        ..notice = (found == null && !failed) ? const _NotInDb() : null;
    });
    _syncFood(index, rebase: false);
  }

  /// 제안을 적용하면 달라지는 값이 있나. 없으면 제안을 띄우지 않는다 —
  /// 이미 그 값인데 `값 채우기` 가 서 있으면 누를 이유를 찾게 된다.
  bool _suggestionWouldChange(_FoodEditors e) {
    final FoodNutritionSuggestion? s = e.suggestion;
    final _FoodBasis? filled = s == null ? null : _filledBy(e, s);
    return filled != null && _wouldChange(e, filled);
  }

  /// [filled] 로 채우면 지금 칸과 달라지는 값이 있나.
  bool _wouldChange(_FoodEditors e, _FoodBasis filled) {
    bool sameGram(double a, double b) => (a - b).abs() < 0.05;
    return !(filled.kcal == _asInt(e.kcal) &&
        filled.sodiumMg == _asInt(e.sodium) &&
        sameGram(filled.carbsG, _asDouble(e.carbs)) &&
        sameGram(filled.sugarG, _asDouble(e.sugar)) &&
        sameGram(filled.proteinG, _asDouble(e.protein)) &&
        sameGram(filled.fatG, _asDouble(e.fat)) &&
        sameGram(filled.amountG, _asAmount(e.amount) ?? 0));
  }

  /// 제안을 **지금 적힌 양에 맞춰** 환산한 한 벌.
  ///
  /// 회원이 이미 양을 적어 두었으면 그 양이 이긴다 — 제안을 받았다고 내가 적은
  /// 양이 뒤집히면 안 된다. 양이 없을 때만 제안이 들고 온 1회 섭취량을 쓴다.
  /// 곱셈은 #1876 의 비례 환산과 같은 계산이다.
  _FoodBasis? _filledBy(_FoodEditors e, FoodNutritionSuggestion s) {
    final double? base = s.food.amountG;
    if (base == null || base <= 0) return null;
    final double target = _asAmount(e.amount) ?? base;
    final double factor = target / base;
    return _FoodBasis(
      amountG: target,
      kcal: (s.food.calories * factor).round(),
      carbsG: s.food.carbsG * factor,
      sugarG: s.food.sugarG * factor,
      proteinG: s.food.proteinG * factor,
      fatG: s.food.fatG * factor,
      sodiumMg: (s.food.sodiumMg * factor).round(),
    );
  }

  /// `값 채우기` — 제안한 값으로 그 음식의 칸을 채운다.
  void _applySuggestion(int index) {
    final FoodNutritionSuggestion? s = _editors[index].suggestion;
    if (s != null) _fillFrom(index, s);
  }

  /// 공공 DB 에서 찾은 값으로 그 음식의 칸을 채운다. `값 채우기` 와, 같은
  /// 음식으로 이름을 바꿨을 때(#2107)가 같은 길을 쓴다.
  ///
  /// 채운 한 벌은 서로 맞는 값이라 모든 기준이 여기서 다시 선다 — 이어서 내용량을
  /// 고치면 #1876 의 비례 환산이, 탄단지를 고치면 #2106 의 열량 반영이 이 값에서
  /// 출발한다. 출처는 찾은 값의 것이다(#2105).
  ///
  /// [announce] 면 무엇으로 바꿨는지 말하고 되돌릴 수 있게 한다. 회원이 누르지
  /// 않았는데 값이 바뀌었기 때문이다.
  void _fillFrom(
    int index,
    FoodNutritionSuggestion found, {
    bool announce = false,
  }) {
    final _FoodEditors e = _editors[index];
    final _FoodBasis? filled = _filledBy(e, found);
    if (filled == null) return;
    final bool changes = _wouldChange(e, filled);
    final _FoodSnapshot before = _FoodSnapshot.of(e);
    e.amount.text = _FoodEditors.gramText(filled.amountG);
    e.kcal.text = _FoodEditors.intText(filled.kcal);
    e.carbs.text = _FoodEditors.gramText(filled.carbsG);
    e.sugar.text = _FoodEditors.gramText(filled.sugarG);
    e.protein.text = _FoodEditors.gramText(filled.proteinG);
    e.fat.text = _FoodEditors.gramText(filled.fatG);
    e.sodium.text = _FoodEditors.intText(filled.sodiumMg);
    e
      ..source = found.food.source
      ..valuesName = e.name.text.trim()
      ..energy = e.readEnergy()
      ..kcalPinned = false
      ..fillOnly = false;
    setState(() {
      // 제안을 거둔다 — 방금 그 값으로 채웠으니 더 제안할 것이 없다.
      e.suggestion = null;
      // 이미 그 값이었으면 바뀐 것이 없으니 말할 것도 없다.
      e.notice = announce && changes ? _FilledFromDb(found, before) : null;
    });
    _syncFood(index);
  }

  /// `되돌리기` — 이름을 바꿔 채운 값을 바꾸기 전으로 되돌린다(#2107).
  ///
  /// 이름은 새 이름 그대로다. 옛 값을 새 이름 아래 두기로 한 것이니 출처는
  /// 회원의 몫이다(#2105). 찾은 값은 제안으로 남겨 다시 고를 수 있게 한다.
  void _undoFill(int index) {
    final _FoodEditors e = _editors[index];
    final _NameNotice? notice = e.notice;
    if (notice is! _FilledFromDb) return;
    notice.before.restoreTo(e);
    e.source = FoodSource.member;
    setState(() {
      e.notice = null;
      e.suggestion = notice.found;
    });
    _syncFood(index, rebase: false);
  }

  void _addFood() {
    // Empty draft name; the localized label is shown only as a placeholder
    // and is validated out on save. 새 줄의 값은 회원이 적는다(#2105) — 공공 DB
    // 값으로 채우면 그때 출처가 바뀐다.
    const DietFood draft = DietFood('', 0, source: FoodSource.member);
    setState(() {
      _foods = <DietFood>[..._foods, draft];
      // 새 줄에서도 이름만 적으면 공공 DB 값을 제안받는다 — 오히려 이쪽이 더
      // 요긴하다. 일곱 칸을 손으로 채우지 않아도 된다(#1896).
      _editors.add(_watchName(_FoodEditors.of(draft)));
    });
  }

  void _removeFood(int index) {
    final _FoodEditors removed = _editors.removeAt(index);
    setState(() => _foods = <DietFood>[..._foods]..removeAt(index));
    // 이번 프레임에는 아직 지워진 줄이 트리에 남아 있다 — 그 줄이 물러난
    // 뒤에 버린다.
    WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
  }

  /// 저장할 음식. 이름이 빈 줄은 버린다 — 새 줄의 자리표시 문구
  /// (`dietNewFood`)가 음식 이름으로 저장되지 않게.
  ///
  /// 영양은 이름·칼로리와 함께 되돌려 보낸다. 빠뜨리면 이 저장 한 번으로
  /// 그 끼니의 탄단지·나트륨·당류가 0 이 된다 — 합계가 음식별 값에서
  /// 계산되기 때문이다(#1853).
  List<FoodItem> _foodPayload() => <FoodItem>[
    for (final DietFood f in _foods)
      if (f.name.trim().isNotEmpty)
        FoodItem(
          name: f.name.trim(),
          calories: f.kcal,
          amountG: f.amountG,
          sodiumMg: f.sodiumMg,
          sugarG: f.sugarG,
          carbsG: f.carbsG,
          proteinG: f.proteinG,
          fatG: f.fatG,
          source: f.source,
        ),
  ];

  /// 보낼 줄만 검사한다 — 이름이 빈 줄은 [_foodPayload] 가 버리므로, 거기
  /// 남은 숫자 때문에 저장이 막히면 어디를 고쳐야 하는지 알 수 없다.
  /// 틀린 칸이 있으면 그 아래에 이유를 세우고 false 다(#1869).
  bool _validateFoods() {
    final List<_FoodEditors> filled = <_FoodEditors>[
      for (int i = 0; i < _foods.length; i++)
        if (_foods[i].name.trim().isNotEmpty) _editors[i],
    ];
    if (_sugarErrors.validate(filled)) return true;
    setState(() {});
    return false;
  }

  /// 끼니·음식을 기록에 반영한다. 날짜는 보내지 않는다 — `날짜 변경` 이 따로
  /// 옮긴다(#1947).
  Future<void> _saveFoods({
    required String id,
    required MealType mealType,
    required List<FoodItem> foods,
  }) {
    return ref
        .read(dietRepositoryProvider)
        .updateEntry(
          id: id,
          mealType: mealType.name,
          foods: foods,
          totalCalories: foods.fold<int>(
            0,
            (int a, FoodItem f) => a + f.calories,
          ),
          // 나트륨·당류는 끼니 행에도 따로 저장된다 — 음식에서 다시 합쳐
          // 보내지 않으면 음식별 값만 바뀌고 끼니 합계는 옛 숫자에 머문다.
          sodiumMg: foods.fold<int>(0, (int a, FoodItem f) => a + f.sodiumMg),
          sugarG: foods.fold<double>(0, (double a, FoodItem f) => a + f.sugarG),
        );
  }

  /// `총 칼로리` 줄. 식단 상세와 직접 추가가 함께 쓴다.
  Widget _totalRow(BuildContext context, AppLocalizations l) {
    final OnCareTokens tokens = context.oncare;
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            l.dietTotalCalories,
            style: _text(
              context,
              OnCareTypography.strong(OnCareTypography.bodySmall),
              OnCareColors.textPrimary,
            ),
          ),
        ),
        Text(
          '$_total ${l.unitKcal}',
          key: const Key('meal-total'),
          style: OnCareTypography.numeric(
            _text(context, OnCareTypography.titleSmall, tokens.brand.primary),
          ),
        ),
      ],
    );
  }

  /// 지금 화면의 음식에서 낸 영양 합계 카드. 식단 상세와 직접 추가가 함께
  /// 쓴다 — 두 화면이 같은 순서·같은 서식으로 읽혀야 한다.
  Widget _nutritionCard(BuildContext context, AppLocalizations l) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _FieldLabel(l.dietNutritionInfo),
          const SizedBox(height: OnCareSpacing.s4),
          Text(
            l.dietEditNutritionHint,
            style: _text(
              context,
              OnCareTypography.caption,
              OnCareColors.textSecondary,
            ),
          ),
          const SizedBox(height: OnCareSpacing.s12),
          // 탄단지가 기준이다. 당류는 탄수화물의 일부라 바로 아래에 들여 붙이고,
          // 나트륨은 탄단지가 아니라 맨 끝에 둔다. 지방은 포화·트랜스까지 나누지
          // 않는다 — 분석이 그만큼 재지 못한다.
          _NutrientRow(
            label: l.homeMacroCarbs,
            value: _gramsText(_carbs),
            unit: l.dietUnitG,
          ),
          const SizedBox(height: OnCareSpacing.s8),
          _NutrientRow(
            label: l.dietSugar,
            value: _gramsText(_sugar),
            unit: l.dietUnitG,
            sub: true,
          ),
          const SizedBox(height: OnCareSpacing.s8),
          _NutrientRow(
            label: l.homeMacroProtein,
            value: _gramsText(_protein),
            unit: l.dietUnitG,
          ),
          const SizedBox(height: OnCareSpacing.s8),
          _NutrientRow(
            label: l.homeMacroFat,
            value: _gramsText(_fat),
            unit: l.dietUnitG,
          ),
          const SizedBox(height: OnCareSpacing.s8),
          _NutrientRow(
            label: l.dietSodium,
            value: '$_sodium',
            unit: l.dietUnitMg,
          ),
        ],
      ),
    );
  }

  /// 음식 한 줄의 수정 칸.
  Widget _foodEditor(int i) => _FoodEditBlock(
    index: i + 1,
    editors: _editors[i],
    sugarError: _sugarErrors.of(_editors[i]),
    // 이름만 바뀐 동안에는 기준을 다시 세우지 않는다 — 값은 그대로다. 이름이
    // 값에 닿는 것은 칸을 벗어난 뒤다([_lookupNutrition]).
    onNameChanged: () => _syncFood(i, rebase: false),
    onAmountChanged: () => _syncAmount(i),
    onKcalChanged: () => _editNutrient(i, kcal: true),
    onMacroChanged: () => _editNutrient(i, macro: true),
    onChanged: () => _editNutrient(i),
    onDelete: () => _removeFood(i),
    suggestion: _suggestionWouldChange(_editors[i])
        ? _editors[i].suggestion
        : null,
    onApplySuggestion: () => _applySuggestion(i),
    onUndoFill: () => _undoFill(i),
  );
}

// ─────────────────────────────────────────────────── 직접 추가 ──

/// 사진 없이 끼니를 적는 화면을 연다(#2151). 저장했으면 true.
///
/// 하단 내비·`+` 버튼을 가리도록 루트 내비게이터에 올린다 — 사진 선택 시트와
/// 같은 자리다(#791).
Future<bool> openDietManualAddPage(BuildContext context) async {
  final bool? saved = await Navigator.of(context, rootNavigator: true)
      .push<bool>(
        MaterialPageRoute<bool>(builder: (_) => const _MealCreatePage()),
      );
  return saved ?? false;
}

/// 사진 없이 적는 끼니. 식단 상세의 수정 모드와 같은 칸을 빈 채로 연다.
///
/// 음식 칸은 [_FoodEditing] 을 그대로 쓴다 — 이름을 적고 칸을 벗어나면 공공 DB
/// 값을 찾아 채우거나 제안하는 흐름(#1896, #2107)이 여기서 가장 요긴하다. 일곱
/// 칸을 손으로 채우지 않아도 된다.
///
/// **사진은 받지 않는다.** 사진 분석으로 저장한 끼니에도 사진을 바꾸는 길이
/// 없어, 여기서만 사진을 받으면 흐름이 갈린다. 목록 썸네일은 음식 이름으로
/// 고른 이모지다(`mealThumbEmoji`).
class _MealCreatePage extends ConsumerStatefulWidget {
  const _MealCreatePage();

  @override
  ConsumerState<_MealCreatePage> createState() => _MealCreatePageState();
}

class _MealCreatePageState extends ConsumerState<_MealCreatePage>
    with _FoodEditing<_MealCreatePage> {
  /// 처음 끼니는 사진 분석과 같이 지금 시각으로 고른다.
  MealType _type = MealType.values.byName(_currentMealType());
  DateTime _date = _todayKst();
  bool _busy = false;

  /// `음식을 하나 이상 적어 주세요` — 저장을 눌렀는데 이름 적힌 음식이 없을 때.
  bool _showEmpty = false;

  /// 저장 한 번에 하나. 응답을 잃고 다시 누른 저장이 끼니를 둘 만들지 않는다.
  final String _idempotencyKey =
      'manual-${DateTime.now().microsecondsSinceEpoch}';

  @override
  void initState() {
    super.initState();
    // 빈 줄 하나로 연다 — 무엇을 적는 화면인지 칸이 먼저 말한다.
    _loadFoods(const <DietFood>[DietFood('', 0, source: FoodSource.member)]);
    // 회원이 적는 값이라 탄수화물 0 도 적은 값이다 — 서버도 그렇게 본다.
    _carbsRecorded = true;
  }

  Future<void> _pickDate() async {
    final DateTime today = _todayKst();
    final DateTime? picked = await showAppDatePicker(
      context: context,
      initialDate: _date,
      // 지난 식사는 얼마든지 적을 수 있지만, 앞날의 식사는 아직 먹지 않았다.
      firstDate: DateTime(today.year - 1),
      lastDate: today,
      showClose: false,
    );
    if (picked == null || !mounted) return;
    setState(() => _date = DateTime(picked.year, picked.month, picked.day));
  }

  Future<void> _save() async {
    final AppLocalizations l = AppLocalizations.of(context);
    final NavigatorState navigator = Navigator.of(context);
    // 페이지를 닫은 뒤에 결과를 알리므로, 사라지지 않는 내비게이터 자리를 쓴다.
    final BuildContext toastContext = navigator.context;
    final List<FoodItem> foods = _foodPayload();
    if (foods.isEmpty) {
      setState(() => _showEmpty = true);
      return;
    }
    if (!_validateFoods()) return;
    setState(() {
      _busy = true;
      _showEmpty = false;
    });
    try {
      await ref
          .read(dietRepositoryProvider)
          .createEntry(
            date: wireDate(_date),
            mealType: _type.name,
            foods: foods,
            idempotencyKey: _idempotencyKey,
          );
      if (!mounted) return;
      ref.invalidate(dietTodayProvider);
      // 기간 뷰(이번 주·전체)는 오늘을 dietByDateProvider 로 읽는다.
      ref.invalidate(dietByDateProvider(nowKst()));
      ref.invalidate(dietByDateProvider(_date));
      // 포인트는 적립되지 않는다 — 사진 분석 저장만 적립한다(#2151).
      navigator.pop(true);
      if (!toastContext.mounted) return;
      showAppToast(toastContext, l.dietSaved, type: AppToastType.success);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
      if (toastContext.mounted) {
        showAppToast(toastContext, l.dietSaveFailed, type: AppToastType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final double side = tokens.density.pagePadding;
    final Widget page = Scaffold(
      key: const Key('mealCreatePage'),
      backgroundColor: OnCareColors.surfaceCard,
      appBar: AppTopBar(title: l.dietManualAddTitle),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: OnCareLayout.mobileContentMaxWidth,
            ),
            child: Column(
              children: <Widget>[
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      side,
                      OnCareSpacing.s8,
                      side,
                      OnCareSpacing.sectionGap,
                    ),
                    children: <Widget>[
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            _FieldLabel(l.dietMealInfo),
                            const SizedBox(height: OnCareSpacing.s12),
                            // 식단 상세와 같은 두 줄 — 날짜와 끼니의 값이 같은
                            // 자리에서 시작한다(#1947).
                            Table(
                              columnWidths: const <int, TableColumnWidth>{
                                0: IntrinsicColumnWidth(),
                                1: FlexColumnWidth(),
                              },
                              defaultVerticalAlignment:
                                  TableCellVerticalAlignment.middle,
                              children: <TableRow>[
                                TableRow(
                                  children: <Widget>[
                                    _InfoLabel(l.dietRecordDate),
                                    Row(
                                      children: <Widget>[
                                        Expanded(
                                          child: Text(
                                            _recordDateLabel(context, _date),
                                            key: const Key('meal-create-date'),
                                            style: _text(
                                              context,
                                              OnCareTypography.strong(
                                                OnCareTypography.bodySmall,
                                              ),
                                              OnCareColors.textPrimary,
                                            ),
                                          ),
                                        ),
                                        AppButton(
                                          key: const Key(
                                            'meal-create-date-change',
                                          ),
                                          label: l.dietRecordDateChange,
                                          onPressed: _busy
                                              ? null
                                              : () => unawaited(_pickDate()),
                                          variant: AppButtonVariant.text,
                                          size: OnCareButtonSize.small,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const TableRow(
                                  children: <Widget>[
                                    SizedBox(height: OnCareSpacing.s12),
                                    SizedBox(height: OnCareSpacing.s12),
                                  ],
                                ),
                                TableRow(
                                  children: <Widget>[
                                    _InfoLabel(l.dietMealKind),
                                    _MealTypeChips(
                                      key: const Key('meal-create-meal'),
                                      selected: _type,
                                      onSelected: (MealType t) =>
                                          setState(() => _type = t),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: OnCareSpacing.cardGap),
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Expanded(child: _FieldLabel(l.dietEatenFood)),
                                AppButton(
                                  key: const Key('meal-create-add-food'),
                                  label: l.dietAddFood,
                                  leadingIcon: AppIcons.add,
                                  variant: AppButtonVariant.text,
                                  size: OnCareButtonSize.small,
                                  onPressed: _busy ? null : _addFood,
                                ),
                              ],
                            ),
                            Text(
                              l.dietManualAddHint,
                              style: _text(
                                context,
                                OnCareTypography.caption,
                                OnCareColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: OnCareSpacing.s12),
                            for (int i = 0; i < _foods.length; i++) ...<Widget>[
                              _foodEditor(i),
                              const SizedBox(height: OnCareSpacing.s8),
                            ],
                            if (_showEmpty) ...<Widget>[
                              Text(
                                l.dietManualAddEmpty,
                                key: const Key('meal-create-empty'),
                                style: _text(
                                  context,
                                  OnCareTypography.caption,
                                  OnCareColors.danger,
                                ),
                              ),
                              const SizedBox(height: OnCareSpacing.s8),
                            ],
                            const AppDivider(),
                            const SizedBox(height: OnCareSpacing.s12),
                            _totalRow(context, l),
                          ],
                        ),
                      ),
                      const SizedBox(height: OnCareSpacing.cardGap),
                      _nutritionCard(context, l),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    side,
                    OnCareSpacing.s8,
                    side,
                    OnCareSpacing.s16,
                  ),
                  child: AppButtonPair(
                    cancelLabel: l.dietCancel,
                    onCancel: _busy ? null : () => Navigator.of(context).pop(),
                    confirmLabel: l.dietSave,
                    onConfirm: _busy ? null : () => unawaited(_save()),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // 저장 요청이 도는 동안에는 뒤로 가지 못하게 한다.
    return PopScope(canPop: !_busy, child: page);
  }
}

class _MealEditSheet extends ConsumerStatefulWidget {
  const _MealEditSheet({required this.meal});
  final DietMeal meal;

  @override
  ConsumerState<_MealEditSheet> createState() => _MealEditSheetState();
}

class _MealEditSheetState extends ConsumerState<_MealEditSheet>
    with _FoodEditing<_MealEditSheet> {
  late MealType _type = widget.meal.mealType;

  /// 이 기록이 놓인 날(#1947). 날짜는 끼니·음식과 따로 저장한다 — 고르는
  /// 즉시 옮기고, 옮기기에 성공했을 때만 바뀐다.
  late DateTime _date = widget.meal.date;

  /// 날짜를 옮기는 중. 두 번 눌러 같은 기록을 두 날로 보내지 않게 막는다.
  bool _movingDate = false;
  bool _busy = false;

  /// 이 화면은 보기로 열리고, 머리의 연필을 눌러야 입력 칸이 된다(#1856).
  /// 대부분은 무엇을 먹었는지 다시 보려고 들어오지 고치려고 들어오지 않는다.
  bool _editing = false;

  /// 취소가 되돌아갈 자리. 저장에 성공하면 여기로 옮겨 온다 — 저장한 뒤에 다시
  /// 고치다 취소했을 때 저장 이전 값으로 되돌아가면 안 된다.
  late MealType _savedType = widget.meal.mealType;
  late List<DietFood> _savedFoods = List<DietFood>.of(widget.meal.items);

  /// 수정 화면 상단의 큰 끼니 사진 높이 (#1125) — 이 화면에 들어온 이유가 대개
  /// "무엇을 먹었는지 다시 보려고" 라, 사진이 주인공이다.
  static const double _photoHeight = 300;

  @override
  void initState() {
    super.initState();
    _loadFoods(widget.meal.items);
    _carbsRecorded = _carbsOf(widget.meal.items) > 0;
  }

  void _beginEdit() => setState(() => _editing = true);

  /// 기록 날짜만 따로 옮긴다(#1947). 연필을 누르지 않아도 되고, 고른 즉시
  /// 그 날의 식단으로 옮긴다.
  ///
  /// 지난 식사 사진을 올린 뒤 날짜만 고치려는 일이 가장 흔하다 — 그것 하나
  /// 때문에 음식·영양 칸이 전부 펼쳐지는 수정 모드를 거치게 하지 않는다.
  /// 끼니·음식 저장과 섞지 않으므로, 수정 중에 날짜를 옮겨도 고치던 값은
  /// 그대로 남고 `취소` 가 날짜를 되돌리지도 않는다.
  Future<void> _pickDate() async {
    final String? id = widget.meal.id;
    if (id == null || _movingDate) return;
    final DateTime today = _todayKst();
    final DateTime? picked = await showAppDatePicker(
      context: context,
      initialDate: _date,
      // 지난 식사는 얼마든지 적을 수 있지만, 앞날의 식사는 아직 먹지 않았다.
      firstDate: DateTime(today.year - 1),
      lastDate: today,
      showClose: false,
    );
    if (picked == null || !mounted) return;
    final DateTime chosen = DateTime(picked.year, picked.month, picked.day);
    if (chosen == _date) return;

    final AppLocalizations l = AppLocalizations.of(context);
    // 페이지를 떠나도 결과는 알린다 — 사라지지 않는 내비게이터 자리를 쓴다.
    final BuildContext toastContext = Navigator.of(context).context;
    final DateTime previous = _date;
    setState(() => _movingDate = true);
    try {
      await ref
          .read(dietRepositoryProvider)
          .updateEntry(id: id, date: wireDate(chosen));
      if (!mounted) return;
      setState(() {
        _date = chosen;
        _movingDate = false;
      });
      // 떠난 날과 도착한 날을 모두 비운다 — 한쪽만 비우면 합계가 두 날에
      // 겹쳐 보이거나 어느 쪽에서도 보이지 않는다.
      ref.invalidate(dietTodayProvider);
      ref.invalidate(dietByDateProvider(previous));
      ref.invalidate(dietByDateProvider(chosen));
      if (!toastContext.mounted) return;
      // 목록으로 돌아가면 이 카드가 원래 날에서 사라진다 — 어디로 갔는지 말한다.
      showAppToast(
        toastContext,
        l.dietRecordDateMoved(_recordDateLabel(toastContext, chosen)),
        type: AppToastType.success,
      );
    } on Object catch (_) {
      if (mounted) setState(() => _movingDate = false);
      if (toastContext.mounted) {
        showAppToast(
          toastContext,
          l.dietRecordDateFailed,
          type: AppToastType.error,
        );
      }
    }
  }

  /// 수정을 접고 처음 값으로 되돌린다. 화면을 나가지는 않는다 — 보기 모드로만
  /// 돌아간다. 컨트롤러는 그 줄이 트리에서 물러난 다음 프레임에 버린다.
  void _cancelEdit() {
    setState(() {
      _editing = false;
      _type = _savedType;
      _loadFoods(_savedFoods);
    });
  }

  Future<void> _save() async {
    final String? id = widget.meal.id;
    final AppLocalizations l = AppLocalizations.of(context);
    final NavigatorState navigator = Navigator.of(context);
    // 페이지를 닫은 뒤에 결과를 알리므로, 사라지지 않는 내비게이터 자리를 쓴다.
    final BuildContext toastContext = navigator.context;
    if (id == null) {
      navigator.pop();
      return;
    }
    final List<FoodItem> foods = _foodPayload();
    // 음식을 모두 지우고 저장했다면 빈 끼니를 남기는 대신 기록을 지울지
    // 묻는다. 지우는 도중이 아니라 저장할 때 묻는 이유는, 한 줄씩 갈아 끼우는
    // 동안 끼어들면 고치던 흐름이 끊기기 때문이다.
    if (foods.isEmpty) {
      await _confirmDelete(emptied: true);
      return;
    }
    // 틀린 칸 아래에 이유를 보이고 요청은 보내지 않는다(#1869).
    if (!_validateFoods()) return;
    // 날짜는 여기서 보내지 않는다 — `날짜 변경` 이 따로 옮긴다(#1947). 끼니·
    // 음식만 고친 저장이 기록을 다른 날로 옮길 일이 없다.
    setState(() => _busy = true);
    try {
      await _saveFoods(id: id, mealType: _type, foods: foods);
      if (!mounted) return;
      ref.invalidate(dietTodayProvider);
      // 기간 뷰(이번 주·전체)는 오늘을 dietByDateProvider 로 읽는다.
      // 같이 비우지 않으면 끼니를 바꿔도 기간 막대만 옛 값에 머문다.
      ref.invalidate(dietByDateProvider(nowKst()));
      // 지난 날의 기록이면 그 날도 비운다 — 오늘만 비우면 그 날 목록이 옛
      // 끼니·칼로리에 머문다.
      ref.invalidate(dietByDateProvider(_date));
      // 화면을 닫지 않고 보기 모드로 돌아간다. 닫아 버리면 목록으로 나가는데
      // 그 카드는 총 칼로리만 말하므로 방금 고친 값이 어떻게 됐는지 확인할
      // 자리가 없다. 취소가 이 화면에 남는 것과도 짝이 맞는다.
      setState(() {
        _busy = false;
        _editing = false;
        _savedType = _type;
        _savedFoods = List<DietFood>.of(_foods);
        // 저장된 끼니가 바뀌었으니 "탄수화물이 적혀 있었나" 의 답도 바뀐다.
        // 서버가 다음 요청에서 보는 값과 같은 값이어야 한다(#1893).
        _carbsRecorded = _carbsOf(_foods) > 0;
      });
      if (!toastContext.mounted) return;
      showAppToast(toastContext, l.dietSaved, type: AppToastType.success);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
      if (toastContext.mounted) {
        showAppToast(toastContext, l.dietSaveFailed, type: AppToastType.error);
      }
    }
  }

  Future<void> _confirmDelete({bool emptied = false}) async {
    final String? id = widget.meal.id;
    if (id == null) {
      Navigator.of(context).pop();
      return;
    }
    final AppLocalizations l = AppLocalizations.of(context);
    final bool ok = await showAppConfirmDialog(
      context: context,
      title: l.dietDeleteTitle,
      message: emptied ? l.dietDeleteWhenEmpty : l.dietDeleteConfirm,
      confirmLabel: l.dietDelete,
      cancelLabel: l.dietCancel,
      destructive: true,
    );
    if (!ok || !mounted) return;

    final NavigatorState navigator = Navigator.of(context);
    final BuildContext toastContext = navigator.context;
    setState(() => _busy = true);
    try {
      await ref.read(dietRepositoryProvider).deleteEntry(id);
      // Page dismissed mid-delete → don't pop the page below.
      if (!mounted) return;
      // 지운 끼니의 적립은 회수된다 — MY 잔액을 다시 읽는다(#1786).
      refreshPointsBalance(ref);
      ref.invalidate(dietTodayProvider);
      // 기간 뷰(이번 주·전체)는 오늘을 dietByDateProvider 로 읽는다.
      // 같이 비우지 않으면 끼니를 바꿔도 기간 막대만 옛 값에 머문다.
      ref.invalidate(dietByDateProvider(nowKst()));
      navigator.pop();
      if (!toastContext.mounted) return;
      showAppToast(toastContext, l.dietDeleted, type: AppToastType.success);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
      if (toastContext.mounted) {
        showAppToast(
          toastContext,
          l.dietDeleteFailed,
          type: AppToastType.error,
        );
      }
    }
  }

  MealPhotoView get _photo => MealPhotoView(
    photoUrl: widget.meal.photoUrl,
    photoAsset: widget.meal.photoAsset,
    emoji: widget.meal.emoji,
    width: double.infinity,
    height: _photoHeight,
    large: true,
  );

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final OnCareTokens tokens = context.oncare;
    final double side = tokens.density.pagePadding;
    final Widget page = Scaffold(
      key: const Key('mealDetailPage'),
      backgroundColor: OnCareColors.surfaceCard,
      // 뒤로는 앱바 한 곳, 저장은 하단 한 곳이다 — 머리의 글자 저장은 없다(#1700).
      // 연필은 앱바가 아니라 `먹은 음식` 카드 머리에 둔다 — 고칠 것 바로 옆에
      // 있어야 무엇을 여는 버튼인지 알아본다.
      // 제목은 저장된 끼니를 따른다 — 열 때의 값에 묶어 두면 끼니를 고쳐
      // 저장한 뒤에도 옛 이름이 머리에 남는다.
      appBar: AppTopBar(title: l.dietMealSheetTitle(mealBadge(l, _savedType))),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: OnCareLayout.mobileContentMaxWidth,
            ),
            child: Column(
              children: <Widget>[
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      side,
                      OnCareSpacing.s8,
                      side,
                      OnCareSpacing.sectionGap,
                    ),
                    children: <Widget>[
                      // 무엇을 고치는 끼니인지 사진으로 먼저 알아본다. 사진이 없는
                      // 끼니는 큰 이모지 자리를 만들지 않는다. (#1053)
                      if (_photo.hasPhoto) ...<Widget>[
                        _photo,
                        const SizedBox(height: OnCareSpacing.cardGap),
                      ],
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            // 연필은 첫 카드에 둔다 — 수정 모드는 기록 날짜·
                            // 끼니·음식·영양을 한꺼번에 바꾸므로(#1947), 음식
                            // 카드에 붙이면 음식만 고치는 것으로 읽힌다.
                            Row(
                              children: <Widget>[
                                Expanded(child: _FieldLabel(l.dietMealInfo)),
                                if (!_editing)
                                  AppIconButton(
                                    key: const Key('mealDetailEditButton'),
                                    icon: AppIcons.edit,
                                    tooltip: l.dietEditMeal,
                                    size: AppIconButtonSize.small,
                                    onPressed: _beginEdit,
                                  ),
                              ],
                            ),
                            const SizedBox(height: OnCareSpacing.s12),
                            // "이 기록이 언제·어느 끼니인가" 를 한자리에서
                            // 읽는다(#1947). 날짜와 끼니를 나란한 두 칸으로 두고
                            // 값이 같은 자리에서 시작하도록 라벨 폭을 맞춘다 —
                            // 라벨 폭을 숫자로 박지 않아 큰 글자에서도 넘치지
                            // 않는다.
                            Table(
                              columnWidths: const <int, TableColumnWidth>{
                                0: IntrinsicColumnWidth(),
                                1: FlexColumnWidth(),
                              },
                              defaultVerticalAlignment:
                                  TableCellVerticalAlignment.middle,
                              children: <TableRow>[
                                TableRow(
                                  children: <Widget>[
                                    _InfoLabel(l.dietRecordDate),
                                    Row(
                                      children: <Widget>[
                                        Expanded(
                                          child: Text(
                                            _recordDateLabel(context, _date),
                                            key: const Key('meal-detail-date'),
                                            style: _text(
                                              context,
                                              OnCareTypography.strong(
                                                OnCareTypography.bodySmall,
                                              ),
                                              OnCareColors.textPrimary,
                                            ),
                                          ),
                                        ),
                                        // 날짜는 연필 없이도 따로 옮긴다 —
                                        // 보기·수정 어느 쪽에서든 같은 자리다.
                                        // 옮기는 동안 버튼이 spinner 로 바뀌어도
                                        // 줄 높이가 튀지 않게 자리를 잡는다.
                                        SizedBox(
                                          height: tokens.density.buttonHeight(
                                            OnCareButtonSize.small,
                                          ),
                                          child: Center(
                                            child: _movingDate
                                                ? const AppLoading.inline()
                                                : AppButton(
                                                    key: const Key(
                                                      'meal-detail-date-change',
                                                    ),
                                                    label:
                                                        l.dietRecordDateChange,
                                                    onPressed: () =>
                                                        unawaited(_pickDate()),
                                                    variant:
                                                        AppButtonVariant.text,
                                                    size:
                                                        OnCareButtonSize.small,
                                                  ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const TableRow(
                                  children: <Widget>[
                                    SizedBox(height: OnCareSpacing.s12),
                                    SizedBox(height: OnCareSpacing.s12),
                                  ],
                                ),
                                TableRow(
                                  children: <Widget>[
                                    _InfoLabel(l.dietMealKind),
                                    // 보기 모드에서는 고른 끼니 하나만 보인다.
                                    // 고를 수 없는 칩 다섯을 늘어놓으면 누를 수
                                    // 있는 것처럼 읽힌다.
                                    if (_editing)
                                      _MealTypeChips(
                                        key: const Key('meal-detail-meal'),
                                        selected: _type,
                                        onSelected: (MealType t) =>
                                            setState(() => _type = t),
                                      )
                                    else
                                      Align(
                                        key: const Key('meal-detail-meal'),
                                        alignment: Alignment.centerLeft,
                                        child: AppTag(
                                          label: mealBadge(l, _type),
                                          tone: AppTagTone.brand,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: OnCareSpacing.cardGap),
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Expanded(child: _FieldLabel(l.dietEatenFood)),
                                if (_editing)
                                  AppButton(
                                    label: l.dietAddFood,
                                    leadingIcon: AppIcons.add,
                                    variant: AppButtonVariant.text,
                                    size: OnCareButtonSize.small,
                                    onPressed: _addFood,
                                  ),
                              ],
                            ),
                            if (_editing)
                              Text(
                                l.dietEditFoodHint,
                                style: _text(
                                  context,
                                  OnCareTypography.caption,
                                  OnCareColors.textSecondary,
                                ),
                              ),
                            const SizedBox(height: OnCareSpacing.s12),
                            for (int i = 0; i < _foods.length; i++) ...<Widget>[
                              if (_editing)
                                _foodEditor(i)
                              else
                                _FoodViewRow(index: i + 1, food: _foods[i]),
                              const SizedBox(height: OnCareSpacing.s8),
                            ],
                            const AppDivider(),
                            const SizedBox(height: OnCareSpacing.s12),
                            _totalRow(context, l),
                          ],
                        ),
                      ),
                      const SizedBox(height: OnCareSpacing.cardGap),
                      _nutritionCard(context, l),
                      const SizedBox(height: OnCareSpacing.s16),
                      // 화면 안에서 삭제 확인창을 여는 버튼은 빨간 글자다(#1690).
                      Center(
                        child: AppButton(
                          label: l.dietDeleteMeal,
                          leadingIcon: AppIcons.delete,
                          variant: AppButtonVariant.destructiveText,
                          onPressed: _busy ? null : _confirmDelete,
                        ),
                      ),
                    ],
                  ),
                ),
                // 취소·저장은 수정 중일 때만 있다. 보기로 들어왔을 뿐인데
                // 저장 버튼이 서 있으면 무엇이 바뀌었는지 묻게 된다.
                if (_editing)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      side,
                      OnCareSpacing.s8,
                      side,
                      OnCareSpacing.s16,
                    ),
                    child: AppButtonPair(
                      cancelLabel: l.dietCancel,
                      onCancel: _busy ? null : _cancelEdit,
                      confirmLabel: l.dietSave,
                      onConfirm: _busy ? null : _save,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    // Block back/drag dismiss while a save/delete request is in flight.
    return PopScope(canPop: !_busy, child: page);
  }
}

/// 끼니를 고르는 칩 다섯. 식단 상세와 분석 완료 시트의 수정 모드가 함께
/// 쓴다(#2097).
class _MealTypeChips extends StatelessWidget {
  const _MealTypeChips({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  /// 끼니 칩의 두 묶음 — 식사 셋과 그 사이·뒤에 먹는 둘.
  ///
  /// 칩 다섯을 `Wrap` 하나에 두면 폰 폭에서 `야식` 하나만 아랫줄로 떨어져 따로
  /// 떨어진 선택지처럼 읽힌다(#2080). 묶음 단위로 줄을 바꿔, 한 줄에 다 들어가지
  /// 않으면 `간식·야식` 이 함께 내려간다.
  static const List<List<MealType>> _groups = <List<MealType>>[
    <MealType>[MealType.breakfast, MealType.lunch, MealType.dinner],
    <MealType>[MealType.snack, MealType.lateNight],
  ];

  final MealType selected;
  final ValueChanged<MealType> onSelected;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    // 바깥 Wrap 은 묶음을, 안쪽 Wrap 은 칩을 늘어놓는다. 안쪽 Wrap 은 제 칩
    // 폭만큼만 차지하므로 한 줄에 다 들어가면 그대로 한 줄이고, 넘치면 두 번째
    // 묶음이 통째로 내려간다. 묶음 하나도 안 들어갈 만큼 좁으면 그 안에서만
    // 줄을 바꾼다.
    return Wrap(
      spacing: OnCareSpacing.s8,
      runSpacing: OnCareSpacing.s8,
      children: <Widget>[
        for (final List<MealType> group in _groups)
          Wrap(
            spacing: OnCareSpacing.s8,
            runSpacing: OnCareSpacing.s8,
            children: <Widget>[
              for (final MealType t in group)
                AppChoiceChip(
                  label: mealBadge(l, t),
                  selected: selected == t,
                  onSelected: (_) => onSelected(t),
                ),
            ],
          ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: _text(
      context,
      OnCareTypography.titleSmall,
      OnCareColors.textPrimary,
    ),
  );
}

/// `식사 정보` 카드 안의 한 줄 라벨(`기록 날짜`·`끼니`). 값과 사이를 띄운다.
/// 분석 완료 시트의 `기록 날짜` 라벨과 같은 모양이다.
class _InfoLabel extends StatelessWidget {
  const _InfoLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(end: OnCareSpacing.s12),
    child: Text(
      text,
      style: _text(context, OnCareTypography.label, OnCareColors.textSecondary),
    ),
  );
}

/// 섭취량을 고칠 때 비례 환산이 출발하는 자리 — **그 양일 때의 영양 한 벌**.
///
/// 화면에 적힌 값에서 곱해 나가지 않는 이유가 여기 있다. `300` 은 한 번에
/// 들어오지 않고 `3` → `30` → `300` 으로 들어오는데, 그때마다 칸의 값을
/// 곱하면 칼로리·나트륨의 정수 반올림이 단계마다 쌓여 같은 300g 인데
/// 555kcal 이 아니라 600kcal 이 남는다. 곱셈은 늘 이 원본 한 벌에서 한 번만
/// 한다. (#1876)
class _FoodBasis {
  const _FoodBasis({
    required this.amountG,
    required this.kcal,
    required this.carbsG,
    required this.sugarG,
    required this.proteinG,
    required this.fatG,
    required this.sodiumMg,
  });

  /// 이 한 벌이 잰 양. 늘 0 보다 크다 — 0 은 나눌 수도, 기준이 될 수도 없다.
  final double amountG;
  final int kcal;
  final double carbsG;
  final double sugarG;
  final double proteinG;
  final double fatG;
  final int sodiumMg;
}

/// 탄단지를 고칠 때 열량이 출발하는 자리 — **서로 맞는 열량·탄·단·지 한 벌.**
/// (#2106)
///
/// 섭취량의 기준([_FoodBasis])과 따로 둔다. 그쪽은 영양 칸을 고칠 때마다 지금
/// 값으로 다시 서는데, 열량의 기준까지 그렇게 하면 `128` 을 치는 동안 `1` 다음
/// 부터는 기준에 탄수화물이 생겨 탄단지 없던 기록의 "채우기" 가 "늘리기" 로
/// 읽히고, 정수 반올림도 글자마다 쌓인다. 그래서 이 한 벌은 앱이 서로 맞는 값을
/// 한꺼번에 적은 때에만 다시 선다 — 편집을 열 때, 섭취량 비례 환산 직후, 공공 DB
/// 값으로 채운 직후.
class _EnergyBasis {
  const _EnergyBasis({
    required this.kcal,
    required this.carbsG,
    required this.proteinG,
    required this.fatG,
  });

  final int kcal;
  final double carbsG;
  final double proteinG;
  final double fatG;

  /// 탄단지 없이 열량만 있는 한 벌 — 인식기가 탄단지를 주지 않은 옛 기록이다
  /// (#1877). 여기에 탄단지를 적는 것은 이미 열량에 든 성분을 **채워 넣는** 것이지
  /// 늘리는 것이 아니다. 반영하면 두 번 센다(700kcal 짜장면에 탄수화물 128g 을
  /// 채우면 1,212kcal).
  bool get onlyKcal => kcal > 0 && carbsG == 0 && proteinG == 0 && fatG == 0;

  /// 탄단지가 이 값들로 바뀌었을 때의 열량 — 바뀐 만큼만 더하고 뺀다. 0 아래로
  /// 내려가지 않는다.
  int kcalFor({
    required double carbsG,
    required double proteinG,
    required double fatG,
  }) {
    final double next =
        kcal +
        4 * (carbsG - this.carbsG) +
        4 * (proteinG - this.proteinG) +
        9 * (fatG - this.fatG);
    return next <= 0 ? 0 : next.round();
  }
}

/// 이름 칸 아래에 서는 한 줄 안내(#2107). 제안(`값 채우기`)과는 다르다 — 이미
/// 일어난 일을 말한다.
sealed class _NameNotice {
  const _NameNotice();
}

/// 같은 음식의 공공 DB 값으로 바꿨다. 무엇으로 바꿨는지 말하고 되돌릴 수 있게
/// 한다 — 회원이 누르지 않았는데 값이 바뀌었다.
final class _FilledFromDb extends _NameNotice {
  const _FilledFromDb(this.found, this.before);

  final FoodNutritionSuggestion found;

  /// 바꾸기 전의 칸. `되돌리기` 가 여기로 돌아간다.
  final _FoodSnapshot before;
}

/// 공공 DB 에 없는 이름이다. 값은 옛 음식의 것 그대로라 확인해 달라고 말한다.
final class _NotInDb extends _NameNotice {
  const _NotInDb();
}

/// 한 음식 줄의 칸과 기준을 통째로 적어 둔 것 — `되돌리기` 가 돌아갈 자리(#2107).
class _FoodSnapshot {
  _FoodSnapshot.of(_FoodEditors e)
    : amount = e.amount.text,
      kcal = e.kcal.text,
      carbs = e.carbs.text,
      sugar = e.sugar.text,
      protein = e.protein.text,
      fat = e.fat.text,
      sodium = e.sodium.text,
      basis = e.basis,
      energy = e.energy,
      kcalPinned = e.kcalPinned,
      fillOnly = e.fillOnly;

  final String amount;
  final String kcal;
  final String carbs;
  final String sugar;
  final String protein;
  final String fat;
  final String sodium;
  final _FoodBasis? basis;
  final _EnergyBasis energy;
  final bool kcalPinned;
  final bool fillOnly;

  void restoreTo(_FoodEditors e) {
    e.amount.text = amount;
    e.kcal.text = kcal;
    e.carbs.text = carbs;
    e.sugar.text = sugar;
    e.protein.text = protein;
    e.fat.text = fat;
    e.sodium.text = sodium;
    e
      ..basis = basis
      ..energy = energy
      ..kcalPinned = kcalPinned
      ..fillOnly = fillOnly;
  }
}

/// 음식 한 줄이 쓰는 입력 컨트롤러 한 벌. [_MealEditSheetState] 가 목록으로
/// 들고 다닌다.
class _FoodEditors {
  _FoodEditors({
    required this.name,
    required this.amount,
    required this.kcal,
    required this.carbs,
    required this.sugar,
    required this.protein,
    required this.fat,
    required this.sodium,
    required this.source,
    required this.valuesName,
  });

  /// 0 은 빈 칸으로 연다 — 새로 추가한 줄에 `0` 이 적혀 있으면 지우고 쓰는
  /// 일이 한 번 더 늘어난다. 섭취량은 **모르는 것**이라 더욱 그렇다(null).
  factory _FoodEditors.of(DietFood food) {
    final _FoodEditors editors = _FoodEditors(
      name: TextEditingController(text: food.name),
      amount: _gramField(food.amountG ?? 0),
      kcal: _intField(food.kcal),
      carbs: _gramField(food.carbsG),
      sugar: _gramField(food.sugarG),
      protein: _gramField(food.proteinG),
      fat: _gramField(food.fatG),
      sodium: _intField(food.sodiumMg),
      source: food.source,
      valuesName: food.name.trim(),
    );
    // 열량 반영의 기준은 **칸에 보이는 값**으로 세운다(#2106). 소수 한 자리로
    // 반올림해 적은 칸과 원본이 다르면, 손대지 않은 칸이 Δ 를 만들어 열량이
    // 저절로 1kcal 씩 흔들린다.
    editors
      ..energy = editors.readEnergy()
      ..fillOnly = editors.energy.onlyKcal;
    // 양을 아는 음식은 열자마자 기준이 선다. 모르는 음식은 회원이 처음 적어
    // 넣는 양이 기준이 된다 — 그때까지는 비례 환산할 근거가 없다.
    final double? amountG = food.amountG;
    if (amountG != null && amountG > 0) {
      editors.basis = _FoodBasis(
        amountG: amountG,
        kcal: food.kcal,
        carbsG: food.carbsG,
        sugarG: food.sugarG,
        proteinG: food.proteinG,
        fatG: food.fatG,
        sodiumMg: food.sodiumMg,
      );
    }
    return editors;
  }

  static String intText(int v) => v == 0 ? '' : '$v';

  static String gramText(double v) => v == 0 ? '' : _gramsFieldText(v);

  static TextEditingController _intField(int v) =>
      TextEditingController(text: intText(v));

  static TextEditingController _gramField(double v) =>
      TextEditingController(text: gramText(v));

  final TextEditingController name;

  /// 이름 칸을 **벗어났을 때** 공공 DB 를 찾기 위한 것(#1896). 타이핑 중간값
  /// (`짜`, `짜장`)으로 부르면 요청만 늘고 쓸모없는 제안이 깜빡인다 — 운동의
  /// 칼로리 미리보기가 같은 방식이다(#1312).
  final FocusNode nameFocus = FocusNode();

  /// 지금 이름으로 찾은 공공 DB 값. 없으면 제안할 것이 없다는 뜻이다.
  FoodNutritionSuggestion? suggestion;

  /// 마지막으로 조회를 건 이름. 같은 이름을 두 번 묻지 않고, 늦게 도착한
  /// 응답이 그 사이 바뀐 이름을 덮지 않게 막는 표식이기도 하다.
  String? lookedUpName;

  /// 먹은 양(g). 이 칸 하나가 아래 여섯 값을 함께 움직인다.
  final TextEditingController amount;
  final TextEditingController kcal;
  final TextEditingController carbs;
  final TextEditingController sugar;
  final TextEditingController protein;
  final TextEditingController fat;
  final TextEditingController sodium;

  /// 지금 적힌 영양이 **어느 양에서 나온 값인가.** 섭취량을 모르는 음식은
  /// null 이고, 회원이 양을 적어 넣거나 영양 칸을 직접 고칠 때 다시 선다.
  _FoodBasis? basis;

  /// 지금 칸의 영양이 어디서 왔나(#2105). 저장할 때 그대로 싣는다.
  FoodSource source;

  /// 지금 칸의 영양이 **어느 이름의 값인가**(#2107). 이름을 이것과 다르게 고치고
  /// 칸을 벗어나야 "다른 음식이 됐다" 로 본다 — 칸만 드나든 것은 이름 변경이
  /// 아니다.
  String valuesName;

  /// 탄단지를 고칠 때 열량이 출발하는 자리(#2106).
  late _EnergyBasis energy;

  /// 회원이 이 음식의 열량을 직접 적었다 — 이번 편집 동안 열량을 탄단지에
  /// 따라 움직이지 않는다(#2106). 라벨 값을 옮겨 적는 중이면 칸을 어느 순서로
  /// 적든 라벨 열량이 남아야 한다. 저장한 기록은 이것을 기억하지 않는다.
  bool kcalPinned = false;

  /// 편집을 열 때 탄단지 없이 열량만 있던 음식이다([_EnergyBasis.onlyKcal]) —
  /// 이번 편집 동안 탄단지를 적어도 열량을 움직이지 않는다. 공공 DB 값으로
  /// 채우면 풀린다.
  late bool fillOnly;

  /// 영양 칸을 손으로 고친 횟수. 이름 조회가 도는 사이 회원이 값을 고쳤는지
  /// 가린다(#2107) — 그랬으면 응답이 그 값을 덮지 않는다.
  int edits = 0;

  /// 이름 칸 아래의 안내(#2107). 없으면 null.
  _NameNotice? notice;

  /// 지금 칸에 적힌 열량·탄·단·지 한 벌(#2106).
  _EnergyBasis readEnergy() => _EnergyBasis(
    kcal: int.tryParse(kcal.text.trim()) ?? 0,
    carbsG: double.tryParse(carbs.text.trim()) ?? 0,
    proteinG: double.tryParse(protein.text.trim()) ?? 0,
    fatG: double.tryParse(fat.text.trim()) ?? 0,
  );

  void dispose() {
    nameFocus.dispose();
    for (final TextEditingController c in <TextEditingController>[
      name,
      amount,
      kcal,
      carbs,
      sugar,
      protein,
      fat,
      sodium,
    ]) {
      c.dispose();
    }
  }
}

/// 먹은 음식 한 줄 — 보기 모드의 읽기 전용 표시.
///
/// 이름 **바로 옆**에 내용량이 온다. 오른쪽 칼로리는 그 양을 재고 나온 값이라,
/// 기준이 보이지 않으면 230kcal 이 한 공기인지 반 공기인지 알 수 없다 —
/// 수정 모드를 열어야만 기준이 드러나는 것은 순서가 뒤집힌 것이다(#1964).
/// 칼로리 앞이 아니라 이름 옆인 까닭은, 양은 "무엇을 얼마나" 의 일부라 음식에
/// 붙고 칼로리는 그 결과라서다. 식단 탭 끼니 카드도 같은 자리에 적는다.
/// 양을 모르는 음식과 이 필드 이전 기록은 null 이라 아무것도 적지 않는다:
/// `0g` 은 안 먹었다는 말이 된다.
class _FoodViewRow extends StatelessWidget {
  const _FoodViewRow({required this.index, required this.food});

  final int index;
  final DietFood food;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final double? amount = food.amountG;
    return AppTile(
      tone: AppTileTone.none,
      child: Row(
        children: <Widget>[
          AppTag(label: '$index', tone: AppTagTone.brand),
          const SizedBox(width: OnCareSpacing.s8),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Flexible(
                  child: Text(
                    food.name.trim().isEmpty ? l.dietNewFood : food.name,
                    style: _text(
                      context,
                      OnCareTypography.strong(OnCareTypography.body),
                      OnCareColors.textPrimary,
                    ),
                  ),
                ),
                if (amount != null && amount > 0) ...<Widget>[
                  const SizedBox(width: OnCareSpacing.s4),
                  Text(
                    '${_gramsText(amount)}${l.dietUnitG}',
                    key: ValueKey<String>('diet-food-view-amount-$index'),
                    style: OnCareTypography.numeric(
                      _text(
                        context,
                        OnCareTypography.caption,
                        OnCareColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: OnCareSpacing.s8),
          Text(
            '${food.kcal}',
            style: OnCareTypography.numeric(
              _text(
                context,
                OnCareTypography.strong(OnCareTypography.body),
                OnCareColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: OnCareSpacing.s4),
          Text(
            l.unitKcal,
            style: _text(
              context,
              OnCareTypography.caption,
              OnCareColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 수정 모드의 음식 한 덩이 — 이름·섭취량과 그 음식의 영양을 한자리에서
/// 고친다(#1856, #1876).
///
/// 끼니 단위 탄단지는 음식별 값의 합계라 영양 정보 카드에서는 고칠 자리가
/// 없다. 값이 실제로 사는 곳이 여기다.
///
/// 맨 위는 **내용량**이다. 아래 여섯 값이 전부 그 양을 재고 나온 값이라,
/// 양을 고치면 함께 움직인다. 그 아래 개별 칸을 그대로 남겨 둔 것은 분석이
/// 틀렸을 때 손으로 바로잡을 자리가 필요하기 때문이다 — 양은 맞는데 값만
/// 틀린 경우가 있다.
class _FoodEditBlock extends StatelessWidget {
  const _FoodEditBlock({
    required this.index,
    required this.editors,
    required this.onNameChanged,
    required this.onChanged,
    required this.onAmountChanged,
    required this.onKcalChanged,
    required this.onMacroChanged,
    required this.onDelete,
    this.sugarError,
    this.suggestion,
    required this.onApplySuggestion,
    required this.onUndoFill,
  });

  /// 숫자 칸 폭. 못 박아 두어야 라벨 칸이 자릿수에 따라 늘었다 줄었다 하지
  /// 않는다.
  static const double _valueWidth = 88;

  final int index;
  final _FoodEditors editors;
  final VoidCallback onNameChanged;

  /// 당류·나트륨 칸. 열량에 들어가지 않는 값이다.
  final VoidCallback onChanged;

  /// 내용량 칸 전용. 나머지 칸과 갈래가 다르다 — 이 칸은 자기 값만 바꾸는
  /// 것이 아니라 아래 여섯 값을 함께 다시 적는다.
  final VoidCallback onAmountChanged;

  /// 열량 칸. 여기에 적으면 그 음식의 열량은 탄단지를 따라가지 않는다(#2106).
  final VoidCallback onKcalChanged;

  /// 탄수화물·단백질·지방 칸. 열량이 바뀐 만큼 따라온다(#2106).
  final VoidCallback onMacroChanged;
  final VoidCallback onDelete;

  /// 당류 칸 아래에 보일 오류 문구. null 이면 아무것도 그리지 않는다(#1869).
  final String? sugarError;

  /// 이 이름으로 공공 DB 에서 찾은 값. **적용하면 달라지는 것이 있을 때만**
  /// 넘어온다 — 이미 그 값이면 제안할 것이 없다. null 이면 줄을 그리지 않는다.
  final FoodNutritionSuggestion? suggestion;
  final VoidCallback onApplySuggestion;

  /// "DB 값으로 바꿨어요" 옆의 `되돌리기`(#2107).
  final VoidCallback onUndoFill;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final TextStyle caption = _text(
      context,
      OnCareTypography.caption,
      OnCareColors.textSecondary,
    );
    return AppTile(
      tone: AppTileTone.neutral,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              AppTag(label: '$index', tone: AppTagTone.brand),
              const SizedBox(width: OnCareSpacing.s8),
              Expanded(
                child: AppTextField(
                  key: ValueKey<String>('diet-food-name-$index'),
                  controller: editors.name,
                  // 이 칸을 벗어날 때 공공 DB 를 찾는다(#1896). 타이핑 중간값으로
                  // 부르지 않으려고 `onChanged` 가 아니라 포커스를 본다.
                  focusNode: editors.nameFocus,
                  hint: l.dietNewFood,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => onNameChanged(),
                ),
              ),
              AppIconButton(
                key: ValueKey<String>('diet-food-remove-$index'),
                icon: AppIcons.delete,
                tooltip: l.a11yRemoveFood,
                size: AppIconButtonSize.small,
                color: OnCareColors.textTertiary,
                onPressed: onDelete,
              ),
            ],
          ),
          // 이미 일어난 일(바꿨다·없다)이 먼저다. 제안과 함께 설 일은 없다 —
          // 바꾼 직후에는 제안이 거둬지고, 되돌리면 안내가 거둬진다.
          if (editors.notice case final _NameNotice notice)
            Padding(
              padding: const EdgeInsets.only(top: OnCareSpacing.s8),
              child: switch (notice) {
                _FilledFromDb(:final FoodNutritionSuggestion found) => Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        l.dietFoodFilledFromDb(found.matchedName),
                        key: ValueKey<String>('diet-food-db-filled-$index'),
                        style: caption,
                      ),
                    ),
                    AppButton(
                      key: ValueKey<String>('diet-food-db-undo-$index'),
                      label: l.dietUndoFill,
                      variant: AppButtonVariant.text,
                      size: OnCareButtonSize.small,
                      onPressed: onUndoFill,
                    ),
                  ],
                ),
                _NotInDb() => Text(
                  l.dietFoodNotInDb,
                  key: ValueKey<String>('diet-food-not-in-db-$index'),
                  style: caption,
                ),
              },
            ),
          if (suggestion case final FoodNutritionSuggestion found)
            Padding(
              padding: const EdgeInsets.only(top: OnCareSpacing.s8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      l.dietFoodDbMatch(found.matchedName),
                      key: ValueKey<String>('diet-food-db-match-$index'),
                      style: caption,
                    ),
                  ),
                  AppButton(
                    key: ValueKey<String>('diet-food-db-apply-$index'),
                    label: l.dietFillFromDb,
                    variant: AppButtonVariant.text,
                    size: OnCareButtonSize.small,
                    onPressed: onApplySuggestion,
                  ),
                ],
              ),
            ),
          _field(
            context,
            fieldKey: 'diet-food-amount-$index',
            label: l.dietAmount,
            unit: l.dietUnitG,
            controller: editors.amount,
            // 다른 칸과 달리 `0` 을 흐린 글씨로 세워 두지 않는다. 양은 모를 수
            // 있는 값이고, 빈 칸에 `0` 이 비쳐 있으면 "0g 먹었다" 로 읽힌다 —
            // 모른다와 안 먹었다는 다른 말이다.
            hint: '',
            onChanged: onAmountChanged,
          ),
          // 내용량과 나머지를 선으로 가른다 — 위의 한 칸이 아래 여섯 칸을
          // 움직인다는 관계가 보이지 않으면, 값이 저절로 바뀌는 것처럼 읽힌다.
          const Padding(
            padding: EdgeInsets.only(top: OnCareSpacing.s8),
            child: AppDivider(),
          ),
          _field(
            context,
            fieldKey: 'diet-food-kcal-$index',
            label: l.dietCalories,
            unit: l.unitKcal,
            controller: editors.kcal,
            decimal: false,
            onChanged: onKcalChanged,
          ),
          _field(
            context,
            fieldKey: 'diet-food-carbs-$index',
            label: l.homeMacroCarbs,
            unit: l.dietUnitG,
            controller: editors.carbs,
            onChanged: onMacroChanged,
          ),
          _field(
            context,
            fieldKey: 'diet-food-sugar-$index',
            label: l.dietSugar,
            unit: l.dietUnitG,
            controller: editors.sugar,
            sub: true,
            error: sugarError,
          ),
          _field(
            context,
            fieldKey: 'diet-food-protein-$index',
            label: l.homeMacroProtein,
            unit: l.dietUnitG,
            controller: editors.protein,
            onChanged: onMacroChanged,
          ),
          _field(
            context,
            fieldKey: 'diet-food-fat-$index',
            label: l.homeMacroFat,
            unit: l.dietUnitG,
            controller: editors.fat,
            onChanged: onMacroChanged,
          ),
          _field(
            context,
            fieldKey: 'diet-food-sodium-$index',
            label: l.dietSodium,
            unit: l.dietUnitMg,
            controller: editors.sodium,
            decimal: false,
          ),
        ],
      ),
    );
  }

  Widget _field(
    BuildContext context, {
    required String fieldKey,
    required String label,
    required String unit,
    required TextEditingController controller,
    bool decimal = true,
    bool sub = false,
    String hint = '0',
    VoidCallback? onChanged,
    String? error,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: OnCareSpacing.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (sub) ...<Widget>[
                const SizedBox(width: OnCareSpacing.s16),
                Text(
                  '↳',
                  style: _text(
                    context,
                    OnCareTypography.bodySmall,
                    OnCareColors.textTertiary,
                  ),
                ),
                const SizedBox(width: OnCareSpacing.s4),
              ],
              Expanded(
                child: Text(
                  label,
                  style: _text(
                    context,
                    OnCareTypography.bodySmall,
                    OnCareColors.textSecondary,
                  ),
                ),
              ),
              SizedBox(
                width: _valueWidth,
                child: AppTextField(
                  key: ValueKey<String>(fieldKey),
                  controller: controller,
                  hint: hint,
                  keyboardType: TextInputType.numberWithOptions(
                    decimal: decimal,
                  ),
                  // 숫자만 받는다 — 빈 칸은 0 으로 읽힌다.
                  inputFormatters: <TextInputFormatter>[
                    if (decimal)
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                    else
                      FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  textAlign: TextAlign.end,
                  onChanged: (_) => (onChanged ?? this.onChanged)(),
                ),
              ),
              const SizedBox(width: OnCareSpacing.s4),
              Text(
                unit,
                style: _text(
                  context,
                  OnCareTypography.caption,
                  OnCareColors.textSecondary,
                ),
              ),
            ],
          ),
          // 값 칸이 좁아(88) 그 안에 문구를 넣으면 한 자씩 끊겨 읽힌다.
          // 줄 아래에 한 줄로 편다 — 색과 크기는 입력 칸 오류와 같다.
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: OnCareSpacing.s4),
              child: Text(
                error,
                key: ValueKey<String>('$fieldKey-error'),
                textAlign: TextAlign.end,
                style: _text(
                  context,
                  OnCareTypography.caption,
                  OnCareColors.danger,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NutrientRow extends StatelessWidget {
  const _NutrientRow({
    required this.label,
    required this.value,
    required this.unit,
    this.sub = false,
  });

  /// 한 칸 들여쓰는 폭. 하위 항목이 상위 항목 라벨보다 안쪽에서 시작해야
  /// `당류` 가 `탄수화물` 에 딸린 값으로 읽힌다.
  static const double _subIndent = 16;

  final String label;
  final String value;
  final String unit;

  /// 바로 위 항목의 하위 값인가 — 들여쓰고 앞에 `↳` 를 붙인다.
  final bool sub;

  @override
  Widget build(BuildContext context) {
    return AppTile(
      tone: AppTileTone.none,
      child: Row(
        children: <Widget>[
          if (sub) ...<Widget>[
            const SizedBox(width: _subIndent),
            Text(
              '↳',
              style: _text(
                context,
                OnCareTypography.bodySmall,
                OnCareColors.textTertiary,
              ),
            ),
            const SizedBox(width: OnCareSpacing.s4),
          ],
          Expanded(
            child: Text(
              label,
              style: _text(
                context,
                OnCareTypography.strong(OnCareTypography.bodySmall),
                OnCareColors.textPrimary,
              ),
            ),
          ),
          Text(
            value,
            style: OnCareTypography.numeric(
              _text(
                context,
                OnCareTypography.titleSmall,
                OnCareColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: OnCareSpacing.s4),
          Text(
            unit,
            style: _text(
              context,
              OnCareTypography.bodySmall,
              OnCareColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
