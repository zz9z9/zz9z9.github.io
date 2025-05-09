---
title: 마이크로서비스간 통신(3) - 비동기 방식
date: 2021-06-14 22:25:00 +0900
---
*※ 해당 내용은 '마이크로서비스 패턴(크리스 리처드슨)' 3장을 읽고 정리한 내용입니다.*

# 비동기 메시징 패턴 응용 통신
---
> 메시징은 서비스가 메시지를 비동기적으로 주고받는 통신 방식으로서 메시지 브로커를 사용할 수도 있고 서비스간 직접 통신을 할 수도 있다.
> 비동기 통신이기 때문에 클라이언트가 응답을 기다리며 블로킹하지 않고 클라이언트는 응답을 바로 받지 못할 것이라는 전제하에 작성한다.

## 1. 메시지와 채널
> 메시지는 메시지 채널을 통해 교환된다. 송신자가 채널에 메시지를 쓰면 수신자는 채널에서 메시지를 읽는다.

- 메시지
  - 헤더와 바디(본문)으로 구성
  - 헤더에는 송신된 데이터에 관한 메타데이터, 메시지ID, 반환주소 등이 포함
  - 본문은 실제로 송신할 데이터 텍스틑 또는 이진 포맷의 데이터
  - 메시지의 종류는 문서, 커맨드, 이벤트 등으로 다양

- 메시지 채널
  - 채널은 점대점 채널, 발행-구독 채널 두 종류가 있다.
  - 점대점 채널
    - 채널을 읽는 컨슈머 중 딱 하나만 지정해서 메시지 전달
    - 일대일 통신 방식의 서비스가 이 채널을 사용 (ex : 커맨드 메시지)
  - 발행-구독 채널
    - 같은 채널을 바라모는 모든 컨슈머에 메시지 전달
    - 일대다 통신 방식의 서비스가 이 채널을 사용 (ex : 이벤트 메시지)

  <figure align = "center">
    <img src = "https://thebook.io/img/007035/128.jpg" height="50%" width="70%"/>
    <figcaption align="center">출처 : https://thebook.io/007035/ch03/03/01/02/</figcaption>
  </figure>


## 2. 메시지 상호 작용 스타일
> 스타일에 따라 메시징으로 직접 구현 가능한 것, 메시징을 토대로 구현해야 하는 것도 있다.

### 요청/응답 및 비동기 요청/응답
- 클라이언트는 수행할 작업과 매개변수가 담긴 커맨드 메시지를 서비스가 소유한 점대점 메시징 채널로 송신
- 서비스는 요청 처리 후 응답 메시지를 클라이언트가 소유한 점대점 메시징 채널로 송신
- 요청 메시지와 응답 메시지는 짝이 맞아야 하는데, 이는 MessageId와 CorrelationId를 통해 맞춰볼 수 있다.
- 메시징으로 통신하는 클라이언트/서비스 간 상호작용은 비동기적이다.
- 이론적으로 클라이언트가 응답 수신시까지 블로킹할 수는 있지만, 실제로 클라이언트는 응답을 비동기 처리 하고
클라이언트 인스턴스 중 하나가 응답을 처리

  <figure align = "center">
    <img src = "https://thebook.io/img/007035/129.jpg" height="50%" width="90%"/>
    <figcaption align="center">출처 : https://thebook.io/007035/ch03/03/02/01/</figcaption>
  </figure>

### 단방향 알림
- 서비스가 소유한 점대점 채널로 메시지를 보내면, 서비스는 이 채널을 구독해서 메시지 처리
- 서비스는 응답을 반환하지 않는다.

### 발행/구독
- 클라이언트는 여러 컨슈머가 읽는 발행/구독 채널에 메시지를 발행하고, 서비스는 도메인 객체의 변경 사실을 알리는 도메인 이벤트를 발행
- 도메인 이벤트를 발행한 서비스는 해당 도메인 클래스의 이름을 딴 발행/구독 채널을 소유 <br>
(ex : 주문 서비스는 Order 이벤트를 Order 채널에 발행)
- 서비스는 자신이 관심 있는 도메인 객체의 이벤트 채널을 구독

### 발행/비동기 응답
- 발행/구독과 요청/응답 방식을 조합
- 클라이언트는 응답 채널 헤더가 명시된 메시지를 발행/구독 채널에 발행하고, 컨슈머는 CorrelationId가 포함된 응답 메시지를
지정된 응답 채널에 송신
- 클라이언트는 CorrelationId로 응답을 취합하여 응답 메시지와 요청을 맞추어본다

