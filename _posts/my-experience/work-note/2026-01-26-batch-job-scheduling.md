---
title: 젠킨스로 배치 Job 스케줄링 생각해보기
date: 2026-01-26 22:25:00 +0900
categories: [지식 더하기, 이론]
tags: [Jenkins]
---

새로운 시스템의 배치 Job 스케줄링을 젠킨스로 하려고한다.
사실 기존에도 Jenkins를 사용중이지만, 운영하면서 느꼈던 불편한 점들이 많아,
새로운 시스템에서는 기존 방식을 개선하고자한다.

## 기존 방식
---

```
[스케줄링]
JOB_A
ㄴ JOB_A_1 -> JOB_A_2 ...

JOB_B

JOB_C
ㄴ JOB_C_1 -> JOB_C_2 ...
```

### 내가 생각하는 문제점

**Job 관리/파악 어려움**

- 실행 순서 및 연계된 JOB 구조가 매우 복잡함
  - 별도의 관리 문서 없으면 파악이 매우 어려움 (어떤게 연계된 배치들인지, 어떤게 단독인지)
  - 연계된 배치들은 어떤 목적으로(ex : 가맹점 정산) 연계된건지 알기가 어려움, 또한 어떠한 목적(카테고리)들이 있는지 파악이 안됨

- 어떤 Job이 몇 시에 실행되는지 한 눈에 보이는게 없음

- 연계 배치는 `Job1 -> Job2 -> ...` 이런 네이밍으로 관리함
  - 중간에 실행될 Job이 추가되면 그 이후 네이밍 다 바꿔줘야됨

**지표 파악이 어려움**

- `JOB_A` 전체 수행에 걸리는 시간을 파악하려면, 모든 연계 배치의 실행시간을 각각 알고 합을 구해야됨

**연계 방식의 세밀함이 떨어짐**
- 연계된 다음 Job의 실행은 젠킨스의 `Trigger If stable`을 활용하고 있어서, 프로세스의 exit code가 1(stable)인지 0(unstable)인지로만 판단
  - 스프링 배치의 `ExitStatus` 등 활용 못함

**배치 job 실행 모니터링**
- spring admin batch plugin 사용중 (한참전에 deprecated됨 -> 젠킨스 특정 버전 이후부터 해당 플러그인 사용하려면, 수동으로 파일 복사해오고, 특정 클래스도 추가해줘야됨)

## 원하는 TO-BE
---

**Job 관리/파악 쉽게**
- 별도 문서 없이도 다음을 파악하기 쉽게:
  - **어떤 Job**들이, **어떤 목적**으로 연계된건지
  - Job별 실행 시작 시간

**지표 파악이 용이하게**
- 주요 지표:
  - Job별 실행시간
  - Step별 실행시간
  - 연계배치 전체 실행시간

**연계 방식의 세밀함**
- 1, 0이 아닌 다양한 상태값으로 제어 가능하도록
  - ex: `NOOP`이면 다음 Job 실행하지 않음 등

**배치 job 실행 모니터링**
- 위에서 언급한 지표, 어떤 Status로 Job이 끝났는지 등 쉽게 모니터링 하는 도구 ?

## 클로드 코드 추천
> 내가 원하는 to-be가 가능하려면 ?

### 1. Jenkins Pipeline (Declarative/Scripted) 활용 - 젠킨스 유지 시
> 기존의 Freestyle Job + Trigger 방식 대신 Pipeline as Code로 전환하면 많은 문제가 해결됩니다.

```
// Jenkinsfile 예시: 가맹점 정산 파이프라인
pipeline {
agent any

    options {
        buildDiscarder(logRotator(numToKeepStr: '30'))
        timestamps()
    }

    stages {
        stage('가맹점 정산') {
            stages {
                stage('1. 거래내역 집계') {
                    steps {
                        script {
                            def result = runBatchJob('transaction-aggregation')
                            if (result.exitStatus == 'NOOP') {
                                currentBuild.result = 'NOT_BUILT'
                                error("NOOP - 처리할 데이터 없음")
                            }
                        }
                    }
                }
                stage('2. 수수료 계산') {
                    steps {
                        runBatchJob('fee-calculation')
                    }
                }
                stage('3. 정산금 확정') {
                    steps {
                        runBatchJob('settlement-confirm')
                    }
                }
            }
        }
    }

    post {
        always {
            // 전체 파이프라인 실행 시간 자동 기록
            script {
                def duration = currentBuild.durationString
                echo "전체 실행 시간: ${duration}"
            }
        }
    }
}
```

**장점**
- 연계 Job 구조가 코드로 명확히 보임
- 네이밍 변경 필요 없음 (순서는 코드로 관리)
- Git으로 버전 관리 가능
- Blue Ocean UI로 시각화

---

### 2. **Spring Cloud Data Flow (SCDF)** - 더 추천

