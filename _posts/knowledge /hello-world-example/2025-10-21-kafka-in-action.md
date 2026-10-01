
- Apache Kafka® is a distributed event streaming platform that is used for building real-time data pipelines and streaming applications.
- Kafka is a distributed system consisting of different kinds of servers and clients that communicate events via a high-performance TCP network protocol.


## Event
---
- event is a record that “something happened” in the world or in your business.

## Topic
---

- 토픽이 partitioned 된다.=> 병렬 처리가 가능해진다.
- 토픽이 여러 브로커에 걸쳐 복제된다 => 내결함성

-

```
┌──────────────────────────┐
│        LinkedIn          │
│   → Kafka 최초 개발      │
└────────────┬─────────────┘
             │
┌────────────▼────────────┐
│  Apache Kafka (오픈소스)│
│  ASF 관리, 커뮤니티 유지 │
└────────────┬────────────┘
             │
┌────────────▼────────────┐
│   Confluent Inc.        │
│  Kafka 창시자들이 설립   │
│  상용 Kafka 플랫폼 제공  │
└──────────────────────────┘
```

## 참고 자료
---
- [https://kafka.apache.org/documentation/](https://kafka.apache.org/documentation/)
- [https://docs.confluent.io/kafka/introduction.html](https://docs.confluent.io/kafka/introduction.html)
