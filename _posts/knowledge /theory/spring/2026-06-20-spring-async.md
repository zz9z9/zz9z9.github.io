

> 목표:
> - @Async가 내부적으로 어떻게 동작하는건지 이해
> - 이를 바탕으로, 적절하게 사용 및 주의해야할 사항에 대해 인지하고 사용하기


## Executor
> https://docs.oracle.com/en/java/javase/17/docs/api/java.base/java/util/concurrent/Executor.html
> An object that **executes submitted Runnable tasks.**

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

- This interface provides a way of decoupling task submission from the mechanics of how each task will be run, including details of thread use, scheduling, etc.
- An Executor is normally used instead of explicitly creating threads.
- For example, rather than invoking new Thread(new RunnableTask()).start() for each of a set of tasks, you might use:
Executor executor = anExecutor();
executor.execute(new RunnableTask1());
executor.execute(new RunnableTask2());
...

- 직접 스레드를 만들어서 Runnable을 실행시키지 않고, 실행 방식을 내부적으로 숨기고 처리하게 만들어주는 역할을 부여하는 인터페이스 ??
=> provides a way of decoupling task submission from the mechanics of how each task will be run, including details of thread use, scheduling, etc. ?? 이게 잘 이해가안되네

```
분리 전: task와 실행 방식이 엉켜있음

비동기로 돌리고 싶으면, 작업을 호출하는 쪽이 스레드 생성·관리까지 직접 해야 했어:

// 내가 하고 싶은 "task" = 이메일 보내기
Runnable sendEmail = () -> emailService.send(...);

// 그런데 "어떻게 실행할지"가 호출부에 박혀버림
new Thread(sendEmail).start();   // ← 매번 새 스레드 생성이라는 '방식'이 코드에 고정됨

여기서 문제는, "이메일 보내기"라는 task와 "새 스레드 만들어 거기서 돌린다"는 실행 메커니즘이 한 줄에 붙어있다는 거야. 만약 나중에:

- "새 스레드 말고 스레드 풀에서 돌리자"
- "지금은 그냥 호출한 스레드에서 동기로 돌리자(테스트용)"
- "큐에 쌓아놓고 순차 처리하자"

로 바꾸려면 sendEmail을 호출하는 모든 곳을 다 고쳐야 해. task 제출 코드가 실행 방식에 종속돼 있으니까.

분리 후: Executor가 그 사이를 끊어줌

Runnable sendEmail = () -> emailService.send(...);

executor.execute(sendEmail);   // ← 나는 "이거 실행해줘"라고 '제출'만 함.
                               //    어떻게 돌릴지는 executor가 결정.

호출부는 이제 "무엇을"만 신경 쓰고, "어떻게"는 모름. 그 "어떻게"는 executor가 무엇이냐에 따라 완전히 달라져 — 그런데 호출부 코드는 한 글자도 안 바뀌어:

// 1) 매번 새 스레드
Executor executor = command -> new Thread(command).start();

// 2) 호출한 스레드에서 그냥 동기 실행 (예: 테스트)
Executor executor = command -> command.run();

// 3) 고정 크기 스레드 풀
Executor executor = Executors.newFixedThreadPool(10);

// 4) 단일 스레드로 순차 처리
Executor executor = Executors.newSingleThreadExecutor();

위 4개 중 뭘 주입하든 executor.execute(sendEmail) 호출부는 동일해. 이게 바

- "task submission" = executor.execute(sendEmail) (작업을 던지는 행위)
- "the mechanics of how each task will be run (thread use, scheduling, ...) (새 스레드냐 / 풀이냐 / 동기냐 / 큐잉이냐)
```

```java
@FunctionalInterface
public interface Runnable {
    /**
     * Runs this operation.
     */
    void run();
}
```

## TaskExecutor
> https://docs.spring.io/spring-framework/docs/6.2.x-SNAPSHOT/javadoc-api/org/springframework/core/task/TaskExecutor.html

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

- 왜 `java.util.concurrent.Executor`와 똑같이 생긴거를 하나 더 만든걸까 ?
=> Executor는 jdk 1.5에 만들어짐, spring은 jdk 1.4 버전 호환 유지해야해서 Executor 도입할 수 없었음
-  TaskExecutor(Spring 2.0, 2006)가 java.util.concurrent.Executor(Java 5, 2004)보다 거의 동시대거나, 스프링 입장에서는 JDK 1.4를 여전히 지원해야 했던 시절에 나왔어.

