---
title: MSA 환경에서 테스트하기(1)
date: 2021-07-10 22:25:00 +0900
categories: [책으로 공부하기, 마이크로서비스 패턴]
tags: [MSA, 테스트 코드]
---
*※ 해당 내용은 '마이크로서비스 패턴(크리스 리처드슨)' 9장을 읽고 필요한 부분을 정리한 내용입니다.*

# 테스트 개요
---
## 자동화 테스트 작성
> 설정 → 실행 → 확인 → 정리

1. 설정 - SUT(System Under Test, 테스트할 대상)와 그 디펜던시로 구성된 테스트 픽스처(test fixture)를 초기화한다.
2. 실행 - SUT 호출 (ex : 테스트 클래스의 특정 메서드)
3. 확인 - 호출 결과 및 SUT의 상태를 단언(assertion)
4. 정리 - 필요한 경우 설정 단계에서 초기화한 DB 트랜잭션을 롤백하는 등의 뒷정리

## Stub/Mock을 이용한 테스트
> SUT는 대부분 디펜던시를 갖고 있고, 이런 디펜던시 때문에 테스트가 복잡하고 느려질 수 있다. 예를 들어, OrderController 클래스는
> OrderService를 호출하고, OrderService 역시 다른 수많은 애플리케이션/인프라 서비스에 의존할 수 있다. 이런 경우,
> OrderController만 따로 테스트하고 싶다면 ?

- SUT가 의존하는 디펜던시를 테스트 더블(디펜던시의 동작을 흉내낸 객체)로 대체한다.
- 테스트 더블은 스텁, 목 두 종류가 있다.
  - 스텁(stub) - SUT에 값을 반환하는 객체
  - 목(mock) - 스텁의 일종으로, SUT가 정확하게 디펜던시를 호출했는지 확인하는 객체
- 일반적으로 테스트 더블은 목 객체 프레임워크인 `Mockito`를 활용해서 구현한다.

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/125169216-1e2d2400-e1e4-11eb-9368-8d0ad4a4b4ce.png" width="80%"/>
  <figcaption align="center">출처 : Chris Richardson, 『Microservice Patterns』, p.296 </figcaption>
</figure>

## 자동화 테스트의 종류
- 일반적으로 '범위'에 따라 테스트는 다음과 같이 나뉜다.
  - 단위 테스트(unit test) - 서비스의 작은 부분(ex : 클래스)을 테스트
  - 통합 테스트(integration test) - 테스트 대상 서비스가 인프라 서비스, 타 서비스 등과 연동되어 잘 작동하는지 테스트
  - 컴포넌트 테스트(component test) - 개별 서비스에 대한 인수 테스트(acceptance test)
  - 종단 간 테스트(end-to-end test) - 전체 애플리케이션에 대한 인수 테스트
- 종단 간 테스트는 중간에 있는 수 많은 디펜던시까지 실행시켜야 하기 때문에, 가능한 한 작성하지 않는 것이 최선이다.

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/125169087-99daa100-e1e3-11eb-82c5-6d718fb08204.png"/>
  <figcaption align="center">출처 : Chris Richardson, 『Microservice Patterns』, p.299 </figcaption>
</figure>


# 마이크로서비스 테스트
---
> ***마이크로서비스는 팀별로 맡은 서비스를 개발하고 API를 발전시켜나가는 분산 시스템이다.
> 따러서, 서비스 개발자는 자신이 개발한 서비스가 디펜던시 및 클라이언트와 잘 연동되는지 반드시 테스트 해야한다.***

## 컨슈머 주도 계약 테스트 (consumer-driven contract test)
> 두 서비스 간의 상호 작용은 두 서비스 사이의 합의 또는 계약이다. 예를 들어, 주문 서비스와 주문 이력 서비스는
> 서로에게 발행될 이벤트 메세지의 구조와 채널에 대해 합의해야 한다.
> API 게이트웨이와 도메인 서비스 역시 REST API 끝점에 대해 합의해야 한다.

