
## 구성요소


## Kafka
> 메세지 브로커

## Kafka Connect
> 카프카와 데이터소스 사이에 연결고리 역할
> Kafka Connect is a free, open-source component of Apache Kafka® that serves as a centralized data hub for simple data integration between databases, key-value stores, search indexes, and file systems.

- Kafka Connect is a tool for scalably and reliably streaming data between Apache Kafka® and other data systems.
- Kafka Connect can ingest entire databases or collect metrics from all your application servers into Kafka topics, making the data available for stream processing with low latency.

- 구성요소
Connectors: The high level abstraction that coordinates data streaming by managing tasks
Tasks: The implementation of how data is copied to or from Kafka
Workers: The running processes that execute connectors and tasks
Converters: The code used to translate data between Connect and the system sending or receiving data
Transforms: Simple logic to alter each message produced by or sent to a connector
Dead Letter Queue: How Connect handles connector errors

### Connectors
Connectors in Kafka Connect define where data should be copied to and from. A connector instance is a logical job that is responsible for managing the copying of data between Kafka and another system. All of the classes that implement or are used by a connector are defined in a connector plugin. Both connector instances and connector plugins may be referred to as “connectors”, but it should always be clear from the context which is being referred to (for example, “install a connector” refers to the plugin, and “check the status of a connector” refers to a connector instance).

- 커넥터 목록 : https://www.confluent.io/product/connectors

## Debezium
> DB 변화를 감지하는 컴포넌트 ?

- Debezium is an open source distributed platform for change data capture.
- Start it up, point it at your databases, and your apps can start responding to all of the inserts, updates, and deletes that other apps commit to your databases.

## Kafka Connect와 Debezium 관계
> JDBC Driver와 구현체들의 관계와 유사 ?

**Kafka Connect = “플랫폼” (JDBC와 유사한 인터페이스 제공)**
- Kafka Connect는 **“커넥터가 어떻게 Kafka와 데이터를 주고받을지”**에 대한 표준화된 API를 제공합니다.
- 예를 들어 JDBC에서 Connection, Statement, ResultSet 같은 공통 인터페이스를 정의하듯,
- Kafka Connect는 SourceConnector, SinkConnector 등의 인터페이스를 정의합니다.
- Debezium, JDBC Sink, Elasticsearch Sink 같은 다양한 커넥터들이 이 인터페이스를 구현합니다.

**Debezium = “특정 데이터 소스에 특화된 구현체”**
- Debezium은 Kafka Connect용 **Source Connector 플러그인**입니다.
- 즉, Kafka Connect의 “표준 규격”을 따르면서, MySQL binlog를 읽고 이벤트를 Kafka로 발행하는 구현체입니다.
- Debezium은 MySQL뿐 아니라 PostgreSQL, MongoDB, Oracle 등용 커넥터도 제공해요.

```
Kafka Connect (플랫폼)
└── Debezium MySQL Connector (플러그인)
  └── MySQL binlog 읽어서 Kafka로 publish
```

| 용어                | 의미                              | 관계                                               |
| ----------------- | ------------------------------- | ------------------------------------------------ |
| **Kafka Connect** | 표준 인터페이스(프레임워크)                 | “확장 포인트(Extension Point)”를 제공함                   |
| **플러그인 (Plugin)** | Connector 구현체를 **패키징해서 배포한 형태** | JAR 파일로 만들어 Kafka Connect에 로드됨                   |
| **Connector 구현체** | Kafka Connect 인터페이스를 **구현한 코드** | Java 클래스로 작성됨 (예: `DebeziumMySqlConnector.java`) |

![img.png](img.png)

## 실습
---

- 실제 사례 : https://techblog.uplus.co.kr/debezium%EC%9C%BC%EB%A1%9C-db-synchronization-%EA%B5%AC%EC%B6%95%ED%95%98%EA%B8%B0-1b6fba73010f

- Kafka 설치 디렉토리 트리 구조 (메시지 브로커 + Connect 포함)