- 스프링은 당시 JDK 1.4 호환성을 유지해야 했는데, java.util.concurrent는 JDK 5부터 들어온 패키지였어.
- 그래서 스프링은 "JDK 버전과 무관하게 우리만의 추상화를 두자"는 의도로 TaskExecutor를 만들었어.
- 나중에 스프링이 JDK 5+ 를 baseline으로 올리면서, TaskExecutor extends Executor 로 정리한 거야. 즉 처음엔 독립적이었다가, 나중에 표준을 상속하도록 합쳐진 형태.
```
┌──────┬───────────────────────────────────────────────┬─────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│      │         java.util.concurrent.Executor         │                                 org.springframework.core.task.TaskExecutor                                  │
├──────┼───────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 소속 │ JDK 표준                                      │ Spring Framework                                                                                            │
├──────┼───────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 의미 │ "이 Runnable을 실행해라" (범용 저수준 추상화) │ "이건 task 실행용이다" — 스프링 추상화의 진입점                                                             │
├──────┼───────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 예외 │ RejectedExecutionException (unchecked)        │ TaskRejectedException (스프링 예외, RejectedExecutionException을 감쌈)                                      │
├──────┼───────────────────────────────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ 역할 │ 단순 실행기                                   │ @Async, AsyncExecutionInterceptor, ThreadPoolTaskExecutor 등 스프링 비동기 인프라의 타입 마커이자 확장 지점 │
└──────┴───────────────────────────────────────────────┴─────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

-  표준/외부 API가 있어도, 스프링은 종종 자기만의 얇은 추상화 인터페이스를 한 겹 더 둔다.

예를 들면:

- Resource — JDK에 File, URL 다 있는데도 스프링은 별도 추상화를 둠
- Environment / PropertySource — 시스템 프로퍼티 직접 안 쓰고 감쌈
- ApplicationEventPublisher — 이벤트도 자기 타입으로
- TaskScheduler — ScheduledExecutorService 있는데도 별도로 둠

왜 이렇게 할까? 확장 지점과 의미(semantic)를 자기가 통제하기 위해서야.

2) TaskExecutor가 줬을 "디커플링과 무관한" 이점들

JDK 이슈가 전혀 없었다고 가정해도, 스프링이 Executor를 그대로 안 쓰고 한 겹 두면 이런 게 가능해져:

- 타입을 통한 의미 부여: "이건 그냥 실행기가 아니라 스프링이 관리하는 task 실행기다"라는 마커. @Async가 컨텍스트에서 빈을 찾을 때 의미 있는 타입이 됨.
- 예외 번역: JDK의 RejectedExecutionException을 스프링 예외 체계(TaskRejectedException)로 감싸 일관성 유지.
- 자유로운 확장: AsyncTaskExecutor(타임아웃, submit), SchedulingTaskExecutor 처럼 스프링이 필요할 때 계층을 덧붙일 자기 소유의 루트를 가짐. java.util.concurrent.Executor는 스프링이 손댈 수 없는 남의 인터페이스니까.

이 세 가지는 JDK 버전과 아무 상관 없는 이점이야.

그래서 결론은

┌─────────────────────────────────────┬────────────────────────────────────────────────────────────────┐
│                가정                 │                              결과                              │
├─────────────────────────────────────┼────────────────────────────────────────────────────────────────┤
│ 디커플링만이 유일한 이유였다면      │ JDK 이슈 없으면 → TaskExecutor 안 만들어졌을 것 ✅ 네 추론대로 │
├─────────────────────────────────────┼────────────────────────────────────────────────────────────────┤
│ 하지만 실제 스프링 설계 철학을 보면 │ JDK 이슈가 없었어도 → 얇은 추상화 한 겹을 뒀을 가능성이 높음   │
└─────────────────────────────────────┴────────────────────────────────────────────────────────────────┘

▎ 한 줄 정리: JDK 호환성은 TaskExecutor를 "지금 당장, 상속도 안 하고" 만들게 한 결정적 방아쇠였다. 하지만 스프링이 외부 표준 위에 자기 추상화를 한 겹 얹는 습관(Resource, Environment 등)을 보면, 그 방아쇠가 없었어도 확장 지점과 예외 번역을 위해 어떤 형태로든 자기 인터페이스를 뒀을 것이라고 보는 게 더 현실적이야.

즉 "안 만들어졌을 수도"는 반은 맞지만, 스프링의 성향상 "그래도 만들었을 것"에 더 무게가 실려.

## ExecutorService
> https://docs.oracle.com/en/java/javase/17/docs/api/java.base/java/util/concurrent/ExecutorService.html
> An Executor that provides methods to manage termination and methods that can produce a Future for tracking progress of one or more asynchronous tasks.
> The Executor implementations provided in this package implement ExecutorService, which is a **more extensive interface.** (Executor 공식문서에서)


Executor는 메서드가 execute(Runnable) 단 하나라서:

// 람다 한 줄로도 구현 가능 — 이게 가능한 건 메서드가 1개뿐이라서
Executor inline = r -> r.run();           // 동기 실행기
Executor newThread = r -> new Thread(r).start();

1) 의존성을 최소로 받을 수 있다. 내 메서드가 "그냥 실행만" 필요하면, 인자를 ExecutorService(메서드 10개)가 아니라 Executor(메서드 1개)로 받는 게 깔끔해. 받는 쪽은 실행만 시킬 수 있고, 실수로 풀을 shutdown 해버릴 수도 없어.

// "나는 이거 실행만 시키면 돼. 풀 생명주기엔 관심 없어"
void process(Executor executor) {
executor.execute(() -> doWork());   // shutdown 같은 건 호출 자체가 불가능 → 안전
}

2) 개념(컨셉)과 운영(기능)을 분리.
- Executor는 "task 제출과 실행을 분리한다"는 순수한 개념만 담은 인터페이스고,
- ExecutorService는 거기에 "실무에서 굴리려면 필요한 것들(결과/종료/일괄)"을 얹은 운영용 인터페이스야.
- 이건 좋은 인터페이스 설계 원칙(인터페이스 분리 원칙, ISP)이기도 해.


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

```java
package java.util.concurrent;

@FunctionalInterface
public interface Callable<V> {

