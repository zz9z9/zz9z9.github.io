---
title: 카프카 브로커 장애와 리더 선출
date: 2026-10-22 22:00:00 +0900
categories: [지식 더하기, 카프카]
tags: [Kafka]
published: false
---

[ISR 글](/posts/kafka-isr-1/)에서 "리더가 죽으면 ISR 안에서 새 리더를 뽑는다"고만 적었다. <br>
이 글은 그 한 줄을 풀어서, **브로커가 죽었다는 걸 누가 언제 알아채고, 새 리더를 어떤 순서로 고르며, 브로커가 돌아온 뒤 리더는 어디로 가는지**를 다룬다.

> **선행 개념**: 클러스터·컨트롤러·쿼럼은 [카프카 클러스터와 컨트롤러 — KRaft](/posts/kafka-cluster-controller-kraft/), ISR·`min.insync.replicas`·`acks=all`은 [ISR 글](/posts/kafka-isr-1/), HW·Leader Epoch은 [카프카 파티션 로그의 오프셋들](/posts/kafka-partition-offsets/).

본문의 동작과 수치는 전부 **Apache Kafka 4.2.0 KRaft 모드**에서 직접 돌려 얻은 값이다. ZooKeeper 모드는 4.0에서 제거됐으므로 다루지 않는다.

## 실습 환경

---

> 컨트롤러 1대와 브로커 3대를 Docker로 띄우고, 브로커를 죽이거나 내리면서 컨트롤러가 남기는 메타데이터 레코드를 본다.

컨트롤러와 브로커를 한 프로세스에 묶는 combined 모드로 띄우면 브로커를 죽일 때 컨트롤러 투표자도 같이 죽는다. 브로커 장애만 관찰하려고 컨트롤러를 따로 뒀다.

```yaml
# docker-compose.yml (요지)
x-common: &common
  image: apache/kafka:4.2.0
  environment: &env
    CLUSTER_ID: "MkU3OEVBNTcwNTJENDM2Qk"
    KAFKA_CONTROLLER_QUORUM_VOTERS: "1@controller:9093"
    KAFKA_CONTROLLER_LISTENER_NAMES: CONTROLLER
    KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: "CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT"
    KAFKA_INTER_BROKER_LISTENER_NAME: PLAINTEXT
services:
  controller:            # node 1, process.roles=controller
    <<: *common
    environment: { <<: *env, KAFKA_NODE_ID: 1, KAFKA_PROCESS_ROLES: controller, KAFKA_LISTENERS: "CONTROLLER://:9093" }
  b2:                    # node 2, process.roles=broker  (b3, b4 도 같은 모양)
    <<: *common
    environment: { <<: *env, KAFKA_NODE_ID: 2, KAFKA_PROCESS_ROLES: broker,
                   KAFKA_LISTENERS: "PLAINTEXT://:9092", KAFKA_ADVERTISED_LISTENERS: "PLAINTEXT://b2:9092" }
```

토픽은 파티션 3개, RF 3, `min.insync.replicas=2`로 만들었다.

```
Topic: t  Partition: 0  Leader: 2  Replicas: 2,3,4  Isr: 2,3,4  Elr:   LastKnownElr:
Topic: t  Partition: 1  Leader: 3  Replicas: 3,4,2  Isr: 3,4,2  Elr:   LastKnownElr:
Topic: t  Partition: 2  Leader: 4  Replicas: 4,2,3  Isr: 4,2,3  Elr:   LastKnownElr:
```

리더가 바뀐 시점은 `kafka-topics.sh --describe`를 반복 호출해서는 정확히 잡히지 않는다(호출 한 번에 1초 넘게 걸린다). 그래서 컨트롤러의 메타데이터 로그를 덤프해 각 레코드의 `CreateTime`을 시각으로 썼다.

```bash
kafka-dump-log.sh --cluster-metadata-decoder \
  --files /tmp/kafka-logs/__cluster_metadata-0/00000000000000000000.log
```

## 브로커와 컨트롤러의 관계

---

> 브로커는 컨트롤러에 등록하고 하트비트를 보낸다. 리더·ISR 변경은 컨트롤러가 `__cluster_metadata` 로그에 `PARTITION_CHANGE_RECORD`로 쓰고, 브로커가 그 레코드를 읽어 반영한다.

클러스터·컨트롤러·쿼럼 개념은 [카프카 클러스터와 컨트롤러 — KRaft](/posts/kafka-cluster-controller-kraft/)에서 다뤘다. 이 글에서 쓰는 것은 세 가지다.