```
kafka_2.13-3.7.0/
├── bin/                              ← 실행 스크립트들
│   ├── kafka-server-start.sh          ← ✅ Kafka Broker (메시지 브로커) 실행
│   ├── kafka-server-stop.sh
│   ├── zookeeper-server-start.sh      ← ✅ ZooKeeper (메타데이터 관리, 일부 버전)
│   ├── kafka-topics.sh                ← 토픽 생성/조회
│   ├── kafka-console-producer.sh      ← CLI Producer
│   ├── kafka-console-consumer.sh      ← CLI Consumer
│   ├── kafka-connect-standalone.sh    ← ✅ Kafka Connect 단일 모드 실행
│   ├── kafka-connect-distributed.sh   ← ✅ Kafka Connect 분산 모드 실행
│   ├── kafka-producer-perf-test.sh
│   └── kafka-consumer-groups.sh
│
├── config/                           ← 설정 파일
│   ├── server.properties              ← ✅ Kafka Broker 설정 (log.dir, listeners 등)
│   ├── zookeeper.properties           ← ZooKeeper 설정
│   ├── connect-standalone.properties  ← Connect 단일 실행용 설정
│   ├── connect-distributed.properties ← Connect 클러스터용 설정
│   ├── producer.properties
│   └── consumer.properties
│
├── libs/                             ← Kafka 런타임 JAR 모음
│   ├── kafka-clients-*.jar           ← ✅ Kafka Producer/Consumer API
│   ├── kafka_2.13-*.jar              ← Kafka Broker 서버 코드
│   ├── connect-api-*.jar             ← ✅ Kafka Connect 프레임워크 API
│   ├── connect-runtime-*.jar         ← ✅ Kafka Connect 엔진 (커넥터 실행 환경)
│   ├── kafka-streams-*.jar
│   ├── slf4j-*.jar, log4j-*.jar      ← 로깅 관련
│   └── ...
│
├── plugins/                          ← (직접 생성) ✅ 커넥터 플러그인 설치 경로
│   ├── debezium-connector-mysql/
│   │   ├── debezium-connector-mysql-2.7.0.Final.jar
│   │   └── ...
│   └── kafka-connect-jdbc/
│       ├── kafka-connect-jdbc-10.7.4.jar
│       ├── mysql-connector-java-8.0.33.jar
│       └── ...
│
├── logs/
│   ├── server.log
│   ├── connect.log
│   └── zookeeper.log
│
└── LICENSE / NOTICE / README
```

brew install zookeeper
brew services start zookeeper



kafka-server-start /usr/local/etc/kafka/server.properties

kafka-topics --bootstrap-server localhost:9092 --list



curl -L -O https://repo1.maven.org/maven2/io/debezium/debezium-connector-mysql/2.7.0.Final/debezium-connector-mysql-2.7.0.Final-plugin.tar.gz



