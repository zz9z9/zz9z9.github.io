---
title: Spring - Spring Boot 버전 현황 (25.07.26)
date: 2025-07-26 00:25:00 +0900
categories: [지식 더하기, 이론]
tags: [Spring]
---

## Spring Boot / Spring 릴리즈 및 지원 종료 일정
---

### Spring Boot
> Spring Boot는 6개월마다 새로운 메이저 또는 마이너 버전을 릴리스 (5월 / 11월) <br>
> (보통) 세 번째주 목요일에 릴리스를 목표로 함

| Branch | Initial Release | End of OSS Support | End Enterprise Support |
|--------|------------------|---------------------|-------------------------|
| `4.0.x` | 2025-11-20       | **2026-12-31**          | **2027-12-31**              |
| `3.5.x` | 2025-05-22       | **2026-06-30**          | **2032-06-30**              |
| `3.4.x` | 2024-11-21       | **2025-12-31**          | **2026-12-31**              |
| `3.3.x` | 2024-05-23       | 2025-06-30          | **2026-06-30**              |
| `3.2.x` | 2023-11-23       | 2024-12-31          | **2025-12-31**              |
| `3.1.x` | 2023-05-18       | 2024-06-30          | 2025-06-30              |
| `3.0.x` | 2022-11-24       | 2023-12-31          | 2024-12-31              |
| `2.7.x` | 2022-05-19       | 2023-06-30          | **2029-06-30**              |
| `2.6.x` | 2021-11-17       | 2022-11-24          | 2024-02-24              |
| `2.5.x` | 2021-05-20       | 2022-05-19          | 2023-08-24              |
| `2.4.x` | 2020-11-12       | 2021-11-18          | 2023-02-23              |
| `2.3.x` | 2020-05-15       | 2021-05-20          | 2022-08-20              |
| `2.2.x` | 2019-10-16       | 2020-10-16          | 2022-01-16              |
| `2.1.x` | 2018-10-30       | 2019-10-30          | 2021-01-30              |
| `2.0.x` | 2018-03-01       | 2019-03-01          | 2020-06-01              |
| `1.5.x` | 2017-01-30       | 2019-08-06          | 2020-11-06              |

### Spring

| Branch  | Initial Release | End of OSS Support | End Enterprise Support |
|---------|------------------|--------------------|-------------------------|
| `7.0.x` | 2025-11-13       | **2027-06-30**         | **2028-06-30**              |
| `6.2.x` | 2024-11-14       | **2026-06-30**       | **2032-06-30**              |
| `6.1.x` | 2023-11-16       | 2025-06-30         | **2026-06-30**              |
| `6.0.x` | 2022-11-16       | 2024-06-30         | 2025-06-30              |
| `5.3.x` | 2020-10-27       | 2023-06-30         | **2029-06-30**              |
| `5.2.x` | 2019-09-30       | 2021-12-31         | 2023-12-31              |
| `5.1.x` | 2018-09-21       | 2020-12-31         | 2022-12-31              |


**※ 참고**

| 항목       | OSS (무료)                                      | Enterprise (유료 – VMware Tanzu) |
| -------- | --------------------------------------------- | ------------------------------ |
| 비용     | 무료                                            | 유료 (라이선스 및 서비스 계약)             |
| 지원    | Spring 커뮤니티에서 Q&A (예: Stack Overflow, GitHub) | VMware Spring 팀의 공식 기술 지원      |
| 보안 패치 | 커뮤니티가 유지 (EOL 이후엔 없음)                         | **EOL 이후에도 보안 패치 및 버그 수정** 지원  |
| 업데이트 주기 | 공개 릴리스 일정에 따름                                 | 장기 지원(LTS) 보장 가능               |
| 대상 | 개인, 중소기업, 오픈소스 사용자                            | 대기업, 금융권, 정부, 고가용성 시스템 운영 조직   |

## 버전 호환성
---

### Spring / JDK / Java & Jakarta EE

| Branch    | JDK 지원 범위                 | Java/Jakarta EE 버전 지원 | 네임스페이스    |
| --------- | ------------------------- | --------------------- | --------- |
| **7.0.x** | JDK 17 ~ 27 *(예상)*       | Jakarta EE 11         | `jakarta` |
| **6.2.x** | JDK 17 ~ 25 *(예상)*       | Jakarta EE 9 ~ 10    | `jakarta` |
| **6.1.x** | JDK 17 ~ 23              | Jakarta EE 9 ~ 10    | `jakarta` |
| **6.0.x** | JDK 17 ~ 21              | Jakarta EE 9 ~ 10    | `jakarta` |
| **5.3.x** | JDK 8 ~ 21 *(5.3.26 기준)* | Java EE 7 ~ 8        | `javax`   |