    V call() throws Exception;
}
```


## ThreadPoolExecutor
> https://docs.oracle.com/en/java/javase/17/docs/api/java.base/java/util/concurrent/ThreadPoolExecutor.html
> ExecutorService 실제 구현체 중 하나
> An ExecutorService that executes each submitted task **using one of possibly several pooled threads**, normally configured using Executors factory methods.

- Thread pools address two different problems: they usually provide improved performance when executing large numbers of asynchronous tasks, due to reduced per-task invocation overhead, and they provide a means of bounding and managing the resources, including threads, consumed when executing a collection of tasks. Each ThreadPoolExecutor also maintains some basic statistics, such as the number of completed tasks.

To be useful across a wide range of contexts, this class provides many adjustable parameters and extensibility hooks. However, programmers are urged to use the more convenient Executors factory methods Executors.newCachedThreadPool() (unbounded thread pool, with automatic thread reclamation), Executors.newFixedThreadPool(int) (fixed size thread pool) and Executors.newSingleThreadExecutor() (single background thread), that preconfigure settings for the most common usage scenarios. Otherwise, use the following guide when manually configuring and tuning this class:

### 핵심 동작

작업이 들어왔을 때의 결정 순서

새 task 도착
│
├─ 현재 스레드 < corePoolSize ?
│     예 → ★새 스레드 생성★ (놀고 있는 스레드 있어도 무조건 만듦)
│
├─ core 다 찼으면 → 큐에 넣기 시도
│     큐에 자리 있음 → ★큐에 적재★ (스레드 추가 안 함)
│
└─ 큐도 꽉 참 → 현재 스레드 < maxPoolSize ?
예 → ★새 스레드 생성★ (core 초과분, 임시 스레드)
아니오 → ★거부(Rejected)★ → RejectedExecutionHandler 발동

여기서 반드시 알아야 할 반직관적 포인트 ⚠️

▎ maximumPoolSize는 "큐가 꽉 찬 다음"에야 작동한다.

많은 사람이 "부하 높으면 core → max까지 스레드가 늘겠지"라고 오해하는데, 실제론 core가 차면 max보다 큐를 먼저 채워. 그래서:

- 큐가 무한대(LinkedBlockingQueue 무제한)면 → 큐가 절대 안 차니까 → maxPoolSize는 영원히 안 쓰임. 스레드는 corePoolSize에서 멈춤. (문서의 "maximumPoolSize therefore doesn't have any effect"가 이 말)

core=5, max=50, queue=무제한  →  실제 최대 스레드 = 5 (max 50은 장식)

- max를 진짜 쓰려면 큐를 유한하게 둬야 해. 그래야 큐가 차고 → 그제서야 core 초과 스레드가 생겨.

각 설정 한 줄 설명

┌──────────────────────────┬────────────────────────────────────────────────────────┬─────────────────────────────────────────────────────┐
│           설정           │                          의미                          │                      튜닝 감각                      │
├──────────────────────────┼────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────┤
│ corePoolSize             │ 평상시 유지하는 기본 스레드 수. 유휴여도(기본) 안 죽음 │ 정상 부하를 감당할 수 (CPU 작업이면 ≈ 코어 수)      │
├──────────────────────────┼────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────┤
│ maxPoolSize              │ 큐가 꽉 찼을 때만 늘어나는 상한                        │ 큐가 유한해야 의미 있음                             │
├──────────────────────────┼────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────┤
│ queueCapacity            │ core가 다 찼을 때 대기시킬 작업 수                     │ 크면 스레드 ↓·지연 ↑ / 작으면 스레드 ↑·throughput ↑ │
├──────────────────────────┼────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────┤
│ keepAliveSeconds         │ core 초과 스레드가 이 시간 놀면 회수                   │ 버스트 끝난 뒤 임시 스레드 정리                     │
├──────────────────────────┼────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────┤
│ allowCoreThreadTimeOut   │ core 스레드도 keepAlive로 죽게 허용                    │ true면 한가할 때 스레드 0까지 감소                  │
├──────────────────────────┼────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────┤
│ rejectedExecutionHandler │ 큐+max 다 차서 못 받을 때 정책                         │ 아래 4종                                            │
└──────────────────────────┴────────────────────────────────────────────────────────┴─────────────────────────────────────────────────────┘

거부 정책(RejectedExecutionHandler) 4종

┌─────────────────────┬───────────────────────────────────────────────────────────┐
│        정책         │                           동작                            │
├─────────────────────┼───────────────────────────────────────────────────────────┤
│ AbortPolicy (기본)  │ RejectedExecutionException 던짐                           │
├─────────────────────┼───────────────────────────────────────────────────────────┤
│ CallerRunsPolicy    │ 제출한 스레드가 직접 실행 → 제출 속도 자연 감속(백프레셔) │
├─────────────────────┼───────────────────────────────────────────────────────────┤
│ DiscardPolicy       │ 조용히 버림                                               │
├─────────────────────┼───────────────────────────────────────────────────────────┤
│ DiscardOldestPolicy │ 큐 맨 앞(오래된) 것 버리고 재시도                         │
└─────────────────────┴───────────────────────────────────────────────────────────┘

▎ 실무에서 백프레셔가 필요하면 CallerRunsPolicy가 많이 쓰여 — 풀이 포화되면 제출자(예: 요청 처리 스레드)가 직접 일을 처리하게 해서 유입 속도를 자연스럽게 늦춤.

## ThreadPoolTaskExecutor
> https://docs.spring.io/spring-framework/docs/current/javadoc-api/org/springframework/scheduling/concurrent/ThreadPoolTaskExecutor.html

- JavaBean that allows for configuring a ThreadPoolExecutor in bean style (through its "corePoolSize", "maxPoolSize", "keepAliveSeconds", "queueCapacity" properties) and exposing it as a Spring TaskExecutor. This class is also well suited for management and monitoring (for example, through JMX), providing several useful attributes: "corePoolSize", "maxPoolSize", "keepAliveSeconds" (all supporting updates at runtime); "poolSize", "activeCount" (for introspection only).
  The default configuration is a core pool size of 1, with unlimited max pool size and unlimited queue capacity. This is roughly equivalent to Executors.newSingleThreadExecutor(), sharing a single thread for all tasks. Setting "queueCapacity" to 0 mimics Executors.newCachedThreadPool(), with immediate scaling of threads in the pool to a potentially very high number. Consider also setting a "maxPoolSize" at that point, as well as possibly a higher "corePoolSize" (see also the "allowCoreThreadTimeOut" mode of scaling).

NOTE: This class implements Spring's TaskExecutor interface as well as the Executor interface, with the former being the primary interface, the other just serving as secondary convenience. For this reason, the exception handling follows the TaskExecutor contract rather than the Executor contract, in particular regarding the TaskRejectedException.

For an alternative, you may set up a ThreadPoolExecutor instance directly using constructor injection, or use a factory method definition that points to the Executors class. To expose such a raw Executor as a Spring TaskExecutor, simply wrap it with a ConcurrentTaskExecutor adapter.

- ThreadPoolExecutor를 감싼 클래스
- 핵심 동작들(스레드 풀링 관련)은 ThreadPoolExecutor 사용
- 편의 기능 등을 좀 더 제공

### 어떤 추가적인 기능 ?
포장지(ThreadPoolTaskExecutor)가 더해주는 3가지

1) 빈(Bean) 스타일 설정 — setter/프로퍼티로 구성

JDK ThreadPoolExecutor는 생성자에 인자를 7개나 넣어야 만들어져:

// JDK 직접 — 생성자 한 방에 다 넣어야 함 (스프링 설정과 안 어울림)
new ThreadPoolExecutor(5, 10, 60L, TimeUnit.SECONDS,
new LinkedBlockingQueue<>(100),
threadFactory, rejectedHandler);

반면 ThreadPoolTaskExecutor는 JavaBean 이라 setter(프로퍼티)로 설정해. 그래서 스프링 @Bean이나 XML, @ConfigurationProperties와 자연스럽게 붙어:

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

▎ 네가 인용한 "configuring a ThreadPoolExecutor in bean style (through its corePoolSize, maxPoolSize... properties)"가 바로 이 얘기야.

2) 스프링 생명주기와 연동 — shutdown 자동 호출

이게 실무에서 제일 큰 이점이야. 앞에서 "풀 안 끄면 스레드 누수 / JVM 안 죽음" 얘기했지? ThreadPoolTaskExecutor는 스프링 컨테이너 생명주기에 묶여서 그걸 자동으로 해줘:

- 스프링이 빈을 만들 때 → initialize()로 내부 풀 생성 (InitializingBean)
- 스프링 컨텍스트가 닫힐 때 → 자동으로 shutdown() 호출 (DisposableBean)

// 내가 shutdown을 직접 안 불러도, 앱 종료 시 스프링이 알아서 풀을 정리해줌

JDK ThreadPoolExecutor를 날것으로 빈 등록하면 이 자동 종료가 안 돼서, graceful shutdown이 깔끔하지 않을 수 있어.

3) 스프링 TaskExecutor 타입으로 노출 + 예외 번역

여기서 드디어 TaskExecutor가 왜 필요했는지가 연결돼. ThreadPoolTaskExecutor는 스프링의 TaskExecutor 타입이라:

- @Async가 이걸 찾아 쓸 수 있어. (@Async는 TaskExecutor/Executor 타입 빈을 찾음)
- 작업 거부 시 JDK의 RejectedExecutionException 대신 스프링 예외 TaskRejectedException을 던져 — 일관성.

4) 추가적인 설정

┌─────────────────────────────────┬──────────────────────────┬───────────────┐
│ ThreadPoolTaskExecutor 프로퍼티 │  JDK ThreadPoolExecutor  │     비고      │
├─────────────────────────────────┼──────────────────────────┼───────────────┤
│ corePoolSize                    │ corePoolSize             │ 그대로        │
├─────────────────────────────────┼──────────────────────────┼───────────────┤
│ maxPoolSize                     │ maximumPoolSize          │ 이름만 줄임   │
├─────────────────────────────────┼──────────────────────────┼───────────────┤
│ keepAliveSeconds                │ keepAliveTime            │ 단위 고정(초) │
├─────────────────────────────────┼──────────────────────────┼───────────────┤
│ allowCoreThreadTimeOut          │ allowCoreThreadTimeOut   │ 그대로        │
├─────────────────────────────────┼──────────────────────────┼───────────────┤
│ threadFactory                   │ ThreadFactory            │ 그대로        │
├─────────────────────────────────┼──────────────────────────┼───────────────┤
│ rejectedExecutionHandler        │ RejectedExecutionHandler │ 그대로        │
├─────────────────────────────────┼──────────────────────────┼───────────────┤
│ prestartAllCoreThreads          │ prestartAllCoreThreads() │ 그대로        │
└─────────────────────────────────┴──────────────────────────┴───────────────┘

   (B) 스프링이 자기 식으로 바꾼 것 ⭐ — queueCapacity

이게 제일 중요해. JDK는 BlockingQueue 객체를 직접 넣어야 해:

// JDK: 큐 객체를 내가 골라서 직접 줌
new ThreadPoolExecutor(..., new LinkedBlockingQueue<>(100));

근데 스프링은 큐 객체 대신 queueCapacity라는 int 하나만 받고, 그 값으로 큐 종류를 내부에서 자동 결정해:

// ThreadPoolTaskExecutor 내부 로직 (단순화)
if (queueCapacity > 0) {
return new LinkedBlockingQueue<>(queueCapacity);  // 용량 있는 큐
} else {
return new SynchronousQueue<>();                  // 0이면 직접 핸드오프 큐
}

▎ 그래서 네가 앞서 인용한 "queueCapacity를 0으로 두면 newCachedThreadPool처럼 동작" 이 이 분기 때문이야. 이건 JDK엔 없는 스프링만의 편의 추상화야.

(C) 스프링이 새로 추가한 것 — JDK엔 아예 없음

┌──────────────────────────────────┬───────────────────────────────────────────────────────────────────────────────────┐
│         스프링 추가 설정             │                                       역할                                        │
├──────────────────────────────────┼───────────────────────────────────────────────────────────────────────────────────┤
│ threadNamePrefix                 │ 스레드 이름 접두사(async-1...). JDK에선 ThreadFactory를 직접 짜야 했던 걸 한 줄로 │
├──────────────────────────────────┼───────────────────────────────────────────────────────────────────────────────────┤
│ waitForTasksToCompleteOnShutdown │ 종료 시 남은 작업을 마칠지(shutdown) 즉시 끊을지(shutdownNow) 선택                │
├──────────────────────────────────┼───────────────────────────────────────────────────────────────────────────────────┤
│ awaitTerminationSeconds          │ 종료 시 최대 몇 초 기다릴지 (graceful shutdown 타임아웃)                          │
├──────────────────────────────────┼───────────────────────────────────────────────────────────────────────────────────┤
│ taskDecorator                    │ 작업을 실행 직전에 감싸는 훅 (예: ThreadLocal/MDC/보안컨텍스트 전파)              │
├──────────────────────────────────┼───────────────────────────────────────────────────────────────────────────────────┤
│ initialize() 생명주기              │ 스프링 빈 초기화/소멸에 풀 생성·종료를 연결                                       │
└──────────────────────────────────┴───────────────────────────────────────────────────────────────────────────────────┘

→ 특히 waitForTasksToCompleteOnShutdown + awaitTerminationSeconds는 앞에서 본 "표준 shutdown + shutdownNow 조합 패턴"을 프로퍼티로 노출한 거야. taskDecorator도 JDK엔 없는 스프링 고유 훅.

## Executor 붙은것들 정리

```
     ┌──────────────── JDK ────────────────┐     ┌──────────── Spring ────────────┐
        Executor ──────────────────────────────────▶ TaskExecutor
           │ (extends)                                   │ (extends)
        ExecutorService                              AsyncTaskExecutor
           │                                             │ (구현)
        ThreadPoolExecutor ◀───────── has-a ──────── ThreadPoolTaskExecutor
        (진짜 풀)                    (감쌈)          (빈 설정 + 생명주기 + @Async 연동)
