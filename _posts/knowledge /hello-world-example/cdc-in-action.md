
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

- 실제 사례
  - https://techblog.uplus.co.kr/debezium%EC%9C%BC%EB%A1%9C-db-synchronization-%EA%B5%AC%EC%B6%95%ED%95%98%EA%B8%B0-1b6fba73010f
  - https://techblog.lycorp.co.jp/ko/migrating-large-data-with-kafka-and-etl => cdc 사용해서 DB 마이그레이션

```
성공적으로 발행된 ETL 메시지를 MongoDB에 저장할 때 긴 시간이 걸린다면 뒤에 이어지는 CDC 기반 마이그레이션 작업에서 처리할 메시지양이 많아집니다. 그렇게 되면 메시지 보관 기간이 길어지면서 Kafka 리소스를 더 많이 차지합니다. 또한 CDC 기반 마이그레이션 작업은 멱등성을 보장할 수 있도록 구성하긴 했지만 예상치 못한 상황이 발생할 수도 있기에 마이그레이션 시간이 늘어나는 것은 피하고자 했습니다.

따라서 최대한 빠르고 안전하게 메시지를 소비해 ETL 기반 마이그레이션을 완료해야 한다는 목표가 생겼습니다. 쿠버네티스의 리소스는 충분해서 처리량을 높이기 위해 토픽의 파티션을 늘리고 그에 맞게 파드를 실행할 수 있었는데요. 고민했던 점은 '어떻게 MongoDB가 이 높은 처리량을 감당할 수 있도록 만들까?'였습니다.

짧은 시간에 너무 많은 데이터가 삽입되면 복제가 설정된 DB에서는 복제 지연이 발생할 수 있고, 지연이 너무 길어지면 서비스 불가 상태가 될 수 있습니다. 따라서 복제 지연이 너무 커진다면 삽입 속도 조절을 고려해야 합니다.

ETL 이후부터 현재까지의 변경 사항을 MongoDB에 적용하려면 CDC 토픽에 들어온 MySQL CDC 메시지를 MongoDB에 반영하면 되는데 이때 언제부터의 메시지를 소비할 것인지를 정해야 합니다. 사실 ETL 데이터가 정확히 어느 시점의 데이터인지는 알 수 없으며, 시점을 정했을 때 오차가 발생할 확률도 높습니다. 따라서 우선 누락된 메시지를 없애기 위해 ETL을 내리는 시점 직전으로 MySQL CDC 오프셋을 조절했습니다.

이렇게 조치하면 누락된 메시지는 없을 테지만 이미 ETL 테이블에 반영된 메시지가 존재할 수 있는데요. 각 CDC 메시지는 멱등성이 보장된 데이터가 아니기에 중복 처리를 하면 문제가 발생합니다. 즉, 중복된 메시지는 다시 처리되지 않게 로직을 구현해야 합니다.
=> 이미지 테이블에 updatedDate라는 필드가 존재했기에 해당 필드를 사용해서 최신 메시지만 적용하도록 메시지를 판별하는 함수를 구현했습니다. 이로써 중복 메시지가 들어와도 최신 변경 사항만 적용할 수 있습니다.
=> fun isNewerMessage(message: Value): Boolean {
        val existingImage = imageRepository.findById(message.id)
        return existingImage.isEmpty || mapper.convertValue(message.updateDate.get(), OffsetDateTime::class.java).isAfter(existingImage.get().updatedDate)

Debezium MySQL Connector는 기본적으로 PK를 메시지의 키로 사용합니다. 따라서 파티션을 분배할 때 ID가 다르면 다른 파티션으로 분배될 수 있습니다.

메시지 처리 순서에 따라 결과가 달라지는 것을 막기 위해서는 CDC 메시지의 키를 변경해야 합니다. 동일한 의미를 갖는 데이터는 같은 파티션에 할당돼야 멱등성을 보장할 수 있습니다. 저희가 사용하고 있는 Debezium MySQL Connector에서는 message.key.columns라는 속성으로 키를 정의하는 방식을 변경할 수 있는데요. 이를 이용해 아래와 같이 동일한 의미의 메시지는 같은 파티션에 할당되도록 설정해서 CDC 메시지 처리의 멱등성을 보장했습니다.

"message.key.columns": "db_name.table_name:image_id,reference_id,reference_type"
```

=> 멱등성, 토픽/파티션, Kafka 리소스 부하, DB 부하, CDC 시점

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

```java
@Component
public class OrderConsumer {

    @KafkaListener(topics = "mysql-cdc.ordersdb.orders", groupId = "cdc-group")
    public void consume(ConsumerRecord<String, String> record) {
        String key = record.key();
        String value = record.value();

        System.out.println("---- CDC Event ----");
        System.out.println("Key: " + key);
        System.out.println("Value: " + value);
        System.out.println("-------------------");
    }

}
```

