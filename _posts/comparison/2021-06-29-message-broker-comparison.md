---
title: Message Broker 비교해보기
date: 2021-06-29 00:25:00 +0900
---

> '나만의 웨딩 플래너'라는 MSA 기반의 토이 프로젝트를 진행하는데 필요한 Message Broker를 선택하기 위해
> 몇 가지 Message Broker에 대해 알아보고 결정하자

# RabbitMQ
---
- 2007년에 출시되었으며 가장 먼저 만들어진 메시지 브로커 중 하나이다.
- Erlang으로 개발되었으며, Erlang은 기본적으로 Erlang 클러스터 노드의 쿠키를 동기화하여 분산 컴퓨팅을 지원한다. 따라서, `Zookeeper`와 같은 third-party 클러스터 관리자를 사용하지 않는다.
- 클러스터에는 일반 클러스터 모드와 미러 클러스터 모드의 두 가지 모드가 있다.
- priority queuing, delay queuing과 같은 다양한 기능 제공
- 영속성 : 영구 및 임시 메시지가 모두 지원
- AMQP(Advanced Message Queuing Protocol)를 구현한다. 따라서, STOMP, MQTT, WebSockets과 같은 <br> 다양한 프로토콜을 지원한다.
- 점대점, 요청/응답, pub/sub 모델 모두 지원 (동기, 비동기 통신 모두 지원)
- RabbitMQ 사용자는 메시지 전달을 위한 정교한 규칙을 설정할 수 있다(보안, 조건부 라우팅 등)
- 강력한 인증 및 표현식 기반의 인가를 갖는다.
- 관리자가 스트림 기록에 액세스하려는 경우, `아파치 카산드라`와 종종 함께 사용된다.
- 디스크에 메시지를 저장할 수 있지만 메시지의 순서가 보장되지는 않는다.
- 큐 모니터링을 위한 GUI와 최적의 REST API를 제공한다.
- RabbitMQ는 큐 미러링을 통해 고가용성을 실현한다. RabbitMQ의 큐 개념은 Kafka의 파티션과 유사하다.
- complex routing을 지원하는 많은 기능을 갖추고 있다.
- master-slave 구조를 갖는다
- RabbitMQ의 아키텍처는 완벽한 복제 설계로 인해 확장성이 떨어진다.

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/123817468-24ddb080-d933-11eb-98b2-0aa0da4e5cc5.png"/>
  <figcaption align="center">출처 : https://www.researchgate.net/publication/347866161_A_Fair_Comparison_of_Message_Queuing_Systems</figcaption>
</figure>


# ActiveMQ
---
- JMS(Java Message Service) 클라이언트와 함께 Java로 작성되었다. 이를 통해 OpenWire, STOMP, REST, XMPP, AMQP와 같은 다양한 통신 프로토콜을 지원한다.
- master-slave 구조를 갖는다
  - master 브로커만 서비스를 제공할 수 있다.
  - slave 브로커는 master 브로커와 동기화하며, 오류로 인해 master가 불능이 되면, Zookeeper가 slave 중 새로운 master를 선택한다.
- pub/sub, 점대점 모델을 모두 지원한다.
- 큐와 토픽을 다르게 관리한다.
  - 토픽에 대한 메세지 순서 보장은 없다. 반면, 큐는 Exclusive Queue를 사용함으로써 메세지 순서가 보장된다.
  - 큐에 대해서는 최소 한번의 전달이 보장되며, 토픽의 경우에 전달이 보장되지 않는다.
- 큐에 있는 메세지는 디스크 파일이나 데이터베이스에 저장되지만, 토픽에 있는 메세지는 기본적으로 보존되지 않는다.
- JMS는 메시징 미들웨어의 샤딩 메커니즘을 명시하지 않기 때문에 샤딩 기능이 없으며, 사용자가 필요에 따라 직접 구현해야 한다.


<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/123818994-63279f80-d934-11eb-872f-1492c8148dbd.png"/>
  <figcaption align="center">출처 : https://www.researchgate.net/publication/347866161_A_Fair_Comparison_of_Message_Queuing_Systems</figcaption>
</figure>