- 서비스가 클라이언트의 기대에 부합하는지 확인하는 테스트
  - 클라이언트는 어떠한 서비스를 호출하는 서비스(API 게이트웨이, 다른 도메인 서비스 등)이다.
- 컨슈머(호출하는 서비스)-프로바이더(호출되는 서비스)의 관계를 맺는다.
- 프로바이더의 API가 컨슈머가 기대한 바와 일치하는지 확인하는 것. 즉, 프로바이더에 대한 통합 테스트이다.
- 비즈니스 로직을 체크하는 테스트가 아니다.
- 다음 사항을 확인
  - 컨슈머가 기대한 HTTP 메서드와 경로인가 ?
  - (헤더가 있는 경우) 컨슈머가 기대한 헤더를 받는가 ?
  - (요청 본문이 있는 경우) 요청 본문을 받는가 ?
  - 컨슈머가 기대한 상태 코드, 헤더, 본문이 포함된 응답을 반환하는가 ?
- 컨슈머/프로바이더간 상호 작용을 계약(contract)이라는 샘플 모음집으로 정의하는 것
  - 예를 들어, REST API의 계약은 HTTP 요청/응답 샘플을 모아 놓은 것
- `Spring Cloud Contract`를 사용하여 컨슈머 계약 테스트를 진행할 수 있다.
- 프로세스
  1. 컨슈머 팀은 개발한 서비스가 프로바이더와 상호 작용하는 방법이 기술된 계약을 작성해서 깃 풀 리퀘스트 등을 통해 프로바이더 팀에 전달
  2. 프로바이더 팀은 계약을 JAR로 패키징해서 메이븐 저장소에 발행
  3. 컨슈머 쪽 테스트는 저장소에서 JAR 파일을 내려받는다.
  4. 주문 서비스의 API를 소비하는 컨슈머 개발 팀은 계약 테스트 스위트를 추가하고, 기대대로 주문 서비스 API가 동작하는지 확인
<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/125169689-4fa6ef00-e1e6-11eb-9f4a-4ed0991e6054.png"/>
  <figcaption align="center">출처 : Chris Richardson, 『Microservice Patterns』, p.302 </figcaption>
</figure>

# 서비스 단위 테스트 작성
---
> 단위 테스트는 서비스의 아주 작은 부속품인 단위(unit)가 제대로 동작하는지 확인하는 테스트이다.
> 일반적으로 단위는 클래스이므로 단위 테스트의 목표는 해당 클래스가 잘 동작하는지 확인하는 것이다.

- 단위 테스트에는 두 가지 종류가 있다.
  - 독립(solitary) 단위 테스트 - 클래스 디펜던시를 목 객체로 나타내고 클래스를 따로 테스트
  - 공동(sociable) 단위 테스트 - 클래스와 디펜던시를 테스트
- 어떤 종류의 단위테스트를 할지는 클래스의 책임과 아키텍처에서의 역할마다 다르다. 다음은 일반적으로 많이 쓰는 테스트 전략이다.
  - 엔티티와 값 객체(Value Object) 같은 도메인 객체는 공동 단위 테스트 수행
  - 여러 서비스에 걸쳐 데이터 일관성을 유지하는 사가는 공동 단위 테스트 수행
  - 컨트롤러와 도메인 서비스 클래스는 독립 단위 테스트 수행
  - 인바운드/아웃바운드 메시징 게이트웨이는 독립 단위 테스트 수행

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/125170218-d8bf2580-e1e8-11eb-9135-7f220666368a.png"/>
  <figcaption align="center">출처 : Chris Richardson, 『Microservice Patterns』, p.308 </figcaption>
</figure>

## 도메인 서비스 테스트
> 이 클래스에 있는 메서드는 일반적으로 엔티티와 리파지토리를 호출하며 도메인 이벤트를 발행한다. 이런 종류의 클래스를 효과적으로 테스트 하려면,
> 리파지토리 및 메시징 클래스 같은 디펜던시를 모킹(mocking)하고 독립 단위 테스트를 수행해야 한다.