- Spring은 장기 지원(JDK LTS) 버전에 대해 완전한 테스트와 지원을 제공.
  - 현재 기준 LTS 버전은 JDK 8, JDK 11, JDK 17, JDK 21
- 또한 JDK 18, 19, 20과 같은 중간 릴리즈 버전도 가능한 한 최선을 다해 지원
  - 즉, 버그 리포트는 수용하며 기술적으로 가능한 범위 내에서 해결하려고 노력하지만, 서비스 수준 보장(SLA)은 제공하지 않음
- Spring Framework 6.x 및 5.3.x를 운영 환경에서 사용할 경우, JDK 17 또는 21을 권장
- Spring Framework 5.3.x가 지원하는 마지막 명세는 javax 기반의 Java EE 8 (이 명세에는 Servlet 4.0, JPA 2.2, Bean Validation 2.0이 포함)
- Spring Framework 6.0부터는 최소 Jakarta EE 9을 필요로 하며, Servlet 5.0, JPA 3.0, Bean Validation 3.0을 포함
  - 최신인 Jakarta EE 10 (Servlet 6.0, JPA 3.1) 사용을 권장

### Spring Boot / JDK / Spring

| Spring Boot 버전 | 최소 Java 버전 | 필요 Spring Framework  | 비고                             |
| -------------- | ---------- | -------------------- | ------------------------------ |
| 4.0            | Java 17 이상 | Spring Framework 7.x | Kotlin 2.2+ 지원, 최신 LTS Java 권장 |
| 3.0            | Java 17 이상 | Spring Framework 6.0 | Java 8 미지원                     |
| 2.0            | Java 8 이상  | Spring Framework 5.0 | Java 6, 7 미지원                  |


**※ 참고 : Java EE / Jakarta EE ?**
> 웹, DB, 보안 등 기업용 기능을 위한 자바 API 명세 모음

**Java EE (Java Platform, Enterprise Edition)**
- Oracle이 주도하던 기업용 자바 표준 플랫폼
- 웹, 트랜잭션, 보안, 메시징 등 엔터프라이즈 애플리케이션 개발에 필요한 API들을 정의
- 주요 구성 요소:
  - Servlet API (웹 요청 처리)
  - JPA (자바 객체 ↔ 관계형 DB 매핑)
  - Bean Validation (입력 검증)
  - JMS (자바 메시지 서비스)
  - EJB, JAX-RS, 등

**Jakarta EE**
- Java EE의 후속 프로젝트로, 현재는 Eclipse Foundation이 주도
- Java EE 8까지는 `javax.*` 네임스페이스를 사용했지만, Jakarta EE 9부터는 모든 API가 `jakarta.*`로 바뀜

- Spring은 자체 프레임워크지만, 위와 같은 EE 스펙들을 내부적으로 사용하거나 호환되도록 설계되어 있음

| 기능              | 내부적으로 EE API 사용                                         |
| --------------- | ------------------------------------------------------- |
| WebMVC          | `Servlet API` 필요 (`javax.servlet` 또는 `jakarta.servlet`) |
| JPA 연동          | `jakarta.persistence` 또는 `javax.persistence`            |
| Bean Validation | `jakarta.validation` or `javax.validation`              |
| JSON 바인딩        | 일부 구현체가 EE API에 의존                                      |


## 참고 자료
- [https://spring.io/projects/spring-boot#support](https://spring.io/projects/spring-boot#support)
- [https://spring.io/projects/spring-framework#support](https://spring.io/projects/spring-framework#support)
- [https://github.com/spring-projects/spring-framework/wiki/Spring-Framework-Versions](https://github.com/spring-projects/spring-framework/wiki/Spring-Framework-Versions)
- [https://github.com/spring-projects/spring-boot/wiki/Supported-Versions](https://github.com/spring-projects/spring-boot/wiki/Supported-Versions)
- [https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-3.0-Migration-Guide](https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-3.0-Migration-Guide)
- [https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-4.0-Migration-Guide](https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-4.0-Migration-Guide)
