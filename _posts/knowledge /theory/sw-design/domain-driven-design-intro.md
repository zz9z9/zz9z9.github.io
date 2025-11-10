---
title: DDD(Domain-Driven-Design) 살펴보기
date: 2025-11-10 22:25:00 +0900
categories: [지식 더하기, 이론]
tags: [설계]
---

> 어떤 장점과 단점이 있을까 (유지보수하기 더 좋은 부분과 안좋은 부분 ?)
> 코드 구성이 달라지는건가 ?

트랜잭션 스크립트 패턴

일반적인 방식과 차이

목표: 복잡한 비즈니스 로직을 모델링하고 코드와 도메인 지식을 일치시키는 것
핵심 아이디어: Ubiquitous Language, Bounded Context, Aggregates, Entities, Value Objects 등

## 핵심 개념
---

### Bounded Context
- 각 컨텍스트는 명확한 경계를 갖는다.
- 이로 인해 시스템의 복잡성을 제어할 수 있다 ?

### Entity
- 엔티티의 제어는 항상 AggregateRoot를 통해 가능하다 ?

### Aggregate
- Aggregate Root
  - Aggregate를 대표하고 외부와의 모든 인터페이스를 책임지는 객체
  - 불변성 유지, 트랜잭션 경계 설정, 내부 객체 보호

## 실전 사례 참고
---

https://techblog.lycorp.co.jp/ko/applying-ddd-to-merchant-system-development
https://tech.kakaopay.com/post/backend-domain-driven-design/
https://helloworld.kurly.com/blog/road-to-ddd/
https://tech.kakao.com/posts/555
https://blog.hwahae.co.kr/all/tech/15004
https://blog.tesser.io/applying-domain-driven-development/
https://helloworld.kurly.com/blog/ddd-msa-service-development/
