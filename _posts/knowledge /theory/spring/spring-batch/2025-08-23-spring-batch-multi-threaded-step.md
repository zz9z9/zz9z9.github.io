---
title: Spring Batch - Multi-threaded Step 알아보기
date: 2025-08-23 12:25:00 +0900
categories: [지식 더하기, 이론]
tags: [Spring Batch]
---

## 개요
---

- Spring Batch는 병렬 처리를 위한 다양한 옵션을 제공한다.
- 큰 틀에서 병렬 처리는 두 가지 방식이 있다:
  - **Single-process**
    - Multi-threaded Step
    - Parallel Steps
  - **Multi-process**
    - Remote Chunking of Step
    - Partitioning a Step (Single or Multi-process)

## Multi-threaded Step
---

> 병렬 처리를 시작하는 가장 단순한 방법은 Step 설정에 TaskExecutor를 추가하는 것

```java
@Bean
public TaskExecutor taskExecutor() {
    return new SimpleAsyncTaskExecutor("spring_batch");
}

@Bean
public Step sampleStep(TaskExecutor taskExecutor, JobRepository jobRepository, PlatformTransactionManager transactionManager) {
	return new StepBuilder("sampleStep", jobRepository)
				.<String, String>chunk(10, transactionManager)
				.reader(itemReader())
				.writer(itemWriter())
				.taskExecutor(taskExecutor)
        .throttleLimit(20) // default : 4 (스프링 배치 5.0부터는 deprecated)
        .build();
}
```

- 위 설정을 통해, Step이 실행될 때 **각 청크(커밋 단위)를 별도의 스레드에서** 읽고, 처리하고, 쓰게 된다.
- 따라서 아이템들이 순차적으로 처리되지 않을 수 있으며, 단일 스레드의 경우와 달리 한 청크에 연속되지 않는 아이템이 포함될 수도 있습니다.
- 추가로, taskExecutor 자체의 제한(예: 스레드 풀이냐 아니냐) 외에도, tasklet 설정에는 throttleLimit(기본값: 4)이 존재합니다.
  - 즉, 동시에 최대 4개의 청크만 병렬 실행
- 스레드 풀을 충분히 활용하려면 이 제한을 늘려야 할 수도 있습니다.

### Throttle limit 폐기
- 버전 5.0부터 throttle limit은 deprecated 되었으며 대체제가 없습니다.
- 현재 기본 `TaskExecutorRepeatTemplate`에서 쓰이는 쓰로틀링 메커니즘을 바꾸고 싶다면, bounded task queue를 가진 TaskExecutor 기반의 커스텀 RepeatOperations 구현체를 만들어서, `StepBuilder#stepOperations`에 넣어야 합니다:

```java
@Bean
public Step sampleStep(RepeatOperations customRepeatOperations, JobRepository jobRepository, PlatformTransactionManager transactionManager) {
    return new StepBuilder("sampleStep", jobRepository)
                .<String, String>chunk(10, transactionManager)
                .reader(itemReader())
                .writer(itemWriter())
                .stepOperations(customRepeatOperations)
                .build();
}
```

### 주의사항
- Step의 많은 구성 요소(예: Reader, Writer)는 stateful 합니다.
  - `FlatFileItemReader`는 파일 포인터(cursor)를 갖고 있어서 여러 스레드가 동시에 접근하면 꼬임.
  - `JdbcCursorItemReader`도 DB 커서 기반이라 멀티스레드에 적합하지 않음.
  - 반면, `JdbcPagingItemReader`는 Stateless Reader