```

```
1) JDK 세계 (java.util.concurrent)

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

JDK 한 줄 요약: Executor(개념) → ExecutorService(실무 인터페이스) → ThreadPoolExecutor(실제 구현). Executors는 그 구현을 쉽게 찍어주는 공장.

2) 스프링 세계 (org.springframework.*)

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

```
┌───────────────────────────┬────────┬─────────────┬──────────────────────────────────────────────────────────────────┐
│           이름            │  세계  │    종류     │                               역할                               │
├───────────────────────────┼────────┼─────────────┼──────────────────────────────────────────────────────────────────┤
│ Executor                  │ JDK    │ 인터페이스  │ 최소 추상화. execute(Runnable)                                   │
├───────────────────────────┼────────┼─────────────┼──────────────────────────────────────────────────────────────────┤
│ ExecutorService           │ JDK    │ 인터페이스  │ + 결과/종료/일괄. 실무 인터페이스                                │
├───────────────────────────┼────────┼─────────────┼──────────────────────────────────────────────────────────────────┤
│ ScheduledExecutorService  │ JDK    │ 인터페이스  │ + 지연/주기 실행                                                 │
├───────────────────────────┼────────┼─────────────┼──────────────────────────────────────────────────────────────────┤
│ ThreadPoolExecutor        │ JDK    │ 클래스      │ 실제 스레드 풀 (core/max/queue)                                  │
├───────────────────────────┼────────┼─────────────┼──────────────────────────────────────────────────────────────────┤
│ Executors                 │ JDK    │ 유틸 클래스 │ 풀 팩토리 (newFixedThreadPool…, newVirtualThreadPerTaskExecutor) │
├───────────────────────────┼────────┼─────────────┼──────────────────────────────────────────────────────────────────┤
│ TaskExecutor              │ Spring │ 인터페이스  │ 스프링 진입점 (extends Executor)                                 │
├───────────────────────────┼────────┼─────────────┼──────────────────────────────────────────────────────────────────┤
│ AsyncTaskExecutor         │ Spring │ 인터페이스  │ + submit/Future. @Async가 요구                                   │
├───────────────────────────┼────────┼─────────────┼──────────────────────────────────────────────────────────────────┤
│ ThreadPoolTaskExecutor    │ Spring │ 클래스      │ JDK 풀을 감싼 스프링 빈 (플랫폼 스레드, 재사용)                  │
├───────────────────────────┼────────┼─────────────┼──────────────────────────────────────────────────────────────────┤
│ VirtualThreadTaskExecutor │ Spring │ 클래스      │ 작업마다 새 가상 스레드(JDK 21+). 풀 아님, I/O 바운드에 강함     │
├───────────────────────────┼────────┼─────────────┼──────────────────────────────────────────────────────────────────┤
│ SimpleAsyncTaskExecutor   │ Spring │ 클래스      │ 작업마다 새 스레드(플랫폼, setVirtualThreads(true)로 가상도)     │
├───────────────────────────┼────────┼─────────────┼──────────────────────────────────────────────────────────────────┤
│ ConcurrentTaskExecutor    │ Spring │ 클래스      │ 기존 JDK Executor를 TaskExecutor로 노출                          │
└───────────────────────────┴────────┴─────────────┴──────────────────────────────────────────────────────────────────┘
```

## 스레드풀, ThreadPoolExecutor ?
> https://zz9z9.github.io/posts/java-threadpool-executor-framework/#threadpoolexecutor

스프링부트 기본 동작 ?
메인 스레드, was 내에 스레드 ??
virtual thread ?
CompletableFuture ? -> ForkJoinPool ?

## 스레드풀 관련 스프링부트 기본 동작 ?


## @Async ? 동작 방식과 신경써야할 부분
> https://docs.spring.io/spring-framework/docs/6.2.x-SNAPSHOT/javadoc-api/org/springframework/scheduling/annotation/Async.html
> Annotation that marks a method as a candidate for asynchronous execution.

- Can also be used at the type level, in which case all the type's methods are considered as asynchronous.
- Note, however, that @Async is not supported on methods declared within a @Configuration class.
- In terms of target method signatures, any parameter types are supported.
- However, the return type is constrained to either void or Future.
- In the latter case, you may declare the more specific CompletableFuture type which allows for richer interaction with the asynchronous task and for immediate composition with further processing steps.


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

**value**
> A qualifier value for the specified asynchronous operation(s).
- May be used to determine the target executor to be used when executing the asynchronous operation(s), matching the qualifier value (or the bean name) of a specific `Executor` or `TaskExecutor` bean definition.

- When specified in a class-level @Async annotation, indicates that the given executor should be used for all methods within the class.
- Method-level use of Async#value always overrides any qualifier value configured at the class level.
- The qualifier value will be resolved dynamically if supplied as a SpEL expression (for example, "#{environment['myExecutor']}") or a property placeholder (for example, "${my.app.myExecutor}").

