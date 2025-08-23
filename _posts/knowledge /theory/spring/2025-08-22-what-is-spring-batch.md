---
title: Spring - Spring Batch 알아보기
date: 2025-08-22 21:25:00 +0900
categories: [지식 더하기, 이론]
tags: [Spring]
---

## Spring Batch
---
> Spring Batch는 엔터프라이즈 시스템의 핵심 일상 업무(vital for the daily operations)를 위한 견고한 배치 애플리케이션 개발을 지원하는 경량·종합 프레임워크

- Spring Batch는 생산성, POJO 기반 개발, 쉬운 사용성 같은 **스프링 특성을 계승**하면서, 필요 시 고급 엔터프라이즈 서비스도 쉽게 활용할 수 있도록 한다.
- Spring Batch는 스케줄링 프레임워크가 아니다.
  - 상용·오픈소스 영역에는 Quartz, Tivoli, Control-M 등 훌륭한 스케줄러가 이미 있다.
  - 따라서, Spring Batch는 스케줄러를 대체하는 게 아니라 함께 동작하도록 설계되었다.
- Spring Batch는 대규모 데이터 처리에 필수적인 재사용 가능한 기능(로그/추적, 트랜잭션 관리, 실행 통계, 재시작, 스킵, 리소스 관리)을 제공한다.
  - 또한 최적화·파티셔닝 기법을 통해 초대규모·고성능 배치 작업을 가능하게 하는 고급 기능도 제공한다.
- 즉, **대규모 데이터 처리 작업 및 운영을 안정적이고 편리하게** 만들어주는 프레임워크

## 주요 개념
---

### Chunk-based processing
> 대용량 데이터를 효율적으로 처리하는 핵심 패턴

- 데이터를 일정 단위(예: 1000건)로 묶어 처리
- 메모리 절약, 안정적 처리, 재시작 용이

### Transaction management
> 배치 처리에서 데이터 일관성을 보장

- Chunk 단위 트랜잭션 보장 (실패 시 해당 Chunk만 롤백 가능)

### Declarative I/O
> 복잡한 I/O 로직을 간단한 설정으로 처리

- ItemReader, ItemWriter 같은 표준 컴포넌트 제공
  - ItemReader: 데이터베이스, 파일, 메시지 큐 등 다양한 소스에서 데이터 읽기
  - ItemWriter: 다양한 형태로 데이터 출력 (DB 저장, 파일 쓰기, API 호출 등)

### Start / Stop / Restart
> 배치 작업의 운영 편의성을 제공

- JobRepository: 작업 실행 상태와 메타데이터를 저장
  - 실행한 Job/Step의 상태, 시작·종료 시간, 처리 건수, 실패 원인 등
  - Job의 이력 관리 가능 (언제 어떤 데이터가 처리되었는지 추적)
- 재시작 지원: 실패 지점부터 다시 시작 가능 (이미 처리된 부분은 건너뜀)
- 중단 후 재개: 안전하게 작업을 중단하고 나중에 이어서 실행

### Retry / Skip
> 오류 상황에 대한 유연한 처리 정책을 제공

- Retry: 일시적 오류(네트워크 끊김 등) 발생 시 지정된 횟수만큼 재시도
- Skip: 특정 오류는 무시하고 다음 데이터로 넘어가기
- 정책 설정: 어떤 예외에 대해 몇 번 재시도할지, 어떤 예외는 건너뛸지 세밀하게 제어

### Job / Step 구조
- Job: 하나의 배치 작업 단위 (예: “월말 정산 작업”)
- Step: Job을 구성하는 세부 단계 (예: “DB에서 데이터 읽기 → 가공 → 결과 저장”)
- 이를 통해, 구조화된 모델 덕분에 작업을 잘게 나누고, 재사용·조합이 가능해짐.
  - 예: 동일한 DB 읽기 Step을 다른 Job에서도 재사용할 수 있음.

### Scalability
- 멀티스레드 Step: 한 Step을 여러 스레드로 분할 처리
- Partitioning: 데이터를 여러 파티션으로 나누어 병렬 처리
- Remote Chunking: “읽기/처리”와 “쓰기”를 분산 노드에서 실행
- Remote Partitioning: Step 자체를 원격 워커들에 분산
- 대규모 데이터도 분산·병렬 환경에서 처리 가능

