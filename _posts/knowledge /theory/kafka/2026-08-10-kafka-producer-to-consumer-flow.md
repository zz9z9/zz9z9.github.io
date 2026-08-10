---
title: 카프카 프로듀서에서 컨슈머까지의 처리 흐름
date: 2026-08-10 22:00:00 +0900
categories: [지식 더하기, 카프카]
tags: [Kafka]
---

이벤트 하나가 프로듀서에서 발행되어 컨슈머가 처리하고 오프셋을 커밋하기까지의 흐름을 훑는다. ISR·High Watermark·오프셋 관리 같은 개별 개념의 상세는 별도 글에서 다루고, 여기서는 각 단계에서 누가 무엇을 결정하는지에 초점을 맞춘다.

본문에 나오는 설정 기본값은 **Apache Kafka 4.2** 문서 기준이다. `acks`, `enable.idempotence`처럼 버전에 따라 기본값이 바뀐 항목이 있으므로 다른 버전을 쓴다면 해당 버전 문서를 확인해야 한다.

## 전체 흐름

---

> 이벤트는 프로듀서의 배치 버퍼 → 리더 파티션 → 팔로워 복제 → 컨슈머 fetch → 오프셋 커밋 순서로 움직인다. <br> 브로커는 어느 구간에서도 먼저 밀어 보내지 않고, 프로듀서와 컨슈머가 각각 요청을 보내면 응답하는 쪽이다.

```
① Producer  ──   send() → 파티셔너가 파티션 결정 → 배치 버퍼(record accumulator)에 적재
② Producer  ──▶  Broker     배치 단위로 전송
③ Broker    ──   리더 파티션에 append → 다른 브로커의 팔로워 레플리카가 복제
④ Broker    ──▶  Producer   ack 응답 (시점은 프로듀서의 acks 설정이 결정)

⑤ Consumer  ──▶  Broker     fetch 요청 ("이 오프셋부터 주세요")
⑥ Broker    ──▶  Consumer   레코드 배치 응답 (High Watermark까지만)
⑦ Consumer  ──   poll()이 리턴한 배치 처리
⑧ Consumer  ──▶  Broker     오프셋 커밋 → __consumer_offsets 토픽에 저장
```

각 단계를 나눠서 보면 다음과 같다.

## 1. 프로듀서 → 브로커

---

> `send()`는 즉시 전송이 아니라 버퍼 적재이고, 응답을 언제 받을지는 프로듀서의 `acks`가 결정한다.

`send()`를 호출하면 파티셔너가 대상 파티션을 정하고, 레코드는 곧바로 나가지 않고 **record accumulator**라는 버퍼에 쌓인다. <br>
배치가 `batch.size`만큼 차거나 `linger.ms`가 지나면 그때 브로커로 전송된다.
즉 프로듀서 단계에서 이미 "레코드 단위"가 아니라 "배치 단위"로 동작한다.

브로커에 도착한 레코드는 **리더 파티션**에 쓰이고, 다른 브로커에 있는 **팔로워 레플리카**가 이를 복제해 간다.

ack를 언제 돌려줄지는 프로듀서의 `acks` 설정이 정한다.

| `acks` | ack 시점 |
| --- | --- |
| `0` | 기다리지 않음. 전송한 것으로 간주 |
| `1` | 리더 파티션에 쓰이면 응답 |
| `all` | ISR 전체에 복제되면 응답 |

여기서 `min.insync.replicas`를 "이만큼 복제되면 ack"로 읽기 쉬운데, 그런 설정이 아니다. `acks=all`일 때 **요구되는 ISR 개수의 하한**이고, ISR이 이 값에 미달하면 브로커가 ack를 늦추는 게 아니라 **쓰기 자체를 거부**한다. ISR과 `min.insync.replicas`의 동작은 별도 글에서 정리한다.

주요 기본값은 다음과 같다.

| 설정 | 기본값 | 비고 |
| --- | --- | --- |
| `acks` | `all` | Kafka 3.0부터. 이전 기본값은 `1` |
| `enable.idempotence` | `true` | Kafka 3.0부터 기본 활성화 |
| `retries` | `2147483647` | 횟수로는 사실상 무제한. 실제로는 `delivery.timeout.ms`가 먼저 끊음 |
| `delivery.timeout.ms` | `120000` | `send()` 이후 성공/실패가 확정되기까지 허용되는 전체 시간 |
| `linger.ms` | `5` | |
| `batch.size` | `16384` | |

