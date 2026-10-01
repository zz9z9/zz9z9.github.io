---
title: Gradle 빌드 라이프사이클
date: 2023-12-01 20:20:00 +0900
---

# Build Phases
<img width="627" alt="image" src="https://github.com/zz9z9/zz9z9.github.io/assets/64415489/f40fc9c7-1d13-4f88-88d7-d49fb160816c">

## Phase 1. Initialization
- Detects the settings.gradle(.kts) file.
- Creates a Settings instance.
- Evaluates the settings file to determine which projects (and included builds) make up the build.
- Creates a Project instance for every project.

## Phase 2. Configuration
- Evaluates the build scripts, build.gradle(.kts), of every project participating in the build.
- Creates a task graph for requested tasks.

## Phase 3. Execution
- Schedules and executes the selected tasks.
- Dependencies between tasks determine execution order.
- Execution of tasks can occur in parallel.

## 예시
```groovy
[settings.gradle]
rootProject.name = 'basic'
println 'This is executed during the initialization phase.'

[build.gradle]
println 'This is executed during the configuration phase.'

tasks.register('configured') {
    println 'This is also executed during the configuration phase, because :configured is used in the build.'
}

tasks.register('test') {
    doLast {
        println 'This is executed during the execution phase.'
    }
}

tasks.register('testBoth') {
	doFirst {
	  println 'This is executed first during the execution phase.'
	}
	doLast {
	  println 'This is executed last during the execution phase.'
	}
	println 'This is executed during the configuration phase as well, because :testBoth is used in the build.'
}
```

- The following command executes the test and testBoth tasks specified above. Because Gradle only configures requested tasks and their dependencies, the configured task never configures:
```
> gradle test testBoth
This is executed during the initialization phase.

> Configure project :
This is executed during the configuration phase.
This is executed during the configuration phase as well, because :testBoth is used in the build.

> Task :test
This is executed during the execution phase.

> Task :testBoth
This is executed first during the execution phase.
This is executed last during the execution phase.

BUILD SUCCESSFUL in 0s
2 actionable tasks: 2 executed
```

# 참고자료
---
- https://docs.gradle.org/current/userguide/build_lifecycle.html
