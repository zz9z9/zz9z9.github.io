

# JPA Batch Insert/Update 가이드

## 개요

Spring Batch + JPA 환경에서 대량 데이터 처리 시 성능 최적화를 위한 설정과 주의사항을 정리합니다.

## Batch Insert가 동작하려면

3가지 조건이 모두 충족되어야 합니다:

| 조건 | 설정 | 설명 |
|------|------|------|
| Hibernate batch | `hibernate.jdbc.batch_size` | INSERT/UPDATE를 모아서 JDBC batch로 전송 |
| MySQL JDBC | `rewriteBatchedStatements=true` | JDBC batch를 multi-row INSERT로 변환 |
| Entity ID | `@GeneratedValue(IDENTITY)` 미사용 | IDENTITY 전략은 batch insert 불가 |

### 설정 예시
yaml
# application.yml

starter:
jpa:
hibernate:
batch-size: 100
order-inserts: true
order-updates: true
java
// DataSourceConfig.java (HikariCP)
config.addDataSourceProperty("rewriteBatchedStatements", "true");

## order-inserts / order-updates 이해

chunk에 여러 테이블의 엔티티가 섞여있는 경우:

A 테이블 INSERT
B 테이블 INSERT
A 테이블 INSERT

### order-inserts: false (기본값)

테이블이 바뀔 때마다 batch가 끊깁니다:
sql
INSERT INTO A VALUES (...)  -- batch 1
INSERT INTO B VALUES (...)  -- batch 2 (끊김)
INSERT INTO A VALUES (...)  -- batch 3 (끊김)
→ 3번의 DB 라운드트립

### order-inserts: true

같은 테이블끼리 정렬해서 모아줍니다:
sql
INSERT INTO A VALUES (...), (...)  -- A 2건 batch
INSERT INTO B VALUES (...)         -- B 1건
→ 2번의 DB 라운드트립

### 언제 효과가 있나?

- 한 chunk에서 **여러 테이블에 저장**할 때 효과적
- 단일 테이블만 저장하면 효과 없음 (이미 같은 테이블이 연속되므로)

## JpaItemWriter 동작 방식

### persist() vs merge()
java
// JpaItemWriter 기본 동작
for (T item : items) {
if (usePersist) {
entityManager.persist(item);  // 새 엔티티 INSERT
} else {
entityManager.merge(item);    // 기본값: SELECT 후 INSERT/UPDATE
}
}

### merge() 사용 시 문제

assigned ID(직접 할당)를 사용하면 Hibernate가 새 엔티티인지 판단하기 어려워서 **SELECT를 먼저 실행**합니다:
sql
-- merge() 호출 시점 (건별 SELECT)
SELECT * FROM table WHERE id = 'ID001';
SELECT * FROM table WHERE id = 'ID002';
SELECT * FROM table WHERE id = 'ID003';
... (chunk size만큼 반복)

-- flush 시점 (batch 가능)
INSERT INTO table VALUES (...), (...), ...
-- 또는
UPDATE table SET ... WHERE id IN ('ID001', 'ID002', ...)

**결과**: SELECT는 건별, INSERT/UPDATE만 batch

## 해결 방법

### 방법 1: 재실행 전 기존 데이터 삭제

배치 Step 시작 전에 해당 범위 데이터를 삭제하고 INSERT만 수행합니다.
java
@Bean
public Job myJob() {
return jobBuilder
.start(deleteExistingDataStep())   // Step 1: 기존 데이터 삭제
.next(insertDataStep())            // Step 2: INSERT (usePersist=true)
.build();
}

@Bean
public JpaItemWriter<MyEntity> jpaItemWriter() {
return new JpaItemWriterBuilder<MyEntity>()
.entityManagerFactory(emf)
.usePersist(true)  // SELECT 없이 바로 INSERT
.build();
}

**장점**: JPA를 그대로 활용, 단순한 구조
**단점**: 삭제 Step 추가 필요

### 방법 2: JdbcBatchItemWriter + UPSERT

