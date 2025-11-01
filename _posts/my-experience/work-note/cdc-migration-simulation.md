---
title: Cubrid에서 MySQL로의 여정(번외) - CDC 활용 상상
date: 2025-11-01 22:00:00 +0900
categories: [경험하기, 작업 노트]
tags: [MySQL]
---


> DBMS 마이그레이션 때 CDC를 활용할 수 있었다면 ?

## 기존 방식의 한계점
---

- 실제 작업은 서비스를 Read Only DB에 붙여서 Cubrid(Target DB)에서의 변경을 막고 데이터 마이그레이션을 진행했다.
- 따라서, 마이그레이션 동안 조회를 제외한 요청은 실패처리됐다.
- 마이그레이션은 약 20분 정도 소요됐다.
- 하지만, 서비스 다운타임이 이 정도까지 허용되지 않는 서비스들의 경우 이런 방식으로 처리할 수는 없다.

## CDC (Change Data Capture) 적용해보기
---
> Cubrid는 지원되는 Source Connector가 없어서 CDC를 적용하기가 어렵기 때문에, Source DB도 MySQL이라고 가정했을때

- 상상해보기

![img.png](db-mig-cdc-simulation2.png)

```
1. 데이터 마이그레이션

(마이그레이션 되는 동안 발생한 DML 이벤트가 Kafka 큐(?)에 쌓임)

2. 마이그레이션 완료

3. 쌓인 DML 이벤트 처리

4. 이벤트 처리 거의다 됐을때 더이상 DML 이벤트 발생하지 않도록 서비스 점검

(서비스 중단)

5. 모든 이벤트 처리 완료됐으면 Target DB를 서비스 DB로 변경

(서비스 재개)
```

## 고민해볼 부분들
---

### 데이터 마이그레이션 방식
> debezium connector initial snapshot vs ETL 도구(PDI, DataX, etc)기반 로딩

**debezium connector initial snapshot**
- 장점
  - 현재 상태의 데이터 마이그레이션 + 마이그레이션되는 동안 발생한 변경을 자연스럽게 이어줌 (스냅샷 완료 이후 변경 이벤트 스트리밍)
  - 스키마 변경(DDL)까지 이벤트로 전달 가능 => 이게 왜 장점일까 ?

- 단점
  - 글로벌 읽기 잠금시 테이블 락이 발생
  - 테이블 크기가 클수록 수 시간 이상 걸릴 수 있음 => 카프카에 변경 이벤트 많이 쌓인다
  - `SELECT * FROM <table>` => 운영 DB에 부하
  - Repeatable Read 오래 잡고있는다 ? => I/O 부담 큼 ??
  - 특정 조건 필터링 불가 (예: “3개월치 데이터만” 같은 조건부 snapshot 불가능, 이력 테이블의 경우 전날 자정까지 쌓인건 이미 완료되어있음, 손해임)

**ETL 도구**
> PDI (Pentaho Data Integration) / ETL 기반 로딩

- 장점
  - 성능 및 유연성
    - 병렬로 테이블 단위/파티션 단위 로딩 가능.
    - DB → File → DB 등 다양한 중간단계(batch 기반) 처리 가능.
  - DB 부담 조절 가능
    - 대용량 테이블을 시간대별/조건별로 쪼개서 로딩 가능.
  - 데이터 전처리/검증 용이
    - 타입 변환, Null 보정, 컬럼 매핑 등 snapshot 전에 한 번에 처리 가능.

- 단점
  - 마이그레이션 시점 이후의 이벤트가 정확히 어디서부터인지 파악이 어렵다.
    - 즉, Debezium을 언제부터 binlog를 tailing 시킬지(즉, 시작 offset을 어디로 잡을지) 명확히 해야 함.

**내 생각**
> ETL 도구 + CDC 방식 사용이 더 좋은 것 같다.<br>
> initial snapshot의 단점이 데이터가 적지 않은 우리의 운영 환경에는 꽤 치명적으로 작용할 것 같다. (특히 DB에)


**해결해야할 과제**
> 마이그레이션 완료 이후 마이그레이션 동안 발생한 변경 이벤트를 싱크할때 데이터 정합성 깨지지 않게 하려면 ?

- ETL 도구를 이용해서 마이그레이션 시작하는 시점의 binlog 위치를 정확히 아는 것은 불가능하다고 생각 (초기 스냅샷처럼 테이블 잠금하고 binlog 위치를 얻어오는게 아니기 때문에)
- 따라서, 마이그레이션 시작보다 조금 앞선 시점에 CDC로 변경 이벤트 수집
- 마이그레이션 이후 이벤트 스트리밍 할 때, **스냅샷 데이터에 이미 반영된 변경 이벤트는 처리되지 않도록 또는 정합성에 영향 없도록 하려면 ??**


### Consumer 선택
- Sink Connector vs Spring boot application

### 마이그레이션 끝난 테이블은 계속 이벤트 쌓지않고, 큐에서 소진되게 할 수 있을까 ?? (kafka 리소스 계속 잡아먹게되니까)

### 서비스 한번도 안멈추고 할 수 있는 방법 ??

### 이벤트가 너무 많이 쌓인 경우 ?? => mysql 부하 ??

### DML 이벤트 순서 보장 ?? => 꼬인다면 ??
- 네트워크 단에서 2가 1보다 먼저 도착할수도 있는거아니야 ?

### 이벤트 유실될때 ??

