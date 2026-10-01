
**동작 방식**
- scheduleAtFixedRate() 호출 시 ScheduledFutureTask 객체가 생성되고, DelayedWorkQueue에 추가됨.
- ensurePrestart()를 통해 Worker 스레드가 실행됨.
- Worker 스레드가 DelayedWorkQueue에서 실행 가능한 작업을 가져와 실행.

| 단계 | 동작 | 실행 주체 |
| --- | --- | --- |
| 1 | `scheduleAtFixedRate()` 호출 | 사용자 코드 |
| 2 | `ScheduledFutureTask` 객체 생성 | `ScheduledThreadPoolExecutor` |
| 3 | `DelayedQueue`에 추가 | `ScheduledThreadPoolExecutor.delayedExecute()` |
| 4 | `Worker` 스레드가 대기 | `Worker` 스레드 (`getTask()`) |
| 5 | 첫 실행 시간이 되면 `task` 실행 | `Worker` 스레드 |
| 6 | `task.run()` 실행 | `Worker` 스레드 |
| 7 | 다음 실행 시간 계산 후 `DelayedQueue`에 추가 | `ScheduledFutureTask.run()` |
| 8 | `Worker` 스레드는 다시 대기 | `Worker` 스레드 (`getTask()`) |
| 9 | 다음 실행 시간이 되면 다시 실행 | `Worker` 스레드 |
| 10 | `task.run()` 실행 후 반복 | `Worker` 스레드 |

- Java의 DelayedQueue는 작업의 실행 시간을 기준으로 정렬되는 우선순위 큐(PriorityQueue) 기반의 데이터 구조입니다. 즉, 실행 시간이 가장 가까운 작업이 큐의 맨 앞에 위치하도록 자동 정렬됩니다.

**워커 스레드 동작 방식 (무한 루프 ?)**
- Worker 스레드는 getTask()를 호출하여 대기열(DelayedQueue)에서 실행 시간이 도래한 작업을 가져옴.
```java
private Runnable getTask() {
  boolean timedOut = false;

  for (;;) {
    int c = ctl.get();

    if (runStateAtLeast(c, STOP) || (runStateAtLeast(c, SHUTDOWN) && workQueue.isEmpty())) {
      return null;
    }

    try {
      // 1️⃣ 실행할 작업이 없으면 블로킹 대기
      Runnable r = workQueue.take();
      if (r != null) return r; // 실행할 Task가 있으면 즉시 반환
    } catch (InterruptedException retry) {
      timedOut = false;
    }
  }
}
```

- DelayedQueue.take()에서 실행 시간이 도래한 Task를 기다리는 과정
```java
public RunnableScheduledFuture<?> take() throws InterruptedException {
  final ReentrantLock lock = this.lock;
  lock.lockInterruptibly();
  try {
    for (;;) {
      RunnableScheduledFuture<?> first = queue.peek();  // 1️⃣ 실행 시간이 가장 빠른 Task 확인
      if (first == null)
        available.await();  // 2️⃣ 실행할 Task가 없으면 대기 => DelayedWorkQueue에서 offer로 task 추가될때 available.signal()로 깨움
      else {
        long delay = first.getDelay(NANOSECONDS);
        if (delay <= 0)
          return queue.poll();  // 3️⃣ 실행 시간이 도래한 Task 반환
        available.awaitNanos(delay);  // 4️⃣ 실행 시간이 도래할 때까지 대기
      }
    }
  } finally {
    lock.unlock();
  }
}
```


```java
public LockManager() {
    // 메서드를 처음 10초 후에 실행하고, 이후 5초 간격으로 반복 실행하도록 예약
    ScheduledExecutorService scheduler = Executors.newScheduledThreadPool(1);
    scheduler.scheduleAtFixedRate(this::removeExpiredLocks, 10, 5, TimeUnit.SECONDS);
}

private void removeExpiredLocks() {
  for (String key : locks.keySet()) {
    CustomLock lock = locks.get(key);
    if (lock != null && lock.isExpired()) {
      log.warn("락 자동 해제 : {}", key);
      releaseLock(key);
    }
  }
}
```

