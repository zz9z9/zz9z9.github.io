---
title: Spring Batch - Step 개념
date: 2025-09-18 22:00:00 +0900
categories: [지식 더하기, 이론]
tags: [Spring Batch]
---


## 개념
---

### Step
- Batch Job을 구성하는 **독립된 작업**
- `BATCH_STEP_EXECUTION` 테이블에 저장됨
  - 해당 Step을 포함하는 JobExecution 정보(`JOB_EXECUTION_ID`)도 기록됨

```java
package org.springframework.batch.core;

public interface Step {

	String STEP_TYPE_KEY = "batch.stepType";

	String getName();

	default boolean isAllowStartIfComplete() {
		return false;
	}

	default int getStartLimit() {
		return Integer.MAX_VALUE;
	}

	void execute(StepExecution stepExecution) throws JobInterruptedException;

}
```

```java
@Bean
public Step step1(JobRepository jobRepository, PlatformTransactionManager transactionManager,
                  FlatFileItemReader<Person> reader, PersonItemProcessor processor, JdbcBatchItemWriter<Person> writer) {
    return new StepBuilder("step1", jobRepository)
            .<Person, Person>chunk(2, transactionManager)
            .reader(reader)
            .processor(processor)
            .writer(writer)
            .allowStartIfComplete(true)
            .build();
}
```

```java
// org.springframework.batch.core.job.SimpleJob#doExecute
@Override
protected void doExecute(JobExecution execution)
		throws JobInterruptedException, JobRestartException, StartLimitExceededException {

	StepExecution stepExecution = null;
	for (Step step : steps) {
		stepExecution = handleStep(step, execution);
		if (stepExecution.getStatus() != BatchStatus.COMPLETED) {
			//
			// Terminate the job if a step fails
			//
			break;
		}
	}

	//
	// Update the job status to be the same as the last step
	//
	if (stepExecution != null) {
		if (logger.isDebugEnabled()) {
			logger.debug("Upgrading JobExecution status: " + stepExecution);
		}
		execution.upgradeStatus(stepExecution.getStatus());
		execution.setExitStatus(stepExecution.getExitStatus());
	}
}
```

### StepExecution
> Step 실행 정보를 담고있는 객체

| 프로퍼티                 | 정의                                                                               |
|----------------------|----------------------------------------------------------------------------------|
| **status**           | 실행 상태를 나타내는 `BatchStatus` 객체. 실행 중이면 `STARTED`, 실패하면 `FAILED`, 성공하면 `COMPLETED`. |
| **startTime**        | `java.time.LocalDateTime` 실행이 시작된 시간. Step이 시작되지 않았다면 비어 있음.                     |
| **endTime**          | `java.time.LocalDateTime` 실행이 종료된 시간 (성공/실패 여부와 관계없음). Step이 아직 종료되지 않았다면 비어 있음. |
| **exitStatus**       | 실행 결과를 나타내는 `ExitStatus`. 종료 코드를 포함해 호출자에게 반환됨. Job이 아직 종료되지 않았다면 비어 있음.         |
| **executionContext** | 실행 간에 유지해야 할 사용자 데이터를 담는 “property bag”.                                         |
| **readCount**        | 성공적으로 읽은 아이템 수.                                                                  |
| **writeCount**       | 성공적으로 기록(write)한 아이템 수.                                                          |
| **commitCount**      | 이 실행에서 커밋된 트랜잭션 수.                                                               |
| **rollbackCount**    | Step이 제어하는 트랜잭션이 롤백된 횟수.                                                         |
| **readSkipCount**    | 읽기 실패로 인해 스킵된 횟수.                                                                |
| **processSkipCount** | 처리 실패로 인해 스킵된 횟수.                                                                |
| **filterCount**      | `ItemProcessor`에 의해 “필터링”된 아이템 수.                                                |
| **writeSkipCount**   | 쓰기 실패로 인해 스킵된 횟수.                                                                |