matching the qualifier value (or the bean name) of a specific `Executor` or `TaskExecutor` bean definition.
=> 그럼 Executor 구현한거 써야되나 TaskExecutor 규현한거 써야되나 ?

## @EnableAsync
> https://docs.spring.io/spring-framework/docs/current/javadoc-api/org/springframework/scheduling/annotation/EnableAsync.html
> Enables Spring's asynchronous method execution capability

MyAsyncBean is a user-defined type with one or more methods annotated with either Spring's @Async annotation, the EJB 3.1 @jakarta.ejb.Asynchronous annotation, or any custom annotation specified via the annotation() attribute. The aspect is added transparently for any registered bean, for instance via this configuration:

```java
@Configuration
public class AnotherAppConfig {

    @Bean
    public MyAsyncBean asyncBean() {
        return new MyAsyncBean();
    }
}
```

By default, Spring will be searching for an associated thread pool definition: either a unique TaskExecutor bean in the context, or an Executor bean named "taskExecutor" otherwise. If neither of the two is resolvable, a SimpleAsyncTaskExecutor will be used to process async method invocations. Besides, annotated methods having a void return type cannot transmit any exception back to the caller. By default, such uncaught exceptions are only logged.

To customize all this, implement AsyncConfigurer and provide:

your own Executor through the getAsyncExecutor() method, and
your own AsyncUncaughtExceptionHandler through the getAsyncUncaughtExceptionHandler() method.
NOTE: AsyncConfigurer configuration classes get initialized early in the application context bootstrap. If you need any dependencies on other beans there, make sure to declare them 'lazy' as far as possible in order to let them go through other post-processors as well.

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

**흐름**

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

- task를 Callable로 만들어서 executor에 submit한다
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



## 질문

