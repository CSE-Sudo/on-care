"""pip_audit_gate.py — 의존성 감사 결과와 허용 목록 대조 검사(#3163).

감사 잡이 오탐하면 백엔드 PR 이 모두 막히고, 놓치면 취약한 의존성이 초록색으로 병합된다.
그래서 통과·차단·만료·형식 오류의 경계를 픽스처로 고정한다.

실행: python3 -m unittest discover -s tool/ci -p 'test_*.py'
"""

from __future__ import annotations

import datetime as dt
import io
import json
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import pip_audit_gate as gate  # noqa: E402

REPO_ROOT = HERE.parent.parent
ALLOWLIST = REPO_ROOT / "backend" / "audit-allowlist.toml"
TODAY = dt.date(2026, 10, 5)


def audit(*deps: dict) -> str:
    return json.dumps({"dependencies": list(deps), "fixes": []})


def dep(name: str, version: str = "1.0.0", *vulns: dict) -> dict:
    return {"name": name, "version": version, "vulns": list(vulns)}


def vuln(vuln_id: str, *aliases: str, fix: tuple[str, ...] = ("1.0.1",)) -> dict:
    return {"id": vuln_id, "aliases": list(aliases), "fix_versions": list(fix), "description": "x"}


def entry(vuln_id: str = "GHSA-aaaa-bbbb-cccc", package: str = "requests",
          reason: str = "고친 버전이 없고 취약 경로를 쓰지 않는다", review_by: str = "2026-11-30") -> str:
    return (
        "[[ignore]]\n"
        f'id = "{vuln_id}"\n'
        f'package = "{package}"\n'
        f'reason = "{reason}"\n'
        f"review_by = {review_by}\n"
    )


def run(audit_text: str, allow_text: str, today: dt.date = TODAY) -> tuple[int, str, str]:
    with tempfile.TemporaryDirectory() as tmp:
        audit_path = Path(tmp) / "audit.json"
        allow_path = Path(tmp) / "allow.toml"
        summary_path = Path(tmp) / "summary.md"
        audit_path.write_text(audit_text, encoding="utf-8")
        allow_path.write_text(allow_text, encoding="utf-8")
        out = io.StringIO()
        with redirect_stdout(out):
            code = gate.main([
                "--audit", str(audit_path), "--allowlist", str(allow_path),
                "--summary", str(summary_path), "--today", today.isoformat(),
            ])
        summary = summary_path.read_text(encoding="utf-8") if summary_path.exists() else ""
    return code, out.getvalue(), summary


class PassAndBlockTest(unittest.TestCase):
    def test_clean_audit_passes(self) -> None:
        code, out, summary = run(audit(dep("fastapi"), dep("requests")), "")
        self.assertEqual(code, 0, out)
        self.assertIn("결과: 통과", summary)

    def test_unlisted_vulnerability_fails(self) -> None:
        code, out, summary = run(audit(dep("requests", "2.0.0", vuln("GHSA-aaaa-bbbb-cccc", "CVE-2026-1"))), "")
        self.assertEqual(code, 1)
        self.assertIn("::error title=pip-audit::requests 2.0.0 — GHSA-aaaa-bbbb-cccc (CVE-2026-1)", out)
        self.assertIn("허용 목록에 없는 취약점", summary)
        self.assertIn("결과: 실패", summary)

    def test_listed_vulnerability_passes(self) -> None:
        code, out, summary = run(audit(dep("requests", "2.0.0", vuln("GHSA-aaaa-bbbb-cccc"))), entry())
        self.assertEqual(code, 0, out)
        self.assertIn("허용 목록으로 통과한 취약점", summary)
        self.assertIn("고친 버전이 없고", summary)

    def test_alias_matches_case_insensitively(self) -> None:
        code, out, _ = run(
            audit(dep("requests", "2.0.0", vuln("PYSEC-2026-9", "cve-2026-1234"))),
            entry(vuln_id="CVE-2026-1234"),
        )
        self.assertEqual(code, 0, out)

    def test_package_names_are_normalized(self) -> None:
        code, out, _ = run(
            audit(dep("Typing_Extensions", "1.0", vuln("GHSA-aaaa-bbbb-cccc"))),
            entry(package="typing-extensions"),
        )
        self.assertEqual(code, 0, out)

    def test_same_id_on_another_package_is_not_allowed(self) -> None:
        code, _, _ = run(audit(dep("urllib3", "1.0", vuln("GHSA-aaaa-bbbb-cccc"))), entry(package="requests"))
        self.assertEqual(code, 1)

    def test_one_allowed_one_blocked_fails(self) -> None:
        code, out, _ = run(
            audit(dep("requests", "2.0", vuln("GHSA-aaaa-bbbb-cccc"), vuln("GHSA-dddd-eeee-ffff"))),
            entry(),
        )
        self.assertEqual(code, 1)
        self.assertIn("GHSA-dddd-eeee-ffff", out)
        self.assertNotIn("GHSA-aaaa-bbbb-cccc — 허용 목록에 없습니다", out)


