---
title: 카프카 파티션 로그의 오프셋들 — LEO, HW, LSO
date: 2026-08-11 22:00:00 +0900
categories: [지식 더하기, 카프카]
tags: [Kafka]
---

카프카를 쓰면서 만나는 "오프셋"은 하나가 아니다. 컨슈머가 커밋하는 오프셋이 있고, 브로커가 파티션 로그를 관리하려고 들고 있는 오프셋이 따로 있다. ISR·복제·리더 선출을 다루면서 나오는 오프셋은 전부 후자 쪽이고, 이걸 모르면 "팔로워가 리더의 LEO까지 따라잡았는지" 같은 문장에서 막힌다.

이 글은 파티션 로그 위에 존재하는 네 개의 오프셋 — **log start offset, LSO, HW, LEO** — 이 각각 무엇이고 무엇이 그것을 전진시키는지 정리한다. 설정 기본값과 동작은 **Apache Kafka 4.2** 문서 기준이다.

## 파티션 로그와 오프셋

---

> 파티션은 append-only 로그이고, 오프셋은 그 로그에서 레코드의 위치를 가리키는 0부터 시작하는 정수다.

프로듀서가 보낸 레코드는 파티션 로그의 끝에 순서대로 붙는다. 붙는 순간 위치가 정해지고, 그 위치가 오프셋이다. 한번 정해지면 바뀌지 않고, 파티션 안에서 레코드를 유일하게 식별한다.

```
파티션 로그:  [ m0 ][ m1 ][ m2 ][ m3 ]
offset:         0     1     2     3     4 ←  다음에 쓸 자리
```

여기서 중요한 건 **파티션의 복제본(replica)마다 이 로그를 각자 하나씩 들고 있다는 점**이다. 리더 replica는 프로듀서 쓰기를 받아 로그를 늘리고, 팔로워 replica는 리더에게 fetch 요청을 보내 받아온 레코드를 자기 로그에 붙인다. 그래서 같은 파티션이라도 시점에 따라 replica들의 로그 길이가 다르다.

아래에서 볼 오프셋들은 이 "여러 개의 로그"라는 사실 위에 서 있다. 어떤 것은 replica마다 값이 다르고(LEO), 어떤 것은 리더가 계산해서 모두에게 알려준다(HW).

## LEO (Log End Offset)

---

> LEO는 **각 replica가 자기 로그에 다음으로 쓸 오프셋**이다. 마지막 레코드의 오프셋 + 1이고, 로그가 비어 있으면 log start offset과 같다.

앞의 그림에서 `4`가 LEO다. "마지막 레코드의 오프셋"이 아니라 "다음에 쓸 자리"라는 점이 헷갈리기 쉬운데, 이렇게 잡아두면 `LEO - log start offset`이 곧 보유 중인 레코드 개수가 되고 구간을 `[start, end)` 반열림으로 다룰 수 있다.

**LEO는 replica마다 값이 다르다.** 리더가 오프셋 200까지 받았는데 느린 팔로워는 아직 100까지만 받았다면, 리더 LEO는 200이고 그 팔로워의 LEO는 100이다. 이 차이가 곧 복제 지연(lag)이고, ISR 판정의 기준이 되는 것도 이 값이다.

| replica | LEO를 전진시키는 것 |
|---|---|
| 리더 | **프로듀서의 쓰기**. produce 요청을 받아 자기 로그에 append하면 그만큼 전진 |
| 팔로워 | **fetch 응답의 레코드**. 리더에게서 받아온 레코드를 자기 로그에 append하면 전진 |

### 리더는 팔로워의 LEO를 어떻게 아는가

팔로워가 별도로 "나 여기까지 받았어요"를 보고하지 않는다. 팔로워가 보내는 `FetchRequest`의 `fetch_offset` 필드가 곧 그 팔로워의 LEO다.

```
팔로워 → 리더 :  FetchRequest(fetch_offset = 100)
리더          :  "이 팔로워는 99까지 받았고, LEO는 100이구나"
              →  records[100..200] + 현재 HW를 응답
팔로워        :  append → 자기 LEO = 200
              →  즉시 FetchRequest(fetch_offset = 200) 전송
```

어차피 보내야 하는 fetch 요청에 진행 상황을 얹어 보내는 것이라 별도의 ACK 메시지가 필요 없다. 리더 입장에서는 fetch 요청 하나가 "직전 데이터 확인 + 다음 데이터 요청"을 겸한다.

## HW (High Watermark)

---

