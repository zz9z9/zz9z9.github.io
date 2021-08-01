---
title: (미해결) 카프카 프로듀서 재송신 테스트
date: 2021-07-31 14:00:00 +0900
categories: [Kafka]
tags: [Kafka, 미해결]
---

# 상황
---
카프카의 전달 보증에 대해 공부했고 at most once, at least once, exactly once 세 종류가 있다는 것을 알게되었다.
각 전달 보증 수준에 대해 공부하면서, 브로커에서 응답하는 ack가 오지않는(유실되는) 경우 프로듀에서 메시지를 재전송 하는 부분에 대해
다음과 같은 테스트를 해보고 싶었다.

- at most once
  - ack가 오지 않아도 메시지를 재전송하지 않는다.

- at least once
  - ack가 오지 않으면 메시지를 재전송한다.
  - 이미 브로커에서 저장된 메시지에 대해 재전송 하게되면, 메시지가 중복으로 저장될 수 있다.

- exactly once
  - ack가 오지 않으면 메시지를 재전송한다.
  - 이미 브로커에서 저장된 메시지에 대해 재전송 하더라도, 브로커에서는 중복 메시지 처리 알고리즘을 활용해 메시지를 중복 저장하지 않는다.

하지만, 생각처럼 상황을 시뮬레이션 할 수가 없었고 어떤 부분을 더 공부해야 원하는 테스트를 제대로 할 수 있는지 모르겠다...
일단 시도해본 것과 실패에 대한 원인을 적어보고, 앞으로 더 공부하면서 어떤걸 몰랐고 잘못 생각하고 있던건지 깨닫게 될 때, 다시 제대로 테스트해서 이 글을 보완할 예정이다.

# 시도해본 것들
---
## Case 1. at least once 수준에서의 재송신
- 환경 및 옵션 세팅
  - 브로커 1대 / acks = 1(default) / request.timeout.ms = 1000 (1초) / retries = 10

- 테스트 시나리오
  1. 브로커를 끈다.
  2. 프로듀서에서 메시지를 송신한다.
  3. request.timeout.ms에 정의된 시간 내에 ack 응답이 오지 않으면 10번 재송신된다.
  4. send 메서드 두 번째 파라미터인 Callback 인터페이스를 구현하여, 재송신된 10건의 메시지에 대한 exception이 10번 뜨는지 확인한다.

- 테스트 결과
  - `exception : org.apache.kafka.common.errors.TimeoutException: Failed to update metadata after 60000 ms.`

- 프로듀서 코드

```java
import org.apache.kafka.clients.producer.*;
import org.apache.kafka.common.serialization.StringSerializer;

import java.util.Properties;
import java.util.Scanner;

public class SampleProducer {
    private static final String TOPIC_NAME = "jaeyoon";
    private static final String FIN_MESSAGE = "exit";

    public static void main(String[] args) {
        Properties properties = new Properties();
        properties.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, "localhost:9092");
        properties.put(ProducerConfig.ACKS_CONFIG, "1");
        properties.put(ProducerConfig.REQUEST_TIMEOUT_MS_CONFIG, 1000);
        properties.put(ProducerConfig.RETRIES_CONFIG, 10);
        properties.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());
        properties.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());

        KafkaProducer<String, String> producer = new KafkaProducer<>(properties);

        while(true) {
            Scanner sc = new Scanner(System.in);
            System.out.print("Input > ");
            String message = sc.nextLine();

            ProducerRecord<String, String> record = new ProducerRecord<>(TOPIC_NAME, message);
            try {
                producer.send(record, (metadata, exception) -> {
                    System.out.println("metadata : "+metadata);
                    if (exception != null) {
                        // some exception
                        System.out.println("exception : "+exception);
                    }
                });
            } catch (Exception e) {
                // exception
            } finally {
                producer.flush();
            }

            if(message.equals(FIN_MESSAGE)) {
                producer.close();
                break;
            }
        }
    }
}
```

### 결과 분석
- 브로커가 꺼져있었기 때문에 ***metadata를 제한 시간내에 가져오지 못해서*** 발생한 에러이다.
  - send 메서드는 실행 후 `max.block.ms(default 60000)`에 정의된 만큼 metadata fetch 및 버퍼 할당을 기다리는 총 시간을 제한한다.
  - 해당 시간이 초과하면 `TimeoutException`이 발생한다.

