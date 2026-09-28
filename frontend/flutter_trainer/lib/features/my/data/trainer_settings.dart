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
class TrainerSettingsController extends StateNotifier<TrainerSettings> {
  /// Creates the controller and loads the stored settings.
  TrainerSettingsController(this._repository) : super(const TrainerSettings()) {
    _load();
  }

  final TrainerSettingsRepository _repository;

  /// Set when the last write failed; the UI shows it once and clears it.
  /// 마지막 저장이 실패했는가. 문구는 화면이 붙인다. (#501)
  bool lastError = false;

  Future<void> _load() async {
    try {
      state = await _repository.load();
    } catch (_) {
      // Keep the defaults on screen — an unreachable settings endpoint
      // shouldn't block the rest of the page.
    }
  }

  /// Toggles new-message notifications.
  Future<void> setNewMessageAlerts(bool value) =>
      _apply(state.copyWith(newMessageAlerts: value));

  /// 상담 요청 알림을 켜고 끈다.
  Future<void> setConsultationAlerts(bool value) =>
      _apply(state.copyWith(consultationAlerts: value));

  /// 예약 알림을 켜고 끈다.
  Future<void> setReservationAlerts(bool value) =>
      _apply(state.copyWith(reservationAlerts: value));

  /// 담당 회원 소식 알림을 켜고 끈다.
  Future<void> setMemberUpdateAlerts(bool value) =>
      _apply(state.copyWith(memberUpdateAlerts: value));

  Future<void> _apply(TrainerSettings next) async {
    final previous = state;
    state = next;
    lastError = false;
    try {
      state = await _repository.save(next);
    } catch (_) {
      state = previous;
      // 문구가 아니라 '실패했다'는 사실만 남긴다 — 컨트롤러는 로케일을
      // 모르고, 화면이 자기 언어로 문구를 붙인다. (#501)
      lastError = true;
    }
  }

  /// Clears [lastError] once the UI has shown it.
  void clearError() => lastError = false;
}

/// The trainer's notification settings.
final trainerSettingsProvider =
    StateNotifierProvider<TrainerSettingsController, TrainerSettings>((ref) {
      return TrainerSettingsController(
        ref.watch(trainerSettingsRepositoryProvider),
      );
    }, name: 'trainerSettings');