- 일반적으로 다음과 같은 프로세스로 진행된다.
1. 설정 : 서비스 디펜던시의 목 객체를 구성
2. 실행 : 서비스 메서드를 호출
3. 확인 : 서비스 메서드가 올바른 값을 반환하고 디펜던시가 올바르게 호출되었는지 확인

## 컨트롤러 테스트
> 컨트롤러 클래스는 각각 지정된 REST API 끝점을 담당한 여러 메서드로 구성된다. 메서드의 매개변수는 경로 변수(path variable)처럼
> HTTP 요청에서 추출된 값을 나타낸다. 컨트롤러 메서드는 도메인 서비스 또는 리파지토리를 호출해서 응답 객체를 반환한다.

- 컨트롤러에서 호출하는 도메인 서비스, 리파지토리 같은 것들을 모킹하여 컨트롤러에 대해 독립 단위 테스트를 수행하는 것이 좋다.
- 컨트롤러 클래스를 인스턴스화하고 메서드를 호출할 수도 있지만, 이렇게 하면 요청 라우팅 같은 중요한 기능은 테스트할 수 없다.
- 따라서 목 MVC 테스트 프레임워크를 활용하는 것이 효율적이다.
  - `Spring MockMvc`, `Rest Assured Mock`이 대표적인 예이다.
  - HTTP 요청을 보내서 반환된 HTTP 응답을 단언(assertion)할 수 있기 때문에
  진짜 네트워크 호출을 하지 않아도 HTTP 요청 라우팅 및 자바 객체 ⟷ JSON 변환이 가능하다.

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/125201570-b8579f80-e2aa-11eb-8832-e99d925a3497.png"/>
  <figcaption align="center">출처 : https://terasolunaorg.github.io/guideline/5.4.1.RELEASE/en/UnitTest/ImplementsOfUnitTest</figcaption>
</figure>

## 이벤트/메세지 핸들러 테스트
> 메세지 어댑터는 컨트롤러처럼 도메인 서비스, 레파지토리 등을 호출하는 단순 클래스이다.
> 즉, 메세지 어댑터의 각 메서드는 메세지/이벤트에서 꺼낸 데이터를 서비스 메서드에 넘겨 호출한다.
> 따라서, 메세지 어댑터는 컨트롤러와 비슷한 방법으로 단위 테스트를 수행할 수 있다.

- 테스트별로 메세지 어탭터 인스턴스를 생성하고 메세지를 채널에 전송한 후, 서비스 목이 정확히 호출되었는지 확인한다.
- 메세징 인프라는 스터빙하기 때문에 실제 메세지 브로커는 관여하지 않는다.
- `Eventuate Tram Mock Messaging` 프레임워크를 이용해서 테스트한다.

```java
public class OrderEventConsumerTest {

  private OrderService orderService;
  private OrderEventConsumer orderEventConsumer;

  @Before
  public void setUp() throws Exception {
    orderService = mock(OrderService.class);
    orderEventConsumer = new OrderEventConsumer(orderService);
  }

  @Test
  public void shouldCreateMenu() {

    CommonJsonMapperInitializer.registerMoneyModule();

    given().
            eventHandlers(orderEventConsumer.domainEventHandlers()).
    when().
            aggregate("net.chrisrichardson.ftgo.restaurantservice.domain.Restaurant", AJANTA_ID).
            publishes(new RestaurantCreated(AJANTA_RESTAURANT_NAME, RestaurantMother.AJANTA_RESTAURANT_MENU)).
    then().
       verify(() -> {
         verify(orderService).createMenu(AJANTA_ID, AJANTA_RESTAURANT_NAME, new RestaurantMenu(RestaurantMother.AJANTA_RESTAURANT_MENU_ITEMS));
       })
    ;

  }

}
```

# 참고자료
---
- 크리스 리처드슨, 『마이크로서비스 패턴』, 길벗(2020), 9장
