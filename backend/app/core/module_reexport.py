"""영역별 모듈로 나눈 코드를 예전 모듈 경로로 다시 내보내는 호환 단계 도우미. (#2909)

트레이너 서비스·라우터를 한 파일에서 영역별 모듈로 옮기는 첫 단계에서, 호출부와
테스트가 쓰는 예전 경로(`app.services.trainer_service`, `app.api.v1.trainer`)를 그대로
살려 둔다.

- 영역 모듈의 이름을 예전 모듈에 **같은 객체**로 올린다. `trainer_service.X` 와
  `trainer.<영역>.X` 는 같은 함수·클래스·예외다.
- 예전 모듈의 속성을 바꾸면(테스트의 `monkeypatch.setattr`) 그 객체를 쥔 영역 모듈에도
  똑같이 반영한다. 한 파일이던 때는 모듈 전역 하나만 바꾸면 그 파일 안 모든 함수가
  새 값을 봤으므로, 나눈 뒤에도 같은 효과가 나야 한다. 되돌릴 때도 같은 길로 원래
  객체가 돌아간다.

영역별로 호출부 import 를 새 경로로 옮긴 뒤, 마지막 단계에서 이 도우미와 함께 지운다.
"""
from __future__ import annotations

import sys
import types
from collections.abc import Iterable, Sequence

_MISSING = object()


class _ReexportModule(types.ModuleType):
    """속성 변경을 원본 영역 모듈까지 전파하는 모듈 타입."""

    def __setattr__(self, name: str, value: object) -> None:
        old = self.__dict__.get(name, _MISSING)
        if old is not _MISSING and not name.startswith("__"):
            for source in self.__dict__.get("__reexport_sources__", ()):
                # 같은 객체를 쥔 모듈만 바꾼다 — 이름만 같고 다른 객체면 건드리지 않는다.
                if source.__dict__.get(name, _MISSING) is old:
                    setattr(source, name, value)
        super().__setattr__(name, value)


def reexport(
    facade_name: str,
    sources: Sequence[types.ModuleType],
    *,
    skip: Iterable[str] = (),
) -> None:
    """[sources] 의 이름을 [facade_name] 모듈에 올리고 속성 변경 전파를 켠다.

    같은 이름이 서로 다른 객체로 두 영역에 있으면 어느 쪽을 가리킬지 정할 수 없으므로
    실패한다. 영역마다 따로 두는 이름(라우터의 `router`)은 [skip] 으로 뺀다.
    """
    facade = sys.modules[facade_name]
    skipped = set(skip)
    exported: dict[str, object] = {}
    for source in sources:
        for name, value in vars(source).items():
            if name.startswith("__") or name in skipped:
                continue
            if exported.get(name, value) is not value:
                raise RuntimeError(
                    f"{facade_name}: '{name}' 가 영역 모듈마다 다른 객체다 ({source.__name__})"
                )
            exported[name] = value
    for name, value in exported.items():
        facade.__dict__.setdefault(name, value)
    facade.__dict__["__reexport_sources__"] = tuple(sources)
    facade.__class__ = _ReexportModule
