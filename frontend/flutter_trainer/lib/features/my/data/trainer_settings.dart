import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:oncare_trainer/features/my/data/trainer_settings_repository.dart';

/// The trainer's notification preferences.
///
/// 종류마다 알림함에 넣을지를 정한다(#2264). 새 메시지만 서버가 처음부터 알고
/// 있고(`notify_new_message`), 상담 요청·예약·담당 회원 소식은 서버에 칸이
/// 생기기 전이다 — 그 셋은 서버 응답에 값이 없으면 `null` 이고, 화면은 그
/// 스위치를 막는다. 서버에 `notify_consultation`·`notify_reservation`·
/// `notify_member_updates` 가 생기면 앱 수정 없이 바로 켜고 끌 수 있다.
class TrainerSettings {
  /// Creates a settings snapshot.
  const TrainerSettings({
    this.newMessageAlerts = true,
    this.consultationAlerts = true,
    this.reservationAlerts = true,
    this.memberUpdateAlerts = true,
  });

  /// Notify when a client sends a message.
  final bool newMessageAlerts;

  /// 상담 요청이 오거나 회원이 거둘 때. `null` 이면 서버가 아직 모르는 설정.
  final bool? consultationAlerts;

  /// 회원이 예약을 잡거나 바꾸거나 취소할 때. `null` 이면 서버가 아직 모름.
  final bool? reservationAlerts;

  /// 담당 회원의 목표·이름 변경, 연결 종료, 담당 요청 수락·거절. `null` 이면
  /// 서버가 아직 모름.
  final bool? memberUpdateAlerts;

  /// Returns a copy with the given fields replaced.
  TrainerSettings copyWith({
    bool? newMessageAlerts,
    bool? consultationAlerts,
    bool? reservationAlerts,
    bool? memberUpdateAlerts,
  }) {
    return TrainerSettings(
      newMessageAlerts: newMessageAlerts ?? this.newMessageAlerts,
      consultationAlerts: consultationAlerts ?? this.consultationAlerts,
      reservationAlerts: reservationAlerts ?? this.reservationAlerts,
      memberUpdateAlerts: memberUpdateAlerts ?? this.memberUpdateAlerts,
    );
  }
}

