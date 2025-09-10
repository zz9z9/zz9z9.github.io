---
title: Spring Batch - Job 개념
date: 2025-09-05 21:25:00 +0900
categories: [지식 더하기, 이론]
tags: [Spring Batch]
---


## 개념

### Job
> 배치 작업

![img](/assets/img/spring-batch-job-step.png)
<br>
(출처 : [https://docs.spring.io/spring-batch/reference/domain.html](https://docs.spring.io/spring-batch/reference/domain.html))

- 하나의 Job은 하나 이상의 Step을 가지며, 각각의 Step은 하나의 `ItemReader`, 하나의 `ItemProcessor`, 그리고 하나의 `ItemWriter`를 가진다.
 - 즉, Job은 Step 인스턴스들을 담는 컨테이너이다.
- Job은 `JobLauncher`를 통해 실행되며, 현재 실행 중인 프로세스에 대한 메타데이터는 `JobRepository`에 저장된다.
  - `JobRepository` : Spring Batch에서 `JobExecution`과 `StepExecution` 같은 다양한 영속화된 도메인 객체들에 대해 기본적인 CRUD(생성, 조회, 수정, 삭제) 작업을 수행하기 위한 저장소

### JobInstance
> 배치 작업의 실행 단위

![img](/assets/img/spring-batch-jobinstance-jobparameters.png)
<br>
(출처 : [https://docs.spring.io/spring-batch/reference/domain.html](https://docs.spring.io/spring-batch/reference/domain.html))

- 예를 들어 (위 그림의) `EndOfDay` Job의 경우 **하루마다 하나의 논리적 JobInstance**가 존재한다.
  - 만약 1월 1일 실행이 처음에 실패하고 다음 날 다시 실행된다 하더라도, 그것은 여전히 1월 1일 실행이다.
  - 실행은 보통 처리되는 데이터와 대응된다. 즉, 1월 1일 실행은 1월 1일 데이터를 처리한다는 의미이다.
  - 즉, `JobInstance`는 여러 번의 실행(`JobExecution`)을 가질 수 있다.
- 특정 Job과 그것을 식별하는 JobParameters에 대응되는 JobInstance은 동시에 하나만(또는 한번만) 실행될 수 있다.
  - `JobInstance` = `Job` + `식별용 JobParameters`
  - `allowStartIfComplete` 속성을 활용하면 완료된 Job을 재실행할 수 있다.

- `BATCH_JOB_INSTANCE`의 `JOB_KEY`가 파라미터의 해시값
  - 파라미터 없는 경우에도 해시값 만들어짐

![img](/assets/img/spring-batch-job-parameters.png)

- 새로운 JobInstance를 사용하는 것은 “처음부터 시작”을 의미하며, 기존 인스턴스를 사용하는 것은 일반적으로(`ExecutionContext`을 활용하여) “이전 실행 지점부터 이어서 시작”을 의미한다.

### JobExecution
> '실행 시도'를 나타내는 개념

- 해당 실행과 연결된 `JobInstance`는 실행이 성공적으로 완료될 때까지 완료된 것으로 간주되지 않는다.
- 예를 들어 앞서 설명한 `EndOfDay` Job을 기준으로, 2017년 1월 1일의 `JobInstance가` 첫 실행에서 실패했다고 가정해 보자.
- 동일한 식별 `JobParameters(2017-01-01)`로 다시 실행하면 새로운 `JobExecution`이 생성된다.
- 그러나 여전히 `JobInstance`는 하나뿐이다.

### 예시 상황

> EndOfDayJob 2017-01-01 실행 (21:00 시작 → 21:30 실패) <br>
> 다음날 같은 파라미터로 재실행 → 성공 (21:00 → 21:30) <br>
> 이어서 2017-01-02 실행 → 성공 (21:31 → 22:29)

- `BATCH_JOB_INSTANCE` 테이블

| JOB\_INST\_ID | JOB\_NAME   |
| ------------- | ----------- |
| 1             | EndOfDayJob |
| 2             | EndOfDayJob |


- `BATCH_JOB_EXECUTION` 테이블

| JOB\_EXEC\_ID | JOB\_INST\_ID | START\_TIME      | END\_TIME        | STATUS    |
| ------------- | ------------- | ---------------- | ---------------- | --------- |
| 1             | 1             | 2017-01-01 21:00 | 2017-01-01 21:30 | FAILED    |
| 2             | 1             | 2017-01-02 21:00 | 2017-01-02 21:30 | COMPLETED |
| 3             | 2             | 2017-01-02 21:31 | 2017-01-02 22:29 | COMPLETED |

## 코드 살짝 들여다보기

### Job 계층구조

```
Job (Interface)
   └── AbstractJob (Abstract Class)
         ├── SimpleJob (Concrete Class)
         └── FlowJob (Concrete Class)
```

```java
// org.springframework.batch.core.job.AbstractJob
abstract protected void doExecute(JobExecution execution) throws JobExecutionException;

@Override
public final void execute(JobExecution execution) {

	Assert.notNull(execution, "jobExecution must not be null");
	execution.getExecutionContext().put(SpringBatchVersion.BATCH_VERSION_KEY, SpringBatchVersion.getVersion());

  ...

	try (Observation.Scope scope = observation.openScope()) {

		jobParametersValidator.validate(execution.getJobParameters());

		if (execution.getStatus() != BatchStatus.STOPPING) {

			execution.setStartTime(LocalDateTime.now());
			updateStatus(execution, BatchStatus.STARTED);

			listener.beforeJob(execution);

			try {
				doExecute(execution);

        ...
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

### JobInstance는 JobParameters로 식별

```java
// org.springframework.batch.core.repository.dao.JdbcJobInstanceDao#createJobInstance

@Override
public JobInstance createJobInstance(String jobName, JobParameters jobParameters) {

  Assert.notNull(jobName, "Job name must not be null.");
  Assert.notNull(jobParameters, "JobParameters must not be null.");

  Assert.state(getJobInstance(jobName, jobParameters) == null, "JobInstance must not already exist");

  Long jobInstanceId = jobInstanceIncrementer.nextLongValue();

  JobInstance jobInstance = new JobInstance(jobInstanceId, jobName);
  jobInstance.incrementVersion();

  Object[] parameters = new Object[] { jobInstanceId, jobName, jobKeyGenerator.generateKey(jobParameters),
    jobInstance.getVersion() };
  getJdbcTemplate().update(getQuery(CREATE_JOB_INSTANCE), parameters,
    new int[] { Types.BIGINT, Types.VARCHAR, Types.VARCHAR, Types.INTEGER });

  return jobInstance;
}
```

### 특정 Job과 그것을 식별하는 JobParameters에 대응되는 JobInstance은 한번만 실행 가능

- 관련 에러 메세지

```
batch.core.job.SimpleStepHandler : Step already complete or not restartable, so no action to execute: StepExecution: id=10, version=5, name=step1, status=COMPLETED, exitStatus=COMPLETED, ...
```

- 호출 흐름

![img](/assets/img/spring-batch-job-callstack.png)

- job이름 , 파라미터로 실행 내역을 찾는다.

```java
// org.springframework.batch.core.launch.support.TaskExecutorJobLauncher#run
jobExecution = jobRepository.createJobExecution(job.getName(), jobParameters);

		try {
			taskExecutor.execute(new Runnable() {

				@Override
				public void run() {
            ...
						job.execute(jobExecution);
```

- 찾은 실행 내역에서 `JobInstance`를 가져온다.

```java
// org.springframework.batch.core.job.SimpleStepHandler#handleStep
JobInstance jobInstance = execution.getJobInstance();

StepExecution lastStepExecution = jobRepository.getLastStepExecution(jobInstance, step.getName());
if (stepExecutionPartOfExistingJobExecution(execution, lastStepExecution)) {
	// If the last execution of this step was in the same job, it's
	// probably intentional so we want to run it again...
	if (logger.isInfoEnabled()) {
		logger.info(String.format(
				"Duplicate step [%s] detected in execution of job=[%s]. "
						+ "If either step fails, both will be executed again on restart.",
				step.getName(), jobInstance.getJobName()));
	}
	lastStepExecution = null;
}
StepExecution currentStepExecution = lastStepExecution;

if (shouldStart(lastStepExecution, execution, step)) {
  ...
}
```

- `jobRepository.getLastStepExecution` 호출로 실행되는 쿼리

```sql
-- org.springframework.batch.core.repository.dao.JdbcStepExecutionDao#GET_LAST_STEP_EXECUTION
SELECT ...
FROM BATCH_JOB_EXECUTION JE
    JOIN BATCH_STEP_EXECUTION SE ON SE.JOB_EXECUTION_ID = JE.JOB_EXECUTION_ID
WHERE JE.JOB_INSTANCE_ID = ?
  AND SE.STEP_NAME = ?
```

- StepExecution의 stepStatus 가 COMPLETED인데 `allowStartIfComplete` 속성이 `false`이거나 stepStatus가 `ABANDONED` 이면 특정 job을 동일한 파라미터로 재실행 불가능

```java
// org.springframework.batch.core.job.SimpleStepHandler#shouldStart
protected boolean shouldStart(StepExecution lastStepExecution, JobExecution jobExecution, Step step)
		throws JobRestartException, StartLimitExceededException {

	BatchStatus stepStatus;
	if (lastStepExecution == null) {
		stepStatus = BatchStatus.STARTING;
	}
	else {
		stepStatus = lastStepExecution.getStatus();
	}

  ...

	if ((stepStatus == BatchStatus.COMPLETED && !step.isAllowStartIfComplete())
			|| stepStatus == BatchStatus.ABANDONED) {
		// step is complete, false should be returned, indicating that the
		// step should not be started
		if (logger.isInfoEnabled()) {
			logger.info("Step already complete or not restartable, so no action to execute: " + lastStepExecution);
		}
		return false;
	}

  ...

}
```

### 특정 Job과 그것을 식별하는 JobParameters에 대응되는 JobInstance은 동시에 하나만 실행 가능

- 관련 에러 메세지

```
Caused by: org.springframework.batch.core.repository.JobExecutionAlreadyRunningException: A job
execution for this job is already running: JobInstance: id=1, ...
```

```java
// org.springframework.batch.core.repository.support.SimpleJobRepository#createJobExecution
@Override
public JobExecution createJobExecution(String jobName, JobParameters jobParameters)
		throws JobExecutionAlreadyRunningException, JobRestartException, JobInstanceAlreadyCompleteException {

	Assert.notNull(jobName, "Job name must not be null.");
	Assert.notNull(jobParameters, "JobParameters must not be null.");

	JobInstance jobInstance = jobInstanceDao.getJobInstance(jobName, jobParameters);
	ExecutionContext executionContext;

	if (jobInstance != null) {

		List<JobExecution> executions = jobExecutionDao.findJobExecutions(jobInstance);

		if (executions.isEmpty()) {
			throw new IllegalStateException("Cannot find any job execution for job instance: " + jobInstance);
		}

		for (JobExecution execution : executions) {
			if (execution.isRunning()) {
				throw new JobExecutionAlreadyRunningException(
						"A job execution for this job is already running: " + jobInstance);
			}

      ...
		}
		executionContext = ecDao.getExecutionContext(jobExecutionDao.getLastJobExecution(jobInstance));
	}

  ...

	return jobExecution;

}
```

```java
// org.springframework.batch.core.BatchStatus
public enum BatchStatus {

  /**
   * The batch job has successfully completed its execution.
   */
  COMPLETED,
  /**
   * Status of a batch job prior to its execution.
   */
  STARTING,
  /**
   * Status of a batch job that is running.
   */
  STARTED,
  /**
   * Status of batch job waiting for a step to complete before stopping the batch job.
   */
  STOPPING,
  /**
   * Status of a batch job that has been stopped by request.
   */
  STOPPED,
  /**
   * Status of a batch job that has failed during its execution.
   */
  FAILED,
  /**
   * Status of a batch job that did not stop properly and can not be restarted.
   */
  ABANDONED,
  /**
   * Status of a batch job that is in an uncertain state.
   */
  UNKNOWN;

  public boolean isRunning() {
    return this == STARTING || this == STARTED || this == STOPPING;
  }

  ...

}

```


## 참고 자료
- [https://docs.spring.io/spring-batch/reference/domain.html](https://docs.spring.io/spring-batch/reference/domain.html)
- [https://docs.spring.io/spring-batch/reference/job/configuring-repository.html](https://docs.spring.io/spring-batch/reference/job/configuring-repository.html)
