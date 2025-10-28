
## Debezium
---

> Debezium은 CDC(Change Data Capture)를 위한 오픈 소스 분산 플랫폼이다.

- Debezium은 Kafka Connect와 호환되는 커넥터(Connectors) 들을 제공합니다.
- 각 커넥터는 특정 데이터베이스 관리 시스템(DBMS) 과 연동되며, DBMS에서 발생하는 데이터 변경 사항을 실시간으로 감지하여 그 기록을 Kafka 토픽으로 스트리밍합니다.
- 그 후, 애플리케이션은 Kafka 토픽에 저장된 이벤트 레코드들을 읽어서 해당 변경 내역을 처리할 수 있습니다.
- Kafka의 신뢰성 높은 스트리밍 플랫폼을 활용함으로써,
  Debezium은 애플리케이션이 데이터베이스에서 발생한 변경 사항을 정확하고 완전하게 소비(consume) 할 수 있도록 합니다.
  애플리케이션이 갑작스럽게 중단되거나 연결이 끊기더라도,
  그 기간 동안 발생한 이벤트를 놓치지 않습니다.
  애플리케이션이 다시 시작되면, 중단되었던 지점(topic의 offset 위치)부터 이어서 이벤트를 읽기 시작합니다.

※ 분산 플랫폼 ?
- Kafka Connect 클러스터 위에서 여러 커넥터 인스턴스가 분산·확장 가능하게 동작하며, 장애 복구 및 병렬 처리를 지원하는 분산 아키텍처 기반의 CDC 시스템이기 때문이에요.

- Debezium은 각 데이터베이스 테이블의 모든 행 단위 변경 사항을 변경 이벤트 스트림(change event stream)으로 기록하며, 애플리케이션은 단순히 이 스트림을 읽어서 변경 이벤트를 원래 발생한 순서대로 확인할 수 있다.
-

## 아키텍처
---
Debezium은 일반적으로 Apache Kafka Connect를 통해 배포됩니다.
Kafka Connect는 다음과 같은 작업을 구현하고 운영하기 위한 프레임워크이자 실행 환경(runtime) 입니다:

Debezium처럼 Kafka로 레코드를 전송하는 소스 커넥터(Source Connector)

Kafka 토픽의 레코드를 다른 시스템으로 전달하는 싱크 커넥터(Sink Connector)

