---
title: Gradle 입문(2)
date: 2023-11-30 20:20:00 +0900
---

# 의존성 관리
- Gradle has built-in support for dependency management.
- Dependency management is an automated technique for declaring and resolving external resources required by a project.
- Gradle build scripts define the process to build projects that may require external dependencies.
- Dependencies refer to JARs, plugins, libraries, or source code that support building your project.

## 버전 카탈로그
- Version catalogs provide a way to centralize your dependency declarations in a `libs.versions.toml` file.
- The catalog makes sharing dependencies and version configurations between subprojects simple.
- It also allows teams to enforce versions of libraries and plugins in large projects.
- The version catalog typically contains four sections:
  - `[versions]` to declare the version numbers that plugins and libraries will reference.
  - `[libraries]` to define the libraries used in the build files.
  - `[bundles]` to define a set of dependencies.
  - `[plugins]` to define plugins.

```groovy
[versions]
androidGradlePlugin = "7.4.1"
mockito = "2.16.0"

[libraries]
google-material = { group = "com.google.android.material", name = "material", version = "1.1.0-alpha05" }
mockito-core = { module = "org.mockito:mockito-core", version.ref = "mockito" }

[plugins]
android-application = { id = "com.android.application", version.ref = "androidGradlePlugin" }
```

- The file is located in the `gradle` directory so that it can be used by Gradle and IDEs automatically.
- The version catalog should be checked into source control: `gradle/libs.versions.toml`.

## 의존성 선언
- To add a dependency to your project, specify a dependency in the dependencies block of your `build.gradle(.kts)` file.
- The following `build.gradle.kts` file adds a plugin and two dependencies to the project using the version catalog above:
```
plugins {
   alias(libs.plugins.android.application) (1)
}

dependencies {
    // Dependency on a remote binary to compile and run the code
    implementation(libs.google.material)   (2)

    // Dependency on a remote binary to compile and run the test code
    testImplementation(libs.mockito.core)  (3)
}
```

- (1) : Applies the Android Gradle plugin to this project, which adds several features that are specific to building Android apps.

- (2) : Adds the Material dependency to the project. Material Design provides components for creating a user interface in an Android App. This library will be used to compile and run the Kotlin source code in this project.

- Adds the Mockito dependency to the project. Mockito is a mocking framework for testing Java code. This library will be used to compile and run the test source code in this project.

- Dependencies in Gradle are grouped by configurations.
  - The material library is added to the `implementation` configuration, which is used for **compiling and running production code.**
  - The mockito-core library is added to the `testImplementation` configuration, which is used for **compiling and running test code.**

# Plugin이란 ?
- Plugins are the primary method to organize build logic and reuse build logic within a project.
  - 예를 들어  ability to compile Java code, are added by plugins.
- Plugins can provide useful tasks with capabilities such as running code, creating documentation, setting up source files, publishing archives, etc.
- Applying a plugin to a project executes code that can create tasks, configure properties, and otherwise extend the project’s capabilities.
  - The Spring Boot Gradle Plugin, `org.springframework.boot`, provides Spring Boot support.
  - The Google Services Gradle Plugin, `com.google.gms:google-services`, enables Google APIs and Firebase services in your Android application.
  - The Gradle Shadow Plugin, `com.github.johnrengelman.shadow`, is a plugin that generates fat/uber JARs with support for package relocation.
- Generally, plugins use the Gradle API **to provide additional functionality and extend Gradle’s core features.**

- Plugins can:
  - Add tasks to the project (e.g. compile, test).
  - Extend the basic Gradle model (e.g. add new DSL elements that can be configured).
  - Configure the project, according to conventions (e.g. add new tasks or configure sensible defaults).
  - Apply specific configuration (e.g. add organizational repositories or enforce standards).
  - Add new properties and methods to existing types via extensions.

## Plugin 추가해보기
- Let’s apply a plugin to our project that is maintained and distributed by Gradle called the Maven Publish Plugin.
- The Maven Publish Plugin provides the ability to publish build artifacts to an Apache Maven repository.
- It can also publish to Maven local which is a repository located on your machine.
- The default location for Maven local repository may vary but is typically:
```
Mac: /Users/\[username]/.m2
Linux: /home/\[username]/.m2
Windows: C:\Users\[username]\.m2
```

- Apply the plugin by adding `maven-publish` to the plugins block in build.gradle.kts:
```groovy
plugins {
    // Apply the application plugin to add support for building a CLI application in Java.
    application
    `maven-publish`
}
```

```
$ ./gradlew :app:tasks

> Task :app:tasks

------------------------------------------------------------
Tasks runnable from project ':app'
------------------------------------------------------------

...

Publishing tasks
----------------
publish - Publishes all publications produced by this project.
publishToMavenLocal - Publishes all Maven publications produced by this project to the local Maven cache.
```

- A new set of publishing tasks are now available called publish, and publishToMavenLocal.

## Plugin 둘러보기
- Plugins are used to extend build capability and customize Gradle.
- Using plugins is the primary mechanism for organizing build logic.
- Plugin authors can either keep their plugins private or distribute them to the public. As such, plugins are distributed three ways:
    - Core plugins - Gradle develops and maintains a set of [Core Plugins](https://docs.gradle.org/current/userguide/plugin_reference.html#plugin_reference).
    - Community plugins - Gradle’s community shares plugins via the [Gradle Plugin Portal](https://plugins.gradle.org/?_gl=1*1ne8wbl*_ga*Njk1MzI2MzYuMTcwMTA5MDEzMw..*_ga_7W7NC6YNPT*MTcwMTM0NzYwNy42LjEuMTcwMTM1MDkzNC42MC4wLjA.).
    - Custom plugins - Gradle enables user to create custom plugins using [APIs](https://docs.gradle.org/current/dsl/org.gradle.api.tasks.javadoc.Javadoc.html).

- [Convention plugins](https://docs.gradle.org/current/samples/sample_convention_plugins.html) are plugins used to share build logic between subprojects (modules). Users can wrap common logic in a convention plugin.
- For example, a code coverage plugin used as a convention plugin can survey code coverage for the entire project and not just a specific subproject.

# 참고자료
---
- https://docs.gradle.org/current/userguide/dependency_management_basics.html
- https://docs.gradle.org/current/userguide/plugin_basics.html
- https://docs.gradle.org/current/userguide/part4_gradle_plugins.html

- https://gradle.org/guides/?q=JVM
- https://spring.io/guides/gs/gradle/#scratch
- https://docs.gradle.org/current/userguide/part1_gradle_init.html