- **등록과 broker epoch**: 브로커는 기동할 때마다 컨트롤러에 등록하고(`REGISTER_BROKER_RECORD`), 그때 새 **broker epoch**을 받는다.
- **하트비트**: `broker.heartbeat.interval.ms`(기본 2000ms)마다 보낸다. 컨트롤러는 그 응답으로 브로커 상태(fenced 여부, 종료 허가 여부)를 정해 준다.
- **fenced 플래그**: 아래 절

이 글의 실습은 쿼럼을 단순하게 하려고 컨트롤러를 1대만 뒀다. 컨트롤러 장애는 다루지 않는다.

### fenced 상태

브로커 등록 정보에는 `fenced` 플래그가 있다. **fenced 브로커는 리더가 될 수 없고 ISR에도 들 수 없다.** 리더 후보를 거르는 조건은 `org.apache.kafka.controller.ClusterControlManager#isActive`에 있다.

```java
// org.apache.kafka.controller.ClusterControlManager (Kafka 4.2.0)
public boolean isActive(int brokerId) {
    BrokerRegistration registration = brokerRegistrations.get(brokerId);
    if (registration == null) return false;
    return !registration.inControlledShutdown() && !registration.fenced();
}
```

fenced가 아니어도 정상 종료 중(`inControlledShutdown`)이면 리더 후보에서 빠진다.

## 브로커 장애는 어떻게 감지하나

---

> 컨트롤러는 하트비트가 `broker.session.timeout.ms`(기본 9000ms) 동안 끊긴 브로커를 fenced로 바꾼다. 브로커가 죽었다는 판정은 이 시점에 처음 나온다.

`docker kill`(SIGKILL)로 파티션 0의 리더인 b2를 죽였다. 컨테이너 종료 시각을 0으로 두고 메타데이터 레코드를 시간 순으로 놓으면 다음과 같다.

```
+0.000s  b2 프로세스 종료 (SIGKILL)
         ... 9초 동안 컨트롤러는 b2를 살아 있는 것으로 본다 ...
+9.092s  [controller.log] Fencing broker 2 at epoch 14 because its session has timed out.
+9.097s  PARTITION_CHANGE_RECORD  p0: isr=[3,4], leader=3
         PARTITION_CHANGE_RECORD  p1: isr=[3,4]
         PARTITION_CHANGE_RECORD  p2: isr=[4,3]
         BROKER_REGISTRATION_CHANGE_RECORD  broker 2: fenced=1
```

kill 후 9.09초 만에 fencing됐다. `broker.session.timeout.ms=9000`과 맞는다. 그 9초 동안 파티션 0에는 응답하지 않는 리더가 그대로 등록돼 있다.

fencing 한 번으로 b2가 들어 있던 파티션 3개가 모두 바뀐다. 리더였던 p0은 리더가 3으로 바뀌고, 팔로워였던 p1·p2는 ISR에서 b2가 빠진다.

### 리더가 아닌 파티션도 멈춘다

b2를 죽이는 동안 `acks=all` 프로듀서(초당 100건, 키 없음)를 돌렸다. 브로커 b3·b4에만 연결하고, b2를 죽이기 6초 전에 시작했다.

```
417 records sent,  33.2 records/sec, 61.5 ms avg latency,   1025.0 ms max latency.
1342 records sent, 268.2 records/sec, 4564.9 ms avg latency, 11861.0 ms max latency.   ← b2 kill 구간
501 records sent, 100.1 records/sec,  9.6 ms avg latency,    21.0 ms max latency.
2500 records sent, ... 11861.00 ms max latency, 11 ms 50th, 10641 ms 95th, 11641 ms 99th
```

b2가 리더인 파티션은 3개 중 1개인데, b2를 죽인 구간에 보낸 레코드 1342건의 평균 지연이 4.5초다. 리더가 멀쩡한 p1·p2로 간 레코드도 같이 멈췄다는 뜻이다.

원인은 ISR이다. fencing 전까지 p1·p2의 ISR에는 죽은 b2가 그대로 남아 있다. `acks=all` 쓰기는 HW가 해당 오프셋을 넘어야 ack되는데, HW는 ISR 전원의 LEO 중 최솟값이라 b2의 LEO에 묶여 전진하지 못한다. fencing으로 ISR이 `[3,4]`로 줄어든 뒤에야 HW가 전진한다.

> 하트비트 기반 감지는 `replica.lag.time.max.ms`(기본 30초)보다 빨리 죽은 브로커를 ISR에서 빼 준다. 그래도 그 9초 동안은 그 브로커를 팔로워로 둔 모든 파티션의 `acks=all` 쓰기가 멈춘다.

