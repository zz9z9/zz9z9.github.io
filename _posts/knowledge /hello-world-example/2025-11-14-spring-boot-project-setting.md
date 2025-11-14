

> File > New > Project from Version Control...

![img.png](img.png)

## File > New > Project...
---

![img_1.png](img_1.png)

![img_2.png](img_2.png)

- Intellij에서 자동으로 구성해줌

![img.png](img_9.png)
=> 공부 목적이 아니면 보통은 이거 사용할듯
=> 플러그인, 의존성 등 다 세팅해줌

![img_8.png](img_8.png)

## 프로젝트 세팅
---
> File > Project Structure (단축키 : `⌘;`)

![img_3.png](img_3.png)

![img_4.png](img_4.png)

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


![img_7.png](img_7.png)
=> JDK 21 + Language level 17

![img_6.png](img_6.png)
=> JDK 17 + Language level 21

**※ 모듈 단위로 SDK, Language level 설정 가능**
![img_10.png](img_10.png)
![img_5.png](img_5.png)

멀티모듈 프로젝트에서 각 모듈의 Java 버전이 다를 수 있음

예)

core 모듈 → Java 17

admin 모듈 → Java 21

legacy 모듈 → Java 11

### Compiler output
> 컴파일한 `.class` 파일을 어디에 저장할지 정하는 경로

Maven/Gradle 빌드 출력(target/, build/)이 아니라
IntelliJ 자체 빌드(⌘F9) 했을 때 .class 파일을 저장하는 디렉터리.

프로젝트 전체를 빌드하면 IntelliJ가 이 디렉터리에

production (main 코드)

test (test 코드)
등을 자동으로 생성함.

- 보통 메이븐/그래들로 빌드하므로 큰 상관은 없지만,
- IntelliJ의 incremental build 를 사용할 때 필요합니다.
- incremental build ??


Gradle 빌드

IntelliJ 빌드

spring boot 실행
main 함수 실행
Gradle 실행

### Platform Settings > SDKs

![img_11.png](img_11.png)

> IntelliJ 전체(IDE 차원)에서 사용할 수 있는 JDK 목록을 등록/관리하는 공간

- 즉, 프로젝트에 적용하기 전에 IntelliJ가 인식할 수 있는 JDK들을 등록해두는 곳
  - 이곳에 등록되어야 프로젝트, 모듈에서 SDK 선택할 수 있음

## Gradle

### 단일 모듈

### 멀티 모듈
