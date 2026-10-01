---
title: Gradle 멀티 프로젝트
date: 2023-12-01 20:20:00 +0900
---

# Multi-Project (multi-module project)
![image](https://github.com/zz9z9/zz9z9.github.io/assets/64415489/01e002d1-8172-4d93-a076-14c07cd52271)

- While some small projects and monolithic applications may contain a single build file and source tree, it is often more common for a project to have been split into smaller, interdependent modules.
- The word "interdependent" is vital, as you typically want to link the many modules together through a single build.
- Gradle supports this scenario through multi-project builds.
- This is sometimes referred to as a multi-module project.
- A multi-project build consists of one root project and one or more subprojects.

# Multi-Project 구조
- The following represents the structure of a multi-project build that contains two subprojects:
  - The settings.gradle.kts file should include all subprojects.
  - Each subproject should have its own build.gradle.kts file.

<img width="317" alt="image" src="https://github.com/zz9z9/zz9z9.github.io/assets/64415489/8f98b792-3b21-4c2e-adde-e0b56a73fc2f">

# Multi-Project 표준
> The Gradle community has two standards for multi-project build structures:

- Multi-Project Builds using buildSrc
  - where `buildSrc` is a subproject-like directory at the Gradle project root containing all the build logic.

- Composite Builds
  - a build that includes other builds where `build-logic` is a build directory at the Gradle project root containing all the build logic.

<img width="615" alt="image" src="https://github.com/zz9z9/zz9z9.github.io/assets/64415489/030de0ad-457e-4b5f-8e1b-77362c26b503">

# Multi-Project building and testing
- The build task is typically used to compile, test, and check a single project.
- In multi-project builds, you may often want to do all of these tasks across various projects.
- The `buildNeeded` and `buildDependents` tasks can help with this.

- 아래 예시의 구조에서, the :services:person-service project depends on both the :api and :shared projects.
- The :api project also depends on the :shared project.

```
.
├── buildSrc
│   ...
├── api
│   ├── src
│   │   └──...
│   └── build.gradle
├── services
│   └── person-service
│       ├── src
│       │   └──...
│       └── build.gradle
├── shared
│   ├── src
│   │   └──...
│   └── build.gradle
└── settings.gradle
```

- Assuming you are working on a single project, the :api project, you have been making changes but have not built the entire project since performing a `clean`.
- You want to build any necessary supporting JARs but only perform code quality and unit tests on the parts of the project you have changed.
- The `build` task does this:
```
$ gradle :api:build

> Task :shared:compileJava
> Task :shared:processResources
> Task :shared:classes
> Task :shared:jar
> Task :api:compileJava
> Task :api:processResources
> Task :api:classes
> Task :api:jar
> Task :api:assemble
> Task :api:compileTestJava
> Task :api:processTestResources
> Task :api:testClasses
> Task :api:test
> Task :api:check
> Task :api:build

BUILD SUCCESSFUL in 0s
```

- If you have just gotten the latest version of the source from your version control system, which included changes in other projects that :api depends on, you might want to build all the projects you depend on AND test them too.
- The `buildNeeded` task builds AND tests all the projects from the project dependencies of the testRuntime configuration:
```
$ gradle :api:buildNeeded

> Task :shared:compileJava
> Task :shared:processResources
> Task :shared:classes
> Task :shared:jar
> Task :api:compileJava
> Task :api:processResources
> Task :api:classes
> Task :api:jar
> Task :api:assemble
> Task :api:compileTestJava
> Task :api:processTestResources
> Task :api:testClasses
> Task :api:test
> Task :api:check
> Task :api:build
> Task :shared:assemble
> Task :shared:compileTestJava
> Task :shared:processTestResources
> Task :shared:testClasses
> Task :shared:test
> Task :shared:check
> Task :shared:build
> Task :shared:buildNeeded
> Task :api:buildNeeded

BUILD SUCCESSFUL in 0s
```

- You may want to refactor some part of the :api project used in other projects.
- If you make these changes, testing only the :api project is insufficient.
- You must test all projects that depend on the :api project.
- The `buildDependents` task tests ALL the projects that have a project dependency (in the testRuntime configuration) on the specified project:

```
$ gradle :api:buildDependents

> Task :shared:compileJava
> Task :shared:processResources
> Task :shared:classes
> Task :shared:jar
> Task :api:compileJava
> Task :api:processResources
> Task :api:classes
> Task :api:jar
> Task :api:assemble
> Task :api:compileTestJava
> Task :api:processTestResources
> Task :api:testClasses
> Task :api:test
> Task :api:check
> Task :api:build
> Task :services:person-service:compileJava
> Task :services:person-service:processResources
> Task :services:person-service:classes
> Task :services:person-service:jar
> Task :services:person-service:assemble
> Task :services:person-service:compileTestJava
> Task :services:person-service:processTestResources
> Task :services:person-service:testClasses
> Task :services:person-service:test
> Task :services:person-service:check
> Task :services:person-service:build
> Task :services:person-service:buildDependents
> Task :api:buildDependents

BUILD SUCCESSFUL in 0s
```

- Finally, you can build and test everything in all projects.
- Any task you run in the root project folder will cause that same-named task to be run on all the children.
- You can run gradle build to build and test ALL projects.




# 실전 적용
=> https://techblog.woowahan.com/2637/
=> https://www.youtube.com/watch?v=ipDzLJK-7Kc

상품권 플젝
=> 상품권몰이랑 나머지 플젝들 하나로 합치기 ??

# 참고자료
---
- https://docs.gradle.org/current/userguide/intro_multi_project_builds.html
