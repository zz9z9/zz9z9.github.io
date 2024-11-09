---
title: Java - Thread Pool을 위한 Java Executor Framework
date: 2021-08-07 00:29:00 +0900
categories: [지식 더하기, 이론]
tags: [Java]
---

자바에서의 비동기 처리를 위해 `CompletableFuture`에 대해 공부하며 클래스 내부를 보다보니 `Executor`, `ForkJoinPool` 등이 눈에 띄었다.
생소한 부분이라 공부하며 나름대로 정리해보았다.

# Thread Pool
---
> `Executor`, `ForkJoinPool`에 대해 알기 전에 먼저 스레드 풀의 개념에 대해 살펴보자.

- 스레드를 만들고 관리하는 데는 비용이 많이 들기 때문에, 스레드를 필요할 때 마다 생성하는게 아니라 미리 생성해놓고 필요할 때 마다 재사용한다.
  - 이를 위해 스레드를 관리하기 위한 ***스레드 풀***이라는 개념이 나오게 된다.
  - 즉, 요청이 들어올 때마다 새 스레드를 만드는 대신 스레드 풀을 사용하여 task를 병렬로 실행할 수 있다.
- 스레드 풀 인스턴스는 이러한 작업을 실행하기 위해 재사용되는 여러 스레드를 제어한다.
  - 스레드를 재사용함으로써, 멀티 스레드를 활용하는 애플리케이션의 리소스를 아낄 수 있다.
- 스레드 풀을 통해 생성하는 스레드 수와 스레드의 생명주기를 제어할 수 있다. 또한 작업(task)을 스케줄링하고 큐에 작업을 보관할 수 있다.
  - 스레드 갯수를 정함으로써 동시성의 정도를 제한할 수 있다.

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/128628455-098b228c-3def-4e36-82db-baba987f990d.png" width="90%"/>
  <figcaption align="center">출처 : <a href="https://www.baeldung.com/thread-pool-java-and-guava" target="_blank"> https://www.baeldung.com/thread-pool-java-and-guava</a> </figcaption>
</figure>

## 스레드 풀을 사용해야 하는 이유
- 자바에서 스레드는 운영 체제의 리소스인 시스템 수준 스레드(system-level thread)에 매핑되기 때문에, 스레드를 무분별하게 생성하면 리소스가 빠르게 소진될 수 있다.
  - ex) `java.lang.OutOfMemoryError: unable to create new native thread`
- 운영 체제는 여러 task를 동시에 처리(실제로는 한 번에 하나의 task)하기 위해 스레드 간 context switching을 수행한다.
  - 따라서, 스레드를 많이 생성할수록 각 스레드가 실제 작업을 수행하는 데 걸리는 시간이 줄어든다.
- reqeust 또는 task 처리 중에 스레드가 생성되지 않으므로 응답 시간이 단축된다.
- 필요에 따라 애플리케이션의 실행 정책을 유연하게 변경할 수 있다.
  - 예를 들어, 자바의 ExecutorService 구현체를 교체하기만 하면 단일 스레드에서 멀티 스레드로 대체할 수 있다.
- 시스템 부하 및 사용 가능한 리소스에 기반하여 스레드 수를 결정하기 때문에, 시스템의 안정성을 높인다.
- 스레드 관리보다 비즈니스 로직에 집중할 수 있다.

# 자바에서의 스레드 풀 관리
---
> Java 1.5 이전까지는 스레드 풀을 만들고 관리하는 것이 개발자의 책임이었지만, JDK 5 부터는 ***Executor 프레임워크***에서 Java에 내장된 다양한 스레드 풀(fixed thread pool, cached thread pool 등)을 제공한다.
> `Executor`, `ExecutorService`, `Executors`는 Executor 프레임워크의 핵심이다.

## Executor / ExecutorService / Executors 비교

### Executor
- Executor는 ***병렬 실행(parallel execution)을 위해 추상화된*** 핵심 인터페이스이다.
```java
public interface Executor {
    void execute(Runnable command);
}
```
- Executor는 작업(task)과 실행(execution)을 결합한 Thread(`new Thread(RunnableTask()).start()`)와는 다르게 작업과 실행을 구분한다.
  - 따라서, Executor는 task를 처리하기 위한 스레드를 직접 호출하는 대신 다음과 같이 사용될 수 있다.
