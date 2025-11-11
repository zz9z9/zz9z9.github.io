
## 우선순위
---

### 내부 협의
- 기술 스택 선정 & 프로젝트 모듈 & github repository 구성
- 패키지 구조 정의
- 도메인 / 테이블 설계
  - 나름의 컨벤션 정하면 좋을듯 (BigDecimal 등등)
- 역할 분담
- 1차 스펙 개발 범위 확정 및 일정 픽스

### 개인 공부
- JPA
- DDD
- AWS 관련
  - ECR, VPC, Zone, Consul, Route53, ALB, ELK, MKS, Waf, Secret Manager
- Github actions 파이프라인
- GitSubmodule
- Docker
- 스프링 배치 운영 (with 젠킨스 ? 딴것도 괜찮은거 있나?)
- 실습
  - 멀티모듈 프로젝트 세팅
  - 도커, AWS 배포
  - AWS 상품들
  - Spring Batch & JPA

### 플젝 구성 ?
```
[console-repository]

nb-settlement-master-console
├── nbass-settlement-master-console-api
└── nbass-settlement-master-console-front

nb-settlement-partner-console
├── nbass-settlement-partner-console-api
└── nbass-settlement-partner-console-front
```

```
[data-loader-repository]
nb-payment-data-loader
```

```
[batch-repository]
nb-settlement-batch
```

```
nb-settlement
├── web-console
│   ├── admin-console
│   │    ├── admin-console-front
│   │    └── admin-console-api
│   └── client-console
│        ├── client-console-front
│        └── client-console-api
├── domain ??
├── batch
├── data-loader (더 적절한 이름 없을까?)
└── external (외부 연동 ?)
```

### 패키지 구성
- 필요한거
  - 도메인을 나타내는 클래스
  - @Service
  - @Controller
  - 요청 받고 / 응답 주는 클래스
  - 유틸
  - 외부 컴포넌트(Kafka, DB 등) 접근

- 도메인 로직을 처리한다 ?? => @Service vs 도메인 객체 생각해보기

========

- jpa
=> 느낌, 실무할때 신경써야할 것 같은 부분, 고민해야하는 부분, 연관관계 / 내부구현 => jh 형님이 적어놨던거 참고 (연관관계 다 맺었을때 ,,)
=> mybatis 실무에서 쓸때 하는 방식 jpa에서는 어떻게 ??
  - 어떤 컬럼이 어떤 쿼리에서 변경되는지
  - 특정 테이블에 insert 하는 로직이 어떤건지 (insert into table 찾고 해당 dao 호출하는거 `ctrl+h`로 찾아보는거)

- 테이블 설계

- 모듈, 프로젝트 시작하는 법 / 실행하는 법 / 생산성 도구 (devtools 등)
- git
- 코드 컨벤션, 배포, 태깅 등
- jdk 버전 / 밴더사 비교


## 결제 데이터를 어떻게 가져올까
---

### 1. source에서 관련 이벤트 발행
- 이벤트 유실 등이 없도록 결제측에서 반드시 보장해줘야한다.
  - 유실 됐을때 DB와 하나의 트랜잭션 묶이도록 처리해줘야한다 ?
- 관련 로직마다 이벤트 발행하는 부분을 누락하지 않아야한다.

### 2. CDC로 가져온다
- MySQL binlog type이 `ROW`여야한다.
- Aurora는 MySQL 호환이지만, 기본적으로 binlog를 비활성화하고 자체 로그 시스템을 사용합니다.

| 항목                    | MySQL             | Aurora MySQL             |
| --------------------- | ----------------- | ------------------------ |
| binlog                | 기본 활성화            | ❌ 기본 비활성화                |
| binlog 설정             | `log_bin=ON`      | 파라미터 그룹에서 수동 활성화 필요      |
| GTID                  | 지원                | Aurora MySQL 5.7 이상에서 지원 |
| replication log       | InnoDB → binlog   | Aurora Storage Log       |
| Debezium / Maxwell 사용 | 가능 (binlog ON 필수) | ⚠️ 가능하지만 binlog 설정 필요    |

**Aurora MySQL은 왜 기본적으로 binlog가 off인거고 on했을때 안좋을만한게 있나 ?**
- “Aurora MySQL의 아키텍처가 MySQL과 근본적으로 다르기 때문”**입니다.
- Aurora는 MySQL의 binlog가 필요 없도록 설계된 DB라서, binlog를 켜면 “중복 로그 기록” + “추가 I/O 부하”가 발생할 수 있음
- 일반 MySQL에서는 다음과 같은 구조로 변경이 반영됨

```
SQL → InnoDB Buffer Pool → redo log → binlog → disk
```

- Aurora는 스토리지 엔진을 AWS가 새로 만든 구조라서  “redo log + binlog”를 로컬 디스크에 남기지 않고, 6개의 복제본으로 분산된 Aurora Storage에 직접 기록

```
SQL → Aurora Storage (6-way replication)
```

