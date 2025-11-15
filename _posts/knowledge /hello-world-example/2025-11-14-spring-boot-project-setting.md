---
title: IntelliJ에서 프로젝트 세팅하기 (Gradle, Spring Boot)
date: 2025-11-14 22:25:00 +0900
categories: [지식 더하기, Hello-World 구현]
tags: [Spring Boot, IntelliJ]
---

Gradle 기반 스프링 부트 프로젝트를 세팅해보자.

## 프로젝트 만들기
---
> 실습환경 : IntelliJ IDEA 2025.2 <br>
> 경로 : `File > New > Project...`

![img](/assets/img/spring-boot-project-setting-img1.png)

![img](/assets/img/spring-boot-project-setting-img2.png)


## 프로젝트 세팅
---
> File > Project Structure

![img](/assets/img/spring-boot-project-setting-img3.png)

### Project SDK
> 프로젝트에서 사용할 JDK 버전을 지정

- 프로젝트 내 모든 모듈이 공통으로 사용할 기본 SDK
- 빌드 결과물의 실행 환경(Java Runtime)과 맞춰야 런타임 오류를 방지할 수 있음

### Language level
> Java 문법을 어느 버전까지 사용할지 결정

| 설정                         | 의미                     |
| -------------------------- |------------------------|
| JDK 21 + Language level 21 | JDK21 기능 모두 사용 가능      |
| JDK 21 + Language level 17 | Java 17 문법으로만 코드 작성 가능 |
| JDK 17 + Language level 21 | 불가능 (SDK가 기능을 지원하지 못함) |

**JDK21부터 지원하는 문법 사용해보기**

- JDK 21 + Language level 17
![img](/assets/img/spring-boot-project-setting-img4.png)

- JDK 17 + Language level 21
![img](/assets/img/spring-boot-project-setting-img5.png)

**※ 모듈 단위로 SDK, Language level 설정 가능**
![img](/assets/img/spring-boot-project-setting-img6.png)
![img](/assets/img/spring-boot-project-setting-img7.png)

- 예 : 멀티모듈 프로젝트에서 각 모듈의 Java 버전이 다를 수 있음
  - core 모듈 → Java 17
  - admin 모듈 → Java 21
  - api 모듈 → Java 11

### Compiler output
> 컴파일한 `.class` 파일을 어디에 저장할지 정하는 경로

- Maven/Gradle 빌드 출력(target/, build/)이 아니라 IntelliJ 자체 빌드 했을 때 .class 파일을 저장하는 디렉터리.

### Platform Settings > SDKs
> IntelliJ 전체(IDE 차원)에서 사용할 수 있는 JDK 목록을 등록/관리하는 공간

![img](/assets/img/spring-boot-project-setting-img8.png)

- 즉, 프로젝트에 적용하기 전에 IntelliJ가 인식할 수 있는 JDK들을 등록해두는 곳
  - 이곳에 등록되어야 프로젝트, 모듈에서 SDK 선택할 수 있음

## IDE 설정
---
> IntelliJ IDEA > settings

### Project bytecode version
> 컴파일된 `.class` 파일의 버전(바이트코드 타겟)을 지정

![img](/assets/img/spring-boot-project-setting-img9.png)

- 예를 들어:
  - Language level: 21
  - SDK: JDK 21
  - Project bytecode version: 11

- 하지만 Java 21 문법을 Java 11 bytecode로 다운그레이드할 수 없음.
- 그래서, 대부분의 경우 **Language Level = SDK = Bytecode Version**을 맞춘다.

### Build Tool > Gradle
> IntelliJ에서 Gradle로 프로젝트 관리시 두 가지 컴파일 방식이 있음

![img](/assets/img/spring-boot-project-setting-img10.png)

