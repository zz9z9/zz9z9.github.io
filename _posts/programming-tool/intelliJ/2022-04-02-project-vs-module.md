---
title: IntelliJ - 프로젝트, 모듈이란 ?
date: 2022-04-02 20:25:00 +0900
categories: [IntelliJ]
tags: [IDE]
---

# Project
---
> 프로젝트는 애플리케이션을 구성하는 모든 것(모듈, 종속성, 공통 설정 등)을 보관하는 디렉토리이다.

- 프로젝트는 일반적으로 설정과 하나 이상의 모듈로 구성된다.

<figure align="center">
  <img src="https://user-images.githubusercontent.com/64415489/161387348-8d44df08-7b4b-4659-8755-0f1bfa5c7a5a.png" width="80%"/>
  <figcaption align="center">출처 : <a href="https://www.jetbrains.com/help/idea/working-with-projects.html#settings-types" target="_blank"> https://www.jetbrains.com/help/idea/working-with-projects.html#settings-types</a> </figcaption>
</figure>

## Project 설정
> 프로젝트 설정은 `.xml` 형식으로 `.idea` 디렉토리에 다른 프로젝트 파일과 함께 저장된다.

- 예를 들어, VCS 설정, SDK, 코드 스타일 및 맞춤법 검사기 설정, 컴파일러 출력, 프로젝트 내의 모든 모듈에 사용할 수 있는 라이브러리 등을 세팅한다.

<img width="1182" alt="image" src="https://user-images.githubusercontent.com/64415489/161386898-2c4b31a3-aefd-4de8-86df-769e9836a541.png">

### Project SDK
An SDK is a collection of tools that you need to develop an application for a specific software framework.
If the necessary SDK is installed on your computer, but not defined in the IDE, select Add SDK | 'SDK name', and specify the path to the SDK home directory.

To develop Java-based applications, you need a JDK (Java Development Kit). For the detailed instructions on how to set up the project JDK, refer to Set up the project JDK.

To view or edit the name and contents of the selected SDK, click Edit. For more information on SDKs and how to work with them, refer to SDKs.


### Project language level
Language level defines coding assistance features that the editor provides. Language level can differ from your project SDK. For example, you can use the JDK 9 and set the language level to 8. This makes the bytecode compatible with Java 8, while inspections make sure you don't use constructs from Java 9.

- Language level also affects compilation. If you don't manually configure the target bytecode version for your compiler (Settings/Preferences | Build, Execution, Deployment | Compiler | Java Compiler), it will be the same as the project language level.

### Project compiler output
Compiler output path is the path to the directory in which IntelliJ IDEA stores the compilation results. Click the Browse icon to select the output directory. In this directory, the IDE creates two sub-directories:

production for production code.

test for test sources.

In these subdirectories, individual output directories will be created for each of your modules.

# Module
---
- In IntelliJ IDEA, a module is an essential part of any project – it's created automatically together with a project. Projects can contain multiple modules – you can add new modules, group them, and unload the modules you don't need at the moment.

- A module is composed of the `.iml` file that keeps internal representation of module settings and the so-called content root, which stores your source code, resources, tests, and so on.

- Generally, modules consist of one or several content roots and a module file, however, modules can exists without content roots. A content root is a folder where you store your code. Usually, it contains subfolders for source code, unit tests, resource files, and so on. A module file (the .iml file) is used for keeping module configuration.

- Modules allow you to combine several technologies and frameworks in one application. In IntelliJ IDEA, you can create several modules for a project and each of them can be responsible for its own framework.

<figure align="center">
  <img src="https://user-images.githubusercontent.com/64415489/161387492-83ac7c31-487a-4687-a8dc-83e5665ea56a.png" width="80%"/>
  <figcaption align="center">출처 : <a href="https://www.jetbrains.com/help/idea/working-with-projects.html#settings-types" target="_blank"> https://www.jetbrains.com/help/idea/working-with-projects.html#settings-types</a> </figcaption>
</figure>

- IntelliJ IDEA allows you to have many modules in one project, and they shouldn't be just Java. You can have one module for a Java application and another module for a Ruby on Rails application or for any other supported technology.

- An application that consists of a client side and a server side is a good example a two-module project.


# 정리
> [해당 글](https://intellij-support.jetbrains.com/hc/en-us/community/posts/206887325-Difference-between-project-and-module
)을 해석했습니다.

- A project can contain one or more modules. Each module is a separate library, web app, etc. So, for example, if you have a web app and a separate server-side application, you might develop them in concert, one module for each application but the same project. Each module is for a single "type" of packaged code, e.g., a jar file, war file, etc. Modules aren't just Java either, so you could have one module for a Java application and another module for a Ruby on Rails application. In general a project will contain related modules, applications, libraries, etc. that are interdependent and are developed in concert.

# 참고 자료
---
- [https://www.jetbrains.com/help/idea/working-with-projects.html#settings-types](https://www.jetbrains.com/help/idea/working-with-projects.html#settings-types)
- [https://www.jetbrains.com/help/idea/working-with-projects.html](https://www.jetbrains.com/help/idea/working-with-projects.html)
- [https://www.jetbrains.com/help/idea/project-settings-and-structure.html](https://www.jetbrains.com/help/idea/project-settings-and-structure.html)
- [https://www.jetbrains.com/help/idea/creating-and-managing-modules.html](https://www.jetbrains.com/help/idea/creating-and-managing-modules.html)
- [https://intellij-support.jetbrains.com/hc/en-us/community/posts/206887325-Difference-between-project-and-module
](https://intellij-support.jetbrains.com/hc/en-us/community/posts/206887325-Difference-between-project-and-module
)
