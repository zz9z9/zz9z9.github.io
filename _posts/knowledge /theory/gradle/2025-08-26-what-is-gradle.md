---
title: Gradle 알아보기
date: 2025-08-26 21:25:00 +0900
categories: [지식 더하기, 이론]
tags: [Gradle]
---

## Gradle 프로젝트 구조
---

```
project
 ├── gradle/                     (1)
 │    ├── libs.versions.toml     (2)
 │    └── wrapper/
 │         ├── gradle-wrapper.jar
 │         └── gradle-wrapper.properties
 │
 ├── gradlew                     (3)
 ├── gradlew.bat                 (3)
 ├── settings.gradle(.kts)       (4)
 ├── subproject-a/
 │    ├── build.gradle(.kts)     (5)
 │    └── src/                   (6)
 └── subproject-b/
      ├── build.gradle(.kts)     (5)
      └── src/                   (6)
```

### (1) : `gradle/`
- Gradle 디렉터리, wrapper 파일과 기타 파일 저장소.

### (2) : `libs.versions.toml`
- Gradle version catalog 파일, 의존성 관리용.
- 라이브러리 버전을 한 곳에서 관리하는 카탈로그.
- 예시:

```
[versions]
spring-boot = "3.2.0"
junit = "5.10.0"

[libraries]
spring-boot-starter-web = { module = "org.springframework.boot:spring-boot-starter-web", version.ref = "spring-boot" }
junit-jupiter = { module = "org.junit.jupiter:junit-jupiter", version.ref = "junit" }
```

- 이렇게 정의해 두면 각 build.gradle에서 버전을 직접 쓰지 않고 이름으로 불러올 수 있음

### (3) : `gradlew`, `gradlew.bat`
- Gradle wrapper 스크립트
- gradlew (리눅스/맥), gradlew.bat (윈도우)
- 로컬에 Gradle이 없어도, 프로젝트가 지정한 Gradle 버전을 자동으로 다운로드해서 실행 가능.
- 즉, 모든 개발자가 같은 버전의 Gradle을 쓰게 보장.

### (4) : `settings.gradle`
- 루트 프로젝트 이름과 서브프로젝트를 정의하는 Gradle 설정 파일.
- 멀티 프로젝트의 구성도 같은 것.
- 예시:
```
rootProject.name = "my-multi-app"
include("subproject-a", "subproject-b")
```

- 이렇게 해야 Gradle이 subproject-a, subproject-b를 인식.
- 멀티 모듈 프로젝트에서는 해당 파일이 반드시 필요함 (단일 모듈 프로젝트에서는 없어도됨)

### (5) : `build.gradle`
- 각 서브프로젝트의 빌드 스크립트
- 각 모듈(예: subproject-a, subproject-b)이 어떤 언어, 어떤 의존성, 어떤 플러그인을 쓰는지 등을 정의

```
plugins {
    id("java")
}

dependencies {
    implementation(libs.spring.boot.starter.web)
    testImplementation(libs.junit.jupiter)
}
```

### (6) : `src/`
- 프로젝트의 소스 코드 및 기타 파일.

```
src/
 ├── main/java/...     # 실제 애플리케이션 코드
 ├── main/resources/   # 설정 파일, 정적 리소스
 └── test/java/...     # 테스트 코드
```

## 핵심 개념
---

> Projects, Build Scripts, Dependencies, Tasks, Plugins

### 1. Projects
- Gradle 프로젝트는 애플리케이션이나 라이브러리처럼 빌드할 수 있는 소프트웨어 조각이다.
- 단일 프로젝트 빌드는 루트 프로젝트라 불리는 단일 프로젝트를 포함한다.
- 멀티 프로젝트 빌드는 하나의 루트 프로젝트와 여러 개의 하위 프로젝트를 포함한다.

```
my-app/
 └── build.gradle
```

```
my-multi-app/
 ├── build.gradle      # 루트 프로젝트
 ├── settings.gradle   # 어떤 서브프로젝트 있는지 선언
 ├── app/              # 서브 프로젝트1
 │   └── build.gradle
 └── library/          # 서브 프로젝트2
     └── build.gradle
```