MySQL의 `INSERT ... ON DUPLICATE KEY UPDATE` 사용:
java
@Bean
public JdbcBatchItemWriter<MyEntity> jdbcItemWriter(DataSource dataSource) {
return new JdbcBatchItemWriterBuilder<MyEntity>()
.dataSource(dataSource)
.sql("""
INSERT INTO my_table
(id, column1, column2, register_ymdt, modify_ymdt)
VALUES
(:id, :column1, :column2, :registerYmdt, :modifyYmdt)
ON DUPLICATE KEY UPDATE
column1 = VALUES(column1),
column2 = VALUES(column2),
modify_ymdt = VALUES(modify_ymdt)
""")
.beanMapped()
.build();
}

**장점**: SELECT 없이 한 번에 INSERT 또는 UPDATE
**단점**: Native SQL 사용, JPA 영속성 컨텍스트 미사용

### 방법 3: Persistable 인터페이스 구현

엔티티에서 `isNew()`를 구현해서 항상 새 엔티티로 인식시킵니다:
java
@Entity
public class MyEntity implements Persistable<String> {

    @Id
    private String id;

    @Transient
    private boolean isNew = true;

    @Override
    public String getId() {
        return id;
    }

    @Override
    public boolean isNew() {
        return isNew;
    }

    @PostLoad
    void markNotNew() {
        this.isNew = false;
    }
}

**주의**: 항상 persist() 동작하므로 이미 존재하면 예외 발생. 방법 1과 조합 필요.

## 권장 사항

| 상황 | 권장 방법 |
|------|----------|
| 항상 새 데이터 INSERT | `usePersist(true)` |
| 재실행 시 같은 결과 보장 | 방법 1 (삭제 후 INSERT) |
| INSERT/UPDATE 혼재, 최고 성능 필요 | 방법 2 (UPSERT) |

## 현재 프로젝트 설정
yaml
# settlement-batch/application-local.yml

starter:
jpa:
hibernate:
ddl-auto: validate
batch-size: 100
order-inserts: true
default-batch-fetch-size: 100
java
// DataSourceConfig.java
config.addDataSourceProperty("rewriteBatchedStatements", "true");

## 참고

