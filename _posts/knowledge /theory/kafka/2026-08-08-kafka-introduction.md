---
title: 카프카 개요
date: 2026-08-08 22:25:00 +0900
categories: [지식 더하기, 카프카]
tags: [Kafka]
---

## 카프카란 ?

---

> [공식 사이트](https://kafka.apache.org/)에서는 "Apache Kafka is an open-source distributed **event streaming platform**"라고 표현

아래는 카프카 에코시스템 구성도로, 외부 시스템을 제외한 모든 게 Apache Kafka **에코시스템**에 포함된다.

단, Schema Registry와 일부 Connect 커넥터 등은 **Confluent 제품**이며 Apache Kafka 코어에는 포함되지 않는다.

<details markdown="1">
<summary>카프카 에코시스템 구성도</summary>

<img src="/assets/img/kafka-introduction-img1.png" alt="Kafka 에코시스템 구성도 - Producers, Brokers, Consumers, Streams, Connect와 외부 시스템" width="50%" height="70%"/>

</details>

## 이벤트란 ?

---

> "어떤 일이 일어났다"는 사실의 기록

- Producer가 보내는 이벤트는 네 가지 요소로 구성:
  - **key** — **파티셔닝의 기준** (같은 key → 같은 파티션 → 순서 보장). 분류 자체는 토픽이 담당
  - **value** — 실제 내용
  - **timestamp** — 발생 시각
  - **headers** — 부가 정보 (선택)
- Kafka가 추가로 부여하는 식별자:
  - **partition, offset** — 메시지의 위치를 유일하게 식별 (replay·재처리의 기준)

### 이벤트 예시

주문 도메인에서 발행되는 `OrderCreated` 이벤트를 예로 들면 다음과 같다.

```
key       : "order-1001"                        // 같은 주문ID는 같은 파티션 → 순서 보장
value     : {
              "orderId": "order-1001",
              "userId": "user-42",
              "amount": 59000,
              "items": [{ "sku": "A-1", "qty": 2 }]
            }
timestamp : 2026-05-24T22:13:21.096+09:00
headers   : {
              "event-type":     "OrderCreated",
              "schema-version": "v3",
              "trace-id":       "9f1c...e2"
            }

// ↓ Kafka가 부여
topic     : "order-events"
partition : 4
offset    : 28173
```

- **key를 orderId로 두는 이유** : 같은 주문에 대한 후속 이벤트(`OrderPaid`, `OrderShipped`)가 동일 파티션에 적재되어 **순서가 보장**됨
- **headers의 용도** : `event-type`, `schema-version`, `trace-id` 등 **value를 역직렬화하지 않고도** 라우팅/필터링/관측에 쓸 수 있는 메타정보
- **value 포맷** : 위 예시는 JSON이지만 실무에서는 Avro / Protobuf가 자주 쓰임 (아래 "이벤트 포맷" 참고)

### 이벤트 포맷

**브로커는 페이로드(value)에 관여하지 않는다.** 직렬화/역직렬화·스키마 검증은 모두 Producer/Consumer의 몫이다.

- 따라서 어떤 포맷을 쓸지는 전적으로 Producer와 Consumer가 **합의**해야 함
- 다만 실무에서는 합의를 코드/문서로만 유지하기 어렵기 때문에, **Schema Registry**(Confluent 제품)를 함께 쓰는 경우가 많음
  - **Avro / Protobuf / JSON Schema** 로 스키마를 등록하고, Producer/Consumer가 동일 스키마를 참조하도록 강제
  - 스키마 호환성 규칙(`BACKWARD` / `FORWARD` / `FULL`)으로 **스키마 진화(evolution)** 를 안전하게 관리
  - 메시지에는 실제 스키마 대신 **스키마 ID만** 포함되어 페이로드 크기도 절감

포맷별 특징을 정리하면 다음과 같다.

| 포맷 | 장점 | 단점 |
| --- | --- | --- |
| JSON | 사람이 읽기 쉬움, 디버깅 편함 | 용량 큼, 스키마 강제 어려움 |
| Avro | 컴팩트, 스키마 진화 강력, Kafka 생태계 표준 | 사람이 읽기 어려움, Schema Registry 의존 |
| Protobuf | 컴팩트, gRPC와 궁합 좋음, 다언어 지원 | 진화 규칙 학습 필요 |

- 정리:
  - **브로커 관점** : 페이로드는 그냥 바이트 → 포맷에 무관
  - **생태계 관점** : Schema Registry로 포맷·스키마를 **계약(contract)** 으로 강제하는 게 일반적

## 이벤트 스트리밍

---

> 데이터베이스, 센서, 모바일 기기 등에서 발생하는 데이터를 실시간으로 **캡처하고, 저장하고, 처리하고, 필요한 곳으로 라우팅**하는 기술

- 이벤트 스트리밍 플랫폼이라고 부르는 건, **단순히 이벤트를 전달하는 브로커 역할을 넘어서** 네 가지를 다 하기 때문:
  - **캡처** : Producer API로 이벤트 **발행(publish)**
  - **저장** : 토픽에 이벤트를 **retention 정책(기본 7일, `retention.ms` / `retention.bytes` / compaction)** 에 따라 보관
  - **라우팅** : **토픽 구독 모델**로 여러 서비스에 전달
    - 서로 다른 Consumer Group은 같은 데이터를 **각자 독립적으로 모두** 수신
    - 한 Consumer Group **내부**에서는 파티션 단위로 분배 (= 워크로드 분산)
    - ⚠ RabbitMQ exchange처럼 "메시지 내용 기반 라우팅"이 아님
  - **처리** : **Kafka Streams**(Apache Kafka 포함)로 스트림 데이터를 직접 가공
    - ksqlDB로도 가능하나, 이는 **Confluent 제품**이며 Apache Kafka 코어에는 포함되지 않음
    - ex : `order` 토픽 → 필터(5만원 이상) → `vip-order` 토픽
    - 토픽에서 토픽으로 **데이터가 흐르면서 가공되는 파이프라인을 Kafka 자체적으로** 만들 수 있음
- 즉, Kafka는 데이터를 수집하고, 보관하고, 흘려보내고, 가공까지 하는 **통합 플랫폼**

## 왜 events가 아닌 streams of events라고 표현할까 ?

---

> 공식 문서 : *"To publish (write) and subscribe to (read) streams of events ..."*

- 일반적인 메시지 큐 (예: RabbitMQ)는 이벤트를 **소비(ack) 시점에 큐에서 제거하는 구조**
  - Consumer가 메시지를 받고 **ack**하면 큐에서 사라짐 (ack 안 하면 다른 Consumer에게 재전달)
  - 관심사는 **"이 메시지를 누군가 처리했는가"**
  - fanout exchange 등으로 멀티 컨슈머 브로드캐스트는 가능하지만, **이미 소비된 메시지를 과거 시점부터 다시 읽는 개념은 없음**
- Kafka는 이벤트를 **흐름 자체로 보존**하는 구조 (retention 기간 내)
  - Consumer가 읽어도 데이터는 그대로 남아있고, 여러 Consumer Group이 같은 흐름을 **각자 다른 offset부터** 읽을 수 있음
  - 소비 위치(offset)는 Consumer 측이 관리 → 브로커는 "누가 어디까지 읽었는지"에 관여하지 않음
- 그래서 Kafka가 "streams of events"라고 표현한 진짜 의미는 단순히 "이벤트가 연속으로 온다"가 아니라, **연속된 흐름 자체를 하나의 데이터로 보존하고 다룬다**는 뜻
- 이 차이 때문에 Kafka에서는 "어제 들어온 주문 흐름을 처음부터 다시 재생(replay)"하는 게 가능 (단, **retention 기간 내**의 데이터에 한함)

## 탄생 배경 & 핵심 개념

---

> LinkedIn에서 2010년경 Jay Kreps · Neha Narkhede · Jun Rao가 설계. 회원·콘텐츠·활동 데이터가 폭증하면서 **데이터 파이프라인 자체가 가장 큰 부채**가 된 상황을 풀기 위해 출발.

### 문제 → 해결 매핑

| # | 문제 | 당시 상황 | 해결 방안 (핵심 개념) | 비고 (링크 / 핵심 인용) |
| --- | --- | --- | --- | --- |
| **P1** | N×M 파이프라인 폭발 | source N개 × sink M개 → 통합 코드 N×M개. 시스템 추가될 때마다 모든 곳을 손봐야 함 | **① 토픽 기반 Pub/Sub** — Producer는 토픽에 발행, Consumer는 토픽을 구독. 양쪽이 서로를 모름 → 통합 비용이 **N+M**으로 떨어짐 | [Introduction](https://kafka.apache.org/42/getting-started/introduction/)<br>[The Log (Kreps)](https://web.archive.org/web/20240105095933/https://engineering.linkedin.com/distributed-systems/log-what-every-software-engineer-should-know-about-real-time-datas-unifying) |
| **P2** | 소비 후 사라짐 | 전통 MQ(ActiveMQ, RabbitMQ)는 ack 시 메시지 삭제 → 같은 데이터를 분석·모니터링·검색에 **재사용 불가** | **② 로그 영속성 + Offset 기반 소비** — append-only log에 영구 저장, offset은 Consumer가 관리. 여러 Consumer가 각자 다른 시점부터 읽기/replay 가능 | [Design §4.5 Consumer — Consumer Position](https://kafka.apache.org/42/design/design/#consumer-position)<br>💬 *"the consumer simply falls behind and catches up when it can"* ([§ Push vs. pull](https://kafka.apache.org/42/design/design/#push-vs-pull)) |
| **P3** | 실시간 ↔ 배치 파이프라인 이중화 | OLTP DB는 백로그 적재용, MQ는 실시간용 → 같은 데이터를 **두 번 파이프**해야 했음 | **③ 로그 = Storage System** — retention 정책으로 시간/용량 단위 보존(무제한도 가능). 같은 토픽을 실시간 스트림 처리 + 배치 적재에 동시 사용 | [Use Cases](https://kafka.apache.org/42/getting-started/uses/)<br>[The Log (Kreps)](https://web.archive.org/web/20240105095933/https://engineering.linkedin.com/distributed-systems/log-what-every-software-engineer-should-know-about-real-time-datas-unifying) — 이 글의 핵심 주장 |
| **P4** | 단일 노드 처리량 한계 | 활동 로그·메트릭 같은 대량 이벤트는 단일 브로커로 감당 불가 | **④ 파티션 + Consumer Group** — 토픽을 파티션 N개로 쪼개 여러 브로커에 분산. Consumer Group 내에서 파티션을 분배해 병렬 소비. key 기반 파티셔닝으로 순서도 함께 보장 | [Introduction § Main Concepts](https://kafka.apache.org/42/getting-started/introduction/#main-concepts-and-terminology) — 파티션·Consumer Group 정의<br>[Design §4.5 Consumer](https://kafka.apache.org/42/design/design/#the-consumer) — Consumer Group 동작 |
| **P5** | Push 모델의 위험 | 빠른 producer가 느린 consumer를 죽임 (back-pressure 부재) | **⑤ Pull 모델** — Consumer가 자기 페이스로 broker에서 pull. 자연스러운 back-pressure 확보 | [Design §4.5 Consumer — Push vs. pull](https://kafka.apache.org/42/design/design/#push-vs-pull) |
| **P6** | 장애 시 데이터 손실 | 단일 브로커 장애 = 메시지 손실. fault-tolerance가 부수 기능 수준 | **⑥ Replication (Leader/Follower + ISR)** — 파티션 단위 leader 1 + follower N 복제. leader를 거의 따라잡은 replica 집합 = ISR(In-Sync Replicas) | [Design §4.7 Replication](https://kafka.apache.org/42/design/design/#replication)<br>💬 *"a committed message will not be lost, as long as there is at least one in sync replica alive."* |
| **P7** | "디스크는 느리다"는 통념 | 빠른 처리를 위해 in-memory MQ 외 선택지 없어 보임 → 영속성 vs 성능 trade-off | **⑦ 순차 I/O + Page Cache + Zero-Copy + 배칭** — 순차 디스크 쓰기 / OS page cache 활용(JVM heap 절약) / `sendfile`로 복사 없이 네트워크 전송 / Producer·Broker·Consumer 공유 바이너리 포맷으로 배칭 → 디스크 기반인데도 **메모리 MQ급 처리량** | [Design §4.2 Persistence](https://kafka.apache.org/42/design/design/#persistence)<br>[Design §4.3 Efficiency](https://kafka.apache.org/42/design/design/#efficiency)<br>💬 *"All data is immediately written to a persistent log on the filesystem without necessarily flushing to disk."* |

## 참고 자료

---

- [The Log: What every software engineer should know about real-time data's unifying abstraction (web.archive.org)](https://web.archive.org/web/20240105095933/https://engineering.linkedin.com/distributed-systems/log-what-every-software-engineer-should-know-about-real-time-datas-unifying) — Jay Kreps, 2013. 정전(canonical) 글. LinkedIn 엔지니어링 블로그 원본이 내려가서 웹 아카이브 스냅샷으로 연결
- [Kafka: a Distributed Messaging System for Log Processing (notes.stephenholiday.com)](https://notes.stephenholiday.com/Kafka.pdf) — Kreps/Narkhede/Rao, NetDB 2011. 원논문
- [Putting Apache Kafka to Use: A Practical Guide to Building an Event Streaming Platform, Part 1 (confluent.io)](https://www.confluent.io/blog/event-streaming-platform-1/) — Kreps의 회고, 2015
- [Apache Kafka Design 문서 (kafka.apache.org/42/design/design)](https://kafka.apache.org/42/design/design/)
- [Apache Kafka Introduction (kafka.apache.org/42/getting-started/introduction)](https://kafka.apache.org/42/getting-started/introduction/)
- [Apache Kafka Use Cases (kafka.apache.org/42/getting-started/uses)](https://kafka.apache.org/42/getting-started/uses/)
