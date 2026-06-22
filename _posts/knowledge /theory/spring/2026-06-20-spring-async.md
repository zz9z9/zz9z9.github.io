---
title: Spring - @Async 살펴보기 (JDK Executor를 곁들인..)
date: 2026-06-20 15:25:00 +0900
categories: [지식 더하기, 이론]
tags: [Spring]
---

JDK의 Executor / ExecutorService / ThreadPoolExecutor
Spring의 TaskExecutor / AsyncTaskExecutor / ThreadPoolTaskExecutor
비슷한 이름의 클래스들 정리 및 @Async 동작까지 살펴보자.

## Executor

> [공식문서](https://docs.oracle.com/en/java/javase/17/docs/api/java.base/java/util/concurrent/Executor.html) <br>
> 제출된 `Runnable` 작업을 실행하는 객체.

```java
// java.util.concurrent.Executor
public interface Executor {

    /**
     * Executes the given command at some time in the future.  The command
     * may execute in a new thread, in a pooled thread, or in the calling
     * thread, at the discretion of the {@code Executor} implementation.
     *
     * @param command the runnable task
     * @throws RejectedExecutionException if this task cannot be
     * accepted for execution
     * @throws NullPointerException if command is null
     */
    void execute(Runnable command);
}
```

`Executor`의 핵심은 공식 문서의 이 한 문장이다.

> 이 인터페이스는 작업 제출(task submission)을, 각 작업이 실제로 어떻게 실행될지(스레드 사용·스케줄링 등의 세부 사항)와 분리하는 방법을 제공한다.

즉 **작업을 제출하는 일(task submission)** 과 **그 작업을 어떻게 실행할지**(스레드 생성·스케줄링 등)를 분리해주는 인터페이스다. 직접 스레드를 만들어 `Runnable`을 실행하는 대신, 실행 방식을 `Executor` 뒤로 숨긴다.

> Executor는 보통 스레드를 직접 생성하는 대신 사용한다.

### 분리 전 — task와 실행 방식이 엉켜 있다

> 비동기로 돌리려면 작업을 호출하는 쪽이 스레드 생성·관리까지 직접 해야 했다.

```java
// 하고 싶은 task = 이메일 보내기
Runnable sendEmail = () -> emailService.send(...);

// 그런데 "어떻게 실행할지"가 호출부에 박혀버린다
new Thread(sendEmail).start();   // 매번 새 스레드 생성이라는 '방식'이 코드에 고정됨
```

"이메일 보내기"라는 task와 "새 스레드를 만들어 거기서 돌린다"는 실행 메커니즘이 한 줄에 붙어 있다. 그래서 나중에 실행 방식을 다음처럼 바꾸려고 하면,

- 새 스레드 대신 스레드 풀에서 돌리기
- (테스트용으로) 호출한 스레드에서 동기 실행
- 큐에 쌓아 순차 처리

`sendEmail`을 호출하는 모든 곳을 다 고쳐야 한다. task를 제출하는 코드가 실행 방식에 종속돼 있기 때문이다.

### 분리 후 — Executor가 그 사이를 끊는다

```java
Runnable sendEmail = () -> emailService.send(...);

// "이거 실행해줘"라고 제출만 한다. 어떻게 돌릴지는 executor가 결정한다.
executor.execute(sendEmail);
```

호출부는 이제 "무엇을"만 신경 쓰고 "어떻게"는 모른다. 그 "어떻게"는 어떤 `Executor`를 주입하느냐에 따라 완전히 달라지지만, 호출부 코드는 한 글자도 바뀌지 않는다.

```java
// 1) 매번 새 스레드
Executor executor = command -> new Thread(command).start();

// 2) 호출한 스레드에서 동기 실행 (예: 테스트)
Executor executor = command -> command.run();

// 3) 고정 크기 스레드 풀
Executor executor = Executors.newFixedThreadPool(10);

// 4) 단일 스레드로 순차 처리
Executor executor = Executors.newSingleThreadExecutor();
```

위 넷 중 무엇을 주입하든 `executor.execute(sendEmail)` 호출부는 동일하다. 이것이 공식 문서가 말하는 디커플링이다.

- **task submission** = `executor.execute(sendEmail)` — 작업을 던지는 행위
- **the mechanics of how each task will be run** — 새 스레드냐 / 풀이냐 / 동기냐 / 큐잉이냐


## TaskExecutor
> [공식문서](https://docs.spring.io/spring-framework/docs/6.2.x-SNAPSHOT/javadoc-api/org/springframework/core/task/TaskExecutor.html)

```java
// org.springframework.core.task.TaskExecutor
@FunctionalInterface
public interface TaskExecutor extends Executor {

	/**
	 * Execute the given {@code task}.
	 * <p>The call might return immediately if the implementation uses
	 * an asynchronous execution strategy, or might block in the case
	 * of synchronous execution.
	 * @param task the {@code Runnable} to execute (never {@code null})
	 * @throws TaskRejectedException if the given task was not accepted
	 */
	@Override
	void execute(Runnable task);

}
```

### 왜 `Executor`와 똑같은 걸 하나 더 만들었나 — JDK 1.4 호환성

> `TaskExecutor`의 `execute(Runnable)`은 `java.util.concurrent.Executor`와 시그니처가 똑같다. 그런데 왜 같은 모양의 인터페이스를 굳이 하나 더 뒀을까? **버전 호환성** 때문이다.

- `java.util.concurrent.Executor`는 Java 5(2004)에 들어왔다.
- `TaskExecutor`가 나온 Spring 2.0(2006) 무렵, 스프링은 아직 JDK 1.4를 지원해야 했다. `java.util.concurrent`는 JDK 5부터라 의존할 수 없었다.
- 그래서 "JDK 버전과 무관하게 우리만의 추상화를 두자"는 의도로 `TaskExecutor`를 따로 만들었다.
- 나중에 baseline을 JDK 5+로 올리면서 `TaskExecutor extends Executor`로 정리했다. 처음엔 독립적이었다가, 표준을 상속하도록 합쳐진 형태다.

| | `java.util.concurrent.Executor` | `org.springframework.core.task.TaskExecutor` |
| --- | --- | --- |
| 소속 | JDK 표준 | Spring Framework |
| 의미 | "이 `Runnable`을 실행해라" (범용 저수준 추상화) | "이건 task 실행용이다" — 스프링 추상화의 진입점 |
| 예외 | `RejectedExecutionException` (unchecked) | `TaskRejectedException` (`RejectedExecutionException`의 하위 클래스) |
| 역할 | 단순 실행기 | `@Async`, `AsyncExecutionInterceptor`, `ThreadPoolTaskExecutor` 등 스프링 비동기 인프라의 타입 마커이자 확장 지점 |

### 스프링이 자체 `TaskExecutor`를 둬서 얻는 것

> JDK 호환성 이슈를 빼고 봐도, `Executor`를 그대로 쓰지 않고 한 겹 두면 이런 이점이 생긴다.

- **타입을 통한 의미 부여**: "그냥 실행기가 아니라 스프링이 관리하는 task 실행기"라는 마커가 된다. `@Async`가 컨텍스트에서 실행기 빈을 찾을 때 의미 있는 타입이 된다.
- **예외 번역**: JDK의 `RejectedExecutionException`을 스프링 예외 체계(`TaskRejectedException`)로 바꿔 일관성을 유지한다.
- **자유로운 확장**: `AsyncTaskExecutor`(submit/Future), `SchedulingTaskExecutor`처럼 필요할 때 계층을 덧붙일 수 있는 **자기 소유의 루트**를 갖는다. `java.util.concurrent.Executor`는 스프링이 손댈 수 없는 남의 인터페이스이기 때문이다.

즉 짚어준 대로 "JDK에 의존하지 않고 스프링이 자체적으로 확장 가능"한 것이 핵심이다. 실제로 인터페이스인 `AsyncTaskExecutor`가 `TaskExecutor`를 상속(`extends`)하며 `submit`/`Future`를 얹는 식으로 계층을 넓혀 간다.

### 호환성 문제가 없었어도 안 만들었을까?

> 호환성만이 유일한 이유였다면 "JDK 이슈가 없었으면 `TaskExecutor`도 없었을 것"이라는 추론이 성립한다. 하지만 스프링의 설계 성향을 보면 **그래도 한 겹 뒀을 가능성이 높다.**

스프링은 표준/외부 API가 있어도 자기만의 얇은 추상화를 한 겹 더 두는 습관이 있다.

- `Resource` — JDK에 `File`, `URL`이 있는데도 별도 추상화를 둠
- `Environment` / `PropertySource` — 시스템 프로퍼티를 직접 쓰지 않고 감쌈
- `ApplicationEventPublisher` — 이벤트도 자기 타입으로
- `TaskScheduler` — `ScheduledExecutorService`가 있는데도 별도로 둠

이렇게 하는 이유는 **확장 지점과 의미(semantic)를 스프링이 직접 통제하기 위해서**다.

| 가정 | 결과 |
| --- | --- |
| 디커플링(호환성)만이 유일한 이유였다면 | JDK 이슈가 없으면 → `TaskExecutor`는 안 만들어졌을 것 |
| 실제 스프링 설계 철학을 보면 | JDK 이슈가 없었어도 → 얇은 추상화 한 겹은 뒀을 가능성이 높음 |

> JDK 호환성은 `TaskExecutor`를 "지금 당장, 상속도 안 하고" 만들게 한 결정적 방아쇠였다. 다만 스프링이 외부 표준 위에 자기 추상화를 얹는 습관(Resource, Environment 등)을 보면, 그 방아쇠가 없었어도 확장과 예외 번역을 위해 어떤 형태로든 자기 인터페이스를 뒀을 거라고 보는 게 더 현실적이다.

## ExecutorService
> [공식문서](https://docs.oracle.com/en/java/javase/17/docs/api/java.base/java/util/concurrent/ExecutorService.html)
> 종료(termination)를 관리하는 메서드와, 하나 이상의 비동기 작업의 진행 상황을 추적할 `Future`를 만들어내는 메서드를 제공하는 `Executor`.

> `Executor`가 "task 제출과 실행을 분리한다"는 **순수한 개념**만 담았다면, `ExecutorService`는 거기에 **실무에서 굴리는 데 필요한 기능**(결과 받기·종료·일괄 실행)을 얹은 인터페이스다.

`Executor` 공식 문서도 이 둘의 관계를 이렇게 설명한다.

> 이 패키지가 제공하는 Executor 구현체들은 더 확장된 인터페이스(more extensive interface)인 `ExecutorService`를 구현한다.


### Executor는 개념 — 메서드가 하나뿐

`Executor`는 메서드가 `execute(Runnable)` 하나뿐이라, 람다 한 줄로도 구현할 수 있다.

```java
// 메서드가 1개뿐이라 람다로 구현 가능
Executor inline    = r -> r.run();               // 동기 실행기
Executor newThread = r -> new Thread(r).start(); // 매번 새 스레드
```

이렇게 단순하다는 점이 두 가지 실용적인 이점을 준다.

**1) 의존성을 최소로 받는다.** 어떤 메서드가 "그냥 실행만" 필요하다면, 인자를 `ExecutorService`(메서드 여러 개)가 아니라 `Executor`(메서드 1개)로 받는 게 깔끔하다. 받는 쪽은 실행만 시킬 수 있고, 실수로 풀을 `shutdown` 해버릴 일도 없다.

```java
// "나는 실행만 시키면 된다. 풀 생명주기엔 관심 없다"
void process(Executor executor) {
    executor.execute(() -> doWork());   // shutdown 같은 건 호출 자체가 불가능 → 안전
}
```

**2) 개념과 운영을 분리한다.** `Executor`는 "task 제출과 실행을 분리한다"는 순수한 개념만 담고, `ExecutorService`는 거기에 실무용 기능(결과/종료/일괄)을 얹은 운영용 인터페이스다. 인터페이스 분리 원칙(ISP)에도 맞는 설계다.

### ExecutorService는 실무용 — 결과·종료·일괄

> `ExecutorService`가 `Executor`에 더하는 기능은 크게 세 묶음이다.

- **결과 받기**: `submit(Callable/Runnable)`로 작업을 던지고 `Future`로 결과·예외·완료 여부를 추적
- **종료 관리**: `shutdown()` / `shutdownNow()` / `awaitTermination()` / `isShutdown()` / `isTerminated()`
- **일괄 실행**: `invokeAll()`(전부 실행) / `invokeAny()`(하나라도 먼저 끝나는 결과)


```java

  public interface ExecutorService extends Executor, AutoCloseable {

      void shutdown();

      List<Runnable> shutdownNow();

      boolean isShutdown();

      boolean isTerminated();

      boolean awaitTermination(long timeout, TimeUnit unit)
          throws InterruptedException;

      <T> Future<T> submit(Callable<T> task);

      <T> Future<T> submit(Runnable task, T result);

      Future<?> submit(Runnable task);

      <T> List<Future<T>> invokeAll(Collection<? extends Callable<T>> tasks)
          throws InterruptedException;

      <T> List<Future<T>> invokeAll(Collection<? extends Callable<T>> tasks,
                                    long timeout, TimeUnit unit)
          throws InterruptedException;

      <T> T invokeAny(Collection<? extends Callable<T>> tasks)
          throws InterruptedException, ExecutionException;

      <T> T invokeAny(Collection<? extends Callable<T>> tasks,
                      long timeout, TimeUnit unit)
          throws InterruptedException, ExecutionException, TimeoutException;

      @Override
      default void close() {
          boolean terminated = isTerminated();
          if (!terminated) {
              shutdown();
              boolean interrupted = false;
              while (!terminated) {
                  try {
                      terminated = awaitTermination(1L, TimeUnit.DAYS);
                  } catch (InterruptedException e) {
                      if (!interrupted) {
                          shutdownNow();
                          interrupted = true;
                      }
                  }
              }
              if (interrupted) {
                  Thread.currentThread().interrupt();
              }
          }
      }
  }
```

> `ExecutorService`가 `AutoCloseable`을 구현하고 `close()` 디폴트 메서드를 갖게 된 것은 Java 19부터다. 그 전에는 `extends Executor`만 했다.

`submit`이 받는 `Callable`은 `Runnable`과 달리 **결과를 반환**하고 예외를 던질 수 있다.

```java
package java.util.concurrent;

@FunctionalInterface
public interface Callable<V> {

    V call() throws Exception;
}
```


## ThreadPoolExecutor
> [공식문서](https://docs.oracle.com/en/java/javase/17/docs/api/java.base/java/util/concurrent/ThreadPoolExecutor.html)
> 제출된 각 작업을 풀에 있는 여러 스레드 중 하나로 실행하는 `ExecutorService`. 보통 `Executors` 팩토리 메서드로 구성한다.

> `ExecutorService`의 실제 구현체 중 하나다. 앞서 본 `submit`/`shutdown`/`invokeAll` 같은 기능을 **스레드 풀**로 실제 구현한 클래스다.

스레드 풀은 두 가지 문제를 해결한다. ① 작업마다 드는 호출 오버헤드를 줄여 대량의 비동기 작업에서 성능을 높이고, ② 작업을 실행할 때 쓰는 자원(스레드 포함)을 제한·관리하는 수단을 준다. (완료된 작업 수 같은 기본 통계도 유지한다.)

조절 가능한 파라미터와 확장 훅이 많지만, 공식 문서는 흔한 경우라면 더 편한 `Executors` 팩토리 메서드를 쓰라고 권한다 — `newCachedThreadPool()`, `newFixedThreadPool(int)`, `newSingleThreadExecutor()`. 직접 튜닝할 때만 아래 동작을 이해하면 된다.

### 동작 방식 — core → 큐 → max 순으로 채운다

> 작업이 들어오면 다음 순서로 처리할 곳을 정한다.

```
새 task 도착
  │
  ├─ 현재 스레드 수 < corePoolSize ?
  │     예 → 새 스레드 생성 (놀고 있는 스레드가 있어도 무조건 생성)
  │
  ├─ core가 다 찼으면 → 큐에 넣기 시도
  │     큐에 자리 있음 → 큐에 적재 (스레드 추가 안 함)
  │
  └─ 큐도 꽉 참 → 현재 스레드 수 < maxPoolSize ?
        예    → 새 스레드 생성 (core 초과분, 임시 스레드)
        아니오 → 거부(Rejected) → RejectedExecutionHandler 발동
```

여기서 반드시 짚어야 할 반직관적인 포인트가 있다.

> `maxPoolSize`는 "큐가 꽉 찬 다음"에야 작동한다.

흔히 "부하가 높으면 core → max까지 스레드가 늘겠지"라고 오해하지만, 실제로는 core가 차면 max보다 **큐를 먼저** 채운다. 그래서 큐가 무한대(`LinkedBlockingQueue` 무제한)면 큐가 절대 안 차고, `maxPoolSize`는 영원히 쓰이지 않는다. 스레드는 `corePoolSize`에서 멈춘다. (공식 문서가 말하는 "maximumPoolSize therefore doesn't have any effect"가 이 뜻이다.)

```
core=5, max=50, queue=무제한  →  실제 최대 스레드 = 5  (max 50은 장식)
```

`maxPoolSize`를 실제로 쓰려면 큐를 유한하게 둬야 한다. 그래야 큐가 차고, 그제서야 core 초과 스레드가 생긴다.

### 주요 설정들

| 설정 | 의미 | 튜닝 감각 |
| --- | --- | --- |
| `corePoolSize` | 평상시 유지하는 기본 스레드 수. 유휴 상태여도(기본) 죽지 않음 | 정상 부하를 감당할 만큼 (CPU 작업이면 ≈ 코어 수) |
| `maxPoolSize` | 큐가 꽉 찼을 때만 늘어나는 상한 | 큐가 유한해야 의미 있음 |
| `queueCapacity` | core가 다 찼을 때 대기시킬 작업 수 | 크면 스레드 ↓·지연 ↑ / 작으면 스레드 ↑·throughput ↑ |
| `keepAliveSeconds` | core 초과 스레드가 이 시간 놀면 회수 | 버스트가 끝난 뒤 임시 스레드 정리 |
| `allowCoreThreadTimeOut` | core 스레드도 keepAlive로 죽게 허용 | true면 한가할 때 스레드 0까지 감소 |
| `rejectedExecutionHandler` | 큐+max가 다 차서 못 받을 때의 정책 | 아래 4종 |

거부 정책(`RejectedExecutionHandler`)은 4종이다.

| 정책 | 동작 |
| --- | --- |
| `AbortPolicy` (기본) | `RejectedExecutionException`을 던진다 |
| `CallerRunsPolicy` | 제출한 스레드가 직접 실행 → 제출 속도를 자연히 늦춤(백프레셔) |
| `DiscardPolicy` | 조용히 버린다 |
| `DiscardOldestPolicy` | 큐 맨 앞(가장 오래된) 것을 버리고 재시도 |

> 실무에서 백프레셔가 필요하면 `CallerRunsPolicy`를 많이 쓴다 — 풀이 포화되면 제출자(예: 요청 처리 스레드)가 직접 일을 처리하게 해서 유입 속도를 자연스럽게 늦춘다.

## ThreadPoolTaskExecutor
> [공식문서](https://docs.spring.io/spring-framework/docs/current/javadoc-api/org/springframework/scheduling/concurrent/ThreadPoolTaskExecutor.html)

공식 문서는 이렇게 설명한다.

> `ThreadPoolExecutor`를 빈 스타일(`corePoolSize`, `maxPoolSize`, `keepAliveSeconds`, `queueCapacity` 프로퍼티)로 설정하고, 그것을 스프링 `TaskExecutor`로 노출하는 JavaBean이다. JMX 같은 관리·모니터링에도 잘 맞으며, `corePoolSize`·`maxPoolSize`·`keepAliveSeconds`(런타임 갱신 가능), `poolSize`·`activeCount`(조회 전용) 같은 속성을 제공한다.
> 기본 설정은 corePoolSize 1, maxPoolSize 무제한, 큐 용량 무제한이다. 이는 `Executors.newSingleThreadExecutor()`와 거의 같아서 모든 작업이 스레드 하나를 공유한다. `queueCapacity`를 0으로 두면 `Executors.newCachedThreadPool()`처럼 동작해 스레드가 즉시 (매우 큰 수까지) 늘어난다. 이때는 `maxPoolSize`도 함께 설정하는 것이 좋다.

> 이 클래스는 스프링의 `TaskExecutor`와 `Executor`를 모두 구현하지만, `TaskExecutor`가 주(primary) 인터페이스이고 `Executor`는 부차적 편의일 뿐이다. 그래서 예외 처리도 `Executor`가 아니라 `TaskExecutor` 계약을 따르며, 거부 시 `TaskRejectedException`을 던진다.

### 내부적으로는 ThreadPoolExecutor를 쓴다

> 스레드 풀링 같은 핵심 동작은 직접 구현하지 않고, 내부에 들고 있는 `ThreadPoolExecutor`에 위임한다.

`ThreadPoolTaskExecutor`는 `ThreadPoolExecutor`를 감싼 래퍼다. 스레드를 몇 개 띄우고, 큐에 쌓고, 거부 정책을 적용하는 실제 풀 동작은 전부 내부 `ThreadPoolExecutor`가 한다. 스프링은 그 위에 "빈으로 쓰기 편한 껍데기"를 씌우고 편의 기능을 얹은 것뿐이다.

날것의 `ThreadPoolExecutor`를 그대로 쓰고 싶다면 생성자 주입이나 `Executors` 팩토리로 만든 뒤, `ConcurrentTaskExecutor` 어댑터로 감싸 스프링 `TaskExecutor`로 노출할 수도 있다.

### 스프링이 더해준 것

> JDK `ThreadPoolExecutor`를 그대로 쓰지 않고 한 겹 감싸면서, 스프링은 설정 방식·생명주기·예외 처리·큐 추상화를 자기 식으로 바꿨다.

**1) 빈(Bean) 스타일 설정 — setter/프로퍼티로 구성**

JDK `ThreadPoolExecutor`는 생성자에 인자를 7개나 넣어야 만들어진다.

```java
// JDK 직접 — 생성자 한 방에 다 넣어야 함 (스프링 설정과 안 어울림)
new ThreadPoolExecutor(5, 10, 60L, TimeUnit.SECONDS,
    new LinkedBlockingQueue<>(100),
    threadFactory, rejectedHandler);
```

반면 `ThreadPoolTaskExecutor`는 JavaBean이라 setter(프로퍼티)로 설정한다. 그래서 스프링 `@Bean`이나 XML, `@ConfigurationProperties`와 자연스럽게 붙는다.

```java
@Bean
public ThreadPoolTaskExecutor taskExecutor() {
    ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
    executor.setCorePoolSize(5);          // setter로 하나씩
    executor.setMaxPoolSize(10);
    executor.setQueueCapacity(100);
    executor.setKeepAliveSeconds(60);
    executor.setThreadNamePrefix("async-");  // 스레드 이름까지 (디버깅에 유용)
    executor.initialize();
    return executor;
}
```

위 공식 문서 인용의 "빈 스타일로 설정한다"가 바로 이 얘기다.

**2) 스프링 생명주기와 연동 — shutdown 자동 호출**

실무에서 제일 큰 이점이다. 앞에서 본 "풀을 안 끄면 스레드가 누수되고 JVM이 안 죽는다"는 문제를, `ThreadPoolTaskExecutor`는 스프링 컨테이너 생명주기에 묶여 자동으로 처리한다.

- 스프링이 빈을 만들 때 → `initialize()`로 내부 풀 생성 (`InitializingBean`)
- 스프링 컨텍스트가 닫힐 때 → 자동으로 `shutdown()` 호출 (`DisposableBean`)

`shutdown()`을 직접 부르지 않아도 앱 종료 시 스프링이 알아서 풀을 정리한다. JDK `ThreadPoolExecutor`를 날것으로 빈 등록하면 이 자동 종료가 안 돼서 graceful shutdown이 깔끔하지 않을 수 있다.

**3) 스프링 TaskExecutor 타입으로 노출 + 예외 번역**

