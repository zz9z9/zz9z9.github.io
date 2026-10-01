---
title: Gradle 빌드 라이프사이클
date: 2023-12-01 20:20:00 +0900
---

# Settings File
<img width="660" alt="image" src="https://github.com/zz9z9/zz9z9.github.io/assets/64415489/968fc838-9f42-41c7-bb8f-d2166242b557">

- Early in the Gradle Build lifecycle, the initialization phase finds the settings file in your project root directory.
- When the settings file settings.gradle(.kts) is found, Gradle instantiates a Settings object.
- One of the purposes of the Settings object is to allow you **to declare all the projects to be included in the build.**
- As the settings script executes, it configures this [Settings](https://docs.gradle.org/current/javadoc/org/gradle/api/initialization/Settings.html).
- Therefore, the settings file defines the Settings.

# Settings Object
> The Settings object is part of the Gradle API.

- Many top-level properties and blocks in a settings script are part of the Settings API.
- For example, we can set the root project name in the settings script using the Settings.rootProject property:
```
settings.rootProject.name = "root"
```

- Which is usually shortened to:
```
rootProject.name = "root"
```


# 참고자료
---
- https://docs.gradle.org/current/userguide/writing_settings_files.html
