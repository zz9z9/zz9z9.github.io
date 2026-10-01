---
title: Maven 프로젝트 구조
date: 2024-08-27 22:00:00 +0900
---

# Maven 프로젝트 구조
> Having a common directory layout allows users familiar with one Maven project to immediately feel at home in another Maven project. The advantages are analogous to adopting a site-wide look-and-feel.
> Try to conform to this structure as much as possible. However, if you can't, these settings can be overridden via the project descriptor.

| 디렉토리| 정의 |
| ------------- | --------------------------- |
| `src/main/java` | Application/Library sources |
| `src/main/resources` | Application/Library resources |
| `src/main/filters` | Resource filter files |
| `src/main/webapp` | Web application sources |
| `src/test/java` | Test sources |
| `src/test/resources` | Test resources |
| `src/test/filters` | Test resource filter files |
| `src/it` | Integration Tests (primarily for plugins) |
| `src/assembly` | Assembly descriptors |
| `src/site` | Site |
| `LICENSE.txt` | Project's license |
| `NOTICE.txt` | Notices and attributions required by libraries that the project depends on |
| `README.txt` | Project's readme |

<img width="233" alt="image" src="https://github.com/user-attachments/assets/cbb87e75-494d-46f5-93aa-70000b8bdb60">


## 참고 자료
- https://maven.apache.org/guides/introduction/introduction-to-the-standard-directory-layout.html