여기서 `TaskExecutor`가 왜 필요했는지가 연결된다. `ThreadPoolTaskExecutor`는 스프링의 `TaskExecutor` 타입이다.

- `@Async`가 이걸 찾아 쓸 수 있다. (`@Async`는 `TaskExecutor`/`Executor` 타입 빈을 찾는다)
- 작업 거부 시 JDK의 `RejectedExecutionException` 대신 스프링 예외 `TaskRejectedException`을 던진다. 예외 타입의 일관성을 위해서다.

**4) 추가적인 설정**

설정 프로퍼티는 크게 셋으로 나뉜다.

**JDK 설정을 이름만 바꿔 그대로 노출한 것**

| ThreadPoolTaskExecutor 프로퍼티 | JDK ThreadPoolExecutor | 비고 |
| --- | --- | --- |
| `corePoolSize` | `corePoolSize` | 그대로 |
| `maxPoolSize` | `maximumPoolSize` | 이름만 줄임 |
| `keepAliveSeconds` | `keepAliveTime` | 단위 고정(초) |
| `allowCoreThreadTimeOut` | `allowCoreThreadTimeOut` | 그대로 |
| `threadFactory` | `ThreadFactory` | 그대로 |
| `rejectedExecutionHandler` | `RejectedExecutionHandler` | 그대로 |
| `prestartAllCoreThreads` | `prestartAllCoreThreads()` | 그대로 |

