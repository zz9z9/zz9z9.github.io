---
title: Gradle 빌드 파일
date: 2023-12-04 20:20:00 +0900
---

# Gradle Build
- The initialization phase in the Gradle Build lifecycle finds the root project and subprojects included in your project root directory using the settings file.
- Then, for each project included in the settings file, Gradle creates a [Project](https://docs.gradle.org/current/dsl/org.gradle.api.Project.html) instance.
- Gradle then looks for a corresponding build script file, which is used in the configuration phase.

<img width="642" alt="image" src="https://github.com/zz9z9/zz9z9.github.io/assets/64415489/7d015ee6-4be0-45d3-b2d9-49cb35690865">


# Build Script
- Every Gradle build comprises one or more projects; a root project and subprojects.
- A project typically corresponds to a software component that needs to be built, like a library or an application.
- It might represent a library JAR, a web application, or a distribution ZIP assembled from the JARs produced by other projects.
- On the other hand, it might represent a thing to be done, such as deploying your application to staging or production environments.
- Gradle scripts are written in either Groovy DSL or Kotlin DSL (domain-specific language).
- A build script configures a project and is associated with an object of type Project.
- As the build script executes, it configures Project.

<img width="480" alt="image" src="https://github.com/zz9z9/zz9z9.github.io/assets/64415489/1e797395-e4b0-4a56-9639-82e6c1cc5b92">


# 참고자료
---
- https://docs.gradle.org/current/userguide/writing_build_scripts.html
