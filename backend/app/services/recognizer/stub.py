"""오프라인 스텁 인식기 — Gemini 키 없이도 /diet/analyze 데모가 동작.

실제 이미지를 보지 않고 결정론적 예시 식단을 반환한다. 엔드포인트의 enrich_analysis 가
공공 식품영양성분 DB로 신뢰 수치를 채우므로, 키 없는 데모에서도 그럴듯한 영양 결과가 나온다.
운영에서 GEMINI_API_KEY 가 있으면 factory 가 실제 Gemini 인식기를 쓴다.

세 항목은 시드(`food_nutrients_seed`)의 같은 이름에 그대로 붙는다 — 여기 값과
시드 값이 갈리면 enrich 가 시드 쪽으로 덮으므로, 고칠 때 둘을 같이 고친다.
같은 결과를 Flutter 로컬 데모(`local_api_interceptor.dart`)도 들고 있다.
"""
from __future__ import annotations

from app.schemas.diet import DietAnalysis, RecognizedFood
from app.services.recognizer.base import FoodRecognizer


class StubFoodRecognizer(FoodRecognizer):
    name = "stub"

    async def recognize(self, image_bytes: bytes, mime_type: str) -> DietAnalysis:  # noqa: ARG002
        foods = [
            RecognizedFood(
                name="요거트 아이스크림", amount_g=110, calories=135, sodium_mg=55, sugar_g=14.5,
                carbs_g=26.0, protein_g=3.0, fat_g=2.0, confidence=0.9,
            ),
            RecognizedFood(
                name="과일 토핑", amount_g=90, calories=55, sodium_mg=5, sugar_g=9.0,
                carbs_g=13.0, protein_g=1.0, fat_g=0.5, confidence=0.85,
            ),
            RecognizedFood(
                name="그래놀라 토핑", amount_g=50, calories=205, sodium_mg=125, sugar_g=6.0,
                carbs_g=20.0, protein_g=5.0, fat_g=11.5, confidence=0.8,
            ),
        ]
        return DietAnalysis(
            engine=self.name,
            foods=foods,
            coach_comment="나트륨이 185mg으로 낮아 부담이 적어요. 당류는 하루 목표(50g)의 "
            "절반 남짓인데, 그 절반이 요거트 아이스크림 자체에서 나옵니다. "
            "토핑은 지금처럼 과일·견과 위주로 담아 보세요.",
        ).compute_totals()