**스프링이 자기 식으로 바꾼 것 — queueCapacity**

JDK는 `BlockingQueue` 객체를 직접 넣어야 한다.

```java
// JDK: 큐 객체를 내가 골라서 직접 줌
new ThreadPoolExecutor(..., new LinkedBlockingQueue<>(100));
```

반면 스프링은 큐 객체 대신 `queueCapacity`라는 `int` 하나만 받고, 그 값으로 큐 종류를 내부에서 자동 결정한다.

```java
// ThreadPoolTaskExecutor 내부 로직 (단순화)
if (queueCapacity > 0) {
    return new LinkedBlockingQueue<>(queueCapacity);  // 용량 있는 큐
} else {
    return new SynchronousQueue<>();                  // 0이면 직접 핸드오프 큐
}
```

앞 공식 문서 인용의 "`queueCapacity`를 0으로 두면 `newCachedThreadPool`처럼 동작한다"가 바로 이 분기 때문이다. JDK엔 없는, 스프링만의 편의 추상화다.

**스프링이 새로 추가한 것 — JDK엔 아예 없음**

| 스프링 추가 설정 | 역할 |
| --- | --- |
| `threadNamePrefix` | 스레드 이름 접두사(`async-1`...). JDK에선 `ThreadFactory`를 직접 짜야 했던 걸 한 줄로 |
| `waitForTasksToCompleteOnShutdown` | 종료 시 남은 작업을 마칠지(`shutdown`) 즉시 끊을지(`shutdownNow`) 선택 |
| `awaitTerminationSeconds` | 종료 시 최대 몇 초 기다릴지 (graceful shutdown 타임아웃) |
| `taskDecorator` | 작업을 실행 직전에 감싸는 훅 (예: `ThreadLocal`/MDC/보안 컨텍스트 전파) |
| `initialize()` 생명주기 | 스프링 빈 초기화/소멸에 풀 생성·종료를 연결 |

