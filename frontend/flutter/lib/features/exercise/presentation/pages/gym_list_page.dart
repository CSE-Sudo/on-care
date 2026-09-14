import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:oncare/app/router/routes.dart';
import 'package:oncare/design_system/figma/figma_kit.dart';
import 'package:oncare/design_system/tokens/colors.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_request.dart';
import 'package:oncare/features/exercise/domain/entities/gym.dart';
import 'package:oncare/features/exercise/domain/entities/trainer.dart';
import 'package:oncare/features/exercise/presentation/controllers/consultation_request_controller.dart';
import 'package:oncare/features/exercise/presentation/controllers/exercise_controller.dart';
import 'package:oncare/features/exercise/presentation/widgets/gym_trainer_line.dart';
import 'package:oncare/features/exercise/presentation/widgets/kakao_map/kakao_map_view.dart';
import 'package:oncare/gen/l10n/app_localizations.dart';
import 'package:oncare/shared/widgets/member_tab_header.dart';

enum _GymSort { recommended, distance, rating }

/// 검색 결과 패널이 차지하는 화면 비율. (#865)
///
/// 최소값은 **완전히 접히지 않는 높이**다 — 결과가 있다는 사실과 첫 카드가 언제나
/// 보여야 한다. 최대값은 검색창과 시스템 영역을 침범하지 않는 선이고, 중간값은
/// 지도를 조금 남긴 채 여러 곳을 견주는 자리다.
class GymListPage extends ConsumerWidget {
  const GymListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: FigmaColors.statBg,
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: Colors.white,
        scrolledUnderElevation: 0,
        title: Text(
          l.exFindGym,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: FigmaColors.ink,
          ),
        ),
      ),
      body: const SafeArea(top: false, child: GymFinderView()),
    );
  }
}

/// 헬스장 찾기 화면의 본체 — 검색 + 지도 + 결과 목록.
///
/// 페이지(`/gyms`)와 운동 탭의 헬스장 화면이 **같은 위젯**을 쓴다. 연결된
/// 헬스장이 없는 회원에게 이 탭에서 할 일은 헬스장을 찾는 것뿐이라, 지도만 띄운
/// 빈 카드와 `헬스장 찾기` 버튼 대신 찾기 화면을 그대로 보여 준다(#1133).
///
/// 지도는 자리에 고정하고 그 위로 **목록 시트를 끌어 올리고 내린다**(#1274).
/// 시트는 세 자리에 붙는다 — 목록만 / 지도·목록 반반 / 지도만. 예전에는 머리줄
/// 화살표 하나로 두 상태를 오갈 뿐이라 폰에서 손으로 원하는 만큼 조절할 수
/// 없었고, 운동 탭처럼 바깥이 스크롤 뷰인 자리에서는 목록을 밀면 지도까지 함께
/// 밀려 올라갔다(#1135 가 막으려던 것이 이 배치에서는 지켜지지 않았다).
///
/// 그래서 이 위젯은 **높이를 스스로 정한다**. 바깥이 높이를 주면 그대로 쓰고,
/// 열린 높이(스크롤 뷰 안)에 놓이면 화면에서 한 몫을 떼어 쓴다 — 시트가 구를
/// 자리를 스스로 갖지 못하면 바깥 페이지가 대신 굴러 지도가 따라 움직인다.
///
/// 가로는 지도·시트가 **화면을 그대로 쓴다** (#1362). 여백은 검색줄과 시트 안
/// 내용이 각자 갖는다 — 창을 지도 폭에 맞춰 들여쓰면 폰에서 목록 카드가 그만큼
/// 좁아진다.
class GymFinderView extends ConsumerStatefulWidget {
  const GymFinderView({super.key});

  @override
  ConsumerState<GymFinderView> createState() => _GymFinderViewState();
}

class _GymFinderViewState extends ConsumerState<GymFinderView> {
  String _query = '';
  _GymSort _sort = _GymSort.recommended;