## 3. 메시지 브로커
> 메시지 브로커는 서비스가 서로 통신할 수 있게 해주는 인프라 서비스로서, 메시징 기반의 애플리케이션은 대부분 메시지 브로커를 사용한다.
> 서비스가 서로 직접 통신하는 브로커리스 기반의 메시지 아키텍처도 있지만 일반적으로 브로커 기반의 아키텍처가 갖는 이점이 크다.

### 브로커리스 아키텍처
- 서비스간 메시지를 직접 교환
- 대표적인 브로커리스 메시징 기술로는 ZeroMQ가 있다.
- 장점
  - 서비스간 직접 전달되므로 네트워크 트래픽이 가볍고 지연 시간이 짧다.
  - 메시지 브로커가 성능 병목점이나 SPOF(Single Poing Of Failure, 단일 장애점)이 될 일이 없다.
  - 브로커가 없기 때문에 관리 포인트가 적어진다.
- 단점
  - 서비스가 서로의 위치를 알고 있어야 하므로 서비스 디스커버리 매커니즘을 사용해야 한다.
  - 송/수신자 모두 실행 중이어야 하므로 가용성이 떨어진다.
  - 전달 보장(delivery-guarantee) 같은 매커니즘을 구현하기 어렵다.

### 브로커 기반 메시징 개요
- 대표적인 메시지 브로커로서 ActiveMQ, RabbitMQ, 아파치 카프카가 있다.
- AWS 키네시스, AWS SQS와 같은 클라우드 기반의 메시징 서비스도 있다.
- 장점
  - 느슨한 결합
    - 클라이언트는 서비스 인스턴스를 몰라도 되기 때문에 서비스 디스커버리 매커니즘도 필요 없다.
  - 메시지 버퍼링
    - 메시지 브로커는 컨슈머가 메시지를 처리할 수 있을 때까지 큐에 메시지를 보관하므로 가용성이 높아진다.
  - 다양한 통신 방식을 지원
- 단점
  - 성능 병목 가능성
    - 메시지 브로커가 성능 병목점이 될 가능성이 있다.(따라서, 확장성이 좋아야한다)
  - 단일 장애점 가능성
    - SPOF가 될 수 있기 때문에 가용성이 높아야한다.
  - 운영 복잡도 부가
- 브로커별로 특징이 있다.
  - 어떤 브로커는 지연 시간이 매우 짧지만 메시지 순서 유지 및 전달 보장이 안된다거나, 메시지를 메모리에만 저장한다.
  - 어떤 브로커는 지연 시간은 길지만, 메시지 전달을 보장하고 디스크에 저장한다.
- 따라서, 애플리케이션 요건에 따라 적합한 브로커를 선택해야 한다.


### 메시지 브로커로 메시지 채널 구현
> 메시지 채널은 브로커마다 구현 방식이 조금씩 다르다.

| 메시지 브로커  | 점대점 채널 | 발행-구독 채널 |
|-------------|----------|--------------|
| JMS | 큐 | 토픽 |
| 아파치 카프카 | 토픽 | 토픽 |
|RabbitMQ(AMQP 브로커)| 익스체인지+큐 | 팬아웃 익스체인지, 컨슈머 개별 큐 |
|AWS 키네시스| 스트림 | 스트림 |
|AWS SQS| 큐 | - |

## 4. 수신자 경합과 메시지 순서 유지
> 예를 들어, 동일한 점대점 채널을 읽는 서비스 인스턴스가 3개 있고, 송신자는 주문 생성 → 변경 → 취소 이벤트 메시지를 차례로 전송한다고 가정해보자.
> 만약 네트워크 이슈, 가비지 컬렉션 문제 등으로 지연이 발생하고 메시지 처리 순서가 어긋난다면,
> 주문을 생성하기도 전에 취소 처리를 해야하는 상황이 벌어질 수도 있다.
> 따라서, 메시지를 동시 처리하는 경우 각 메시지를 정확히 한 번만 순서대로 처리하는 것이 보장되어야 한다.