특히 `waitForTasksToCompleteOnShutdown` + `awaitTerminationSeconds`는 앞에서 본 "표준 `shutdown` + `shutdownNow` 조합 패턴"을 프로퍼티로 노출한 것이다. `taskDecorator`도 JDK엔 없는 스프링 고유 훅이다.

## 중간 정리 — Executor 계열 한눈에 보기

> 지금까지 본 Executor 계열을 JDK 세계와 스프링 세계로 나눠 정리한다. 두 세계는 거의 1:1로 대응하고, 스프링 쪽 끝(`ThreadPoolTaskExecutor`)이 JDK 풀(`ThreadPoolExecutor`)을 감싸 들고 있는 구조다.

```
        JDK 세계                          Spring 세계
   ─────────────────                 ─────────────────────
   Executor              ──(대응)──▶  TaskExecutor
      │ extends                          │ extends
   ExecutorService                    AsyncTaskExecutor
      │ (구현체)                          │ (구현체)
   ThreadPoolExecutor  ◀──(has-a)──   ThreadPoolTaskExecutor
   (진짜 스레드 풀)                      (빈 설정 + 생명주기 + @Async 연동)
```

### JDK 세계 (java.util.concurrent)

```
Executor  (interface)                         ← 최소 추상화: execute(Runnable)
   │  "task 제출 ↔ 실행 메커니즘" 분리, 그게 전부
   │
   └── ExecutorService  (interface)           ← + submit/Future, shutdown, invokeAll, AutoCloseable
          │   "실무용 실행기" (결과·생명주기·일괄)
          │
          ├── ScheduledExecutorService (interface)   ← + 지연/주기 실행 (schedule…)
          │
          └── AbstractExecutorService (abstract class)  ← submit/invokeAll 공통 구현 제공
                 │
                 ├── ThreadPoolExecutor (class) ★      ← 진짜 스레드 풀 (core/max/queue/거부정책)
                 │      │
                 │      └── ScheduledThreadPoolExecutor ← ThreadPoolExecutor + 스케줄링
                 │
                 └── ForkJoinPool (class)               ← work-stealing 풀 (병렬 스트림 등)

Executors  (유틸 클래스)  ← new 안 하고 풀 만들어주는 팩토리
   newFixedThreadPool() / newCachedThreadPool() / newSingleThreadExecutor() …
   → 내부적으로 ThreadPoolExecutor 를 설정해서 반환
```

