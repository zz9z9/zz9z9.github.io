

```
.
├── gradlew
├── gradlew.bat
├── settings.gradle(.kts)
├── sub-project-1
│   └── build.gradle(.kts)
├── sub-project-2
│   └── build.gradle(.kts)
└── sub-project-3
    └── build.gradle(.kts)
```


The Gradle community has two standards for multi-project build structures:

1. Multi-Project Builds using buildSrc - where buildSrc is a subproject-like directory at the Gradle project root containing shared build logic.

2. Composite Builds including build-logic - a build that includes other builds where build-logic is a build directory at the Gradle project root containing reusable build logic.

In either case, the build-logic and buildSrc folders are used to organize build logic.

Each approach has trade-offs. buildSrc is easier to get started with but less flexible.
Composite builds require a bit more setup but scale better and align with Gradle’s long-term best practices for sharing build logic.



![img.png](img.png)


## Multi-Project Paths
---

A project path has the following pattern: it starts with an optional colon, which denotes the root project.

The root project, :, is the only project in a path not specified by its name. The rest of a project path is a colon-separated sequence of project names, where the next project is a subproject of the previous project:

- You can see the project paths when running `gradle projects:`

```
------------------------------------------------------------
Root project 'project'
------------------------------------------------------------

Root project 'project'
+--- Project ':sub-project-1'
\--- Project ':sub-project-2'
```

### Executing tasks by name
The command gradle test will execute the test task in any subprojects relative to the current working directory that has that task.

If you run the command from the root project directory, you will run test in sub-project-1, sub-project-2, and sub-project-3.

The basic rule behind Gradle’s behavior is to execute all tasks down the hierarchy with this name. And complain if there is no such task found in any of the subprojects traversed.

Some task selectors, like help or dependencies, will only run the task on the project they are invoked on and not on all the subprojects to reduce the amount of information printed on the screen.

### Executing tasks by fully qualified name
- In a multi-project build, you can run tasks for a specific subproject by using the task’s fully qualified name. This name combines the project path and the task name.