### 토픽 / 파티션 구성 ..
- 기본적으로 debezium source connector에서 토픽은 topic.prefix와 테이블명을 기반으로 자동생성함
- Kafka에서 자동생성 허용해줘야됨
- 근데 보통 운영에서 자동생성 안하긴 하는 것 같던데

### 각 컴포넌트 장애 상황
- connector, kafka, consumer, target db, binlog 지워지면 ? 등

### 마이그레이션 동안 쌓인 DML 이벤트가 많은 경우 이슈 ?
snapshot이 완료될 때까지 binlog를 읽긴 하지만
아직 Kafka로 “적용(commit)”하지 않습니다.

즉, binlog 이벤트는 커넥터 내부의 큐(메모리 버퍼)에 잠시 쌓이거나,
Kafka 전송이 snapshot 이후에 몰려 발생합니다.

따라서 snapshot이 수시간 걸린다면,
→ 그동안 발생한 DML 이벤트가 수백만 건 이상 backlog로 쌓일 수 있습니다.

🧨 2️⃣ 주요 문제점
(1) Kafka 브로커 디스크 압박

snapshot 완료 후 한꺼번에 DML 이벤트가 flush되면
특정 partition에 단기간 massive write가 발생합니다.

만약 topic retention이 짧거나 segment size 설정이 작으면,
disk IO burst + log segment churn이 일어납니다.

(2) Consumer Lag 폭증

Downstream (예: SinkConnector, Stream Processor)이
snapshot 종료 후 갑자기 대량 이벤트를 처리해야 하므로
consumer lag이 수십~수백만 건으로 튀어오름.

이 시점에 TPS가 평소보다 10배 이상으로 증가할 수 있습니다.

(3) 메모리/GC 부하 (Connector 내부)

snapshot 동안 buffer된 이벤트가 많으면
커넥터 JVM heap이 급격히 증가, GC pause 유발 가능.

특히 snapshot.fetch.size 또는 max.batch.size 기본값이 클 때 심각해짐.

(4) 데이터 순서 역전 가능성

snapshot 완료 직전까지 DML이 지속적으로 발생하면,
snapshot의 특정 row보다 더 “오래된” 변경 이벤트가 나중에 들어올 수 있음.
→ Downstream에서 merge logic이 필요할 수도 있음.

## 공부
---

### `SELECT * FROM <table>` => 운영 DB에 부하
- Repeatable Read 오래 잡고있는다 ? => I/O 부담 큼 ??
어떤 부하 , 부담 ?

### PDI ?
PDI (Pentaho Data Integration)는 데이터 마이그레이션이나 ETL(Extract, Transform, Load) 작업을 자동화하기 위한 대표적인 오픈소스 도구입니다.
보통 “Pentaho”라고 하면 BI(비즈니스 인텔리전스) 전체 플랫폼을 말하고,
그 중 데이터 처리 파이프라인 부분만 따로 떼어낸 게 PDI입니다.

간단히 말하면 👇

“SQL이나 스크립트로 데이터 옮기던 걸 시각적으로 설계해서, 병렬로 빠르고 안정적으로 수행하게 해주는 툴”

| 구성 요소              | 역할                                                           | 비유             |
| ------------------ | ------------------------------------------------------------ | -------------- |
| **Transformation** | 데이터를 추출(Extract), 변환(Transform), 적재(Load)하는 **단일 데이터 흐름 단위** | “SQL 쿼리 한 덩어리” |
| **Job**            | 여러 Transformation을 순차/병렬로 실행하는 **워크플로우 단위**                  | “배치 스크립트”      |

Transformation: MySQL → CSV로 export, 데이터 정제

Job: “1. export → 2. 파일 전송 → 3. 완료 로그 기록”

| 기능                             | 설명                                                                              |
| ------------------------------ | ------------------------------------------------------------------------------- |
| **Extract (데이터 추출)**           | MySQL, Oracle, PostgreSQL, Cubrid, CSV, Excel, JSON, REST API 등 거의 모든 데이터 소스 지원 |
| **Transform (변환)**             | 필드 매핑, 형변환, Null 처리, 조건 분기, 조인, 집계, 필터링 등 GUI 기반 데이터 변환                         |
| **Load (적재)**                  | RDBMS, 파일, Kafka, MongoDB, Elastic 등 다양한 타겟으로 로딩 가능                             |
| **병렬 처리 (Parallel Execution)** | 테이블/파티션 단위로 병렬 Extract/Load 가능                                                  |
| **에러 처리 / 로깅**                 | step별 실패 처리, 재시도, 오류 로그 파일 기록 기능 내장                                             |
| **스케줄링 / 자동화**                 | cron, Carte server, Kitchen(PDI CLI) 등으로 자동 실행 가능                               |


- 대체 도구 비교

| 도구                      | 특징                    | 비고              |
| ----------------------- | --------------------- | --------------- |
| **PDI (Pentaho)**       | 안정적, GUI 기반, 범용       | 오픈소스, 상용 지원도 있음 |
| **Apache Nifi**         | 스트리밍 ETL, 실시간 파이프라인   | CDC에 더 가까움      |
| **Airbyte / Singer.io** | 모던 ETL 프레임워크, YAML 기반 | CDC/Batch 겸용    |
| **AWS DMS**             | 클라우드 기반 마이그레이션 전문     | 자동화 쉬움, 유료      |
| **DataX (Alibaba)**     | 초대용량 데이터 병렬 복사에 특화    | 국내에서도 종종 사용됨    |