> JDK 한 줄 요약: `Executor`(개념) → `ExecutorService`(실무 인터페이스) → `ThreadPoolExecutor`(실제 구현). `Executors`는 그 구현을 쉽게 찍어주는 공장이다.

### 스프링 세계 (org.springframework.*)

```
Executor (JDK)                                ← 스프링은 여기서 출발(상속)
   │
   └── TaskExecutor (interface) ★             ← 스프링 진입점. execute(Runnable)만 (JDK와 동일 시그니처)
          │   "이건 스프링이 관리하는 task 실행기다" + 예외 번역(TaskRejectedException)
          │
          └── AsyncTaskExecutor (interface)    ← + submit(Callable)/Future, submitCompletable
                 │   "결과를 받는 비동기 실행기" (@Async가 요구하는 타입)
                 │
                 ├── SchedulingTaskExecutor (interface)
                 │
                 └── [구현체들]
                       ├── ThreadPoolTaskExecutor (class) ★  ← 내부에 JDK ThreadPoolExecutor를 들고 감
                       ├── ConcurrentTaskExecutor (class)    ← 남의 JDK Executor를 감싸는 어댑터
                       ├── VirtualThreadTaskExecutor         ← 작업마다 새 '가상 스레드' (풀 아님)
                       ├── SimpleAsyncTaskExecutor (class)   ← 풀 아님! 매번 새 스레드(또는 가상스레드)
                       └── TaskExecutorAdapter (class)       ← raw Executor → AsyncTaskExecutor 변환(내부용)
```