class ReviewDateTest(unittest.TestCase):
    def test_review_day_itself_still_passes(self) -> None:
        code, out, _ = run(audit(dep("requests", "2", vuln("GHSA-aaaa-bbbb-cccc"))),
                           entry(review_by="2026-10-05"))
        self.assertEqual(code, 0, out)

    def test_expired_entry_fails(self) -> None:
        code, out, summary = run(audit(dep("requests", "2", vuln("GHSA-aaaa-bbbb-cccc"))),
                                 entry(review_by="2026-10-04"))
        self.assertEqual(code, 1)
        self.assertIn("재검토 날짜 2026-10-04 가 지났습니다", out)
        self.assertIn("재검토 날짜가 지난 허용 항목", summary)

    def test_expired_entry_fails_even_when_no_longer_reported(self) -> None:
        code, _, _ = run(audit(dep("requests")), entry(review_by="2026-09-01"))
        self.assertEqual(code, 1)

    def test_review_date_too_far_is_a_config_error(self) -> None:
        code, out, _ = run(audit(dep("requests")), entry(review_by="2027-12-31"))
        self.assertEqual(code, 2)
        self.assertIn("180일보다 멉니다", out)

    def test_quoted_date_is_a_config_error(self) -> None:
        code, out, _ = run(audit(dep("requests")), entry(review_by='"2026-11-30"'))
        self.assertEqual(code, 2)
        self.assertIn("TOML 날짜", out)

    def test_datetime_is_a_config_error(self) -> None:
        code, _, _ = run(audit(dep("requests")), entry(review_by="2026-11-30T00:00:00"))
        self.assertEqual(code, 2)


class WarningsTest(unittest.TestCase):
    def test_stale_entry_only_warns(self) -> None:
        code, out, summary = run(audit(dep("requests")), entry())
        self.assertEqual(code, 0, out)
        self.assertIn("::warning file=", out)
        self.assertIn("더 이상 보고되지 않습니다", out)
        self.assertIn("지울 대상", summary)

    def test_skipped_dependency_only_warns(self) -> None:
        skipped = {"name": "local-pkg", "skip_reason": "Dependency not found on PyPI"}
        code, out, summary = run(audit(dep("requests"), skipped), "")
        self.assertEqual(code, 0, out)
        self.assertIn("::warning title=pip-audit::local-pkg 를 검사하지 못했습니다", out)
        self.assertIn("검사하지 못한 의존성", summary)


class ConfigErrorTest(unittest.TestCase):
    def test_bad_allowlist_entries(self) -> None:
        cases = {
            "id 없음": '[[ignore]]\npackage = "requests"\nreason = "충분히 긴 사유입니다요"\nreview_by = 2026-11-30\n',
            "사유 짧음": entry(reason="짧음"),
            "사유 빔": entry(reason=" "),
            "id 형식": entry(vuln_id="nope"),
            "패키지 빔": entry(package=""),
            "모르는 키": entry() + 'owner = "x"\n',
            "모르는 최상위 키": 'other = 1\n',
            "중복": entry() + entry(),
            "TOML 오류": "[[ignore]\n",
        }
        for label, text in cases.items():
            with self.subTest(case=label):
                code, out, _ = run(audit(dep("requests")), text)
                self.assertEqual(code, 2, out)
                self.assertIn("::error title=pip-audit::", out)

    def test_bad_audit_output(self) -> None:
        for label, text in {"빈 파일": "", "JSON 아님": "not json", "목록 없음": "{}",
                            "배열": "[]"}.items():
            with self.subTest(case=label):
                code, out, _ = run(text, "")
                self.assertEqual(code, 2, out)

    def test_missing_files(self) -> None:
        with redirect_stdout(io.StringIO()):
            code = gate.main(["--audit", "/nonexistent/audit.json", "--allowlist", str(ALLOWLIST)])
        self.assertEqual(code, 2)


class RepositoryAllowlistTest(unittest.TestCase):
    def test_repository_allowlist_is_valid_today(self) -> None:
        # 저장소의 허용 목록이 오늘 기준으로 읽히고 만료 항목이 없어야 한다.
        today = dt.datetime.now(dt.timezone.utc).date()
        allowed = gate.load_allowlist(ALLOWLIST.read_text(encoding="utf-8"), today)
        self.assertEqual([e for e in allowed if e.review_by < today], [])

    def test_commented_example_stays_valid(self) -> None:
        # 주석의 예시를 풀어 쓰면 그대로 통과해야 한다(형식 안내가 틀리지 않게).
        lines = ALLOWLIST.read_text(encoding="utf-8").splitlines()
        start = lines.index("# [[ignore]]")
        example = "\n".join(line[2:] for line in lines[start:start + 5]) + "\n"
        allowed = gate.load_allowlist(example, dt.date(2026, 10, 1))
        self.assertEqual(len(allowed), 1)


if __name__ == "__main__":
    unittest.main()
