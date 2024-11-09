---
title: 카프카 전달보증 구현하기 - Exactly Once
date: 2021-07-29 14:00:00 +0900
---

# Exactly Once
---
- 메시지 유실없이 정확히 한 번 전달한다 ?? --> 전달보다는 '브로커에서' 정확히 한번만 '처리된다'라는게 맞는거같다
 -> 근데 컨슈머측에서 처리하다 에러나면, 재송신하는거 아닌가 ?
 -> 즉, at least once랑 같은데 메시지 중복처리만 안되게하는거 아닌가 ??v
 -> 아닌거 같다, 만약 브로커에서 프로듀서로부터 받은 메시지 저장했는데 ack를 다시 프로듀서로 못 보내서
  프로듀서에서 재송신오는 경우, transaction id 통해 메시지 중복처리 방지해줄거같다.
  -> 따라서, 컨슈머측에서는 중복된 메시지를 consume 하는 일은 없는것 ??

> 카프카는 초기에 `at-most-once`와 `at-least-once` 수준의 전달 보증만 지원했었다. <br>
> 하지만, 카프카의 유용성이 높아지면서 Exactly Once 수준의 전달을 보증하고자 하는 요구가 높아졌다. <br>
> 이를 위해 카프카에 ***트랜잭션*** 개념이 도입되었다.
> `exactly-once` 전달 보증은 0.11 버전부터(Released June 28, 2017, [참고](https://kafka.apache.org/downloads) ) `idempotent`와 `transactional producers` 두 가지 옵션을 통해 지원한다. 결과적으로 메시지는 한 번만 전달되며 유실되지 않는다.


- exactly-once delivery는 프로듀서부터 컨슈머까지 연결되는 파이프라인의 처리를 뜻합니다. 기존 프로듀서의 경우 트랜잭션처리를 하지 않으면 카프카 클러스터에 두번이상 데이터가 저장될 수 있습니다.
데이터가 클러스터에 저장되었으나 ack가 유실되어 프로듀서가 재처리하는 경우가 대표적입니다. 결과적으로 카프카 트랜잭션 처리를 하더라도 컨슈머가 중복해서 데이터 처리하는 것에 대해 보장하지 않으므로,
***컨슈머의 중복처리는 따로 로직을 작성해야합니다.***

- `enable.idempotence`를 true로 하게 되면 카프카는 중복 메시지 제거 알고리즘에서 `transactional.id`를 사용하여 프로듀서가 보내는 모든 메시지의 멱등성(idempotence)을 보장한다.
  - 간단히 말해, 프로듀서가 같은 메시지를 두 번 이상 송신하게 되면, Kafka는 이러한 설정을 통해 알아차릴 수 있다.
  - 프로듀서마다 트랜잭션 ID는 구별되어야 한다.
- `at-most-once`와 `at-least-once` 수준의 전달 보증에 비해 처리량이 낮고(lower throughput) 대기 시간이 더 길 수 있다(higher latency).

## 구현하기
- To work with the transaction API, we'll need Kafka's Java client

```xml
<dependency>
    <groupId>org.apache.kafka</groupId>
    <artifactId>kafka-clients</artifactId>
    <version>2.0.0</version>
</dependency>

```

### 1. 프로듀서
-
```
producerProps.put("enable.idempotence", "true");
producerProps.put("transactional.id", "prod-1");
producerProps.put("acks", "all");

 max.in.flight.requests.per.connection ???
```


enable.idempotence
When set to 'true', the producer will ensure that exactly one copy of each message is written in the stream. If 'false', producer retries due to broker failures, etc., may write duplicates of the retried message in the stream. Note that enabling idempotence requires max.in.flight.requests.per.connection to be less than or equal to 5, retries to be greater than 0 and acks must be 'all'.

If these values are not explicitly set by the user, suitable values will be chosen. If incompatible values are set, a ConfigException will be thrown.
-> https://docs.confluent.io/platform/current/installation/configuration/producer-configs.html


2. 프로듀서 준비
  - `producer.initTransactions();`
  - 트랜잭션을 사용하는 프로듀서로 브로커에 등록된다.
  - 프로듀서는 transactional.id와 시퀀스 번호 또는 에포크(epoch)로 식별된다.
  - 브로커는 이를 사용하여 트랜잭션 로그에 모든 작업을 미리 기록한다.
  - 결과적으로 브로커는 동일한 트랜잭션 ID와 이전 에포크를 가진 프로듀서에 속하는 모든 작업을 해당 로그에서 제거하고, 이러한 작업이 존재하지 않는 트랜잭션에서 발생한 것으로 가정한다. (??)

3. ???
  - `producer.beginTransaction();` ???
  - 메시지는 파티셔닝 될 수 있기 때문에, 트랜잭션 메시지가 여러 파티션에 걸쳐 있고 각 파티션마다 별도의 컨슈머가 메시지를 읽는다.
  - 따라서 Kafka는 트랜잭션에 대해 업데이트된 모든 파티션 목록을 저장한다.
  - 트랜잭션 내에서 프로듀서는 멀티 스레드를 사용하여 레코드를 병렬로 전송할 수 있다.

### 2. 브로커
- `min.insync.replicas`
 -> When a producer sets acks to "all" (or "-1"), min.insync.replicas specifies the minimum number of replicas that must acknowledge a write for the write to be considered successful. If this minimum cannot be met, then the producer will raise an exception (either NotEnoughReplicas or NotEnoughReplicasAfterAppend).
    When used together, min.insync.replicas and acks allow you to enforce greater durability guarantees. A typical scenario would be to create a topic with a replication factor of 3, set min.insync.replicas to 2, and produce with acks of "all". This will ensure that the producer raises an exception if a majority of replicas do not receive a write.

### 3. Consumer
- `isolation.level`을 사용하여 연관된 트랜잭션이 커밋될 때까지 트랜잭션 메시지를 기다릴 수 있다.
  - `read_committed` : 트랜잭션이 완료되기 전까지 트랜잭션 메시지를 읽지 않는다. (default 값)
  - `read_uncommitted` : 아직 커밋되지 않은 메시지뿐 아니라 트랜잭션이 abort된 메시지도 읽는다. (즉 모든 메시지를 읽는다)
  -  트랜잭션과 무관한 메시지는 isolation.level과 상관없이 모든 경우에 읽을 수 있다.
```
consumerProps.put("enable.auto.commit", "false");
consumerProps.put("isolation.level", "read_committed");
```

2. 마지막으로 방금 소비한 오프셋을 적용해야 합니다. 트랜잭션을 사용하면 오프셋을 정상적으로 읽은 입력 항목에 다시 적용합니다. 또한, 우리는 생산자의 거래에 그것들을 보냅니다.

## 테스트 시나리오

- `enable.idempotence`를 true로 하게 되면 카프카는 중복 메시지 제거 알고리즘에서 `transactional.id`를 사용하여 프로듀서가 보내는 모든 메시지의 멱등성(idempotence)을 보장한다.
  -> 어케 테스트하지 ???

1. producer.sendOffsetsToTransaction(offsetsToCommit, CONSUMER_GROUP_ID); 없으면 오프셋 변동 없을지
2.

## 테스트 결과
- 정확히 한번만 전달되어야됨
- 메시지 중복 없어야됨

## 전체 코드

#


트랜잭션 처리를 위한 STATE 같은게 있나 ??

# 실제 운영환경 ?
---
- acks=1이라고 해서 메시지 손실률이 전혀 없는 것은 아닙니다. 하지만 방금 설명드린 현상이 빈번하게 일어나는 일은 아니고, 메시지를 보내는 속도 역시 고려사항중 하나이기 때문에 실제 운영환경에서는 acks=1로 가장 많이 사용하고 있습니다. 제가 운영하는 카프카에서도 프로듀서 옵션은 acks=1을 가장 많이 사용하고 있습니다. 이어서 마지막 옵션에 대해 살펴보겠습니다.

- 실제 운영환경에서 브로커 노드 2개가 동시에 다운되는 일은 거의 발생하지 않습니다. 그래서 Replication Factor를 3으로 운영하시고, 안정적인 구현을 위해서는 min.insync.replicas는 2로 설정하는 것이 가장 바람직하다고 생각됩니다.

- 제가 설명드린 여러 예제중 가장 안정적인 예제로 acks=all, Replication Factor=3과  min.insync.replicas=2로 설명드렸지만, 실제 운영환경에서 가장 많이 쓰이는 옵션은 아닙니다. 운영환경에서 가장 많이 쓰이는 옵션은 프로듀서의 acks=all보다는 acks=1를 가장 많이 사용하고 있습니다. 그래서 저는 운영하면서 브로커의 min.insync.replicas옵션에 대해 크게 신경쓰지 않았습니다. 하지만 앞으로 추가되는 메시지의 중요도에 따라 해당 옵션들을 변경하여 사용할 수 있기 때문에 해당 옵션들에 대해 완벽하게 이해하시고 본인의 운영환경을 파악한 후 그에 알맞은 설정을 하는 것이 가장 중요하다고 생각합니다.

- 우리회사는 ??

# ???
---
Invalid transition attempted from state READY to state ABORTING_TRANSACTION
consumer.commitInSync랑 차이 ??
TransactionalId prod-0: Invalid transition attempted from state READY to state ABORTING_TRANSACTION

- 전달보증은 메시지를 보내는 횟수와 관련이 있는거고, 메시지 유실과 관련된건 acks와 replication ??
 - 상호 보완적인것 ??
 - at least once를 구현하려면 acks가 필요하다 ??

- ★ 프로듀서에서의 전달 보증은 acks를 통해 구현할 수 있다 !
  -> acks가 0이면 at most once
  -> acks가 1이면 at least once
  -> acks가 all이면 exactly once ?? (all이라는건 min.insync.replica에 정의된 최소 ISR 수, min.insync.replicas 옵션은 브로커의 옵션이다 - config/server.properties)
     -> all 이여도
  -> acks가 all이어도 at least once 될 수 있지 않나 ???

- 전달보증이라는건 브로커 -> 컨슈머로의 전달을 의미 ??
  ->



# 참고자료
---
- https://www.baeldung.com/kafka-exactly-once
- https://supergloo.com/kafka/kafka-architecture-delivery/
- https://blog.voidmainvoid.net/354
- https://dzone.com/articles/kafka-producer-delivery-semantics
- https://gunju-ko.github.io/kafka/2019/01/07/%EC%B9%B4%ED%94%84%EC%B9%B4%EC%BB%A8%EC%8A%88%EB%A8%B8.html
- https://www.popit.kr/kafka-%EC%9A%B4%EC%98%81%EC%9E%90%EA%B0%80-%EB%A7%90%ED%95%98%EB%8A%94-producer-acks/