- Key, Value 둘 다 아래와 같은 포맷

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

**insert**

- Key

```json
{
  "schema" : {
    "type" : "struct",
    "fields" : [ {
      "type" : "int64",
      "optional" : false,
      "field" : "id"
    } ],
    "optional" : false,
    "name" : "mysql-cdc.ordersdb.orders.Key"
  },
  "payload" : {
    "id" : 13
  }
}
```

- Value

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
      "id" : 13,
      "customer_name" : "LEE66",
      "amount" : "Opg=",
      "created_at" : "2025-10-20T14:34:09Z"
    },
    "source" : {
      "version" : "3.2.4.Final",
      "connector" : "mysql",
      "name" : "mysql-cdc",
      "ts_ms" : 1760970849000,
      "snapshot" : "false",
      "db" : "ordersdb",
      "sequence" : null,
      "ts_us" : 1760970849000000,
      "ts_ns" : 1760970849000000000,
      "table" : "orders",
      "server_id" : 1,
      "gtid" : null,
      "file" : "binlog.000040",
      "pos" : 203734562,
      "row" : 0,
      "thread" : 411,
      "query" : null
    },
    "transaction" : null,
    "op" : "c",
    "ts_ms" : 1760970849105,
    "ts_us" : 1760970849105848,
    "ts_ns" : 1760970849105848000
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

## 실전 시나리오
---
> db 마이그레이션에서 서비스 중단 시간을 최소화하는거야, 예를 들어 mysql -> oracle로 이관한다고 했을때 특정 시점의 스냅샷 데이터를 mysql -> oracle로 이관하고, 이관되는 동안 mysql에 commit된 내역들은 CDC로 수집하는거지. 그리고 스냅샷 이관이 완료되면, 이관되는 동안 commit된 내역에 대한 이벤트들을 oracle에 반영하는거야. 그래서, 쌓인 이벤트들을 최대한 빠르게 Oracle DB에 반영하게 하고싶은거지.(대신 Oracle DB에 큰 부하는 주지 않으면서) 그럼 파티션 개수, 컨슈머 그룹 구성을 어떻게 하는게 좋을것 같아 ? 내 생각엔 티션 : 컨슈머 수 = 1:1 -> 2:2 -> 이런식으로 늘려가면서 최적의 개수를 찾는게 좋지 않나 생각이드는데, 그리고 Oracle db 이상있으면 잠깐 이벤트 cosume을 멈추는? 그런것도 가능한가 ?

- 즉, 주요 목표는:
  - **서비스 중단 없이(또는 최소로)** DB 마이그레이션 (Zero Downtime DB Migration)
  - 마이그레이션 동안 쌓인 DML 이벤트를 **최대한 빠르게 target db에 반영**


### 정확히 원하는 시점의 이벤트부터 쌓는게 가능할까 ?

| 시각       | 액션             | 비고 |
|----------|-----------| ---- |
| 03:59:57 | Cubrid commit  | |
| 03:59:58 | Cubrid commit  | |
| 03:59:59 | Cubrid commit  | |
| 04:00:00 | 이 시점의 스냅샷을 기준으로 MySQL로 데이터 마이그레이션 | |
| 04:00:01 | Cubrid commit | Kafka Connect에서 감지해서 이벤트 발행 |

- 즉, 정확히 스냅샷 이후 커밋부터(04:00:01) 카프카 큐에 적재하는게 가능한가 ?

### 완전한 무중단 마이그레이션이 가능할까 ?
> '스냅샷 마이그레이션 -> cdc 이벤트 target db에 동기화' 하더라도 mysql cdc 이벤트가 계속 발생하는한 완전하게 두 db가 일치된 상태인 경우는 없을것 같은데

현실적인 목표는 “Near-Zero Downtime”  보통 이런 식으로 접근합니다

| 단계                         | 설명                                                  |
| -------------------------- | --------------------------------------------------- |
| **1️⃣ Snapshot Migration** | MySQL 데이터를 Oracle로 bulk dump/import (대부분 Read-only) |
| **2️⃣ CDC 동기화 시작**         | Debezium이 MySQL 변경 이벤트를 Oracle에 실시간 반영              |
| **3️⃣ 동기화 상태 확인**          | Kafka Lag이 거의 0일 때 → Oracle과 MySQL이 거의 일치           |
| **4️⃣ 서비스 Freeze (잠깐)**    | MySQL 쓰기 중단 or Lock (수초~수분)                         |
| **5️⃣ 잔여 CDC 이벤트 반영**      | 남은 이벤트 전부 Oracle에 적용                                |
| **6️⃣ 서비스 DB 전환**          | 애플리케이션 DB URL → Oracle 로 변경                         |
| **7️⃣ Oracle 쓰기 재개**       | Oracle에서 서비스 정상 운영                                  |