## 비교 : Spring MVC vs Spring Batch
---
> 예시 상황 : 대량의 주문 정보 업데이트가 필요, 업데이트 하려면 외부 api 호출 필요.

- Spring MVC 방식

```java
@Service
public class OrderBatchService {

  @Transactional
  public void processOrders(List<Order> orders) {
    for (Order order : orders) {
      try {
        ApiResult result = externalApi.call(...); // 외부 API 호출
        order.makeOrder(result);  // 주문 상태 변경
        updateOrder(order); // DB 업데이트
      } catch (ApiException e) {
        // 재시도 로직을 직접 구현해야 함
        for (int i = 0; i < 3; i++) {
          try {
            ApiResult result = externalApi.call(...);
            order.makeOrder(result);
            updateOrder(order);
            break; // 성공하면 탈출
          } catch (Exception retryEx) {
            if (i == 2) {
              // 실패 기록을 직접 관리해야 함
              log.error("Order {} 처리 실패", order.getId());
              saveToFailedOrderTable(order);
            }
          }
        }
      }
    }
  }

}
```

- Spring Batch

```java
@Configuration
@EnableBatchProcessing
public class OrderBatchConfig {

  @Bean
  public Job orderJob(JobRepository jobRepository, Step orderStep) {
    return new JobBuilder("orderJob", jobRepository)
      .start(orderStep)
      .build();
  }

  @Bean
  public Step orderStep(JobRepository jobRepository,
                        PlatformTransactionManager transactionManager) {
    return new StepBuilder("orderStep", jobRepository)
      .<Order, Order>chunk(1000, transactionManager)
      .reader(orderReader())
      .processor(orderProcessor())
      .writer(orderWriter())
      .faultTolerant()
      .skip(ApiException.class)        // 특정 예외 건너뛰기
      .skipLimit(100)                  // 최대 100건까지 Skip 허용
      .retry(ApiException.class)       // API 호출 실패 시 재시도
      .retryLimit(3)                   // 최대 3번까지 재시도
      .build();
  }

  @Bean
  public JdbcPagingItemReader<Order> orderReader(DataSource dataSource) {
    return new JdbcPagingItemReaderBuilder<Order>()
      .name("orderReader")
      .dataSource(dataSource)
      .selectClause("SELECT ...")
      .fromClause("FROM orders")
      .sortKeys(Collections.singletonMap("id", Order.ASCENDING))
      .pageSize(1000)
      .rowMapper(new BeanPropertyRowMapper<>(Order.class))
      .build();
  }

  @Bean
  public ItemProcessor<Order, Order> orderProcessor() {
    return order -> {
      ApiResult result = externalApi.call(...);
      order.makeOrder(result);
      return order;
   };

  @Bean
  public JdbcBatchItemWriter<Order> orderWriter(DataSource dataSource) {
    return new JdbcBatchItemWriterBuilder<Order>()
      .dataSource(dataSource)
      .sql("UPDATE orders ...")
      .beanMapped()
      .build();
  }

}
```

| 항목           | Spring MVC                    | Spring Batch                                      |
| ------------ | ----------------------------- | ------------------------------------------------- |
| **재시도 처리**   | `try-catch` + 반복문 직접 구현 필요    | `.retry(Exception.class).retryLimit(n)` 으로 선언적 설정 |
| **스킵 처리**    | 실패한 건을 따로 DB 저장 로직 작성 필요      | `.skip(Exception.class).skipLimit(n)` 으로 선언적 설정   |
| **실패 내역 관리** | 별도 테이블(`failed_orders`) 직접 구현 | `JobRepository`에 자동 저장 (실패 건수, 예외 타입 등)           |
| **재처리**      | 실패 테이블 기반으로 재처리 Job 따로 작성     | 실패 이력 기반으로 Job/Step 재시작 가능                        |
| **운영 편의성**   | 로그 + 수작업 확인 필요                | 실패 내역이 메타DB에 기록 → 운영자가 재실행 가능                     |


## 참고 자료
- [https://spring.io/projects/spring-batch#overview](https://spring.io/projects/spring-batch#overview)
- [https://docs.spring.io/spring-batch/reference/spring-batch-intro.html](https://docs.spring.io/spring-batch/reference/spring-batch-intro.html)
