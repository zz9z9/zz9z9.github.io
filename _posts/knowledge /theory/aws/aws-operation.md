
## 구성요소

Docker — 애플리케이션을 상자로 만든다

Docker는:

“내 앱을 어떤 환경에서도 같은 방식으로 돌아가게 하는 컨테이너(상자)”

예)

Java 설치 필요 없음

OS 설정 필요 없음

JAR만 넣어서 Dockerfile로 이미지 만들면 끝

🟧 AWS ECR — Docker 이미지 저장소

ECR은:

“Docker 용 Nexus”

Docker 이미지 저장하는 곳
→ GitHub Actions가 만든 Docker 이미지를 ECR에 push 함

🟦 AWS ECS — 컨테이너 실행 서비스

ECS는:

“Docker 컨테이너를 자동으로 배포/실행/관리해주는 서비스”

역할:

ECR에서 이미지 받아옴

컨테이너 실행

헬스체크로 문제가 있으면 자동 재시작

무중단 배포(Blue/Green) 가능

컨테이너를 여러 개로 늘려서 트래픽 처리 가능

운영 서버에 SSH로 접속할 필요 없음
ECS가 스스로 관리함

🟩 GitHub Actions — CI/CD 자동화

GitHub Actions는:

“Jenkins 대신 GitHub이 제공하는 빌드 서버”

장점:

별도 Jenkins 서버 필요 없음

Docker 빌드 + ECR push + ECS 배포까지 자동화 가능

GitHub에 push하면 자동으로 시작됨


### 현재 방식 vs Docker/ECS 방식 비교


```
[로컬 개발]
      ↓
   GitHub
      ↓
[Jenkins - CI]
  - 코드 체크아웃
  - Maven/Gradle 빌드
  - 유닛 테스트
  - 정적 분석(Optional)
      ↓
[Jenkins - CD]
  - JAR 생성
  - 배포 서버로 파일 전송
  - SSH로 배포 스크립트 실행
      ↓
[운영 서버(Spring Boot / Tomcat)]
```

```
[로컬 개발]
      ↓
    GitHub
      ↓
[GitHub Actions - CI]
  - 코드 체크아웃
  - 테스트 실행
  - 빌드
  - Lint/정적 분석(Optional)
      ↓
[GitHub Actions - CD]
  - Docker 이미지 빌드
  - ECR에 Push
  - ECS 서비스 업데이트 트리거
      ↓
[ECS가 컨테이너 실행 / 교체]
      ↓
[운영 서버(컨테이너)]
```

| 항목               | 현재 방식 (Jenkins + JAR) | Docker/ECS 방식                 |
| ---------------- | --------------------- | ----------------------------- |
| **빌드 위치**        | Jenkins 서버            | GitHub Actions                |
| **빌드 결과물**       | JAR 파일                | Docker 이미지 (컨테이너)             |
| **배포 방식**        | 서버에 JAR 복사 + 스크립트로 실행 | ECS가 컨테이너 이미지 가져와 자동 배포       |
| **배포 대상**        | 물리/VM 서버              | ECS 컨테이너(Task)                |
| **버전 관리**        | JAR 파일 버전             | Docker 이미지 태그                 |
| **운영 서버 의존성**    | Java 버전/OS 설정 다 맞아야 함 | 모두 Docker 이미지에 포함되어서 의존성이 사라짐 |
| **확장성(스케일링)**    | 수동으로 서버 늘림            | ECS가 자동으로 컨테이너 늘림             |
| **무중단 배포**       | 직접 스크립트 짜야 함          | ECS Blue/Green 자동 지원          |
| **Rollback**     | 수동 rollback           | 이전 이미지 태그로 자동 rollback        |
| **CI/CD 구성 난이도** | Jenkins를 직접 운영해야 함    | GitHub Actions에서 YAML만 작성하면 됨 |

| 구분           | 기존 방식                 | Docker/ECS 방식                         |
| ------------ | --------------------- | ------------------------------------- |
| **CI 실행 위치** | Jenkins 서버            | GitHub Actions                        |
| **CI 내용**    | Maven/Gradle 빌드 + 테스트 | Docker build 포함한 전체 테스트               |
| **CD 실행 위치** | Jenkins → SSH 배포 스크립트 | GitHub Actions → ECR push → ECS 자동 배포 |
| **배포 대상**    | OS 서버 + JAR           | Docker 컨테이너                           |
| **롤백**       | 직접 수동                 | ECS가 기존 이미지로 자동 롤백                    |

새 방식의 핵심

“JAR 배포”에서 → “Docker Image 배포”로 전환

직접 운영 서버 접속 → ❌

배포 스크립트 직접 실행 → ❌

ECS가 자동으로 배포/롤백 → ⭕

GitHub Actions가 CI/CD 서버 → ⭕

서버 의존성 문제 0 → ⭕

확장성 + 장애 복구 자동화 → ⭕


## 멀티모듈 vs 프로젝트 분리


