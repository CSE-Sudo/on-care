"""소셜 provider → Verifier 팩토리."""
from __future__ import annotations

from app.services.social.base import SocialVerifier
from app.services.social.google import GoogleVerifier
from app.services.social.kakao import KakaoVerifier
from app.services.social.naver import NaverVerifier

_VERIFIERS: dict[str, type[SocialVerifier]] = {
    "kakao": KakaoVerifier,
    "google": GoogleVerifier,
    "naver": NaverVerifier,
}


def get_verifier(provider: str) -> SocialVerifier:
    cls = _VERIFIERS.get(provider.lower())
    if cls is None:
        raise ValueError(f"지원하지 않는 소셜 provider: {provider}")
    return cls()