재시도를 제어하는 값은 `retries`가 아니라 `delivery.timeout.ms`로 보는 편이 맞다. `retries` 기본값이 `Integer.MAX_VALUE`라 횟수로는 사실상 무제한이고, 실제로는 배치 대기 시간 + 브로커 응답 대기 + 재시도를 모두 합쳐 `delivery.timeout.ms`(기본 2분)를 넘기는 순간 실패로 확정되기 때문이다.

기본값이 `acks=all` + 재시도이므로, **별도 설정 없이도 프로듀서는 at-least-once**로 동작한다. at-least-once가 따로 켜야 하는 옵션이 아니다.

## 2. 브로커 → 컨슈머

---

> 컨슈머는 주기적으로 밀어 받는 게 아니라, 애플리케이션 루프가 `poll()`을 호출할 때마다 "이 오프셋부터 달라"고 직접 요청한다.

컨슈머에 "폴링 주기" 설정은 없다. 실제 구조는 애플리케이션이 도는 루프다.

```java
while (true) {
    ConsumerRecords<String, String> records = consumer.poll(Duration.ofMillis(100));
    // 레코드 처리
    // (필요하면 커밋)
}
```

직전 `poll()`이 리턴한 레코드의 처리가 끝나면 곧바로 다음 `poll()`이 호출된다. 즉 **poll 간격 = 배치 처리 시간**이고, 처리가 빠를수록 poll도 잦아진다. <br>
Spring Kafka 같은 프레임워크도 내부적으로 이 루프를 대신 돌려준다.

`max.poll.interval.ms`(기본 300000)는 폴링 주기가 아니라 **poll 호출 간격의 상한**이다. <br>
한 배치 처리가 이 시간을 넘기면 컨슈머가 죽은 것으로 간주되어 그룹에서 퇴출되고 리밸런싱이 일어난다.

받아올 레코드가 없을 때 `poll()`이 곧바로 빈손으로 리턴하면 busy-loop가 되므로, 브로커는 `fetch.min.bytes`만큼 데이터가 모이거나 `fetch.max.wait.ms`(기본 500)가 지날 때까지 응답을 붙들고 있는다. long polling 방식이다.

읽을 위치를 정하는 주체도 브로커가 아니다. 컨슈머가 파티션별 **position**(다음에 읽을 오프셋)을 메모리에 들고 있고, fetch 요청에 그 오프셋을 명시해서 보낸다. <br>
커밋된 오프셋은 매 요청마다 참조되는 게 아니라, **컨슈머가 재시작하거나 리밸런싱으로 파티션을 새로 할당받을 때 시작 위치를 복원하는 용도**로 쓰인다. <br>
복원할 기록이 없으면 `auto.offset.reset`(기본 `latest`)을 따른다.

그 외 이 구간에서 알아둘 것:

- 한 컨슈머 그룹 안에서 **하나의 파티션은 하나의 컨슈머만** 소비한다. 파티션 할당은 브로커 중 하나인 **그룹 코디네이터**가 주관한다.
- 컨슈머는 **High Watermark까지만** 읽을 수 있다. 리더에만 쓰이고 아직 복제 중인 레코드는 fetch 요청이 와도 내려주지 않는다. 복제 전 레코드를 읽었는데 리더가 죽으면 존재한 적 없는 데이터를 읽은 셈이 되기 때문이다.
- 이 제약은 프로듀서의 `acks`와 무관하다. `acks=1`로 ack를 받았더라도 컨슈머에게는 복제가 끝난 뒤에야 보인다.

## 3. 처리와 오프셋 커밋

---

> 기본값은 auto commit이고, 커밋되는 값은 "처리한 마지막 오프셋"이 아니라 "다음에 읽을 오프셋"이다.

"처리를 마치면 커밋한다"는 건 auto commit을 끄고 `commitSync()`/`commitAsync()`를 직접 호출했을 때의 이야기다. 기본값은 `enable.auto.commit=true`다.

기본 프로토콜(`group.protocol=classic`)에서 auto commit은 별도 백그라운드 타이머가 아니라 **`poll()` 호출 안에서** 처리된다. <br>
`poll()`이 불릴 때마다 마지막 커밋 이후 `auto.commit.interval.ms`(기본 5000)가 지났는지 확인하고, 지났으면 현재 position을 커밋한다. <br>
따라서 실제 커밋 간격은 정확히 5초가 아니라 **"5초 이상, poll 주기에 따라"** 이고, `poll()`을 호출하지 않으면 커밋도 일어나지 않는다. `close()`나 리밸런싱 시점에도 커밋한다.

> Kafka 4.x에는 `group.protocol=consumer`(KIP-848)로 켜는 새 컨슈머 그룹 프로토콜이 있고, 여기서는 그룹 관리와 커밋 처리를 백그라운드 스레드가 맡는다. <br>
> 4.2 기준 기본값은 여전히 `classic`이다.