/// Drives the 설정 screen's notification section.
///
/// Writes optimistically — a switch that waits for a round trip feels
/// broken — but **rolls back and surfaces the error** if the write
/// fails. Silently keeping a value the server rejected is how a settings
/// screen starts lying about itself.
///
/// 상태는 "아직 모름(로딩) / 받음 / 실패" 를 가른다(#2883). 예전에는 기본값(모두
/// 켬)에서 출발해, 받기 전·실패 뒤에도 스위치가 켬으로 보이고 눌렸다. 그때
/// 다른 스위치를 누르면 기본값이 섞인 전체 상태가 저장돼, 꺼 둔 새 메시지
/// 알림이 켬으로 덮어써졌다. 이제 값을 받기 전에는 쓰기를 받지 않는다.
class TrainerSettingsController
    extends StateNotifier<AsyncValue<TrainerSettings>> {
  /// Creates the controller and loads the stored settings.
  TrainerSettingsController(this._repository)
    : super(const AsyncLoading<TrainerSettings>()) {
    _load();
  }

  final TrainerSettingsRepository _repository;

  /// Set when the last write failed; the UI shows it once and clears it.
  /// 마지막 저장이 실패했는가. 문구는 화면이 붙인다. (#501)
  bool lastError = false;

  /// 쓰기 순번(#3103). 저장은 설정 전체를 덮어쓰는 `PUT` 이라, 스위치를 빠르게
  /// 끔→켬 하면 두 요청이 동시에 돈다. 응답은 보낸 순서대로 오지 않으므로
  /// 순번으로 어느 쪽이 최신인지 가린다.
  int _writeSeq = 0;

  /// 아직 응답이 오지 않은 쓰기의 순번.
  final Set<int> _pending = <int>{};

  /// 서버가 마지막으로 확인해 준 값과 그 순번(불러오기는 0). 최신 쓰기가
  /// 실패하면 요청 직전 값이 아니라 이 값으로 되돌린다 — 앞 요청 직전 값으로
  /// 되돌리면 뒤 요청으로 이미 저장된 변경이 화면에서 사라진다.
  TrainerSettings? _confirmed;
  int _confirmedSeq = 0;

  Future<void> _load() async {
    try {
      final TrainerSettings loaded = await _repository.load();
      _confirmed = loaded;
      _confirmedSeq = 0;
      if (mounted) state = AsyncData<TrainerSettings>(loaded);
    } catch (error, stackTrace) {
      // 기본값으로 채우지 않는다 — 화면은 실패를 알리고 다시 시도를 둔다.
      if (mounted) state = AsyncError<TrainerSettings>(error, stackTrace);
    }
  }

  /// 불러오기에 실패했을 때 다시 읽는다. 이미 받았거나 읽는 중이면 그대로 둔다.
  Future<void> reload() async {
    if (!state.hasError) return;
    state = const AsyncLoading<TrainerSettings>();
    await _load();
  }

  /// Toggles new-message notifications.
  Future<void> setNewMessageAlerts(bool value) =>
      _apply((s) => s.copyWith(newMessageAlerts: value));

  /// 상담 요청 알림을 켜고 끈다.
  Future<void> setConsultationAlerts(bool value) =>
      _apply((s) => s.copyWith(consultationAlerts: value));

  /// 예약 알림을 켜고 끈다.
  Future<void> setReservationAlerts(bool value) =>
      _apply((s) => s.copyWith(reservationAlerts: value));

  /// 담당 회원 소식 알림을 켜고 끈다.
  Future<void> setMemberUpdateAlerts(bool value) =>
      _apply((s) => s.copyWith(memberUpdateAlerts: value));

  /// 받은 값에만 얹어 저장한다. 받기 전·실패 뒤에는 아무것도 보내지 않는다 —
  /// 보내면 서버 값을 기본값으로 덮어쓴다(#2883).
  ///
  /// 응답·롤백은 순서를 확인하고 쓴다(#3103). 더 새 요청이 아직 돌고 있으면
  /// 화면은 그 요청의 낙관적 값을 그대로 두고 — 새 요청은 화면의 전체 값을
  /// 보내므로 앞 요청의 변경도 함께 싣는다 — 모든 요청이 끝난 뒤 서버가
  /// 마지막으로 확인한 값으로 맞춘다. 앞 요청만 실패하면 되돌리지도 알리지도
  /// 않는다.
  Future<void> _apply(TrainerSettings Function(TrainerSettings) change) async {
    final AsyncValue<TrainerSettings> previous = state;
    if (previous is! AsyncData<TrainerSettings>) return;
    final TrainerSettings next = change(previous.value);
    final int seq = ++_writeSeq;
    _pending.add(seq);
    state = AsyncData<TrainerSettings>(next);
    lastError = false;
    try {
      final TrainerSettings saved = await _repository.save(next);
      if (seq > _confirmedSeq) {
        _confirmed = saved;
        _confirmedSeq = seq;
      }
    } catch (_) {
      // 문구가 아니라 '실패했다'는 사실만 남긴다 — 컨트롤러는 로케일을
      // 모르고, 화면이 자기 언어로 문구를 붙인다. (#501) 최신 요청의
      // 실패만 알린다 — 앞 요청의 실패는 뒤 요청이 같은 변경을 다시 싣는다.
      if (seq == _writeSeq) lastError = true;
    } finally {
      _pending.remove(seq);
    }
    _settle();
  }

  /// 확인된 값보다 새 요청이 남아 있지 않으면 화면을 확인된 값에 맞춘다.
  void _settle() {
    if (!mounted) return;
    if (_pending.any((int s) => s > _confirmedSeq)) return;
    final TrainerSettings? confirmed = _confirmed;
    if (confirmed != null) state = AsyncData<TrainerSettings>(confirmed);
  }

  /// Clears [lastError] once the UI has shown it.
  void clearError() => lastError = false;
}

/// The trainer's notification settings.
///
/// 받기 전은 [AsyncLoading], 실패는 [AsyncError] 다(#2883).
final trainerSettingsProvider =
    StateNotifierProvider<
      TrainerSettingsController,
      AsyncValue<TrainerSettings>
    >((ref) {
      return TrainerSettingsController(
        ref.watch(trainerSettingsRepositoryProvider),
      );
    }, name: 'trainerSettings');
