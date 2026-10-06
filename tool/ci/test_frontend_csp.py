"""CloudFront 응답 헤더 정책과 두 웹 앱 meta CSP 의 일치 검사(#3017).

운영(AWS CloudFront)은 infra/frontend-hosting.yml 의 응답 헤더 정책으로 CSP 를 내리고,
두 앱의 web/index.html 은 같은 지시어를 meta 로 건다(로컬 개발·Pages 데모용). 브라우저는
둘을 함께 적용하므로 한쪽에만 출처를 더하면 운영에서 그 출처가 막힌다. 그래서

* 두 index.html 의 meta CSP 는 서로 같고,
* 헤더 CSP 는 connect-src·frame-ancestors 를 빼면 meta 와 같은 지시어·출처를 가지며,
* 헤더의 connect-src 는 'self'·API 출처·정적 출처만 연다(https: 전체·localhost 금지)

를 병합 전에 확인한다. 템플릿은 CloudFormation 태그(!Sub 등)를 쓰므로 YAML 로 읽지 않고
리소스 블록 단위로 잘라 문자열로 본다.

실행: python3 -m unittest discover -s tool/ci -p 'test_*.py'
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
TEMPLATE = REPO_ROOT / "infra" / "frontend-hosting.yml"
INDEX_FILES = (
    REPO_ROOT / "frontend" / "flutter" / "web" / "index.html",
    REPO_ROOT / "frontend" / "flutter_trainer" / "web" / "index.html",
)

META_CSP = re.compile(
    r'<meta\s+http-equiv="Content-Security-Policy"\s+content="([^"]+)"', re.IGNORECASE
)
HEADER_CSP = re.compile(r'^\s*ContentSecurityPolicy:\s*(?:!Sub\s+)?"([^"]+)"\s*$', re.MULTILINE)
# 헤더에만 있어야 하는 지시어와, 헤더에서 좁히는 지시어.
HEADER_ONLY = {"frame-ancestors"}
NARROWED = {"connect-src"}
# 헤더 connect-src 가 열어 둘 수 있는 출처. ${...} 는 스택 파라미터 자리다.
ALLOWED_STATIC_CONNECT = {
    "'self'",
    # 사진 선택기가 줄인 사진을 같은 탭의 blob: 주소에서 읽는다. 외부 출처가 아니다.
    "blob:",
    "${ApiOrigin}",
    "${ExtraConnectSources}",
    "https://www.gstatic.com",
    "https://fonts.gstatic.com",
    "https://dapi.kakao.com",
    # 구글 로그인 버튼(GIS)이 로그인 상태를 묻는 곳(#330).
    "https://accounts.google.com/gsi/",
}


def parse_csp(value: str) -> dict[str, set[str]]:
    """`a b c; d e` → {"a": {"b", "c"}, "d": {"e"}}. 같은 지시어가 두 번 나오면 실패."""
    directives: dict[str, set[str]] = {}
    for part in value.split(";"):
        tokens = part.split()
        if not tokens:
            continue
        name = tokens[0].lower()
        if name in directives:
            raise AssertionError(f"CSP 지시어 중복: {name}")
        directives[name] = set(tokens[1:])
    return directives


def resource_block(text: str, name: str) -> str:
    """최상위 리소스 하나(`  Name:` 부터 다음 `  Other:` 직전까지)를 잘라 낸다."""
    match = re.search(rf"^  {re.escape(name)}:\n(.*?)(?=^  [A-Za-z][A-Za-z0-9]*:\n|^[A-Za-z]|\Z)",
                      text, re.MULTILINE | re.DOTALL)
    if not match:
        raise AssertionError(f"템플릿에 {name} 리소스가 없습니다")
    return match.group(1)


def header_csp(block: str) -> dict[str, set[str]]:
    found = HEADER_CSP.findall(block)
    if len(found) != 1:
        raise AssertionError(f"CSP 문자열을 하나 찾아야 하는데 {len(found)}개입니다")
    return parse_csp(found[0])


class FrontendCspTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.template = TEMPLATE.read_text(encoding="utf-8")
        cls.app_block = resource_block(cls.template, "FrontendAppResponseHeadersPolicy")
        cls.landing_block = resource_block(cls.template, "FrontendLandingResponseHeadersPolicy")
        cls.app_csp = header_csp(cls.app_block)
        cls.landing_csp = header_csp(cls.landing_block)
        metas = []
        for path in INDEX_FILES:
            found = META_CSP.findall(path.read_text(encoding="utf-8"))
            if len(found) != 1:
                raise AssertionError(f"{path} 에 meta CSP 가 하나 있어야 합니다")
            metas.append(parse_csp(found[0]))
        cls.metas = metas

    def test_parse_csp_rejects_duplicate_directive(self) -> None:
        with self.assertRaises(AssertionError):
            parse_csp("default-src 'self'; default-src https:")

    def test_parse_csp_ignores_empty_parts_and_case(self) -> None:
        self.assertEqual(parse_csp(" Default-Src 'self' ;; img-src data: "),
                         {"default-src": {"'self'"}, "img-src": {"data:"}})

    def test_two_apps_share_one_meta_policy(self) -> None:
        self.assertEqual(self.metas[0], self.metas[1])

    def test_header_matches_meta_except_narrowed_directives(self) -> None:
        meta = self.metas[0]
        header = {k: v for k, v in self.app_csp.items() if k not in HEADER_ONLY | NARROWED}
        expected = {k: v for k, v in meta.items() if k not in NARROWED}
        self.assertEqual(header, expected)

    def test_meta_does_not_carry_header_only_directives(self) -> None:
        for meta in self.metas:
            for name in HEADER_ONLY:
                self.assertNotIn(name, meta)

    def test_header_connect_src_is_narrowed(self) -> None:
        sources = self.app_csp["connect-src"]
        self.assertIn("'self'", sources)
        self.assertIn("${ApiOrigin}", sources)
        self.assertIn("blob:", sources)
        self.assertNotIn("https:", sources)
        for source in sources:
            self.assertNotIn("localhost", source)
            self.assertNotIn("127.0.0.1", source)
            self.assertFalse(source.startswith("http://"), source)
            self.assertIn(source, ALLOWED_STATIC_CONNECT)

    def test_header_connect_src_is_within_meta(self) -> None:
        meta = self.metas[0]["connect-src"]
        for source in self.app_csp["connect-src"]:
            if source.startswith(("https://", "${")):
                self.assertIn("https:", meta)
            else:
                self.assertIn(source, meta)

    def test_both_policies_forbid_framing(self) -> None:
        for csp, block in ((self.app_csp, self.app_block), (self.landing_csp, self.landing_block)):
            self.assertEqual(csp.get("frame-ancestors"), {"'none'"})
            self.assertRegex(block, r"FrameOption:\s*DENY")
            self.assertRegex(block, r"ContentTypeOptions:")
            self.assertRegex(block, r"ReferrerPolicy:\s*strict-origin-when-cross-origin")

    def test_both_policies_send_hsts_for_a_year(self) -> None:
        for block in (self.app_block, self.landing_block):
            match = re.search(r"AccessControlMaxAgeSec:\s*(\d+)", block)
            self.assertIsNotNone(match)
            self.assertGreaterEqual(int(match.group(1)), 31536000)
            self.assertRegex(block, r"IncludeSubdomains:\s*true")
            # preload 목록 등록은 운영 도메인 확정 뒤 따로 정한다.
            self.assertRegex(block, r"Preload:\s*false")

    def test_landing_policy_blocks_outbound_requests(self) -> None:
        self.assertEqual(self.landing_csp["connect-src"], {"'self'"})
        self.assertEqual(self.landing_csp["object-src"], {"'none'"})

    def test_app_paths_use_app_policy_and_default_uses_landing_policy(self) -> None:
        dist = resource_block(self.template, "FrontendDistribution")
        for pattern in ("/frontend/*", "/trainer/*"):
            behaviour = re.search(
                rf"- PathPattern: {re.escape(pattern)}\n(.*?)(?=\n          - PathPattern:|\n        DefaultCacheBehavior:)",
                dist, re.DOTALL)
            self.assertIsNotNone(behaviour, pattern)
            self.assertIn("ResponseHeadersPolicyId: !Ref FrontendAppResponseHeadersPolicy",
                          behaviour.group(1))
            self.assertIn("FunctionARN: !GetAtt FrontendRouterFunction.FunctionARN",
                          behaviour.group(1))
        default = dist.split("DefaultCacheBehavior:", 1)[1].split("DefaultRootObject", 1)[0]
        self.assertIn("ResponseHeadersPolicyId: !Ref FrontendLandingResponseHeadersPolicy", default)

    def test_router_redirects_app_roots_without_slash(self) -> None:
        router = resource_block(self.template, "FrontendRouterFunction")
        self.assertIn("uri === '/frontend' || uri === '/trainer'", router)
        self.assertIn("statusCode: 301", router)

    def test_custom_domain_is_optional_and_paired(self) -> None:
        self.assertRegex(self.template, r"AlternateDomainName:\n\s+Type: String\n\s+Default: ''")
        self.assertRegex(self.template, r"AcmCertificateArn:\n\s+Type: String\n\s+Default: ''")
        self.assertIn("acm:us-east-1:", self.template)
        self.assertIn("CustomDomainNeedsCertificate:", self.template)
        dist = resource_block(self.template, "FrontendDistribution")
        self.assertRegex(dist, r"ViewerCertificate: !If\n\s+- HasCustomDomain")
        self.assertIn("CloudFrontDefaultCertificate: true", dist)
        self.assertIn("SslSupportMethod: sni-only", dist)


if __name__ == "__main__":
    unittest.main()