### BatchStatus vs ExitStatus
- 보통은 `BatchStatus`와 `ExitStatus`가 모두 `COMPLETED`이거나 `FAILED`
  - Job은 정상 수행되었지만, 아무 처리도 하지 않은 경우에는 `BatchStatus`는 `COMPLETED`, `ExitStatus`는 `NOOP`일수도 있다.
- 좀 더 세부적으로 처리가 필요한 경우 `ExitStatus`는 커스터마이징이 가능하다.
  - `BatchStatus` enum, `ExitStatus`는 class

```java
package org.springframework.batch.core;

public enum BatchStatus {

  COMPLETED,

  STARTING,

  STARTED,

  STOPPING,

  STOPPED,

  FAILED,

  ABANDONED,

  UNKNOWN;

  ...

}
```


```java
package org.springframework.batch.core;

...

public class ExitStatus implements Serializable, Comparable<ExitStatus> {

  public static final ExitStatus UNKNOWN = new ExitStatus("UNKNOWN");

  public static final ExitStatus EXECUTING = new ExitStatus("EXECUTING");

  public static final ExitStatus COMPLETED = new ExitStatus("COMPLETED");

  public static final ExitStatus NOOP = new ExitStatus("NOOP");

  public static final ExitStatus FAILED = new ExitStatus("FAILED");

  public static final ExitStatus STOPPED = new ExitStatus("STOPPED");

  private final String exitCode;

  private final String exitDescription;

  public ExitStatus(String exitCode) {
    this(exitCode, "");
  }

  public ExitStatus(String exitCode, String exitDescription) {
    super();
    this.exitCode = exitCode;
    this.exitDescription = exitDescription == null ? "" : exitDescription;
  }

  ...

}
```

- 예:

| 상황       | BatchStatus | ExitStatus             | 설명                                 |
| -------- | ----------- | ---------------------- | ---------------------------------- |
| 정상 처리 완료 | `COMPLETED` | `COMPLETED`            | 아무 문제 없음                           |
| 처리 중 실패  | `FAILED`    | `FAILED`               | 시스템 오류 등으로 실패                      |
| 데이터 없음   | `COMPLETED` | `NO DATA`              | 시스템 입장에서는 성공적으로 끝났지만, 처리할 데이터가 없음  |
| 일부 스킵 발생 | `COMPLETED` | `COMPLETED WITH SKIPS` | 프레임워크는 정상 종료로 보지만, 비즈니스상 경고가 필요함   |
| 재처리 필요   | `COMPLETED` | `RETRY NEEDED`         | 실행 자체는 완료되었지만, 특정 조건으로 인해 다시 돌려야 함 |


## Tasklet
---
> Chunk 기반(reader → processor → writer) 처리가 굳이 필요하지 않은 경우 <br>
> (예: DB stored procedure 호출, 스크립트 실행, 단순 SQL update/delete batch 등) <br>
> Tasklet 기반 Step을 사용하면 Tasklet 인터페이스를 구현한 객체의 execute 메서드를 실행한다.

```java
// org.springframework.batch.core.step.tasklet.Tasklet
@FunctionalInterface
public interface Tasklet {

	@Nullable
	RepeatStatus execute(StepContribution contribution, ChunkContext chunkContext) throws Exception;

}
```

- `MethodInvokingTaskletAdapter` 사용

```java
@Bean
public MethodInvokingTaskletAdapter myTasklet() {
	MethodInvokingTaskletAdapter adapter = new MethodInvokingTaskletAdapter();

	adapter.setTargetObject(fooDao());
	adapter.setTargetMethod("updateFoo");

	return adapter;
}
```

- `Tasklet` 인터페이스 구현

```java
public class DemoTasklet implements Tasklet {

    @Override
    public RepeatStatus execute(StepContribution contribution, ChunkContext chunkContext) throws Exception {
        // doSomething
        return null;
    }

}
```

### 코드 살펴보기

- `TaskletStepBuilder` 사용 (아래에서 실펴볼 Chunk 기반은 `SimpleStepBuilder` 사용)

