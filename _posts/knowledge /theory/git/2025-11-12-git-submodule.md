---
title: Git - Submodule 알아보기
date: 2025-11-12 22:25:00 +0900
categories: [지식 더하기, 이론]
tags: [Git]
---

## 배경
---
> AWS 환경에서 운영시 사내 nexus를 사용할 수 없어서, common 모듈 같은 공통 모듈을 별도 프로젝트로 관리하고, git submodule로 포함시킨다는데 이게 어떤 의미일까 ?

- 보통 사내에서 빌드된 공통 라이브러리(common module)는 Nexus (또는 Artifactory) 같은 **사설 Maven Repository**에 업로드
- 다른 프로젝트에서는 의존성으로 이렇게 불러온다.

```
dependencies {
    implementation 'com.company:common:1.2.3'
}
```

- 이렇게 하면 빌드 시 Gradle/Maven이 Nexus에서 jar를 받아온다.
- 그런데 AWS 환경에서는 종종 다음과 같은 이유로 사내 Nexus에 접근이 불가능할 수 있다:
  - AWS VPC 내부망에서 사내망(Nexus 서버) 으로 직접 접근이 차단됨
  - VPN 연결 없이 외부망(AWS)에서 내부망(Nexus)에 접근 불가
  - Nexus 서버가 프라이빗 네트워크에 있고, 인터넷에 노출되지 않음
- 즉, 의존성 아티팩트를 원격 Repository에서 받을 수 없는 상황이 된다.

**※ Nexus ?**
> [Sonatype Nexus Repository](https://www.sonatype.com/products/sonatype-nexus-repository)는 빌드 결과물(예: jar, war, npm 패키지, Docker 이미지 등)을
중앙에서 저장하고 배포할 수 있게 해주는 Artifact Repository(아티팩트 저장소)
> 즉, Maven Central이나 npmjs.org 같은 공용 저장소의 사내 버전

- 필요성
  - 여러 프로젝트에서 공통 라이브러리(core, util 등) 사용
  - 외부 네트워크 접근이 제한된 환경 (AWS VPC, 내부망 등)
  - 회사 내부 전용 라이브러리 (보안상 외부에 공개 불가)
  - 그래서 “사내 전용 Maven Central” 같은 서버가 필요

| 역할                   | 설명                                                                           |
| -------------------- | ---------------------------------------------------------------------------- |
| **Artifact 저장소**     | 빌드 결과물(JAR, WAR, ZIP, Docker 이미지 등)을 업로드(Publish)하고 다른 프로젝트에서 다운로드(Fetch) 가능 |
| **사설 Repository 관리** | 외부 공개 불가능한 내부용 라이브러리를 보관                                                     |
| **Proxy Cache**      | Maven Central, npm registry 등의 캐시 프록시 역할 (외부 패키지를 한 번 받아두면 내부에서 빠르게 재사용 가능)  |
| **버전 관리**            | 아티팩트의 버전을 `1.0.0`, `1.0.1`, `SNAPSHOT` 등으로 관리                                |
| **권한 관리**            | LDAP, SSO 연동으로 팀별 접근 권한 제어 가능                                                |

- AWS 환경에서는 Nexus 대신 AWS CodeArtifact(AWS 관리형 Nexus 같은 서비스)가 같은 역할을 한다.

## Git Submodule
---
> 하나의 Git 저장소 안에 다른 Git 저장소를 하위 디렉터리로 포함시키는 기능

```
main-repo/
├── .gitmodules
├── app/
└── common-lib/   ← 다른 Git 저장소 (submodule)
```

### 주요 특징

| 항목                   | 설명                                                                      |
| -------------------- |-------------------------------------------------------------------------|
| **독립 버전 관리**         | Submodule은 자체 Git 히스토리를 가지고 있어요. 부모 저장소와 별도로 커밋, 푸시 가능.                 |
| **특정 커밋 고정**         | 부모 저장소는 submodule의 **“브랜치”가 아니라 “특정 커밋 SHA”를 참조**합니다.                   |
| **업데이트는 수동**         | submodule 쪽에서 변경이 있어도, 부모 저장소에서는 `git submodule update`로 직접 갱신해야 반영됩니다. |
| **`.gitmodules` 파일** | submodule 경로와 원격 저장소 URL을 관리하는 설정 파일입니다.                                |


### 멀티모듈 프로젝트와의 차이

| 비교 항목         | **Git Submodule**            | **멀티모듈 프로젝트 (예: Gradle, Maven 등)**                       |
| ------------- | ---------------------------- | -------------------------------------------------------- |
| **소스 관리 단위**  | 각 모듈이 **서로 다른 Git 저장소**      | 하나의 **Git 저장소 안에 여러 모듈**                                 |
| **버전 관리**     | 각 모듈은 자체 버전, 커밋 히스토리를 가짐     | 전체가 한 커밋 단위로 버전 관리됨                                      |
| **의존성 연결 방식** | Git 커밋 기반 링크 (`.gitmodules`) | 빌드 시스템(Gradle, Maven)의 `settings.gradle`이나 `pom.xml`로 연결 |
| **업데이트 방식**   | 수동으로 `git submodule update`  | 자동으로 같은 브랜치/커밋 기준에서 빌드                                   |
| **빌드 통합성**    | 독립적 빌드, 통합 자동화 어려움           | 전체 프로젝트를 한 번에 빌드 가능                                      |
| **주 사용 목적**   | 외부 공용 라이브러리나 공통 모듈 재사용       | 대규모 단일 프로젝트를 논리적으로 분리                                    |

### 장/단점

| 구분  | 내용                                                                                                                           |
| --- |------------------------------------------------------------------------------------------------------------------------------|
| 장점  | - Nexus가 없어도 공통 모듈 사용 가능<br>- 각 모듈의 버전을 Git 커밋으로 고정 가능<br>- 별도 jar 배포 없이 코드 동기화 가능                                           |
| 단점 | - submodule 업데이트를 수동으로 해야 함 (`git submodule update`)<br>- 여러 프로젝트가 같은 submodule을 쓰면 버전 동기화가 번거로울 수 있음<br>- 빌드 시스템 통합 관리가 어려움 |


## 적용
---

- 디렉토리 구조

```
repo1/
├── .gitmodules
├── api/
├── admin/
├── web/
└── core/   ← submodule (repo2)
```

- 명령어

```
# repo1에서 core 모듈(submodule) 추가
# 즉, repo1은 core 저장소의 특정 커밋 SHA를 기록 (.gitmodules 파일과 내부 .git/config에 저장됨)
git submodule add https://github.com/company/repo2.git core

# 서브모듈 초기화 및 업데이트
git submodule init
git submodule update
```

- `repo1/settings.gradle`

```
include(":api", ":admin", ":web", ":core")
project(":core").projectDir = file("core")
```

- `repo1/build.gradle`

```
dependencies {
    implementation project(":core")
}
```

- core 코드는 같은 워크스페이스에 존재하므로, AWS 환경에서도 별도 Nexus 없이 빌드 가능해진다.