```java
private class ScheduledFutureTask<V>
        extends FutureTask<V> implements RunnableScheduledFuture<V> {

    /** Sequence number to break ties FIFO */
    private final long sequenceNumber;

    /** The nanoTime-based time when the task is enabled to execute. */
    private volatile long time;

    /**
     * Period for repeating tasks, in nanoseconds.
     * A positive value indicates fixed-rate execution.
     * A negative value indicates fixed-delay execution.
     * A value of 0 indicates a non-repeating (one-shot) task.
     */
    private final long period;

    /** The actual task to be re-enqueued by reExecutePeriodic */
    RunnableScheduledFuture<V> outerTask = this;

    /**
     * Index into delay queue, to support faster cancellation.
     */
    int heapIndex;

    /**
     * Creates a one-shot action with given nanoTime-based trigger time.
     */
    ScheduledFutureTask(Runnable r, V result, long triggerTime,
                        long sequenceNumber) {
        super(r, result);
        this.time = triggerTime;
        this.period = 0;
        this.sequenceNumber = sequenceNumber;
    }

    /**
     * Creates a periodic action with given nanoTime-based initial
     * trigger time and period.
     */
    ScheduledFutureTask(Runnable r, V result, long triggerTime,
                        long period, long sequenceNumber) {
        super(r, result);
        this.time = triggerTime;
        this.period = period;
        this.sequenceNumber = sequenceNumber;
    }

    /**
     * Creates a one-shot action with given nanoTime-based trigger time.
     */
    ScheduledFutureTask(Callable<V> callable, long triggerTime,
                        long sequenceNumber) {
        super(callable);
        this.time = triggerTime;
        this.period = 0;
        this.sequenceNumber = sequenceNumber;
    }

    public long getDelay(TimeUnit unit) {
        return unit.convert(time - System.nanoTime(), NANOSECONDS);
    }

    public int compareTo(Delayed other) {
        if (other == this) // compare zero if same object
            return 0;
        if (other instanceof ScheduledFutureTask) {
            ScheduledFutureTask<?> x = (ScheduledFutureTask<?>)other;
            long diff = time - x.time;
            if (diff < 0)
                return -1;
            else if (diff > 0)
                return 1;
            else if (sequenceNumber < x.sequenceNumber)
                return -1;
            else
                return 1;
        }
        long diff = getDelay(NANOSECONDS) - other.getDelay(NANOSECONDS);
        return (diff < 0) ? -1 : (diff > 0) ? 1 : 0;
    }

    /**
     * Returns {@code true} if this is a periodic (not a one-shot) action.
     *
     * @return {@code true} if periodic
     */
    public boolean isPeriodic() {
        return period != 0;
    }

    /**
     * Sets the next time to run for a periodic task.
     */
    private void setNextRunTime() {
        long p = period;
        if (p > 0)
            time += p;
        else
            time = triggerTime(-p);
    }

    public boolean cancel(boolean mayInterruptIfRunning) {
        // The racy read of heapIndex below is benign:
        // if heapIndex < 0, then OOTA guarantees that we have surely
        // been removed; else we recheck under lock in remove()
        boolean cancelled = super.cancel(mayInterruptIfRunning);
        if (cancelled && removeOnCancel && heapIndex >= 0)
            remove(this);
        return cancelled;
    }

    /**
     * Overrides FutureTask version so as to reset/requeue if periodic.
     */
    public void run() {
        if (!canRunInCurrentRunState(this))
            cancel(false);
        else if (!isPeriodic())
            super.run();
        else if (super.runAndReset()) {
            setNextRunTime();
            reExecutePeriodic(outerTask);
        }
    }
}
```

```java
// java.util.concurrent.ScheduledThreadPoolExecutor.scheduleAtFixedRate
public ScheduledFuture<?> scheduleAtFixedRate(Runnable command,
                                              long initialDelay,
                                              long period,
                                              TimeUnit unit) {
  if (command == null || unit == null)
    throw new NullPointerException();
  if (period <= 0L)
    throw new IllegalArgumentException();
  ScheduledFutureTask<Void> sft =
    new ScheduledFutureTask<Void>(command,
      null,
      triggerTime(initialDelay, unit),
      unit.toNanos(period),
      sequencer.getAndIncrement());
  RunnableScheduledFuture<Void> t = decorateTask(command, sft);
  sft.outerTask = t;
  delayedExecute(t);
  return t;
}

private void delayedExecute(RunnableScheduledFuture<?> task) {
  if (isShutdown())
    reject(task);
  else {
    super.getQueue().add(task);
    if (!canRunInCurrentRunState(task) && remove(task))
      task.cancel(false);
    else
      ensurePrestart();
  }
}

void ensurePrestart() {
  int wc = workerCountOf(ctl.get());
  if (wc < corePoolSize)
    addWorker(null, true);
  else if (wc == 0)
    addWorker(null, false);
}

private boolean addWorker(Runnable firstTask, boolean core) {
  retry:
  for (int c = ctl.get();;) {
    // Check if queue empty only if necessary.
    if (runStateAtLeast(c, SHUTDOWN)
      && (runStateAtLeast(c, STOP)
      || firstTask != null
      || workQueue.isEmpty()))
      return false;

    for (;;) {
      if (workerCountOf(c)
        >= ((core ? corePoolSize : maximumPoolSize) & COUNT_MASK))
        return false;
      if (compareAndIncrementWorkerCount(c))
        break retry;
      c = ctl.get();  // Re-read ctl
      if (runStateAtLeast(c, SHUTDOWN))
        continue retry;
      // else CAS failed due to workerCount change; retry inner loop
    }
  }

  boolean workerStarted = false;
  boolean workerAdded = false;
  Worker w = null;
  try {
    w = new Worker(firstTask);
    final Thread t = w.thread;
    if (t != null) {
      final ReentrantLock mainLock = this.mainLock;
      mainLock.lock();
      try {
        // Recheck while holding lock.
        // Back out on ThreadFactory failure or if
        // shut down before lock acquired.
        int c = ctl.get();

        if (isRunning(c) ||
          (runStateLessThan(c, STOP) && firstTask == null)) {
          if (t.getState() != Thread.State.NEW)
            throw new IllegalThreadStateException();
          workers.add(w);
          workerAdded = true;
          int s = workers.size();
          if (s > largestPoolSize)
            largestPoolSize = s;
        }
      } finally {
        mainLock.unlock();
      }
      if (workerAdded) {
        t.start();
        workerStarted = true;
      }
    }
  } finally {
    if (! workerStarted)
      addWorkerFailed(w);
  }
  return workerStarted;
}
```