> HW는 **ISR에 속한 모든 replica가 복제를 마친 지점**이다. `HW = min(리더 LEO, ISR 팔로워들의 LEO)`로 계산되고, 컨슈머가 읽을 수 있는 경계가 된다.

오프셋이 HW보다 작은 레코드는 ISR 전원의 로그에 들어가 있다. 즉 replica 하나가 죽어도 남아 있다. 이 상태를 카프카는 **committed**라고 부르고, 컨슈머에게는 committed된 레코드만 보여준다.

```
리더 로그:  [ m0 ][ m1 ][ m2 ][ m3 ][ m4 ]
offset:       0     1     2     3     4     5 ← LEO
                                ↑
                              HW = 3
            └─ committed ─┘ └ 미복제 꼬리 ┘
```

`m3`, `m4`는 리더 로그에는 있지만 아직 ISR 전원에게 복제되지 않았다. 컨슈머는 이 구간을 받지 못한다.

**컨슈머가 "안 보는" 게 아니라 리더가 "안 준다".** 컨슈머의 fetch 요청(`replica_id = -1`)에 리더는 HW까지만 잘라서 응답한다. 반면 팔로워의 fetch 요청(`replica_id ≥ 0`)에는 리더 LEO까지 다 준다 — 팔로워가 그 꼬리를 가져가야 HW가 전진하기 때문이다. 같은 Fetch API인데 요청자에 따라 응답 상한이 다르다.

### HW를 미는 건 팔로워의 fetch다

리더 LEO는 프로듀서가 밀지만, HW는 팔로워가 민다. 이 둘의 동력이 다르다는 점이 `acks=all`의 동작으로 이어진다. 팔로워들이 fetch로 따라붙어 → 리더가 `min(LEO)`를 다시 계산해 HW를 전진시키고 → HW가 해당 오프셋을 넘어서면 그때 대기 중이던 `acks=all` produce 요청에 ack이 나간다.

### 팔로워는 HW를 한 라운드 늦게 안다

HW는 리더가 계산해서 `FetchResponse`의 `high_watermark` 필드로 알려준다. 팔로워는 그걸 받아 `자기 HW = min(응답의 리더 HW, 자기 LEO)`로 갱신한다. 자기가 갖고 있지도 않은 오프셋을 committed로 표시할 수는 없으니 min을 취한다.

```
초기: 리더 LEO=200(프로듀서가 씀), F1.LEO=F2.LEO=100, HW=100

① F1: Fetch(100) → 리더: F1.LEO=100 기록, records[100..200] + HW=100 응답
② F1: append → LEO=200, 자기 HW = min(100, 200) = 100, Fetch(200) 전송
③ F2도 동일하게 200까지 따라붙어 Fetch(200) 전송
④ 리더: F1.LEO=F2.LEO=200 확인 → HW = min(200,200,200) = 200 전진
⑤ 리더: F1의 Fetch(200)에 HW=200을 실어 응답
⑥ F1: 자기 HW = min(200, 200) = 200  ← 이제서야 학습
```

리더는 ④에서 HW=200을 알지만 팔로워는 ⑥에서야 안다. **HW 전파는 항상 한 라운드 늦다.** 여기서 한 라운드는 `FetchRequest` 하나가 나갔다가 `FetchResponse`가 돌아오는 **왕복 1회**를 말한다.

한 라운드가 뜨는 이유는 이렇다. ①의 응답이 나가는 시점에는 팔로워가 아직 데이터를 받기 전이니 HW=100이 맞다. 팔로워가 받았다는 사실은 ④, 즉 **다음 요청의 `fetch_offset`으로** 리더에게 도착하고, 그렇게 새로 계산된 HW를 실어 보낼 응답은 그 다음 응답인 ⑤뿐이다. 리더가 중간에 "HW가 올랐다"고 따로 통보하는 경로가 없어서(pull 모델) 왕복 하나가 구조적으로 밀린다.

이 시차가 팔로워 재시작 시 로그를 자르는(truncation) 판단을 HW로 하면 안 되는 이유이고, Leader Epoch이 도입된 배경이기도 하다.

> Kafka 4.x에서 ELR(Eligible Leader Replicas, KIP-966)을 활성화하면 여기에 조건이 하나 붙는다. ISR 크기가 `min.insync.replicas` 이상일 때만 HW가 전진한다. 이렇게 해야 "HW까지의 데이터는 최소 그만큼의 replica에 있다"가 보장된다. Kafka 4.0은 기본 비활성, 4.1부터 신규 클러스터 기본 활성이다.

## LSO (Last Stable Offset)

---

