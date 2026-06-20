
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


Executor : RejectedExecutionException 발생시 ?? abort policy ??
TaskExecutor :TaskRejectedException

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




## 대규모 트래픽 ?


---

메인 스레드, 비동기 스레드 컴구조 관점에서 어떤식으로 처리되는거지 ?
