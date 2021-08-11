---
title: 비동기 프로그래밍을 위한 자바 클래스 살펴보기
date: 2021-08-09 00:29:00 +0900
categories: [JAVA]
tags: [JAVA, 비동기, Future, CompletableFuture]
---

# 들어가기 전
---
회사에서 화면 조회 성능 개선을 위해 어떤 부분을 리팩토링 하면될까 고민하던 중, 몇몇 화면이 호출하는 api에서 수행하는 로직이 각각 독립적인 조회 결과들을 Map에 담아 화면에 리턴해주는 형태로 되어있는 것을 보았다.
따라서, 이런 경우 비동기적으로 처리한다면 성능이 개선되지 않을까 ? 하는 생각이들어 어떤식으로 자바에서 비동기 프로그래밍을 하면되는지 공부해보았다.

# Thread
---
- 자바에서 비동기 프로그래밍을 위한 첫 번째 방법은 JDK 1.0에 있는 `Runnable` 인터페이스와 `Thread` 클래스를 사용하는 것이다.
- 클래스는 `Runnable`을 구현하고 `run()` 메서드를 재정의하거나, `Thread`를 상속받아 동일한 작업을 수행할 수 있다.
  - 차이점은 실행 메서드가 `Runnable`에서 직접 호출될 때 새 스레드가 생성되지 않고 호출 중인 스레드에서 실행된다.
  - `thread.start()`를 수행하면 새 스레드가 생성된다.

- JDK 1.5의 스레드 관리를 개선하기 위해 `Executor` 프레임워크가 등장했다. 따라서, 여러 스레드 풀을 사용할 수 있으며, 수동으로 스레드를 작성할 필요가 없다.
- 또한, 스레드 수를 지정할 수 있으며 스레드를 재사용할 수 있다.