  List<Gym> _visibleGyms(List<Gym> gyms) {
    final String query = _query.trim().toLowerCase();
    final List<Gym> visible = gyms
        .where((Gym gym) {
          if (query.isEmpty) return true;
          return gym.name.toLowerCase().contains(query) ||
              gym.address.toLowerCase().contains(query) ||
              gym.tags.any((String tag) => tag.toLowerCase().contains(query));
        })
        .toList(growable: false);

    return switch (_sort) {
      _GymSort.recommended => visible,
      _GymSort.distance =>
        visible.toList()
          ..sort((Gym a, Gym b) => a.distanceKm.compareTo(b.distanceKm)),
      _GymSort.rating =>
        visible.toList()..sort((Gym a, Gym b) => b.rating.compareTo(a.rating)),
    };
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    // 제휴 헬스장 + 카카오 Local 주변 헬스장(#329). 카카오 쪽만 좌표가 있어도
    // 지도는 뜨고, 카카오가 실패하면 제휴 목록만 남는다.
    final AsyncValue<List<Gym>> gymsAsync = ref.watch(gymFinderResultsProvider);
    final List<Gym> visible = _visibleGyms(
      gymsAsync.valueOrNull ?? const <Gym>[],
    );
    // 상담 요청 확인 아이콘의 배지 — 대기 중인 요청이 있으면 점을 켠다(#1257).
    final bool hasPendingConsultation = ref
        .watch(consultationRequestControllerProvider)
        .any((ConsultationRequest r) => r.status == ConsultationStatus.pending);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints outer) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SizedBox(
            // 바깥이 높이를 주면 그대로 쓴다. 운동 탭처럼 **높이가 열린
            // 자리**(바깥이 스크롤 뷰)에 놓이면 화면에서 한 몫을 떼어 쓴다 —
            // 시트가 구를 자리를 스스로 갖지 못하면 바깥 페이지가 대신 굴러
            // 지도가 따라 움직인다 (#1274).
            height: outer.hasBoundedHeight
                ? outer.maxHeight
                : math.max(MediaQuery.sizeOf(context).height * 0.72, 460),
            // 좌우 여백은 **검색줄에만** 준다 (#1362). 지도·시트 묶음은
            // 화면 가로를 그대로 쓴다 — `주변 헬스장` 은 화면 아래에 붙는
            // 창이라 지도 폭에 맞춰 안으로 들여쓸 이유가 없고, 폰에서는 그
            // 여백만큼 목록 카드가 좁아진다. 시트 안 내용은 제 여백을 따로
            // 가진다.
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: _SearchField(
                          hintText: l.exGymSearchPlaceholder,
                          onChanged: (String value) =>
                              setState(() => _query = value),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // 헤더의 채팅 버튼과 같은 자리·배지 모양이다 — 대기 중인
                      // 상담 요청이 있으면 점이 켜진다(#1257).
                      HeaderActionButton(
                        key: const Key('consult-history-shortcut'),
                        icon: Icons.assignment_rounded,
                        tooltip: l.exViewConsultationRequest,
                        showDot: hasPendingConsultation,
                        onPressed: () =>
                            context.push(AppRoutes.consultationHistory),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                // 지도는 자리에 고정되고 그 위로 목록 시트가 오르내린다
                // (#1274). 시트가 화면 몫을 다 쓰므로 남는 높이를 그대로
                // 넘긴다.
                Expanded(
                  child: _GymMapAndList(
                    gyms: visible,
                    header: l.exNearbyGyms,
                    controls: gymsAsync.hasValue
                        ? _ResultControls(
                            countLabel: l.exResultCount(visible.length),
                            sort: _sort,
                            onSort: (_GymSort value) =>
                                setState(() => _sort = value),
                          )
                        : null,
                    resultSliver: _resultSliver(context, gymsAsync, visible),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 결과 목록 — 시트 하나가 통째로 구르는 스크롤 뷰의 조각이다 (#1274).
  ///
  /// 목록을 제 스크롤 뷰로 두면 시트를 끌 때와 목록을 밀 때가 서로 다른 손짓이
  /// 된다. 머리줄·정렬 줄과 같은 스크롤 뷰에 얹어야, 목록이 맨 위에 닿은 채로
  /// 계속 내리면 시트가 그대로 이어서 내려간다. 상자로 감싸지 않고 배경 위에
  /// 카드를 바로 쌓는 것은 그대로다 (#1135).
  Widget _resultSliver(
    BuildContext context,
    AsyncValue<List<Gym>> gymsAsync,
    List<Gym> visible,
  ) {
    final AppLocalizations l = AppLocalizations.of(context);
    return gymsAsync.when(
      loading: () => const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(child: CircularProgressIndicator(strokeWidth: 3)),
        ),
      ),
      error: (Object _, StackTrace _) => SliverToBoxAdapter(
        child: _LoadError(
          message: l.exGymsLoadError,
          onRetry: () => ref.invalidate(gymFinderResultsProvider),
        ),
      ),
      data: (List<Gym> _) {
        if (visible.isEmpty) {
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: _EmptyResults(message: l.exNoSearchResults),
            ),
          );
        }
        return SliverList.separated(
          itemCount: visible.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (BuildContext context, int index) => _GymListCard(
            key: Key('gym-card-${visible[index].id}'),
            gym: visible[index],
            onTap: () =>
                context.push(AppRoutes.gymDetailPath(visible[index].id)),
          ),
        );
      },
    );
  }
}

/// 위에 고정된 지도와 그 아래 결과 목록 (#1274 → #1362 → #1370).
///
/// **자리는 둘뿐이다 — 반반 / 목록만.** 머리줄의 화살표로만 오간다. 예전에는
/// 시트를 손으로 끌어 크기를 바꿨는데([DraggableScrollableSheet]), 그 손짓이
/// 목록 스크롤과 같은 방향이라 폰에서 목록이 넘어가지 않았다. 끄는 동작을
/// 없애면 목록에 닿은 손은 언제나 목록의 것이다.
///
/// 지도는 위에 **가로로 긴 띠 하나**로 고정된다(높이 고정, #1382). 목록만 보는
/// 자리에서는 그 띠가 통째로 사라진다 — 아래쪽에 지도가 다시 나오는 일은 없다.
///
/// 지도와 목록은 **자리를 나눠 갖는다** — 겹치지 않는다. 겹쳐 두면 웹에서
/// 목록 위의 터치가 아래 지도(플랫폼 뷰, DOM 요소)로 새어 나간다 (#1362).
/// 그래서 목록을 굴려도 지도는 움직이지 않고, 지도를 끌어도 목록은 그대로다.
///
/// 머리줄·정렬 줄은 목록 **위에 고정**되고, 구르는 것은 카드뿐이다. 접는
/// 화살표가 목록과 함께 굴러 사라지면 다시 펼 데가 없다.
class _GymMapAndList extends StatefulWidget {
  const _GymMapAndList({
    required this.gyms,
    required this.header,
    required this.controls,
    required this.resultSliver,
  });

  final List<Gym> gyms;
  final String header;

  /// 결과 수와 정렬 드롭다운. 아직 못 읽었으면 null 이라 자리도 없다.
  final Widget? controls;
  final Widget resultSliver;

  /// 지도 띠의 높이. **고정값**이다 (#1382) — 위에 가로로 길게 눕는 띠 하나이고,
  /// 그 아래는 목록뿐이다. 화면 비율로 잡으면 큰 폰에서 지도가 화면 절반을
  /// 먹어 머리줄·탭 줄까지 밀려 보이지 않는다.
  static const double kMapHeight = 200;

  /// 자리가 좁을 때 지도가 가져갈 수 있는 최대 몫. 목록이 카드 한 장도 못
  /// 세우게 두지 않는다.
  static const double kMapMaxFraction = 0.45;

  @override
  State<_GymMapAndList> createState() => _GymMapAndListState();
}

class _GymMapAndListState extends State<_GymMapAndList> {
  /// 목록만 보는 자리인가. 화살표가 이 값 하나를 뒤집는다.
  bool _listOnly = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final double height = box.maxHeight;
        // 좁은 자리에서는 고정값보다 그 자리를 따른다 — 지도가 부모를 넘겨
        // 목록을 밀어내면 안 된다.
        final double mapHeight = math.min(
          _GymMapAndList.kMapHeight,
          height * _GymMapAndList.kMapMaxFraction,
        );
        return Column(
          children: <Widget>[
            // 지도는 위에 가로로 긴 띠 하나로 **붙박이**다 (#1382). 목록만 보는
            // 자리에서는 크기를 0 으로 줄이는 대신 **트리에서 아예 뺀다** —
            // 웹에서 지도는 플랫폼 뷰(DOM 요소)라, 크기가 애니메이션으로
            // 흔들리는 상자 안에 있으면 제 상자를 벗어나 머리줄·탭 줄 위를
            // 덮었다. 사각 클립도 함께 씌워 상자 밖으로 넘치지 못하게 한다.
            if (!_listOnly)
              SizedBox(
                key: const Key('gym-map-slot'),
                height: mapHeight,
                width: double.infinity,
                child: ClipRect(child: _GymMap(gyms: widget.gyms)),
              ),
            Expanded(
              child: _SheetSurface(
                key: const Key('gym-result-sheet'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _SheetHead(
                      title: widget.header,
                      // 반반 자리가 곧 **접힌** 목록이다 — 여기서 화살표는
                      // 위를 가리키고, 누르면 목록이 화면을 다 쓴다.
                      collapsed: !_listOnly,
                      onToggle: () => setState(() => _listOnly = !_listOnly),
                    ),
                    if (widget.controls != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                        child: widget.controls,
                      ),
                    // 구르는 것은 카드뿐이다. 제 자리 안에서 구르므로 지도도,
                    // 바깥 화면도 따라 움직이지 않는다.
                    Expanded(
                      child: CustomScrollView(
                        key: const Key('gym-result-list'),
                        slivers: <Widget>[
                          // 시트는 화면 가로를 다 쓰고, 여백은 그 안에서
                          // 준다 (#1362).
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            sliver: widget.resultSliver,
                          ),
                          const SliverToBoxAdapter(child: SizedBox(height: 20)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 시트의 바탕 — 지도 위에 얹히므로 제 배경과 위쪽 둥근 모서리를 가진다.
class _SheetSurface extends StatelessWidget {
  const _SheetSurface({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: FigmaColors.statBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: child,
      ),
    );
  }
}

/// 목록 머리 — 제목과 화살표 한 줄 (#1186, #1370).
///
/// 손잡이 표시는 없다. 자리를 바꾸는 길이 화살표 하나뿐이라, 끌 수 있다는
/// 뜻으로 읽히는 표시를 두면 되지 않는 손짓을 부른다.
///
/// 화살표는 목록만 보고 있으면 아래를(지도를 다시 부를 수 있다), 반반이면
/// 위를(목록을 크게 볼 수 있다) 가리킨다.
class _SheetHead extends StatelessWidget {
  const _SheetHead({
    required this.title,
    required this.collapsed,
    required this.onToggle,
  });

  final String title;
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: _NearbyHeader(
        title: title,
        collapsed: collapsed,
        onToggle: onToggle,
      ),
    );
  }
}

/// `주변 헬스장` 머리줄 — 제목과 시트를 오르내리는 화살표 (#1186, #1274).
class _NearbyHeader extends StatelessWidget {
  const _NearbyHeader({
    required this.title,
    required this.collapsed,
    required this.onToggle,
  });

  final String title;
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    final String label = collapsed ? l.exGymListExpand : l.exGymListCollapse;
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: FigmaColors.ink,
            ),
          ),
        ),
        // 접힘 상태와 무엇을 할 수 있는지를 음성 안내에도 남긴다.
        Semantics(
          button: true,
          expanded: !collapsed,
          label: label,
          child: IconButton(
            key: const ValueKey<String>('gym-list-toggle'),
            onPressed: onToggle,
            tooltip: label,
            visualDensity: VisualDensity.compact,
            icon: Icon(
              collapsed
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              color: FigmaColors.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.hintText, required this.onChanged});

  final String hintText;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(
          color: AppColors.mutedForeground,
          fontSize: 13,
        ),
        prefixIcon: const Icon(
          Icons.search,
          color: FigmaColors.textMuted,
          size: 20,
        ),
        filled: true,
        fillColor: FigmaColors.softBlue,
        contentPadding: const EdgeInsets.symmetric(vertical: 15),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: FigmaColors.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: FigmaColors.primary),
        ),
      ),
    );
  }
}

class _ResultControls extends StatelessWidget {
  const _ResultControls({
    required this.countLabel,
    required this.sort,
    required this.onSort,
  });

