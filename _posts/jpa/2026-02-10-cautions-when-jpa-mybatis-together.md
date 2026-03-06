---
title: JPA / MyBatis 혼용시 주의사항 (in 배치 애플리케이션)
date: 2026-02-10 22:00:00 +0900
categories: [JPA]
tags: [JPA, Hibernate]
---

> JPA와 MyBatis는 서로의 존재를 모른다. <br>
> MyBatis는 JDBC를 직접 사용하므로 **JPA 영속성 컨텍스트를 우회하여 DB를 변경하고, JPA는 이를 감지할 수 없다.** <br>
> 결과적으로 JPA 1차 캐시에는 변경 전 데이터(stale data)가 남게 되어 **데이터 불일치**가 발생한다.

## 문제 상황 예시

---

### 1. 같은 엔티티를 JPA로 읽고 MyBatis로 UPDATE

```java
@Bean
public Step problematicStep() {
    return stepBuilder("step")
        .<BatchTarget, BatchTarget>chunk(100, transactionManager)
        .reader(jpaReader())           // JPA로 읽음 → 영속성 컨텍스트에 캐시
        .processor(processor())
        .writer(myBatisWriter())       // MyBatis로 UPDATE → DB만 변경
        .listener(new StepExecutionListener() {
            @Override
            public ExitStatus afterStep(StepExecution stepExecution) {
                // 문제: 영속성 컨텍스트에는 변경 전 데이터가 남아있음
                BatchTarget target = batchTargetRepository.findById(1L).get();
                log.info("status: {}", target.getStatus());  // 변경 전 값!
                return ExitStatus.COMPLETED;
            }
        })
        .build();
}
```

> **주의:** <br>
> `afterStep`은 Step 전체가 끝난 후 호출된다. <br>
> 이 시점에서 청크 트랜잭션은 이미 커밋되었지만, 같은 EntityManager가 살아있고 `clear()`되지 않았다면 <br>
> 1차 캐시에 stale 데이터가 남아 있을 수 있다. <br>
> 반대로 트랜잭션 커밋과 함께 영속성 컨텍스트가 정리된 경우에는 DB에서 새로 조회되므로 문제가 발생하지 않는다. <br>
> **EntityManager의 라이프사이클을 반드시 확인해야 한다.**

---

### 2. Processor에서 JPA 조회 → Writer에서 MyBatis INSERT 후 재조회

```java
@Bean
public ItemProcessor<SourceRecord, BatchResult> processor() {
    return record -> {
        // JPA로 대상 조회 → 영속성 컨텍스트에 캐시됨
        BatchTarget target = batchTargetRepository.findById(record.getTargetId()).get();

        return BatchResult.builder()
            .target(target)
            .amount(record.getAmount())
            .build();
    };
}

@Bean
public MyBatisBatchItemWriter<BatchResult> writer() {
    // MyBatis로 INSERT (target_id 포함)
    // 만약 이 INSERT가 BatchTarget 테이블도 UPDATE 한다면?
    // → 영속성 컨텍스트의 BatchTarget은 stale 상태
}
```

같은 청크 내 다음 item 처리 시:

```java
@Bean
public ItemProcessor<SourceRecord, BatchResult> processor() {
    return record -> {
        // 1차 캐시에서 반환 → DB 변경사항 반영 안 됨!
        BatchTarget target = batchTargetRepository.findById(record.getTargetId()).get();

        // target.getProcessedCount()가 MyBatis에서 증가했는데 반영 안 됨
        return BatchResult.builder()
            .target(target)
            .amount(record.getAmount())
            .build();
    };
}
```

---

### 3. CompositeItemWriter에서 JPA + MyBatis 혼용

```java
@Bean
public CompositeItemWriter<BatchResult> compositeWriter() {
    CompositeItemWriter<BatchResult> writer = new CompositeItemWriter<>();

    writer.setDelegates(List.of(
        myBatisResultWriter(),    // 1. MyBatis로 result INSERT
        jpaTargetWriter()         // 2. JPA로 target UPDATE
    ));

    return writer;
}

@Bean
public ItemWriter<BatchResult> jpaTargetWriter() {
    return items -> {
        for (BatchResult result : items) {
            // 문제: MyBatis가 INSERT한 result를 JPA가 모름
            // result.getTarget()이 영속 상태면 연관관계 불일치 가능
            BatchTarget target = result.getTarget();
            target.setLastProcessedAt(result.getProcessedAt());
            batchTargetRepository.save(target);
        }
    };
}
```

---

### 4. Skip/Retry 로직에서 JPA 조회

```java
@Bean
public Step stepWithRetry() {
    return stepBuilder("step")
        .<Input, Output>chunk(100, transactionManager)
        .reader(reader())
        .processor(processor())
        .writer(myBatisWriter())
        .faultTolerant()
        .retryLimit(3)
        .retry(DeadlockLoserDataAccessException.class)
        .listener(new RetryListener() {
            @Override
            public <T, E extends Throwable> void onError(
                RetryContext context,
                RetryCallback<T, E> callback,
                Throwable throwable
            ) {
                // Retry 시 JPA로 상태 확인하려 하면
                // 이전 MyBatis 작업 결과가 rollback 되었는지 JPA는 모름
                Entity entity = jpaRepository.findById(id).get();  // stale 가능
            }
        })
        .build();
}
```

---