| 빌드/실행 방법                             | 컴파일 수행 주체<br>(누가 `javac`을 실행시키는가?) | 사용되는 `javac`의 JDK 버전                            |
| ------------------------------------ |----------------------------------| --------------------------------------------- |
| IntelliJ Build                  | IntelliJ IDE                     | **Project SDK**의 javac                        |
| Gradle Build (`./gradlew build` or Run) | Gradle(JavaCompile task)         | **Gradle JVM**의 javac 또는 **Gradle toolchain** |

## Gradle
---

### Toolchain
> [공식문서](https://docs.gradle.org/current/userguide/toolchains.html) <br>
> 코드를 컴파일 할 때 어떤 JDK를 사용할지를 Gradle이 직접 다운받아 지정하는 기능

```
// build.gradle
java {
  toolchain {
    languageVersion = JavaLanguageVersion.of(21)
  }
}
```

- Toolchain이 다운로드한 모든 JDK는 `~/.gradle/jdks/<jdk-version>/`에 있음
- Gradle Toolchain이 JDK를 다운받는 기본 저장소 : Adoptium / Eclipse Temurin (기본값)
- Gradle은 다음 순서로 JDK를 찾는다:
  - 환경변수 `JAVA_HOME`
  - SDKMAN 설치 JDK
  - ASDF 설치 JDK
  - `/usr/lib/jvm` 같은 시스템 JDK
  - Windows 레지스트리의 JDK
  - 그래도 없으면 기본 저장소에서 다운로드

**예시 상황**

| 환경                                | Toolchain 없음          | Toolchain 있음 |
|-----------------------------------| --------------------- | ----------- |
| 로컬 IntelliJ 빌드 (Gradle Build인 경우) | IntelliJ Gradle JVM JDK | Toolchain JDK |
| 로컬 터미널 `./gradlew build`          | `$JAVA_HOME`          | Toolchain JDK |
| Jenkins 서버 빌드                     | Jenkins에 설치된 JDK      | Toolchain JDK |
| GitHub Actions                    | setup-java로 지정한 JDK   | Toolchain JDK |
| Docker 빌드                         | Docker 이미지 내의 JDK     | Toolchain JDK |
| 일관성                               | 서로 다름                 | 항상 동일       |

- 사람마다 / 서버마다 JDK 버전이 다르면, 빌드 결과와 에러도 다르게 나올 수 있다.
- 예시:
  - 개발자 A: Java 21로 빌드 → 성공
  - 개발자 B: Java 17로 빌드 → 실패
  - Jenkins: Java 11로 빌드 → 실패
- “로컬은 되는데 서버에서는 안된다” 문제 발생

## 애플리케이션 실행
---

| 실행 방식                                                            | 실행 주체    | 실행 JDK                  | 특징             |
|------------------------------------------------------------------| -------- |-------------------------|----------------|
| **Build and Run using IntelliJ**                                 | IntelliJ | Project SDK             | 개발 편의성 좋음      |
| **Build and Run using Gradle**<br> (./gradlew bootRun 실행한 것과 동일) | Gradle   | Gradle JVM or Toolchain | IDE/Gradle 일관성 |
| **./gradlew bootRun**                                            | Gradle   | JAVA_HOME or Toolchain   | 터미널/CI 친화적     |
| **./gradlew bootJar** --> **java -jar**                          | OS JVM   | 서버 JDK                   | 운영 배포 방식       |
| **Docker 실행**                                                    | Docker   | Docker JDK               | 환경 완전 격리       |


## 정리
---

| 설정                               | 설정                       |
| ----------------------------------- |--------------------------|
| **Project SDK**                     | Temurin 21               |
| **Project Language Level**          | SDK Default              |
| **Module Language Level**           | Project Default          |
| **Compiler – bytecode version**     | 21                       |
| **Gradle JVM**                      | Project SDK (Temurin 21) |
| **Gradle Toolchain (build.gradle)** | 없음 또는 같음(21)             |

- IntelliJ 빌드, Gradle 빌드, 런타임 모두 JDK 21로 통일되므로 예상치 못한 빌드 오류, bytecode mismatch, IDE/Gradle 충돌 문제 등을 방지 할 수 있음

