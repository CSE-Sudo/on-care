#!/usr/bin/env python3
"""백엔드 의존성 감사(pip-audit) 결과를 허용 목록과 대조해 통과·실패를 정한다(#3163).

백엔드 CI 의 `Dependency audit (pip-audit)` 잡은 예전에 경고 모드라 알려진 취약점이 있어도
초록색이었다. 이제는 허용 목록(`backend/audit-allowlist.toml`)에 **사유와 재검토 날짜를
적고 올린 항목만** 통과시킨다.

실패(종료 코드 1)
  - 허용 목록에 없는 취약점이 하나라도 있다.
  - 허용 목록 항목의 재검토 날짜(`review_by`)가 지났다 — 그날까지는 통과, 다음 날부터 실패.
설정 오류(종료 코드 2)
  - 감사 결과·허용 목록을 읽지 못했거나, 항목에 id·package·reason·review_by 가 빠졌거나 형식이 틀렸다.
경고만
  - 허용 목록 항목이 더 이상 보고되지 않는다(고쳐졌으면 지운다).
  - pip-audit 이 검사하지 못하고 건너뛴 의존성이 있다.

허용 목록 형식(TOML)
  [[ignore]]
  id = "GHSA-xxxx-xxxx-xxxx"      # pip-audit 의 id 또는 별칭(CVE·PYSEC·GHSA) 중 하나
  package = "requests"             # 패키지 이름(대소문자·`-`/`_`/`.` 무시)
  reason = "왜 지금 고칠 수 없는지, 우리 코드가 영향받는지"
  review_by = 2026-12-31           # TOML 날짜. 이날이 지나면 CI 가 실패한다

사용
  pip_audit_gate.py --audit audit.json --allowlist backend/audit-allowlist.toml \\
      [--summary $GITHUB_STEP_SUMMARY] [--today YYYY-MM-DD]
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import sys
import tomllib
from dataclasses import dataclass, field
from pathlib import Path

#: 재검토 날짜를 너무 멀리 두면 허용 목록이 사실상 영구 면제가 된다.
MAX_REVIEW_DAYS = 180
MIN_REASON_CHARS = 10
ENTRY_KEYS = {"id", "package", "reason", "review_by"}


class GateError(Exception):
    """감사 결과나 허용 목록을 쓸 수 없다(설정 오류)."""


def normalize(name: str) -> str:
    """PEP 503 패키지 이름 정규화."""
    return re.sub(r"[-_.]+", "-", name).lower()


@dataclass(frozen=True)
class Allowed:
    id: str
    package: str
    reason: str
    review_by: dt.date


@dataclass(frozen=True)
class Finding:
    package: str
    version: str
    id: str
    aliases: tuple[str, ...]
    fix_versions: tuple[str, ...]

    @property
    def ids(self) -> set[str]:
        return {self.id.upper(), *(alias.upper() for alias in self.aliases)}


@dataclass
class Result:
    blocked: list[Finding] = field(default_factory=list)
    allowed: list[tuple[Finding, Allowed]] = field(default_factory=list)
    expired: list[Allowed] = field(default_factory=list)
    stale: list[Allowed] = field(default_factory=list)
    skipped: list[tuple[str, str]] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return not self.blocked and not self.expired


def load_allowlist(text: str, today: dt.date) -> list[Allowed]:
    try:
        data = tomllib.loads(text)
    except tomllib.TOMLDecodeError as exc:
        raise GateError(f"허용 목록을 TOML 로 읽지 못했습니다: {exc}") from exc
    unknown = set(data) - {"ignore"}
    if unknown:
        raise GateError(f"허용 목록에 알 수 없는 최상위 키가 있습니다: {sorted(unknown)}")
    entries = data.get("ignore", [])
    if not isinstance(entries, list):
        raise GateError("허용 목록의 ignore 는 [[ignore]] 표 배열이어야 합니다.")
    allowed: list[Allowed] = []
    seen: set[tuple[str, str]] = set()
    for index, entry in enumerate(entries, start=1):
        where = f"허용 목록 {index}번째 항목"
        if not isinstance(entry, dict):
            raise GateError(f"{where}이 표가 아닙니다.")
        missing = ENTRY_KEYS - set(entry)
        extra = set(entry) - ENTRY_KEYS
        if missing:
            raise GateError(f"{where}에 {', '.join(sorted(missing))} 가 없습니다.")
        if extra:
            raise GateError(f"{where}에 알 수 없는 키가 있습니다: {', '.join(sorted(extra))}")
        vuln_id, package, reason, review_by = (entry[k] for k in ("id", "package", "reason", "review_by"))
        if not isinstance(vuln_id, str) or not re.fullmatch(r"[A-Za-z]+-[A-Za-z0-9-]+", vuln_id.strip()):
            raise GateError(f"{where}의 id 형식이 틀렸습니다: {vuln_id!r}")
        if not isinstance(package, str) or not package.strip():
            raise GateError(f"{where}의 package 가 비어 있습니다.")
        if not isinstance(reason, str) or len(reason.strip()) < MIN_REASON_CHARS:
            raise GateError(f"{where}({vuln_id})의 reason 이 비었거나 너무 짧습니다.")
        if isinstance(review_by, dt.datetime) or not isinstance(review_by, dt.date):
            raise GateError(f"{where}({vuln_id})의 review_by 는 따옴표 없는 TOML 날짜(YYYY-MM-DD)여야 합니다.")
        if review_by > today + dt.timedelta(days=MAX_REVIEW_DAYS):
            raise GateError(
                f"{where}({vuln_id})의 review_by {review_by} 가 {MAX_REVIEW_DAYS}일보다 멉니다. 더 가까운 날짜로 다시 봅니다."
            )
        key = (vuln_id.strip().upper(), normalize(package))
        if key in seen:
            raise GateError(f"{where}({vuln_id})이 중복입니다.")
        seen.add(key)
        allowed.append(Allowed(vuln_id.strip(), package.strip(), reason.strip(), review_by))
    return allowed


def load_findings(text: str) -> tuple[list[Finding], list[tuple[str, str]]]:
    try:
        data = json.loads(text)
    except ValueError as exc:
        raise GateError(f"pip-audit 결과를 JSON 으로 읽지 못했습니다: {exc}") from exc
    dependencies = data.get("dependencies") if isinstance(data, dict) else None
    if not isinstance(dependencies, list):
        raise GateError("pip-audit 결과에 dependencies 목록이 없습니다(-f json 출력인지 확인).")
    findings: list[Finding] = []
    skipped: list[tuple[str, str]] = []
    for dep in dependencies:
        name = str(dep.get("name", "?"))
        if "skip_reason" in dep:
            skipped.append((name, str(dep["skip_reason"])))
            continue
        for vuln in dep.get("vulns") or []:
            findings.append(
                Finding(
                    package=name,
                    version=str(dep.get("version", "?")),
                    id=str(vuln.get("id", "?")),
                    aliases=tuple(str(a) for a in vuln.get("aliases") or ()),
                    fix_versions=tuple(str(v) for v in vuln.get("fix_versions") or ()),
                )
            )
    return findings, skipped


def evaluate(findings: list[Finding], skipped: list[tuple[str, str]],
             allowed: list[Allowed], today: dt.date) -> Result:
    result = Result(skipped=list(skipped))
    result.expired = [entry for entry in allowed if entry.review_by < today]
    used: set[int] = set()
    for finding in findings:
        match = next(
            (
                (i, entry) for i, entry in enumerate(allowed)
                if normalize(entry.package) == normalize(finding.package)
                and entry.id.upper() in finding.ids
            ),
            None,
        )
        if match is None:
            result.blocked.append(finding)
        else:
            used.add(match[0])
            result.allowed.append((finding, match[1]))
    result.stale = [entry for i, entry in enumerate(allowed) if i not in used]
    return result


def _finding_line(finding: Finding) -> str:
    fix = ", ".join(finding.fix_versions) or "없음"
    aliases = f" ({', '.join(finding.aliases)})" if finding.aliases else ""
    return f"{finding.package} {finding.version} — {finding.id}{aliases}, 고친 버전: {fix}"


def report(result: Result, allowlist_path: str) -> tuple[list[str], list[str]]:
    """(GitHub 주석 줄, 요약 마크다운 줄)."""
    annotations: list[str] = []
    summary = ["### pip-audit (허용 목록 대조)"]
    for finding in result.blocked:
        annotations.append(f"::error title=pip-audit::{_finding_line(finding)} — 허용 목록에 없습니다.")
    for entry in result.expired:
        annotations.append(
            f"::error file={allowlist_path},title=pip-audit 허용 목록::{entry.package} {entry.id} 의 재검토 날짜 "
            f"{entry.review_by} 가 지났습니다. 다시 판단해 고치거나 날짜·사유를 갱신합니다."
        )
    for entry in result.stale:
        annotations.append(
            f"::warning file={allowlist_path},title=pip-audit 허용 목록::{entry.package} {entry.id} 는 더 이상 "
            "보고되지 않습니다. 고쳐졌으면 항목을 지웁니다."
        )
    for name, why in result.skipped:
        annotations.append(f"::warning title=pip-audit::{name} 를 검사하지 못했습니다: {why}")

    if result.blocked:
        summary.append("")
        summary.append("**허용 목록에 없는 취약점**")
        summary.extend(f"- {_finding_line(f)}" for f in result.blocked)
    if result.expired:
        summary.append("")
        summary.append("**재검토 날짜가 지난 허용 항목**")
        summary.extend(f"- {e.package} {e.id} (review_by {e.review_by})" for e in result.expired)
    if result.allowed:
        summary.append("")
        summary.append("**허용 목록으로 통과한 취약점**")
        summary.extend(
            f"- {_finding_line(f)} — {e.reason} (review_by {e.review_by})" for f, e in result.allowed
        )
    if result.stale:
        summary.append("")
        summary.append("**보고되지 않는 허용 항목(지울 대상)**")
        summary.extend(f"- {e.package} {e.id}" for e in result.stale)
    if result.skipped:
        summary.append("")
        summary.append("**검사하지 못한 의존성**")
        summary.extend(f"- {name}: {why}" for name, why in result.skipped)
    summary.append("")
    summary.append("결과: " + ("통과" if result.ok else "실패"))
    return annotations, summary


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="pip-audit 결과를 허용 목록과 대조한다.")
    parser.add_argument("--audit", type=Path, required=True, help="pip-audit -f json 출력")
    parser.add_argument("--allowlist", type=Path, required=True)
    parser.add_argument("--summary", type=Path, help="요약 마크다운을 덧붙일 파일")
    parser.add_argument("--today", type=dt.date.fromisoformat, default=None, help="검사 기준일(테스트용)")
    args = parser.parse_args(argv)
    today = args.today or dt.datetime.now(dt.timezone.utc).date()

    try:
        allowed = load_allowlist(args.allowlist.read_text(encoding="utf-8"), today)
        findings, skipped = load_findings(args.audit.read_text(encoding="utf-8"))
    except (OSError, GateError) as exc:
        print(f"::error title=pip-audit::{exc}")
        return 2

    result = evaluate(findings, skipped, allowed, today)
    annotations, summary = report(result, str(args.allowlist))
    for line in annotations:
        print(line)
    print("\n".join(summary))
    if args.summary:
        with args.summary.open("a", encoding="utf-8") as handle:
            handle.write("\n".join(summary) + "\n")
    print(
        f"취약점 {len(findings)}건 — 차단 {len(result.blocked)}, 허용 {len(result.allowed)}; "
        f"허용 항목 {len(allowed)}건 — 만료 {len(result.expired)}, 미사용 {len(result.stale)}"
    )
    return 0 if result.ok else 1


if __name__ == "__main__":
    sys.exit(main())