### 샤딩된(파티셔닝된) 채널 이용해서 메시지 처리 순서 보장하기
- 샤딩된 채널은 복수의 샤드로 구성되며, 각 샤드는 채널처럼 작동
- 송신자는 메시지 헤더에 샤드 키를 지정하고, 메시지 브로커는 샤드 키별로 샤드/파티션에 메시지를 배정
- 메시지 브로커는 여러 수신자 인스턴스를 묶어 마치 동일한 수신자인 것처럼 취급한다(카프카에선 '컨슈머 그룹')
- 메시지 브로커는 각 샤드를 하나의 수신자에 배정하고, 수신자가 시동/종료하면 샤드를 재배정한다.
- 아래 그림에서 같은 주문에 대한 이벤트(주문 생성, 변경, 취소 등)는 동일한 샤드에 발행될 것이고(샤드 키인 orderId가 같으므로)
샤드는 하나의 수신자 인스턴스에 배정되기 때문에 메시지 처리 순서가 보장된다.

  <figure align = "center">
    <img src = "https://thebook.io/img/007035/137.jpg" height="50%" width="90%"/>
    <figcaption align="center">출처 : https://thebook.io/007035/ch03/03/05-01/</figcaption>
  </figure>


## 5. 중복 메시지 처리
> 시스템이 정상일 때 '적어도 한 번 전달'을 보장하는 메시지 브로커는 각 메시지를 한 번만 전달한다.
> 그러나 클라이언트나 네트워크 또는 브로커 자신이 실패할 경우, 같은 메시지를 여러번 전달할 수도 있다.
> 단적인 예로, 주문 생성 → 취소 이벤트를 발행했는데 문제가 생겨 생성 이벤트만 재전송하게 되면,
> 결국 주문이 접수되는 문제가 생길 수 있다.

### 멱등한 로직 작성
> 멱등하다 : 동일한 입력 값을 반복 호출해도 결과가 달라지지 않는다 (ex : 주문 취소)

- 메시지 재전송시 순서를 유지하다는 전제하에 멱등한 메시지 로직은 여러 번 호출되도 별 문제가 없다.
- 하지만 실제로 이렇게 멱등한 애플리케이션 로직은 많지 않다.

### 메시지 추적과 중복 메시지 솎아 내기
> 예를 들어, 신용카드 결제 승인과 같은 로직은 여러번 호출되면 심각한 문제를 발생시킬 수 있다. <br>
> 따라서 중복 메시지를 솎아 내는 메시지 핸들러가 필요하다.

- 하나의 방법으로 컨슈머가 소비하는 메시지 ID를 DB 테이블에 저장하여 메시지 ID를 이용하여 메시지 처리 여부를 추적하면서 중복 메시지를 알아낸다.
- 즉, 컨슈머는 메시지를 처리할 때 비즈니스 엔터티를 생성/수정하는 트랜잭션의 일부로 메시지 ID를 DB 테이블에 기록한다.

## 6. 트랜잭셔널 메시징
> DB 업데이트와 메시지 전송을 한 트랜잭션으로 묶지 않으면, DB 업데이트 후 메시지는 아직 전송되지 않은 상태에서 서비스가 중단될 수 있다.
> 이 두 작업이 서비스에서 원자적으로 수행되지 않으면, 실패할 경우 시스템은 매우 불안정한 상태가 될 수 있다.
> 애플리케이션에서 메시지를 확실하게 발행하려면 어떻게 해야할까 ?

### DB 테이블을 메시지 큐로 활용
- RDBMS 기반의 애플리케이션의 경우 DB 테이블을 임시 메시지 큐로 사용할 수 있다.(트랜잭셔널 아웃 박스 패턴)
- 로컬 ACID 트랜잭션이기 때문에 원자성은 자동으로 보장된다.
- NoSQL DB인 경우에는 DB에 레코드로 적재된 비즈니스 엔터티에 발행할 메시지 목록을 가리키는 속성에
DB 엔터티 업데이트시 메시지를 덧붙인다.

  <figure align = "center">
    <img src = "https://thebook.io/img/007035/140.jpg" height="50%" width="90%"/>
    <figcaption align="center">출처 : https://thebook.io/007035/ch03/03/07/01/</figcaption>
  </figure>

### 이벤트 발행 : 폴링 발행기 패턴
- 메시지 릴레이로 테이블을 폴링해서 미발행 메시지를 조회
- 메시지 릴레이는 조회한 메시지를 하니씩 각자의 목적지 채널로 보내서 메시지 브로커에 발행하고 OUTBOX 테이블에서 메시지 삭제
- DB 폴링은 규모가 작은 경우 적합하고, 자주 하는 경우 비용이 유발된다.

