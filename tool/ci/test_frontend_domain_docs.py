"""프론트 배포 문서의 데모·운영 도메인 모델 검사(#3021).

데모(GitHub Pages)와 운영(CloudFront)은 서로 다른 도메인이다. 데모 도메인(CNAME)은 사람이
주기적으로 갱신해야 살아 있는 무료 DNS 라 운영 도메인·운영 인증서의 근거가 될 수 없다(#2000).
예전 문서에는 그 데모 도메인으로 ACM 인증서를 발급해 CloudFront 로 옮기고 Pages 배포를
중단하라는 절차가 현행 계획처럼 남아 있었다. 같은 서술이 다시 들어오지 않게 막는다.

실행: python3 -m unittest discover -s tool/ci -p 'test_*.py'
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
DOCS = (
    REPO_ROOT / "docs" / "frontend_deployment.md",
    REPO_ROOT / "docs" / "aws-frontend-deployment.md",
)
DEMO_DOMAIN = (REPO_ROOT / "CNAME").read_text(encoding="utf-8").strip()

# 데모 도메인과 한 줄에 함께 나오면 "데모 도메인을 운영으로 옮긴다"는 서술로 본다.
OPERATIONAL_WORDS = re.compile(r"ACM|인증서|certificate|CloudFront\s*로|alternate|대체 도메인|Aliases",
                               re.IGNORECASE)
# 데모 Pages 를 끄는 단계와, Pages 를 운영(사용자 제공) 도메인으로 적는 서술.
FORBIDDEN = (
    re.compile(r"Pages\s*배포\s*중단"),
    re.compile(r"Pages\s*배포를\s*중단합니다"),
    re.compile(r"DNS\s*를\s*GitHub Pages\s*에서\s*CloudFront"),
    re.compile(r"커스텀 도메인은\s*(\*\*)?\s*여전히 GitHub Pages"),
)


def offending_lines(text: str) -> list[str]:
    found = []
    for number, line in enumerate(text.splitlines(), start=1):
        if DEMO_DOMAIN in line and OPERATIONAL_WORDS.search(line):
            found.append(f"{number}: {line.strip()}")
            continue
        if any(pattern.search(line) for pattern in FORBIDDEN):
            found.append(f"{number}: {line.strip()}")
    return found


class FrontendDomainDocsTest(unittest.TestCase):
    def test_demo_domain_is_known(self) -> None:
        self.assertRegex(DEMO_DOMAIN, r"^[a-z0-9.-]+\.[a-z]+$")

    def test_docs_do_not_move_demo_domain_to_production(self) -> None:
        for path in DOCS:
            with self.subTest(doc=path.name):
                self.assertEqual(offending_lines(path.read_text(encoding="utf-8")), [])

    def test_docs_state_the_two_domain_model(self) -> None:
        for path in DOCS:
            with self.subTest(doc=path.name):
                self.assertIn("서로 다른 도메인", path.read_text(encoding="utf-8"))

    def test_detector_catches_old_wording(self) -> None:
        old = "\n".join([
            f"1. `us-east-1`에서 `{DEMO_DOMAIN}`용 ACM 인증서 발급 및 DNS 검증",
            "3. DNS를 GitHub Pages에서 CloudFront로 전환",
            "5. 롤백 가능 여부를 확인한 뒤 GitHub Pages 배포 중단",
            "사용자에게 제공하는 **커스텀 도메인은 여전히 GitHub Pages** 를 가리킵니다.",
        ])
        self.assertEqual(len(offending_lines(old)), 4)

    def test_detector_allows_demo_rows_and_negated_steps(self) -> None:
        ok = "\n".join([
            f"| `https://{DEMO_DOMAIN}/` | 랜딩페이지 | `public/index.html` |",
            "데모 Pages 배포를 중단하는 단계는 없습니다.",
            "`us-east-1` 에서 `<운영 도메인>` 용 ACM 인증서를 요청합니다.",
        ])
        self.assertEqual(offending_lines(ok), [])


if __name__ == "__main__":
    unittest.main()
