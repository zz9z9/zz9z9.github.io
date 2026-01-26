---
title: 젠킨스 Pipeline 알아보기
date: 2026-01-26 22:25:00 +0900
categories: [지식 더하기, 이론]
tags: [Jenkins]
---

## Jenkins Pipeline
> CD(Continuous Delivery) 파이프라인을 **코드로 정의**하는 **Jenkins 플러그인 모음**

### 핵심 개념

```
Pipeline
  └── Stage
    └── Step
```

| 개념 | 설명 | 예시 |
| --- | ---- | --- |
| Pipeline | 전체 빌드 프로세스 정의 | `pipeline { }` |
| Node | 파이프라인을 실행하는 머신 | `node { }` (Scripted) |
| Stage | 논리적 작업 단위 | "Build", "Test", "Deploy" |
| Step | 실제 수행할 단일 작업 | sh 'make', echo 'hello' |

### Pipeline의 장점

| 특징 | 설명 |
| ---- | ---- |
| Code | 파이프라인을 코드로 작성 → Git 버전 관리 가능 |
| Durable | Jenkins 재시작해도 파이프라인 유지됨 |
| Pausable | 중간에 멈추고 사람의 승인을 기다릴 수 있음 |
| Versatile | 분기(fork/join), 반복(loop), 병렬 처리 지원 |
| Extensible | 플러그인/Shared Libraries로 확장 가능 |


## Jenkinsfile
> Jenkins Pipeline을 정의하는 텍스트 파일

```
┌─────────────────────────────────────────────────┐
│  프로젝트 저장소 (Git)                            │
├─────────────────────────────────────────────────┤
│  📁 src/                                        │
│  📁 test/                                       │
│  📄 pom.xml                                     │
│  📄 Jenkinsfile  ← 이 파일!                      │
└─────────────────────────────────────────────────┘
```

- Jenkinsfile은 프로젝트 루트에 위치하며, Jenkins가 이 파일을 읽어서 파이프라인을 실행

### 장점

**기존 방식 (Web UI)**
- Jenkins 웹 화면에서 직접 설정
  - 설정 변경 이력 추적 어려움
  - 다른 프로젝트에 복사하기 번거로움
  - 누가 뭘 바꿨는지 모름

**Jenkinsfile 방식 (Pipeline as Code)**
- Git으로 버전 관리
- 코드 리뷰 가능
- 변경 이력 추적
- 브랜치별 다른 파이프라인 가능

### 주요 기능

| 기능 | 설명 |
| --- | ---- |
| 환경변수 | `env.BUILD_ID`, `env.WORKSPACE` 등 사용 가능 |
| Credentials | `credentials('credential-id')`로 비밀 정보 접근 |
| 파라미터 | `params.PARAM_NAME`으로 빌드 파라미터 사용 |
| 실패 처리 | `post { failure { ... } }` 블록 활용 |
| 다중 Agent | Stage별로 다른 agent 지정 가능 |

### 주요 문법 요소

```groovy
pipeline {
    agent any    // 필수

    stages {     // 필수
        stage('X') {   // 최소 1개
            steps {   // 필수
                // 작업 내용
            }
        }
    }
}
```

| Directive | 용도 | 예시 |
| --------- | ----| --- |
| agent | 실행 환경 지정 | `agent { docker 'maven:3.9' }`, `agent any`(사용 가능한 아무 노드에서 실행) |
| environment | 환경변수 설정 | `environment { CC = 'clang' }` |
| `options { }` | 파이프라인 옵션 (타임아웃, 재시도 등) | options { timeout(time: 1, unit: 'HOURS') } |
| `parameters` | 빌드 파라미터 | `parameters { string(name: 'ENV') }` |
| `triggers` | 자동 트리거 | `triggers { cron('H */4 * * 1-5') }` |
| `when` | 조건부 실행 | `when { branch 'master' }` |
| `post` | 빌드 후 처리 | `post { always { junit '**/*.xml' } }` |
| `stages { }` | Stage들을 감싸는 블록 | |
| `stage('이름') { }` | 개별 단계 정의 | |
| `sh 'command'` | 쉘 명령어 실행 | |

**when 조건 종류**
- branch 'pattern' - 브랜치 매칭
- environment name: 'X', value: 'Y' // 환경변수 조건
- expression { return true }  // Groovy 표현식
- allOf { }, anyOf { }, not { } // 복합 조건

```groovy
when {
    allOf {
        branch 'master'
        environment name: 'DEPLOY', value: 'true'
        not {
            expression {
                return false
            }
        }
    }
}
```

### 두 가지 문법 스타일
**1. Declarative (권장)**
> 구조화된 문법, 읽기 쉬움, 문법 검증 가능

