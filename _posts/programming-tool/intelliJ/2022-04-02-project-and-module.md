---
title: IntelliJ - 프로젝트, 모듈이란 ?
date: 2022-04-02 20:25:00 +0900
categories: [개발 도구, IntelliJ]
tags: [IDE]
---

# Project
---
> 프로젝트는 애플리케이션을 구성하는 모든 것(모듈, 종속성, 공통 설정 등)을 보관하는 디렉토리이다.

- 일반적으로 프로젝트에는 관련 모듈, 애플리케이션, 라이브러리 등이 포함되며, 이를 통해 상호 의존적으로 협력하여 개발이 가능해진다.

<figure align="center">
  <img src="https://user-images.githubusercontent.com/64415489/161387348-8d44df08-7b4b-4659-8755-0f1bfa5c7a5a.png" width="80%"/>
  <figcaption align="center">출처 : <a href="https://www.jetbrains.com/help/idea/working-with-projects.html#settings-types" target="_blank"> https://www.jetbrains.com/help/idea/working-with-projects.html#settings-types</a> </figcaption>
</figure>

## Project 설정
> 프로젝트 설정은 `.xml` 형식으로 `.idea` 디렉토리에 다른 프로젝트 파일과 함께 저장된다.

- 예를 들어, VCS 설정, SDK, 코드 스타일 및 맞춤법 검사기 설정, 컴파일러 출력, 프로젝트 내의 모든 모듈에 사용할 수 있는 라이브러리 등을 세팅한다.

<img width="1182" alt="image" src="https://user-images.githubusercontent.com/64415489/161386898-2c4b31a3-aefd-4de8-86df-769e9836a541.png">

### Project SDK
> SDK는 특정 소프트웨어 프레임워크용 애플리케이션을 개발하는 데 필요한 도구 모음이다.

- 필요한 SDK가 컴퓨터에 설치되어 있지만 IDE에 정의되어 있지 않은 경우, `Add SDK | 'SDK name'`을 지정하고 SDK 홈 디렉터리의 경로를 지정한다.
- 예를 들어, Java 기반 애플리케이션을 개발하려면 JDK(Java Development Kit)가 필요하다.

### Project language level
> Language level은 편집기가 제공하는 코딩 지원 기능을 정의한다.

- 예를 들어 JDK 9를 사용하고 언어 레벨을 8로 설정할 수 있다.
  - 이렇게 하면 바이트코드가 Java 8과 호환되는 반면, 검사(inspection)에서는 Java 9의 구성을 사용하지 않도록한다.

- Language level은 컴파일에도 영향을 준다.
  - 컴파일러(`(Settings/Preferences | Build, Execution, Deployment | Compiler | Java Compiler)`)의 타겟 바이트코드 버전을 따로 세팅하지 않으면, 타겟 바이트코드 버전은 Language level로 간주된다.

### Project compiler output
> 컴파일러 출력 경로는 IntelliJ IDEA가 컴파일 결과를 저장하는 디렉토리 경로이다.

- 이 디렉터리에서 IDE는 두 개의 하위 디렉터리를 만든다.
  - `production` : 프로덕션 코드
  - `test` : 테스트 코드

- 하위 디렉토리에서 각 모듈에 대한 개별 출력 디렉토리가 생성된다.

# Module
---
> IntelliJ IDEA에서 모듈은 모든 프로젝트의 필수적인 부분으로써, 프로젝트와 함께 자동으로 생성된다.

- 프로젝트는 여러 모듈을 포함할 수 있다(멀티 모듈 프로젝트).
  - 또한, 새 모듈을 추가하고 그룹화하고 현재 필요하지 않은 모듈을 언로드할 수 있다.

- 일반적으로 모듈은 내부 설정을 유지하는 `.iml` 파일과 소스 코드, 리소스, 테스트 등을 저장하는 `content root`로 구성된다.
  - `content root` 없이 모듈이 존재할 수도 있다.

- 각 모듈은 자체 프레임워크를 담당할 수 있다.
- 각 모듈은 별도의 라이브러리, webapp 등이 될 수 있다.
- 각 모듈은 패키지된 코드의 단일 유형(jar 파일, war 파일 등)용이다.

<figure align="center">
  <img src="https://user-images.githubusercontent.com/64415489/161387492-83ac7c31-487a-4687-a8dc-83e5665ea56a.png" width="80%"/>
  <figcaption align="center">출처 : <a href="https://www.jetbrains.com/help/idea/working-with-projects.html#settings-types" target="_blank"> https://www.jetbrains.com/help/idea/working-with-projects.html#settings-types</a> </figcaption>
</figure>

# 참고 자료
---
- [https://www.jetbrains.com/help/idea/working-with-projects.html#settings-types](https://www.jetbrains.com/help/idea/working-with-projects.html#settings-types)
- [https://www.jetbrains.com/help/idea/working-with-projects.html](https://www.jetbrains.com/help/idea/working-with-projects.html)
- [https://www.jetbrains.com/help/idea/project-settings-and-structure.html](https://www.jetbrains.com/help/idea/project-settings-and-structure.html)
- [https://www.jetbrains.com/help/idea/creating-and-managing-modules.html](https://www.jetbrains.com/help/idea/creating-and-managing-modules.html)
- [https://intellij-support.jetbrains.com/hc/en-us/community/posts/206887325-Difference-between-project-and-module
](https://intellij-support.jetbrains.com/hc/en-us/community/posts/206887325-Difference-between-project-and-module
)