```
// settings.gradle
rootProject.name = "my-multi-app"
include("app", "library")
```

### 2. Build Scripts
- 빌드 스크립트는 Gradle에게 프로젝트를 빌드하기 위해 어떤 단계를 수행해야 하는지를 알려준다.
- 각 프로젝트는 하나 이상의 빌드 스크립트를 포함할 수 있다.
- 예 : "이 프로젝트는 자바야, 이 라이브러리 필요해"라고 Gradle에게 알려주는 설명서.

```
// build.gradle
plugins {
    id 'java' // 자바 관련 Task들 자동 등록
}

group = 'com.example'
version = '1.0.0'

repositories {
    mavenCentral() // 외부 라이브러리를 여기서 가져옴
}

dependencies {
    implementation 'org.springframework.boot:spring-boot-starter-web:3.2.0'
    testImplementation 'org.junit.jupiter:junit-jupiter:5.10.0'
}

```

### 3. Dependencies and Dependency Management
> 프로젝트에 필요한 외부 리소스(=의존성)를 선언하고 해결하는 자동화된 기법

- 의존성(Dependencies)에는 JAR, 라이브러리, 소스 코드 등이 포함되며, 이는 프로젝트 빌드를 지원한다.
- Gradle은 이러한 의존성을 자동으로 다운로드하고, 캐싱하고, 해결해주기 때문에 개발자가 직접 관리할 필요가 없다.
- 또한 Gradle은 버전 충돌 처리를 해주고, 유연한 버전 선언 방식도 지원한다.

```
dependencies {
    implementation 'org.springframework.boot:spring-boot-starter-web:3.2.0'
}
```

- Gradle에서는 의존성을 Configuration(구성) 별로 그룹화하여, **언제/어떻게 사용되는지**를 정의한다.
  - implementation: 프로덕션 코드의 컴파일 및 실행에 필요한 의존성
  - api: 라이브러리 소비자에게도 공개되어야 하는 의존성 (즉, 라이브러리를 쓰는 쪽에서도 접근 가능해야 하는 경우)

- 의존성 트리를 확인하려면 dependencies 작업을 실행할 수 있다.
  - 예: :app 프로젝트의 의존성을 보려면
  - `$ ./gradlew :app:dependencies`

**버전 카탈로그**
> 빌드 전체에서 의존성 좌표(group:name:version)와 버전을 중앙 집중적이고 일관되게 관리하는 방법을 제공한다.

각 `build.gradle(.kts)` 파일마다 버전을 직접 적는 대신, `libs.versions.toml` 파일에 한 번만 정의하고 공통으로 가져다 쓸 수 있다.
- 이를 통해 다음이 쉬워진다:
  - 여러 서브프로젝트 간 공통 의존성 선언 공유
  - 중복 및 버전 불일치 방지
  - 대규모 프로젝트에서 의존성과 플러그인 버전 강제

- 일반적으로 libs.versions.toml 파일에는 4개의 섹션이 있다:
  - [versions] → 플러그인 및 라이브러리가 참조할 버전 번호 선언
  - [libraries] → 빌드 파일에서 사용할 라이브러리 정의
  - [bundles] → 여러 의존성을 묶어서 세트로 정의
  - [plugins] → 플러그인 정의

- 예시:

```
[versions]
guava = "32.1.2-jre"
juneau = "8.2.0"

[libraries]
guava = { group = "com.google.guava", name = "guava", version.ref = "guava" }
juneau-marshall = { group = "org.apache.juneau", name = "juneau-marshall", version.ref = "juneau" }
```

```
// build.gradle
dependencies {
    implementation(libs.guava)
    api(libs.juneau.marshall)
}
```

**Dependency Configurations**
> Gradle 프로젝트에서 선언되는 모든 의존성은 특정 **범위(scope)**에 적용된다. <br>
> **Dependency Configuration(의존성 구성)**은 프로젝트 안에서 서로 다른 목적에 맞게 의존성을 분리하여 정의하는 방법이다.