> LSO는 **트랜잭션이 확정된 경계**다. 진행 중인 트랜잭션이 없으면 HW와 같고, 있으면 그중 가장 이른 트랜잭션의 첫 오프셋에서 멈춘다.

트랜잭션 프로듀서가 쓴 레코드는 로그에 먼저 들어가고, commit 여부는 나중에 control marker로 기록된다. 그래서 로그에는 "복제는 끝났지만 commit인지 abort인지 아직 모르는" 구간이 생길 수 있다. 그 구간의 시작점이 LSO다.

`isolation.level=read_committed` 컨슈머는 LSO 미만까지만 읽는다. abort된 트랜잭션의 레코드를 보여주지 않기 위해서다. 기본값인 `read_uncommitted` 컨슈머는 HW까지 읽는다.

여기서 자주 나오는 오해가 하나 있다.

> `read_uncommitted`로 두면 리더 LEO까지 다 받는다 → **아니다.**

`isolation.level`이 조정하는 건 **트랜잭션 축**이지 **복제 축**이 아니다. 컨슈머 응답의 상한은 isolation level과 무관하게 **항상 HW**이고, `read_uncommitted`는 그 HW 안쪽에서 "commit 안 된 트랜잭션 레코드도 보여줘"라는 의미다. "복제 안 된 레코드도 보여줘"가 아니다.

| "committed"의 두 축 | 의미 | 경계 |
|---|---|---|
| 복제 관점 committed | ISR 전원에게 복제됨 (내구성) | **HW** |
| 트랜잭션 관점 committed | 프로듀서 트랜잭션이 commit됨 | **LSO** (≤ HW) |

HW와 LEO 사이의 미복제 꼬리는 어떤 컨슈머에게도 가지 않는다. 그 구간은 팔로워만 받아가고, 팔로워는 `isolation.level` 자체를 쓰지 않는다.

## log start offset

---

> log start offset은 **파티션에 아직 남아 있는 가장 오래된 오프셋**이다. 로그의 왼쪽 경계다.

파티션 로그는 무한히 자라지 않는다. 보존 정책(`retention.ms`, `retention.bytes`)에 걸린 오래된 세그먼트가 삭제되거나, `DeleteRecords` API로 특정 오프셋 이전을 잘라내면 log start offset이 그만큼 전진한다. 삭제된 오프셋 번호가 재사용되지는 않는다.

```
삭제 전:  [ m0 ][ m1 ][ m2 ][ m3 ]    log start offset = 0
           0     1     2     3

삭제 후:              [ m2 ][ m3 ]    log start offset = 2
                       2     3
```

컨슈머가 log start offset보다 작은 오프셋을 요청하면 `OFFSET_OUT_OF_RANGE`가 나고, 이때 `auto.offset.reset`(기본 `latest`) 설정에 따라 위치가 재조정된다. 오랫동안 멈춰 있던 컨슈머 그룹을 다시 띄웠을 때 메시지를 건너뛰는 상황이 여기서 나온다.

## 네 오프셋의 순서 관계

---

> 정상 상태에서 네 오프셋은 항상 `log start offset ≤ LSO ≤ HW ≤ LEO` 순서를 지킨다.

```
로그:  [ ...... 삭제됨 ...... ][ 확정 ][ 트랜잭션 미확정 ][ 미복제 꼬리 ]
                              ↑        ↑                  ↑              ↑
                    log start offset  LSO                HW            LEO

read_committed   컨슈머  →  LSO 까지
read_uncommitted 컨슈머  →  HW  까지
팔로워 replica          →  LEO 까지   (복제해야 HW가 전진하므로)
```

| 오프셋 | 무엇을 가리키나 | 무엇이 전진시키나 | 값이 replica마다 다른가 |
|---|---|---|---|
| log start offset | 남아 있는 가장 오래된 오프셋 | 보존 정책 만료, `DeleteRecords` | 대체로 같음 |
| LSO | 트랜잭션 확정 경계 | 트랜잭션 commit/abort marker 기록 | 리더가 계산 |
| HW | ISR 전원이 복제한 경계 (committed) | **팔로워의 fetch** | 리더가 계산해 전파 (한 라운드 지연) |
| LEO | 다음에 쓸 자리 | 리더는 **프로듀서 쓰기**, 팔로워는 **fetch 응답** | **다름** |

ISR 관련 설명에서 "팔로워가 리더의 LEO까지 따라잡았는가"를 따지는 이유가 이 표에 있다. 리더 LEO는 프로듀서가 계속 밀어 올리는 목표점이고, 팔로워 LEO는 그걸 쫓아가는 현재 위치다. 정해진 시간(`replica.lag.time.max.ms`, 기본 30초) 안에 한 번도 그 목표점에 닿지 못하면 그 팔로워는 ISR에서 빠진다.