### 전체 한눈에 보기

| 이름 | 세계 | 종류 | 역할 |
| --- | --- | --- | --- |
| `Executor` | JDK | 인터페이스 | 최소 추상화. `execute(Runnable)` |
| `ExecutorService` | JDK | 인터페이스 | + 결과/종료/일괄. 실무 인터페이스 |
| `ScheduledExecutorService` | JDK | 인터페이스 | + 지연/주기 실행 |
| `ThreadPoolExecutor` | JDK | 클래스 | 실제 스레드 풀 (core/max/queue) |
| `Executors` | JDK | 유틸 클래스 | 풀 팩토리 (`newFixedThreadPool`…, `newVirtualThreadPerTaskExecutor`) |
| `TaskExecutor` | Spring | 인터페이스 | 스프링 진입점 (`extends Executor`) |
| `AsyncTaskExecutor` | Spring | 인터페이스 | + submit/Future. `@Async`가 요구 |
| `ThreadPoolTaskExecutor` | Spring | 클래스 | JDK 풀을 감싼 스프링 빈 (플랫폼 스레드, 재사용) |
| `VirtualThreadTaskExecutor` | Spring | 클래스 | 작업마다 새 가상 스레드(JDK 21+). 풀 아님, I/O 바운드에 강함 |
| `SimpleAsyncTaskExecutor` | Spring | 클래스 | 작업마다 새 스레드(플랫폼, `setVirtualThreads(true)`로 가상도) |
| `ConcurrentTaskExecutor` | Spring | 클래스 | 기존 JDK Executor를 `TaskExecutor`로 노출 |

## 스프링 부트의 스레드풀 기본 동작