![img](/assets/img/debezium-intro-img1.png)
(출처 : [https://debezium.io/documentation//reference/stable/architecture.html](https://debezium.io/documentation//reference/stable/architecture.html))

- 다음 이미지는 Debezium 기반의 변경 데이터 캡처(CDC) 파이프라인 구조를 보여줍니다.
  그림에서 보듯이, MySQL과 PostgreSQL용 Debezium 커넥터가 배포되어 각 데이터베이스의 변경 사항을 캡처합니다.
  각 Debezium 커넥터는 자신이 감시할 소스 데이터베이스와 연결을 설정합니다.

- 하나의 데이터베이스 테이블에서 발생한 변경 사항은 테이블 이름과 동일한 Kafka 토픽에 기록됩니다.
  필요하다면 Debezium의 Topic Routing Transformation 설정을 통해 대상 토픽 이름을 조정할 수 있습니다.
  예를 들어 다음과 같은 작업이 가능합니다:

테이블 이름과 다른 이름의 토픽으로 레코드를 라우팅

여러 테이블의 변경 이벤트를 하나의 토픽으로 합치기

※ Debezium을 배포한다 ?
(참고 : https://debezium.io/documentation//reference/stable/tutorial.html#deploying-mysql-connector)

- “배포한다”는 건 Debezium이 어떤 방식으로 CDC를 수행할지를 정하고, 그에 맞게 구성하고 실행 환경에 올리는 것을 말합니다.

| 배포 방식                      | 실제로 하는 일                                                    | 설명                                                         |
| -------------------------- | ----------------------------------------------------------- | ---------------------------------------------------------- |
| **Kafka Connect 기반 배포**    | Debezium 커넥터를 Kafka Connect 클러스터에 등록하고 실행                   | Kafka Connect에서 Debezium이 “소스 커넥터”로 DB의 변경사항을 읽어 Kafka에 넣음 |
| **Debezium Server 배포**     | Debezium Server 애플리케이션을 실행하고 환경 설정 지정 (예: DB 연결 정보, 메시징 대상) | Kafka 없이 Kinesis, Pub/Sub 등으로 CDC 스트리밍                     |
| **Debezium Engine 내장형 배포** | Java 애플리케이션에 Debezium 라이브러리를 포함시켜 코드 레벨에서 실행                | 앱 내부에서 CDC 수행 (Kafka Connect 불필요)                          |


```
# Kafka Connect 기반 Debezium 배포 예시
docker run -it --rm \
  -e GROUP_ID=1 \
  -e CONFIG_STORAGE_TOPIC=my_connect_configs \
  -e OFFSET_STORAGE_TOPIC=my_connect_offsets \
  -p 8083:8083 \
  debezium/connect:latest
```

```
# Debezium Server 실행 예시
java -jar debezium-server.jar --config application.properties
```

## 실행 예시
---

```
Start Kafka
Start a MySQL database
Start a MySQL command line client
Start Kafka Connect
```

### Registering a connector to monitor the inventory database
- Debezium MySQL 커넥터를 등록하면, 그 커넥터는 MySQL 데이터베이스 서버의 binlog(바이너리 로그) 를 감시하기 시작합니다.
- 이 binlog에는 데이터베이스에서 발생한 모든 트랜잭션 기록이 저장됩니다.
  - 예를 들어, 개별 행(row)의 변경이나 스키마(schema)의 변경 등이 포함됩니다.
- 데이터베이스의 어떤 행이 변경되면, Debezium은 그 변경을 감지하여 change event(변경 이벤트) 를 생성합니다.
- 운영(Production) 환경에서는 보통 두 가지 방법 중 하나를 사용합니다:
  - Kafka 도구(Kafka CLI 등) 를 이용해 필요한 토픽을 수동으로 생성하고, 복제(replica) 개수 같은 세부 설정을 직접 지정하거나,
  - Kafka Connect 설정을 통해, 자동으로 생성되는 토픽의 설정을 커스터마이징(customizing) 합니다.

- 이 튜토리얼에서는, Kafka가 자동으로 토픽을 생성하도록 설정되어 있으며, 각 토픽은 복제본(replica)이 1개뿐인 단순한 구성을 사용합니다.

```json
{
  "name": "inventory-connector",
  "config": {
    "connector.class": "io.debezium.connector.mysql.MySqlConnector",
    "tasks.max": "1",
    "database.hostname": "mysql",
    "database.port": "3306",
    "database.user": "debezium",
    "database.password": "dbz",
    "database.server.id": "184054",
    "topic.prefix": "dbserver1",
    "database.include.list": "inventory",
    "schema.history.internal.kafka.bootstrap.servers": "kafka:9092",
    "schema.history.internal.kafka.topic": "schema-changes.inventory"
  }
}
```

**name**
> 커넥터의 이름

- 커넥터 인스턴스를 구분하기 위한 고유한 이름을 지정

**config**
> 커넥터가 어떻게 동작할지를 정의하는 세부 설정 항목들
- 참고 : [MySQL connector configuration properties](https://debezium.io/documentation//reference/stable/connectors/mysql.html#mysql-connector-properties))

**tasks.max**
> The maximum number of tasks to create for this connector.
- Because the MySQL connector always uses a single task, changing the default value has no effect.

- 한 번에 하나의 태스크(task) 만 실행되어야 합니다. 그 이유는 MySQL 커넥터가 MySQL 서버의 binlog(바이너리 로그)를 읽기 때문입니다.
- 단일 태스크로 실행하면 이벤트의 순서와 처리가 올바르게 유지됩니다.
- Kafka Connect 서비스는 커넥터를 통해 하나 이상의 태스크를 실행할 수 있으며, 실행 중인 태스크들을 Kafka Connect 클러스터 내의 여러 노드에 자동으로 분산 배치(distribute) 합니다.
- 만약 어떤 서비스가 중지되거나 충돌(crash)하더라도, 해당 태스크는 자동으로 다른 실행 중인 서비스로 재할당(redistribute) 됩니다.

**database.hostname**
> 데이터베이스 호스트명(database host)

- Docker를 사용하는 경우, MySQL 서버를 실행하는 Docker 컨테이너 이름(mysql) 입니다.
- Docker는 컨테이너 내부의 네트워크 스택을 조작하여, 서로 연결된 컨테이너들이 /etc/hosts 파일을 통해 컨테이너 이름을 호스트 이름(hostname) 으로 인식할 수 있도록 만듭니다.

- 만약 MySQL이 일반적인 네트워크 환경(즉, Docker가 아닌)에서 실행 중이라면, MySQL 서버의 IP 주소나 DNS로 해석 가능한 호스트 이름을 지정해야 합니다.

**database.server.id**
> Debezium 커넥터(MySQL 클라이언트)의 고유 숫자 ID
- 지정된 ID는 현재 MySQL 클러스터 내에서 실행 중인 모든 데이터베이스 프로세스와 중복되지 않아야(unique) 합니다.
- Debezium 커넥터가 binlog(바이너리 로그) 를 읽기 위해서는, 이 ID를 사용해 MySQL 클러스터에 또 하나의 서버(slave / replica)로 접속(join) 합니다.

- Debezium MySQL 커넥터는 **MySQL의 replication(복제) 기능을 이용**해서 binlog를 읽어요.
- 즉, Debezium은 MySQL 입장에서 보면 “하나의 복제 서버(replica client)” 처럼 동작합니다.
- MySQL 복제 환경에서는 각 서버(마스터, 슬레이브 등)가 서로를 구분하기 위해 server_id 를 사용합니다.
- 따라서 Debezium 커넥터도 database.server.id 값을 통해 자신을 MySQL 클러스터 내에서 고유하게 식별해야 합니다.
- 이 값이 중복되면 MySQL이 “같은 ID의 클라이언트가 이미 연결되어 있다”며 복제를 거부합니다.

**topic.prefix**
> 데이터베이스 서버 또는 클러스터를 구분하기 위한 네임스페이스(namespace)를 지정하는 문자열

- 이 값은 Kafka 토픽 이름의 접두사(prefix) 로 사용되며, 커넥터가 생성하는 모든 이벤트 토픽 이름이 이 값을 기반으로 만들어집니다.

- 따라서 각 커넥터마다 이 prefix 값은 고유(unique) 해야 합니다.
(다른 커넥터와 겹치면 Kafka 토픽 이름 충돌이 발생할 수 있음)

- 값에는 영문자, 숫자, 하이픈(`-`), 점(`.`), 밑줄(`_`) 만 사용할 수 있습니다.

- 예를 들어, prefix가 "dbserver1"이라면

dbserver1.inventory.customers
dbserver1.inventory.orders
이런 식으로 토픽이 생성됩니다.

**database.include.list**
> 커넥터가 변경 사항을 캡처할 데이터베이스 이름을 지정 (필수 옵션은 아님)

- 쉼표(,) 로 구분된 정규식(regular expression) 목록으로 작성합니다.

커넥터는 database.include.list에 명시된 이름과 일치하는 데이터베이스의 변경만 캡처하며,
여기에 포함되지 않은 데이터베이스의 변경 사항은 캡처하지 않습니다.

기본적으로(database.include.list를 지정하지 않은 경우),
커넥터는 모든 데이터베이스의 변경 사항을 캡처합니다.

- 데이터베이스 이름을 일치시킬 때, Debezium은
  사용자가 지정한 정규식을 “앵커(anchor)가 포함된 정규식” 으로 처리합니다.

즉, 지정한 표현식은 데이터베이스 이름 전체 문자열과 완전히 일치해야 하며,
이름 일부(부분 문자열, substring) 에만 일치하는 경우는 매칭되지 않습니다.

정규식 "test" → test 와만 매칭됨

test_db 또는 mytest 와는 매칭되지 않음

^test.* 처럼 직접 앵커(^, $)를 넣으면 패턴을 제어할 수 있음

- database.include.list 속성을 설정했다면,
  database.exclude.list 속성은 함께 설정하지 말아야 합니다.

**schema.history.internal.kafka.bootstrap.servers**
> 커넥터가 Kafka 클러스터에 초기 연결을 맺을 때 사용할 호스트/포트 쌍(host/port pairs) 목록

- 이 연결은 두 가지 목적으로 사용됩니다:
  - 커넥터가 이전에 Kafka에 저장한 데이터베이스 스키마 이력(database schema history)을 가져올 때
  - 소스 데이터베이스에서 읽어들인 DDL(데이터 정의 언어, 예: CREATE TABLE, ALTER TABLE) 문 을 Kafka에 기록할 때

- 각 호스트/포트 쌍은 Kafka Connect 프로세스가 사용하는 Kafka 클러스터와 동일한 클러스터를 가리켜야 합니다.

- 이 설정이 하는 역할은 두 가지입니다:
  - 스키마 이력 읽기: Debezium은 DB 스키마 변화를 Kafka 토픽(database.history.kafka.topic)에 저장합니다. 커넥터가 재시작되면 이 토픽에서 과거 스키마 정보를 불러와 복구합니다.
  - DDL 이벤트 기록: DB 구조(테이블 생성, 컬럼 변경 등)가 바뀔 때, 해당 DDL 문을 Kafka에 기록하여 다른 시스템이 이를 인식할 수 있게 합니다.

따라서 이 설정은 데이터 변경(CDC) 이벤트용 Kafka 연결과는 별개로, 스키마 이력 관리용 Kafka 연결을 정의하는 것입니다.

**schema.history.internal.kafka.topic**
> 커넥터가 데이터베이스 **스키마 변경 이력**을 저장하는 Kafka 토픽의 전체 이름을 지정

- Debezium은 단순히 데이터(row) 의 변경만 캡처하지 않고, 테이블 구조(DDL, 스키마 변화) 도 함께 추적합니다.

- 예를 들어, `ALTER TABLE customers ADD COLUMN phone VARCHAR(20);`
  - 이때 Debezium은 단순히 customers 테이블의 데이터만 바뀌었다고 알리는 게 아니라, "이 시점에 테이블 구조가 이렇게 바뀌었음" 이라는 스키마 변경 이력을 별도의 토픽에 기록해 둡니다.

- 이렇게 해야 Debezium이 재시작되거나 장애 복구 후에도 정확한 스키마 정보로 binlog를 다시 해석할 수 있습니다.

- 이 설정의 역할

| 역할            | 설명                                        |
| ------------- | ----------------------------------------- |
| **DDL 기록**    | 테이블 생성, 삭제, 컬럼 추가/변경 등의 DDL 문을 저장         |
| **스키마 복원**    | 커넥터가 재시작되면, 이 토픽에서 과거 스키마를 불러와 재구성        |
| **이벤트 해석 기준** | binlog의 각 이벤트를 당시의 테이블 구조에 맞게 해석하기 위함     |
| **내부 관리용**    | 이 토픽은 보통 **내부 관리용이므로 외부 애플리케이션이 구독하지 않음** |

Debezium은 내부적으로 이런 흐름을 가집니다
```
MySQL binlog
↓
Debezium Connector
├─ DDL 감지 (스키마 변경)
├─ DML 감지 (데이터 변경)
↓
Kafka
├─ schema-changes.inventory  ← 스키마 이력 저장
└─ dbserver1.inventory.customers ← 데이터 변경 이벤트 저장
```

- 참고 : 커넥터 관련 REST API

$ curl -i -X POST -H "Accept:application/json" -H "Content-Type:application/json" localhost:8083/connectors/ -d '{ "name": "inventory-connector", "config": { "connector.class": "io.debezium.connector.mysql.MySqlConnector", "tasks.max": "1", "database.hostname": "mysql", "database.port": "3306", "database.user": "debezium", "database.password": "dbz", "database.server.id": "184054", "topic.prefix": "dbserver1", "database.include.list": "inventory", "schema.history.internal.kafka.bootstrap.servers": "kafka:9092", "schema.history.internal.kafka.topic": "schemahistory.inventory" } }'


$ curl -i -X GET -H "Accept:application/json" localhost:8083/connectors/inventory-connector


### Watching the connector start

- 커넥터를 등록하면 Kafka Connect 컨테이너에서 매우 많은 로그가 출력됩니다.
- 이 로그를 확인하면 커넥터가 생성된 이후 MySQL 서버의 binlog를 읽기 시작하기까지 어떤 과정을 거치는지를 더 잘 이해할 수 있습니다.
- inventory-connector 커넥터를 등록한 후에는, Kafka Connect 컨테이너(connect)의 로그 출력을 확인하여 커넥터의 상태 변화를 추적할 수 있습니다.
- 처음 몇 줄의 로그는 inventory-connector가 생성되고 시작되는 과정을 보여줍니다.

```
...
2021-11-30 01:38:44,223 INFO   ||  [Worker clientId=connect-1, groupId=1] Tasks [inventory-connector-0] configs updated   [org.apache.kafka.connect.runtime.distributed.DistributedHerder]
2021-11-30 01:38:44,224 INFO   ||  [Worker clientId=connect-1, groupId=1] Handling task config update by restarting tasks []   [org.apache.kafka.connect.runtime.distributed.DistributedHerder]
2021-11-30 01:38:44,224 INFO   ||  [Worker clientId=connect-1, groupId=1] Rebalance started   [org.apache.kafka.connect.runtime.distributed.WorkerCoordinator]
2021-11-30 01:38:44,224 INFO   ||  [Worker clientId=connect-1, groupId=1] (Re-)joining group   [org.apache.kafka.connect.runtime.distributed.WorkerCoordinator]
2021-11-30 01:38:44,227 INFO   ||  [Worker clientId=connect-1, groupId=1] Successfully joined group with generation Generation{generationId=3, memberId='connect-1-7b087c69-8ac5-4c56-9e6b-ec5adabf27e8', protocol='sessioned'}   [org.apache.kafka.connect.runtime.distributed.WorkerCoordinator]
2021-11-30 01:38:44,230 INFO   ||  [Worker clientId=connect-1, groupId=1] Successfully synced group in generation Generation{generationId=3, memberId='connect-1-7b087c69-8ac5-4c56-9e6b-ec5adabf27e8', protocol='sessioned'}   [org.apache.kafka.connect.runtime.distributed.WorkerCoordinator]
2021-11-30 01:38:44,231 INFO   ||  [Worker clientId=connect-1, groupId=1] Joined group at generation 3 with protocol version 2 and got assignment: Assignment{error=0, leader='connect-1-7b087c69-8ac5-4c56-9e6b-ec5adabf27e8', leaderUrl='http://172.17.0.7:8083/', offset=4, connectorIds=[inventory-connector], taskIds=[inventory-connector-0], revokedConnectorIds=[], revokedTaskIds=[], delay=0} with rebalance delay: 0   [org.apache.kafka.connect.runtime.distributed.DistributedHerder]
2021-11-30 01:38:44,232 INFO   ||  [Worker clientId=connect-1, groupId=1] Starting connectors and tasks using config offset 4   [org.apache.kafka.connect.runtime.distributed.DistributedHerder]
2021-11-30 01:38:44,232 INFO   ||  [Worker clientId=connect-1, groupId=1] Starting task inventory-connector-0   [org.apache.kafka.connect.runtime.distributed.DistributedHerder]
...
```

- 조금 더 아래로 내려가면, 커넥터로부터 다음과 같은 로그 출력이 나타나는 것을 볼 수 있습니다.

```
...
2021-11-30 01:38:44,406 INFO   ||  Kafka version: 3.0.0   [org.apache.kafka.common.utils.AppInfoParser]
2021-11-30 01:38:44,406 INFO   ||  Kafka commitId: 8cb0a5e9d3441962   [org.apache.kafka.common.utils.AppInfoParser]
2021-11-30 01:38:44,407 INFO   ||  Kafka startTimeMs: 1638236324406   [org.apache.kafka.common.utils.AppInfoParser]
2021-11-30 01:38:44,437 INFO   ||  Database schema history topic '(name=schemahistory.inventory, numPartitions=1, replicationFactor=1, replicasAssignments=null, configs={cleanup.policy=delete, retention.ms=9223372036854775807, retention.bytes=-1})' created   [io.debezium.storage.kafka.history.KafkaSchemaHistory]
2021-11-30 01:38:44,497 INFO   ||  App info kafka.admin.client for dbserver1-schemahistory unregistered   [org.apache.kafka.common.utils.AppInfoParser]
2021-11-30 01:38:44,499 INFO   ||  Metrics scheduler closed   [org.apache.kafka.common.metrics.Metrics]
2021-11-30 01:38:44,499 INFO   ||  Closing reporter org.apache.kafka.common.metrics.JmxReporter   [org.apache.kafka.common.metrics.Metrics]
2021-11-30 01:38:44,499 INFO   ||  Metrics reporters closed   [org.apache.kafka.common.metrics.Metrics]
2021-11-30 01:38:44,499 INFO   ||  Reconnecting after finishing schema recovery   [io.debezium.connector.mysql.MySqlConnectorTask]
2021-11-30 01:38:44,524 INFO   ||  Requested thread factory for connector MySqlConnector, id = dbserver1 named = change-event-source-coordinator   [io.debezium.util.Threads]
2021-11-30 01:38:44,525 INFO   ||  Creating thread debezium-mysqlconnector-dbserver1-change-event-source-coordinator   [io.debezium.util.Threads]
2021-11-30 01:38:44,526 INFO   ||  WorkerSourceTask{id=inventory-connector-0} Source task finished initialization and start   [org.apache.kafka.connect.runtime.WorkerSourceTask]
2021-11-30 01:38:44,529 INFO   MySQL|dbserver1|snapshot  Metrics registered   [io.debezium.pipeline.ChangeEventSourceCoordinator]
2021-11-30 01:38:44,529 INFO   MySQL|dbserver1|snapshot  Context created   [io.debezium.pipeline.ChangeEventSourceCoordinator]
2021-11-30 01:38:44,534 INFO   MySQL|dbserver1|snapshot  No previous offset has been found   [io.debezium.connector.mysql.MySqlSnapshotChangeEventSource]
2021-11-30 01:38:44,534 INFO   MySQL|dbserver1|snapshot  According to the connector configuration both schema and data will be snapshotted   [io.debezium.connector.mysql.MySqlSnapshotChangeEventSource]
2021-11-30 01:38:44,534 INFO   MySQL|dbserver1|snapshot  Snapshot step 1 - Preparing   [io.debezium.relational.RelationalSnapshotChangeEventSource]
...
```

- Debezium의 로그 출력은 MDC(Mapped Diagnostic Context)를 사용합니다. 이는 각 스레드별 문맥 정보를 로그에 포함시켜, 멀티스레드 환경의 Kafka Connect 서비스에서 어떤 일이 일어나고 있는지 쉽게 파악할 수 있게 해줍니다.
- 예를 들어 로그에는 다음과 같은 정보가 포함됩니다:
  - 커넥터 유형 (위 예시에서는 MySQL)
  - 커넥터의 논리적 이름 (dbserver1)
  - 커넥터의 활동 단계 (예: task, snapshot, binlog 등)

- 위 로그에서 처음 몇 줄은 커넥터의 태스크(task) 활동에 관한 내용으로,
  기본적인 관리 정보를 보여줍니다.
  (이 경우, 커넥터가 이전 오프셋(offset) 없이 새로 시작되었다는 내용입니다.)

- 그 다음 세 줄은 스냅샷(snapshot) 단계에 해당하며, Debezium MySQL 사용자의 권한(grant)으로 스냅샷이 시작되었음을 보고합니다.

- 만약 커넥터가 MySQL에 연결되지 않거나, 테이블 또는 binlog를 인식하지 못하는 경우에는 해당 MySQL 사용자에게 필요한 권한(grant) 들이 모두 부여되어 있는지 확인해야 합니다.

- 다음으로, 커넥터는 스냅샷(snapshot) 작업을 수행하는 단계별 과정을 로그로 보고합니다.

```
...
2021-11-30 01:38:44,534 INFO   MySQL|dbserver1|snapshot  Snapshot step 1 - Preparing   [io.debezium.relational.RelationalSnapshotChangeEventSource]
2021-11-30 01:38:44,535 INFO   MySQL|dbserver1|snapshot  Snapshot step 2 - Determining captured tables   [io.debezium.relational.RelationalSnapshotChangeEventSource]
2021-11-30 01:38:44,535 INFO   MySQL|dbserver1|snapshot  Read list of available databases   [io.debezium.connector.mysql.MySqlSnapshotChangeEventSource]
2021-11-30 01:38:44,537 INFO   MySQL|dbserver1|snapshot  	 list of available databases is: [information_schema, inventory, mysql, performance_schema, sys]   [io.debezium.connector.mysql.MySqlSnapshotChangeEventSource]
2021-11-30 01:38:44,537 INFO   MySQL|dbserver1|snapshot  Read list of available tables in each database   [io.debezium.connector.mysql.MySqlSnapshotChangeEventSource]
2021-11-30 01:38:44,548 INFO   MySQL|dbserver1|snapshot  	snapshot continuing with database(s): [inventory]   [io.debezium.connector.mysql.MySqlSnapshotChangeEventSource]
2021-11-30 01:38:44,551 INFO   MySQL|dbserver1|snapshot  Snapshot step 3 - Locking captured tables [inventory.addresses, inventory.customers, inventory.geom, inventory.orders, inventory.products, inventory.products_on_hand]   [io.debezium.relational.RelationalSnapshotChangeEventSource]
2021-11-30 01:38:44,552 INFO   MySQL|dbserver1|snapshot  Flush and obtain global read lock to prevent writes to database   [io.debezium.connector.mysql.MySqlSnapshotChangeEventSource]
2021-11-30 01:38:44,557 INFO   MySQL|dbserver1|snapshot  Snapshot step 4 - Determining snapshot offset   [io.debezium.relational.RelationalSnapshotChangeEventSource]
2021-11-30 01:38:44,560 INFO   MySQL|dbserver1|snapshot  Read binlog position of MySQL primary server   [io.debezium.connector.mysql.MySqlSnapshotChangeEventSource]
2021-11-30 01:38:44,562 INFO   MySQL|dbserver1|snapshot  	 using binlog 'mysql-bin.000003' at position '156' and gtid ''   [io.debezium.connector.mysql.MySqlSnapshotChangeEventSource]
2021-11-30 01:38:44,562 INFO   MySQL|dbserver1|snapshot  Snapshot step 5 - Reading structure of captured tables   [io.debezium.relational.RelationalSnapshotChangeEventSource]
2021-11-30 01:38:44,562 INFO   MySQL|dbserver1|snapshot  All eligible tables schema should be captured, capturing: [inventory.addresses, inventory.customers, inventory.geom, inventory.orders, inventory.products, inventory.products_on_hand]   [io.debezium.connector.mysql.MySqlSnapshotChangeEventSource]
2021-11-30 01:38:45,058 INFO   MySQL|dbserver1|snapshot  Reading structure of database 'inventory'   [io.debezium.connector.mysql.MySqlSnapshotChangeEventSource]
2021-11-30 01:38:45,187 INFO   MySQL|dbserver1|snapshot  Snapshot step 6 - Persisting schema history   [io.debezium.relational.RelationalSnapshotChangeEventSource]
2021-11-30 01:38:45,273 INFO   MySQL|dbserver1|snapshot  Releasing global read lock to enable MySQL writes   [io.debezium.connector.mysql.MySqlSnapshotChangeEventSource]
2021-11-30 01:38:45,274 INFO   MySQL|dbserver1|snapshot  Writes to MySQL tables prevented for a total of 00:00:00.717   [io.debezium.connector.mysql.MySqlSnapshotChangeEventSource]
2021-11-30 01:38:45,274 INFO   MySQL|dbserver1|snapshot  Snapshot step 7 - Snapshotting data   [io.debezium.relational.RelationalSnapshotChangeEventSource]
2021-11-30 01:38:45,275 INFO   MySQL|dbserver1|snapshot  Snapshotting contents of 6 tables while still in transaction   [io.debezium.relational.RelationalSnapshotChangeEventSource]
2021-11-30 01:38:45,275 INFO   MySQL|dbserver1|snapshot  Exporting data from table 'inventory.addresses' (1 of 6 tables)   [io.debezium.relational.RelationalSnapshotChangeEventSource]
2021-11-30 01:38:45,276 INFO   MySQL|dbserver1|snapshot  	 For table 'inventory.addresses' using select statement: 'SELECT `id`, `customer_id`, `street`, `city`, `state`, `zip`, `type` FROM `inventory`.`addresses`'   [io.debezium.relational.RelationalSnapshotChangeEventSource]
2021-11-30 01:38:45,295 INFO   MySQL|dbserver1|snapshot  	 Finished exporting 7 records for table 'inventory.addresses'; total duration '00:00:00.02'   [io.debezium.relational.RelationalSnapshotChangeEventSource]
2021-11-30 01:38:45,296 INFO   MySQL|dbserver1|snapshot  Exporting data from table 'inventory.customers' (2 of 6 tables)   [io.debezium.relational.RelationalSnapshotChangeEventSource]
2021-11-30 01:38:45,296 INFO   MySQL|dbserver1|snapshot  	 For table 'inventory.customers' using select statement: 'SELECT `id`, `first_name`, `last_name`, `email` FROM `inventory`.`customers`'   [io.debezium.relational.RelationalSnapshotChangeEventSource]
2021-11-30 01:38:45,304 INFO   MySQL|dbserver1|snapshot  	 Finished exporting 4 records for table 'inventory.customers'; total duration '00:00:00.008'   [io.debezium.relational.RelationalSnapshotChangeEventSource]
2021-11-30 01:38:45,304 INFO   MySQL|dbserver1|snapshot  Exporting data from table 'inventory.geom' (3 of 6 tables)   [io.debezium.relational.RelationalSnapshotChangeEventSource]
2021-11-30 01:38:45,305 INFO   MySQL|dbserver1|snapshot  	 For table 'inventory.geom' using select statement: 'SELECT `id`, `g`, `h` FROM `inventory`.`geom`'   [io.debezium.relational.RelationalSnapshotChangeEventSource]
2021-11-30 01:38:45,316 INFO   MySQL|dbserver1|snapshot  	 Finished exporting 3 records for table 'inventory.geom'; total duration '00:00:00.011'   [io.debezium.relational.RelationalSnapshotChangeEventSource]
2021-11-30 01:38:45,316 INFO   MySQL|dbserver1|snapshot  Exporting data from table 'inventory.orders' (4 of 6 tables)   [io.debezium.relational.RelationalSnapshotChangeEventSource]
2021-11-30 01:38:45,316 INFO   MySQL|dbserver1|snapshot  	 For table 'inventory.orders' using select statement: 'SELECT `order_number`, `order_date`, `purchaser`, `quantity`, `product_id` FROM `inventory`.`orders`'   [io.debezium.relational.RelationalSnapshotChangeEventSource]
2021-11-30 01:38:45,325 INFO   MySQL|dbserver1|snapshot  	 Finished exporting 4 records for table 'inventory.orders'; total duration '00:00:00.008'   [io.debezium.relational.RelationalSnapshotChangeEventSource]
2021-11-30 01:38:45,325 INFO   MySQL|dbserver1|snapshot  Exporting data from table 'inventory.products' (5 of 6 tables)   [io.debezium.relational.RelationalSnapshotChangeEventSource]
2021-11-30 01:38:45,325 INFO   MySQL|dbserver1|snapshot  	 For table 'inventory.products' using select statement: 'SELECT `id`, `name`, `description`, `weight` FROM `inventory`.`products`'   [io.debezium.relational.RelationalSnapshotChangeEventSource]
2021-11-30 01:38:45,343 INFO   MySQL|dbserver1|snapshot  	 Finished exporting 9 records for table 'inventory.products'; total duration '00:00:00.017'   [io.debezium.relational.RelationalSnapshotChangeEventSource]
2021-11-30 01:38:45,344 INFO   MySQL|dbserver1|snapshot  Exporting data from table 'inventory.products_on_hand' (6 of 6 tables)   [io.debezium.relational.RelationalSnapshotChangeEventSource]
2021-11-30 01:38:45,344 INFO   MySQL|dbserver1|snapshot  	 For table 'inventory.products_on_hand' using select statement: 'SELECT `product_id`, `quantity` FROM `inventory`.`products_on_hand`'   [io.debezium.relational.RelationalSnapshotChangeEventSource]
2021-11-30 01:38:45,353 INFO   MySQL|dbserver1|snapshot  	 Finished exporting 9 records for table 'inventory.products_on_hand'; total duration '00:00:00.009'   [io.debezium.relational.RelationalSnapshotChangeEventSource]
2021-11-30 01:38:45,355 INFO   MySQL|dbserver1|snapshot  Snapshot - Final stage   [io.debezium.pipeline.source.AbstractSnapshotChangeEventSource]
2021-11-30 01:38:45,356 INFO   MySQL|dbserver1|snapshot  Snapshot ended with SnapshotResult [status=COMPLETED, offset=MySqlOffsetContext [sourceInfoSchema=Schema{io.debezium.connector.mysql.Source:STRUCT}, sourceInfo=SourceInfo [currentGtid=null, currentBinlogFilename=mysql-bin.000003, currentBinlogPosition=156, currentRowNumber=0, serverId=0, sourceTime=2021-11-30T01:38:45.352Z, threadId=-1, currentQuery=null, tableIds=[inventory.products_on_hand], databaseName=inventory], snapshotCompleted=true, transactionContext=TransactionContext [currentTransactionId=null, perTableEventCount={}, totalEventCount=0], restartGtidSet=null, currentGtidSet=null, restartBinlogFilename=mysql-bin.000003, restartBinlogPosition=156, restartRowsToSkip=0, restartEventsToSkip=0, currentEventLengthInBytes=0, inTransaction=false, transactionId=null, incrementalSnapshotContext =IncrementalSnapshotContext [windowOpened=false, chunkEndPosition=null, dataCollectionsToSnapshot=[], lastEventKeySent=null, maximumKey=null]]]   [io.debezium.pipeline.ChangeEventSourceCoordinator]
...
```

- 이 단계들은 커넥터가 일관성 있는 스냅샷(consitent snapshot) 을 생성하기 위해 수행하는 작업을 단계별로 보여줍니다.
- 예를 들어, 6단계(Step 6) 에서는 캡처 대상 테이블의 DDL(테이블 생성문 등) 을 역추적(reverse engineering)하여 스키마를 수집하고, 글로벌 쓰기 잠금(global write lock) 을 획득한 뒤 1초 이내에 해제합니다.
- 7단계(Step 7) 에서는 각 테이블의 모든 행(row) 을 읽고, 처리에 걸린 시간과 읽은 행의 개수를 로그로 기록합니다.
- 이 예시의 경우, 커넥터는 전체 스냅샷을 1초 이내에 완료했습니다.

- 실제 데이터베이스에서는 스냅샷 과정이 이보다 오래 걸릴 수 있습니다.
- 그러나 커넥터는 충분히 상세한 로그를 출력하므로, 테이블의 행(row)이 많더라도 현재 어떤 단계에서 작업 중인지 추적할 수 있습니다.
- 또한 스냅샷 초기에 쓰기 잠금(write lock) 이 사용되지만, 데이터 복사가 시작되기 전에 잠금이 해제되므로 대규모 데이터베이스에서도 이 잠금이 오래 유지되지는 않습니다.

- 정리하면,

| 단계 | 내용                      | 비고                                |
| -- | ----------------------- | --------------------------------- |
| 1  | 커넥터 생성 및 태스크 시작         | Kafka Connect 클러스터에서 작업 분배        |
| 2  | 스키마 히스토리 토픽 생성          | `schemahistory.inventory` 생성      |
| 3  | 스냅샷 시작                  | DB 초기 상태 캡처                       |
| 4  | 테이블 목록 및 binlog 위치 식별   | consistent snapshot 확보            |
| 5  | 데이터 덤프(snapshotting)    | 각 테이블의 데이터를 Kafka로 내보냄            |
| 6  | 스냅샷 완료 후 binlog 스트리밍 시작 | 실시간 CDC 모드 전환                     |
| 7  | LEADER_NOT_AVAILABLE 경고 | 새 토픽 생성 시 Kafka 리더 재할당 과정 (무시 가능) |

- 마지막으로, 로그는 커넥터가 스냅샷 모드에서 MySQL binlog 스트리밍 모드로 전환된 것을 보여줍니다. 이 시점부터 커넥터는 실시간 변경 데이터(CDC) 를 지속적으로 읽기 시작합니다.

```
...
2021-11-30 01:38:45,362 INFO   MySQL|dbserver1|streaming  Starting streaming   [io.debezium.pipeline.ChangeEventSourceCoordinator]
...
Nov 30, 2021 1:38:45 AM com.github.shyiko.mysql.binlog.BinaryLogClient connect
INFO: Connected to mysql:3306 at mysql-bin.000003/156 (sid:184054, cid:13)
2021-11-30 01:38:45,392 INFO   MySQL|dbserver1|binlog  Connected to MySQL binlog at mysql:3306, starting at MySqlOffsetContext [sourceInfoSchema=Schema{io.debezium.connector.mysql.Source:STRUCT}, sourceInfo=SourceInfo [currentGtid=null, currentBinlogFilename=mysql-bin.000003, currentBinlogPosition=156, currentRowNumber=0, serverId=0, sourceTime=2021-11-30T01:38:45.352Z, threadId=-1, currentQuery=null, tableIds=[inventory.products_on_hand], databaseName=inventory], snapshotCompleted=true, transactionContext=TransactionContext [currentTransactionId=null, perTableEventCount={}, totalEventCount=0], restartGtidSet=null, currentGtidSet=null, restartBinlogFilename=mysql-bin.000003, restartBinlogPosition=156, restartRowsToSkip=0, restartEventsToSkip=0, currentEventLengthInBytes=0, inTransaction=false, transactionId=null, incrementalSnapshotContext =IncrementalSnapshotContext [windowOpened=false, chunkEndPosition=null, dataCollectionsToSnapshot=[], lastEventKeySent=null, maximumKey=null]]   [io.debezium.connector.mysql.MySqlStreamingChangeEventSource]
2021-11-30 01:38:45,392 INFO   MySQL|dbserver1|streaming  Waiting for keepalive thread to start   [io.debezium.connector.mysql.MySqlStreamingChangeEventSource]
2021-11-30 01:38:45,393 INFO   MySQL|dbserver1|binlog  Creating thread debezium-mysqlconnector-dbserver1-binlog-client   [io.debezium.util.Threads]
...
```

## Viewing change events
---


## 참고 자료
---
- [https://debezium.io/documentation//reference/stable/architecture.html](https://debezium.io/documentation//reference/stable/architecture.html)
- [https://debezium.io/documentation//reference/stable/tutorial.html](https://debezium.io/documentation//reference/stable/tutorial.html)