- 만약 이 상태가 스레드별로 분리되지 않는다면, 멀티스레드 Step에서는 사용할 수 없습니다.
- 특히, Spring Batch가 제공하는 대부분의 Reader와 Writer는 멀티스레드 용도로 설계되지 않았습니다.
- 그러나, stateless 또는 thread-safe한 Reader/Writer를 사용한다면 가능하며, [Spring Batch 샘플](https://github.com/spring-projects/spring-batch/tree/main/spring-batch-samples)에서는 DB 입력 테이블에 **처리 여부 플래그(process indicator)**를 두어 어떤 아이템이 이미 처리되었는지 추적하는 방법을 보여줍니다.
- Spring Batch는 일부 ItemWriter, ItemReader 구현을 제공합니다.
  - Javadoc에 thread-safe 여부 또는 동시성 환경에서 피해야 할 문제가 명시되어 있는 경우가 많습니다.
  - 정보가 없다면 구현체를 직접 확인해 상태(state)가 있는지 살펴야 합니다.

- 만약 Reader가 thread-safe하지 않다면, `SynchronizedItemStreamReader`로 감싸거나, 직접 동기화 래퍼를 구현할 수 있습니다.
- read() 호출을 동기화하면, 비록 읽기 자체는 직렬화되더라도, 처리(processing)와 쓰기(writing) 단계가 청크 내에서 가장 비용이 큰 부분이라면, 전체 Step은 여전히 싱글스레드보다 훨씬 빠르게 끝날 수 있습니다.

## 예시
---

```java
@Configuration
@EnableBatchProcessing
public class OrderBatchConfig {

    private final DataSource dataSource;

    public OrderBatchConfig(DataSource dataSource) {
        this.dataSource = dataSource;
    }

    // 멀티스레드용 TaskExecutor
    @Bean
    public ThreadPoolTaskExecutor taskExecutor() {
        ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
        executor.setCorePoolSize(8);   // 동시에 실행할 스레드 수
        executor.setMaxPoolSize(8);    // 최대 스레드 수도 동일하게 설정
        executor.setQueueCapacity(0);  // bounded queue → 무한 큐 방지
        executor.setThreadNamePrefix("spring_batch-");
        executor.initialize();
        return executor;
    }

    // Reader (페이징 기반, 멀티스레드 안전)
    @Bean
    public JdbcPagingItemReader<Order> orderReader() throws Exception {
        JdbcPagingItemReader<Order> reader = new JdbcPagingItemReader<>();
        reader.setDataSource(dataSource);
        reader.setPageSize(100);

        SqlPagingQueryProviderFactoryBean queryProvider = new SqlPagingQueryProviderFactoryBean();
        queryProvider.setDataSource(dataSource);
        queryProvider.setSelectClause("id, customer_id, status");
        queryProvider.setFromClause("from orders");
        queryProvider.setWhereClause("where status = 'NEW'");
        queryProvider.setSortKeys(Map.of("id", Order.ASCENDING));

        reader.setQueryProvider(queryProvider.getObject());

        reader.setRowMapper((rs, rowNum) -> new Order(
                rs.getLong("id"),
                rs.getLong("customer_id"),
                rs.getString("status")
        ));
        return reader;
    }

    // Processor (상태 변경)
    @Bean
    public ItemProcessor<Order, Order> orderProcessor() {
        return order -> {
            order.setStatus("PROCESSED");
            return order;
        };
    }

    // Writer (Batch update)
    @Bean
    public JdbcBatchItemWriter<Order> orderWriter() {
        return new JdbcBatchItemWriterBuilder<Order>()
                .dataSource(dataSource)
                .sql("UPDATE orders SET status = :status WHERE id = :id")
                .beanMapped()
                .build();
    }

    // Step 정의 (멀티스레드 적용)
    @Bean
    public Step processOrdersStep(JobRepository jobRepository, PlatformTransactionManager transactionManager) throws Exception {
        return new StepBuilder("processOrdersStep", jobRepository)
                .<Order, Order>chunk(100, transactionManager)
                .reader(orderReader())
                .processor(orderProcessor())
                .writer(orderWriter())
                .taskExecutor(taskExecutor())   // 멀티스레드 실행
                .build();
    }

    // Job 정의
    @Bean
    public Job orderJob(JobRepository jobRepository, Step processOrdersStep) {
        return new JobBuilder("orderJob", jobRepository)
                .start(processOrdersStep)
                .build();
    }
}
```

### 페이징 처리 방식
- `JdbcPagingItemReader`는 `pageSize` 단위로 쿼리를 실행해서 데이터를 가져옵니다.
- 예를 들어, 전체 조회 대상이 10000개이고 pageSize=100이면:
  - 1차 쿼리 : `where status='NEW' order by id limit 100 offset 0`
  - 2차 쿼리 : `where status='NEW' order by id limit 100 offset 100`
  - 이런 식으로 쿼리를 날려서 10000개를 끊어서 가져옵니다. 따라서 중복 없이 전체 10000개를 다 읽습니다.<br>
  (단, 여기서 정렬 기준 `sortKeys`를 반드시 지정해야 안정적으로 paging이 됩니다. 보통 id ASC 같은 단일 PK 기준을 많이 씁니다.)


### pageSize > chunkSize 이면 ?
> 총 대상 데이터 : 10,000개 (status=NEW) <br>
> chunkSize = 100 <br>
> pageSize = 1000

- Reader
  - DB에서 1000개를 한 번에 select 해와서 메모리에 들고 있음.
  - 예: id 1 ~ 1000

- Processor & Writer
  - 읽어온 1000개 중 100개씩 잘라서 Processor → Writer → commit 실행.
  - 즉, 같은 1000개 데이터를 내부 버퍼에서 10번(=1000/100) 반복해서 처리.

- 다음 Reader 호출
  - Reader가 다시 DB에 쿼리 → 다음 1000개(id 1001~2000) 가져옴.
  - 그 안에서도 chunk 단위(100)로 나눠서 10번 commit.

- 결과
  - DB는 10번(=10000 / 1000)만 조회함.
  - Processor/Writer는 여전히 100개 단위로 동작해서 총 100번 commit(=10000 / 100).
  - 즉, pageSize는 "DB fetch 단위", **chunkSize는 "트랜잭션 처리 단위"**라는 점이 드러남.

## 참고 자료
---
- [https://docs.spring.io/spring-batch/reference/scalability.html](https://docs.spring.io/spring-batch/reference/scalability.html)
