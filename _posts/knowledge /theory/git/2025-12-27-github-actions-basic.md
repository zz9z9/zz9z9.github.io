---
title: Github Actions - 기초 개념
date: 2025-12-27 00:00:00 +0900
categories: [지식 더하기, Git & Github]
tags: [Github]
---

## Github Actions
---
> GitHub Actions는 빌드, 테스트, 배포 파이프라인을 자동화할 수 있게 해주는 **CI/CD 플랫폼**

- 리포지토리에 들어오는 모든 PR에 대해 빌드·테스트를 수행하는 워크플로우를 만들 수 있고, 머지된 PR을 운영 환경에 배포하는 워크플로우도 만들 수 있다.
- GitHub Actions는 단순한 DevOps를 넘어, **리포지토리에서 발생하는 다양한 이벤트에 반응**해 워크플로우를 실행할 수 있다.
  - 예를 들어, 누군가 새 이슈를 만들면 자동으로 적절한 라벨을 붙이는 워크플로우를 실행할 수 있다.

- GitHub는 워크플로우 실행을 위해, Linux / Windows / macOS **가상 머신**을 제공한다.
- 직접 관리하는 runner(self-hosted runner)를 데이터센터나 클라우드에 둘 수도 있다.

## 구성 요소
---

### Workflow
> 하나 이상의 Job을 실행하는 설정 가능한 자동화 프로세스

- 워크플로우는 리포지토리에 커밋된 YAML 파일로 정의된다.
  - `.github/workflows/*.yml`

- 하나의 리포지토리는 여러 개의 워크플로우를 가질 수 있다.

- 워크플로우 실행 방법:
  - 이벤트 발생 시
  - REST API 호출
  - 수동 실행
  - 스케줄(cron)

- 한 워크플로우에서 다른 워크플로우를 재사용할 수도 있다.

### Events
> 워크플로우 실행을 트리거하는 리포지토리 내 특정 활동

- 예: PR 생성, 이슈 생성, 커밋 푸시

### Jobs
> 같은 Runner에서 실행되는 Step들의 묶음

- Job들은 순차 실행 또는 병렬 실행이 가능하다.
- 각각의 Job은 자신만의 Runner(VM) 또는 컨테이너 환경에서 실행된다.

- Job은 하나 이상의 Step으로 구성되며, Step은 직접 정의한 **쉘 스크립트 실행 또는 미리 만들어진 Action 실행** 중 하나다.
- Step은 순서대로 실행되며, 이전 Step 결과에 의존한다.
  - ex : 애플리케이션 빌드 Step -> 빌드 결과물을 테스트하는 Step
  - 같은 Runner에서 실행되기 때문에, Step 간에 데이터 공유가 가능하다.

- Job들간의 의존성을 설정할 수 있다.

### Actions
> 워크플로우 안에서 특정 작업을 수행하는 미리 정의된 재사용 가능한 코드 묶음

- 워크플로우 파일에서 중복 코드를 줄여준다.
- 직접 Action을 만들 수도 있고, GitHub Marketplace에 있는 Action을 사용할 수도 있다.
- 예:
  - `actions/checkout`
  - `actions/setup-java`

- `actions/checkout`
  - [https://github.com/marketplace/actions/checkout](https://github.com/marketplace/actions/checkout)
  - GitHub Actions에서 Runner는 빈 VM으로 시작
  - 그래서 빌드 / 테스트 / 패키징을 하려면, 소스 코드를 먼저 가져와야 함

```
# 이걸 Action으로 캡슐화해 둔 것
git clone https://github.com/org/repo.git
cd repo
git checkout main
```

- `actions/setup-java`
  - [https://github.com/marketplace/actions/setup-java-jdk](https://github.com/marketplace/actions/setup-java-jdk)
  - Runner는 기본 OS만 있을 뿐이고 Java 버전은 보장되지 않음 또는 프로젝트 요구와 다를 수 있음
  - 따라서:
    - 지정한 Java 배포판 설치
    - JAVA_HOME 설정
    - PATH에 java/bin 등록 필요

```
# 이걸 Action으로 캡슐화해 둔 것
apt install openjdk-21-jdk
export JAVA_HOME=/usr/lib/jvm/java-21
java -version
```

### Runners
> 워크플로우를 실제로 실행하는 서버

- 하나의 Runner는 한 번에 하나의 Job만 실행한다.
- GitHub-hosted Runner의 경우, 매 실행마다 완전히 새 VM이 생성된다.

## 참고 자료
---

- [https://docs.github.com/en/actions/get-started/understand-github-actions](https://docs.github.com/en/actions/get-started/understand-github-actions)