### 메타데이터는 언제 가져오나 ?
  - 프로듀서가 처음으로 메타데이터 요청을 하는 때는 클라이언트 구성에서 설정한 부트스트랩 서버(`bootstrap.server`)에 연결할 때다.
    - 물론, 한 대 이상의 브로커일 수 있지만 반드시 클러스터에 있는 모든 브로커일 필요는 없다(따라서 메타데이터 요청은 각 브로커에 대한 것이 아님).
    - 메타데이터를 통해, 프로듀서는 자신이 메시지를 보내고자 하는 토픽이 어디에 있는지 정보를 얻는다.
  - 또는, 토픽의 리더 레플리카를 가진 브로커에 연결 오류가 발생하면 메타데이터 요청을 수행할 수 있다.
    - 이 경우 브로커에 연결하기 위해(다른 토픽에 대해 아직 연결되지 않은 경우) 어떤 브로커가 새 리더인지 알아야 한다.

<br>

## Case 2. 1번 케이스에서 메타데이터 얻어온 후 브로커 종료
- 환경 및 옵션 세팅 (case1과 동일)
  - 브로커 1대 / acks = 1(default) / request.timeout.ms = 1000 (1초) / retries = 10

- 테스트 시나리오
  1. 브로커를 켜고 메시지를 한 번 송신한다.(메타데이터를 받아온다.)
  2. 브로커를 끈다.
  3. 메시지를 송신한다.
  4. request.timeout.ms에 정의된 시간 내에 ack 응답이 오지 않으면 10번 재송신된다.
  5. send 메서드 두 번째 파라미터인 Callback 인터페이스를 구현하여, 재송신된 10건의 메시지에 대한 exception이 10번 뜨는지 확인한다.

- 프로듀서 코드 (case1과 동일)

- 테스트 결과

```
Input > bye

exception : org.apache.kafka.common.errors.TimeoutException: Expiring 1 record(s) for jaeyoon-0: 1018 ms has passed since batch creation plus linger time
```

### 결과 분석
- 해당 에러는 버퍼에 쌓인 레코드가 `request.timeout.ms(default 30000)`에 세팅된 시간 + `linger.ms (default 0)`에 세팅된 시간을 초과할 때 까지 브로커에 송신되지 않으면 발생한다.
  - 일반적으로 `레코드가 버퍼에 쌓이는 속도 >>> 레코드를 송신하는 속도`인 경우 레코드가 버퍼에서 대기하는 시간이 길어져 이러한 에러가 발생할 수 있다.
  - 위 테스트의 경우에는 프로듀서가 송신할 브로커를 찾지 못해 버퍼에 레코드가 쌓여있다가 `request.timeout.ms`에 세팅된 1초를 넘겨 에러가 발생했다.
- `linger.ms`
  - 프로듀서는 해당 옵션에 세팅된 시간만큼(default 0) 지연 후 브로커로 메시지를 송신한다.
  - 즉, 버퍼에 쌓인 레코드를 즉시 내보내는 것이 아니라, 다른 레코드가 함께 전송될 수 있도록(batch 처리) 기다린다.

### batch 처리
- 레코드는 브로커에게 전송하기 위한 묶음으로(batch) 그룹화되어 메시지당 전송 오버헤드를 줄이고 처리량을 증가시킨다.
  - send 메서드를 호출하면 브로커에게 보낼 수 있도록 ProducerRecord가 내부 버퍼에 저장된다.
  - send 메서드는 전송 여부와 관계없이 ProducerRecord가 버퍼링되면 즉시 return 한다.
  - 배치가 제한 시간보다 오래 대기한 경우 예외가 발생하며, 해당 배치의 레코드는 전송 대기열에서 제거된다. (위 테스트의 경우)

<br>

## Case3. min.insync.replicas 활용하여 에러 발생시키기
- 환경 및 옵션 세팅
  - 브로커 3대 / replication.factor = 3 / min.insync.replicas = 2 / acks = all / retries = 5
  - 토픽 생성
    - `./bin/kafka-topics.sh --create --zookeeper localhost:2181 --config min.insync.replicas=2 --replication-factor 3 --partitions 1 --topic 토픽명`