### 토픽
- Debezium은 `<topic.prefix>.<database>.<table>` 조합으로 토픽을 자동 생성
- 예시:
```
"topic.prefix": "mysql-cdc",
"database.include.list": "ordersdb,usersdb",
"table.include.list": "ordersdb.orders,ordersdb.payments,usersdb.user_profiles"
```
=> 토픽 : `mysql-cdc.ordersdb.orders`, `mysql-cdc.ordersdb.payments`, `mysql-cdc.usersdb.user_profiles`

- 스냅샷 데이터 마이그레이션이 완전 끝나고 이벤트 consume을 시작하는게 아닌, 마이그레이션이 끝난 테이블 (토픽)은 먼저 consume하는건 ?
=> Sink Connector 여러 개로 분리
=> Spring Boot Application이면 ?

### 파티션 / 컨슈머 그룹
- 그래서 Debezium이 새 토픽으로 이벤트를 publish하면, Kafka 브로커가 내부 설정값을 기준으로 자동 생성합니다.
- Kafka에는 자동 생성 토픽의 구성을 제어하는 설정들이 있습니다:

| 설정 항목                        | 설명                               | 기본값    |
| ---------------------------- | -------------------------------- | ------ |
| `auto.create.topics.enable`  | 존재하지 않는 토픽으로 publish할 때 자동 생성 여부 | `true` |
| `num.partitions`             | 자동 생성되는 토픽의 기본 파티션 수             | `1`    |
| `default.replication.factor` | 자동 생성되는 토픽의 복제본 개수               | `1`    |

- Debezium 입장에서는 “토픽을 지정”할 뿐, Kafka가 어떤 설정으로 토픽을 생성할지는 브로커 설정에 위임

### 파티션 수 변경 방법

**브로커 설정 변경 (글로벌 기본값)**
> Kafka 전체 기본값을 바꿔서 자동 생성 토픽의 파티션 수를 조정할 수 있습니다.

```
# server.properties
num.partitions=4
default.replication.factor=3
```

**토픽 생성 스크립트 실행**

```
kafka-topics.sh --create \
  --topic mysql-cdc.ordersdb.orders \
  --partitions 4 \
  --replication-factor 3 \
  --bootstrap-server localhost:9092
```

**자동 생성 끄고, 명시적으로 관리**
> 운영 환경에서는 보통 이렇게 합니다

```
auto.create.topics.enable=false
```

### Target DB에서 받을 부하 ?
> 순식간에 커밋이 많이 발생하면 ?? 근데 서비스중인 DB가 아니니까 괜찮지 않나 ?

- 부하 조절 방법 ?

“서비스 중이 아니라면 부하 자체는 덜 민감하지만”,
DB 자체의 트랜잭션 처리 구조나 리소스 관리 한계 때문에
한꺼번에 커밋이 몰리면 실제로는 심각한 성능 저하나 병목이 생깁니다.

| 병목 요소                      | 증상                              |
| -------------------------- | ------------------------------- |
| **Redo Log flush**         | 디스크 I/O 병목 (commit latency 급상승) |
| **Undo space 부족**          | ORA-30036 / rollback segment 확장 |
| **Row-level lock 경합**      | PK 중복 update 시 lock 대기          |
| **Buffer cache thrashing** | 대량 DML 시 cache hit ratio 저하     |
| **Index maintenance 부하**   | 인덱스 재정렬로 CPU 폭증                 |


그래서 실무에서는 “CDC 배치 제어”를 둡니다

CDC consumer (예: Spring Boot 애플리케이션) 또는 Sink Connector 쪽에서
DB 반영 속도를 인위적으로 제어합니다.

| 전략                            | 설명                               |
| ----------------------------- | -------------------------------- |
| **① 배치 크기 제한 (Batch Size)**   | 500건, 1000건 단위로 모아 커밋            |
| **② 지연 주입 (Throttle)**        | 커밋 사이에 짧은 sleep(수 ms~수십ms)       |
| **③ 병렬 제한 (Thread Pool)**     | DB insert 스레드 수 제한 (예: 2~4개)     |
| **④ 트랜잭션 크기 조절**              | auto-commit 대신 명시적 commit으로 조절   |
| **⑤ DLQ (Dead Letter Queue)** | DB 오류나 constraint 위반 시 재처리용 큐 분리 |


### 장애 시나리오
- Target DB 장애시
- 이벤트 유실
  - connect <--> kafka
  - kafka <--> consumer

## 참고 자료
---
- [https://kafka.apache.org/documentation.html#connect](https://kafka.apache.org/documentation.html#connect)

- [https://docs.confluent.io/platform/current/connect/index.html](https://docs.confluent.io/platform/current/connect/index.html)
