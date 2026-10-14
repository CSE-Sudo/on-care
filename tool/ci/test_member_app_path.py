"""회원 앱 배포 경로(/member/)와 Pages 주소 배선 검사(#2000).

회원 앱은 `/member/` 에 올라간다(트레이너 웹 `/trainer/` 와 같은 사용자 기준 이름). 두 배포의
base-href 나 랜딩 바로가기 중 하나만 예전 `/frontend/` 로 남으면 빌드는 성공하고 앱만 빈 화면이
되거나 바로가기가 404 가 되므로 병합 전에 확인한다.

실행: python3 -m unittest discover -s tool/ci -p 'test_*.py'
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
WORKFLOWS = REPO_ROOT / ".github" / "workflows"


class MemberAppPathTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.pages = (WORKFLOWS / "deploy.yml").read_text(encoding="utf-8")
        cls.aws = (WORKFLOWS / "aws-frontend-deploy.yml").read_text(encoding="utf-8")
        cls.landing = (REPO_ROOT / "index.html").read_text(encoding="utf-8")

    def test_both_deploys_build_member_app_under_member(self) -> None:
        # AWS 는 도메인 루트, Pages 는 저장소 경로(/on-care) 아래라 Pages 설정의 base_path 를 붙인다.
        self.assertIn('--base-href "/member/"', self.aws)
        self.assertIn('--base-href "${PAGES_BASE_PATH}/member/"', self.pages)
        self.assertIn('--base-href "${PAGES_BASE_PATH}/trainer/"', self.pages)
        self.assertIn("PAGES_BASE_PATH: ${{ steps.pages.outputs.base_path }}", self.pages)
        for text in (self.pages, self.aws):
            self.assertNotIn("/frontend/", text)

    def test_pages_does_not_depend_on_custom_domain(self) -> None:
        # 사람이 갱신해야 살아 있는 커스텀 도메인을 떼었다(#2000). CNAME 이 돌아오면 같은 장애가 난다.
        self.assertFalse((REPO_ROOT / "CNAME").exists())
        self.assertNotIn("CNAME", self.pages)
        self.assertIn("PAGES_BASE_URL: ${{ steps.pages.outputs.base_url }}", self.pages)

    def test_landing_links_point_to_member(self) -> None:
        self.assertIn('href="member/#/dashboard"', self.landing)
        self.assertIsNone(re.search(r'href="(\./)?frontend/', self.landing))

    def test_pages_points_landing_apps_to_production_after_stamping(self) -> None:
        """데모 Pages 랜딩의 앱 바로가기는 운영 사이트로 간다(#3437). 원본은 상대 경로 그대로다.

        stamp 가 치환 전에 상대 경로 규칙을 보므로 바꾸기는 그 뒤여야 하고, 배포 후 확인도 같은
        주소를 받아야 바꾼 랜딩을 실패로 보지 않는다. AWS 배포는 바꾸지 않는다.
        """
        stamp = self.pages.index("landing_site_url.sh stamp public/index.html")
        point = self.pages.index(
            'landing_site_url.sh point-apps public/index.html "$PRODUCTION_FRONTEND_URL"'
        )
        self.assertLess(stamp, point)
        self.assertEqual(
            self.pages.count("PRODUCTION_FRONTEND_URL: ${{ vars.PRODUCTION_FRONTEND_URL }}"), 2
        )
        self.assertIn(
            'landing_site_url.sh verify "$SITE_URL" "$site" 600 "$PRODUCTION_FRONTEND_URL"',
            self.pages,
        )
        self.assertNotIn("point-apps", self.aws)
        self.assertIsNone(re.search(r'href="https?://[^"]*/(member|trainer)/', self.landing))


if __name__ == "__main__":
    unittest.main()