- 테스트 시나리오
  1. 브로커를 3대를 켠다.
  2. 메시지를 한 번 송신하고 정상적으로 처리되는지 확인한다.
  3. 브로커 두 대를 다운시킨다.
  4. 브로커가 한 대만 남아있으므로 `min.insync.replicas=2`를 만족할 수 없기 때문에 에러가 발생할 것이고 메시지는 재전송 될 것이다.
  5. send 메서드 두 번째 파라미터인 Callback 인터페이스를 구현하여, 재송신된 10건의 메시지에 대한 exception이 10번 뜨는지 확인한다.

- 테스트 결과
  - 프로듀서 측

  ```
  Input > down test!

  exception : org.apache.kafka.common.errors.NotEnoughReplicasException: Messages are rejected since there are fewer in-sync replicas than required.
  ```

  - 브로커 측 (1대 남은 브로커)
    - 첫 번째 에러 발생 후, 프로듀서 측에 세팅한 대로 5번 재시도 하는 것을 볼 수 있다.

  ```
  [2021-08-02 04:05:07,937] ERROR [ReplicaManager broker=0] Error processing append operation on partition dawn-0 (kafka.server.ReplicaManager)
  org.apache.kafka.common.errors.NotEnoughReplicasException: The size of the current ISR Set(0) is insufficient to satisfy the min.isr requirement of 2 for partition dawn-0
  [2021-08-02 04:05:08,043] ERROR [ReplicaManager broker=0] Error processing append operation on partition dawn-0 (kafka.server.ReplicaManager)
  org.apache.kafka.common.errors.NotEnoughReplicasException: The size of the current ISR Set(0) is insufficient to satisfy the min.isr requirement of 2 for partition dawn-0
  [2021-08-02 04:05:08,150] ERROR [ReplicaManager broker=0] Error processing append operation on partition dawn-0 (kafka.server.ReplicaManager)
  org.apache.kafka.common.errors.NotEnoughReplicasException: The size of the current ISR Set(0) is insufficient to satisfy the min.isr requirement of 2 for partition dawn-0
  [2021-08-02 04:05:08,258] ERROR [ReplicaManager broker=0] Error processing append operation on partition dawn-0 (kafka.server.ReplicaManager)
  org.apache.kafka.common.errors.NotEnoughReplicasException: The size of the current ISR Set(0) is insufficient to satisfy the min.isr requirement of 2 for partition dawn-0
  [2021-08-02 04:05:08,363] ERROR [ReplicaManager broker=0] Error processing append operation on partition dawn-0 (kafka.server.ReplicaManager)
  org.apache.kafka.common.errors.NotEnoughReplicasException: The size of the current ISR Set(0) is insufficient to satisfy the min.isr requirement of 2 for partition dawn-0
  [2021-08-02 04:05:08,465] ERROR [ReplicaManager broker=0] Error processing append operation on partition dawn-0 (kafka.server.ReplicaManager)
  org.apache.kafka.common.errors.NotEnoughReplicasException: The size of the current ISR Set(0) is insufficient to satisfy the min.isr requirement of 2 for partition dawn-0
  ```

- 프로듀서 코드

```java
import org.apache.kafka.clients.producer.*;
import org.apache.kafka.common.serialization.StringSerializer;

import java.util.Properties;
import java.util.Scanner;

public class SampleProducer {
    private static final String TOPIC_NAME = "dawn";
    private static final String FIN_MESSAGE = "exit";

    public static void main(String[] args) {
        Properties properties = new Properties();
        properties.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, "localhost:9092,localhost:9093,localhost:9094");
        properties.put(ProducerConfig.ACKS_CONFIG, "all");
        properties.put(ProducerConfig.REQUEST_TIMEOUT_MS_CONFIG, 1000);
        properties.put(ProducerConfig.RETRIES_CONFIG, 5);
        properties.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());
        properties.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());

        KafkaProducer<String, String> producer = new KafkaProducer<>(properties);

        while (true) {
            Scanner sc = new Scanner(System.in);
            System.out.print("Input > ");
            String message = sc.nextLine();

            ProducerRecord<String, String> record = new ProducerRecord<>(TOPIC_NAME, message);
            try {

                producer.send(record, (metadata, exception) -> {
                    if (exception != null) {
                        // some exception
                        System.out.println("exception : " + exception);
                    }
                });
            } catch (Exception e) {
                // exception
            } finally {
                producer.flush();
            }

            if (message.equals(FIN_MESSAGE)) {
                producer.close();
                break;
            }
        }
    }
}
```