```groovy
pipeline {
    agent any

    stages {
        stage('Build') {
            steps {
                sh 'make'
            }
        }

        stage('Test') {
            steps {
                sh 'make check'
                junit 'reports/**/*.xml'
            }
        }

        stage('Deploy') {
            steps {
                sh 'make publish'
            }
        }
    }
}
```

**2. Scripted**
> Groovy 자유도 높음, 복잡한 로직에 유리

```groovy
node {
    stage('Build') {
        sh 'make'
    }

    stage('Test') {
        sh 'make check'
        junit 'reports/**/*.xml'
    }

    stage('Deploy') {
        sh 'make publish'
    }
}
```

## Pipeline 실행 흐름과 실패 전파
---

> Jenkins Pipeline은 위에서 아래로 순차 실행되며, 기본적으로 하나의 Step이라도 실패하면 전체 파이프라인이 실패한다.

```groovy
stage('Test') {
    steps {
        sh 'exit 1'   // 이 시점에서 파이프라인 실패
        sh 'echo never called'
    }
}
```

- 실패한 Stage 이후 Stage는 실행되지 않음
- 단, `post` 블록은 실행됨

### post 블록
> post는 파이프라인 또는 Stage 단위로 선언 가능하다.

```groovy
post {
    success {
        echo '빌드 성공'
    }
    failure {
        echo '빌드 실패'
    }
    always {
        echo '항상 실행'
    }
}
```

| 조건       | 설명                |
| -------- | ----------------- |
| always   | 항상 실행             |
| success  | 성공 시              |
| failure  | 실패 시              |
| unstable | 테스트 실패 등으로 불안정 상태 |
| aborted  | 사용자가 중단           |
| changed  | 이전 빌드와 상태가 달라졌을 때 |

## 기타
---

### Stage 단위 agent 지정
> 전체 파이프라인에 `agent any`를 쓰더라도, Stage별로 다른 실행 환경을 지정할 수 있다.

```groovy
pipeline {
    agent any

    stages {
        stage('Build') {
            agent {
                docker {
                    image 'maven:3.9'
                }
            }
            steps {
                sh 'mvn clean package'
            }
        }

        stage('Deploy') {
            agent {
                label 'deploy-node'
            }
            steps {
                sh './deploy.sh'
            }
        }
    }
}
```

- 빌드 / 배포 환경 분리할 때 매우 중요

### parallel – 병렬 실행
> 여러 Stage를 동시에 실행할 수 있다.

```groovy
stage('Test') {
    parallel {
        stage('Unit Test') {
            steps {
                sh './gradlew test'
            }
        }
        stage('Integration Test') {
            steps {
                sh './gradlew integrationTest'
            }
        }
    }
}
```

- 전체 병렬 중 하나라도 실패하면 전체 실패
- 테스트 시간 단축에 매우 유용

### input – 사람 승인 대기
> CD 파이프라인에서 운영 배포 전 승인 받을 때 자주 사용한다.

```groovy
stage('Approve') {
    steps {
        input message: '운영에 배포할까요?', ok: 'Deploy'
    }
}
```

- Jenkins UI에서 버튼 클릭 전까지 대기
- 승인 이력 남음

### try-catch (Scripted 또는 script 블록)
> Declarative에서도 `script {}` 블록 안에서는 Groovy 로직 사용 가능하다.

```groovy
stage('Deploy') {
    steps {
        script {
            try {
                sh './deploy.sh'
            } catch (e) {
                echo '배포 실패'
                currentBuild.result = 'FAILURE'
                throw e
            }
        }
    }
}
```

- 실무 권장 패턴 : Declarative + 필요한 부분만 `script {}`

### 실무에서 자주 쓰는 Jenkinsfile 뼈대

```groovy
pipeline {
    agent any

    options {
        timeout(time: 30, unit: 'MINUTES')
    }

    parameters {
        choice(name: 'ENV', choices: ['dev', 'staging', 'prod'])
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build & Test') {
            steps {
                sh './gradlew build'
            }
        }

        stage('Deploy') {
            when {
                branch 'main'
            }
            steps {
                input message: '배포 진행?', ok: 'Deploy'
                sh './deploy.sh'
            }
        }
    }

    post {
        failure {
            echo '빌드 실패 알림 전송'
        }
    }
}
```

## 참고 자료
- [https://www.jenkins.io/doc/book/pipeline/](https://www.jenkins.io/doc/book/pipeline/)
- [https://www.jenkins.io/doc/book/pipeline/jenkinsfile/](https://www.jenkins.io/doc/book/pipeline/jenkinsfile/)
- [https://www.jenkins.io/doc/book/pipeline/syntax/](https://www.jenkins.io/doc/book/pipeline/syntax/)
- Claude Code / Chat GPT