```java
@Bean
public Step step1(JobRepository jobRepository, PlatformTransactionManager transactionManager, Tasklet demoTasklet) {
    return new StepBuilder("step1", jobRepository)
            .tasklet(demoTasklet, transactionManager)
            .build();
}
```

```java
// org.springframework.batch.core.step.builder.StepBuilder#tasklet
public TaskletStepBuilder tasklet(Tasklet tasklet, PlatformTransactionManager transactionManager) {
	return new TaskletStepBuilder(this).tasklet(tasklet, transactionManager);
}
```

```java
// org.springframework.batch.core.step.builder.TaskletStepBuilder#createTasklet
@Override
protected Tasklet createTasklet() {
	return tasklet;
}
```

## Chunk
---
> 청크 지향 처리란, 데이터를 한 번에 하나씩(ItemReader) 읽고, 읽은 데이터를 모아서 **청크(chunk)**를 만드는 방식. <br>
> 이렇게 모은 청크는 하나의 트랜잭션 경계 안에서 ItemWriter를 통해 한번에 쓰여진다. <br>
> 읽은 아이템의 개수가 **커밋 간격(commit interval)**에 도달하면, ItemWriter가 청크 전체를 기록하고, 그 시점에 트랜잭션이 커밋된다.

- `Reader -> Processor -> Writer` 의사 코드

```java
List items = new Arraylist();
for(int i = 0; i < commitInterval; i++){
    Object item = itemReader.read();
    if (item != null) {
        items.add(item);
    }
}

List processedItems = new Arraylist();
for(Object item: items){
    Object processedItem = itemProcessor.process(item);
    if (processedItem != null) {
        processedItems.add(processedItem);
    }
}

itemWriter.write(processedItems);
```

### 코드 살펴보기

- `SimpleStepBuilder` 사용

```java
@Bean
public Step step1(JobRepository jobRepository, PlatformTransactionManager transactionManager,
                  FlatFileItemReader<Person> reader, PersonItemProcessor processor, JdbcBatchItemWriter<Person> writer) {
    return new StepBuilder("step1", jobRepository)
            .<Person, Person>chunk(2, transactionManager)
            .reader(reader)
            .processor(processor)
            .writer(writer)
            .allowStartIfComplete(true)
            .build();
}
```

```java
// org.springframework.batch.core.step.builder.SimpleStepBuilder#chunk(int)
public SimpleStepBuilder<I, O> chunk(int chunkSize) {
	Assert.state(completionPolicy == null || chunkSize == 0,
			"You must specify either a chunkCompletionPolicy or a commitInterval but not both.");
	this.chunkSize = chunkSize;
	return this;
}
```

- `FaultTolerantStepBuilder` 추가 가능

```java
@Bean
public Step step1(JobRepository jobRepository, PlatformTransactionManager transactionManager,
                  FlatFileItemReader<Person> reader, PersonItemProcessor processor, JdbcBatchItemWriter<Person> writer) {
  Step step1 = new StepBuilder("step1", jobRepository)
    .<Person, Person>chunk(2, transactionManager)
    .reader(reader)
    .processor(processor)
    .writer(writer)
    .allowStartIfComplete(true)
    .faultTolerant()
    .skip()
    .retry()
    .reader()
    .build();

  return step1;
}
```

```java
// org.springframework.batch.core.step.builder.SimpleStepBuilder#faultTolerant
public FaultTolerantStepBuilder<I, O> faultTolerant() {
	return new FaultTolerantStepBuilder<>(this);
}
```

- `ChunkOrientedTasklet` 구현체 생성

