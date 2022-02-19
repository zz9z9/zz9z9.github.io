---
title: 스프링 배치 핵심 개념 살펴보기
date: 2021-11-23 22:25:00 +0900
categories: [Spring Batch]
tags: [Job, Step, ]
---

# 들어가기 전
---
해당 글은 [스프링 배치 공식 문서](https://docs.spring.io/spring-batch/docs/4.3.x/reference/html/domain.html#domainLanguageOfBatch)의 내용을 공부하면서 정리한 글입니다.


# 일반적인 배치 구조
---
- 아래 다이어그램은 수십 년 동안 사용된 배치 참조 아키텍처를 단순하게 표현한 것으로, 배치 처리에 필요한 구성 요소의 개요를 보여준다.
- `Job`에는 하나의 단계부터 여러 단계가 있으며, 각 단계에는 하나의 `ItemReader`, `ItemProcessor`, `ItemWriter`가 있다.
- `JobLauncher`를 사용하여 작업을 시작하고, 현재 실행 중인 프로세스에 대한 메타데이터를 `JobRepository`에 저장해야 한다.

![image](https://user-images.githubusercontent.com/64415489/143042927-c1b7e167-c17e-4dde-9778-b203434f8eec.png)

# Job
---
> Job은 **전체 배치 프로세스를 캡슐화**하는 엔티티이다.

- 다른 Spring 프로젝트와 마찬가지로 `Job`은 XML 구성 파일 또는 Java 기반 구성과 함께 연결된다.
- Job은 다음 다이어그램과 같이 전체 계층의 맨 위에 있다.

![image](https://user-images.githubusercontent.com/64415489/143045689-f991a8ae-8b89-48a8-b7d0-d6ecff747f9b.png)

- Job은 Step 인스턴스를 위한 컨테이너 역할을 한다.
  - 즉, 논리적으로 함께 속하는 여러 Step을 결합하고 '재시작 가능성'과 같은 모든 단계에 대한 속성을 전체적으로 구성할 수 있다.
- Job에 대한 속성에는 다음이 포함된다.
  - Job의 간단한 이름
  - Step 인스턴스의 정의 및 순서
  - Job을 재시작할 수 있는지 여부

- Java 구성을 사용하는 경우, Spring Batch는 Job 인터페이스 위에 일부 표준 기능을 더한 `SimpleJob` 클래스 형태로 제공한다.

```java
package org.springframework.batch.core;

import org.springframework.lang.Nullable;

public interface Job {
    String getName();

    boolean isRestartable();

    void execute(JobExecution var1);

    @Nullable
    JobParametersIncrementer getJobParametersIncrementer();

    JobParametersValidator getJobParametersValidator();
}
```

```java
package org.springframework.batch.core.job;

public class SimpleJob extends AbstractJob {
    private List<Step> steps;

    public SimpleJob() {
        this((String)null);
    }

    public SimpleJob(String name) {
        super(name);
        this.steps = new ArrayList();
    }

    public void setSteps(List<Step> steps) {
        this.steps.clear();
        this.steps.addAll(steps);
    }

    public Collection<String> getStepNames() {
        List<String> names = new ArrayList();
        Iterator var2 = this.steps.iterator();

        while(var2.hasNext()) {
            Step step = (Step)var2.next();
            names.add(step.getName());
            if (step instanceof StepLocator) {
                names.addAll(((StepLocator)step).getStepNames());
            }
        }

        return names;
    }

    public void addStep(Step step) {
        this.steps.add(step);
    }

    public Step getStep(String stepName) {
        Iterator var2 = this.steps.iterator();

        while(var2.hasNext()) {
            Step step = (Step)var2.next();
            if (step.getName().equals(stepName)) {
                return step;
            }

            if (step instanceof StepLocator) {
                Step result = ((StepLocator)step).getStep(stepName);
                if (result != null) {
                    return result;
                }
            }
        }

        return null;
    }

    protected void doExecute(JobExecution execution) throws JobInterruptedException, JobRestartException, StartLimitExceededException {
        StepExecution stepExecution = null;
        Iterator var3 = this.steps.iterator();

        while(var3.hasNext()) {
            Step step = (Step)var3.next();
            stepExecution = this.handleStep(step, execution);
            if (stepExecution.getStatus() != BatchStatus.COMPLETED) {
                break;
            }
        }

        if (stepExecution != null) {
            if (logger.isDebugEnabled()) {
                logger.debug("Upgrading JobExecution status: " + stepExecution);
            }

            execution.upgradeStatus(stepExecution.getStatus());
            execution.setExitStatus(stepExecution.getExitStatus());
        }

    }
}

```


- 자바 기반 구성을 사용할 때, 아래의 예와 같이 Job의 인스턴스화에 빌더 컬렉션을 사용할 수 있다.

```java
@Bean
public Job footballJob() {
    return this.jobBuilderFactory.get("footballJob")
                     .start(playerLoad())
                     .next(gameLoad())
                     .next(playerSummarization())
                     .build();
}
```

```java
@Bean
public Job importUserJob(JobCompletionNotificationListener listener, Step step1) {
    return jobBuilderFactory.get("importUserJob")
            .incrementer(new RunIdIncrementer())
            .listener(listener)
            .flow(step1)
            .end()
            .build();
}
```

# JobInstance
---
> `JobInstance`는 논리적 작업 실행 단위이다.

- 위에서 살펴본 다이어그램의 'EndOfDay' 작업과 같이 하루가 끝날 때 한 번 실행해야 하는 배치 작업을 생각해보자.
  - 'EndOfDay' 작업이 하나 있지만 각 작업 실행은 개별적으로 추적해야 한다.
  - 이러한 경우, 하루에 하나의 논리적 JobInstance가 있다.
    - 예를 들어 1월 1일 실행, 1월 2일 실행 등이 있다.
    - 1월 1일 실행이 처음에 실패하고 다음날 다시 실행되더라도 여전히 1월 1일 실행이다.(보통 1월 1일 실행이 1월 1일 데이터를 처리한다는 의미).
    - 따라서 각 JobInstance는 여러 번의 실행을 가질 수 있으며, **특정 JobParameters를 식별하는 JobInstance 하나만 한 번에 실행할 수 있다.**

- JobInstance는 로드할 데이터와 전혀 관련이 없다.
  - 데이터가 로드되는 방법을 결정하는 것은 전적으로 ItemReader 구현에 달려 있다.
- 예를 들어 EndOfDay 시나리오에서는 데이터에 데이터가 속한 '유효 날짜' 또는 '예약 날짜'를 나타내는 컬럼이 있을 수 있다.
  - 위 케이스의 경우, 1월 1일 런은 1월 1일 데이터만 로드하고 1월 2일 런은 2일 데이터만 로드한다.
  - 이러한 결정은 비즈니스 관점에서의 결정일 가능성이 높기 때문에, ItemReader의 구현에 달려 있다.
- 동일한 JobInstance를 사용하면 이전 실행의 '상태'(ExecutionContext)가 사용되는지 여부가 결정된다.
- 새로운 JobInstance를 사용하는 것은 '처음부터 시작'을 의미하며, 기존 인스턴스를 사용하는 것은 일반적으로 '멈춘 곳부터 시작'을 의미한다.


# JobParameters
---