```java
static <U> CompletableFuture<U> asyncSupplyStage(Executor e, Supplier<U> f) {
        if (f == null) throw new NullPointerException();
        CompletableFuture<U> d = new CompletableFuture<U>();
        e.execute(new AsyncSupply<U>(d, f));
        return d;
    }
```

### ExecutorService
- ExecutorService는 Executor 인터페이스의 확장으로, Future 개체를 반환하고, 스레드 풀을 종료하는 등의 다양한 기능을 제공한다.

```java
public interface ExecutorService extends Executor {
...
}
```

- `shutdown()`이 호출되면 스레드 풀은 새로운 task를 수락하지 않고 보류 중인 task를 완료한다.
- `submit()`을 통해 `Future` 객체를 리턴한다.

```java
<T> Future<T> submit(Callable<T> task);

<T> Future<T> submit(Runnable task, T result);

Future<?> submit(Runnable task);
```

- Future 객체는 비동기 실행 기능을 제공한다.
  - 즉, task에 대한 실행이 완료될 때까지 기다릴 필요없이, 추후에 Future 객체에 결과가 있는지 확인하고 실행이 완료되면 `Future.get()`을 사용하여 결과를 얻을 수 있다.
  - `get()`은 blocking method이다.
    - 즉, task의 실행이 완료될 때까지 기다리고 아직 완료되지 않은 경우 결과를 사용할 수 없다.