  final String countLabel;
  final _GymSort sort;
  final ValueChanged<_GymSort> onSort;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            countLabel,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: FigmaColors.ink,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.only(left: 12, right: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: FigmaColors.hairline),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<_GymSort>(
              value: sort,
              borderRadius: BorderRadius.circular(12),
              icon: const Icon(Icons.expand_more, size: 18),
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: FigmaColors.ink,
              ),
              items: <DropdownMenuItem<_GymSort>>[
                DropdownMenuItem<_GymSort>(
                  value: _GymSort.recommended,
                  child: Text(l.exSortRecommended),
                ),
                DropdownMenuItem<_GymSort>(
                  value: _GymSort.distance,
                  child: Text(l.exSortDistance),
                ),
                DropdownMenuItem<_GymSort>(
                  value: _GymSort.rating,
                  child: Text(l.exSortRating),
                ),
              ],
              onChanged: (_GymSort? value) {
                if (value != null) onSort(value);
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// 결과 목록의 헬스장 카드 하나.
///
/// 이름·거리·평점·영업시간과 태그 아래에 **그 헬스장 소속 트레이너 전원**을
/// 적는다 (#1185) — 여기가 헬스장을 견주는 자리인데, 정작 누가 있는지는 상세로
/// 들어가야 알 수 있었다.
class _GymListCard extends ConsumerWidget {
  const _GymListCard({required this.gym, required this.onTap, super.key});

  final Gym gym;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l = AppLocalizations.of(context);
    final BorderRadius radius = BorderRadius.circular(16);
    // 트레이너를 아직 못 읽었거나 한 명도 없으면 이 부분은 통째로 없다 —
    // 카드가 예전과 같은 모습으로 남는다.
    final List<Trainer> trainers =
        ref.watch(gymTrainersProvider(gym.id)).valueOrNull ?? const <Trainer>[];
    return Material(
      color: Colors.white,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Ink(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: FigmaColors.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: FigmaColors.primaryA(0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.fitness_center,
                      size: 21,
                      color: FigmaColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          gym.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: FigmaColors.ink,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Row(
                          children: <Widget>[
                            Text(
                              '${gym.distanceKm.toStringAsFixed(1)}km',
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.mutedForeground,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Icon(
                              Icons.star_rounded,
                              size: 14,
                              color: FigmaColors.orange,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              gym.rating.toStringAsFixed(1),
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: FigmaColors.ink,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(
                          gym.weekdayHours == null
                              ? gym.address
                              : '${gym.address} · ${l.exGymWeekdayHours(gym.weekdayHours!)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.mutedForeground,
                          ),
                        ),
                        if (gym.tags.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 9),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: <Widget>[
                              for (final String tag in gym.tags.take(2))
                                _TagChip(label: tag),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (onTap != null) ...<Widget>[
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: FigmaColors.textFaint,
                    ),
                  ],
                ],
              ),
              // 소속 트레이너는 카드 **폭 전체**를 쓴다 — 이름·직함과 추천
              // 이유가 좁은 칸에서 두 번 접히지 않게.
              for (final Trainer trainer in trainers) ...<Widget>[
                const SizedBox(height: 9),
                GymTrainerLine(
                  key: Key('gym-trainer-${trainer.id}'),
                  trainer: trainer,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: FigmaColors.primaryA(0.09),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: FigmaColors.primary,
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.foreground, fontSize: 13),
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: Text(l.actionRetry)),
        ],
      ),
    );
  }
}

class _EmptyResults extends StatelessWidget {
  const _EmptyResults({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.foreground, fontSize: 13),
      ),
    );
  }
}

/// 목록에 보이는 헬스장을 카카오맵 핀으로 찍는다. `KAKAO_JS_KEY` 가 없거나
/// SDK 로드가 실패하면 [_GymMiniMap] 그래픽으로 폴백한다(#329).
class _GymMap extends StatelessWidget {
  const _GymMap({required this.gyms});