```java
// org.springframework.batch.core.step.builder.AbstractTaskletStepBuilder
protected abstract Tasklet createTasklet();

public TaskletStep build() {

	registerStepListenerAsChunkListener();

	TaskletStep step = new TaskletStep(getName());

	super.enhance(step);

	step.setChunkListeners(chunkListeners.toArray(new ChunkListener[0]));

	if (this.transactionManager != null) {
		step.setTransactionManager(this.transactionManager);
	}

	if (transactionAttribute != null) {
		step.setTransactionAttribute(transactionAttribute);
	}

	if (stepOperations == null) {

		stepOperations = new RepeatTemplate();

		if (taskExecutor != null) {
			TaskExecutorRepeatTemplate repeatTemplate = new TaskExecutorRepeatTemplate();
			repeatTemplate.setTaskExecutor(taskExecutor);
			repeatTemplate.setThrottleLimit(throttleLimit);
			stepOperations = repeatTemplate;
		}

		((RepeatTemplate) stepOperations).setExceptionHandler(exceptionHandler);

	}
	step.setStepOperations(stepOperations);
	step.setTasklet(createTasklet()); // Tasklet 구현체 만들기

	step.setStreams(streams.toArray(new ItemStream[0]));

	try {
		step.afterPropertiesSet();
	}
	catch (Exception e) {
		throw new StepBuilderException(e);
	}

	return step;

}
```

```java
// org.springframework.batch.core.step.builder.SimpleStepBuilder#createTasklet
@Override
protected Tasklet createTasklet() {
	Assert.state(reader != null, "ItemReader must be provided");
	Assert.state(writer != null, "ItemWriter must be provided");
	RepeatOperations repeatOperations = createChunkOperations();
	SimpleChunkProvider<I> chunkProvider = new SimpleChunkProvider<>(getReader(), repeatOperations);
	SimpleChunkProcessor<I, O> chunkProcessor = new SimpleChunkProcessor<>(getProcessor(), getWriter());
	chunkProvider.setListeners(new ArrayList<>(itemListeners));
	chunkProvider.setMeterRegistry(this.meterRegistry);
	chunkProcessor.setListeners(new ArrayList<>(itemListeners));
	chunkProcessor.setMeterRegistry(this.meterRegistry);
	ChunkOrientedTasklet<I> tasklet = new ChunkOrientedTasklet<>(chunkProvider, chunkProcessor);
	tasklet.setBuffering(!readerTransactionalQueue);
	return tasklet;
}
```

- `ChunkOrientedTasklet`도 결국 `Tasklet`을 구현한 클래스

```java
public class ChunkOrientedTasklet<I> implements Tasklet {

  ...

  @Nullable
  @Override
  public RepeatStatus execute(StepContribution contribution, ChunkContext chunkContext) throws Exception {

    @SuppressWarnings("unchecked")
    Chunk<I> inputs = (Chunk<I>) chunkContext.getAttribute(INPUTS_KEY);
    if (inputs == null) {
      inputs = chunkProvider.provide(contribution);
      if (buffering) {
        chunkContext.setAttribute(INPUTS_KEY, inputs);
      }
    }

    chunkProcessor.process(contribution, inputs);
    chunkProvider.postProcess(contribution, inputs);

    // Allow a message coming back from the processor to say that we
    // are not done yet
    if (inputs.isBusy()) {
      logger.debug("Inputs still busy");
      return RepeatStatus.CONTINUABLE;
    }

    chunkContext.removeAttribute(INPUTS_KEY);
    chunkContext.setComplete();

    if (logger.isDebugEnabled()) {
      logger.debug("Inputs not busy, ended: " + inputs.isEnd());
    }
    return RepeatStatus.continueIf(!inputs.isEnd());

  }

}
```

### 실행 흐름

```java
// org.springframework.batch.core.job.SimpleStepHandler#handleStep
@Override
public StepExecution handleStep(Step step, JobExecution execution)
		throws JobInterruptedException, JobRestartException, StartLimitExceededException {

  ...

	if (shouldStart(lastStepExecution, execution, step)) {

		currentStepExecution = execution.createStepExecution(step.getName());

    ...

		try {
			step.execute(currentStepExecution);
			currentStepExecution.getExecutionContext().put("batch.executed", true);
		}

    ...
	}

	return currentStepExecution;
}
```

