"""요청을 보낸 클라이언트 IP. (#2815)

rate limit 키와 감사 로그 IP 는 **이 함수 하나**로 정한다. 둘이 다른 방법으로
IP 를 읽으면 한쪽은 막히고 다른 쪽 기록은 위조되는 식으로 어긋난다.

`X-Forwarded-For` 는 요청자가 아무 값이나 넣을 수 있다. 믿을 수 있는 것은 우리
앞단 프록시가 **덧붙인** 값뿐이고, 프록시는 자기가 본 주소를 오른쪽 끝에 붙인다.
그래서 앞단 프록시 수(`trusted_proxy_hops`)만큼 오른쪽에서 센 값을 클라이언트
IP 로 본다. 요청자가 왼쪽에 무엇을 써 넣든 결과가 바뀌지 않는다.

- 홉 수 0: 헤더를 보지 않고 소켓 주소(`request.client.host`)를 쓴다. 프록시 없이
  직접 받는 로컬·테스트가 이쪽이다.
- 홉 수 N: 헤더 값이 N 개보다 적으면 프록시를 거치지 않은 요청이라 소켓 주소를 쓴다.

uvicorn `--proxy-headers` 가 고치는 `request.client.host` 에 기대지 않는 이유:
`--forwarded-allow-ips="*"` 이면 uvicorn 은 헤더의 **왼쪽 첫 값**(요청자가 쓴 값)을
그대로 소켓 주소로 바꾼다. 관리형 로드 밸런서(ECS Express Mode 의 ALB 등)처럼 프록시
주소 대역이 고정되지 않은 플랫폼에서는 그 값을 좁힐 수 없어, 앱이 직접 오른쪽에서 센다.
"""
from __future__ import annotations

import logging

from starlette.requests import HTTPConnection

from app.core.config import Settings, get_settings

log = logging.getLogger(__name__)

#: 감사 로그 `ip` 칸 길이에 맞춘 상한.
MAX_IP_LENGTH = 64


def _forwarded_chain(request: HTTPConnection) -> list[str]:
    """`X-Forwarded-For` 값을 왼쪽부터 순서대로. 헤더가 여러 줄이면 이어 붙인다."""
    chain: list[str] = []
    for raw in request.headers.getlist("x-forwarded-for"):
        chain.extend(part.strip() for part in raw.split(",") if part.strip())
    return chain


def client_ip(request: HTTPConnection, settings: Settings | None = None) -> str:
    """rate limit·감사 로그가 쓰는 클라이언트 IP. 알 수 없으면 빈 문자열."""
    hops = (settings or get_settings()).effective_proxy_hops
    if hops > 0:
        chain = _forwarded_chain(request)
        if len(chain) >= hops:
            return chain[-hops][:MAX_IP_LENGTH]
    return (request.client.host if request.client else "")[:MAX_IP_LENGTH]


def warn_if_untrusted_setup(settings: Settings | None = None) -> None:
    """운영에서 클라이언트 IP 를 소켓 주소로 읽도록 설정됐으면 기동 로그에 남긴다.

    프록시 뒤인데 홉 수가 0 이면 모든 요청이 프록시 주소 하나로 보여, IP 단위
    한도가 사용자 전체에 한꺼번에 걸린다.
    """
    s = settings or get_settings()
    if s.is_prod and s.effective_proxy_hops == 0:
        log.warning(
            "TRUSTED_PROXY_HOPS=0 — 운영에서 클라이언트 IP 를 소켓 주소로 읽습니다. "
            "프록시 뒤라면 rate limit 이 프록시 주소 하나로 묶입니다."
        )
