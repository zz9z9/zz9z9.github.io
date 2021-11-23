---
title: 스프링 배치 핵심 개념 살펴보기
date: 2021-11-23 22:25:00 +0900
categories: [Spring Batch]
tags: [Job, Step, ]
---

# 들어가기 전
---
해당 글은 [스프링 배치 공식 문서](https://docs.spring.io/spring-batch/docs/4.3.x/reference/html/domain.html#domainLanguageOfBatch)의 내용을 공부하면서 정리한 글입니다.


# 일반적인 배치 구조
---
- 아래 다이어그램은 수십 년 동안 사용된 배치 참조 아키텍처를 단순하게 표현한 것으로, 배치 처리에 필요한 구성 요소의 개요를 보여준다.
- `Job`에는 하나의 단계부터 여러 단계가 있으며, 각 단계에는 하나의 `ItemReader`, `ItemProcessor`, `ItemWriter`가 있다.
- `JobLauncher`를 사용하여 작업을 시작하고, 현재 실행 중인 프로세스에 대한 메타데이터를 `JobRepository`에 저장해야 한다.

![image](https://user-images.githubusercontent.com/64415489/143042927-c1b7e167-c17e-4dde-9778-b203434f8eec.png)

# Job
---