- Aurora Storage Log를 직접 이용해서 CDC를 구현할 수는 없습니다. AWS 내부 전용 형식으로 설계되어 있고, 외부에서 접근하거나 파싱하는 API가 없습니다.
- 하지만 AWS가 Aurora Storage Log를 이용해서 내부적으로 CDC를 수행하는 서비스(`Aurora DML Streaming`, `DMS Aurora Integration`)를 제공합니다.
이게 사실상 “storage log 기반 CDC”의 유일한 합법적 접근 경로입니다.

http://docs.aws.amazon.com/ko_kr/AmazonRDS/latest/AuroraUserGuide/DBActivityStreams.html
=> Aurora DB Activity Stream

![img_8.png](img_8.png)

Aurora CDC 관련
=> https://rastalion.dev/aurora-for-mysql%EC%97%90%EC%84%9C-cdc%EB%A5%BC-%EC%A4%80%EB%B9%84%ED%95%98%EB%8A%94-%EA%B3%BC%EC%A0%95/
=> https://aws.amazon.com/ko/blogs/tech/cdc-data-pipeline-from-db-to-opensearch-service/
   => [AWS DMS](https://aws.amazon.com/ko/dms/), binlog 켠다

=> https://velog.io/@okarinas/aws-aurora-mysql-cdc-dms-%EC%9E%A5%EC%95%A0-%EB%8C%80%EC%9D%91%EA%B8%B0
  => binlog CDC 이슈

Aurora DB Activity Stream
AWS DMS
Kinesis Data stream

### 3. 배치로 가져오기
- 첨엔 배치로 하고 후에 고도화 ??

### 4. Spring Cloud Data Flow (SCDF)

| 역할                    | 예시                                              |
| --------------------- | ----------------------------------------------- |
| **Source**            | Kinesis / Kafka / RabbitMQ / HTTP 등에서 이벤트 수신    |
| **Processor**         | JSON 파싱, 필터링, 변환, 집계, enrichment                |
| **Sink**              | Kafka, Database, REST API, Elasticsearch 등으로 전달 |
| **Orchestrator**      | Stream을 정의하고, 배포/확장/모니터링/롤백 관리                  |
| **Scheduler (Batch)** | ETL job (e.g. PDI, Spring Batch) 스케줄링 가능        |

| 항목                   | 설명                                           |
| -------------------- | -------------------------------------------- |
| **SCDF는 CDC 도구가 아님** | DB 변경 감지를 하지 않음                              |
| **CDC 데이터 처리에 적합함**  | CDC 이벤트를 수집·필터링·가공·저장하는 파이프라인을 구성할 수 있음      |
| **CDC 도구와 함께 사용**    | 예: Debezium → Kafka → SCDF Processor → Sink  |
| **Spring 생태계 통합**    | Spring Cloud Stream, Spring Batch와 자연스럽게 연동됨 |

```
┌──────────────────────────────┐
│          MySQL DB            │
│  (row-based binlog enabled)  │
└──────────────┬───────────────┘
│
▼
┌──────────────────────────────┐
│      Debezium MySQL Connector│
│   (Kafka Connect Source Task)│
└──────────────┬───────────────┘
│
▼
┌────────────┐
│   Kafka    │
│   (CDC 토픽) │
└────────────┘
│
▼
┌──────────────────────────────┐
│   Spring Cloud Data Flow     │
│  (Stream Orchestration Layer)│
│ ┌──────────────────────────┐ │
│ │ kafka-source | processor | │
│ │     | sink(Kafka/App/DB)│ │
│ └──────────────────────────┘ │
└──────────────┬───────────────┘
│
▼
┌──────────────────────────────┐
│   Spring Boot Consumer App   │
│ (도메인 로직 반영 / Elastic / Redis 등) │
└──────────────────────────────┘

```

Spring Cloud Data Flow (Orchestration Layer)

SCDF는 Debezium이 발행한 CDC 이벤트를
다양한 방식으로 가공·분기·전달하는 역할을 함.

💡 예시 Stream 정의
dataflow:> stream create cdc-pipeline \
--definition "kafka --topic=shop.user \
| filter --expression=#jsonPath(payload,'$.op')=='u' \
| transform --expression=#jsonPath(payload,'$.after') \
| kafka --topic=shop.user.updates" \
--deploy

| 단계                    | 설명                              |
| --------------------- | ------------------------------- |
| `kafka source`        | Debezium CDC 토픽(`shop.user`) 구독 |
| `filter processor`    | `op='u'` (update 이벤트만 필터링)      |
| `transform processor` | `after` 필드만 추출                  |
| `kafka sink`          | `shop.user.updates` 토픽으로 발행     |



## 기술 선택
---
- Front : SPA vs MVC
- Web Framework : Spring Boot
- Batch Framework : Spring Batch (with Jenkins)
- Persistence Framework : MyBatis vs JPA vs Jooq ?? 등
- Build Tool : Maven vs Gradle

- Monitoring
- Logging
- APM

- 기술 숙련도
- 프로젝트 일정

인증/인가는 ??

기술 선택 (어떤걸 고려해서 선택해야할까) 및 PoC 해봐야할부분

## 모니터링
---

- CPU, 메모리, 디스크
- 슬로우 쿼리 ??

