---
title: 카프카 전달보증 구현하기 - Exactly Once
date: 2021-07-29 14:00:00 +0900
categories: [Kafka]
tags: [Kafka, delivery-guarantees, exactly-once]
---

# Exactly Once
---
> 카프카는 초기에 `at-most-once`와 `at-least-once` 수준의 전달 보증만 지원했었다. <br>
> 하지만, 카프카의 유용성이 높아지면서 Exactly Once 수준의 전달을 보증하고자 하는 요구가 높아졌다. <br>
> 이를 위해 카프카에 ***트랜잭션*** 개념이 도입되었다.
> `exactly-once` 전달 보증은 0.11 버전부터(Released June 28, 2017, [참고](https://kafka.apache.org/downloads) ) `idempotent`와 `transactional producers` 두 가지 옵션을 통해 지원한다.

- idempotent option
  - 동일 옵션을 사용하면 중복 항목이 더 이상 발생하지 않습니다. (The idempotent option will no longer introduce duplicates.)
- transactional producer
  - 트랜잭션 생성기는 응용 프로그램이 여러 파티션에 메시지를 원자적으로 보낼 수 있도록 합니다. (allows an application to send messages to multiple partitions atomically.)

- `exactly-once` 전달 보증에서는 메시지는 한 번만 전달되며 메시지가 유실되지 않는디.
- `at-most-once`와 `at-least-once` 수준의 전달 보증에 비해 처리량이 낮고(lower throughput) 대기 시간(higher latency)이 더 길 수 있다.

# 구현하기
---
- To work with the transaction API, we'll need Kafka's Java client

```xml
<dependency>
    <groupId>org.apache.kafka</groupId>
    <artifactId>kafka-clients</artifactId>
    <version>2.0.0</version>
</dependency>

```


## 테스트 시나리오

## 테스트

### Producer 코드

### Consumer 코드

### 결과

트랜잭션 처리를 위한 STATE 같은게 있나 ??

# ???
---
Invalid transition attempted from state READY to state ABORTING_TRANSACTION
consumer.commitInSync랑 차이 ??
TransactionalId prod-0: Invalid transition attempted from state READY to state ABORTING_TRANSACTION

# 참고자료
---
- https://www.baeldung.com/kafka-exactly-once
- https://supergloo.com/kafka/kafka-architecture-delivery/
- https://blog.voidmainvoid.net/354
- https://dzone.com/articles/kafka-producer-delivery-semantics
