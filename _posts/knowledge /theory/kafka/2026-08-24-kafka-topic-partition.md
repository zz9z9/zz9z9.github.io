---
title: Kafka - 토픽과 파티션
date: 2026-08-24 21:00:00 +0900
categories: [지식 더하기, 카프카]
tags: [Kafka]
---

토픽과 파티션은 카프카에서 가장 먼저 배우는 개념이지만, "토픽은 폴더고 파티션은 그 안의 파일"이라는 비유 수준에서 멈추기 쉽다. 실제 디스크를 열어 보면 그 비유는 맞지 않고, 그 차이를 모르면 "파티션은 왜 줄일 수 없는가", "파티션을 늘렸더니 왜 순서가 깨지는가" 같은 질문에서 막힌다.

이 글은 토픽과 파티션의 정의부터 디스크에 실제로 어떻게 놓이는지, 그리고 운영에서 걸리는 지점들을 정리한다. 본문의 명령 출력과 파일 목록은 모두 **Apache Kafka 4.3.1**(`apache/kafka:latest`, KRaft 단일 노드) 컨테이너를 띄워 직접 실행해 얻은 결과다.

## 정의

---

> 토픽은 이벤트를 분류하는 이름이고, 파티션은 그 토픽을 실제로 나눠 담는 단위다.

공식 문서는 토픽을 이렇게 설명한다.

> "Events are organized and durably stored in topics. Very simplified, a topic is similar to a folder in a filesystem, and the events are the files in that folder."

