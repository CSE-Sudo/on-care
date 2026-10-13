# Frontend

On-Care 의 프론트엔드 — **Flutter 로 만든 두 개의 앱**. 트레이너와 회원을 잇는
서비스라 화면을 쓰는 사람이 둘이고, 쓰는 자리도 달라(센터 PC / 개인 휴대폰)
코드베이스를 나눴다. 서로 import 하지 않고 아키텍처 패턴만 미러링한다.

| | 회원 앱 | 트레이너 웹 |
| --- | --- | --- |
| 디렉토리 | [`flutter/`](flutter/) | [`flutter_trainer/`](flutter_trainer/) |
| 개발 가이드 | **[flutter/README.md](flutter/README.md)** | **[flutter_trainer/README.md](flutter_trainer/README.md)** |
| 타깃 | Android · iOS · Web | Web 전용 (센터 PC·태블릿) |
| 라이브 | https://cse-sudo.github.io/on-care/member/ | https://cse-sudo.github.io/on-care/trainer/ |
| CI | [`user-app-ci.yml`](../.github/workflows/user-app-ci.yml) | [`trainer-ci.yml`](../.github/workflows/trainer-ci.yml) |

두 앱이 함께 읽는 것은 **데모 픽스처**([`shared/demo_fixture/`](../shared/demo_fixture/))
하나뿐이다. 나란히 놓고 시연할 때 같은 날짜의 숫자가 어긋나지 않도록 김민수의
하루를 한곳에서 만든다(백엔드 시드도 같은 픽스처를 쓴다).

API 계약은 두 앱과 백엔드가 [`backend/API_CONTRACT.md`](../backend/API_CONTRACT.md)
하나를 본다.
