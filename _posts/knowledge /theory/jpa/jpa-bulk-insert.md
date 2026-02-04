

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