```java
// org.springframework.batch.core.step.AbstractStep#execute
@Override
public final void execute(StepExecution stepExecution)
		throws JobInterruptedException, UnexpectedJobExecutionException {

  ...

	try (Observation.Scope scope = observation.openScope()) {
		getCompositeListener().beforeStep(stepExecution);
		open(stepExecution.getExecutionContext());

		try {
			doExecute(stepExecution);
		}
		catch (RepeatException e) {
			throw e.getCause();
		}
		exitStatus = ExitStatus.COMPLETED.and(stepExecution.getExitStatus());

    ...

	}

}

protected abstract void doExecute(StepExecution stepExecution) throws Exception;
```

- `Tasklet.execute`는 하나의 트랜잭션 내에서 실행된다. (`TransactionTemplate.execute`의 콜백 메서드로 호출되는 `ChunkTransactionCallback#doInTransaction`내에서 `Tasklet.execute`가 호출됨)
- `stepOperations.iterate(new StepContextRepeatCallback(stepExecution) { ... }`를 통해 chunk 단위로 반복 (따라서, chunk 단위로 트랜잭션 보장됨)

```java
// org.springframework.batch.core.step.tasklet.TaskletStep#doExecute
@Override
protected void doExecute(StepExecution stepExecution) throws Exception {
  ...

	// Shared semaphore per step execution, so other step executions can run
	// in parallel without needing the lock
	final Semaphore semaphore = createSemaphore();

	stepOperations.iterate(new StepContextRepeatCallback(stepExecution) {

		@Override
		public RepeatStatus doInChunkContext(RepeatContext repeatContext, ChunkContext chunkContext)
				throws Exception {

			StepExecution stepExecution = chunkContext.getStepContext().getStepExecution();

			// Before starting a new transaction, check for
			// interruption.
			interruptionPolicy.checkInterrupted(stepExecution);

			RepeatStatus result;
			try {
				result = new TransactionTemplate(transactionManager, transactionAttribute)
					.execute(new ChunkTransactionCallback(chunkContext, semaphore));
			}
			catch (UncheckedTransactionException e) {
				// Allow checked exceptions to be thrown inside callback
				throw (Exception) e.getCause();
			}

			chunkListener.afterChunk(chunkContext);

			// Check for interruption after transaction as well, so that
			// the interrupted exception is correctly propagated up to
			// caller
			interruptionPolicy.checkInterrupted(stepExecution);

			return result == null ? RepeatStatus.FINISHED : result;
		}

	});

}
```

```java
// org.springframework.batch.core.step.tasklet.TaskletStep.ChunkTransactionCallback#doInTransaction
@Override
public RepeatStatus doInTransaction(TransactionStatus status) {
	TransactionSynchronizationManager.registerSynchronization(this);

	RepeatStatus result = RepeatStatus.CONTINUABLE;

	StepContribution contribution = stepExecution.createStepContribution();

	chunkListener.beforeChunk(chunkContext);

	// In case we need to push it back to its old value
	// after a commit fails...
	oldVersion = new StepExecution(stepExecution.getStepName(), stepExecution.getJobExecution());
	copy(stepExecution, oldVersion);

	try {

		try {
			try {
				result = tasklet.execute(contribution, chunkContext);
				if (result == null) {
					result = RepeatStatus.FINISHED;
				}
			}
			catch (Exception e) {
				if (transactionAttribute.rollbackOn(e)) {
					chunkContext.setAttribute(ChunkListener.ROLLBACK_EXCEPTION_KEY, e);
					throw e;
				}
			}
		}
		finally {

			// If the step operations are asynchronous then we need
			// to synchronize changes to the step execution (at a
			// minimum). Take the lock *before* changing the step
			// execution.
			try {
				semaphore.acquire();
				locked = true;
			}
			catch (InterruptedException e) {
				logger.error("Thread interrupted while locking for repository update");
				stepExecution.setStatus(BatchStatus.STOPPED);
				stepExecution.setTerminateOnly();
				Thread.currentThread().interrupt();
			}

			// Apply the contribution to the step
			// even if unsuccessful
			if (logger.isDebugEnabled()) {
				logger.debug("Applying contribution: " + contribution);
			}
			stepExecution.apply(contribution);

		}

		stepExecutionUpdated = true;

		stream.update(stepExecution.getExecutionContext());

		try {
			// Going to attempt a commit. If it fails this flag will
			// stay false and we can use that later.
			if (stepExecution.getExecutionContext().isDirty()) {
				getJobRepository().updateExecutionContext(stepExecution);
			}
			stepExecution.incrementCommitCount();
			if (logger.isDebugEnabled()) {
				logger.debug("Saving step execution before commit: " + stepExecution);
			}
			getJobRepository().update(stepExecution);
		}
		catch (Exception e) {
			// If we get to here there was a problem saving the step
			// execution and we have to fail.
			String msg = "JobRepository failure forcing rollback";
			logger.error(msg, e);
			throw new FatalStepExecutionException(msg, e);
		}
	}
	catch (Error e) {
		if (logger.isDebugEnabled()) {
			logger.debug("Rollback for Error: " + e.getClass().getName() + ": " + e.getMessage());
		}
		rollback(stepExecution);
		throw e;
	}
	catch (RuntimeException e) {
		if (logger.isDebugEnabled()) {
			logger.debug("Rollback for RuntimeException: " + e.getClass().getName() + ": " + e.getMessage());
		}
		rollback(stepExecution);
		throw e;
	}
	catch (Exception e) {
		if (logger.isDebugEnabled()) {
			logger.debug("Rollback for Exception: " + e.getClass().getName() + ": " + e.getMessage());
		}
		rollback(stepExecution);
		// Allow checked exceptions
		throw new UncheckedTransactionException(e);
	}

	return result;

}
```