- 이것은 빌드 과정의 여러 단계(컴파일, 실행, 테스트 등)에서 의존성이 언제, 어떻게 사용될지를 결정한다.
- Configurations는 Gradle의 **의존성 해석(dependency resolution)**에서 기본적인 역할을 한다.
- Java Library Plugin을 적용하면 프로젝트가 Java 라이브러리를 생산할 수 있고, 이 플러그인은 여러 Configuration을 자동으로 추가한다.
  - 예: 소스 코드 컴파일, 테스트 실행 등 다양한 classpath에 필요한 의존성 그룹.

| Configuration          | 설명                                                  | 비고                              |
| ---------------------- | --------------------------------------------------- | ------------------------------- |
| **api**                | 컴파일 & 실행 시 모두 필요한 의존성. 또한 **배포된 API에 포함**된다.        | `java-library` 플러그인 전용          |
| **implementation**     | 컴파일 & 실행 시 필요한 의존성. 하지만 API로 노출되지는 않는다.             | 일반적인 경우 가장 많이 사용                |
| **compileOnly**        | **컴파일 시에만** 필요한 의존성. 실행(runtime)이나 배포 시에는 포함되지 않는다. | 예: Lombok, Annotation Processor |
| **compileOnlyApi**     | 컴파일 시에만 필요하지만, **배포된 API에는 포함**된다.                  |                                 |
| **runtimeOnly**        | **실행 시에만** 필요한 의존성. 컴파일 classpath에는 없음.             | 예: JDBC Driver, 로깅 구현체          |
| **testImplementation** | **테스트 코드 컴파일 & 실행**에 필요한 의존성.                       | 예: JUnit                        |
| **testCompileOnly**    | **테스트 코드 컴파일**에만 필요한 의존성. 실행에는 불필요.                 |                                 |
| **testRuntimeOnly**    | **테스트 실행 시에만** 필요한 의존성.                             |                                 |

- annotationProcessor는 목록에 없을까?
  - 이유는, annotationProcessor는 Java 플러그인/Java Library 플러그인에서 추가적으로 정의한 특수 Configuration이기 때문
  - 원래 Gradle 기본 문서에서 “주요 Configuration”만 소개했을 때는 annotationProcessor가 빠져 있음

- annotationProcessor는 다음을 위해 사용됨:
  - 컴파일 시에 애노테이션 프로세서를 실행해야 할 때 (예: Lombok, MapStruct)
  - 실행(runtime)이나 API 배포와는 무관하게, 오직 컴파일 단계에서만 필요

### 4. Tasks
> 작업(Task)은 코드를 컴파일하거나 테스트를 실행하는 것 같은 **독립적인 작업 단위**이다.

- 일반적인 작업(Task)의 유형에는 다음이 포함된다:
  - 소스 코드 컴파일
  - 테스트 실행
  - 출력물 패키징 (예: JAR 또는 APK 생성)
  - 문서 생성 (예: Javadoc)
  - 빌드 산출물을 저장소에 배포

- 각 작업은 독립적이지만, 다른 작업이 먼저 실행되어야만 수행될 수도 있다.
  - Gradle은 이 정보를 사용해서 가장 효율적인 순서로 작업들을 실행하며, 이미 최신 상태인 작업은 건너뛴다.

- Gradle 플러그인과 빌드 스크립트는 프로젝트에서 사용할 수 있는 작업들을 정의한다.
  - `$ ./gradlew tasks`로 확인 가능

**Task 실행**
> `./gradlew <Task명>`

- 작업을 실행하려면 프로젝트 루트 디렉터리에서 Gradle Wrapper를 사용한다.
- 예를 들어, build 작업을 실행하려면: `./gradlew build`
  - 이 명령은 build 작업과 그에 필요한 모든 의존 작업들을 실행한다.
- Gradle은 어떤 작업이 다른 어떤 작업에 의존하는지 알고 있으며, 올바른 순서로 자동으로 실행한다.