  final List<Gym> gyms;

  @override
  Widget build(BuildContext context) {
    final List<Gym> located = gyms
        .where((Gym g) => g.hasCoordinates)
        .toList(growable: false);

    // 높이를 스스로 정하지 않는다 — 시트가 어디에 있느냐가 지도의 높이를
    // 정한다 (#1274, #1362). 화면 가로를 그대로 쓰므로 모서리는 둥글리지
    // 않는다 — 아래로 이어지는 시트만 제 위쪽 모서리를 갖는다.
    return SizedBox.expand(
      child: KakaoMapView(
        // 지도 중심은 언제나 검색 중심([kGymFinderArea])이다. 첫 결과 좌표를
        // 쓰면 검색어·정렬·응답 순서에 따라 중심이 흔들려, 지도 중심과 장소
        // 검색 중심이 같아야 한다는 요건이 깨진다.
        centerLat: kGymFinderArea.lat,
        centerLng: kGymFinderArea.lng,
        markers: <KakaoMapMarker>[
          for (final Gym g in located)
            KakaoMapMarker(lat: g.lat!, lng: g.lng!, title: g.name),
        ],
        fallback: _GymMiniMap(pinCount: located.isEmpty ? 3 : located.length),
      ),
    );
  }
}

/// Lightweight illustrative map for the 헬스장 찾기 페이지 — a soft map backdrop
/// with [pinCount] location pins (헬스장 하나당 핀 하나) and a center "내 위치"
/// dot. Purely decorative (no real map/tiles/network) for the demo.
class _GymMiniMap extends StatelessWidget {
  const _GymMiniMap({required this.pinCount});