- 반복 호출 (`stepOperations.iterate`) 내부

```java
// org.springframework.batch.repeat.support.RepeatTemplate#iterate
@Override
public RepeatStatus iterate(RepeatCallback callback) {

  RepeatContext outer = RepeatSynchronizationManager.getContext();

  RepeatStatus result = RepeatStatus.CONTINUABLE;
  try {
    // This works with an asynchronous TaskExecutor: the
    // interceptors have to wait for the child processes.
    result = executeInternal(callback);
  }
  finally {
    RepeatSynchronizationManager.clear();
    if (outer != null) {
      RepeatSynchronizationManager.register(outer);
    }
  }

  return result;
}

private RepeatStatus executeInternal(final RepeatCallback callback) {

    // 반복 실행을 위한 RepeatContext 생성 (루프 상태 추적: 완료 여부, 반복 횟수 등)
    RepeatContext context = start();

    // 이미 complete 표시된 상태라면 실행 안 함
    boolean running = !isMarkedComplete(context);

    // 모든 리스너(open) 호출 (루프 시작 시 1회 실행)
    for (RepeatListener interceptor : listeners) {
        interceptor.open(context);
        // 리스너가 complete 시킬 수도 있으므로 다시 체크
        running = running && !isMarkedComplete(context);
        if (!running)
            break;
    }

    // 기본 결과 상태는 CONTINUABLE (계속 반복 가능)
    RepeatStatus result = RepeatStatus.CONTINUABLE;

    // 반복 상태 추적 객체 (예외 모음, 비동기 결과 등)
    RepeatInternalState state = createInternalState(context);
    Collection<Throwable> throwables = state.getThrowables(); // 실행 중 발생한 예외 모음
    Collection<Throwable> deferred = new ArrayList<>();       // 나중에 재던질 치명적 예외

    try {

        // 반복 루프 시작 (조건이 만족할 때까지 계속 콜백 실행)
        while (running) {

            // 각 반복(=청크 실행) 직전에 before 리스너 호출
            for (RepeatListener interceptor : listeners) {
                interceptor.before(context);
                running = running && !isMarkedComplete(context); // 중간에 complete 가능
            }

            // 여전히 running 상태일 때만 콜백 실행
            if (running) {
                try {
                    // 콜백 실행 → 여기서 실제로 doInChunkContext 호출
                    // 즉, 트랜잭션 열고 청크 단위로 읽기/처리/쓰기/커밋 진행
                    result = getNextResult(context, callback, state);

                    // after 리스너 호출
                    executeAfterInterceptors(context, result);
                }
                catch (Throwable throwable) {
                    // 콜백 중 예외 발생 시 처리 (재시도/스킵 정책 등 적용 가능)
                    doHandle(throwable, context, deferred);
                }

                // 반복 종료 조건:
                // 1) 결과가 FINISHED
                // 2) context가 complete 상태
                // 3) deferred 예외 존재
                if (isComplete(context, result) || isMarkedComplete(context) || !deferred.isEmpty()) {
                    running = false;
                }
            }
        }

        // 비동기 실행 시 결과 기다리기
        result = result.and(waitForResults(state));

        // throwables 모아둔 것 처리
        for (Throwable throwable : throwables) {
            doHandle(throwable, context, deferred);
        }

        // 내부 상태 해제
        state = null;

    }
    finally {
        try {
            // deferred 예외가 남아 있다면 fatal → 그대로 재던짐
            if (!deferred.isEmpty()) {
                Throwable throwable = deferred.iterator().next();
                if (logger.isDebugEnabled()) {
                    logger.debug("Handling fatal exception explicitly (rethrowing first of " + deferred.size()
                            + "): " + throwable.getClass().getName() + ": " + throwable.getMessage());
                }
                rethrow(throwable);
            }
        }
        finally {
            try {
                // 모든 리스너 close 호출 (루프 종료 시점)
                for (int i = listeners.length; i-- > 0;) {
                    RepeatListener interceptor = listeners[i];
                    interceptor.close(context);
                }
            }
            finally {
                // context 자원 정리
                context.close();
            }
        }
    }

    // 최종 결과 반환 (CONTINUABLE or FINISHED)
    return result;
}
```