### 결과 분석
- 브로커 측에서 프로듀서에 세팅한 재송신 횟수 만큼의 예외 메시지를 출력한다. 그렇다는건 초기에 세팅한 횟수만큼 메시지를 재전송 했다는 것이다.
- 재전송을 하긴 했는데, 프로듀서 측에서의 콜백은 한 번만 발생했다.
  - 재전송이라는게 send 메서드가 여러번 호출되는 개념이 아니라, send를 한 번 호출하면 그 안에서 필요한 경우 자동으로 재전송이 되고 그에 대한 최종적인 결과를 콜백 메서드에 넘겨주는건가 ?
  - 정확히 send 메서드 내부의 코드를 이해하지는 못했지만, 이에 대한 의문은 RetriableException에 대해 공부하면서 조금은 해소되었다.

### RetriableException
- 프로듀서의 에러 처리에는 두 가지가 있다.
  - 프로듀서가 자동으로 처리하는 에러(=재시도 가능한 에러)
  - 개발자가 프로듀서 라이브러리를 사용해서 처리해야하는 에러
- 예를 들어, `LEADER_NOT_AVAILABE` 같은 에러는 리더가 다시 선출되면 해결되는 문제이므로 ***재시도 가능한 에러(retriable error)*** 라고 한다.
- 반면, `INVALD_CONFIG`에러 (구성이 잘못되어 발생한 에러)의 경우는 아무리 메시지를 재전송해도 구성이 변경되지 않으므로 ***재시도 불가능한 에러***이다.
- ***재시도 가능한 에러는 카프카 프로듀서 객체가 알아서 해주므로 우리 코드에서 직접 처리할 필요가 없다.***
- 위에서 발생한 `NotEnoughReplicasException` 또한 재시도 가능한 에러이다.
![image](https://user-images.githubusercontent.com/64415489/127784192-639bed9f-f9f7-4ccc-a30e-fc658140b829.png)

### ReplicaManager
- 테스트 결과의 브로커 측 예외 메시지를 보면 `kafka.server.ReplicaManager`에서 에러를 발생시키는 것 같아 찾아보니 다음과 같은 구성으로 되어있는 것 같다.
- "ReplicaManager manages log replicas using the LogManager." 라고 설명 되어있는데, 카프카 서버측 로그를 담당하는 역할을 하는 것 같다.

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/127783271-9fc5dea4-1ba9-41b0-a9fe-4682f9a835b2.png"/>
  <figcaption align="center">출처 : https://jaceklaskowski.gitbooks.io/apache-kafka/content/kafka-server-ReplicaManager.html </figcaption>
</figure>


## Case4. at most once vs at least once 메시지 유실 정도 비교 (작성중)
- 새로운 리더 선발하는 동안 at most once와 at least once의 메시지 유실 정도 비교하기

`./bin/kafka-topics.sh --describe --topic 토픽명 --zookeeper localhost:2181` 명령어를 통해 leader 레플리카를 파악한다.


# Case 별로 배운 부분
---
추측이나 확실히 모르겠는건 추후 보완 예정 !

## Case1~2
- 브로커에서 ack 응답이 오지 않는 상황을 브로커를 다운시킴으로써 시뮬레이션 하려고 했으나, 브로커가 꺼져있으면 프로듀서에서 브로커로 송신 자체가 되지 않는다.
- ***ack를 유실하는 경우를 어떻게 시뮬레이션 할 수 있을까 ??***

## Case3
- 재시도 가능한 에러는 프로듀서 내부에서 자동으로 재전송해준다. (해당 코드는 어디에 있을까 ?)
- 추측 : 재전송이 여러번 되더라도 send 메서드에 대한 콜백은 한 번만 발생하는 것 같다.

# 참고자료
---
- [https://kafka.apache.org/documentation/#producerconfigs](https://kafka.apache.org/documentation/#producerconfigs)
- [https://stackoverflow.com/questions/56794122/metadata-requests-in-kafka-producer](https://stackoverflow.com/questions/56794122/metadata-requests-in-kafka-producer)
- [https://stackoverflow.com/questions/46750420/kafka-producer-error-expiring-10-records-for-topicxxxxxx-6686-ms-has-passed](https://stackoverflow.com/questions/46750420/kafka-producer-error-expiring-10-records-for-topicxxxxxx-6686-ms-has-passed)
- [https://bistros.tistory.com/152](https://bistros.tistory.com/152)
- 네하 나크헤데 외 2인 『카프카 핵심 가이드』, 제이펍(2018), chapter6