### 5. 같은 청크 내에서 Reader 재조회 (Cursor vs Paging)

```java
@Bean
public Step pagingStep() {
    return stepBuilder("step")
        .<Order, OrderSettlement>chunk(100, transactionManager)
        .reader(jpaPagingReader())    // page 1 읽음 → 영속성 컨텍스트에 100개
        .processor(processor())
        .writer(myBatisBatchWriter()) // MyBatis로 상태 UPDATE
        // 다음 청크에서 page 2 읽을 때
        // → 새 쿼리지만, 같은 데이터가 있다면?
        // → 1차 캐시에서 반환될 수 있음 (stale)
        .build();
}
```

> **정확한 동작 조건:** <br>
> Spring Batch는 청크 단위로 트랜잭션을 커밋한다. <br>
> `JpaPagingItemReader`는 자체 EntityManager를 생성하여 사용하는 경우가 대부분이므로 <br>
> 청크 트랜잭션의 EntityManager와는 **별개로 동작**한다. <br>
>
> 따라서 이 문제는 **Reader와 Step이 동일한 EntityManager를 공유하는 경우에만 발생**한다. <br>
> Reader가 자체 EntityManager를 사용한다면 청크 간 캐시 이슈는 발생하지 않을 수 있다. <br>
>
>  **사용 중인 Reader의 EntityManager 관리 방식을 반드시 확인해야 한다.**

---

## 안전하게 사용하려면

### 방법 1: 청크마다 영속성 컨텍스트 클리어

```java
@Bean
public Step safeStep() {
    return stepBuilder("step")
        .<Input, Output>chunk(100, transactionManager)
        .reader(reader())
        .writer(myBatisWriter())
        .listener(new ChunkListener() {
            @Override
            public void afterChunk(ChunkContext context) {
                entityManager.clear();  // 청크 완료 후 1차 캐시 클리어
            }
        })
        .build();
}
```

> **clear() 사용 시 주의사항** <br>
> clear 이후 기존 영속 엔티티는 **detached 상태**가 된다. <br>
> Lazy Loading 연관관계 접근 시 `LazyInitializationException`이 발생할 수 있다. <br>
> 반드시 다시 조회해서 사용해야 한다.

---

### 방법 2: Reader/Writer 완전 분리

* JPA로 읽는 엔티티와 MyBatis로 쓰는 엔티티가 **완전히 다르고 연관관계가 없다면 안전**하다.
* 설계 단계에서 가장 먼저 고려해야 할 구조적 해결책이다.

---

### 방법 3: JPA 네이티브 쿼리 + 자동 clear

```java
@Modifying(clearAutomatically = true, flushAutomatically = true)
@Query("UPDATE batch_target SET status = :status WHERE id = :id", nativeQuery = true)
void updateStatus(@Param("id") Long id, @Param("status") String status);
```

* 쿼리 실행 후 **영속성 컨텍스트 자동 초기화**
* MyBatis를 JPA 네이티브 쿼리로 대체 가능한 경우 가장 간단한 해결책

---

### 방법 4: 한쪽 기술로 통일

```java
// Option A: MyBatis로 통일
@Bean
public Step allMyBatisStep() {
    return stepBuilder("step")
        .<Map<String, Object>, BatchResult>chunk(100, transactionManager)
        .reader(myBatisPagingReader())
        .processor(processor())
        .writer(myBatisBatchWriter())
        .build();
}

// Option B: JPA로 통일
@Bean
public Step allJpaStep() {
    return stepBuilder("step")
        .<BatchTarget, BatchResult>chunk(100, transactionManager)
        .reader(jpaPagingReader())
        .processor(processor())
        .writer(jpaItemWriter())
        .build();
}
```

* **같은 테이블을 읽고/쓰는 경우 반드시 한쪽으로 통일**
* 가장 확실하고 안전한 해결책

---

### 방법 5: TransactionManager 확인

* JPA와 MyBatis가 **같은 DataSource / TransactionManager**를 공유하는지 반드시 확인해야 한다.
* 서로 다른 TransactionManager를 사용하면 캐시 문제를 넘어 **트랜잭션 정합성 문제**로 확대된다.

```java
// 잘못된 예: 서로 다른 TransactionManager
@Bean
public PlatformTransactionManager jpaTransactionManager() { ... }

@Bean
public PlatformTransactionManager myBatisTransactionManager() { ... }
// → 청크 트랜잭션에는 하나만 참여 → 커밋 시점 불일치 발생

// 올바른 예: 단일 TransactionManager
@Bean
public PlatformTransactionManager transactionManager(EntityManagerFactory emf) {
    return new JpaTransactionManager(emf);
}
// MyBatis도 같은 DataSource 사용 시 동일 트랜잭션 참여
```

---

## 정리
---

| 방법                               | 적용 난이도 | 안전성   | 비고                             |
| -------------------------------- | ------ | ----- | ------------------------------ |
| 청크마다 `clear()`                   | 낮음     | 중간    | LazyInitializationException 주의 |
| Reader/Writer 엔티티 분리             | 중간     | 높음    | 설계 단계 고려 필요                    |
| `@Modifying(clearAutomatically)` | 낮음     | 중간    | MyBatis 대체 가능 시                |
| 한쪽 기술로 통일                        | 높음     | 가장 높음 | 가장 확실한 해결책                     |
| TransactionManager 통일            | 낮음     | 필수    | 혼용 시 반드시 확인                    |