- `cancel()`을 통해 보류 중인 실행을 취소할 수 있다.
- 이외에도 `invokeAny()`, `invokeAll()` 등 다양한 메서드를 제공한다. (자세한 내용은 [공식 문서](https://docs.oracle.com/javase/7/docs/api/java/util/concurrent/ExecutorService.html) 참조)

### Executors
- Executors는 `Collections`와 유사한 **유틸리티 클래스**로, fixed thread pool, cached thread pool과 같은 서로 다른 유형의 스레드 풀을 만드는 ***팩토리 메서드***를 제공한다.

```java
public static ExecutorService newFixedThreadPool(int nThreads, ThreadFactory threadFactory) {
       return new ThreadPoolExecutor(nThreads, nThreads,
                                     0L, TimeUnit.MILLISECONDS,
                                     new LinkedBlockingQueue<Runnable>(),
                                     threadFactory);
}

public static ExecutorService newSingleThreadExecutor() {
    return new FinalizableDelegatedExecutorService
        (new ThreadPoolExecutor(1, 1,
                                0L, TimeUnit.MILLISECONDS,
                                new LinkedBlockingQueue<Runnable>()));
}
```

## Executor 프레임워크 사용시 주의할 점
- fixed length thread pool 사용시 스레드 풀 용량
  - 애플리케이션이 task를 효율적으로 실행하기 위해 필요한 스레드 수를 결정하는 것은 매우 중요하다.
  - 너무 큰 스레드 풀은 대부분의 스레드가 대기 모드에 있게되고, 이러한 스레드를 만드는데 불필요한 오버헤드가 발생한다.
  - 너무 적으면 큐에 있는 task는 대기하는 시간이 길어지기 때문에, 애플리케이션이 응답하지 않는 것처럼 보일 수 있다.

- 작업 취소 후 `Future.get()` 메서드 호출
  - 이미 취소된 작업의 결과를 가져오려고 하면 `CancellationException`이 발생한다.

- `Future.get()` 메서드로 인해 예기치 않게 긴 blocking
  - 이를 방지하기 위해 제한 시간을 사용하는 것이 좋다.

# ThreadPoolExecutor
---
- ThreadPoolExecutor는 미세 조정을 위한 많은 매개변수와 후크가 있는 확장 가능한 스레드 풀 구현체이다.
  - ExecutorService를 스레드 풀을 관리하는 역할을 정의한 것이라고 한다면, ThreadPoolExecutor는 그 역할을 구현하는 구현체라고 생각하면 될 것 같다.
    <figure align = "center">
      <img src = "https://user-images.githubusercontent.com/64415489/128664569-30468988-643f-4b83-9184-806e7a0534f8.png" width="70%" height="70%"/>
      <figcaption align="center">출처 : <a href="https://docs.oracle.com/javase/7/docs/api/java/util/concurrent/ThreadPoolExecutor.html" target="_blank"> https://docs.oracle.com/javase/7/docs/api/java/util/concurrent/ThreadPoolExecutor.html</a> </figcaption>
    </figure>

- 주요 구성 매개변수는 `corePoolSize`, `maximumPoolSize`, `keepAliveTime`이다.
  - corePoolSize 매개변수는 인스턴스화되어 풀에 보관될 코어 스레드의 수이다.
  - 새 작업이 들어올 때 모든 코어 스레드가 사용 중이고 내부 큐가 가득 차면 풀이 maximumPoolSize까지 커질 수 있다.
- 풀은 항상 내부에 유지되는 고정된 수의 코어 스레드로 구성된다.
  - 생성된 다음 더 이상 필요하지 않을 때 종료될 수 있는 excessive 스레드로 구성되기도 한다.

```java
public ThreadPoolExecutor(int corePoolSize,
                          int maximumPoolSize,
                          long keepAliveTime,
                          TimeUnit unit,
                          BlockingQueue<Runnable> workQueue) {
    this(corePoolSize, maximumPoolSize, keepAliveTime, unit, workQueue,
         Executors.defaultThreadFactory(), defaultHandler);
}

public ThreadPoolExecutor(int corePoolSize,
                          int maximumPoolSize,
                          long keepAliveTime,
                          TimeUnit unit,
                          BlockingQueue<Runnable> workQueue,
                          ThreadFactory threadFactory) {
    this(corePoolSize, maximumPoolSize, keepAliveTime, unit, workQueue,
         threadFactory, defaultHandler);
}

public ThreadPoolExecutor(int corePoolSize,
                          int maximumPoolSize,
                          long keepAliveTime,
                          TimeUnit unit,
                          BlockingQueue<Runnable> workQueue,
                          RejectedExecutionHandler handler) {
    this(corePoolSize, maximumPoolSize, keepAliveTime, unit, workQueue,
         Executors.defaultThreadFactory(), handler);
}

public ThreadPoolExecutor(int corePoolSize,
                          int maximumPoolSize,
                          long keepAliveTime,
                          TimeUnit unit,
                          BlockingQueue<Runnable> workQueue,
                          ThreadFactory threadFactory,
                          RejectedExecutionHandler handler) {
    if (corePoolSize < 0 ||
        maximumPoolSize <= 0 ||
        maximumPoolSize < corePoolSize ||
        keepAliveTime < 0)
        throw new IllegalArgumentException();
    if (workQueue == null || threadFactory == null || handler == null)
        throw new NullPointerException();
    this.corePoolSize = corePoolSize;
    this.maximumPoolSize = maximumPoolSize;
    this.workQueue = workQueue;
    this.keepAliveTime = unit.toNanos(keepAliveTime);
    this.threadFactory = threadFactory;
    this.handler = handler;
}
```

## FixedThreadPool
- corePoolSize와 maximumPoolSize가 같으며 keepAliveTime이 0인 ThreadPoolExecutor.
- 따라서, 이 스레드 풀의 스레드 수는 항상 동일하다.

```java
public static ExecutorService newFixedThreadPool(int nThreads, ThreadFactory threadFactory) {
    return new ThreadPoolExecutor(nThreads, nThreads,
                                  0L, TimeUnit.MILLISECONDS,
                                  new LinkedBlockingQueue<Runnable>(),
                                  threadFactory);
}
```

- 아래 예시의 경우, 동시에 실행되는 작업의 수가 항상 2개보다 작거나 같으면 즉시 실행된다.
  - 즉, 처음 두 태스크는 한 번에 실행되고 세 번째 태스크는 대기열에서 대기해야 한다.

```java
ThreadPoolExecutor executor = (ThreadPoolExecutor) Executors.newFixedThreadPool(2);

executor.submit(() -> {
    Thread.sleep(1000);
    return null;
});
executor.submit(() -> {
    Thread.sleep(1000);
    return null;
});
executor.submit(() -> {
    Thread.sleep(1000);
    return null;
});

assertEquals(2, executor.getPoolSize());
assertEquals(1, executor.getQueue().size());
```

## CachedThreadPool
- corePoolSize는 0, maximumPoolSize는 Integer.MAX_VALUE, keepAliveTime은 60초인 ThreadPoolExecutor.
  - 즉, 스레드 풀이 모든 task를 수용할 수 있도록 제한 없이 커질 수 있음을 의미한다.
  - 또한 스레드가 60초 동안 사용하지 않으면 폐기된다.
- CachedThreadPool은 애플리케이션이 주로 short-living task를 처리하는 경우 활용한다.
- 내부적으로 `SynchronousQueue`가 사용되므로 대기열 크기는 항상 0이다.
  - SynchronousQueue에서는 삽입 및 제거 작업 쌍이 항상 동시에 수행되기 때문에, 실제로 아무것도 포함하지 않는다.

```java
public static ExecutorService newCachedThreadPool() {
       return new ThreadPoolExecutor(0, Integer.MAX_VALUE,
                                     60L, TimeUnit.SECONDS,
                                     new SynchronousQueue<Runnable>());
}

public static ExecutorService newCachedThreadPool(ThreadFactory threadFactory) {
    return new ThreadPoolExecutor(0, Integer.MAX_VALUE,
                                  60L, TimeUnit.SECONDS,
                                  new SynchronousQueue<Runnable>(),
                                  threadFactory);
}
```

```java
ThreadPoolExecutor executor = (ThreadPoolExecutor) Executors.newCachedThreadPool();

executor.submit(() -> {
    Thread.sleep(1000);
    return null;
});
executor.submit(() -> {
    Thread.sleep(1000);
    return null;
});
executor.submit(() -> {
    Thread.sleep(1000);
    return null;
});

assertEquals(3, executor.getPoolSize());
assertEquals(0, executor.getQueue().size());
```

## SingleThreadExecutor
- `Executors.newSingleThreadExecutor()`는 단일 스레드를 포함하는 또 다른 일반적인 형태의 ThreadPoolExecutor를 만든다.
- SingleThreadExecutor는 이벤트 루프를 만드는 데 이상적이다. corePoolSize, maximumPoolSize는 1이고 keepAliveTime은 0이다.

```java
public static ExecutorService newSingleThreadExecutor() {
    return new FinalizableDelegatedExecutorService
        (new ThreadPoolExecutor(1, 1,
                                0L, TimeUnit.MILLISECONDS,
                                new LinkedBlockingQueue<Runnable>()));
}

public static ExecutorService newSingleThreadExecutor(ThreadFactory threadFactory) {
    return new FinalizableDelegatedExecutorService
        (new ThreadPoolExecutor(1, 1,
                                0L, TimeUnit.MILLISECONDS,
                                new LinkedBlockingQueue<Runnable>(),
                                threadFactory));
}
```

```java
AtomicInteger counter = new AtomicInteger();

ExecutorService executor = Executors.newSingleThreadExecutor();
executor.submit(() -> {
    counter.set(1);
});
executor.submit(() -> {
    counter.compareAndSet(1, 2);
});
```

## ScheduledThreadPoolExecutor
- ScheduledThreadPoolExecutor는 ThreadPoolExecutor 클래스를 상속받고 ScheduledExecutorService 인터페이스도 구현하여 부가적인 기능을 제공한다.
  - `schedule()` 메서드를 사용하면 지정된 지연 후 작업을 한 번 실행할 수 있다.
  - `scheduleAtFixedRate()` 메서드를 사용하면 지정된 초기 지연 후에 작업을 실행한 다음 특정 기간 동안 반복 실행할 수 있다.
    - 즉, task 수행 시작 시간은 (initialDelay + delay), (initialDelay + 2 * period), ... 이런식으로 계산된다.
  - `scheduleWithFixedDelay()` 메서드는 지정된 태스크를 반복적으로 실행한다는 점에서 `scheduleAtFixedRate()`와 유사하다.
    - 하지만, delay는 이전 task의 종료와 다음 task의 시작 사이에서 측정된다.
    - 즉, task 수행 시작 시간은 (이전 task의 끝나는 시점 + delay)가 된다.

```java
public class ScheduledThreadPoolExecutor
        extends ThreadPoolExecutor
         implements ScheduledExecutorService {
...
}
```

```java
public ScheduledThreadPoolExecutor(int corePoolSize) {
    super(corePoolSize, Integer.MAX_VALUE,
          DEFAULT_KEEPALIVE_MILLIS, MILLISECONDS,
          new DelayedWorkQueue());
}

public ScheduledThreadPoolExecutor(int corePoolSize,
                                   ThreadFactory threadFactory) {
    super(corePoolSize, Integer.MAX_VALUE,
          DEFAULT_KEEPALIVE_MILLIS, MILLISECONDS,
          new DelayedWorkQueue(), threadFactory);
}

public ScheduledThreadPoolExecutor(int corePoolSize,
                                   RejectedExecutionHandler handler) {
    super(corePoolSize, Integer.MAX_VALUE,
          DEFAULT_KEEPALIVE_MILLIS, MILLISECONDS,
          new DelayedWorkQueue(), handler);
}

public ScheduledThreadPoolExecutor(int corePoolSize,
                                   ThreadFactory threadFactory,
                                   RejectedExecutionHandler handler) {
    super(corePoolSize, Integer.MAX_VALUE,
          DEFAULT_KEEPALIVE_MILLIS, MILLISECONDS,
          new DelayedWorkQueue(), threadFactory, handler);
}
```

```java
public static ScheduledExecutorService newScheduledThreadPool(int corePoolSize) {
    return new ScheduledThreadPoolExecutor(corePoolSize);
}

public static ScheduledExecutorService newScheduledThreadPool(
        int corePoolSize, ThreadFactory threadFactory) {
    return new ScheduledThreadPoolExecutor(corePoolSize, threadFactory);
}
```

```java
ScheduledExecutorService executor = Executors.newScheduledThreadPool(5);
executor.schedule(() -> {
    System.out.println("Hello World");
}, 500, TimeUnit.MILLISECONDS);
```

- 다음 코드는 500밀리초 지연 후 작업을 실행한 후 100밀리초마다 반복하는 방법을 보여준다.
- 또한, 작업을 예약한 후 CountDownLatch lock을 사용하여 작업이 세 번 실행될 때까지 기다린 후, `Future.cancel()` 메서드를 사용하여 작업을 취소한다.

```java
CountDownLatch lock = new CountDownLatch(3);

ScheduledExecutorService executor = Executors.newScheduledThreadPool(5);
ScheduledFuture<?> future = executor.scheduleAtFixedRate(() -> {
    System.out.println("Hello World");
    lock.countDown();
}, 500, 100, TimeUnit.MILLISECONDS);

lock.await(1000, TimeUnit.MILLISECONDS);
future.cancel(true);
```

# 더 공부할 부분
---
- Fork/Join Framework

# 참고자료
---
- [https://docs.oracle.com/javase/7/docs/api/java/util/concurrent/Executor.html](https://docs.oracle.com/javase/7/docs/api/java/util/concurrent/Executor.html)
- [https://stackoverflow.com/questions/26938210/executorservice-vs-casual-thread-spawner](https://stackoverflow.com/questions/26938210/executorservice-vs-casual-thread-spawner)
- [https://stackoverflow.com/questions/3984076/what-are-the-advantages-of-using-an-executorservice](https://stackoverflow.com/questions/3984076/what-are-the-advantages-of-using-an-executorservice)
- [https://www.baeldung.com/thread-pool-java-and-guava](https://www.baeldung.com/thread-pool-java-and-guava)
- [https://www.baeldung.com/java-executor-service-tutorial](https://www.baeldung.com/java-executor-service-tutorial)
- [https://javarevisited.blogspot.com/2017/02/difference-between-executor-executorservice-and-executors-in-java.html#axzz72wOdvf6F](https://javarevisited.blogspot.com/2017/02/difference-between-executor-executorservice-and-executors-in-java.html#axzz72wOdvf6F)