## committed 메시지와 committed offset은 다른 것이다

---

> 이름이 같아서 섞이기 쉽지만, HW가 정하는 "committed 메시지"와 컨슈머가 커밋하는 "committed offset"은 영역도 주체도 다르다.

| | committed 메시지 (HW) | committed offset (컨슈머) |
|---|---|---|
| 영역 | 브로커 / 복제 | 컨슈머 / 진행 추적 |
| 의미 | ISR 전원에게 복제됨 → 내구성·가시성 확보 | 내가 여기까지 처리했다 |
| 저장 | 리더가 메모리에서 관리 | `__consumer_offsets` 토픽에 기록 |
| 전진 주체 | 리더가 ISR의 LEO를 보고 계산 | 컨슈머가 `commitSync()` / auto-commit |
| 답하는 질문 | *데이터가 안전한가?* | *어디까지 읽었나?* |

여기에 컨슈머 쪽 오프셋이 하나 더 있다. **position**은 컨슈머가 다음에 fetch할 오프셋으로 메모리에만 있고, `poll()` 할 때마다 전진한다. committed offset은 그 position을 브로커에 기록해 둔 스냅샷이다. 둘이 벌어져 있는 동안 컨슈머가 죽으면 committed offset부터 다시 읽게 되고, 그 구간이 중복 처리된다.

컨슈머 오프셋 커밋의 흐름은 [카프카 프로듀서에서 컨슈머까지의 처리 흐름](/posts/kafka-producer-to-consumer-flow/)에서 다뤘다.

## 직접 확인하기

---

> CLI로 확인할 수 있는 건 log start offset과 HW까지다. 리더 LEO는 외부 클라이언트 API로 노출되지 않는다.

```bash
# latest offset — read_uncommitted 기준이므로 실제로는 HW
kafka-get-offsets.sh --bootstrap-server localhost:9092 --topic my-topic --time -1

# earliest offset — log start offset
kafka-get-offsets.sh --bootstrap-server localhost:9092 --topic my-topic --time -2
```

`--time -1`이 반환하는 값은 리더 LEO가 아니라 **HW**다. `KafkaConsumer.endOffsets()`도 마찬가지다 — `read_uncommitted`에서는 HW를, `read_committed`에서는 LSO를 돌려준다. 즉 일반 클라이언트에게 HW와 LEO 사이의 미복제 꼬리는 존재 자체가 보이지 않는다.

replica별 LEO를 보려면 각 브로커의 JMX 지표를 봐야 한다. 복제 지연 정도만 알면 되는 경우라면 `kafka-log-dirs.sh --describe` 출력의 replica별 `offsetLag`으로도 충분하다.

> 이 절의 명령은 동작 방식 설명이고, 실제 클러스터를 띄워 얻은 출력값은 아직 싣지 않았다. 값의 정확한 형태는 직접 실행해 확인하는 편이 좋다.

## 참고 자료

---

- [Apache Kafka — Design: Replication (kafka.apache.org/42/design)](https://kafka.apache.org/42/design/design/#replication) — committed 메시지의 정의와 ISR
- [Apache Kafka — Design: Consumer Position (kafka.apache.org/42/design)](https://kafka.apache.org/42/design/design/#consumer-position) — 컨슈머가 오프셋을 관리하는 이유
- [KafkaConsumer javadoc — endOffsets (kafka.apache.org/42/javadoc)](https://kafka.apache.org/42/javadoc/org/apache/kafka/clients/consumer/KafkaConsumer.html) — isolation level에 따라 HW / LSO가 반환된다는 설명
- [Apache Kafka — A Guide To The Kafka Protocol: Fetch API (kafka.apache.org/protocol)](https://kafka.apache.org/protocol.html) — `fetch_offset`, `high_watermark`, `log_start_offset` 필드
- [KIP-101: Reduce log complexity with Leader Epoch (cwiki.apache.org)](https://cwiki.apache.org/confluence/display/KAFKA/KIP-101+-+Alter+Replication+Protocol+to+use+Leader+Epoch+rather+than+High+Watermark+for+Truncation) — HW 전파 지연이 만드는 문제
- [KIP-966: Eligible Leader Replicas (cwiki.apache.org)](https://cwiki.apache.org/confluence/display/KAFKA/KIP-966:+Eligible+Leader+Replicas) — ISR 크기에 따른 HW 전진 조건