  final int pinCount;

  static const List<Alignment> _pinSpots = <Alignment>[
    Alignment(-0.55, -0.4),
    Alignment(0.5, -0.55),
    Alignment(0.42, 0.42),
    Alignment(-0.35, 0.55),
  ];

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    // 실지도와 **같은 자리**를 차지한다 (#1362) — 화면 가로를 채우고 높이는
    // 부모(시트가 남긴 자리)를 따른다. 둘의 생김새가 다르면 폴백으로 떨어질
    // 때 화면 구조가 바뀐다.
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFFE9F0F4)),
      child: SizedBox.expand(
        child: Stack(
          children: <Widget>[
            Positioned.fill(child: CustomPaint(painter: _MapRoadsPainter())),
            const Align(child: _MyLocationDot()),
            for (int i = 0; i < pinCount && i < _pinSpots.length; i++)
              Align(alignment: _pinSpots[i], child: const _MapPin()),
            Positioned(
              right: 10,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  l.exNearbyGymsMapLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.mutedForeground,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapPin extends StatelessWidget {
  const _MapPin();

  @override
  Widget build(BuildContext context) {
    return const Icon(
      Icons.location_on,
      size: 30,
      color: FigmaColors.primary,
      shadows: <Shadow>[
        Shadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1)),
      ],
    );
  }
}

class _MyLocationDot extends StatelessWidget {
  const _MyLocationDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: FigmaColors.primary,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
    );
  }
}

class _MapRoadsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint road = Paint()
      ..color = Colors.white
      ..strokeWidth = 7
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(0, size.height * 0.62),
      Offset(size.width, size.height * 0.5),
      road,
    );
    canvas.drawLine(
      Offset(size.width * 0.32, 0),
      Offset(size.width * 0.46, size.height),
      road,
    );
    canvas.drawLine(
      Offset(size.width * 0.7, size.height * 0.1),
      Offset(size.width * 0.86, size.height),
      road,
    );
    final Paint grid = Paint()
      ..color = const Color(0x0F1A1A1A)
      ..strokeWidth = 1;
    for (double x = size.width * 0.16; x < size.width; x += size.width * 0.22) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (
      double y = size.height * 0.28;
      y < size.height;
      y += size.height * 0.32
    ) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
  }

  @override
  bool shouldRepaint(covariant _MapRoadsPainter oldDelegate) => false;
}