```
$ ./gradlew build

> Task :app:compileJava
> Task :app:processResources NO-SOURCE
> Task :app:classes
> Task :app:jar
> Task :app:startScripts
> Task :app:distTar
> Task :app:distZip
> Task :app:assemble
> Task :app:check
> Task :app:build

BUILD SUCCESSFUL in 764ms
7 actionable tasks: 7 executed
```

### 5. Plugins
> Gradle 빌드 시스템에 **추가 기능을 제공**하는 재사용 가능한 소프트웨어 조각

- 추가 기능 예:
  - 새로운 작업(Task)을 빌드에 추가한다 (예: compileJava, test)
  - 새로운 설정(Configuration)을 추가한다 (예: implementation, runtimeOnly)
  - 새로운 DSL(Domain Specific Language, 빌드 스크립트에서 쓸 수 있는 전용 문법) 요소를 제공한다 (예: application {}, publishing {})

- 즉, Gradle은 기본적으로 최소 기능만 있고 플러그인을 붙이면 기능이 늘어남.
- 예시:

```
plugins {
    id("java") // java 플러그인을 적용
}

dependencies {
    implementation("org.springframework.boot:spring-boot-starter-web") // 코드 컴파일 시 필요한 라이브러리
    testImplementation("org.junit.jupiter:junit-jupiter:5.10.0")       // 테스트 전용 라이브러리
    runtimeOnly("com.h2database:h2")                                   // 실행 시에만 필요한 라이브러리
}
```

- java 플러그인을 적용하기 전에는 implementation, testImplementation, runtimeOnly 같은 Configuration이 없음.
- 플러그인을 적용하면서 Gradle이 이런 "의존성 그룹"을 자동으로 만들어줌.

```
plugins {
    id("org.springframework.boot") version "3.2.0"
}

tasks.named<org.springframework.boot.gradle.tasks.run.BootRun>("bootRun") {
    args("--spring.profiles.active=dev")
}
```

- 플러그인은 특정 도메인이나 워크플로우에 필요한 모든 로직을 가져온다.
  - 도메인 = "특정한 문제 영역" (예: Java 빌드, Spring Boot 실행, Android 앱 패키징 등)
  - 플러그인은 그 도메인에 필요한 Task, Configuration, DSL 블록을 한꺼번에 제공한다.
  - 즉, 어떤 워크플로우(흐름)를 실행하기 위해 필요한 것들을 전부 제공한다.
  - Spring Boot 플러그인을 적용하면:
    - bootRun, bootJar 같은 Task 자동 추가
    - developmentOnly, runtimeClasspath 같은 Configuration 추가
    - springBoot {} 같은 DSL 블록 제공
    - 결과적으로 Spring Boot 앱 빌드/실행/배포에 필요한 전 과정을 자동화할 수 있음.

**플러그인 종류**
> Gradle은 세 가지 타입의 플러그인을 지원한다

`1. 스크립트 플러그인 (Script plugins)`
- **다른 Gradle 스크립트 파일(.gradle / .gradle.kts)**을 불러다 쓰는 방식.
- apply from: 문법으로 적용.
- 흔히 공통 설정을 `common.gradle` 같은 파일로 분리해서 여러 프로젝트에서 재사용할 때 사용.

```
// common.gradle
tasks.register("hello") {
    doLast {
        println("Hello from common.gradle")
    }
}
```

```
// build.gradle
apply from: "common.gradle"
```

`2. 사전 컴파일된 플러그인 (Pre-compiled plugins)`
- Kotlin 또는 Groovy 코드로 패키징된 플러그인.
- 직접 플러그인 클래스를 작성해서 프로젝트 내에서 재사용.
- `buildSrc/` 디렉터리에 넣으면 자동으로 인식됨.

```
project-root/
 ├── buildSrc/
 │   └── src/main/kotlin/MyConventionPlugin.kt
 └── build.gradle.kts
```

```kotlin
// buildSrc/src/main/kotlin/MyConventionPlugin.kt
import org.gradle.api.Plugin
import org.gradle.api.Project

class MyConventionPlugin : Plugin<Project> {
    override fun apply(project: Project) {
        project.tasks.register("greet") {
            doLast { println("Hello from MyConventionPlugin!") }
        }
    }
}
```