최대 지연(11.9초)이 fencing까지 걸린 시간(9.1초)보다 2.8초 긴 이유는 따로 확인하지 않았다. 프로듀서의 메타데이터 갱신과 재전송 대기 시간으로 추정한다. 프로듀서가 보낸 2500건은 모두 에러 없이 전송됐다.

### 세션 타임아웃을 줄이면

`broker.session.timeout.ms`를 줄이면 감지는 빨라진다. 대신 GC 정지나 네트워크 지연이 그 값을 넘을 때마다 멀쩡한 브로커가 fencing되고, 리더 이동과 ISR 축소·확장이 반복된다. 이 값은 컨트롤러 설정이다.

## 장애가 나면 리더는 이렇게 바뀐다

---

> 컨트롤러는 fencing된 브로커를 ISR에서 빼고, 남은 ISR 중 replica 목록 순서상 앞선 브로커를 리더로 고른다.

위 실험에서 p0의 replica 목록은 `[2,3,4]`, ISR은 `[2,3,4]`였다. b2가 빠지자 ISR `[3,4]` 중 목록상 첫 번째인 3이 리더가 됐다.

선출 순서는 `org.apache.kafka.controller.PartitionChangeBuilder#electAnyLeader`에 있다.

```java
// org.apache.kafka.controller.PartitionChangeBuilder (Kafka 4.2.0, 요약)
private ElectionResult electAnyLeader() {
    if (isValidNewLeader(partition.leader))            // ① 현재 리더가 여전히 유효하면 유지
        return new ElectionResult(partition.leader, false);

    Optional<Integer> onlineLeader = targetReplicas.stream()
        .filter(this::isValidNewLeader)                // ② replica 순서대로, 유효한 첫 후보
        .findFirst();
    if (onlineLeader.isPresent())
        return new ElectionResult(onlineLeader.get(), false);

    if (canElectLastKnownLeader())                     // ③ 마지막 리더 (ELR 절에서 다룸)
        return new ElectionResult(partition.lastKnownElr[0], true);

    if (election == Election.UNCLEAN) { ... }          // ④ unclean 선출 허용 시 아무 replica
    return new ElectionResult(NO_LEADER, false);       // ⑤ 리더 없음
}

private boolean isValidNewLeader(int replica) {
    // ISR 멤버이거나, ISR이 비었을 때 ELR 멤버여야 하고, 활성 브로커여야 한다.
    return (targetIsr.contains(replica) || (targetIsr.isEmpty() && targetElr.contains(replica))) &&
        isAcceptableLeader.test(replica);
}
```

두 번째 인자(`true`/`false`)는 이 선출이 unclean인지를 나타낸다. ②까지는 깨끗한(clean) 선출이다.