# Apache Kafka
---
- 2011년 Linkedin에서 높은 처리량과 짧은 지연 시간 처리를 다루기 위해 만들었다.
- peer-to-peer 구조를 갖는다.
- 대량의 데이터를 장기간 저장하도록 구축된 높은 처리량 분산 큐 시스템이다.
- 분산 스트리밍 플랫폼인 Kafka는 pub/sub 서비스를 복제한다.
- 영속성이 요구되는 일대다 상황에 이상적이다.
- pub/sub 모델을 사용하지만 publisher 대신 producer를 subscriber 대신 consumer라는 용어를 사용한다.
- 토픽을 파티션으로 분할할 수 있다. 이를 통해, 여러 컨슈머가 스트림의 일부를 처리할 수 있고 수평 스케일링을 가능하게 해준다.
- 카프카는 메시지가 배치될 때 가장 잘 작동한다. 즉, 작은 메시지를 많이 수신하는 대신 대규모 데이터 배치로 적게 수신하므로써 성능이 향상된다.
- 가장 작은 배치의 크기는 100바이트, 가급적이면 1-10KB가 좋다.
- 배치 크기가 클수록 구현에 따라 지연 시간이 약간 증가한다(일반적으로 몇 밀리초)
- 하나의 파티션 내의 메세지는 순서가 보장된다.
- 기본적으로 최소 한번의 전달을 보증하며, producer가 비동기식으로 제출하도록 설정하면 최대 한 번까지 전달을 보증한다.
- 모니터링을 위해 GUI가 사전 제공되지 않기 때문에 일반적으로 Kibana를 함께 사용한다.

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/123818292-d381f100-d933-11eb-911f-a4e54c4c2843.png"/>
  <figcaption align="center">출처 : https://www.researchgate.net/publication/347866161_A_Fair_Comparison_of_Message_Queuing_Systems</figcaption>
</figure>

# Redis
---
- 고성능 key-value 저장소 또는 메시지 브로커로 사용할 수 있는 in-memory 저장소이다.
- 영속성이 없지만 Disk/DB에 메모리를 덤프한다.
- 실시간 데이터 처리에도 이상적이다.
- 원래, 레디스는 일대일도 아니었고 일대다도 아니었다. 하지만 Redis5.0 pub/sub을 도입하면서 기능이 향상됐고 일대다 옵션이 됐다.
- 메모리에만 저장하기 때문에 카프카보다도 빠르다.


# 비교해보기
---

## 전반적인 특징
<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/123820407-87d04700-d935-11eb-82c8-c923a7abb1b7.png"/>
  <figcaption align="center">출처 : https://www.researchgate.net/publication/347866161_A_Fair_Comparison_of_Message_Queuing_Systems</figcaption>
</figure>


## 성능
---
### 처리량(Throughput)
<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/123821152-1f359a00-d936-11eb-81cc-ccff914e1dbb.png"/>
  <figcaption align="center">출처 : https://www.researchgate.net/publication/347866161_A_Fair_Comparison_of_Message_Queuing_Systems</figcaption>
</figure>

- 모두 배치 처리 기술을 사용했다. 즉,메시지가 임계값에 도달하기 위해 누적된다.
- 균일하게 전송되므로 전송 오버헤드가 감소하고 처리량이 증가한다.
- 따라서 메시지 크기가 커질수록 배치 처리를 기다리는 시간이 줄어들고 그에 따라 처리량도 증가한다.

### 지연(Latency)
<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/123823452-2cec1f00-d938-11eb-922b-8e4ddf6c9388.png"/>
  <figcaption align="center">출처 : https://www.researchgate.net/publication/347866161_A_Fair_Comparison_of_Message_Queuing_Systems</figcaption>
</figure>

- 카프카와 Rabbit MQ는 다른 시스템보다 긴 지연 시간을 보이는데, 이는 배치 처리를 채택하여 지연 시간을 높이는 대신 처리량을 개선했기 때문이다.

# 나의 선택은 ?
---
- 솔직히, 아직 하나도 제대로 써본 경험이 없어서 위에서 조사한 특징들이 어떤 의미를 갖는 것인지 잘 모르겠다 ..
- Kafka가 처리량, 데이터 영속성 등에서 우수한 것 같으니 Kafka를 먼저 공부하고 사용해보면서 직접 느껴보자

# 더 공부해야할 부분
---
- 메세지 브로커에 대한 전반적인 이해
- Kafka


# 참고 자료
---
- [https://otonomo.io/redis-kafka-or-rabbitmq-which-microservices-message-broker-to-choose/](https://otonomo.io/redis-kafka-or-rabbitmq-which-microservices-message-broker-to-choose/)
- [https://dattell.com/data-architecture-blog/kafka-vs-rabbitmq-how-to-choose-an-open-source-message-broker/](https://dattell.com/data-architecture-blog/kafka-vs-rabbitmq-how-to-choose-an-open-source-message-broker/)
- [https://www.confluent.io/blog/kafka-fastest-messaging-system/](https://www.confluent.io/blog/kafka-fastest-messaging-system/)
- [https://www.researchgate.net/publication/347866161_A_Fair_Comparison_of_Message_Queuing_Systems](https://www.researchgate.net/publication/347866161_A_Fair_Comparison_of_Message_Queuing_Systems)