```
// build.gradle.kts
plugins {
    id("my-convention-plugin") // 클래스 이름 기반으로 자동 인식
}
```

`3. 바이너리 플러그인 (Binary plugins)`
- 패키징·배포된 플러그인(Plugin Portal 또는 Maven에 올라온 것).
- 대부분 우리가 쓰는 유명한 플러그인들 (예: java, application, spring-boot, spotless)

```
plugins {
    id("java-library") // Gradle 코어 플러그인 (버전 지정 필요 없음)
    id("org.springframework.boot") version "3.2.0" // 커뮤니티 플러그인
    id("com.diffplug.spotless") version "6.25.0"   // 코드 포맷팅 플러그인
}
```

**플러그인 배포 경로**
> Gradle 플러그인은 여러 소스에서 제공되며, 상황에 맞게 선택할 수 있다.

`1. 코어 플러그인 (Core Plugins)`
- Gradle 배포판에 포함된 플러그인. ([목록](https://docs.gradle.org/current/userguide/plugin_reference.html))
- Gradle 팀에서 관리한다.
- 예: java-library

```
plugins {
    id("java-library")
}
```

`2. 커뮤니티 플러그인 (Community Plugins, Plugin Portal)`
- Gradle 커뮤니티가 만든 플러그인.
- [Gradle Plugin Portal](https://plugins.gradle.org/)에 공개되어 있고, ID와 버전으로 적용 가능.

```
plugins {
    id("org.springframework.boot").version("3.1.5")
}
```

`3. 로컬/커스텀 플러그인 (Local or Custom Plugins)`
- 직접 만든 플러그인. 단일 프로젝트에서만 쓰거나 여러 프로젝트에서 공유할 수 있다.
- 가장 흔한 형태는 Convention Plugin.
  - `buildSrc/` 디렉토리나 별도 `build-logic` 모듈 안에 위치.
  - Kotlin/Groovy로 작성.

## Gradle Wrapper
---
> Gradle Wrapper는 항상 신뢰할 수 있고, 제어되고, 표준화된 빌드 실행을 보장하기 때문에 권장되는 Gradle 빌드 방식이다.

- Wrapper 스크립트는 선언된 Gradle 버전을 호출하며, 필요하다면 먼저 그것을 다운로드한다.
- 프로젝트 루트 디렉터리에서 `gradlew` 또는 `gradlew.bat` 파일로 제공된다:

```
root
├── gradlew     // THE WRAPPER
├── gradlew.bat // THE WRAPPER
└── ...
```

- 프로젝트에 이 파일들이 없다면, 그것은 아마도 Gradle 프로젝트가 아니거나, Wrapper가 아직 설정되지 않은 것일 수 있다.
- Wrapper는 인터넷에서 직접 다운로드하는 것이 아니다. Gradle이 설치된 머신에서 `gradle wrapper` 명령을 실행하여 생성해야 한다.


![image](/assets/img/gradle-wrapper-flow-img.png)
<figure align = "center">
  <figcaption align="center">출처 : https://docs.gradle.org/current/userguide/gradle_wrapper_basics.html</figcaption>
</figure>

### Wrapper가 제공하는 이점
- 지정된 Gradle 버전을 자동으로 다운로드하고 사용한다.
- 프로젝트를 특정 Gradle 버전에 표준화한다.
- 서로 다른 사용자 및 환경(IDE, CI 서버 등)에 동일한 Gradle 버전을 제공한다.
- Gradle을 직접 수동 설치하지 않고도 Gradle 빌드를 쉽게 실행할 수 있게 해준다.


**만약 실행 환경별로 버전이 다르면 ?**

`1. 빌드 스크립트 문법 차이`
- Gradle은 계속 발전하면서 DSL(Groovy/Kotlin) 문법이 추가·변경·Deprecated 됨
  - 예: 예전 버전에서 쓰던 compile-> implementation으로 변경
- Gradle 4.x를 쓰면 compile이 잘 동작하지만, Gradle 7.x에선 에러 발생

`2. 플러그인 호환성 문제`
- Spring Boot, Kotlin, Android 등은 Gradle 버전에 맞춰 플러그인을 업데이트
- 특정 버전의 Gradle에서는 플러그인이 아예 동작하지 않거나 경고/에러가 발생할 수 있음.
  - 예: 최신 Android Gradle Plugin은 최소 Gradle 7.x 이상을 요구. 누군가는 6.x를 쓰면 빌드 자체가 불가능.
- CI/CD 서버나 다른 개발자 환경에서 빌드 깨짐.

`3. 빌드 결과물 차이`
- 같은 코드를 빌드해도 Gradle 내부 동작(캐싱, 병렬 빌드 방식, dependency resolution 방식)이 버전에 따라 달라집니다.
  - 예: Gradle 6.x와 7.x는 의존성 중복 처리 방식이 달라서, 한쪽은 충돌 나고 다른 한쪽은 자동 해결될 수도 있음.
- 로컬에서 테스트한 JAR/WAR는 잘 돌아가는데, 서버에서 빌드된 건 오류가 날 수 있음.

`4. CI/CD 환경과 로컬 환경 불일치`
- 로컬 개발자는 Gradle 8.x, CI 서버는 Gradle 7.x → 서버에서만 빌드 에러 발생.
- 빌드 실패 원인을 파악하기 어려워지고, 시간을 허비하게 됨.

### Wrapper 구성 요소

```
.
├── gradle
│   └── wrapper
│       ├── gradle-wrapper.jar
│       └── gradle-wrapper.properties
├── gradlew
└── gradlew.bat
```

- gradle-wrapper.jar
  - 작은 JAR 파일로, Gradle Wrapper 코드를 담고 있다.
  - 프로젝트에 필요한 Gradle 버전이 설치되어 있지 않으면 이를 다운로드하고 설치하는 역할을 한다.

- gradle-wrapper.properties
  - Gradle Wrapper에 대한 설정 속성을 담고 있는 파일이다.
  - 예: Gradle을 어디서 다운로드할지(배포 URL), 배포 유형(ZIP 또는 TARBALL).

- gradlew
  - Unix 계열 시스템에서 사용하는 셸 스크립트.
  - `gradle-wrapper.jar`를 감싸는 역할을 하며, Gradle을 수동 설치하지 않고도 Gradle 작업을 실행할 수 있다.

- gradlew.bat
  - Windows에서 사용하는 배치 스크립트.
  - 목적은 `gradlew`와 동일하다.

### 실행 흐름 예시
> `./gradlew build`

- gradlew (shell script) 동작:
  - `CLASSPATH=$APP_HOME/gradle/wrapper/gradle-wrapper.jar` 설정
  - Java 실행기로 gradle-wrapper.jar를 실행
  - 이때, gradle-wrapper.properties 파일도 읽어서 “Gradle 몇 버전, 어디서 받을지” 확인

- gradle-wrapper.jar 동작:
  - 지정된 버전의 Gradle 설치 여부 확인
  - 없으면 다운로드 (ZIP이나 TAR)
  - 해당 Gradle 런처를 호출해서 실제 빌드 실행

### 주의 사항

- 이 파일들은 절대 직접 수정해서는 안 된다.
- Gradle 버전을 확인하거나 업데이트하려면 명령줄에서 다음 명령을 사용한다:

```
$ ./gradlew --version
$ ./gradlew wrapper --gradle-version 7.2
```

## 참고 자료
---
- [https://docs.gradle.org/current/userguide/gradle_basics.html](https://docs.gradle.org/current/userguide/gradle_basics.html)
- [https://docs.gradle.org/current/userguide/dependency_management_basics.html](https://docs.gradle.org/current/userguide/dependency_management_basics.html)
- [https://docs.gradle.org/current/userguide/dependency_configurations.html](https://docs.gradle.org/current/userguide/dependency_configurations.html)
- [https://docs.gradle.org/current/userguide/task_basics.html](https://docs.gradle.org/current/userguide/task_basics.html)
- [https://docs.gradle.org/current/userguide/task_basics.html](https://docs.gradle.org/current/userguide/task_basics.html)