- 더이상 읽을게 없으면, `RepeatStatus`가 `FINISHED`로 된다.

```java
// org.springframework.batch.core.step.item.ChunkOrientedTasklet#execute

@Nullable
@Override
public RepeatStatus execute(StepContribution contribution, ChunkContext chunkContext) throws Exception {

	@SuppressWarnings("unchecked")
	Chunk<I> inputs = (Chunk<I>) chunkContext.getAttribute(INPUTS_KEY);
	if (inputs == null) {
		inputs = chunkProvider.provide(contribution);
		if (buffering) {
			chunkContext.setAttribute(INPUTS_KEY, inputs);
		}
	}

  ...

	return RepeatStatus.continueIf(!inputs.isEnd());

}
```

```java
// org.springframework.batch.repeat.RepeatStatus
public static RepeatStatus continueIf(boolean continuable) {
	return continuable ? CONTINUABLE : FINISHED;
}
```

## 적절한 상황 생각해보기 : Tasklet 기반 구성 vs Chunk 기반 구성
---

### Tasklet 기반
- 원자적이고 단순한 작업 (한 방 쿼리, 파일 생성, 스크립트 실행 등)
- 실패 시 전체 롤백 후 재실행으로 충분할 때
- 데이터 건수가 적거나, 중간 커밋 의미가 없을 때

### Chunk 기반
- DB 락 점유를 줄이고 주기적 커밋이 필요한 경우
- 외부 API 호출 등 실패 가능성이 있고, 재시도/스킵이 필요한 경우


## 참고 자료
- [https://docs.spring.io/spring-batch/reference/domain.html](https://docs.spring.io/spring-batch/reference/domain.html)
- [https://docs.spring.io/spring-batch/reference/step/tasklet.html](https://docs.spring.io/spring-batch/reference/step/tasklet.html)
- [https://docs.spring.io/spring-batch/reference/step/chunk-oriented-processing.html](https://docs.spring.io/spring-batch/reference/step/chunk-oriented-processing.html)
- [https://docs.spring.io/spring-batch/reference/step/controlling-flow.html#batchStatusVsExitStatus](https://docs.spring.io/spring-batch/reference/step/controlling-flow.html#batchStatusVsExitStatus)