커밋되는 값은 **마지막으로 처리한 오프셋 + 1**, 즉 다음에 읽을 오프셋이다. 오프셋 100까지 처리했다면 101이 커밋된다.

auto commit에서 유실이 생길 수 있는 이유는 커밋 대상이 "처리를 완료한 오프셋"이 아니라 **"poll로 받아간 오프셋"** 이기 때문이다. 상황에 따라 갈린다.

| 처리 방식 | 결과 |
| --- | --- |
| 동기 루프 (poll → 배치 전부 처리 → 다음 poll) | 커밋 시점엔 처리가 끝나 있으므로 유실 없음. 중복만 가능 |
| 받은 배치를 다른 스레드에 넘기고 바로 다음 poll | 아직 처리 중인 레코드의 오프셋이 커밋됨 → 크래시 후 재시작하면 그 지점부터 읽어 미처리 레코드를 건너뜀 (유실) |
| 처리 중 예외를 삼키고 루프 계속 진행 | 실패한 레코드까지 커밋됨 (유실) |

## 4. 커밋된 오프셋은 어디에 남는가

---

> `__consumer_offsets` 내부 토픽에 저장되며, 프로듀서에게 알려지는 것은 없다.

커밋된 오프셋은 `__consumer_offsets`라는 내부 토픽에 **(그룹, 토픽, 파티션)** 을 키로 저장된다. 커밋 요청은 그룹 코디네이터 브로커가 처리한다. <br>
브로커가 오프셋을 다른 파티션들에 "전파"하는 동작 같은 건 없고, `__consumer_offsets` 토픽 자체가 복제될 뿐이다.

프로듀서 쪽으로 전달되는 것도 없다. 프로듀서와 컨슈머는 완전히 분리되어 있고, 프로듀서는 컨슈머 오프셋의 존재 자체를 모른다.

커밋 기록은 영구 보관되지 않는다. `offsets.retention.minutes`(기본 10080, 7일)가 지나면 만료된다.

## 흔히 오해하는 지점 정리

---

> 위 내용 중 직관과 어긋나기 쉬운 것들을 모았다.

| 오해 | 실제 |
| --- | --- |
| `min.insync.replicas`만큼 복제되면 ack | ack 시점은 `acks`가 결정. `min.insync.replicas`는 `acks=all`일 때 요구되는 ISR 하한이고, 미달이면 쓰기 자체가 거부됨 |
| 컨슈머에 폴링 주기 설정이 있다 | 없음. 애플리케이션 루프가 `poll()`을 직접 호출. `max.poll.interval.ms`는 주기가 아니라 간격의 상한 |
| 브로커가 컨슈머 그룹별로 어디부터 보낼지 판단해서 전송 | 컨슈머가 자기 position을 들고 있다가 fetch 요청에 명시. 커밋된 오프셋은 재시작·리밸런싱 시 복원용 |
| 처리를 완료하면 커밋된다 | 기본값은 auto commit. 처리 완료 기준 커밋은 auto commit을 끄고 직접 호출해야 함 |
| auto commit은 5초마다 백그라운드에서 동작 | `classic` 프로토콜에서는 `poll()` 안에서 검사. poll을 안 부르면 커밋도 없음 |
| 커밋 값은 마지막으로 처리한 오프셋 | 마지막 처리 오프셋 + 1 (다음에 읽을 오프셋) |
| `acks`를 낮추면 컨슈머가 더 빨리 볼 수 있다 | 무관. 컨슈머는 High Watermark까지만 읽으므로 복제 완료 후에야 보임 |
| 브로커가 오프셋을 전파하고 프로듀서에도 알린다 | `__consumer_offsets` 토픽에 저장될 뿐. 프로듀서와는 무관 |

## 참고 자료

---

- [Apache Kafka Design (kafka.apache.org/42/design/design)](https://kafka.apache.org/42/design/design/) — Persistence, The Consumer, Replication
- [Apache Kafka Producer Configs (kafka.apache.org/42/configuration/producer-configs)](https://kafka.apache.org/42/configuration/producer-configs/)
- [Apache Kafka Consumer Configs (kafka.apache.org/42/configuration/consumer-configs)](https://kafka.apache.org/42/configuration/consumer-configs/)
- [Apache Kafka Broker Configs (kafka.apache.org/42/configuration/broker-configs)](https://kafka.apache.org/42/configuration/broker-configs/)
- [KafkaConsumer javadoc (kafka.apache.org/42/javadoc)](https://kafka.apache.org/42/javadoc/org/apache/kafka/clients/consumer/KafkaConsumer.html) — position과 committed offset의 구분