- [Hibernate Batch Processing](https://docs.jboss.org/hibernate/orm/current/userguide/html_single/Hibernate_User_Guide.html#batch)
- [MySQL Connector/J rewriteBatchedStatements](https://dev.mysql.com/doc/connector-j/8.0/en/connector-j-connp-props-performance-extensions.html)


=============================================================================================

아니면 미리 영속성 컨텍스트에 올려두게 ProjectSettlementDetailProcessor#process 에서 PaymentTransaction의
paymentTransactionNumber에 매핑되는 ProjectSettlementDetail이 있는지 조회하는 로직 추가하는건 어때 ?

● 그 방식도 결국 건별 SELECT가 발생합니다. Processor는 item을 하나씩 처리하기 때문입니다:

// Processor.process()는 item 하나씩 호출됨
for (PaymentTransaction tx : chunk) {
processor.process(tx);  // 여기서 findById() → 건별 SELECT
}

효과를 보려면 chunk 단위로 한 번에 조회해야 합니다:

방법: ChunkListener + IN 절 조회

@StepScope
@Component
public class ProjectSettlementDetailProcessor implements ItemProcessor<...>, ChunkListener {

      private final Map<String, ProjectSettlementDetail> existingDetailsCache = new HashMap<>();
      private final ProjectSettlementDetailRepository detailRepository;

      @Override
      public void beforeChunk(ChunkContext context) {
          // Chunk 시작 전에 현재 chunk의 ID들로 한 번에 조회
          // 문제: 여기서 현재 chunk의 item들을 알 수 없음
      }
}

문제: beforeChunk()에서 현재 chunk에 어떤 item들이 있는지 알 수 없습니다.

  ---
대안: Reader에서 LEFT JOIN으로 함께 조회

// Reader에서 PaymentTransaction + 기존 ProjectSettlementDetail을 함께 조회
queryFactory
.select(Projections.constructor(TransactionWithDetail.class,
paymentTransaction,
projectSettlementDetail))  // LEFT JOIN
.from(paymentTransaction)
.leftJoin(projectSettlementDetail)
.on(paymentTransaction.paymentTransactionNumber.eq(
projectSettlementDetail.paymentTransactionNumber))
.where(...)

→ 이미 존재하는 detail이 있으면 영속성 컨텍스트에 올라감

  ---
결론

복잡도 대비 효과를 고려하면:
1. 단순하게 가려면: 삭제 후 INSERT (방법 1)
2. 성능 최우선: JdbcBatchItemWriter + UPSERT (방법 2)

Processor에서 미리 조회하는 방식은 구현 복잡도가 높아서 권장하지 않습니다.

==========================================================================

```
음 .. 현재 내가 작성한 로직이 jpa 기반이고 어제일자 결제내역 n건 조회 (페이징) -> 가공 -> 정산내역 n건 저장 (chunk-size == batch-size == n) 이런식인데, 처음엔 무조건 insert지만, 재처리시에는 update가 돼서, 무조건 insert로만 처리할 수가 없어.
(db: mysql) 그래서 select, insert 모두 효율적으로 처리하기 떠올려본 방법은

방법 1. 기존 로직 수행 전에 무조건 어제일자 정산 데이터 지우고 시작 (insert만 발생 => usePersist 같은거 사용해서 select 발생하지 않게 만들 수 있음. 하지만 delete 건수 많으면 이것도 DB에 부하이지 않나 ?)
방법 2. writer는 JdbcTemplate이나 MyBatis 또는 QueryDSL 사용해서, DUPLICATED ON KEY 쿼리 사용
```

# Spring Batch · JPA · 대량 처리 전체 Q&A 정리

> 이 문서는 아래 흐름의 **질문–답변 전체 내용을 누락 없이 구조화**한 기록이다.
> 주제는 *Spring Batch 환경에서 JPA / Hibernate / MyBatis / jOOQ를 이용한 대량 저장, 재처리, 성능 설계*이다.

---

## Q1. assigned ID를 쓰면 Hibernate가 SELECT를 먼저 실행하나?

### A.
대체로 맞는 설명이다.

- `@GeneratedValue` 전략에서는 `id == null`이면 Hibernate가 **무조건 새 엔티티**로 판단 → 바로 INSERT
- **assigned ID**(직접 할당 PK)에서는:
  - 이 ID가 DB에 이미 존재하는지 Hibernate가 알 수 없음
  - 따라서 **unsaved 여부 판단을 위해 SELECT가 발생**할 수 있음

이는 Hibernate 내부의 보호 로직이며, 특히 `persist()`나 `merge()` 과정에서 나타난다.

---

## Q2. SimpleJpaRepository.save()에서 SELECT는 어디서 발생하나?

```java
if (entityInformation.isNew(entity)) {
    entityManager.persist(entity);
} else {
    entityManager.merge(entity);
}
```

### A.

- `save()` 메서드 자체에는 SELECT 없음
- `isNew()` 판단 로직에도 SELECT 없음
- **실제 SELECT는 Hibernate가 `persist()` 또는 `merge()`를 수행하는 내부 로직에서 발생**

### isNew() 동작 방식
- `Persistable` 구현 시 → `isNew()` 직접 호출
- 아니면:
  - `@Version` 있으면 `version == null`
  - 없으면 `id == null`

👉 이 판단은 **DB를 보지 않는다**

---

## Q3. Spring Batch에서 assigned ID + save() + batch-size = 쿼리 패턴은?

### 조건
- chunk-size = batch-size = 1000
- 총 100,000건
- assigned ID
- `repository.save()` 사용

### 실제 결과
- **SELECT: 100,000번**
- **INSERT: 100,000건**
- JDBC batch로 INSERT는 묶여서 전송되지만,
  - 논리적으로 INSERT 1번이 아님

👉 병목은 INSERT가 아니라 **엔티티 수만큼 발생하는 SELECT**

---

## Q4. rewriteBatchedStatements=true면 INSERT가 한 번에 처리되는 거 아닌가?

### A.
반은 맞고, 반은 오해.

### 의미
- 여러 INSERT statement를
- **multi-values INSERT 하나로 재작성**
```sql
INSERT INTO t (a,b)
VALUES (?,?), (?,?), (?,?)
```

### 효과
- 네트워크 왕복 감소
- SQL 파싱/최적화 1회
- binlog / replication 효율 증가

### 한계
- **merge()에서 발생하는 SELECT는 줄어들지 않음**
- 엔티티 단위 판단은 여전히 개별 수행

---

## Q5. multi-values INSERT vs 여러 INSERT의 차이는?

### 차이점 요약

| 항목 | 여러 INSERT | multi-values INSERT |
|---|---|---|
| SQL 파싱 | N번 | 1번 |
| 옵티마이저 | N번 | 1번 |
| statement context | N번 | 1번 |
| binlog | 분산 | 묶임 |
| replication | 느림 | 빠름 |

👉 단순 전송량 차이가 아니라 **DB 실행 경로 자체가 다름**

---

## Q6. IDENTITY 전략은 왜 bulk insert가 안 되나?

### A.
구조적인 이유.

- INSERT 직후 DB가 생성한 PK를 즉시 받아야 함 (`getGeneratedKeys()`)
- 따라서:
  - JDBC batch 불가
  - multi-values INSERT 불가

👉 Hibernate 공식적으로도:
> IDENTITY is incompatible with JDBC batching

---

## Q7. 배치에서 IDENTITY vs assigned ID에 대한 관점은?

### A.

- **OLTP**
  - IDENTITY 👍 (안전, 단순)
- **Batch**
  - IDENTITY ❌ (성능 병목)
  - assigned ID + persist 제어 ⭕

👉 배치에서는 **assigned ID가 전제 조건**

---

## Q8. JdbcTemplate 쓰면 SQL 하드코딩 지옥 아닌가?

### A.
그렇지 않다.

### 대안
- NamedParameterJdbcTemplate
- SQL 상수 분리
- SQL 전용 클래스

그리고 실무에서는:

👉 **Writer만 MyBatis 사용하는 패턴이 매우 흔함**

---

## Q9. 재처리 때문에 INSERT만 할 수 없을 때 전략은?

### 상황
- 최초 실행: INSERT
- 재처리: UPDATE 필요
- MySQL 사용

### 제안된 방법

#### 방법 1. DELETE 후 INSERT
- 장점: 로직 단순, SELECT 제거 가능
- 단점:
  - DELETE 비용 큼
  - 중간 실패 시 데이터 공백
  - 동시 조회 리스크

👉 **조건부 전략**

#### 방법 2. UPSERT (추천)

```sql
INSERT INTO table (...)
VALUES (...)
ON DUPLICATE KEY UPDATE ...
```

- SELECT 없음
- INSERT/UPDATE 자동 분기
- DB 내부에서 가장 효율적인 경로

👉 **정산 / 재처리 배치의 기본 전략**

---

## Q10. MyBatis 기반 Writer 예시는?

### 핵심 구성
- Writer 전용 DTO (`SettlementWriteModel`)
- MyBatis Mapper + XML
- multi-values INSERT + ON DUPLICATE KEY UPDATE
- chunk-size == batch-size → SQL 1회

👉 SQL 가시성 + 성능 + 안정성

---

## Q11. 기존 JPA 엔티티를 Writer에 그대로 쓰면 안 되나?

### A.
기술적으로 가능하지만 **기본적으로 반대**.

### 이유
- 영속성 컨텍스트 충돌 가능
- flush 시 예기치 않은 UPDATE
- 업데이트 컬럼 통제 어려움
- 도메인 의미 혼합

### 권장
- Writer 전용 DTO / WriteModel
- Processor에서 변환

👉 변환 비용은 무시 가능, 안정성 비용은 매우 큼

---

## Q12. 엔티티 → WriteModel 변환 비용은 괜찮은가?

### A.
전혀 문제 없음.

- 객체 생성 비용은 DB I/O에 비하면 무시 수준
- 오히려:
  - 의도 명확
  - 디버깅 비용 감소
  - 사고 예방

👉 **보험료에 가까운 비용**

---

## Q13. 그럼 영속성 컨텍스트의 이점은 뭔가?

### 핵심 가치
- 1차 캐시
- 변경 감지 (Dirty Checking)
- 동일성 보장
- 도메인 중심 사고

### 어디에 적합한가?
- **OLTP**
- 요청 단위 처리
- 복잡한 도메인 모델

### 배치에서는?
- 대량 처리엔 오버헤드
- SQL 제어 어려움
- upsert/재처리에 부적합

👉 **JPA는 읽기와 도메인에, 배치는 SQL 중심**

---

## Q14. jOOQ는 어디에 위치하나?

### A.
- ORM 아님
- 영속성 컨텍스트 없음
- 타입 안전한 SQL DSL

### 배치 Writer 기준
- MyBatis와 같은 계열
- 동적 SQL / 타입 안전 필요하면 jOOQ
- 정적 대량 INSERT면 MyBatis가 더 단순

👉 **JPA의 대안이 아니라, JPA가 불편해지는 지점을 메우는 도구**

---

## 최종 결론

> 배치는 ORM의 영역이 아니라 데이터 파이프라인이다.
> JPA는 읽기와 도메인에, 쓰기는 SQL(MyBatis/jOOQ)에게 맡기는 것이
> 성능·안정성·운영 측면에서 가장 균형 잡힌 선택이다.

========


해결 방법
방법 1: Persistable 인터페이스 구현 (권장)
// org.springframework.data.domain.Persistable
@Entity
public class MyEntity implements Persistable<String> {

    @Id
    private String id;

    @Transient
    private boolean isNew = true;

    @Override
    public String getId() {
        return id;
    }

    @Override
    public boolean isNew() {
        return isNew;
    }

    @PostLoad
    @PostPersist
    void markNotNew() {
        this.isNew = false;
    }
}

우회 원리:
// org.hibernate.event.internal.EntityState
public static EntityState getEntityState(...) {
if (entity instanceof Persistable) {
Persistable<?> persistable = (Persistable<?>) entity;
if (persistable.isNew()) {
return TRANSIENT;  // ✅ entityIsDetached() 우회!
}
}
// ...
}

isNew() = true → TRANSIENT → entityIsTransient() → SELECT 없이 바로 INSERT

방법 2: persist() 직접 사용
@Bean
public ItemWriter<MyEntity> itemWriter(EntityManagerFactory emf) {
return items -> {
EntityManager em = emf.createEntityManager();
EntityTransaction tx = em.getTransaction();
tx.begin();

        for (MyEntity item : items) {
            em.persist(item);  // merge() 대신 persist()
        }

        em.flush();
        em.clear();
        tx.commit();
        em.close();
    };
}


방법 3: JdbcBatchItemWriter 사용
Bulk INSERT 성능이 가장 중요하다면:
@Bean
public JdbcBatchItemWriter<MyEntity> writer(DataSource dataSource) {
return new JdbcBatchItemWriterBuilder<MyEntity>()
.dataSource(dataSource)
.sql("INSERT INTO my_table (id, col1, col2) VALUES (:id, :col1, :col2)")
.beanMapped()
.build();
}


참고
Hibernate 버전: 6.x 기준
Spring Data JPA 사용 시 Persistable 인터페이스가 가장 깔끔한 해결책
Batch 처리 시에는 JdbcBatchItemWriter 고려

=====================================

● 설정은 전부 맞습니다. bulk insert는 실제로 동작하고 있을 가능성이 높고, p6spy 로그가 보여주는 것이 실제 DB에 도달하는 쿼리가 아닌 것이 원인입니다.

로그에 단건으로 보이는 이유

p6spy와 Hibernate SQL 로그 모두 MySQL JDBC 드라이버보다 상위 레이어에서 찍힙니다.

Hibernate persist(item1), persist(item2), ... persist(item100)
│
▼  flush()
Hibernate ActionQueue: INSERT 100건을 JDBC batch로 묶음
│
▼  addBatch() × 100  ← p6spy는 여기서 개별 로그를 찍음
P6SpyPreparedStatement (로깅 레이어)
│
▼  executeBatch()
HikariCP → MySQL PreparedStatement
│
▼  rewriteBatchedStatements=true  ← 여기서 multi-row INSERT로 재작성
MySQL JDBC Driver
│
▼  INSERT INTO ... VALUES (...), (...), (...), ...  ← 실제 DB에 도달하는 쿼리
MySQL Server

p6spy는 addBatch() 호출 시점에 개별 SQL을 로깅하기 때문에 단건으로 보입니다. 실제 multi-row INSERT 재작성은 그 아래 MySQL 드라이버 내부에서 일어나므로 p6spy가 볼 수
없습니다.

설정 검증 (전부 OK)
┌───────────────────────────┬─────────────────────────┬──────────────────────────────────────────┐
│           설정            │           값            │                   역할                   │
├───────────────────────────┼─────────────────────────┼──────────────────────────────────────────┤
│ hibernate.jdbc.batch_size │ 100                     │ Hibernate가 JDBC batch 사용              │
├───────────────────────────┼─────────────────────────┼──────────────────────────────────────────┤
│ hibernate.order_inserts   │ true                    │ 같은 테이블 INSERT를 모아서 batch        │
├───────────────────────────┼─────────────────────────┼──────────────────────────────────────────┤
│ rewriteBatchedStatements  │ true                    │ MySQL 드라이버가 multi-row INSERT로 변환 │
├───────────────────────────┼─────────────────────────┼──────────────────────────────────────────┤
│ usePersist(true)          │ true                    │ merge() 대신 persist() → SELECT 안 함    │
├───────────────────────────┼─────────────────────────┼──────────────────────────────────────────┤
│ ID 전략                   │ assigned (not IDENTITY) │ IDENTITY면 batch 불가, assigned는 가능   │
└───────────────────────────┴─────────────────────────┴──────────────────────────────────────────┘
실제로 batching 되고 있는지 확인하는 방법

application-local.yml에 statistics를 켜면 됩니다.

nbaas:
starter:
jpa:
hibernate:
generate-statistics: true

flush 후 로그에 이런 식으로 찍힙니다:

xxx nanoseconds spent executing 1 JDBC batches

1 JDBC batches로 100건이 처리되었다면 batching이 정상 동작하는 것입니다. 개별 execute가 100번 호출됐다면 100 JDBC statements로 찍힙니다.

요약

p6spy/Hibernate SQL 로그로는 multi-row INSERT를 확인할 수 없습니다. 이 두 로거 모두 MySQL 드라이버의 rewriteBatchedStatements 재작성보다 상위에서 동작하기 때문입니다. 실제
DB에는 multi-row INSERT가 날아가고 있을 가능성이 높고, generate-statistics: true로 확인할 수 있습니다.

===================

● batching 정상 동작하고 있습니다.

355966500 nanoseconds spent executing 8 JDBC statements;   ← SELECT 등 개별 쿼리 8건
96888300 nanoseconds spent executing 1 JDBC batches;       ← INSERT 11건이 1번의 batch로 실행됨
220395600 nanoseconds spent executing 1 flushes (flushing a total of 56 entities and 0 collections);

- 1 JDBC batches — 11건의 INSERT가 하나의 executeBatch() 호출로 처리됨
- 8 JDBC statements — Processor의 SELECT(수수료 정책, 계약조건 조회 등) + Spring Batch 메타데이터 UPDATE
- rewriteBatchedStatements=true에 의해 MySQL 드라이버 내부에서 multi-row INSERT로 변환되어 DB에 도달

p6spy/Hibernate SQL 로그에서 단건으로 보이는 건 로깅 레이어의 한계일 뿐, 실제 DB에는 bulk insert가 정상적으로
날아가고 있습니다.

2026-02-05T18:02:51.849+09:00  INFO 19184 --- [settlement-batch] [           main] i.StatisticalLoggingSessionEventListener : Session Metrics {
17400 nanoseconds spent acquiring 1 JDBC connections;
0 nanoseconds spent releasing 0 JDBC connections;
307297400 nanoseconds spent preparing 9 JDBC statements;
355966500 nanoseconds spent executing 8 JDBC statements;
96888300 nanoseconds spent executing 1 JDBC batches;
0 nanoseconds spent performing 0 L2C puts;
0 nanoseconds spent performing 0 L2C hits;
0 nanoseconds spent performing 0 L2C misses;
220395600 nanoseconds spent executing 1 flushes (flushing a total of 56 entities and 0 collections);
11050900 nanoseconds spent executing 6 pre-partial-flushes;
12378100 nanoseconds spent executing 6 partial-flushes (flushing a total of 78 entities and 78 collections)
}

====================

2026-02-05T18:09:50.782+09:00  INFO 25304 --- [settlement-batch] [           main] i.StatisticalLoggingSessionEventListener : Session Metrics {
20000 nanoseconds spent acquiring 1 JDBC connections;
0 nanoseconds spent releasing 0 JDBC connections;
1155685000 nanoseconds spent preparing 20 JDBC statements;
3223974300 nanoseconds spent executing 19 JDBC statements;
282356300 nanoseconds spent executing 1 JDBC batches;
0 nanoseconds spent performing 0 L2C puts;
0 nanoseconds spent performing 0 L2C hits;
0 nanoseconds spent performing 0 L2C misses;
461973800 nanoseconds spent executing 1 flushes (flushing a total of 56 entities and 0 collections);
7092500 nanoseconds spent executing 6 pre-partial-flushes;
8986900 nanoseconds spent executing 6 partial-flushes (flushing a total of 78 entities and 78 collections)
}
=> merge 사용

=====================


엇 근데         config.addDataSourceProperty("rewriteBatchedStatements", "false"); 이렇게 했는데도 496446800
nanoseconds spent executing 1 JDBC batches; 이렇게 나오는데 ?

● 다른 겁니다. 두 개는 레이어가 다릅니다.

Hibernate (hibernate.jdbc.batch_size=100)
→ addBatch() × 11, executeBatch() × 1     ← 통계의 "1 JDBC batches"는 여기
│
▼
MySQL JDBC Driver (rewriteBatchedStatements)
├─ true  → INSERT INTO ... VALUES (...), (...), (...)   ← 패킷 1개
└─ false → INSERT INTO ... VALUES (...)                 ← 패킷 11개
INSERT INTO ... VALUES (...)
INSERT INTO ... VALUES (...)
...
┌─────────────────────┬───────────────────────────────┬────────────────────────────────┐
│                     │ rewriteBatchedStatements=true │ rewriteBatchedStatements=false │
├─────────────────────┼───────────────────────────────┼────────────────────────────────┤
│ Hibernate 통계       │ 1 JDBC batches                │ 1 JDBC batches                 │
├─────────────────────┼───────────────────────────────┼────────────────────────────────┤
│ executeBatch() 호출  │ 1번                            │ 1번                            │
├─────────────────────┼───────────────────────────────┼────────────────────────────────┤
│ MySQL에 실제 전송      │ multi-row INSERT 1개          │ 개별 INSERT 11개                 │
└─────────────────────┴───────────────────────────────┴────────────────────────────────┘
1 JDBC batches는 Hibernate가 executeBatch()를 1번 호출했다는 뜻이지, MySQL에 쿼리가 몇 개 날아갔는지가 아닙니다.

rewriteBatchedStatements는 그 executeBatch() 안에서 MySQL 드라이버가 네트워크로 보내는 방식을 바꾸는 것입니다. false
11건을 개별 패킷으로 보내고, true면 1개의 multi-row INSERT로 합쳐서 보냅니다.

================

2026-02-05T18:19:43.200+09:00  INFO 24224 --- [settlement-batch] [           main] i.StatisticalLoggingSessionEventListener : Session Metrics {
12400 nanoseconds spent acquiring 1 JDBC connections;
0 nanoseconds spent releasing 0 JDBC connections;
337008600 nanoseconds spent preparing 30 JDBC statements;
1303123600 nanoseconds spent executing 30 JDBC statements;
0 nanoseconds spent executing 0 JDBC batches;
0 nanoseconds spent performing 0 L2C puts;
0 nanoseconds spent performing 0 L2C hits;
0 nanoseconds spent performing 0 L2C misses;
601443700 nanoseconds spent executing 1 flushes (flushing a total of 56 entities and 0 collections);
9935900 nanoseconds spent executing 6 pre-partial-flushes;
13261900 nanoseconds spent executing 6 partial-flushes (flushing a total of 78 entities and 78 collections)
}

=> batch-size 0

❯ batch-size 0으로하면 ?

● 그러면 JDBC batching이 꺼집니다.

0 nanoseconds spent executing 0 JDBC batches;    ← batch 없음
xxx nanoseconds spent executing 19 JDBC statements;  ← INSERT 11건이 개별 execute()로 실행

batch_size=0이면 Hibernate가 addBatch() + executeBatch()를 안 쓰고, 건건이 execute()를 호출합니다.
rewriteBatchedStatements=true여도 batch 자체가 없으니 rewrite할 게 없습니다.
