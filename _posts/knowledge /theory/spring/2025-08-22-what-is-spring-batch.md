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

### Tasklet
- Step 안에서 한 번에 실행할 **작업(Task)**을 구현하는 방식
- 인터페이스: Tasklet → RepeatStatus execute(StepContribution, ChunkContext) 메서드 구현
- 반복 처리(Chunk 기반)가 필요 없는 단순 로직에 적합
  - 예: 특정 테이블 초기화, 파일 삭제, 외부 API 한 번 호출
- 선언형 Chunk 모델보다 `Spring MVC + @Service` 스타일과 유사
- 하지만 Spring Batch 실행 모델(Job/Step, JobRepository, 재시작 지원 등) 위에서 동작하므로, 단순 로직도 **운영 메타데이터 관리, 재시작, 스케줄링 연동 혜택을 받음**
- 예시:
  - 아래 코드 실행 중 외부 API 호출이 네트워크 문제로 실패했다면?
  - MVC라면 로그 보고 사람이 수동으로 재시도
  - Batch라면 Job 상태가 FAILED로 기록됨
  - 운영자가 restart 하면 해당 Step만 다시 실행 → 중간부터 이어서 처리 가능

```java
@Bean
public Step apiStep(JobRepository jobRepository, PlatformTransactionManager transactionManager) {
    return new StepBuilder("apiStep", jobRepository)
            .tasklet((contribution, chunkContext) -> {
                externalApi.call(...); // 외부 API 호출
                return RepeatStatus.FINISHED;
            }, transactionManager)
            .allowStartIfComplete(false) // 이미 성공한 Step은 재실행 안 함
            .build();
}
```

- Tasklet vs Chunk

