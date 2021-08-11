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

# 비동기와 Non-blocking
---


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
- [Future/Promise 방식](작성 예정)을 구현한 클래스
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

### CompletableFuture 사용시 주의사항
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