mkdir -p /usr/local/Cellar/kafka/4.1.0/libexec/plugins/debezium-mysql
cp -r debezium-connector-mysql/* /usr/local/Cellar/kafka/4.1.0/libexec/plugins/debezium-mysql/



connect-distributed /usr/local/etc/kafka/connect-distributed.properties
=> plugin.path=/usr/local/Cellar/kafka/4.1.0/libexec/plugins

```
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d '{
    "name": "mysql-orders-connector",
    "config": {
      "connector.class": "io.debezium.connector.mysql.MySqlConnector",
      "database.hostname": "localhost",
      "database.port": "3306",
      "database.user": "root",
      "database.password": "",
      "database.server.id": "184054",
      "database.server.name": "mysql-cdc",
      "database.include.list": "ordersdb",
      "table.include.list": "ordersdb.orders",
      "include.schema.changes": "false",
      "database.history.kafka.bootstrap.servers": "localhost:9092",
      "database.history.kafka.topic": "schema-changes.orders"
    }
  }'
```
=> {"error_code":400,"message":"Connector configuration is invalid and contains the following 1 error(s):\nThe 'topic.prefix' value is invalid: A value is required\nYou can also find the above list of errors at the endpoint /connector-plugins/{connectorType}/config/validate"}%

```
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d '{
  "name": "mysql-orders-connector",
  "config": {
    "connector.class": "io.debezium.connector.mysql.MySqlConnector",
    "database.hostname": "localhost",
    "database.port": "3306",
    "database.user": "root",
    "database.password": "",
    "database.server.id": "184054",
    "topic.prefix": "mysql-cdc",
    "database.include.list": "ordersdb",
    "table.include.list": "ordersdb.orders",
    "include.schema.changes": "false",
    "database.history.kafka.bootstrap.servers": "localhost:9092",
    "database.history.kafka.topic": "schema-changes.orders"
  }
}'
```

=> {"error_code":400,"message":"Connector configuration is invalid and contains the following 1 error(s):\nUnable to connect: The server time zone value 'KST' is unrecognized or represents more than one time zone. You must configure either the server or JDBC driver (via the 'connectionTimeZone' configuration property) to use a more specific time zone value if you want to utilize time zone support.\nYou can also find the above list of errors at the endpoint `/connector-plugins/{connectorType}/config/validate`"}%

```
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d '{
  "name": "mysql-orders-connector",
  "config": {
    "connector.class": "io.debezium.connector.mysql.MySqlConnector",
    "database.hostname": "localhost",
    "database.port": "3306",
    "database.user": "root",
    "database.password": "",
    "database.server.id": "184054",
    "topic.prefix": "mysql-cdc",
    "database.include.list": "ordersdb",
    "table.include.list": "ordersdb.orders",
    "include.schema.changes": "false",
    "schema.history.internal.kafka.bootstrap.servers": "localhost:9092",
    "schema.history.internal.kafka.topic": "schema-changes.orders",
    "database.connectionTimeZone": "Asia/Seoul"
  }
}'
```

=> "database.history.kafka.bootstrap.servers": "localhost:9092",
"database.history.kafka.topic": "schema-changes.orders"
이 설정은 Debezium 1.x 시절 방식인데,
Debezium 2.x에서는 database.history.* → schema.history.internal.* 로 바뀌었습니다.

따라서 Debezium이 KafkaSchemaHistory 초기화에 실패해서 바로 터지는 것.



```
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d '{
  "name": "mysql-orders-connector",
  "config": {
    "connector.class": "io.debezium.connector.mysql.MySqlConnector",
    "database.hostname": "localhost",
    "database.port": "3306",
    "database.user": "",
    "database.password": "",
    "database.server.id": "184054",
    "topic.prefix": "mysql-cdc",
    "database.include.list": "ordersdb",
    "table.include.list": "ordersdb.orders",
    "include.schema.changes": "false",
    "database.connectionTimeZone": "Asia/Seoul",

    "schema.history.internal.kafka.bootstrap.servers": "localhost:9092",
    "schema.history.internal.kafka.topic": "schema-changes.orders"
  }
}'
```

```
ERROR [mysql-orders-connector|task-0] WorkerSourceTask{id=mysql-orders-connector-0} Task threw an uncaught and unrecoverable exception. Task is being killed and will not recover until manually restarted (org.apache.kafka.connect.runtime.WorkerTask:251)
java.lang.NoSuchMethodError: 'org.apache.kafka.clients.consumer.ConsumerRecords org.apache.kafka.clients.consumer.KafkaConsumer.poll(long)'
	at io.debezium.storage.kafka.history.KafkaSchemaHistory.recoverRecords(KafkaSchemaHistory.java:319) ~[debezium-storage-kafka-2.7.0.Final.jar:2.7.0.Final]
	at io.debezium.relational.history.AbstractSchemaHistory.recover(AbstractSchemaHistory.java:100) ~[debezium-core-2.7.0.Final.jar:2.7.0.Final]
	at io.debezium.relational.history.SchemaHistory.recover(SchemaHistory.java:192) ~[debezium-core-2.7.0.Final.jar:2.7.0.Final]
	at io.debezium.relational.HistorizedRelationalDatabaseSchema.recover(HistorizedRelationalDatabaseSchema.java:72) ~[debezium-core-2.7.0.Final.jar:2.7.0.Final]
	at io.debezium.schema.HistorizedDatabaseSchema.recover(HistorizedDatabaseSchema.java:40) ~[debezium-core-2.7.0.Final.jar:2.7.0.Final]
	at io.debezium.connector.common.BaseSourceTask.validateAndLoadSchemaHistory(BaseSourceTask.java:148) ~[debezium-core-2.7.0.Final.jar:2.7.0.Final]
	at io.debezium.connector.mysql.MySqlConnectorTask.start(MySqlConnectorTask.java:134) ~[debezium-connector-mysql-2.7.0.Final.jar:2.7.0.Final]
	at io.debezium.connector.common.BaseSourceTask.start(BaseSourceTask.java:248) ~[debezium-core-2.7.0.Final.jar:2.7.0.Final]
	at org.apache.kafka.connect.runtime.AbstractWorkerSourceTask.initializeAndStart(AbstractWorkerSourceTask.java:288) ~[connect-runtime-4.1.0.jar:?]
	at org.apache.kafka.connect.runtime.WorkerTask.doStart(WorkerTask.java:191) ~[connect-runtime-4.1.0.jar:?]
	at org.apache.kafka.connect.runtime.WorkerTask.doRun(WorkerTask.java:242) ~[connect-runtime-4.1.0.jar:?]
	at org.apache.kafka.connect.runtime.WorkerTask.run(WorkerTask.java:298) ~[connect-runtime-4.1.0.jar:?]
	at org.apache.kafka.connect.runtime.AbstractWorkerSourceTask.run(AbstractWorkerSourceTask.java:83) ~[connect-runtime-4.1.0.jar:?]
	at org.apache.kafka.connect.runtime.isolation.Plugins.lambda$withClassLoader$1(Plugins.java:254) ~[connect-runtime-4.1.0.jar:?]
	at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:572) ~[?:?]
	at java.base/java.util.concurrent.FutureTask.run(FutureTask.java:317) ~[?:?]
	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1144) ~[?:?]
	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:642) ~[?:?]
	at java.base/java.lang.Thread.run(Thread.java:1583) [?:?]
[2025-10-19 22:42:30,693] INFO [mysql-orders-connector|task-0] Stopping down connector (io.debezium.connector.common.BaseSourceTask:406)
```

=> kafka-connect, debezium 간의 버전 호환성 필요

![img.png](kafka-connect-debezium-version.png)
=> https://debezium.io/releases/

### 실행

```
0. brew services start zookeeper

1. kafka-server-start /usr/local/etc/kafka/server.properties
=> 토픽 목록 보기 : kafka-topics --bootstrap-server localhost:9092 --list

2. connect-distributed /usr/local/etc/kafka/connect-distributed.properties

3.

curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d '{
  "name": "mysql-orders-connector",
  "config": {
    "connector.class": "io.debezium.connector.mysql.MySqlConnector",
    "database.hostname": "localhost",
    "database.port": "3306",
    "database.user": "root",
    "database.password": "",
    "database.server.id": "184054",
    "topic.prefix": "mysql-cdc",
    "database.include.list": "ordersdb",
    "table.include.list": "ordersdb.orders",
    "include.schema.changes": "false",
    "database.connectionTimeZone": "Asia/Seoul",

    "schema.history.internal.kafka.bootstrap.servers": "localhost:9092",
    "schema.history.internal.kafka.topic": "schema-changes.orders"
  }
}'
```

- debezium-connector-mysql 디렉토리

```
CHANGELOG.md
CONTRIBUTE.md
COPYRIGHT.txt
LICENSE-3rd-PARTIES.txt
LICENSE.txt
README.md
README_JA.md
README_KO.md
README_ZH.md
antlr4-runtime-4.10.1.jar
debezium-api-3.2.4.Final.jar
debezium-common-3.2.4.Final.jar
debezium-connector-binlog-3.2.4.Final.jar
debezium-connector-mysql-3.2.4.Final.jar
debezium-core-3.2.4.Final.jar
debezium-ddl-parser-3.2.4.Final.jar
debezium-openlineage-api-3.2.4.Final.jar
debezium-storage-file-3.2.4.Final.jar
debezium-storage-kafka-3.2.4.Final.jar
mysql-binlog-connector-java-0.40.2.jar
mysql-connector-j-9.1.0.jar
```

## 변경 감지 이벤트 형태
---

```json
{
  "schema" : {
    ...
  },
  "payload" : {
    ...
  }
}
```

- insert

```json
{
  "schema" : {
    "type" : "struct",
    "fields" : [ {
      "type" : "struct",
      "fields" : [ {
        "type" : "int64",
        "optional" : false,
        "field" : "id"
      }, {
        "type" : "string",
        "optional" : true,
        "field" : "customer_name"
      }, {
        "type" : "bytes",
        "optional" : true,
        "name" : "org.apache.kafka.connect.data.Decimal",
        "version" : 1,
        "parameters" : {
          "scale" : "2",
          "connect.decimal.precision" : "10"
        },
        "field" : "amount"
      }, {
        "type" : "string",
        "optional" : true,
        "name" : "io.debezium.time.ZonedTimestamp",
        "version" : 1,
        "field" : "created_at"
      } ],
      "optional" : true,
      "name" : "mysql-cdc.ordersdb.orders.Value",
      "field" : "before"
    }, {
      "type" : "struct",
      "fields" : [ {
        "type" : "int64",
        "optional" : false,
        "field" : "id"
      }, {
        "type" : "string",
        "optional" : true,
        "field" : "customer_name"
      }, {
        "type" : "bytes",
        "optional" : true,
        "name" : "org.apache.kafka.connect.data.Decimal",
        "version" : 1,
        "parameters" : {
          "scale" : "2",
          "connect.decimal.precision" : "10"
        },
        "field" : "amount"
      }, {
        "type" : "string",
        "optional" : true,
        "name" : "io.debezium.time.ZonedTimestamp",
        "version" : 1,
        "field" : "created_at"
      } ],
      "optional" : true,
      "name" : "mysql-cdc.ordersdb.orders.Value",
      "field" : "after"
    }, {
      "type" : "struct",
      "fields" : [ {
        "type" : "string",
        "optional" : false,
        "field" : "version"
      }, {
        "type" : "string",
        "optional" : false,
        "field" : "connector"
      }, {
        "type" : "string",
        "optional" : false,
        "field" : "name"
      }, {
        "type" : "int64",
        "optional" : false,
        "field" : "ts_ms"
      }, {
        "type" : "string",
        "optional" : true,
        "name" : "io.debezium.data.Enum",
        "version" : 1,
        "parameters" : {
          "allowed" : "true,first,first_in_data_collection,last_in_data_collection,last,false,incremental"
        },
        "default" : "false",
        "field" : "snapshot"
      }, {
        "type" : "string",
        "optional" : false,
        "field" : "db"
      }, {
        "type" : "string",
        "optional" : true,
        "field" : "sequence"
      }, {
        "type" : "int64",
        "optional" : true,
        "field" : "ts_us"
      }, {
        "type" : "int64",
        "optional" : true,
        "field" : "ts_ns"
      }, {
        "type" : "string",
        "optional" : true,
        "field" : "table"
      }, {
        "type" : "int64",
        "optional" : false,
        "field" : "server_id"
      }, {
        "type" : "string",
        "optional" : true,
        "field" : "gtid"
      }, {
        "type" : "string",
        "optional" : false,
        "field" : "file"
      }, {
        "type" : "int64",
        "optional" : false,
        "field" : "pos"
      }, {
        "type" : "int32",
        "optional" : false,
        "field" : "row"
      }, {
        "type" : "int64",
        "optional" : true,
        "field" : "thread"
      }, {
        "type" : "string",
        "optional" : true,
        "field" : "query"
      } ],
      "optional" : false,
      "name" : "io.debezium.connector.mysql.Source",
      "version" : 1,
      "field" : "source"
    }, {
      "type" : "struct",
      "fields" : [ {
        "type" : "string",
        "optional" : false,
        "field" : "id"
      }, {
        "type" : "int64",
        "optional" : false,
        "field" : "total_order"
      }, {
        "type" : "int64",
        "optional" : false,
        "field" : "data_collection_order"
      } ],
      "optional" : true,
      "name" : "event.block",
      "version" : 1,
      "field" : "transaction"
    }, {
      "type" : "string",
      "optional" : false,
      "field" : "op"
    }, {
      "type" : "int64",
      "optional" : true,
      "field" : "ts_ms"
    }, {
      "type" : "int64",
      "optional" : true,
      "field" : "ts_us"
    }, {
      "type" : "int64",
      "optional" : true,
      "field" : "ts_ns"
    } ],
    "optional" : false,
    "name" : "mysql-cdc.ordersdb.orders.Envelope",
    "version" : 2
  },
  "payload" : {
    "before" : null,
    "after" : {
      "id" : 9,
      "customer_name" : "LEE22",
      "amount" : "LuA=",
      "created_at" : "2025-10-19T14:46:20Z"
    },
    "source" : {
      "version" : "3.2.4.Final",
      "connector" : "mysql",
      "name" : "mysql-cdc",
      "ts_ms" : 1760885180000,
      "snapshot" : "false",
      "db" : "ordersdb",
      "sequence" : null,
      "ts_us" : 1760885180000000,
      "ts_ns" : 1760885180000000000,
      "table" : "orders",
      "server_id" : 1,
      "gtid" : null,
      "file" : "binlog.000040",
      "pos" : 203732050,
      "row" : 0,
      "thread" : 410,
      "query" : null
    },
    "transaction" : null,
    "op" : "c",
    "ts_ms" : 1760885180748,
    "ts_us" : 1760885180748329,
    "ts_ns" : 1760885180748329000
  }
}
```

- update : update 수만큼 이벤트 옴

```json
{
  "schema" : {
    ...
  },
  "payload" : {
    "before" : {
      "id" : 8,
      "customer_name" : "LEE22",
      "amount" : "LuA=",
      "created_at" : "2025-10-19T13:40:52Z"
    },
    "after" : {
      "id" : 8,
      "customer_name" : "MOD_LEE22",
      "amount" : "LuA=",
      "created_at" : "2025-10-19T13:40:52Z"
    },
    "source" : {
      "version" : "3.2.4.Final",
      "connector" : "mysql",
      "name" : "mysql-cdc",
      "ts_ms" : 1760885949000,
      "snapshot" : "false",
      "db" : "ordersdb",
      "sequence" : null,
      "ts_us" : 1760885949000000,
      "ts_ns" : 1760885949000000000,
      "table" : "orders",
      "server_id" : 1,
      "gtid" : null,
      "file" : "binlog.000040",
      "pos" : 203733180,
      "row" : 0,
      "thread" : 411,
      "query" : null
    },
    "transaction" : null,
    "op" : "u",
    "ts_ms" : 1760885949152,
    "ts_us" : 1760885949152329,
    "ts_ns" : 1760885949152329000
  }
}
```

```json
{
  "schema" : {
    ...
  },
  "payload" : {
    "before" : {
      "id" : 9,
      "customer_name" : "LEE22",
      "amount" : "LuA=",
      "created_at" : "2025-10-19T14:46:20Z"
    },
    "after" : {
      "id" : 9,
      "customer_name" : "MOD_LEE22",
      "amount" : "LuA=",
      "created_at" : "2025-10-19T14:46:20Z"
    },
    "source" : {
      "version" : "3.2.4.Final",
      "connector" : "mysql",
      "name" : "mysql-cdc",
      "ts_ms" : 1760885949000,
      "snapshot" : "false",
      "db" : "ordersdb",
      "sequence" : null,
      "ts_us" : 1760885949000000,
      "ts_ns" : 1760885949000000000,
      "table" : "orders",
      "server_id" : 1,
      "gtid" : null,
      "file" : "binlog.000040",
      "pos" : 203733180,
      "row" : 1,
      "thread" : 411,
      "query" : null
    },
    "transaction" : null,
    "op" : "u",
    "ts_ms" : 1760885949152,
    "ts_us" : 1760885949152769,
    "ts_ns" : 1760885949152769000
  }
}
```

- delete

```json
{
  "schema" : {
    ...
  },
  "payload" : {
    "before" : {
      "id" : 10,
      "customer_name" : "MOD_LEE",
      "amount" : "LuA=",
      "created_at" : "2025-10-19T14:54:39Z"
    },
    "after" : null,
    "source" : {
      "version" : "3.2.4.Final",
      "connector" : "mysql",
      "name" : "mysql-cdc",
      "ts_ms" : 1760886160000,
      "snapshot" : "false",
      "db" : "ordersdb",
      "sequence" : null,
      "ts_us" : 1760886160000000,
      "ts_ns" : 1760886160000000000,
      "table" : "orders",
      "server_id" : 1,
      "gtid" : null,
      "file" : "binlog.000040",
      "pos" : 203733582,
      "row" : 0,
      "thread" : 411,
      "query" : null
    },
    "transaction" : null,
    "op" : "d",
    "ts_ms" : 1760886160859,
    "ts_us" : 1760886160859853,
    "ts_ns" : 1760886160859853000
  }
}
```

- `payload.op`에 Create(c), Update(u), Delete(d) 나와있음

### 동시성 ?
- 동일한 테이블에 대한 이벤트는 순서대로 처리돼야한다.
- 여러 컨슈머에서 동일한 테이블 이벤트를 처리하면 안되지않을까 ??
- 그럼 컨슈머 구성을 어떻게하는게 좋을까




## 참고 자료
---

- [https://docs.confluent.io/platform/current/connect/index.html](https://docs.confluent.io/platform/current/connect/index.html)