| 구분                  | **Chunk 기반 처리**                                                                    | **Tasklet 기반 처리**                                                |
| ------------------- | ---------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| **처리 방식**           | 데이터를 **읽기-처리-쓰기(Reader/Processor/Writer)** 패턴으로 반복 실행                              | `execute()` 메서드 안에서 단일 작업 수행                                     |
| **적합한 시나리오**        | - 대량 데이터(수천\~수억 건)<br>- 주기적인 정산/집계<br>- DB → 파일, 파일 → DB 적재<br>- 데이터 변환, ETL 파이프라인 | - 단순 작업(한두 번 실행)<br>- 테이블 초기화/백업<br>- 외부 API 호출 1회<br>- 파일 압축/삭제 |
| **트랜잭션 관리**         | **Chunk 단위 트랜잭션** (예: 1000건씩 커밋) → 실패 시 해당 Chunk만 롤백                               | 보통 전체 Step이 1 트랜잭션 → 실패 시 전체 롤백                                  |
| **재시작(Checkpoint)** | 마지막 커밋된 Chunk 위치부터 이어서 실행 가능                                                       | Step 자체가 단일 실행 단위 → 실패 시 Step 전체 재실행                             |
| **Retry/Skip**      | 선언적으로 설정 가능 (`.retry()`, `.skip()`) → **데이터 단위 예외 처리**                             | 별도 로직 작성 필요 (try-catch 안에서 수동 구현)                                |
| **운영 편의성**          | 대량 데이터 처리 시 안정성, 확장성 뛰어남                                                           | 단순 로직도 Job/Step 메타데이터에 기록되므로 운영 추적 가능                            |
| **비교 비유**           | “**엑셀에서 100만 행 데이터를 1000행씩 끊어서 처리**”                                               | “**버튼 한 번 누르면 테이블 삭제**” 같은 단일 태스크                                |


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
        order.doSomething(result);  // 주문 상태 변경
        updateOrder(order); // DB 업데이트
      } catch (ApiException e) {
        // 재시도 로직을 직접 구현해야 함
        for (int i = 0; i < 3; i++) {
          try {
            ApiResult result = externalApi.call(...);
            order.doSomething(result);
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
      order.doSomething(result);
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

## 기타
---

### 개발 배경
> [https://docs.spring.io/spring-batch/reference/spring-batch-intro.html#springBatchBackground](https://docs.spring.io/spring-batch/reference/spring-batch-intro.html#springBatchBackground)

- 오픈소스 커뮤니티는 주로 웹/마이크로서비스 아키텍처에 집중했지만, Java 기반 배치 처리용 재사용 가능한 아키텍처 프레임워크는 부족했다. 기업 IT 환경에서는 여전히 배치 처리가 필요한데도 말이다.
- 표준 배치 프레임워크 부재로 인해 기업들은 제각각 자체 배치 솔루션을 개발해왔다.
- SpringSource(현재 VMware)와 Accenture가 이를 바꾸기 위해 협력했다.
- Accenture의 산업/배치 경험, SpringSource의 기술 전문성, Spring의 프로그래밍 모델이 합쳐져 엔터프라이즈 Java의 공백을 메우는 고품질 배치 프레임워크가 탄생했다.
- 두 회사는 고객들과 협력하며 Spring 기반 배치 아키텍처를 구축했고, 이 경험이 현실 제약 조건과 요구사항을 반영해 실제 문제에 적용 가능한 솔루션을 만드는 데 기여했다.
- Accenture는 과거 사내 독점 배치 프레임워크와 개발자 리소스를 Spring Batch에 기여해 기능 확장과 지원을 제공했다.
- Accenture는 메인프레임 COBOL, 유닉스 C++, 자바 기반 아키텍처 등 수십 년간의 배치 경험을 토대로 기여했다.
- Accenture와 SpringSource의 협력 목표는 엔터프라이즈 IT에서 배치 애플리케이션 개발 시 재사용 가능한 표준 프레임워크를 만드는 것이었다.
- 표준화되고 검증된 솔루션을 원하는 기업·정부 기관은 Spring Batch로부터 혜택을 얻을 수 있다.

### 별도의 프로젝트 ?
- Spring Framework 프로젝트에서 하나의 모듈이 아닌 별도의 Spring Batch 프로젝트로 관리된다. (참고 : [github repo](https://github.com/spring-projects/spring-batch))
- Spring Web MVC는 Spring Framework의 하나의 모듈로 관리된다.
- Spring Batch도 `spring-aop`, `spring-beans` 등의 핵심 모듈을 사용하는데, 왜 별도의 프로젝트로 분리되었을까?
- GPT에게 물어보았다. (맞는지는 모르겠다)

```
1. 역할과 성격이 다른 기능
- Spring Framework는 애플리케이션 전반의 기반 기능(IOC 컨테이너, AOP, 트랜잭션, 웹 MVC 등)을 제공하는 핵심 프레임워크입니다.
- Spring Batch는 배치 처리에 특화된 기능(잡/스텝 정의, 잡 실행 관리, 리스타트/스킵/리트라이, 청크 기반 처리 등)을 제공하는 응용 계층 프레임워크입니다.
- 즉, Batch는 **도메인 특화 기능(DSF, Domain-Specific Framework)**에 가깝기 때문에, 코어 프레임워크와 같은 레벨에서 관리하기보다는 별도의 독립 프로젝트로 분리하는 게 더 적절했습니다.

2. 릴리스 주기 및 버전 독립성
- Spring Framework는 전반적인 생태계에 영향을 주므로 안정적이고 보수적인 릴리스 주기가 필요합니다.
- Spring Batch는 특정 기업 환경(금융, 대규모 데이터 처리 등) 요구사항에 맞추어 더 빠르게 발전하거나 독자적으로 패치될 필요가 있습니다.
- 별도 프로젝트로 분리함으로써 Spring Framework 릴리스와 강하게 묶이지 않고, 독자적인 릴리스 주기를 가질 수 있습니다.

3. 사용자 대상의 범위 차이
- Spring Framework는 거의 모든 Spring 애플리케이션 개발자가 사용하는 범용 플랫폼입니다.
- Spring Batch는 **배치 처리(ETL, 대규모 DB 마이그레이션, 정산 작업 등)**를 수행하는 특정 케이스에서만 필요합니다.
- 따라서 일반적인 웹 애플리케이션 개발자가 꼭 가져가야 하는 모듈이 아니기 때문에, 선택적으로 추가할 수 있도록 별도 프로젝트로 분리한 겁니다.

4. 팀/프로젝트 관리상의 이유
- Spring Batch는 초기에 Accenture와 SpringSource가 협력해서 만든 프로젝트입니다.
- 즉, 시작부터 **외부 파트너십과 특정 요구사항(기업용 배치 처리)**을 기반으로 설계되었기 때문에 Spring Framework 코어에 바로 들어가기보다는 독립된 프로젝트로 출발하는 게 자연스러웠습니다.
- 지금도 Spring 팀은 Framework, Boot, Data, Security, Batch 등을 프로젝트 단위로 관리합니다.
```

## 참고 자료
- [https://spring.io/projects/spring-batch#overview](https://spring.io/projects/spring-batch#overview)
- [https://docs.spring.io/spring-batch/reference/spring-batch-intro.html](https://docs.spring.io/spring-batch/reference/spring-batch-intro.html)