Spring Batch를 사용 중이시라면 **SCDF**가 가장 자연스러운 선택입니다.

┌─────────────────────────────────────────────────────┐
│  Spring Cloud Data Flow Dashboard                   │
├─────────────────────────────────────────────────────┤
│  Task: 가맹점-정산                                    │
│  ┌─────────┐   ┌─────────┐   ┌─────────┐           │
│  │거래집계  │ → │수수료계산│ → │정산확정  │           │
│  └─────────┘   └─────────┘   └─────────┘           │
│  Status: ✅     Status: ✅     Status: 🔄           │
│  Duration: 5m   Duration: 3m   Duration: running    │
└─────────────────────────────────────────────────────┘

**장점**
- Spring Batch의 ExitStatus, StepExecution 완벽 지원
- Job/Step별 실행시간 자동 추적
- 연계 배치를 Composed Task로 정의
- 웹 UI에서 DAG 형태로 시각화
- REST API로 프로그래밍 방식 제어

### 3. **하이브리드: Jenkins + Spring Batch 메타테이블 활용**

젠킨스를 유지하면서 Spring Batch의 메타테이블을 활용하는 방식:
┌──────────────┐     ┌──────────────────────────────┐
│   Jenkins    │     │     Spring Batch DB          │
│  (스케줄링)   │────▶│  BATCH_JOB_EXECUTION         │
└──────────────┘     │  BATCH_STEP_EXECUTION        │
└──────────────────────────────┘
│
▼
┌──────────────────────────────┐
│   모니터링 대시보드            │
│  (Grafana + Custom Query)    │
└──────────────────────────────┘

## Question

### 파이프라인 방식에서  1,2,3 STEP 중에 2,3번만 다시 실행하고 싶으면 별도의 파이프라인을 다시 만들어야하는거야 ?
> 별도 파이프라인을 만들 필요 없이 몇 가지 방법으로 해결할 수 있습니다.

**방법1: 파라미터로 시작 Stage 선택**

pipeline {
agent any

    parameters {
        choice(
            name: 'START_FROM',
            choices: ['1-거래내역집계', '2-수수료계산', '3-정산금확정'],
            description: '어느 단계부터 시작할까요?'
        )
    }

    stages {
        stage('1. 거래내역 집계') {
            when {
                expression {
                    params.START_FROM == '1-거래내역집계'
                }
            }
            steps {
                runBatchJob('transaction-aggregation')
            }
        }
        stage('2. 수수료 계산') {
            when {
                expression {
                    params.START_FROM in ['1-거래내역집계', '2-수수료계산']
                }
            }
            steps {
                runBatchJob('fee-calculation')
            }
        }
        stage('3. 정산금 확정') {
            // 항상 실행 (마지막 단계)
            steps {
                runBatchJob('settlement-confirm')
            }
        }
    }
}

**실행 화면:**

┌─────────────────────────────────────┐
│  Build with Parameters              │
├─────────────────────────────────────┤
│  START_FROM: [2-수수료계산    ▼]    │
│                                     │
│  [Build]                            │
└─────────────────────────────────────┘

**방법 2: 체크박스로 개별 Stage 선택**

pipeline {
agent any

    parameters {
        booleanParam(name: 'RUN_거래집계', defaultValue: true)
        booleanParam(name: 'RUN_수수료계산', defaultValue: true)
        booleanParam(name: 'RUN_정산확정', defaultValue: true)
    }

    stages {
        stage('1. 거래내역 집계') {
            when { expression { params.RUN_거래집계 } }
            steps {
                runBatchJob('transaction-aggregation')
            }
        }
        stage('2. 수수료 계산') {
            when { expression { params.RUN_수수료계산 } }
            steps {
                runBatchJob('fee-calculation')
            }
        }
        stage('3. 정산금 확정') {
            when { expression { params.RUN_정산확정 } }
            steps {
                runBatchJob('settlement-confirm')
            }
        }
    }
}

**실행 화면:**
┌─────────────────────────────────────┐
│  Build with Parameters              │
├─────────────────────────────────────┤
│  ☐ RUN_거래집계                      │
│  ☑ RUN_수수료계산                    │
│  ☑ RUN_정산확정                      │
│                                     │
│  [Build]                            │
└─────────────────────────────────────┘



**방법 3: Restart from Stage (Jenkins 내장 기능)**
- Blue Ocean이나 최신 Jenkins UI에서는 **실패한 Stage부터 재시작**이 가능합니다.
- 단, 이 기능은 Declarative Pipeline에서만 지원되고, 일부 제약이 있습니다.

Pipeline: 가맹점정산
┌─────────┐   ┌─────────┐   ┌─────────┐
│거래집계  │ → │수수료계산│ → │정산확정  │
│   ✅    │   │   ❌    │   │   ⏸    │
└─────────┘   └─────────┘   └─────────┘
│
└── [Restart from here] 클릭 가능