- For example, to run the build task in sub-project-1, use ./gradlew :sub-project-1:build. This ensures that only sub-project-1’s `build task is executed, rather than running build across the entire build.

- You can use this pattern for any task.
- For example, to list all tasks available in sub-project-3, run ./gradlew :sub-project-3:tasks.

## Multi-Project Builds using buildSrc
---
- Multi-project builds allow you to organize projects with many modules, wire dependencies between those modules, and easily share common build logic amongst them.
- For example, if the project above had common build logic between sub-project-1, sub-project-2 and sub-project-3, it could be structured as follows:

```
.
├── gradlew
├── gradlew.bat
├── settings.gradle(.kts)
├── buildSrc
│   ├── build.gradle.kts
│   └── src/main/*/shared-build-conventions.gradle(.kts)
├── sub-project-1
│   └── build.gradle(.kts)
├── sub-project-2
│   └── build.gradle(.kts)
└── sub-project-3
    └── build.gradle(.kts)
```


Gradle recognized buildSrc folder
Contains common build logic from sub-project-1, sub-project-2 and sub-project-3
Applies shared-build-conventions.gradle(.kts)
The buildSrc directory is automatically recognized by Gradle. It is a good place to define and maintain shared configuration or imperative build logic, such as custom tasks or plugins.

buildSrc is automatically included in your build as a special subproject if a build.gradle(.kts) file is found under buildSrc.

buildSrc 상세 : https://docs.gradle.org/current/userguide/sharing_build_logic_between_subprojects.html#sharing_build_logic_between_subprojects

## Composite Builds including build-logic
---

- Composite Builds, also referred to as included builds, are best for sharing logic between builds (not subprojects) or isolating access to shared build logic.

## 루트 모듈 ?
---

Gradle 멀티 모듈 구조는 다음과 같은 개념으로 동작합니다:

- **하나의 루트 빌드가 전체 모듈을 관리한다.**

- 각 서브 모듈은 루트의 Gradle Wrapper(gradlew)를 통해 빌드된다.
- 빌드 실행 시 항상 루트의 settings.gradle을 기준으로 프로젝트 전체가 구성된다.
  - Gradle의 멀티 모듈 프로젝트는 개별 모듈(API, core, batch)을 각각 독립된 프로젝트로 취급하는 게 아니라, **하나의 “빌드 단위"**로 묶어서 관리하는 구조입니다.
  - 이를 위해 루트에 하나의 settings.gradle 파일이 필요합니다.
  - settings.gradle은 Gradle에게 다음을 알려줍니다:
    - 어떤 모듈들이 포함되었는지
    - 각각을 어떻게 연결할지
    - 전체 빌드 그래프를 어떻게 구성할지

- 즉, 루트가 없으면 Gradle은 “어떤 모듈이 프로젝트에 포함되는지” 알 수 없습니다.
- 어떤 모듈을 빌드하더라도 실행은 다음처럼 루트에서 해야 합니다:

```
./gradlew :api:build
./gradlew :core:test
./gradlew build   # 전체 빌드
```

### 하나의 빌드 ?

멀티 모듈 프로젝트에서 하나의 빌드라는 건 다음을 의미한다:

전체 프로젝트(api / core / batch)를 **하나의 Gradle 빌드 단위(Build Graph)로 묶어서 실행**한다는 뜻이다.

즉, Gradle 입장에서는 전체 프로젝트가 “한 번에 정의된 하나의 큰 빌드”이며, 그 내부에 여러 모듈(tasks)이 있을 뿐인 형태야.

Gradle 빌드 그래프(Build Graph)

Gradle은 루트 프로젝트와 모든 서브 프로젝트를 읽어서 다음과 같은 빌드 그래프를 만든다:

예시:
```
:core:compileJava
:core:jar
:api:compileJava (core를 먼저 빌드해야 함)
:api:jar
:batch:compileJava
:batch:jar
```
Gradle은 이 전체 트리를 “하나의 빌드”로 인식하고 다음처럼 동작함:

build 명령을 루트에서 한 번 실행하면

Gradle은 어떤 모듈이 먼저 빌드되어야 하는지 계산하고

의존 순서대로 모든 모듈을 자동으로 빌드함

즉,

./gradlew build


하나의 명령 → 여러 모듈이 자동으로 빌드

멀티 모듈 = “하나의 공장(빌드) + 여러 라인(모듈)”

하나의 공장에서 여러 생산 라인(API, core, batch)을 동시에 관리하는 것.

라인마다 결과물이 다르지만(각각 jar), 공장은 하나다.

공장을 한 번 가동하면 모든 라인이 돌아간다.

## 장점
---
api와 batch가 core를 공통으로 사용하면:

core 커밋 하자마자 api와 batch 테스트가 동시에 돌아감

버전 충돌 없음 (core-1.0, core-1.1 같은 버전 관리 필요 없음)

core 변경으로 두 서비스 중 하나만 깨지는지 빠르게 확인 가능

즉, 공유 코드 안정성↑, 운영 리스크↓

2) 공통 의존성, 공통 버전 통합 관리

root에서 다음처럼 공통 dependencies 선언 가능:

subprojects {
apply plugin: "java"
dependencies {
implementation("com.fasterxml.jackson.core:jackson-databind:2.17.1")
}
}
core를 별도 artifact로 배포할 필요 없음

만약 멀티 모듈이 아니라면:

core를 별도 repo로 분리해야 하고

core 버전을 배포/업데이트하고

api와 batch에서 그 버전을 맞춰야 하고

버전 충돌을 계속 신경 써야 함

→ 멀티 모듈은 이 모든 귀찮음을 제거해준다.

하나의 gradlew로 전체를 관리 가능

배치는 빌드 잘 되는데 API만 깨지는 상황도 한 번에 확인 가능.
CI/CD에서도 하나의 pipeline로 처리 가능.

하지만, 멀티 모듈을 쓰지 않는 게 더 좋은 경우도 있음

아래 조건이면 멀티 모듈은 오히려 독이 된다.

❌ 1) 서로 완전히 독립된 서비스이고, 공유 코드가 없다

서로 아무 관계 없는 서비스 2개를 억지로 멀티 모듈로 묶는 건 좋지 않다.

❌ 2) core를 공유하지 않고, REST API나 gRPC로만 통신한다

서비스별 독립 배포가 중요한 경우는 별도 레포가 맞다.

❌ 3) 팀 구조가 서비스별로 완전히 분리돼 있다

각 서비스가 단독으로 개발·릴리즈해야 한다면 모노레포/멀티 모듈은 오히려 속도 저하.


멀티 모듈의 장점 중 하나는 다음과 같습니다:

공통된 dependency 관리

공통된 플러그인 적용

동일한 Gradle 버전 사용

동일한 빌드 로그/출력 구조 가짐

예를 들어, 모든 모듈( api / batch / core )에서 Spring Boot 버전을 일관되게 유지하려면 루트 build.gradle에서 관리해야 합니다:

subprojects {
apply plugin: "java"
group = "com.example"
version = "1.0.0"

    dependencies {
        implementation("org.springframework.boot:spring-boot-starter")
    }
}


루트 모듈이 없다면 각 모듈이 서로 다른 설정을 가져갈 수밖에 없습니다 → 멀티 모듈의 장점이 사라짐.
## 실습
---
- 모듈 추가
![img_1.png](img_1.png)


- 루트 모듈 `settings.gradle`
```
rootProject.name = 'multi-module-service'
include('api', 'batch', 'core')
```

```
Task 'wrapper' not found in project ':web'.

* Try:
> Run gradle tasks to get a list of available tasks.
> For more on name expansion, please refer to https://docs.gradle.org/8.14/userguide/command_line_interface.html#sec:name_abbreviation in the Gradle documentation.
> Run with --stacktrace option to get the stack trace.
> Run with --info or --debug option to get more log output.
> Run with --scan to get full insights.
> Get more help at https://help.gradle.org.
BUILD FAILED in 210ms
```

![img_2.png](img_2.png)

=> web을 spring boot generator로 생성하면, 이런식으로 세팅됨
=> web 디렉토리에 Gradle root 프로젝트의 모든 흔적(gradlew, settings.gradle, gradle/, build.gradle 등)이 존재하기 때문에 IntelliJ가 web을 “독립된 Gradle 프로젝트”라고 자동 인식하게됨

즉, web은 서브 모듈처럼 보이지만 사실상 완전히 별도 프로젝트로 구성되어 있기 때문에 IntelliJ의 Gradle 패널에 자동으로 잡힌 것.

Gradle 프로젝트 구조는 다음 4개만 있으면 무조건 독립 프로젝트로 간주됨:
build.gradle
settings.gradle
gradlew
gradle/wrapper 디렉토리

- src, build.gradle만 남기고 다 삭제
- Unlink Gradle Project

![img_3.png](img_3.png)

- include에 web 포함

![img_4.png](img_4.png)


## git 서브모듈
---

git submodule add https://github.com/zz9z9/common-submodule.git common


submodule 추가 후 해야 할 Gradle 설정

루트 settings.gradle에서:

include("core")
project(":core").projectDir = file("core")

그러면 core가 정상적인 Gradle 서브모듈처럼 동작함.

```
rootProject.name = 'multi-module-service'
include('api', 'batch', 'web', 'core', 'common')
project(":common").projectDir = file("common")
```

```
git submodule add https://github.com/zz9z9/common-submodule.git common  128 ↵  2007  00:41:18 '/Users/jeayoon/dev/src/multi-module-service/common'에 복제합니다... Username for 'https://github.com': zz9z9 Password for 'https://zz9z9@github.com': remote: Invalid username or token. Password authentication is not supported for Git operations. fatal: Authentication failed for 'https://github.com/zz9z9/common-submodule.git/' fatal: 'https://github.com/zz9z9/common-submodule.git'에서 하위 모듈 경로 '/Users/jeayoon/dev/src/multi-module-service/common'에 복제하는데 실패했습니다 비밀번호 제대로 입력했는데 이렇게뜬다.
```

=> 토큰 인증 등 설정필요 ?

GitHub는 더 이상 비밀번호 인증을 지원하지 않는다. (2021년 이후 전면 중단)
그래서 아무리 비밀번호를 정확히 입력해도 아래 오류가 무조건 발생한다:

Password authentication is not supported for Git operations.
fatal: Authentication failed


2차 인증(OTP, MFA)이 있어서가 아니라,
GitHub는 더 이상 ID/Password 방식의 git access 자체를 막아놨기 때문이다.

🟩 해결 방법 (3가지 중 하나 선택)

GitHub repository를 clone/submodule 하려면 아래 방식 중 하나를 사용해야 한다:

✅ 해결 방법 1: Personal Access Token(PAT) 사용 (가장 많이 사용함)

패스워드 자리에 “비밀번호”가 아니라
Personal Access Token을 넣어야 한다.

1) 토큰 생성 방법

GitHub → Settings → Developer settings → Tokens → "Fine-grained tokens" 또는 "Classic token"

권한:

repo (필수)

(private repo라면 repo 권한 반드시 필요)

2) git submodule add 실행
   git submodule add https://github.com/zz9z9/common-submodule.git common


Username 입력 → GitHub 계정 ID
Password 입력 → 토큰

토큰은 보통 이런 형태임:

ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx


여기까지 하면 해결됨.

✅ 해결 방법 2: SSH 주소로 submodule 추가 (더 깔끔함)

이미 SSH 키 등록해두었다면
HTTPS 대신 SSH URL을 써야 한다.

git submodule add git@github.com:zz9z9/common-submodule.git common


SSH 방식은:

토큰 필요 없음

비밀번호 입력 없음

GitHub MFA 상관없음

가장 안정적인 방식

SSH 키가 등록되어 있다면 바로 동작하고,

없다면 아래처럼 등록해야 함:

ssh-keygen -t rsa -b 4096 -C "you@example.com"
cat ~/.ssh/id_rsa.pub


GitHub → Settings → SSH and GPG keys → Add new SSH key

✅ 해결 방법 3: Git credential manager 설정

맥이라면 두 번째로 간단한 방법:

brew install gh
gh auth login


GitHub CLI로 로그인하면
git submodule add 시 자동 인증됨.

🟥 정리하자면
❌ GitHub는 비밀번호로 git 접근을 지원하지 않음
❌ MFA 여부와 관계없이 비밀번호 로그인은 100% 실패함
✔ PAT 또는 SSH 키로 인증해야만 GitHub submodule 추가 가능함
🟦 가장 추천하는 방식

당신이 AWS 운영 환경도 함께 고려해야 한다면:

👉 SSH 방식 권장
git submodule add git@github.com:zz9z9/common-submodule.git common


이유:

로컬/CI/CD 환경에서 토큰 관리 필요 없음

보안적 이점 큼

GitHub MFA와 충돌 없음

매번 토큰 입력할 필요 없음

### 커밋 ?
가져온 곳에서 commit한거 submodule 플젝에 반영 가능?

submodule은 사실 "그 repo의 특정 commit을 checkout 해둔 폴더"임.

그래서 부모 repo는 딱 이것만 기억함:

core → commit 7a3fd90 (submodule repo의 특정 커밋)


그래서 core 내부에서 commit을 새로 만들면
새 commit이 생기는 거고, 부모 repo는:

core → commit 9f3a122 (업데이트됨)


이걸 다시 저장해줘야 함.

## submodule 말고
---

core를 별도 Gradle Composite Build로 포함

Gradle의 정식 기능인데 매우 강력함.

❗ 특징

라이브러리처럼 사용되는데,

빌드 시 코드가 로컬에서 바로 컴파일됨

nexus 필요 없음

submodule 필요 없음

📌 설정 방법
1) settings.gradle에 composite build 추가
   includeBuild('../core')


이렇게 하면 core는 독립적인 Gradle 프로젝트인데, main 프로젝트는 이를 로컬 라이브러리처럼 가져다 씀.

2) main build.gradle에서 의존성 추가
   dependencies {
   implementation("com.example:core")
   }


이렇게 하면 core를 jar처럼 dependency 추가한 것처럼 동작하지만, 사실은 로컬 build다.

🔥 세 방식 비교
방식	nexus 필요?	업데이트 용이성	원본 repo에 push	복잡도	추천도
Git subtree	❌ 없음	👍 쉬움	👍 가능	⭐ 중간	⭐⭐⭐⭐⭐
vendor-in(복사)	❌ 없음	❌ 어려움	❌ 불가능	⭐ 쉬움	⭐⭐
Gradle Composite Build	❌ 없음	👍 쉬움	가능하긴 함	⭐ 조금 어려움	⭐⭐⭐⭐
🏆 결론 – 사내 Nexus 접근 불가 상황에서는?
👉 최고의 실전 선택 = Git subtree 또는 Gradle Composite Build
⭐ subtree 추천 이유

관리 편함(submodule처럼 귀찮은 것 없음)

코드 공유 가능

push/pull 둘 다 쉬움

실제 운영에서 submodule보다 훨씬 인기 많음

⭐ composite build 추천 이유

멀티모듈처럼 행동함

gradle native 기능이라 안정적

원본 repo push 가능

⛔ git submodule은 추천하지 않는 이유

detached HEAD 문제

push 어렵고 실수 빈번

CI/CD에서 문제 많이 발생

팀원마다 clone/init 문제 잦음

## 기술 블로그 참고
> https://engineering.linecorp.com/ko/blog/mono-repo-multi-project-gradle-plugin