> [공식문서](https://docs.spring.io/spring-boot/reference/features/task-execution-and-scheduling.html)

> 스프링 부트는 `TaskExecutionAutoConfiguration`으로 `applicationTaskExecutor`라는 `AsyncTaskExecutor` 빈을 자동 등록한다. `@Async`나 MVC 비동기 요청 처리 등이 이 빈을 기본 실행기로 쓴다.

### 무엇이 자동으로 만들어지나

- **빈 이름**: `applicationTaskExecutor` (`taskExecutor`라는 이름도 함께 붙는다)
- **타입**: 기본은 `ThreadPoolTaskExecutor`. 단, 가상 스레드를 켜면(`spring.threads.virtual.enabled=true`, Java 21+) `SimpleAsyncTaskExecutor`(가상 스레드, 풀 아님)로 바뀐다.

> 빈에 `taskExecutor`라는 이름이 같이 붙는 게 핵심이다. 앞서 본 `@EnableAsync`의 executor 탐색 규칙(② 이름이 `"taskExecutor"`인 `Executor` 빈)에 그대로 걸려서, `@Async`가 자동 설정된 이 풀을 별도 설정 없이 찾아 쓴다.

문서가 정리한, 이 빈을 쓰는 곳:

- `@EnableAsync`로 띄우는 `@Async` 비동기 작업 (단, `AsyncConfigurer`를 직접 정의하면 그쪽이 우선)
- 스프링 MVC 비동기 요청 처리(`Callable` 반환 등), WebFlux의 블로킹 실행 지원, WebSocket 메시지 채널
- JPA 부트스트랩, 빈 백그라운드 초기화의 부트스트랩 실행기

### 기본 설정값

> 별도 설정이 없으면 core 8개, 큐·max 무제한으로 만들어진다.

| 프로퍼티 (`spring.task.execution.*`) | 기본값 | 의미 |
| --- | --- | --- |
| `pool.core-size` | 8 | 코어 스레드 수 |
| `pool.max-size` | `Integer.MAX_VALUE` | 최대 스레드 수(사실상 무제한) |
| `pool.queue-capacity` | `Integer.MAX_VALUE` | 큐 용량(사실상 무제한) |
| `pool.keep-alive` | 60s | 유휴 스레드를 회수하기까지의 대기 시간 |
| `pool.allow-core-thread-timeout` | `true` | 코어 스레드도 유휴 시 회수 허용 |
| `thread-name-prefix` | `task-` | 스레드 이름 접두사 |

> 큐가 무제한(`queue-capacity` 기본값)이라, 앞서 본 `ThreadPoolExecutor`의 "큐가 꽉 찬 다음에야 max가 작동한다"가 그대로 적용된다. 즉 기본 상태에서는 작업이 큐에 쌓이기만 하고 `max-size`까지 스레드가 늘지 않아, **사실상 스레드 8개**로 동작한다. 부하에 따라 스레드를 늘리려면 `queue-capacity`를 유한한 값으로 두고 `max-size`를 함께 설정해야 한다.

설정 예:

```properties
spring.task.execution.pool.max-size=16
spring.task.execution.pool.queue-capacity=100
spring.task.execution.pool.keep-alive=10s
```

문서 설명대로, 이렇게 두면 큐가 꽉 찰 때(100개) 풀이 최대 16개까지 늘어나고, 스레드가 10초만 놀아도 회수돼(기본 60초보다 공격적으로) 풀이 줄어든다.

### 커스텀 Executor를 두면 — 자동 설정이 물러난다(back off)

> 컨텍스트에 직접 만든 `Executor` 빈이 있으면 자동 설정은 물러나고, 그 커스텀 `Executor`가 (`@EnableAsync`를 통한) 일반 작업 실행에 쓰인다.

- 단, 스프링 MVC·WebFlux·GraphQL은 여전히 `applicationTaskExecutor`라는 이름의 `AsyncTaskExecutor` 빈을 요구한다.
- `spring.task.execution.mode=force`로 두면, `@Primary`로 등록한 커스텀 `Executor`가 있더라도 자동 설정된 `AsyncTaskExecutor`를 모든 통합 지점에서 강제로 쓴다.

### 스케줄링은 별도 — TaskSchedulingAutoConfiguration

> `@Scheduled`용 풀은 `spring.task.scheduling.*`로 따로 자동 설정된다. 기본은 스레드 1개짜리 `ThreadPoolTaskScheduler`(가상 스레드를 켜면 `SimpleAsyncTaskScheduler`).

| 프로퍼티 (`spring.task.scheduling.*`) | 기본값 | 의미 |
| --- | --- | --- |
| `pool.size` | 1 | 스케줄러 스레드 수 |
| `thread-name-prefix` | `scheduling-` | 스레드 이름 접두사 |

## @Async와 @EnableAsync

> `@Async`로 메서드를 비동기 후보로 표시하고, `@EnableAsync`로 그 기능을 켠다. 실제 비동기 동작은 스프링이 해당 빈을 프록시로 감싸 처리한다.

### @Async — 메서드를 비동기 후보로 표시 + value로 실행기 지정

> [공식문서](https://docs.spring.io/spring-framework/docs/6.2.x-SNAPSHOT/javadoc-api/org/springframework/scheduling/annotation/Async.html)

> 메서드를 비동기 실행 후보로 표시하는 애너테이션이다.

- 타입(클래스) 레벨에도 붙일 수 있고, 그러면 그 타입의 모든 메서드가 비동기로 간주된다.
- 단, `@Configuration` 클래스 안에 선언된 메서드에는 `@Async`를 쓸 수 없다.
- 메서드 시그니처상 파라미터 타입은 무엇이든 된다.
- 반환 타입은 `void` 또는 `Future`로 제한된다.
- `Future`를 쓸 때는 더 구체적인 `CompletableFuture`로 선언하면, 비동기 작업과 더 풍부하게 상호작용하고 후속 처리 단계를 바로 조합할 수 있다.


```java
// org.springframework.scheduling.annotation.Async
@Target({ElementType.TYPE, ElementType.METHOD})
@Retention(RetentionPolicy.RUNTIME)
@Documented
@Reflective
public @interface Async {

	String value() default "";

}
```

**`value` — 어떤 실행기(executor)를 쓸지 지정**

> 해당 비동기 작업에 대한 qualifier 값이다.

- 이 값으로 작업을 실행할 executor를 결정한다. qualifier 값(또는 빈 이름)이 특정 `Executor` 또는 `TaskExecutor` 빈 정의와 매칭된다.
- 클래스 레벨 `@Async`에 지정하면 그 클래스의 모든 메서드에 해당 executor가 쓰인다.
- 메서드 레벨 `value`는 클래스 레벨에 설정된 qualifier 값을 항상 덮어쓴다.
- qualifier 값은 SpEL 표현식(예: `#{environment['myExecutor']}`)이나 프로퍼티 플레이스홀더(예: `${my.app.myExecutor}`)로 주면 동적으로 해석된다.

> **Executor를 써야 하나, TaskExecutor를 써야 하나?** — 둘 다 된다. `value`로 준 이름/qualifier에 맞는 빈을 찾을 때 타입이 `Executor`든 `TaskExecutor`든 상관없다. 순수 `Executor`로 찾히면 스프링이 내부에서 `TaskExecutorAdapter`로 감싸 `AsyncTaskExecutor`로 맞춰 쓴다. (그래서 아래 실습처럼 `@Bean Executor mailExecutor`로 등록해도 동작한다)

### @EnableAsync — 비동기 기능 켜기 + executor 탐색 규칙

> [공식문서](https://docs.spring.io/spring-framework/docs/current/javadoc-api/org/springframework/scheduling/annotation/EnableAsync.html)

> 스프링의 비동기 메서드 실행 기능을 활성화한다.

`MyAsyncBean`은 스프링의 `@Async`, EJB 3.1의 `@jakarta.ejb.Asynchronous`, 또는 `annotation()` 속성으로 지정한 커스텀 애너테이션이 붙은 메서드를 하나 이상 가진 사용자 정의 타입이다. 이 비동기 처리(aspect)는 등록된 빈에 투명하게 더해진다. 예를 들어 다음 설정으로:

```java
@Configuration
public class AnotherAppConfig {

    @Bean
    public MyAsyncBean asyncBean() {
        return new MyAsyncBean();
    }
}
```

**executor 탐색 규칙** — `@EnableAsync`는 `@Async`가 쓸 스레드 풀을 다음 순서로 찾는다.

1. 컨텍스트에 `TaskExecutor` 타입 빈이 **딱 하나** 있으면 그것을 쓴다.
2. 없으면, 이름이 `"taskExecutor"`인 `Executor` 빈을 찾는다.
3. 둘 다 못 찾으면 `SimpleAsyncTaskExecutor`(풀이 아니라 매번 새 스레드)로 비동기 호출을 처리한다.

> 반환 타입이 `void`인 메서드는 예외를 호출자에게 전달할 수 없다. 기본 동작에서는 이런 잡히지 않은 예외를 로그로만 남긴다.

이 동작들을 커스터마이징하려면 `AsyncConfigurer`를 구현해서 다음을 제공한다.

- `getAsyncExecutor()`로 직접 만든 `Executor`
- `getAsyncUncaughtExceptionHandler()`로 직접 만든 `AsyncUncaughtExceptionHandler`

> NOTE: `AsyncConfigurer` 설정 클래스는 애플리케이션 컨텍스트 부트스트랩 초기에 초기화된다. 여기서 다른 빈에 의존해야 한다면, 그 빈들이 다른 후처리기(post-processor)도 거치도록 가능한 한 `lazy`로 선언하는 것이 좋다.

```java
@Configuration
@EnableAsync
public class AppConfig implements AsyncConfigurer {

    @Override
    public Executor getAsyncExecutor() {
        ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
        executor.setCorePoolSize(7);
        executor.setMaxPoolSize(42);
        executor.setQueueCapacity(11);
        executor.setThreadNamePrefix("MyExecutor-");
        executor.initialize();
        return executor;
    }

    @Override
    public AsyncUncaughtExceptionHandler getAsyncUncaughtExceptionHandler() {
        return new MyAsyncUncaughtExceptionHandler();
    }
}

```

### 실습

<details>
<summary>실습 코드 전체 보기</summary>

```java
@Configuration
public class AsyncConfig {

    // @Async가 작업을 던질 실제 실행기. 빈 이름이 "mailExecutor".
    @Bean("mailExecutor")
    public Executor mailExecutor() {
        ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
        executor.setCorePoolSize(2);
        executor.setMaxPoolSize(4);
        executor.setQueueCapacity(100);
        executor.setThreadNamePrefix("mail-");   // 비동기 스레드 이름 → 로그로 확인용
        executor.setRejectedExecutionHandler(new ThreadPoolExecutor.CallerRunsPolicy());
        executor.initialize();
        return executor;
    }
}
```

```java
@Service
public class EmailService {

    // ★ 핵심: 이 메서드는 "mailExecutor" 풀의 스레드에서 비동기로 실행된다.
    @Async("mailExecutor")
    public void send(String to) {
        System.out.println("[send] 실행 스레드 = " + Thread.currentThread().getName());
        sleep(500);
        System.out.println("[send] " + to + " 에게 메일 전송 완료");
    }

    // 결과를 받고 싶으면 CompletableFuture<T> 반환
    @Async("mailExecutor")
    public CompletableFuture<String> sendWithResult(String to) {
        System.out.println("[sendWithResult] 실행 스레드 = " + Thread.currentThread().getName());
        sleep(500);
        return CompletableFuture.completedFuture("sent:" + to);
    }

    // ⚠️ 함정 시연용: 같은 빈 안에서 send()를 직접 호출하면 비동기가 안 된다 (self-invocation)
    public void sendViaSelfCall(String to) {
        System.out.println("[sendViaSelfCall] 실행 스레드 = " + Thread.currentThread().getName());
        this.send(to);   // ← this. 호출이라 프록시를 안 거침 → 동기 실행됨
    }

    private static void sleep(long ms) {
        try { Thread.sleep(ms); } catch (InterruptedException e) { Thread.currentThread().interrupt(); }
    }
}
```

```java
@Component
public class DemoRunner implements CommandLineRunner {

    private final EmailService emailService;

    // 주입받는 emailService는 "진짜 EmailService"가 아니라 스프링이 만든 프록시다.
    public DemoRunner(EmailService emailService) {
        this.emailService = emailService;
    }

    @Override
    public void run(String... args) throws Exception {
        System.out.println("주입된 타입 = " + emailService.getClass().getName()); // ...$$SpringCGLIB$$...
        System.out.println("[caller] 호출 스레드 = " + Thread.currentThread().getName());

        // 1) 일반 비동기 호출: caller 스레드와 다른 mail- 스레드에서 실행됨
        emailService.send("a@test.com");

        // 2) 결과 받는 비동기 호출
        CompletableFuture<String> f = emailService.sendWithResult("b@test.com");
        System.out.println("[caller] future 결과 = " + f.get());  // 끝날 때까지 대기

        // 3) self-invocation 함정: 내부 this.send() 라 동기로 돌아감 (스레드가 안 바뀜)
        emailService.sendViaSelfCall("c@test.com");

        Thread.sleep(1000); // 비동기 작업 출력 보려고 잠깐 대기
    }
}
```

```java
@SpringBootApplication
@EnableAsync   // ★ 이게 있어야 @Async 프록시가 만들어진다 (없으면 그냥 동기 실행)
public class AsyncApplication {
    public static void main(String[] args) {
        SpringApplication.run(AsyncApplication.class, args);
    }
}
```

</details>

### 프록시로 동작한다

> `@Async`가 붙은 빈은 원본이 아니라, 스프링이 AOP로 감싼 CGLIB 프록시로 컨테이너에 등록된다. 메서드 호출을 이 프록시가 가로채 executor로 넘기기 때문에 비동기가 성립한다.

```
@EnableAsync
   │  → AsyncConfigurationSelector 가 동작
   ▼
AsyncAnnotationBeanPostProcessor 등록  (빈 후처리기)
   │  → 컨테이너 기동 시 모든 빈을 훑어서
   │    "@Async 메서드를 가진 빈"을 발견하면
   ▼
그 빈을 'AOP 프록시'로 감싸서 교체
   (Advisor = AsyncAnnotationAdvisor,
    Advice  = AnnotationAsyncExecutionInterceptor)

그래서 컨테이너 안에 들어가는 EmailService 빈은 원본이 아니라, 원본을 감싼 CGLIB 프록시 객체
```

```
DemoRunner (main 스레드)
   │  emailService.send("a@test.com")
   ▼
[프록시.send()]                         ← 진짜 메서드가 아니라 프록시가 먼저 가로챔
   │
   ▼
AsyncExecutionInterceptor.invoke()      ← @Async를 처리하는 AOP advice
   │  1) 이 메서드에 맞는 Executor 결정
   │     → @Async("mailExecutor") 의 값으로
   │       "mailExecutor" 빈을 찾음  (AsyncConfig.java:14)
   │
   │  2) "원본 메서드 호출"을 Callable로 감쌈
   │       Callable task = () -> 원본EmailService.send("a@test.com");
   │
   │  3) executor.submit(task)  ← 풀에 제출하고
   │
   ▼  4) 즉시 리턴 (void라 그냥 반환)   ← 여기서 main 스레드는 바로 다음 줄로!
[main 스레드는 계속 진행]
                                         (한편)
   mail-1 스레드가 task를 꺼내 실행
   → 원본 EmailService.send() 가 mail-1에서 돈다  ← 출력의 "[send] 실행 스레드 = mail-1"
```

프록시가 가로챈 뒤의 핵심 동작은 "원본 메서드 호출을 `Callable`로 감싸 executor에 `submit`하는 것"이다. 실제 advice인 `AsyncExecutionInterceptor#invoke`를 보면 그대로 드러난다.

```java
// org.springframework.aop.interceptor.AsyncExecutionInterceptor#invoke

@Override
@Nullable
@SuppressWarnings("NullAway")
public Object invoke(final MethodInvocation invocation) throws Throwable {
  Class<?> targetClass = (invocation.getThis() != null ? AopUtils.getTargetClass(invocation.getThis()) : null);
  final Method userMethod = BridgeMethodResolver.getMostSpecificMethod(invocation.getMethod(), targetClass);

  AsyncTaskExecutor executor = determineAsyncExecutor(userMethod);
  if (executor == null) {
    throw new IllegalStateException(
      "No executor specified and no default executor set on AsyncExecutionInterceptor either");
  }

  Callable<Object> task = () -> {
    try {
      Object result = invocation.proceed();
      if (result instanceof Future<?> future) {
        return future.get();
      }
    }
    catch (ExecutionException ex) {
      handleError(ex.getCause(), userMethod, invocation.getArguments());
    }
    catch (Throwable ex) {
      handleError(ex, userMethod, invocation.getArguments());
    }
    return null;
  };

  return doSubmit(task, executor, userMethod.getReturnType());
}
```
