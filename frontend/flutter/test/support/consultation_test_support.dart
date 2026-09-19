import 'package:oncare/features/exercise/data/repositories/dio_consultation_repository.dart';
import 'package:oncare/features/exercise/data/repositories/mock_gym_repository.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_draft.dart';
import 'package:oncare/features/exercise/domain/entities/consultation_request.dart';
import 'package:oncare/features/exercise/presentation/controllers/consultation_request_controller.dart';

/// 서버로 나가지 않는 컨트롤러 — 테스트는 대기 상태만 필요하다.
ConsultationRequestController newTestConsultationController() =>
    ConsultationRequestController(
      MockConsultationRepository(MockGymRepository()),
    );

/// 표시용 요청에서 접수 payload 를 만든다. mock repository 는 내용을 보지 않으므로
/// 대상 트레이너만 맞으면 충분하다.
ConsultationDraft draftFor(ConsultationRequest request) => ConsultationDraft(
  trainerId: request.trainerId ?? '',
  exerciseGoal: ExerciseGoal.fitness,
  healthPurposeType: HealthPurposeType.general,
  healthPurposeDetail: null,
  slotId: 'slot-test',
  message: request.message,
);

/// 예전 `controller.add(r)` 를 대신한다. 접수되면 true.
Future<bool> seedPending(
  ConsultationRequestController controller,
  ConsultationRequest request,
) async {
  final ConsultationRequest? saved = await controller.submit(
    draft: draftFor(request),
    display: request,
  );
  return saved != null;
}