### 이벤트 발행 : 트랜잭션 로그 테일링 패턴
- 메시지 릴레이로 DB 트랜잭션 로그(커밋 로그)를 테일링한다.
- 트랜잭션 로그 마이너로 로그를 읽어 변경분을 하나씩 메시지로 브로커에게 발행
- 트랜잭션 로그 마이너는 로그 항목을 읽고, 삽입된 메시지에 대응되는 각 로그 항목을 메시지로 전환하여 브로커에 발행
- 이 방식을 응용한 사례로는, 디비지움, 링크드인 데이터버스, DynamoDB, 이벤추에이트 트램 등이 있다.

  <figure align = "center">
    <img src = "https://thebook.io/img/007035/142.jpg" height="60%" width="90%"/>
    <figcaption align="center">출처 : https://thebook.io/007035/ch03/03/07/03/</figcaption>
  </figure>

# 동기 상호 방식 제거하기
> 요청을 처리하는 과정에서 타 서비스와 동기 통신을 하면 그만큼 가용성이 떨어지므로 <br>
> 가능한 서비스가 비동기 메시징을 이용하여 통신하도록 설계하는 것이 바람직하다.

## 비동기 방식으로 처리
- 동기 방식으로 처리

  <figure align = "center">
    <img src = "https://thebook.io/img/007035/147.jpg" height="60%" width="90%"/>
    <figcaption align="center">출처 : https://thebook.io/007035/ch03/04/01/</figcaption>
  </figure>

- 비동기 방식으로 바꿔보기

  <figure align = "center">
    <img src = "https://thebook.io/img/007035/148.jpg" height="60%" width="90%"/>
    <figcaption align="center">출처 : https://thebook.io/007035/ch03/04/02/01/</figcaption>
  </figure>

## 데이터 복제
- 서비스 요청 처리에 필요한 데이터의 레플리카를 유지하는 방법
- 데이터 레플리카를 통해 다른 서비스와 상호 작용할 필요가 없어진다.
- 하지만 대용량 데이터의 레플리카를 만드는 것은 매우 비효율적이다.

  <figure align = "center">
    <img src = "https://thebook.io/img/007035/149.jpg" height="60%" width="90%"/>
    <figcaption align="center">출처 : https://thebook.io/007035/ch03/04/02/02/</figcaption>
  </figure>

## 응답 반환 후 마무리

  <figure align = "center">
    <img src = "https://thebook.io/img/007035/151.jpg" height="70%" width="90%"/>
    <figcaption align="center">출처 : https://thebook.io/007035/ch03/04/02/03-01/</figcaption>
  </figure>

- 주문 서비스는 다른 서비스를 호출하지 않은 채 주문을 생성한 후, 다른 서비스와 메시지를 교환하여 생성한 Order를 비동기적으로 검증한다.
- 이렇게 처리하면 다른 서비스가 내려가더라도 주문 서비스는 계속 주문을 생성하고 클라이언트에 응답을 할 수 있다.
나중에 문제가 됐던 서비스가 재기동 되면 큐에 쌓인 메시지를 처리하고 밀린 주문을 검증할 수 있다.
- 이처럼 요청을 완전히 처리하기 전에 클라이언트에 응답하는 서비스는 클라이언트가 조금 복잡해진다.
  - 클라이언트 입장에서 주문 생성 성공 여부를 알아내려면 주기적으로 폴링하거나 주문 서비스가 알림 메시지를 보내줘야 한다.
  - 복잡하지만 동기 방식보다는 이게 더 나은 방법이다. 왜냐하면 분산 트랜잭션 관리 이슈를 이런 방식으로 해결할 수 있기 때문이다.

---

# 실제로 적용해보기
---
- [토이 프로젝트 '나만의 웨딩 매니저' 통신 방식 구조](https://zz9z9.github.io/posts/my-wedding-manager-communication-architecture/)

# 더 공부해야할 부분
---
- 논블로킹 / 비동기
- 로그 테일링
- 메시지 브로커별 특징

# 참고 자료
---
- 크리스 리처드슨, 『마이크로서비스 패턴』, 길벗(2020), p104-152.