- [이전에 공부했듯이](https://zz9z9.github.io/posts/java-threadpool-executor-framework/), 멀티 스레딩을 위해서는 스레드 풀을 사용하는 것이 장점이 많기 때문에 일반적으로는 비동기 처리를 위해 굳이 스레드를 직접 생성하고 관리하진 않는 것 같다.

# Future
---
- Java 5 부터, `Future` 인터페이스는 `FutureTask`를 사용하여 비동기 작업을 수행할 수 있는 방법을 제공한다.
- `ExecutorService`의 `sumbit()` 메서드를 사용하여 비동기적으로 작업을 수행하고 `FutureTask` 객체를 반환한다.
  - 이 객체는 작업이 끝나면 결과를 얻을 수 있다는 약속(promise)이며, `get()` 메서드를 사용해 결과를 얻는다.

```java
ExecutorService threadpool = Executors.newCachedThreadPool();
Future<Long> futureTask = threadpool.submit(() -> factorial(number));

while (!futureTask.isDone()) {
    System.out.println("FutureTask is not finished yet...");
}
long result = futureTask.get();

threadpool.shutdown();
```

## Future의 한계

> Future API는 몇 가지 중요하고 유용한 기능이 부족하다.

### 1. 수동으로 완료될 수 없다.
- 외부 API를 호출하는 등의 과정을 거쳐 결과적으로 Future를 반환하는 메서드가 있다고 가정하자.
- 만약 API 서비스가 다운된 경우, 캐시된 가장 최근의 값 등을 Future에 세팅하여 수동으로 리턴한다면 에러가 발생하지 않을 것이다. 하지만, Future에 이러한 기능은 없다.

### 2. 블로킹 없이 추가적인 작업을 수행할 수 없다.
- Future에 콜백 함수를 추가하고 Future의 결과를 사용할 수 있을 때, 자동으로 호출하도록 할 수 없다.
  - 즉, 결과를 사용할 수 있을 때까지 블로킹하는 `get()` 메서드만 제공한다.

### 3. 여러개의 작업을 병합할 수 없다.
- 병렬로 실행하려는 10개의 작업이 있고 모든 작업이 완료된 후 일부 기능을 실행한다고 가정했을 때, Future에는 10개를 한꺼번에 실행할 수 있는 기능은 없다.

### 4. 예외 처리를 제공하지 않는다.
- Future API에는 예외 처리를 위한 메서드 등이 없다.

# CompletableFuture
---
> 위에서 살펴봤듯이 Future에는 여러가지 한계점이 있었다. 따라서, 자바8에서는 Future를 업그레이드 시킨 `CompletableFuture`가 등장했다.

- CompletableFuture는 Future 뿐아니라 `CompletionStage` 인터페이스도 구현한다.
  - `CompletionStage`는 다른 스레드에서 계산된 결과를 간단하게 사용할 수 있는 다양한 메서드를 제공한다.
  - 즉, 중첩된 콜백(callback hell) 없이 단일 결과에 여러 비동기 연산을 연결, 결합하는 파이프라인을 지원한다.

  ```java
  CompletableFuture<Integer> priceInEur = CompletableFuture.supplyAsync(this::getPriceInEur);
  CompletableFuture<Integer> exchangeRateEurToUsd = CompletableFuture.supplyAsync(this::getExchangeRateEurToUsd);
  CompletableFuture<Integer> netAmountInUsd = priceInEur
         .thenCombine(exchangeRateEurToUsd, (price, exchangeRate) -> price * exchangeRate);

  logger.info("this task started");

  netAmountInUsd
         .thenCompose(amount -> CompletableFuture.supplyAsync(() -> amount * (1 + getTax(amount))))
         .whenComplete((grossAmountInUsd, throwable) -> {
             if (throwable == null) {
                 logger.info("this task finished: {}", grossAmountInUsd);
             } else {
                 logger.warn("this task failed: {}", throwable.getMessage());
             }
         }); // non-blocking

  logger.info("another task started");
  ```

- 내부적으로 `ForkJoinPool`을 사용하여 작업을 비동기식으로 처리한다.
  - 즉, 전역 `ForkJoinPool.commonPool()`메서드에서 얻은 스레드에서 작업을 실행한다.
    - `ForkJoinPool.commonPool()` 메서드에 의해 반환된 스레드 풀은 모든 CompletableFutures 및 모든 병렬 스트림에 의해 JVM 전체에서 공유된다.
    ```java
    private static final Executor ASYNC_POOL = USE_COMMON_POOL ?
        ForkJoinPool.commonPool() : new ThreadPerTaskExecutor();
    ```

  - 사용자가 스레드 풀을 명시적으로 생성하여 해당 스레드 풀에서 가져온 스레드로 작업을 처리할 수도 있다.
    - 즉, CompletableFuture의 여러 메소드에는 두 가지 변형이 있다.
    - 하나는 사용자가 생성한 스레드 풀을 사용하고, 다른 하나는 내부적으로 생성된 스레드 풀을 사용한다.
    ```java
    public static <U> CompletableFuture<U> supplyAsync(Supplier<U> supplier) {
        return asyncSupplyStage(ASYNC_POOL, supplier);
    }
    public static <U> CompletableFuture<U> supplyAsync(Supplier<U> supplier,
                                                       Executor executor) {
        return asyncSupplyStage(screenExecutor(executor), supplier);
    }
    ```
    ```java
    CompletableFuture<Long> completableFuture = CompletableFuture.supplyAsync(() -> factorial(number));
    long result = completableFuture.get();
    ```

## CompletableFuture 메서드 살펴보기
- CompletableFuture 메서드는 크게 5개 그룹으로 나뉠 수 있다.
1. CompletableFuture 생성
2. 작업 완료 상태 체크
3. 작업 완료 시키기
4. 처리 결과 읽기
5. 여러개의 작업 처리(bulk futures)

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/129049955-86ef5769-1123-4d66-9084-54e49acdf089.png"/>
  <figcaption align="center">출처 : <a href="https://www.linkedin.com/pulse/asynchronous-programming-java-completablefuture-aliaksandr-liakh" target="_blank"> https://www.linkedin.com/pulse/asynchronous-programming-java-completablefuture-aliaksandr-liakh</a> </figcaption>
</figure>

### 1. CompletableFuture 생성 메서드
- 일반적으로 한 스레드에서 완료되지 않은 Future가 생성되고 다른 스레드에서 완료된다. 그러나 경우에 따라 이미 완료된 Future를 만들 수도 있다.
- 파라미터가 없는 CompletableFuture 생성자는 완료되지 않은 Future를 생성한다.

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/129054187-7dc96c1e-176e-4725-a603-5925f3d0741b.png"/>
  <figcaption align="center">출처 : <a href="https://www.linkedin.com/pulse/asynchronous-programming-java-completablefuture-aliaksandr-liakh" target="_blank"> https://www.linkedin.com/pulse/asynchronous-programming-java-completablefuture-aliaksandr-liakh</a> </figcaption>
</figure>

### 2. 완료 상태 체크 메서드
- CompletableFuture 클래스에는 작업이 완료되지 않았는지, 정상적으로 완료되었는지, 예외적으로 완료되었는지, 취소되었는지 여부를 확인하기 위한 non-blocking 메서드가 있다.
- 이미 완료된 작업은 취소가 불가능하다.

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/129054317-6e046a0b-d7ae-48cc-98fa-018a4a0e93ca.png"/>
  <figcaption align="center">출처 : <a href="https://www.linkedin.com/pulse/asynchronous-programming-java-completablefuture-aliaksandr-liakh" target="_blank"> https://www.linkedin.com/pulse/asynchronous-programming-java-completablefuture-aliaksandr-liakh</a> </figcaption>
</figure>

### 3. 작업 완료를 위한 메서드
- CompletableFuture에는 아직 완료되지 않은 작업을 정상완료, 예외완료, 취소 상태를 갖는 완료된 작업으로 바꾸는 메서드가 있다.
- cancel 메서드가 호출되면 `CancellationException`과 함께 연산이 취소된다. 하지만, 해당 작업을 수행하는 스레드를 중단하기 위한 `Thread.interrupt()`는 호출되지 않는다.

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/129054544-907049d6-a9e1-424d-94b4-090214f735e1.png"/>
  <figcaption align="center">출처 : <a href="https://www.linkedin.com/pulse/asynchronous-programming-java-completablefuture-aliaksandr-liakh" target="_blank"> https://www.linkedin.com/pulse/asynchronous-programming-java-completablefuture-aliaksandr-liakh</a> </figcaption>
</figure>

### 4. 처리 결과 읽기 메서드
- CompletableFuture는 작업에 대한 결과를 읽는(아직 완료되지 않은 경우는 대기) 메서드를 제공한다.
- 이러한 메서드는 대부분의 경우, 계산 파이프라인의 마지막 단계로 사용해야 한다.
- `get()`, `get(timeout, timeUnit)` 메서드는 'checked exception'을 발생시킬 수 있다.
  - `ExecutionException` : 작업이 예외적으로 완료된 경우
  - `InterruptedException` : 현재 스레드가 중단된 경우
  - `TimeoutException` : `get(timeout, timeUnit)` 메서드 사용시 타임아웃 발생하는 경우
- `join()`, `getNow(valueIfAbsent)` 메서드는 'unchecked exception'을 발생시킬 수 있다.
  -  `CompletionException` : 작업이 예외적으로 완료되는 경우
- 작업이 취소되는 경우, 모든 메서드가 `CancellationException`(unchecked exception)을 발생시킬 수 있다.

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/129055474-a98868dc-6faf-4ef8-a918-61382d94fbe7.png"/>
  <figcaption align="center">출처 : <a href="https://www.linkedin.com/pulse/asynchronous-programming-java-completablefuture-aliaksandr-liakh" target="_blank"> https://www.linkedin.com/pulse/asynchronous-programming-java-completablefuture-aliaksandr-liakh</a> </figcaption>
</figure>

### 5. 여러개의 작업 처리를 위한 메서드
- CompletableFuture에는 많은 작업이 완료될 때까지 대기하는 두 가지 정적 메서드가 있다.
- 각각 다른 타입의 CompletableFuture가 메서드 파라미터로 입력될 수 있다.
  - 정의된 파라미터 : `CompletableFuture<?>... cfs`

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/129055651-d4c2c46d-b8ac-4f70-b481-02c22bd68c57.png"/>
  <figcaption align="center">출처 : <a href="https://www.linkedin.com/pulse/asynchronous-programming-java-completablefuture-aliaksandr-liakh" target="_blank"> https://www.linkedin.com/pulse/asynchronous-programming-java-completablefuture-aliaksandr-liakh</a> </figcaption>
</figure>


## CompletionStage
- CompletionStage 인터페이스는 여러 단계를 거치는 연산에서, fork, chain, join할 수 있는 각 단계를 나타낸다.
- 또한, future/promise 구현에 대한 파이프라이닝을 명시한다.
- 파이프라이닝
  - 각 단계는 연산을 수행한다. 값을 계산하거나(결과 반환) 작업 수행만 할 수도 있다(결과 반환 안 함).
  - 각 단계를 파이프라인으로 연결한다.
    - 하나 또는 두 개의 이전 단계를 완료하여 현재 단계를 시작할 수 있다.
    - 각 단계는 연산이 완료되면 종료된다.
  - 각 단계는 동기식 또는 비동기식으로 실행될 수 있다. 처리될 데이터에 따라 적절한 방법을 선택해야 한다.

- CompletionStage 인터페이스의 메서드는 크 두 그룹으로 나눌 수 있다.
1. 파이프라이닝 연산을 위한 메서드
2. 예외 처리를 위한 메서드

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/129051294-111163be-2dfb-4d52-854c-c0c864d24158.png"/>
  <figcaption align="center">출처 : <a href="https://www.linkedin.com/pulse/asynchronous-programming-java-completablefuture-aliaksandr-liakh" target="_blank"> https://www.linkedin.com/pulse/asynchronous-programming-java-completablefuture-aliaksandr-liakh</a> </figcaption>
</figure>

### 1. 파이프라이닝 연산을 위한 메서드
> CompletionStage 인터페이스에는 43개의 public 메서드가 있으며, 대부분 세 가지의 이름 패턴을 갖는다.

#### 첫째, 새로운 단계가 시작되는 방법을 설명한다.
- 메서드 이름에 "then"이 있으면, 하나의 이전 단계가 완료된 후 새 단계가 시작된다.
- 메서드 이름에 "either"가 있으면, 이전 두 단계 중 첫 번째 단계가 완료된 후 새 단계가 시작된다.
- 메서드 이름에 "both"가 있으면, 이전 두 단계를 모두 완료한 후 새 단계가 시작된다.

#### 둘째, 새로운 단계가 수행하는 연산에 대해 설명한다.
- 메서드 이름에 "apply"가 있으면, 새로운 단계는 주어진 `Function`을 기준으로 인수를 변환한다.
- 메서드 이름에 "accept"가 있으면, 새로운 단계는 주어진 `Consumer`를 기준으로 인수를 처리한다.
- 메서드 이름에 "run"이 있으면, 새로운 단계는 주어진 `Runnable`를 기준으로 작업을 수행한다.

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/129068414-9ae5e35f-e54e-4a3b-9fdb-1e470209f3d9.png"/>
  <figcaption align="center">출처 : <a href="https://www.linkedin.com/pulse/asynchronous-programming-java-completablefuture-aliaksandr-liakh" target="_blank"> https://www.linkedin.com/pulse/asynchronous-programming-java-completablefuture-aliaksandr-liakh</a> </figcaption>
</figure>

#### 셋째, 어떤 스레드가 새로운 단계를 실행하는지 설명한다.
- 메서드에 "something(...)"의 형태이면, 새 단계는 기본 스레드 풀에 의해 실행된다.(동기 또는 비동기)
- 메서드에 "somethingAsync()"의 형태이면, 새 단계는 기본 비동기 스레드 풀(ForkJoinPool)에 의해 실행된다.
- 메서드에 "somethingAsync(..., Executor))"의 형태이면,새 단계는지정된 Executor(사용자 정의 스레드 풀)에 의해 실행된다.

```java
CompletableFuture<Double> pi = CompletableFuture.supplyAsync(() -> Math.PI);
CompletableFuture<Integer> radius = CompletableFuture.supplyAsync(() -> 1);

// area of a circle = π * r^2
CompletableFuture<Void> area = radius
        .thenApply(r -> r * r)
        .thenCombine(pi, (multiplier1, multiplier2) -> multiplier1 * multiplier2)
        .thenAccept(a -> logger.info("area: {}", a))
        .thenRun(() -> logger.info("operation completed"));

area.join();
```

### 2. 예외 처리를 위한 메서드
> 각 단계별 연산은 정상적으로 또는 예외적으로 완료될 수 있다.
> 또한, 비동기 연산에서는 예외가 발생한 곳과 예외 처리를 위한 메서드는 서로 다른 스레드에 있을 수 있다.
> 따라서 이 경우 try-catch-finally 문을 사용하여 예외를 처리할 수 없기 때문에
> CompletionStage는 예외를 처리하기 위한 특별한 메서드를 제공한다.

- 이전 단계가 정상적으로 완료되면, 다음 단계가 정상적으로 실행되기 시작합니다.
- 이전 단계가 예외적으로 완료되면, 파이프라인에 예외 복구 단계가 없는 한 다음 단계는 예외적으로 완료된다.
- `whenComplete` 메서드를 사용하면 결과(없는 경우 null)와 예외(없는 경우 null)를 모두 읽을 수 있지만 결과를 변경할 수는 없습니다.
- 예외 발생시 복구해야 하는 경우 `handle`과 `exceptionally` 메서드를 사용한다.
  - `handle` 메소드의 `BiFunction` 인수는 이전 단계가 정상적으로 또는 예외적으로 완료될 때 모두 호출된다.
  - `exceptionally` 메서드의 `Function` 인수는 이전 단계가 예외적으로 완료될 때 호출된다.
  - 두 경우 모두 예외가 다음 단계로 전파되지 않는다.

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/129049131-389e06b3-b558-4e28-a7fc-f8a0ac09d786.png"/>
  <figcaption align="center">출처 : <a href="https://www.linkedin.com/pulse/asynchronous-programming-java-completablefuture-aliaksandr-liakh" target="_blank"> https://www.linkedin.com/pulse/asynchronous-programming-java-completablefuture-aliaksandr-liakh</a> </figcaption>
</figure>

```java
CompletableFuture.supplyAsync(() -> 0)
       .thenApply(i -> { logger.info("stage 1: {}", i); return 1 / i; }) // executed and failed
       .thenApply(i -> { logger.info("stage 2: {}", i); return 1 / i; }) // skipped
       .whenComplete((value, t) -> {
           if (t == null) {
               logger.info("success: {}", value);
           } else {
               logger.warn("failure: {}", t.getMessage()); // executed
           }
       })
       .thenApply(i -> { logger.info("stage 3: {}", i); return 1 / i; }) // skipped
       .handle((value, t) -> {
           if (t == null) {
               return value + 1;
           } else {
               return -1; // executed and recovered
           }
       })
       .thenApply(i -> { logger.info("stage 4: {}", i); return 1 / i; }) // executed
       .join();
```

## CompletableFuture 사용시 주의사항
- 어떤 스레드가 어떤 단계를 실행하는지 알고, 되도록이면 우선 순위가 높은 스레드가 오래 실행되는 낮은 우선 순위의 작업을 처리하지 않게 한다.
- 파이프라인 내에서 블로킹 메서드 사용을 지양한다.
- 빈번한 context switch로 인해 상당한 오버헤드가 발생할 수 있으므로 짧은(수백 밀리초) 비동기식 계산을 지양한다.
- try-catch-finally 문과 다르게 작동하는 새로운 예외 처리 메커니즘에 유의할 것.
- 작업이 완료되는 것을 너무 오래 기다리지 않도록 타임아웃을 관리한다.


# Parallel Streams
---


# @Async
---


# 실제로 적용하기
---
- 회사 코드 비동기적으로 리팩토링 해보기

# 참고자료
---
- [https://www.baeldung.com/java-asynchronous-programming](https://www.baeldung.com/java-asynchronous-programming)
- [https://www.cognizantsoftvision.com/blog/async-in-java/](https://www.cognizantsoftvision.com/blog/async-in-java/)
- [https://www.linkedin.com/pulse/java-8-future-vs-completablefuture-saral-saxena](https://www.linkedin.com/pulse/java-8-future-vs-completablefuture-saral-saxena)
- [https://www.callicoder.com/java-8-completablefuture-tutorial/](https://www.callicoder.com/java-8-completablefuture-tutorial/)
- [https://www.linkedin.com/pulse/asynchronous-programming-java-completablefuture-aliaksandr-liakh](https://www.linkedin.com/pulse/asynchronous-programming-java-completablefuture-aliaksandr-liakh)
