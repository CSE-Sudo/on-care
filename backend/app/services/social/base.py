"""소셜 로그인 검증 추상화.

각 provider(kakao/google/naver/apple)는 SocialVerifier 를 구현해,
클라이언트가 넘긴 토큰을 provider 에 확인하고 정규화된 SocialIdentity 를 돌려준다.
recognizer/embedder 와 동일한 factory 패턴.
"""
from __future__ import annotations

from dataclasses import dataclass


class SocialAuthError(Exception):
    """소셜 토큰 검증 실패(무효 토큰 등). 라우터는 401 로 답한다."""


class SocialProviderResponseError(SocialAuthError):
    """provider 가 약속한 형식이 아닌 응답을 줬다(HTML·깨진 JSON·필드 타입 이상).

    사용자 토큰 문제가 아니라 provider 쪽 문제라 라우터는 502 로 답한다. 인증 실패의
    한 갈래이므로 SocialAuthError 를 상속한다 — 이 예외를 모르는 호출부도 최소한
    인증 실패로는 처리한다.
    """


@dataclass
class SocialIdentity:
    provider: str            # kakao|google|naver|apple
    provider_user_id: str    # provider 내 고유 사용자 id
    email: str = ""
    name: str = ""
    #: provider 가 이 이메일의 소유를 확인했는가(#1551). 참일 때만 같은 이메일의 기존
    #: 계정에 자동으로 연결한다. 확인할 수단이 없는 provider 는 거짓으로 둔다.
    email_verified: bool = False


class SocialVerifier:
    provider: str = ""

    async def verify(self, token: str) -> SocialIdentity:
        raise NotImplementedError