리더가 바뀌면 그 파티션의 **leader epoch**이 1 오른다. `PARTITION_CHANGE_RECORD`에는 epoch 필드가 따로 없고, 레코드를 반영하는 쪽에서 리더가 바뀌었으면 epoch을 올린다. 새 리더 기준으로 팔로워 로그를 맞추는 과정(truncation)은 [카프카 파티션 로그의 오프셋들 §Leader Epoch으로 분기점을 리더에게 묻는다](/posts/kafka-partition-offsets/#leader-epoch으로-분기점을-리더에게-묻는다)에서 다뤘다.

### 돌아온 브로커는 팔로워로 들어온다

b2를 다시 띄웠다. b2의 `REGISTER_BROKER_RECORD`(컨트롤러 로그 기준 13:52:20.851)를 0으로 둔다.

```
+0.000s  REGISTER_BROKER_RECORD  broker 2, brokerEpoch=292 (이전 14), 새 incarnationId
+0.514s  [controller.log] The request from broker 2 to unfence has been granted
         because it has caught up with the offset of its register broker record 292.
         BROKER_REGISTRATION_CHANGE_RECORD  broker 2: fenced=-1 (unfenced)
+0.975s  PARTITION_CHANGE_RECORD  p1: isr=[2,3,4]
+1.031s  PARTITION_CHANGE_RECORD  p0: isr=[2,3,4]
         PARTITION_CHANGE_RECORD  p2: isr=[2,3,4]
```

- 재등록하면 broker epoch이 새로 발급된다(14 → 292). 컨트롤러는 epoch으로 이전 프로세스가 보낸 늦은 요청과 새 프로세스의 요청을 구분한다.
- 등록 직후에는 fenced 상태다. 브로커가 메타데이터 로그를 자기 등록 레코드 오프셋까지 따라 읽어야 unfence된다. 메타데이터를 다 읽지 않은 브로커가 리더를 맡는 일을 막는 조건이다.
- unfence된 뒤 리더를 따라잡으면 ISR에 다시 들어간다.

b2가 ISR에 돌아왔지만 **p0의 리더는 여전히 3이다.**

## 정상 종료는 다르게 흘러간다

---

> 정상 종료(SIGTERM)하는 브로커는 내려가기 전에 컨트롤러에 종료를 알린다. 컨트롤러가 그 브로커가 맡은 리더를 먼저 다른 브로커로 넘기므로 리더 공백이 생기지 않는다.

이 동작을 controlled shutdown이라 하고, `controlled.shutdown.enable`(기본 `true`)로 켜고 끈다. 같은 b2를 이번엔 `docker stop`(SIGTERM)으로 내렸다. 컨트롤러가 종료 요청을 받은 시각을 0으로 둔다.

```
+0.000s  [controller.log] Unfenced broker 2 has requested and been granted a controlled shutdown.
+0.002s  BROKER_REGISTRATION_CHANGE_RECORD  broker 2: inControlledShutdown=1
         PARTITION_CHANGE_RECORD  p0: isr=[3,4], leader=3
         PARTITION_CHANGE_RECORD  p1: isr=[3,4]
         PARTITION_CHANGE_RECORD  p2: isr=[3,4]
+2.091s  [controller.log] The request from broker 2 to shut down has been granted since
         the lowest active offset 701 is now greater than the broker's controlled shutdown offset 700.
         BROKER_REGISTRATION_CHANGE_RECORD  broker 2: fenced=1
+2.780s  b2 프로세스 종료 (exit 143 = SIGTERM)
```

1. 브로커가 하트비트에 "종료하고 싶다"를 실어 보낸다. 컨트롤러는 `inControlledShutdown=1`로 표시한다. `isActive` 조건대로 이 시점부터 b2는 리더 후보가 아니다. 그래서 같은 순간 p0의 리더가 3으로 옮겨지고, 세 파티션의 ISR에서 b2가 빠진다.
2. 컨트롤러는 다른 브로커들이 이 변경 레코드(오프셋 700)까지 메타데이터를 반영한 걸 확인한 뒤 종료를 허가하고 b2를 fenced로 바꾼다. 로그의 "lowest active offset 701 > controlled shutdown offset 700"이 그 확인이다.
3. b2는 그 다음에 프로세스를 끝낸다.

SIGKILL에서는 리더가 9초 동안 비어 있었지만, 여기서는 종료 요청과 같은 순간에 리더가 넘어갔다.

프로듀서 측정도 같은 조건으로 했다.

```
501 records sent, 100.1 records/sec, 15.8 ms avg latency, 588.0 ms max latency.   ← 기동 직후 구간
500 records sent, 100.0 records/sec,  9.3 ms avg latency,  17.0 ms max latency.   ← b2 stop 구간
501 records sent, 100.2 records/sec,  8.9 ms avg latency,  19.0 ms max latency.
500 records sent,  99.9 records/sec,  8.8 ms avg latency,  20.0 ms max latency.
```

첫 구간의 588ms는 b2를 내리기 전, 프로듀서가 연결·메타데이터를 처음 잡는 구간이다. b2를 내린 구간의 최대 지연은 17ms다.

| | SIGKILL (`docker kill`) | SIGTERM (`docker stop`) |
|---|---|---|
| 컨트롤러가 아는 시점 | 하트비트 끊기고 9.09초 뒤 | 종료 요청 즉시 |
| 리더 공백 | 약 9초 | 없음 |
| `acks=all` 최대 지연 (실측) | 11,861ms | 17ms |
| 다음 기동이 clean인가 | 아니다 (ELR 판정에 영향) | 그렇다 |

> 롤링 재시작에서 브로커를 SIGKILL로 내리면 브로커마다 이 9초가 한 번씩 생긴다. 컨테이너 오케스트레이터의 종료 유예 시간(Kubernetes `terminationGracePeriodSeconds` 등)이 controlled shutdown을 끝내기에 충분한지 확인해야 하는 이유다.

## ISR이 전멸하면: Unclean Leader Election

---

> ISR에 살아 있는 브로커가 하나도 없으면, ISR 밖의(out-of-sync) replica를 리더로 쓸지 정해야 한다. 가용성과 무손실 중 하나를 고르는 설정이다.

| 설정 | 동작 | 대가 |
|------|------|------|
| `unclean.leader.election.enable=false` (기본) | ISR 멤버가 돌아올 때까지 리더 없음(`leader=-1`) | 그동안 파티션 읽기·쓰기 불가 |
| `unclean.leader.election.enable=true` | 살아 있는 아무 replica나 리더로 선출 | 새 리더가 갖지 못한 커밋된 레코드 유실 |

`true`면 out-of-sync replica가 리더가 된다. 그 replica의 로그가 이전 HW보다 짧으면 그 사이의 커밋된 레코드는 새 리더에 없고, 다른 replica들도 새 리더를 따라 그 구간을 잘라 낸다. 앞의 `electAnyLeader` ④가 이 경로다.

Kafka 4.x에서는 이 양자택일 앞에 ELR이 한 단계 끼어든다.

## ELR (Eligible Leader Replicas)

---

> ELR은 ISR에서 빠졌지만 HW까지의 데이터는 확실히 가진 replica 목록이다. ISR이 비었을 때 unclean 선출 없이 리더를 뽑을 수 있는 후보가 된다. KRaft 전용 기능이다(KIP-966).

### 풀려는 문제

RF=3, `min.insync.replicas=2`인데 장애가 이어져 ISR이 리더 한 대만 남은 상황이다. KIP-966은 이 상황의 위험을 이렇게 설명한다.

> ISR의 마지막 replica가 unclean shutdown으로 커밋된 데이터를 잃으면, 재기동 후 다시 리더로 선출된다. 그러면 다시 합류하는 팔로워들이 로그를 잘라 내면서 커밋된 레코드의 마지막 복사본까지 지워진다. (KIP-966)

L(리더)·F1·F2로 풀면 다음과 같다.

```
① m 을 acks=all 로 발행 → L·F1·F2 모두 복제 → HW 전진 → m 커밋. 복사본 3곳.
② F1·F2 가 지연/재시작으로 ISR 에서 빠짐 → ISR={L}
   (F1·F2 디스크엔 m 이 그대로 있다. ISR 에서 빠졌을 뿐이다.)
③ L 이 unclean shutdown → L 디스크에서 m 소실          ← 데이터를 잃은 쪽: L
④ L 재기동 → 마지막 ISR 멤버라 다시 리더. L 로그엔 m 이 없다.
⑤ F1·F2 가 팔로워로 복귀 → 리더 기준으로 truncate → m 삭제  ← 마지막 복사본: F1·F2
⑥ m 이 세 replica 모두에서 사라짐
```

③에서 커밋된 데이터가 디스크에서 사라질 수 있는 이유는, 카프카가 레코드를 OS 페이지 캐시에 쓰고 fsync는 OS에 맡기기 때문이다(`log.flush.*` 기본값). 커밋(HW 전진)은 여러 replica의 페이지 캐시에 들어갔다는 보장이지 디스크에 기록됐다는 보장이 아니다. 정전이나 커널 패닉 같은 unclean shutdown은 아직 디스크에 쓰지 않은 페이지 캐시를 잃는다.

ELR이 있으면 ②에서 빠진 F1·F2를 컨트롤러가 기억해 두고, ④에서 데이터를 잃었을 수 있는 L 대신 F1·F2를 리더로 고른다.

### ELR에 들어가는 조건

ISR이 `min.insync.replicas`보다 작아질 때 빠지는 멤버만 ELR에 들어간다. 이 조건은 `org.apache.kafka.controller.PartitionChangeBuilder#maybePopulateTargetElr`에 있다.

```java
// org.apache.kafka.controller.PartitionChangeBuilder (Kafka 4.2.0, 요약)
// ISR 이 min ISR 이상이면 ELR 과 LastKnownElr 을 비운다.
if (targetIsr.size() >= minISR) {
    targetElr = List.of();
    targetLastKnownElr = List.of();
    return;
}
// 새 ELR = (현재 ISR ∪ 현재 ELR) − 새 ISR − unclean shutdown 한 replica
```

ISR 전원(2·3·4)을 SIGKILL로 하나씩 죽이며 p0을 관찰했다.

| 단계 | ISR | Leader | ELR | LastKnownElr |
|---|---|---|---|---|
| 시작 | `[2,3,4]` | 2 | | |
| b4 kill | `[2,3]` | 2 | | |
| b3 kill | `[2]` | 2 | `[3]` | |
| b2 kill | `[]` | -1 | `[2,3]` | `[2]` |

- b4가 빠질 때는 ISR이 2로, `min.insync.replicas` 이상이라 ELR에 기록되지 않았다.
- b3가 빠지면서 ISR이 1이 되자 b3는 ELR에 들어갔다.
- 마지막 리더 b2까지 죽자 ISR이 비고 리더가 없어졌다(`leader=-1`). b2도 ELR로 옮겨졌고, `LastKnownElr`에는 마지막 리더 2가 기록됐다.

ELR 멤버는 HW까지의 데이터를 가졌다는 보장이 있어야 한다. 그 보장의 토대가 **ISR이 `min.insync.replicas` 이상일 때만 HW가 전진한다**는 규칙이다. 이 규칙은 `kafka.cluster.Partition#maybeIncrementLeaderHW` 첫머리에 있다.

```scala
// kafka.cluster.Partition (Kafka 4.2.0)
private def maybeIncrementLeaderHW(leaderLog: UnifiedLog, currentTimeMs: Long = time.milliseconds): Boolean = {
  if (isUnderMinIsr) {
    trace(s"Not increasing HWM because partition is under min ISR(ISR=${partitionState.isr}")
    return false
  }
  ...
```

ISR이 `min.insync.replicas` 아래로 내려간 뒤에는 HW가 멈춘다. 그래서 그 시점에 ISR에서 빠진 멤버는 HW까지의 데이터를 반드시 갖고 있다.

### 돌아오는 브로커가 clean인지가 갈림길이다

ELR 멤버라도 **unclean shutdown 후 재기동하면 ELR에서 빠진다.** 브로커는 정상 종료할 때 로그 디렉터리에 clean shutdown 표시를 남긴다. 다음 기동 때 그 표시가 없으면 컨트롤러는 `handleBrokerUncleanShutdown`으로 그 브로커를 ISR·ELR에서 지운다. 페이지 캐시를 잃었을 수 있는 replica를 무손실 후보로 볼 수 없기 때문이다.

**경우 1: ELR 멤버가 clean하게 돌아온다.** 이번엔 b4·b3는 `docker stop`으로, 마지막 리더 b2는 `docker kill`로 내렸다. 표의 마지막 상태(ISR `[]`, ELR `[2,3]`)까지 같다. 그 다음 b3를 다시 띄웠다.

```
PARTITION_CHANGE_RECORD p0: isr=[3], leader=3, eligibleLeaderReplicas=[2], lastKnownElr=[]
```

b3가 ELR에서 바로 리더가 됐다. `electAnyLeader` ②의 `isValidNewLeader`가 "ISR이 비었으면 ELR 멤버도 유효"로 판정한 경로이고, unclean 선출이 아니다.

**경우 2: 전원 SIGKILL 후 하나씩 돌아온다.** 위 표의 상태에서 이어 갔다.

```
b4 start (ELR 밖)   → 변화 없음. 리더 없음.
b3 start (unclean)  → [controller.log] handleBrokerUncleanShutdown
                      PARTITION_CHANGE_RECORD p0: eligibleLeaderReplicas=[2]      ← b3 가 ELR 에서 빠짐
b2 start (unclean)  → [controller.log] handleBrokerUncleanShutdown
                      [controller.log] Setting new leader for ... partition 0 to 2 using an unclean election.
                      UNCLEAN partition change for t-0: isr: [] -> [2], leader: -1 -> 2,
                        leaderRecoveryState: RECOVERED -> RECOVERING, leaderEpoch: 9 -> 10,
                        lastKnownElr: [2] -> []
```

- b4는 ELR에 없으므로 리더 후보가 아니다. `unclean.leader.election.enable=false`라 ④ 경로도 막혀 있다.
- b3는 unclean 재기동이라 ELR에서 빠졌다. 파티션은 여전히 리더가 없다.
- b2도 unclean 재기동이라 ELR에서 빠졌다. 그런데 `LastKnownElr`에 남아 있던 마지막 리더로서, **`unclean.leader.election.enable=false`인데도 unclean 선출로 리더가 됐다.** 이 레코드에는 `leaderRecoveryState=RECOVERING`이 붙는다.

마지막 단계가 `electAnyLeader` ③ `canElectLastKnownLeader`다.

```java
// org.apache.kafka.controller.PartitionChangeBuilder (Kafka 4.2.0, 요약)
private boolean useLastKnownLeaderInBalancedRecovery = true;

private boolean canElectLastKnownLeader() {
    if (!eligibleLeaderReplicasEnabled || !useLastKnownLeaderInBalancedRecovery) return false;
    if (!targetElr.isEmpty() || !targetIsr.isEmpty()) return false;   // ISR·ELR 이 모두 비어 있고
    if (partition.lastKnownElr.length != 1) return false;              // 마지막 리더가 한 명 기록돼 있고
    if (!isAcceptableLeader.test(partition.lastKnownElr[0])) return false; // 그 브로커가 살아 있으면
    return true;                                                        // → 그 브로커를 리더로 (unclean 표시)
}
```

`useLastKnownLeaderInBalancedRecovery`는 기본값이 `true`이고, 4.2.0 메인 코드에서 이 값을 바꾸는 setter를 부르는 곳은 없다. 결국 ELR 이전의 동작과 같다. 마지막 ISR 멤버가 돌아오면 그 브로커가 데이터를 잃었을 수 있어도 리더가 된다. 차이는 컨트롤러가 이 선출을 unclean으로 기록한다는 점이다.

> ELR이 막아 주는 건 **ELR 멤버 중 하나라도 clean하게 살아 돌아오는 경우**다. 전원이 unclean으로 죽으면 마지막 리더가 돌아와 리더가 되고, 앞의 ④~⑥이 그대로 일어날 수 있다.

### 리더 선출 우선순위 정리

`electAnyLeader` 기준이다.

1. 현재 리더가 여전히 유효하면 유지
2. ISR 멤버 중 활성(unfenced, 종료 중 아님) 브로커, replica 목록 순서
3. ISR이 비었으면 ELR 멤버 중 활성 브로커
4. ISR·ELR이 모두 비었고 마지막 리더(`LastKnownElr`)가 살아 있으면 그 브로커 (unclean 표시)
5. `unclean.leader.election.enable=true`면 살아 있는 아무 replica (unclean)
6. 아무도 없으면 리더 없음

KIP-966 문서에는 fenced ELR 멤버를 다루는 `unclean.recovery.strategy` 같은 설정이 제안돼 있다. 하지만 4.2.0 브로커 설정 목록에는 없다. 4.2에서 unclean 쪽 설정은 `unclean.leader.election.enable`과 `unclean.leader.election.interval.ms` 두 개다.

### 버전과 활성화

| 버전 | 상태 |
|------|------|
| Kafka 4.0 | 사용 가능하지만 기본 비활성 |
| Kafka 4.1+ | 새 클러스터에서 기본 활성 |

새로 만든 4.2.0 실습 클러스터의 feature 조회 결과다.

```
Feature: eligible.leader.replicas.version  SupportedMinVersion: 0  SupportedMaxVersion: 1  FinalizedVersionLevel: 1
```

켜고 끄는 건 `kafka-features.sh`로 `eligible.leader.replicas.version`을 1/0으로 바꿔서 한다. 기존 클러스터를 4.1 이상으로 올린 경우에는 이 값이 자동으로 1이 되지 않을 수 있다. 업그레이드한 클러스터라면 위 명령으로 직접 확인해야 한다(이 부분은 업그레이드 경로로 실측하지 않았다).

## 복구 후의 리더 위치

---

> 장애에서 돌아온 브로커는 팔로워로만 들어온다. 리더를 원래 자리(preferred leader)로 되돌리는 건 별도 작업이다.

**preferred leader**는 replica 목록의 첫 번째 브로커다. 토픽을 만들 때 카프카는 파티션마다 첫 번째 replica를 다른 브로커로 배치해 리더를 고르게 나눈다. 실습 토픽도 p0·p1·p2의 첫 replica가 각각 2·3·4다.

장애 후에는 이 분산이 깨진다. b2가 돌아온 뒤에도 p0·p1의 리더가 둘 다 3이었고, b2는 리더를 하나도 맡지 않았다. 이걸 되돌리는 방법은 두 가지다.

### 자동: `auto.leader.rebalance.enable`

기본값은 `true`다. 컨트롤러가 `leader.imbalance.check.interval.seconds`(기본 300초)마다 `electPreferred` 작업을 돌려, preferred leader가 아닌 파티션의 리더를 되돌린다.

```
13:50:08.061  Registering periodic task electPreferred to run every 300000 ms
13:52:21      b2 ISR 복귀 (p0 리더는 여전히 3)
13:55:07.864  PARTITION_CHANGE_RECORD p0: leader=2
```

컨트롤러가 기동한 13:50:08부터 300초 뒤인 13:55:08에 p0의 리더가 2로 돌아왔다. b2가 ISR에 복귀한 뒤 약 3분 반 동안은 리더가 3에 몰려 있었다.

ZooKeeper 모드 시절에는 브로커별 불균형 비율이 `leader.imbalance.per.broker.percentage`(기본 10%)를 넘을 때만 되돌렸다. 4.2.0에는 이 설정이 없다. KRaft 컨트롤러는 비율 기준 없이, preferred leader가 아닌 파티션을 한 번에 최대 1,000개(`ReplicationControlManager.MAX_ELECTIONS_PER_IMBALANCE`)씩 되돌린다.

### 수동: `kafka-leader-election.sh`

```bash
$ kafka-leader-election.sh --bootstrap-server b3:9092 --election-type preferred --all-topic-partitions
Successfully completed leader election (PREFERRED) for partitions t-0
```

실행 직후 p0의 리더가 2로 돌아왔다. `--topic`·`--partition`으로 대상을 좁힐 수도 있다.

`--election-type unclean`으로 실행하면 해당 파티션에 한해 unclean 선출을 시도한다. 리더가 없는 파티션을 유실을 감수하고 살릴 때 쓰는 옵션이다(실측하지 않았다).

## 운영

---

> 장애 대응에서 정할 것은 `min.insync.replicas`·unclean 선출 설정의 조합이고, 볼 것은 컨트롤러와 파티션 상태 메트릭이다.

### 설정 조합 (RF=3 기준)

| 워크로드 | `min.insync.replicas` | `unclean.leader.election.enable` | 우선순위 |
|---------|--------------------|--------------------------------|------|
| 결제·주문·이벤트 소싱 | 2 | false | 유실 방지 |
| 일반 서비스 | 2 | false | 기본값 |
| 로그·텔레메트리 | 1 | true | 가용성, 일부 유실 허용 |

### 메트릭 (JMX)

메트릭 이름은 4.2.0 소스(`org.apache.kafka.controller.metrics`)와 공식 모니터링 문서 기준이다. JMX로 직접 조회해 보지는 않았다.

| 메트릭 | 보는 것 |
|--------|------|
| `kafka.controller:type=KafkaController,name=ActiveControllerCount` | 활성 컨트롤러 수. 클러스터 전체 합이 1이 아니면 이상 |
| `kafka.controller:type=KafkaController,name=FencedBrokerCount` | fencing된 브로커 수 |
| `kafka.controller:type=KafkaController,name=OfflinePartitionsCount` | 리더가 없는 파티션 수. 0이 아니면 그 파티션은 읽기·쓰기 불가 |
| `kafka.controller:type=KafkaController,name=PreferredReplicaImbalanceCount` | preferred leader가 아닌 리더를 가진 파티션 수 |
| `kafka.controller:type=ControllerStats,name=UncleanLeaderElectionsPerSec` | unclean 선출 빈도. 0이 아니면 유실 가능성 조사 |
| `kafka.controller:type=ControllerStats,name=ElectionFromEligibleLeaderReplicasPerSec` | ELR에서 리더를 뽑은 빈도 |
| `kafka.server:type=ReplicaManager,name=UnderReplicatedPartitions` | ISR < RF인 파티션 수 |
| `kafka.server:type=ReplicaManager,name=UnderMinIsrPartitionCount` | ISR < `min.insync.replicas`인 파티션 수. `acks=all` 쓰기가 거부되고 HW가 멈춘 상태 |
| `kafka.server:type=ReplicaManager,name=IsrShrinksPerSec` / `IsrExpandsPerSec` | ISR 변동 빈도. 반복되면 flapping |

## 참고 자료

---

- [Apache Kafka — Design: Replication (kafka.apache.org/42/design)](https://kafka.apache.org/42/design/design/#replication) — ISR 안에서 리더를 뽑는 원칙, unclean leader election의 두 선택지
- [Apache Kafka — Broker Configs (kafka.apache.org/42/configuration)](https://kafka.apache.org/42/configuration/broker-configs) — `broker.session.timeout.ms`, `broker.heartbeat.interval.ms`, `controlled.shutdown.enable`, `auto.leader.rebalance.enable`, `unclean.leader.election.enable`
- [Apache Kafka — Basic Kafka Operations (kafka.apache.org/42/operations)](https://kafka.apache.org/42/operations/basic-kafka-operations/) — graceful shutdown, 리더 균형 맞추기
- [Apache Kafka — Monitoring (kafka.apache.org/42/operations)](https://kafka.apache.org/42/operations/monitoring) — 컨트롤러·ReplicaManager JMX 메트릭
- [KIP-631: The Quorum-based Kafka Controller (cwiki.apache.org)](https://cwiki.apache.org/confluence/display/KAFKA/KIP-631%3A+The+Quorum-based+Kafka+Controller) — 브로커 등록, 하트비트, fencing, broker epoch
- [KIP-966: Eligible Leader Replicas (cwiki.apache.org)](https://cwiki.apache.org/confluence/display/KAFKA/KIP-966%3A+Eligible+Leader+Replicas) — ELR 도입 배경, ISR ≥ min ISR일 때만 HW 전진, clean shutdown 감지
- [apache/kafka 4.2.0 — PartitionChangeBuilder.java (github.com)](https://github.com/apache/kafka/blob/4.2.0/metadata/src/main/java/org/apache/kafka/controller/PartitionChangeBuilder.java) — 리더 선출 순서, ELR 계산, last known leader 선출
