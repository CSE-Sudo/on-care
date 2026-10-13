"""CI 가 테스트를 여러 잡으로 나눠 돌릴 때 쓰는 묶음 규칙. (#3321)

스위트 전체를 한 러너에서 차례로 돌리면 30분 가까이 걸린다. CI 는 `PYTEST_SHARD=2/6`
처럼 "여섯 묶음 중 둘째"를 환경변수로 주고, 잡마다 자기 묶음만 돌린다. 묶음마다 자기
Postgres 를 가지므로 각 잡은 지금까지와 같은 "한 프로세스·한 DB" 로 돈다.

규칙은 두 가지를 지킨다.

* **빠짐도 겹침도 없다.** 모든 파일이 정확히 한 묶음에 들어간다. 묶음을 모두 돌리면
  스위트 전체를 한 번 돌린 것과 같다.
* **어느 잡에서 계산해도 같다.** 입력(파일별 테스트 수)만으로 정해지고 순서·시각·
  난수에 기대지 않는다. 잡마다 답이 다르면 어떤 파일은 두 번 돌고 어떤 파일은 한 번도
  돌지 않는다.

**파일 단위**로 나눈다 — 한 파일 안의 테스트는 같은 묶음에서 원래 순서대로 돈다.
"""
from __future__ import annotations

from collections.abc import Mapping

#: 환경변수 이름. 값은 `<묶음 번호>/<묶음 수>` 이고 번호는 1 부터다.
ENV_VAR = "PYTEST_SHARD"


def parse_shard(value: str | None) -> tuple[int, int] | None:
    """`"2/6"` → `(2, 6)`. 비어 있으면 나누지 않는다(`None`).

    잘못된 값은 조용히 넘기지 않는다. 오타 하나로 묶음이 전부를 돌거나 아무것도 돌지
    않으면, 잡은 초록인데 테스트는 빠진 상태가 된다.
    """
    if value is None or not value.strip():
        return None
    index_text, sep, total_text = value.strip().partition("/")
    if not sep or not index_text.isdigit() or not total_text.isdigit():
        raise ValueError(f"{ENV_VAR} 는 '<묶음 번호>/<묶음 수>' 여야 합니다: {value!r}")
    index, total = int(index_text), int(total_text)
    if total < 1 or not 1 <= index <= total:
        raise ValueError(f"{ENV_VAR} 의 묶음 번호는 1 이상 묶음 수 이하여야 합니다: {value!r}")
    return index, total


def assign_shards(weights: Mapping[str, int], total: int) -> dict[str, int]:
    """파일마다 묶음 번호(1 부터)를 정한다.

    무게(테스트 수)가 큰 파일부터, 그때까지 가장 가벼운 묶음에 넣는다. 테스트 수가
    실행 시간과 정확히 비례하지는 않지만, 이름순으로 자르는 것보다 묶음 길이가 훨씬
    고르다 — 같은 기능의 무거운 파일들이 이름이 비슷해 한 묶음에 몰리기 때문이다.

    무게가 같으면 이름순, 가벼운 묶음이 여럿이면 번호가 작은 쪽이다.
    """
    if total < 1:
        raise ValueError(f"묶음 수는 1 이상이어야 합니다: {total}")
    loads = [0] * total
    assignment: dict[str, int] = {}
    for name in sorted(weights, key=lambda n: (-weights[n], n)):
        lightest = min(range(total), key=lambda i: (loads[i], i))
        assignment[name] = lightest + 1
        loads[lightest] += weights[name]
    return assignment