```
❯        ├── ThreadPoolExecutor (class) ★      ← 진짜 스레드 풀 (core/max/queue/거부정책)
                   │      │
                   │      └── ScheduledThreadPoolExecutor ← ThreadPoolExecutor + 스케줄링
                   │
                   └── ForkJoinPool (class)               ← work-stealing 풀 (병렬 스트림 등)

  근데 여기 보면 두 축이 있잖아 ForkJoinPool은 CompletableFuture랑 관련있다고 들은것 같은데, CompletableFuture가 리턴타입말고 비동기 실행도 가능하지 않나 ? 정리좀 해줄래 ?

좋은 연결이야. 네가 짚은 "두 축"이 정확히 핵심이고, 거기에 CompletableFuture가 어떻게 얽히는지가 빠진 고리야. 정리할게.

먼저 "두 축"이 뭔지

ExecutorService
   ├── ThreadPoolExecutor      ← [축 A] "내가 설정하는" 일반 풀 (core/max/queue)
   └── ForkJoinPool            ← [축 B] "work-stealing" 풀 (분할정복/병렬, 공용 풀)

둘 다 ExecutorService지만 설계 철학이 달라:

- ThreadPoolExecutor: 작업을 하나의 공유 큐에 쌓고 워커들이 꺼내감. 네가 풀 크기/큐를 직접 튜닝. 일반적인 비동기 작업·@Async용.
- ForkJoinPool: 워커마다 자기 큐(deque) 를 갖고, 자기 큐가 비면 남의 큐 꼬리에서 작업을 훔쳐(work-stealing) 옴. 큰 작업을 잘게 쪼개(fork) 병렬 처리하고 합치는(join) 데 최적화.

ForkJoinPool — 그리고 "공용 풀(common pool)"

ForkJoinPool이 중요한 이유는 JVM에 기본으로 떠 있는 공용 풀이 있기 때문이야:

ForkJoinPool.commonPool()   // JVM 전역 공유 풀, 기본 병렬도 = CPU 코어 수 - 1

그리고 이 공용 풀이 두 군데에서 기본 실행기로 쓰여:

1. 병렬 스트림 — list.parallelStream()...
2. CompletableFuture의 *Async 메서드 (executor 안 넘기면) ← 네가 들은 게 이거야

▎ 그래서 "ForkJoinPool과 CompletableFuture가 관련 있다"는 말이 맞아. CompletableFuture의 비동기 실행은 기본적으로 ForkJoinPool.commonPool()에서 돈다.

CompletableFuture의 두 얼굴 ⭐

네 직관이 정확해. CompletableFuture는 단순한 "리턴 타입(결과 핸들)"이 아니라, 비동기 실행을 직접 띄우는 도구이기도 해. 두 역할로 나눠보자:

역할 1: 결과 핸들 (Future의 강화판)

Future처럼 결과를 담지만, 콜백 체이닝/조합이 돼:

future.thenApply(x -> x + 1)        // 결과 변환
      .thenCompose(x -> other(x))   // 다른 비동기 작업으로 연결
      .thenCombine(f2, (a, b) -> …)  // 두 결과 합치기
      .exceptionally(ex -> fallback) // 예외 처리

(@Async 메서드 반환 타입으로 이걸 쓰는 게 이 역할이야)

역할 2: 비동기 실행 런처 ★ (네가 물은 부분)

static 메서드로 작업을 직접 풀에 던질 수 있어:

// 결과 있는 비동기 실행 (Supplier)
CompletableFuture<String> f =
    CompletableFuture.supplyAsync(() -> {
        System.out.println(Thread.currentThread().getName()); // ForkJoinPool.commonPool-worker-1
        return loadData();
    });
// → executor 안 넘김 → ForkJoinPool.commonPool()에서 실행됨!

// 결과 없는 비동기 실행 (Runnable)
CompletableFuture<Void> f2 =
    CompletableFuture.runAsync(() -> doSomething());

즉 supplyAsync/runAsync/thenApplyAsync 같은 *Async 계열이 "비동기 실행"을 일으키는 진입점이야. 이건 ExecutorService.submit()과 같은 일을 하는 거고, 기본 실행기가 commonPool 인 거지.

핵심: executor를 명시하면 풀을 바꿀 수 있다

*Async 메서드는 두 번째 인자로 Executor를 받는 오버로드가 있어. 안 넘기면 commonPool, 넘기면 그 풀에서 실행:

ExecutorService myPool = Executors.newFixedThreadPool(4);

CompletableFuture.supplyAsync(() -> work(), myPool);   // ← 내 풀에서 실행
//                                          ^^^^^^ commonPool 대신 지정

▎ ⚠️ 실무 팁: commonPool은 JVM 전역 공유라, 거기서 블로킹 I/O를 오래 돌리면 병렬 스트림 등 다른 곳까지 굶주려. 그래서 블로킹 작업엔 commonPool 말고 전용 Executor를 넘기는 게 정석이야.

정리: submit vs CompletableFuture

┌───────────────┬───────────────────────────┬─────────────────────────────────────────┐
│               │ executor.submit(callable) │ CompletableFuture.supplyAsync(supplier) │
├───────────────┼───────────────────────────┼─────────────────────────────────────────┤
│ 반환          │ Future<T>                 │ CompletableFuture<T>                    │
├───────────────┼───────────────────────────┼─────────────────────────────────────────┤
│ 조합/콜백     │ ❌ (get()으로 블로킹만)   │ ✅ thenApply/thenCompose…               │
├───────────────┼───────────────────────────┼─────────────────────────────────────────┤
│ 기본 실행기   │ (그 executor)             │ ForkJoinPool.commonPool()               │
├───────────────┼───────────────────────────┼─────────────────────────────────────────┤
│ executor 지정 │ 그 자체가 executor        │ 2번째 인자로 가능                       │
├───────────────┼───────────────────────────┼─────────────────────────────────────────┤
│ 예외 처리     │ get()에서 터짐            │ exceptionally/handle                    │
└───────────────┴───────────────────────────┴─────────────────────────────────────────┘

@Async와의 관계 — 헷갈리지 말 것

세 가지는 별개의 비동기 실행 진입점이야:

1. executor.submit(task)               ← 직접 풀에 던짐
2. CompletableFuture.supplyAsync(task) ← commonPool(또는 지정 풀)에 던짐
3. @Async 메서드 호출                    ← 프록시가 TaskExecutor.submit으로 던짐

특히 @Async와 CompletableFuture를 섞을 때 주의:

@Async("mailExecutor")
public CompletableFuture<String> send() {
    // 여기 본문은 이미 mailExecutor 스레드에서 돈다 (@Async가 띄움)
    return CompletableFuture.completedFuture("done");  // ← completedFuture! supplyAsync 아님
}

@Async 메서드 안에서는 이미 비동기 스레드라, 보통 completedFuture(...)로 결과만 감싸서 반환해. 여기서 또 supplyAsync를 쓰면 commonPool로 한 번 더 비동기가 일어나 이중으로 떠버려(스레드 두 번 점프). 의도한 게 아니면 피해야 해.

전체 그림

ExecutorService
 ├── ThreadPoolExecutor ── 일반 비동기/@Async (네가 설정하는 풀)
 └── ForkJoinPool
        └── commonPool() ──┬── parallelStream()
                           └── CompletableFuture.*Async(executor 생략 시 기본값)

CompletableFuture
   ├── [런처]  supplyAsync/runAsync/*Async  → 풀에 작업 제출 (기본 commonPool)
   └── [핸들]  thenApply/thenCompose/exceptionally → 결과 조합·콜백

한 줄 정리

▎ ForkJoinPool은 ThreadPoolExecutor와 다른 축의 풀(work-stealing)이고, 그 공용 풀(commonPool)이 CompletableFuture의 *Async 메서드와 병렬 스트림의 기본 실행기다. 그리고 네 말대로 CompletableFuture는 리턴 타입일 뿐 아니라 supplyAsync/runAsync로 비동기 실행을 직접 띄우는 런처이기도 하다 — executor를 안 넘기면 commonPool, 넘기면 지정한 풀에서 돈다. 단 commonPool은 전역 공유라 블로킹 작업엔 전용 Executor를 넘기는 게 정석이고, @Async 메서드 안에서는 보통 completedFuture로 결과만 감싸 이중 비동기를 피한다.

CompletableFuture의 조합(thenCompose vs thenApply, thenCombine, allOf/anyOf)이나 예외 처리(exceptionally/handle)를 코드로 더 파볼까? 아니면 지금까지 내용을 블로그 글로 묶어줄까?

✻ Cooked for 58s

❯ 큰 작업을 잘게 쪼개(fork) 병렬 처리하고 합치는(join) 데 최적화.
  => 예시좀

ForkJoinPool의 fork/join은 RecursiveTask(결과 있음) 또는 RecursiveAction(결과 없음) 으로 쓰는 게 정석이야. 고전 예제인 "1부터 N까지 합"으로 보여줄게 — 단순 합이지만 분할정복 구조가 명확히 드러나.

예제: 큰 배열 합을 fork/join으로

import java.util.concurrent.RecursiveTask;
import java.util.concurrent.ForkJoinPool;

public class SumTask extends RecursiveTask<Long> {

    private static final int THRESHOLD = 10_000;  // 이보다 작으면 그냥 직접 계산
    private final long[] arr;
    private final int start, end;

    SumTask(long[] arr, int start, int end) {
        this.arr = arr; this.start = start; this.end = end;
    }

    @Override
    protected Long compute() {
        int length = end - start;

        // ① 충분히 작으면 → 쪼개지 말고 직접 계산 (base case)
        if (length <= THRESHOLD) {
            long sum = 0;
            for (int i = start; i < end; i++) sum += arr[i];
            return sum;
        }

        // ② 크면 → 반으로 쪼갠다 (divide)
        int mid = (start + end) / 2;
        SumTask left  = new SumTask(arr, start, mid);
        SumTask right = new SumTask(arr, mid, end);

        // ③ fork: 왼쪽을 풀의 다른 스레드에 비동기로 던짐
        left.fork();

        // ④ 오른쪽은 '현재 스레드'가 직접 계산 (재귀)
        Long rightResult = right.compute();

        // ⑤ join: 던졌던 왼쪽 결과를 기다려서 받음
        Long leftResult = left.join();

        // ⑥ 합친다 (conquer)
        return leftResult + rightResult;
    }

    public static void main(String[] args) {
        long[] arr = new long[10_000_000];
        for (int i = 0; i < arr.length; i++) arr[i] = i + 1;

        ForkJoinPool pool = ForkJoinPool.commonPool();   // 공용 풀 사용
        long result = pool.invoke(new SumTask(arr, 0, arr.length));

        System.out.println("합 = " + result);  // 50000005000000
    }
}

핵심 패턴 3개

이 코드의 compute()가 fork/join의 정형 패턴이야:

compute() {
    if (작업이 작으면) return 직접계산();      // base case (쪼개기 멈춤)

    반으로 분할;
    left.fork();              // 왼쪽 → 다른 스레드로 (비동기)
    right.compute();          // 오른쪽 → 내가 직접 (재귀)
    left.join();              // 왼쪽 결과 회수
    return left + right;      // 합치기
}

┌───────────┬──────────────────────────────────────────────────────┐
│  메서드   │                         의미                         │
├───────────┼──────────────────────────────────────────────────────┤
│ fork()    │ 이 하위작업을 현재 워커의 큐에 넣어 비동기 실행 예약 │
├───────────┼──────────────────────────────────────────────────────┤
│ compute() │ 현재 스레드에서 직접 실행 (재귀 분할)                │
├───────────┼──────────────────────────────────────────────────────┤
│ join()    │ fork한 작업의 결과를 기다려 받음                     │
└───────────┴──────────────────────────────────────────────────────┘

▎ 팁: left.fork() 하고 right는 compute()로 직접 하는 게 관용구야. 둘 다 fork하면 현재 스레드가 놀게 돼서 비효율. "하나는 던지고, 하나는 내가 하고, 던진 거 회수"가 표준.

분할 트리 (어떻게 쪼개지나)

[0, 10_000_000) 이 THRESHOLD까지 반씩 쪼개지는 모습:

                [0 ~ 10,000,000)
                 /            \
        [0~5,000,000)      [5,000,000~10,000,000)
          /       \              /        \
       ...        ...          ...        ...
        │
   (10,000 이하가 될 때까지 계속 쪼갬)
        │
   [0~10,000)  ← 여기서 멈추고 for문으로 직접 합산

리프(leaf) 조각들이 여러 스레드에 분산돼 동시에 계산되고, join으로 올라오며 합쳐져.

work-stealing이 여기서 빛나는 이유

ForkJoinPool이 일반 풀과 다른 점이 이 fork/join에서 드러나:

워커1 큐: [작업A, 작업B, 작업C]   ← fork된 하위작업들이 자기 큐에 쌓임
워커2 큐: []  ← 비었다!

→ 워커2가 놀지 않고 워커1 큐의 '꼬리'에서 작업C를 훔쳐옴 (work-stealing)

- 각 워커가 자기 deque를 갖고, fork한 작업을 자기 큐 머리(head)에 넣고 거기서 꺼내 씀(LIFO → 캐시 친화적).
- 놀고 있는 워커는 바쁜 워커 큐의 꼬리(tail)에서 훔쳐옴(FIFO).
- 덕분에 작업이 불균등하게 쪼개져도 부하가 자동으로 분산돼. → 분할정복처럼 "작업이 동적으로 계속 생기는" 상황에 최적.

일반 ThreadPoolExecutor(공유 큐 하나)는 이런 재귀적 작업 생성에서 큐 경합이 심한데, ForkJoinPool은 워커별 큐 + 훔치기로 이를 피해.

현실에선 직접 안 짜도 된다

사실 위 "배열 합" 같은 건 병렬 스트림이 내부적으로 ForkJoinPool로 똑같이 해줘:

long sum = java.util.stream.LongStream.rangeClosed(1, 10_000_000)
                .parallel()        // ← 내부적으로 ForkJoinPool.commonPool() + fork/join
                .sum();

parallelStream()/.parallel()이 바로 이 fork/join 분할정복을 자동으로 적용하는 거야. RecursiveTask를 직접 쓰는 건 스트림으로 표현 안 되는 커스텀 분할 로직(트리 순회, 재귀적 탐색 등)이 필요할 때야.

한 줄 정리

▎ fork/join은 RecursiveTask/RecursiveAction의 compute()에서 "작으면 직접 계산, 크면 반으로 쪼개 fork()(던지고) → compute()(직접) → join()(회수) → 합치기" 패턴으로 큰 작업을 분할정복한다. ForkJoinPool은 워커별 큐 + work-stealing으로 이렇게 동적으로 생기는 하위작업의 부하를 자동 분산하며, 병렬 스트림이 내부적으로 이 메커니즘을 그대로 사용한다.

✻ Cooked for 42s

❯ 실무에서 이런 케이스는 잘 와닿지 않는것 같은데, api 호출이나 기타 실제로 이걸 적용할만한 부분이 있나 ?

아주 현실적인 질문이고, 솔직히 말하면 RecursiveTask로 직접 fork/join 짜는 건 일반적인 API 백엔드에선 거의 안 써. 그건 CPU 바운드 분할정복용이라, I/O(API 호출)가 대부분인 웹 서버 일과는 결이 달라. 정직하게 나눠서 정리할게.

1) fork/join(RecursiveTask)을 "직접" 쓸 일은 드물다

RecursiveTask가 진짜 맞는 자리는 CPU 바운드 + 재귀적 분할이야:

- 메모리에 올린 대용량 데이터 집계/변환 (수백만 건 in-memory 합산·필터)
- 이미지/영상 처리, 대형 행렬 연산
- 거대한 트리/그래프 재귀 탐색

전형적인 CRUD/API 서버는 "DB 갔다가 → 외부 API 부르고 → JSON 말아서 응답"이라 CPU를 쪼갤 큰 덩어리가 별로 없어. 그래서 RecursiveTask를 손으로 짜는 건 평생 몇 번 안 해.

2) 대신 fork/join은 "간접적으로" 이미 쓰고 있다

직접 안 짜도 JDK가 내부에서 ForkJoinPool로 해주는 것들:

Arrays.parallelSort(bigArray);        // 내부 fork/join 병렬 정렬
list.parallelStream()...              // 내부 fork/join
CompletableFuture.supplyAsync(...)    // 기본 실행기가 ForkJoinPool.commonPool()

→ "ForkJoinPool 적용 사례"의 90%는 이렇게 라이브러리가 대신 써주는 형태야.

3) ⚠️ API 호출엔 fork/join을 쓰면 안 된다

이게 중요해. "여러 API 동시 호출"은 fork/join처럼 보이지만 도구가 달라. API 호출은 블로킹 I/O라:

// ❌ 안티패턴: ForkJoinPool에서 블로킹 I/O
ForkJoinPool.commonPool().submit(() -> restTemplate.getForObject(...));
// commonPool은 CPU 코어 수만큼만 스레드가 있어서,
// 블로킹 I/O로 스레드가 멈추면 → 병렬 스트림 등 JVM 전역이 같이 굶음

ForkJoinPool은 "스레드가 멈추지 않고 CPU를 계속 굴린다"는 가정으로 설계됐어. I/O로 스레드가 대기하면 그 가정이 깨져.

4) 그래서 "API 여러 개 동시 호출 → 합치기"의 실무 정답

fork/join의 아이디어(쪼개서 병렬 → 합치기)는 맞지만, 도구는 CompletableFuture + 전용 풀이야. 이게 진짜 실무에서 자주 나오는 패턴이야.

시나리오: 상세 페이지를 만들려고 3개 서비스를 동시에 호출

@Service
public class ProductPageService {

    // API 호출(I/O)용 전용 풀 — commonPool 오염 방지
    private final Executor apiPool = Executors.newFixedThreadPool(20);

    private final UserClient userClient;
    private final OrderClient orderClient;
    private final RecommendClient recommendClient;

    public ProductPage load(Long userId, Long productId) {
        // ① fork: 3개를 동시에 던짐 (각각 apiPool 스레드에서 블로킹 호출)
        CompletableFuture<User> userF =
            CompletableFuture.supplyAsync(() -> userClient.get(userId), apiPool);

        CompletableFuture<List<Order>> ordersF =
            CompletableFuture.supplyAsync(() -> orderClient.getByUser(userId), apiPool);

        CompletableFuture<List<Item>> recF =
            CompletableFuture.supplyAsync(() -> recommendClient.get(productId), apiPool);

        // ② join: 셋 다 끝날 때까지 대기
        CompletableFuture.allOf(userF, ordersF, recF).join();

        // ③ 합치기 (conquer)
        return new ProductPage(userF.join(), ordersF.join(), recF.join());
    }
}

이게 왜 이득이냐

순차 호출:  user(300ms) → orders(300ms) → rec(300ms)  = 900ms
병렬 호출:  세 개 동시                                  ≈ 300ms (가장 느린 것 기준)

3번 직렬로 부르면 900ms인데, 동시에 던지면 제일 느린 호출 하나(≈300ms) 로 끝나. 이게 fork/join "정신"을 API에 적용한 실무 사례야.

▎ 핵심 포인트 2개:
▎ - supplyAsync에 전용 apiPool을 꼭 넘긴다 (commonPool 안 씀 → 전역 오염 방지)
▎ - 풀 크기는 동시 호출 수에 맞춰 넉넉히 (I/O 바운드라 코어 수보다 크게 잡아도 됨)

5) 그리고 요즘은 — 가상 스레드가 이걸 더 간단하게

앞서 본 VirtualThreadTaskExecutor/가상 스레드(JDK 21)가 바로 이 "블로킹 I/O 여러 개"에 최적이야:

// 가상 스레드 풀이면 크기 걱정 없이 던질 수 있음
var vexec = Executors.newVirtualThreadPerTaskExecutor();
CompletableFuture.supplyAsync(() -> userClient.get(userId), vexec);

블로킹 호출이 많을수록 가상 스레드가 캐리어 스레드를 안 잡고 양보하니, 풀 크기 튜닝 부담이 줄어.

결정 가이드 (언제 뭘 쓰나)

┌─────────────────────────────────────────┬────────────────────────────────────────────┐
│                  상황                   │                    도구                    │
├─────────────────────────────────────────┼────────────────────────────────────────────┤
│ 대용량 in-memory 데이터 CPU 연산 병렬화 │ parallelStream / RecursiveTask (fork/join) │
├─────────────────────────────────────────┼────────────────────────────────────────────┤
│ 여러 API/DB 동시 호출 후 합치기         │ CompletableFuture + 전용 풀 (allOf)        │
├─────────────────────────────────────────┼────────────────────────────────────────────┤
│ 단순 "메서드 하나 백그라운드로"         │ 스프링 @Async                              │
├─────────────────────────────────────────┼────────────────────────────────────────────┤
│ 블로킹 I/O가 매우 많음(JDK 21+)         │ 가상 스레드 + CompletableFuture            │
├─────────────────────────────────────────┼────────────────────────────────────────────┤
│ CPU 바운드 작업 + 자원 통제             │ ThreadPoolTaskExecutor(바운딩된 풀)        │
└─────────────────────────────────────────┴────────────────────────────────────────────┘

한 줄 정리

▎ RecursiveTask fork/join을 직접 쓰는 건 CPU 바운드 분할정복(대용량 in-memory 연산)용이라 일반 API 백엔드에선 드물다. API 호출(블로킹 I/O)에 ForkJoinPool/commonPool을 쓰는 건 오히려 안티패턴이고, 실무에서 "여러 API 동시 호출 → 합치기"는 fork/join의 아이디어를 CompletableFuture + 전용 풀(allOf) 로 구현하는 게 정답이다(JDK 21+면 가상 스레드가 더 편함). fork/join 자체는 parallelStream·Arrays.parallelSort처럼 라이브러리가 내부에서 대신 써주는 형태로 더 자주 만난다.

✻ Worked for 52s

❯ 근데 foo 라는 메서드가 어떤 맥락에서는 비동기로 호출되는게 효율적이고, 어떤 맥락에서는 동기로 호출돼야한다고 하면 @Async를 달면 안될것 같은데, 이런경우는 CompletableFuture에서 pool 넘겨서 사용하는 식으로하나 ?

정확히 그 직관이 맞아. 그리고 이건 사실 설계 원칙 문제로 귀결돼:

▎ 동시성(비동기로 돌릴지)은 "메서드의 속성"이 아니라 "호출자의 결정"이다.

@Async는 이 원칙을 위반해. 메서드에 @Async를 달면 "이 메서드는 항상 비동기" 로 고정돼버리거든. 같은 메서드를 맥락에 따라 동기/비동기로 못 골라.

왜 @Async가 이 경우엔 안 맞나

@Async("pool")
public Result foo() { ... }

- 프록시를 거치는 외부 호출은 무조건 비동기. "이번엔 동기로" 같은 분기가 안 됨.
- 동기로 부르려고 this.foo() 하면 → self-invocation이라 프록시 안 거쳐서 동기가 되긴 하는데, 이건 함정을 의도적으로 악용하는 꼴이라 절대 권장 안 함. (다른 사람이 보면 버그로 오해)
- 결국 "맥락에 따라 다르게"를 표현할 수단이 없어.

정답: foo는 평범한 동기 메서드로 두고, 호출자가 결정한다

foo에서 @Async를 떼고 그냥 동기 메서드로 만들어. 그리고 비동기로 돌리고 싶은 호출자가 그때 풀에 던져:

@Service
public class FooService {
    // 동시성에 대해 아무것도 모른다. 그냥 일만 함. (= '작업' 그 자체)
    public Result foo(Input in) {
        return heavyWork(in);
    }
}

동기로 쓰고 싶은 호출자

Result r = fooService.foo(input);   // 그냥 부른다. 끝.

비동기로 쓰고 싶은 호출자 — 네 말대로 풀을 넘겨서

@Service
public class OrchestrationService {

    private final FooService fooService;
    private final Executor appPool;   // 스프링 TaskExecutor 빈 주입 (Executor 타입이면 됨)

    public OrchestrationService(FooService fooService,
                                @Qualifier("mailExecutor") Executor appPool) {
        this.fooService = fooService;
        this.appPool = appPool;
    }

    public CompletableFuture<Result> fooAsync(Input in) {
        // 여기서 '이 맥락에선 비동기로' 결정
        return CompletableFuture.supplyAsync(() -> fooService.foo(in), appPool);
    }
}

이게 정확히 맨 처음에 얘기했던 "task 제출 ↔ 실행 메커니즘 분리(Executor 디커플링)" 의 실전 적용이야:

foo()           = 작업(task) 그 자체           ← "무엇을"
호출자          = 실행 전략 결정               ← "어떻게/동기냐 비동기냐"
supplyAsync/pool = 그 사이를 잇는 메커니즘

foo는 자기가 어느 스레드에서 도는지 몰라야 하고, 그 결정권은 그 맥락을 아는 호출자에게 있어야 해.

스프링 빈을 그대로 Executor로 넘겨도 된다

앞에서 본 것처럼 ThreadPoolTaskExecutor는 Executor니까, CompletableFuture에 그대로 넘길 수 있어. 굳이 JDK 풀을 새로 만들 필요 없이 이미 설정해둔 스프링 풀 빈을 재사용해:

CompletableFuture.supplyAsync(() -> fooService.foo(in), threadPoolTaskExecutorBean);
//                                                       ^^^^^^^^^^^^^^^^^^^^^^^^^ 스프링 빈 OK

submit만 필요하고 조합(thenApply 등)이 없으면 더 간단히:

Future<Result> f = threadPoolTaskExecutorBean.submit(() -> fooService.foo(in));

정리: 세 가지 선택지 비교

┌──────────────────────────────────────────┬────────────────────────────┬───────────────────────────────────────┐
│                   방식                   │      동기/비동기 선택      │               적합한 때               │
├──────────────────────────────────────────┼────────────────────────────┼───────────────────────────────────────┤
│ @Async 메서드                            │ ❌ 항상 비동기 (고정)      │ 그 메서드가 언제나 비동기여야 할 때만 │
├──────────────────────────────────────────┼────────────────────────────┼───────────────────────────────────────┤
│ foo 동기 + 호출자가 supplyAsync(…, pool) │ ✅ 호출자가 맥락별로 선택  │ 네 상황 (맥락 따라 다름)              │
├──────────────────────────────────────────┼────────────────────────────┼───────────────────────────────────────┤
│ foo 동기 + executor.submit(…)            │ ✅ 선택 가능, 단 조합 없음 │ 결과 조합 불필요할 때                 │
└──────────────────────────────────────────┴────────────────────────────┴───────────────────────────────────────┘

한 줄 정리

▎ 맥락에 따라 동기/비동기가 갈리면 @Async는 부적합하다 — 그건 메서드를 "항상 비동기"로 고정하기 때문. 정석은 foo를 평범한 동기 메서드로 두고, 동시성 결정을 호출자에게 위임하는 것: 동기가 필요하면 그냥 foo(), 비동기가 필요하면 CompletableFuture.supplyAsync(() -> foo(), pool)(또는 executor.submit)로 호출자가 풀을 넘겨 실행한다. 이때 풀은 새로 만들 필요 없이 스프링 TaskExecutor/ThreadPoolTaskExecutor 빈을 그대로 Executor로 넘기면 된다. 즉 "동시성은 메서드가 아니라 호출자의 관심사"라는 원칙의 실전 적용이다.
```

---

메인 스레드, 비동기 스레드 컴구조 관점에서 어떤식으로 처리되는거지 ?