여기서 "Very simplified"라는 단서가 붙어 있다. 실제 구현은 폴더 구조가 아니고, 그 얘기는 아래 [디스크 위의 실체](#디스크-위의-실체) 절에서 다룬다.

파티션은 다음과 같이 정의된다.

> "Topics are partitioned, meaning a topic is spread over a number of 'buckets' located on different Kafka brokers."

토픽 하나가 여러 브로커에 흩어진 파티션 N개로 쪼개진다. 이 구조에서 나오는 성질이 카프카의 거의 모든 동작을 결정한다.

| | 토픽 | 파티션 |
| --- | --- | --- |
| 역할 | 이벤트의 **분류** | 이벤트의 **저장·분산 단위** |
| 실체 | 메타데이터상의 이름 + ID | append-only 로그 (디스크의 파일들) |
| 순서 보장 | **없음** | **있음** (오프셋 순) |
| 복제 단위 | 아님 | **맞음** (leader 1 + follower N) |
| 병렬 처리 단위 | 아님 | **맞음** (컨슈머 그룹 내 분배) |
| 개수 변경 | 생성/삭제 | 증가만 가능, **감소 불가** |

순서 보장의 범위가 핵심이다.

> "Kafka guarantees that any consumer of a given topic-partition will always read that partition's events in exactly the same order as they were written."

**topic-partition** 단위라고 명시돼 있다. 토픽 전체의 순서를 보장한다는 말은 어디에도 없다.

## 디스크 위의 실체

---

> `log.dirs` 아래에는 토픽 디렉터리가 없다. `<토픽명>-<파티션번호>` 디렉터리가 파티션 개수만큼 평평하게 놓인다.

파티션 3개짜리 토픽을 만들고 브로커의 로그 디렉터리를 열어 보면 이렇다.

```bash
$ kafka-topics.sh --bootstrap-server localhost:9092 \
    --create --topic order-events --partitions 3 --replication-factor 1
Created topic order-events.

$ ls /tmp/kraft-combined-logs/
.lock
__cluster_metadata-0/
bootstrap.checkpoint
cleaner-offset-checkpoint
log-start-offset-checkpoint
meta.properties
order-events-0/          ← 파티션 0
order-events-1/          ← 파티션 1
order-events-2/          ← 파티션 2
recovery-point-offset-checkpoint
replication-offset-checkpoint
```

`order-events/` 라는 디렉터리는 없다. 토픽 이름은 파티션 디렉터리 이름의 **접두어로만** 존재한다. 공식 문서의 표현도 디렉터리는 파티션 단위라고 못박는다.

> "The name of partition directories consists of the topic name, appended by a dash (-) and the partition id."

### 파티션 디렉터리 안

파티션 디렉터리 하나를 열면 다음과 같다.

```bash
$ ls -la /tmp/kraft-combined-logs/order-events-0/
-rw-r--r-- 10485760  00000000000000000000.index
-rw-r--r--        0  00000000000000000000.log
-rw-r--r-- 10485756  00000000000000000000.timeindex
-rw-r--r--        8  leader-epoch-checkpoint
-rw-r--r--       43  partition.metadata
```

| 파일 | 역할 |
| --- | --- |
| `.log` | 실제 레코드가 append되는 세그먼트 파일 |
| `.index` | 오프셋 → 파일 내 byte position 매핑 (희소 인덱스) |
| `.timeindex` | 타임스탬프 → 오프셋 매핑 (`offsetsForTimes`, 시간 기반 retention에 사용) |
| `.snapshot` | producer id 상태 스냅샷 (멱등/트랜잭션 프로듀서 복구용) |
| `leader-epoch-checkpoint` | leader epoch → 시작 오프셋. 로그 truncation 판단에 사용 |
| `partition.metadata` | 이 파티션이 속한 `topic_id` |

`.log` 파일이 0바이트인데 `.index`는 10MB다. 활성 세그먼트의 인덱스 파일은 `log.index.size.max.bytes`(기본 10MB)만큼 미리 할당되고, 세그먼트가 닫힐 때 실제 크기로 잘린다.

`order-1001` ~ `order-10010` 키로 메시지 10건을 넣으면 `.log`에 데이터가 들어간다. 다만 10건이 한 파일에 모이지는 않는다. 파티션이 3개이므로 키 해시에 따라 셋으로 갈라지고, **아래는 그중 파티션 0의 `.log` 하나만 덤프한 것**이다.

```bash
$ kafka-dump-log.sh --files .../order-events-0/00000000000000000000.log --print-data-log
Log starting offset: 0
baseOffset: 0 lastOffset: 4 count: 5 ... isTransactional: false isControl: false
  position: 0 CreateTime: 1787577612696 size: 336 magic: 2 compresscodec: none crc: 871884934
| offset: 0 CreateTime: 1787577612677 keySize: 10 valueSize: 38 sequence: 0 headerKeys: []
    key: order-1001 payload: {"orderId":"order-1001","amount":1000}
| offset: 1 ... key: order-1002 payload: {"orderId":"order-1002","amount":2000}
| offset: 2 ... key: order-1004 payload: {"orderId":"order-1004","amount":4000}
| offset: 3 ... key: order-1005 payload: {"orderId":"order-1005","amount":5000}
| offset: 4 ... key: order-1007 payload: {"orderId":"order-1007","amount":7000}
```

파티션 0에 5건이 들어갔다. 나머지는 파티션 1에 4건(`order-1003`, `1006`, `1008`, `10010`), 파티션 2에 1건(`order-1009`)으로 갈렸다. 합쳐서 10건이다. 키가 어느 파티션으로 가는지는 [레코드는 어느 파티션으로 가는가](#레코드는-어느-파티션으로-가는가)에서 다룬다.

저장 형태를 보면 레코드가 하나씩 쌓이는 게 아니라 **레코드 배치(record batch)** 단위로 묶여 있다. 위 출력에서 `baseOffset: 0 lastOffset: 4 count: 5`가 배치 하나이고, 그 안에 개별 레코드 5건이 들어 있다. 압축·CRC·트랜잭션 여부는 전부 배치 헤더에 달린다.

### 세그먼트 — 파티션 로그를 쪼갠 파일 단위

파티션 로그는 논리적으로는 끝없이 append되는 하나의 로그지만, 물리적으로는 파일 하나가 아니다. 일정 크기·기간마다 새 파일로 끊어서 저장하고, 그 조각 하나를 세그먼트(segment)라고 부른다.

> "Each log file is named with the offset of the first message it contains. So the first file created will be 00000000000000000000.log"

`segment.bytes`를 1MiB로 낮추고 1KB 레코드 4,000건(약 4MB)을 넣으면 파티션 디렉터리가 이렇게 된다.

```bash
$ kafka-producer-perf-test.sh --topic seg-demo --num-records 4000 --record-size 1024 ...
4000 records sent, 3633.060854 records/sec (3.55 MB/sec) ...

$ ls -la /tmp/kraft-combined-logs/seg-demo-0/
     528  00000000000000000000.index      ┐
 1044700  00000000000000000000.log        ├ 세그먼트 ①   offset 0 ~ 1027
     780  00000000000000000000.timeindex  ┘
     528  00000000000000001028.index      ┐
 1042252  00000000000000001028.log        │ 세그먼트 ②   offset 1028 ~ 2032
     608  00000000000000001028.snapshot   │
     756  00000000000000001028.timeindex  ┘
     528  00000000000000002033.index      ┐
 1042252  00000000000000002033.log        ├ 세그먼트 ③   offset 2033 ~ 3037
     ...                                  ┘
10485760  00000000000000003038.index      ┐
 1021531  00000000000000003038.log        ├ 세그먼트 ④   offset 3038 ~  (쓰는 중)
10485756  00000000000000003038.timeindex  ┘
```

두 단계로 나눠서 봐야 한다.

- **세그먼트 하나** = 같은 숫자를 이름으로 공유하는 `.log` / `.index` / `.timeindex` 묶음. 그 숫자는 세그먼트의 첫 레코드 오프셋(base offset)이다.
- **파티션 하나** = 이런 세그먼트 여러 개.

쓰기가 `.log`에 일어나는 건 맞다. 다만 `.log`는 파티션당 하나가 아니라 위처럼 세그먼트 수만큼 있고, **프로듀서가 보낸 레코드는 그중 마지막 세그먼트의 `.log`에만 붙는다.** ①~③의 `.log`는 이미 닫혀서 읽기 전용이고, 새 레코드는 전부 ④로 간다.

이 "지금 쓰기를 받고 있는 마지막 세그먼트"를 부르는 이름이 **활성 세그먼트(active segment)** 다. 따로 존재하는 구조가 아니라 위치를 가리키는 호칭이고, 롤링이 일어나면 새로 생긴 세그먼트가 그 자리를 넘겨받는다. 파티션마다 항상 정확히 하나씩 있다.

`ls` 출력만으로 어느 게 활성인지 구분된다. 인덱스가 10MB면 활성, ①~③처럼 528바이트로 잘려 있으면 닫힌 세그먼트다. 인덱스 파일은 미리 10MB(`log.index.size.max.bytes`)로 할당해 두고 세그먼트가 닫힐 때 실제 크기로 잘라내기 때문이다.

### 세그먼트가 넘어가는 조건

새 세그먼트로 넘어가는(rolling) 조건은 두 가지다.

| 설정 | 기본값 | 롤링 조건 |
| --- | --- | --- |
| `segment.bytes` | 1GiB | 활성 세그먼트가 이 크기를 넘으면 |
| `segment.ms` | 7일 | 활성 세그먼트가 만들어진 지 이 시간이 지나면 |

둘 중 **먼저 걸리는 쪽**이 적용된다. 위 예시는 크기 기반이고, `segment.ms=10000`으로 두면 크기와 무관하게 시간만으로 닫힌다.

```bash
$ ls -la /tmp/kraft-combined-logs/segms-0/
       0  00000000000000000000.index
     147  00000000000000000000.log      ← 147바이트인데 이미 닫혔다
      12  00000000000000000000.timeindex
10485760  00000000000000000002.index
      74  00000000000000000002.log      ← 활성 세그먼트
10485756  00000000000000000002.timeindex
```

`segment.bytes`의 최솟값은 4.3 기준 1MiB다. 더 작게 넣으면 거부된다.

```
InvalidConfigurationException: Invalid value 300 for configuration segment.bytes:
Value must be at least 1048576
```

### 세그먼트로 쪼개는 이유는 삭제 때문이다

> "Deleting is done one log segment at a time."

retention이 만료돼도 카프카는 레코드를 하나씩 지우지 않는다. **세그먼트 파일을 통째로 지운다.** 로그 중간을 건드리지 않으므로 append-only 성질이 그대로 유지되고, 삭제 비용도 파일 unlink 한 번으로 끝난다. 즉 세그먼트는 **retention이 작동하는 최소 단위**다.

여기서 따라오는 결론이 하나 있다. **retention은 세그먼트 단위로만 걸리므로, `retention.ms`가 지났다고 해서 그 시점에 데이터가 사라지지는 않는다.** 세그먼트가 닫히고, 그 세그먼트 안의 **가장 마지막 레코드**까지 보존 기간을 넘겨야 삭제 대상이 된다. `segment.bytes`가 1GiB인데 트래픽이 적으면 세그먼트가 며칠씩 안 닫히고, 그동안 데이터는 남아 있는다.

`retention.ms=10000`(10초)을 걸고 실제로 관찰한 순서는 이렇다. 세그먼트 4개(약 4MB)가 쌓인 토픽에 더 이상 produce하지 않고 40초를 기다렸다.

```bash
# ① 만료 판정 직후 — 파일명에 .deleted 가 붙는다
    1042252  00000000000000000000.log.deleted
    1042252  00000000000000001005.log.deleted
    1042252  00000000000000002010.log.deleted
    1021531  00000000000000003015.log.deleted   ← 활성 세그먼트였던 것
          0  00000000000000004000.log           ← 새로 만들어진 빈 활성 세그먼트

# ② file.delete.delay.ms(기본 60초) 뒤 — 물리적으로 사라진다
          0  00000000000000004000.log
         56  00000000000000004000.snapshot
   10485756  00000000000000004000.timeindex
```

두 가지가 드러난다.

- **활성 세그먼트도 결국 삭제된다.** 다만 바로 지우는 게 아니라, 빈 세그먼트(`...4000`)를 새로 롤링해 활성 자리를 넘긴 뒤 원래 것을 삭제한다. 쓰기 대상이 없는 순간이 생기지 않게 하려는 순서다.
- **삭제는 2단계다.** 먼저 `.deleted`로 이름만 바꿔 로그에서 떼어 내고, `file.delete.delay.ms`(기본 60초) 뒤에 실제로 파일을 지운다. 그 사이에 진행 중이던 읽기가 파일을 붙잡고 있어도 안전하다.

삭제 후 오프셋을 보면 이렇다.

```bash
$ kafka-get-offsets.sh --bootstrap-server localhost:9092 --topic seg --time -2   # earliest
seg:0:4000
$ kafka-get-offsets.sh --bootstrap-server localhost:9092 --topic seg --time -1   # latest
seg:0:4000
```

레코드는 전부 사라졌지만 오프셋은 0으로 돌아가지 않고 4000에서 이어진다. 삭제된 오프셋 번호는 재사용되지 않는다.

### `.index` — 오프셋을 파일 안의 위치로 바꾸는 표

컨슈머는 "오프셋 3,500번부터 달라"고 요청한다. 브로커는 이걸 **파일 읽기**로 바꿔야 하는데, 파일에서 데이터를 읽으려면 "몇 번째 바이트부터"를 알아야 한다. 이 파일 안에서의 바이트 위치가 **byte position**이다.

레코드는 길이가 제각각이라 `오프셋 × 레코드 크기`로 계산할 수 없다. 그래서 **오프셋 → byte position** 대응표를 따로 파일로 들고 있고, 그게 `.index`다.

```bash
$ kafka-dump-log.sh --files .../seg-demo-0/00000000000000000000.index
offset: 52   position: 18004
offset: 67   position: 33560
offset: 82   position: 49116
offset: 97   position: 64672
offset: 112  position: 80228
```

두 번째 줄은 "오프셋 67번 레코드는 이 세그먼트 `.log` 파일의 33,560번째 바이트부터 시작한다"는 뜻이다. 이 값이 있으면 브로커는 파일을 처음부터 훑지 않고 곧장 그 위치로 `seek`할 수 있다.

### 희소(sparse) 인덱스 — 전부 적지 않는다

위 출력에서 오프셋이 52, 67, 82, 97로 **15씩 건너뛴다.** 0~51번, 53~66번 레코드의 위치는 표에 아예 없다. 이렇게 **일부 레코드에 대해서만 엔트리를 두는 인덱스를 희소(sparse) 인덱스**라고 한다. 반대로 모든 레코드에 엔트리가 있으면 조밀(dense) 인덱스다.

그러면 표에 없는 오프셋 60번은 어떻게 찾는가.

```
① .index 에서 60 이하의 가장 큰 엔트리를 이진 탐색   →  offset 52, position 18004
② .log 파일의 18004 바이트로 seek
③ 거기서부터 레코드를 순차로 읽으며 60번이 나올 때까지 전진
```

정확한 위치는 인덱스가 알려주지 않는다. **"이 근처"까지만 점프시켜 주고 나머지는 스캔**한다. 공식 문서의 설명도 같은 순서다.

> "locating the log segment file in which the data is stored, calculating the file-specific offset from the global offset value, and then reading from that file offset"

엔트리 간격은 `index.interval.bytes`(기본 4096)로 정해진다. 로그에 4KB를 쓸 때마다 엔트리를 하나 추가하되, 레코드 배치 경계에서만 기록하므로 배치가 크면 위처럼 간격이 더 벌어진다. 그래서 스캔 구간은 대체로 수 KB 수준이다.

### 왜 조밀하게 만들지 않는가

인덱스 엔트리는 **8바이트**다 (relative offset 4바이트 + position 4바이트). 파일 크기로 확인된다.

| 파일 | 크기 | ÷ 8 | ÷ 12 |
| --- | --- | --- | --- |
| `.index` (닫힘) | 528 | **66** | 44 |
| `.index` (활성, 미리 할당) | 10485760 | **1310720** | 873813.33 |
| `.timeindex` (닫힘) | 780 | 97.5 | **65** |
| `.timeindex` (활성) | 10485756 | 1310719.5 | **873813** |

활성 `.index`(10485760)는 8로 떨어지지만 12로는 안 떨어지고, 닫힌 `.timeindex`(780)는 12로 떨어지지만 8로는 안 떨어진다. 두 파일의 엔트리 크기가 다르다는 뜻이다 — `.timeindex` 엔트리는 timestamp 8바이트 + relative offset 4바이트 = 12바이트다. 활성 `.timeindex`가 10MB가 아니라 10485756인 것도 10MB 이하 12의 배수 중 최댓값이라서다.

파일명이 base offset인 이유도 여기 있다. 엔트리에 절대 오프셋 대신 **base offset으로부터의 상대 오프셋**을 저장하면 4바이트로 충분해진다. 세그먼트 이름이 곧 기준점 역할을 한다.

1,044,700바이트짜리 세그먼트의 인덱스가 528바이트, 즉 엔트리 66개다. 레코드 1,028건에 엔트리 66개니까 대략 **1/16 수준**만 적어 둔 셈이다. 모든 레코드에 엔트리를 달면 인덱스가 8KB를 넘는다.

인덱스 파일은 mmap으로 메모리에 올라가므로 엔트리 수가 곧 페이지 캐시 압박이 된다. 파티션이 수천 개면 이 차이가 그대로 브로커 메모리 사용량이 된다. 어차피 순차 읽기는 빠르니 대략의 위치만 잡고 나머지를 스캔하는 쪽이 이득이다.

### 그러면 토픽은 어디에 있는가

토픽의 실체는 디스크의 데이터가 아니라 **KRaft 메타데이터 로그의 레코드**다. `__cluster_metadata-0`을 디코딩해 보면 토픽과 파티션이 별도 레코드로 남아 있다.

```bash
$ kafka-dump-log.sh --cluster-metadata-decoder --files .../__cluster_metadata-0/00000000000000000000.log

{"type":"TOPIC_RECORD","version":0,
 "data":{"name":"order-events","topicId":"arvK229bSmSz_lBQJbIuhg"}}

{"type":"PARTITION_RECORD","version":2,
 "data":{"partitionId":0,"topicId":"O9tTOuh6TLaWS7nww1ejbg",
         "replicas":[1],"isr":[1],"removingReplicas":[],"addingReplicas":[],
         "leader":1,"leaderEpoch":0,"partitionEpoch":0,
         "directories":["g0NiE87GanF13iNX2t0zCQ"]}}
```

`TOPIC_RECORD`가 들고 있는 건 이름과 ID뿐이다. 어느 브로커에 있는지, 누가 리더인지, 어느 디스크에 놓였는지는 전부 `PARTITION_RECORD` 쪽에 있다.

> 토픽은 파티션들을 묶는 **이름표**이고, 데이터와 배치 정보는 전부 파티션에 달려 있다.

앞의 "토픽은 폴더"라는 비유를 정정하면 이렇게 된다.

| | 흔한 비유 | 실제 |
| --- | --- | --- |
| 토픽 | 폴더 | 메타데이터 레코드 (이름 + `topic_id`) |
| 파티션 | 폴더 안의 로그 파일 | **디렉터리** (`<topic>-<id>`) |
| 세그먼트 | — | 그 디렉터리 안의 `.log` / `.index` / `.timeindex` 파일 묶음 |

## 레코드는 어느 파티션으로 가는가

---

> 파티션 선택은 브로커가 아니라 프로듀서가 한다. 키가 있으면 키 해시, 없으면 배치 단위로 한 파티션에 몰아 보낸다.

`partitioner.class`를 지정하지 않았을 때의 기본 동작은 다음과 같다.

> "1. If no partition is specified but a key is present, choose a partition based on a hash of the key. 2. If no partition or key is present, choose the sticky partition that changes when at least `batch.size` bytes are produced to the partition."

키가 있을 때의 해시는 murmur2다. `BuiltInPartitioner.partitionForKey`를 디컴파일하면 이렇다.

```
public static int partitionForKey(byte[], int);
   0: aload_0
   1: invokestatic  Utils.murmur2:([B)I
   4: invokestatic  Utils.toPositive:(I)I
   7: iload_1
   8: irem                                  // % numPartitions
```

즉 `toPositive(murmur2(keyBytes)) % numPartitions`. 파티션 수가 식에 직접 들어간다는 점이 뒤에 나올 문제의 원인이다.

키를 `order-1001` ~ `order-10010`으로 주고 파티션 3개짜리 토픽에 넣으면 이렇게 흩어진다.

```
Partition:0  order-1001, order-1002, order-1004, order-1005, order-1007
Partition:1  order-1003, order-1006, order-1008, order-10010
Partition:2  order-1009
```

균등하지 않다. 해시 분포는 키가 많아질수록 고르게 수렴하지만, 키 종류가 적거나 특정 키에 트래픽이 몰리면 파티션 간 불균형이 그대로 남는다.

키가 없으면 라운드로빈이 아니라 **sticky** 방식이다. `batch.size`가 찰 때까지 한 파티션에 몰아 보내고 그 다음에 파티션을 바꾼다. 요청 수를 줄여 처리량을 높이려는 설계이고, 관련 설정이 두 개 있다.

| 설정 | 기본값 | 의미 |
| --- | --- | --- |
| `partitioner.ignore.keys` | `false` | `true`면 키가 있어도 무시하고 sticky로 분배 |
| `partitioner.adaptive.partitioning.enable` | `true` | 빠른 브로커의 파티션으로 더 많이 보냄 |

`partitioner.ignore.keys=true`로 두면 **키 기반 순서 보장이 사라진다.** 키를 로그 압축(`cleanup.policy=compact`)의 식별자로만 쓰고 순서는 신경 쓰지 않는 경우에만 쓸 수 있다.

## 반드시 알아야 할 것

---

> 파티션은 늘릴 수만 있고, 늘리는 순간 키→파티션 매핑이 바뀐다. 그리고 컨슈머 병렬성의 상한은 파티션 수다.

### 파티션은 줄일 수 없다

```bash
$ kafka-topics.sh --bootstrap-server localhost:9092 --alter --topic order-events --partitions 2
Error while executing topic command : The topic order-events currently has 3 partition(s);
2 would not be an increase.
ERROR org.apache.kafka.common.errors.InvalidPartitionsException:
  The topic order-events currently has 3 partition(s); 2 would not be an increase.
```

공식 문서도 명시한다.

> "Kafka does not currently support reducing the number of partitions for a topic."

메타데이터만 보면 `PARTITION_RECORD`를 지우면 될 것 같지만, 그 파티션에는 이미 오프셋이 매겨진 데이터와 그 오프셋을 커밋해 둔 컨슈머 그룹이 붙어 있다. 남은 파티션으로 옮기면 오프셋이 충돌하고 순서도 깨진다. 옮기지 않으면 데이터가 사라진다. 어느 쪽도 카프카가 보장하는 성질을 지키지 못한다.

파티션을 줄여야 한다면 **새 토픽을 만들어 데이터를 옮기는 것이 유일한 방법**이다.

### 파티션을 늘리면 키의 순서 보장이 깨진다

파티셔닝 식이 `hash(key) % numPartitions`이므로 `numPartitions`가 바뀌면 결과가 바뀐다.

> "If data is partitioned by `hash(key) % number_of_partitions`, the default partitioner's mapping logic changes when the partition count increases."

파티션을 3 → 5로 늘린 뒤 **같은 키들을 다시 발행**해 봤다.

| 키 | 확장 전 | 확장 후 | |
| --- | --- | --- | --- |
| `order-1001` | 0 | **3** | 이동 |
| `order-1002` | 0 | 0 | 유지 |
| `order-1003` | 1 | **3** | 이동 |
| `order-1004` | 0 | **1** | 이동 |
| `order-1005` | 0 | **4** | 이동 |
| `order-1006` | 1 | **2** | 이동 |
| `order-1007` | 0 | 0 | 유지 |
| `order-1008` | 1 | **3** | 이동 |
| `order-1009` | 2 | **3** | 이동 |

9개 중 7개가 다른 파티션으로 갔다. `order-1001` 키는 확장 전에 쓴 레코드가 파티션 0에, 확장 후에 쓴 레코드가 파티션 3에 남는다.

이 주문의 `OrderCreated`가 확장 전에, `OrderPaid`가 확장 후에 발행됐다면 두 이벤트는 서로 다른 파티션에 흩어진다. **파티션이 다르면 카프카는 두 레코드의 상대 순서를 보장하지 않는다.**

기존 데이터가 재배치되지도 않는다.

```bash
$ kafka-get-offsets.sh --bootstrap-server localhost:9092 --topic order-events --time -2  # earliest
order-events:0:0   order-events:1:0   order-events:2:0   order-events:3:0   order-events:4:0

$ kafka-get-offsets.sh --bootstrap-server localhost:9092 --topic order-events --time -1  # latest
order-events:0:7   order-events:1:5   order-events:2:2   order-events:3:4   order-events:4:1
```

파티션 0~2의 earliest 오프셋이 그대로 0이다. 확장 전에 쌓인 레코드가 새 파티션으로 빠져나간 흔적이 없다는 뜻이다. 파티션 3·4에 들어 있는 4건과 1건은 전부 확장 후에 발행한 레코드다.

메타데이터도 마찬가지다. 기존 `TOPIC_RECORD`는 그대로 두고 `PARTITION_RECORD`만 3, 4번이 추가된다.

여기에 컨슈머 쪽 함정이 하나 더 붙는다.

> "Existing consumers configured with `auto.offset.reset=latest` might miss messages produced to the new partitions."

### 파티션 수가 컨슈머 병렬성의 상한이다

한 컨슈머 그룹 안에서 파티션 하나는 컨슈머 하나에만 할당된다. 파티션 2개짜리 토픽에 컨슈머 3개를 붙이면 하나는 논다.

```bash
$ kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group g1 --members
GROUP  CONSUMER-ID                    CLIENT-ID         #PARTITIONS
g1     console-consumer-f4d135ca-...  console-consumer  0     ← 할당된 파티션 없음
g1     console-consumer-bcf80338-...  console-consumer  1
g1     console-consumer-046d5b8f-...  console-consumer  1
```

컨슈머를 아무리 늘려도 처리량이 오르지 않는 상황은 대개 여기다. 스케일 아웃 여력을 남기려면 파티션 수를 예상 컨슈머 수보다 넉넉히 잡아야 하는데, 그 "넉넉히"에는 아래의 비용이 따라온다.

### retention과 복제는 파티션 단위다

`retention.bytes`는 토픽 전체 크기가 아니다.

> "This configuration controls the maximum size a partition (which consists of log segments) can grow to before we will discard old log segments to free up space."

파티션이 10개면 토픽이 실제로 차지할 수 있는 최대 크기는 `retention.bytes × 10`이고, 복제 팩터 3이면 클러스터 전체로는 `× 30`이다. 파티션을 늘리면 디스크 상한도 같이 늘어난다.

복제도 마찬가지로 파티션 단위다.

> "replication is performed at the level of topic-partitions"

토픽에 leader가 있는 게 아니라 **파티션마다 leader 1개와 follower N개**가 있다. ISR·HW·리더 선출이 전부 파티션 단위로 도는 이유이고, 자세한 동작은 [카프카 파티션 로그의 오프셋들 — LEO, HW, LSO](/posts/kafka-partition-offsets/)에서 다뤘다.

주요 토픽 설정의 기본값은 다음과 같다 (4.3 기준).

| 설정 | 기본값 | 적용 범위 |
| --- | --- | --- |
| `cleanup.policy` | `delete` | 토픽 |
| `retention.ms` | `604800000` (7일) | 파티션 |
| `retention.bytes` | `-1` (무제한) | **파티션** |
| `segment.bytes` | `1073741824` (1GiB) | 파티션 |
| `segment.ms` | `604800000` (7일) | 파티션 |
| `file.delete.delay.ms` | `60000` (60초) | 세그먼트 |
| `min.insync.replicas` | `1` | 파티션 |
| `max.message.bytes` | `1048588` | 레코드 배치 |

## 실무에서 고려할 것

---

> 파티션 수는 한 번 정하면 늘릴 수만 있다. 그래서 "얼마나 잡을 것인가"가 토픽 설계에서 사실상 되돌릴 수 없는 유일한 결정이다.

### 파티션 수 정하기

Confluent가 제시한 기준은 목표 처리량 기반이다. 목표 처리량 `t`, 파티션 하나가 감당하는 프로듀서 처리량 `p`, 컨슈머 처리량 `c`라 할 때 최소 `max(t/p, t/c)` 개가 필요하다.

여기에 실무적인 조건 두 개를 더 얹게 된다.

- **컨슈머 확장 여력**: 지금 컨슈머가 3개라도 앞으로 6개까지 늘릴 계획이면 파티션은 6개 이상
- **키 카디널리티**: 파티션 수가 키 종류보다 많으면 빈 파티션이 생긴다

### 파티션이 많을 때의 비용

파티션은 공짜가 아니다. 대표적인 비용은 다음과 같다.

| 비용 | 내용 |
| --- | --- |
| 파일 핸들 | 파티션마다 세그먼트별로 `.log` / `.index` / `.timeindex` 세 개. 파티션이 많으면 브로커의 open file 수가 수만 단위로 올라간다 |
| 프로듀서 메모리 | 프로듀서는 파티션마다 배치 버퍼를 잡는다. Confluent 기준으로 파티션당 최소 수십 KB |
| 복제 지연 | 파티션 수만큼 복제 fetch가 늘어난다. 1,000개 파티션 복제에 약 20ms 지연이 붙는다는 측정치가 있다 |
| 리더 선출 시간 | 브로커가 죽으면 그 브로커가 리더였던 파티션 전부에 대해 선출이 돈다 |

> 위 수치는 2015년 ZooKeeper 시절 측정 기준이다. KRaft로 넘어오면서 컨트롤러 페일오버 비용 구조가 바뀌었으므로, "브로커당 2~4천 개, 클러스터당 수만 개"라는 당시 권고를 그대로 적용할 수는 없다. Confluent 랩 환경에서 KRaft 클러스터가 200만 파티션까지 검증됐다는 보고가 있지만, 파일 핸들·메모리·복제 비용은 KRaft와 무관하게 그대로 남는다. 실제 상한은 사용하는 버전과 하드웨어에서 직접 측정하는 편이 맞다.

정리하면, **"나중에 늘릴 수 있으니 일단 작게"도 "혹시 모르니 일단 크게"도 좋은 전략이 아니다.** 전자는 순서 보장이 깨지는 마이그레이션을 부르고, 후자는 상시 비용이 된다. 목표 처리량과 컨슈머 확장 계획으로 계산한 값에 약간의 여유만 두는 게 낫다.

### 브로커를 추가해도 파티션은 옮겨가지 않는다

> "these new servers will not automatically be assigned any data partitions, so unless partitions are moved to them they won't be doing any work."

브로커를 늘렸는데 부하가 그대로인 이유가 이것이다. `kafka-reassign-partitions.sh`로 직접 옮겨야 한다.

```bash
# 1. 재배치 계획 생성
kafka-reassign-partitions.sh --bootstrap-server localhost:9092 \
  --topics-to-move-json-file topics.json --broker-list "1,2,3,4" --generate

# 2. 실행
kafka-reassign-partitions.sh --bootstrap-server localhost:9092 \
  --reassignment-json-file plan.json --execute

# 3. 진행 확인
kafka-reassign-partitions.sh --bootstrap-server localhost:9092 \
  --reassignment-json-file plan.json --verify
```

재배치는 파티션 데이터를 네트워크로 통째로 복사하는 작업이다. 운영 중이라면 `--throttle`로 대역폭을 제한하지 않으면 정상 트래픽까지 영향을 받는다.

### 데이터 스큐

키 해시가 균등해도 **키별 트래픽 양이 균등하지는 않다.** 특정 사용자나 특정 상품에 이벤트가 몰리면 그 키가 매핑된 파티션 하나만 커진다. 파티션은 브로커 하나가 담당하므로 그 브로커가 병목이 된다.

증상은 컨슈머 그룹의 파티션별 lag으로 드러난다.

```bash
kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --group my-group
# 특정 PARTITION 행의 LAG만 계속 커진다면 스큐를 의심
```

대응은 키 설계를 바꾸는 쪽이다. 순서 보장이 `orderId` 단위로만 필요한데 키를 `userId`로 잡았다면 `orderId`로 낮추고, 그마저 몰린다면 `userId#0` ~ `userId#N` 같은 salt를 붙여 쪼갠다. 단, salt를 붙이면 원래 키 기준의 순서 보장은 포기하게 된다.

### 내부 토픽은 건드리지 않는다

`__consumer_offsets`, `__transaction_state`, `__share_group_state`, `__cluster_metadata`의 파티션 수는 수동으로 바꾸면 안 된다. 공식 문서가 **never**로 경고한다. 코디네이터가 `hash(group.id) % 파티션 수`로 담당 파티션을 정하기 때문에, 파티션 수가 바뀌면 기존 그룹의 오프셋을 찾지 못한다.

```bash
$ kafka-topics.sh --bootstrap-server localhost:9092 --describe --topic __consumer_offsets
Topic: __consumer_offsets  PartitionCount: 50  ReplicationFactor: 1
  Configs: compression.type=producer, cleanup.policy=compact, segment.bytes=104857600
```

기본 50개이고, 바꾸려면 클러스터 최초 구성 시 `offsets.topic.num.partitions`로 정해야 한다.

### 토픽을 삭제하고 같은 이름으로 다시 만들면 다른 토픽이다

```bash
$ cat .../parallel-demo-0/partition.metadata     # 삭제 전
version: 0
topic_id: zvtYTgbUSOWL8GQLFewUSQ

$ kafka-topics.sh --delete --topic parallel-demo ...
$ kafka-topics.sh --create --topic parallel-demo --partitions 2 ...

$ cat .../parallel-demo-0/partition.metadata     # 재생성 후
version: 0
topic_id: O9tTOuh6TLaWS7nww1ejbg
```

이름은 같아도 `topic_id`가 다르다. 오프셋은 0부터 다시 시작하고, 기존 컨슈머 그룹이 커밋해 둔 오프셋은 새 토픽의 오프셋 범위와 아무 관계가 없다. 삭제 직후 재생성은 브로커 간 메타데이터 전파 타이밍에 따라 클라이언트가 `UNKNOWN_TOPIC_ID`를 만날 수도 있다. 운영 환경에서 토픽을 갈아엎어야 한다면 같은 이름을 재사용하기보다 새 이름을 쓰고 컨슈머를 옮기는 편이 안전하다.

## 정리

---

> 토픽은 이름이고, 실체는 전부 파티션에 있다.

- 디스크에 있는 건 `<토픽명>-<파티션번호>` 디렉터리와 그 안의 세그먼트 파일들이다. 토픽 디렉터리는 존재하지 않는다.
- 토픽은 KRaft 메타데이터의 `TOPIC_RECORD`(이름 + ID)일 뿐이고, 리더·복제본·디스크 위치는 전부 `PARTITION_RECORD`에 달려 있다.
- 순서 보장, 복제, 병렬 처리, retention 크기 제한이 모두 파티션 단위다.
- 파티션은 늘릴 수만 있고, 늘리면 `hash(key) % numPartitions`가 바뀌어 키의 순서 보장이 끊긴다. 기존 데이터는 재배치되지 않는다.
- 컨슈머 병렬성의 상한이 파티션 수이므로, 처리량 목표와 확장 계획을 기준으로 처음에 잘 잡아야 한다.

## 참고 자료

---

- [Apache Kafka — Introduction: Main Concepts and Terminology (kafka.apache.org/43/getting-started)](https://kafka.apache.org/43/getting-started/introduction/) — 토픽·파티션 정의, 파티션 단위 순서 보장, 파티션 단위 복제
- [Apache Kafka — Implementation: Log (kafka.apache.org/43/implementation)](https://kafka.apache.org/43/implementation/log/) — 파티션 디렉터리 명명 규칙, 세그먼트 파일명, 읽기·삭제 동작
- [Apache Kafka — Operations: Basic Kafka Operations (kafka.apache.org/43/operations)](https://kafka.apache.org/43/operations/basic-kafka-operations/) — 파티션 증가 시 주의사항, 파티션 감소 미지원, 브로커 추가 후 재배치, 내부 토픽 경고
- [Apache Kafka — Producer Configs (kafka.apache.org/43/configuration)](https://kafka.apache.org/43/configuration/producer-configs/) — `partitioner.class` 기본 동작, `partitioner.ignore.keys`, `partitioner.adaptive.partitioning.enable`
- [Apache Kafka — Topic Configs (kafka.apache.org/43/configuration)](https://kafka.apache.org/43/configuration/topic-configs/) — `retention.bytes`가 파티션 단위라는 설명, 각 설정 기본값
- [How to Choose the Number of Topics/Partitions in a Kafka Cluster? (confluent.io)](https://www.confluent.io/blog/how-choose-number-topics-partitions-kafka-cluster/) — Jun Rao, 2015. `max(t/p, t/c)` 기준과 파티션 증가 비용 (ZooKeeper 시절 기준)
- [KRaft Overview (docs.confluent.io)](https://docs.confluent.io/platform/current/kafka-metadata/kraft.html) — KRaft에서의 파티션 규모 관련 설명