Docker + GitHub Actions + ECS 같은 클라우드·컨테이너 기반 환경에서는 멀티모듈 사용이 확실히 ‘줄어든다’.
하지만 완전히 안 쓰는 것도 아니고, 상황에 따라 선택이 달라져.

아주 명확히 정리해줄게.

🟦 1. 왜 기존 환경에서는 멀티모듈을 많이 썼을까?

기존(Jenkins + JAR 직접 배포) 환경에서 멀티모듈을 많이 쓴 이유는:

공통 모듈(core)을 여러 서비스(api/admin/batch)가 공유해야 했고

하나의 프로젝트 안에 있는 게 빌드/버전 관리/배포가 쉽기 때문

즉,

parent
├─ core
├─ api
├─ admin
├─ batch


이런 식으로 해서 전체를 한 번에 빌드 → 각각 JAR 만들어 배포하는 패턴.

🟩 2. 그런데 Docker 기반에서는 왜 멀티모듈을 덜 쓸까?

Docker + ECS 같은 환경에서는 서비스가 각각 독립적인 컨테이너가 됨.

즉,

“서비스 = 컨테이너 = 하나의 독립된 배포 단위”

가 되는 것.

예를 들어:

API → 하나의 컨테이너

ADMIN → 하나의 컨테이너

BATCH → 하나의 컨테이너

각각 별도로 빌드/배포/롤백된다.

➜ 이러면 멀티모듈 내부에서 한 번에 빌드할 필요가 줄어듦

왜냐면 멀티모듈의 장점(한 번에 전체 빌드 & 패키징)이
컨테이너 환경에서는 오히려 단점이 되기 때문.

🟧 3. Docker 환경에서 멀티모듈이 줄어드는 "실질적인 이유"
✔ 1) 서비스가 각각 독립 빌드 → 멀티모듈이 발목 잡음

ECS는 “하나의 서비스 = 하나의 이미지” 개념

멀티모듈이면 모든 모듈을 매번 함께 빌드해야 함

이건 Docker 이미지 빌드 속도를 크게 느리게 함

✔ 2) core 모듈 같은 공통 라이브러리는 Nexus/ECR에서 버전으로 관리하는 게 일반적

컨테이너 시대에는 공유 기능은 보통:

독립 repo로 운영됨

Maven Central 또는 사내 Nexus/ECR로 배포됨

서비스는 그걸 dependency로 받음

즉 멀티모듈 유지할 이유가 많이 사라짐.

✔ 3) 빌드 캐시 효율성이 떨어짐

Docker 빌드는 레이어 캐시가 핵심인데 멀티모듈이면:

소스 전체가 변경되었는지 판단하기 어렵고

Docker 캐시가 계속 깨짐
→ 매우 비효율적

반면 서비스별 repo로 분리하면:

변경된 서비스만 Docker build

Build 속도 빠름

ECS 배포도 더 가벼움

🟩 4. 그렇다면 멀티모듈은 아예 안 쓰는 걸까? (아님!)
여전히 사용되는 경우가 있음:
① 단일 프로젝트 모노리식 구조

예: 하나의 API 서버 + 내부 기능이 여러 모듈로 나뉨

my-app
├─ core
├─ domain
├─ infrastructure
└─ api


→ 최종적으로 JAR 1개 생성 + Docker 이미지 1개 만들면 OK
→ 이런 구조는 “아키텍처를 정리하는 용도”로 멀티모듈 사용

② 같이 버전 관리하는 라이브러리 묶음

예: 회사 내부 SDK, 인증 라이브러리 등
→ 이런 건 멀티모듈을 유지해도 됨
→ 출시는 Nexus나 internal registry로 진행

🟥 5. 실제 AWS ECS 운영 환경에서는 어떤 방식이 “표준”일까?

98%의 회사는 멀티모듈을 서비스 단위로 완전히 분리한다.

예:

❌ 이전 방식(모놀리식 멀티모듈)
parent
├─ core
├─ api
├─ admin
├─ batch

⭕ 추천 방식(컨테이너 시대)
core-lib       (공통 라이브러리 repo)
api-service    (독립 repo → 독립 Docker image)
admin-service  (독립 repo → 독립 Docker image)
batch-service  (독립 repo → 독립 Docker image)


이게 배포/스케일링/롤백에서 압도적으로 유리함.

🎯 최종 결론
✔ Docker + ECS 환경에서는

→ 멀티모듈을 잘 사용하지 않음

✔ 이유는?

컨테이너는 서비스별로 독립 빌드가 원칙

전부 하나에서 빌드하면 Docker 캐시 깨지고 비효율적

공통 모듈(core)은 Nexus/ECR로 독립 배포하는 것이 표준

서비스 단위로 repo를 분리하는 것이 CI/CD 효율 최고

✔ 예외

단일 애플리케이션 내부 구조 분리는 멀티모듈 유지 가능(모듈형 설계 목적)
