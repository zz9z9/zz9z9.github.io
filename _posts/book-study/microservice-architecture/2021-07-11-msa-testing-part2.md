---
title: MSA 환경에서 테스트하기(2) - 통합 테스트
date: 2021-07-11 22:25:00 +0900
categories: [책으로 공부하기, 마이크로서비스 패턴]
tags: [MSA, 테스트 코드]
---
*※ 해당 내용은 '마이크로서비스 패턴(크리스 리처드슨)' 10장을 읽고 필요한 부분을 정리한 내용입니다.*


> ***서비스가 서로 올바르게 상호 작용하는지에 대해서는 단위 테스트만으로는 확인할 수 없다.
> 예를 들어, 실제 DB에 저장을 했는지, 커맨드 메세지를 올바른 포맷으로, 올바른 채널에 전송했는지 등에 대한 부분이다.
> 이를 위해, 서비스를 전부 띄워 놓고 일일이 API를 호출해 보는 종단 간 테스트를 해보면 가장 확실하겠지만
> 이런 테스트는 느리고 취약하며 비용이 많이 든다.
> 따라서, 다른 서비스와 제대로 상호 작용하는지 확인하기 위해서는 단위 테스트 바로 윗 단계인 '통합 테스트'가 필요하다.***

# 컨슈머 주도 계약 테스트(consumer-driven contract test)
---
> 통합 테스트를 진행하기에 앞서 '계약'이라는 개념에 대해 알고가자.
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

# 통합 테스트 작성
---

## 통합 테스트 전략
> 통합 테스트는 전체 서비스를 실행시키지 않는다.
> 테스트 효과에 영향을 끼치지 않으면서 테스트를 간소화하기 위해 두 가지 전략을 사용한다.

1. 각 서비스의 어댑터(가능하면 어댑터의 지원 클래스까지)를 테스트
- 예를 들어, JPA 영속화 테스트를 위해서는 API를 호출하는게 아니라 OrderRepository 클래스를 직접 테스트
- 전체 서비스 대신 소수의 클래스로 테스트 범위를 좁히면 테스트가 단순/신속해진다.
    <figure align = "center">
      <img src = "https://user-images.githubusercontent.com/64415489/125203628-294f8500-e2b4-11eb-9a45-f9f942ce4280.png" width="80%"/>
      <figcaption align="center">출처 : Chris Richardson, 『Microservice Patterns』, p.319</figcaption>
    </figure>

2. 계약(두 서비스 간 상호 작용의 구체적인 사례)을 활용
- 계약의 구조는 서비스 간 상호 작용의 종류마다 다르다.
- 소비자 측 테스트
  - 컨슈머 어댑터에 대한 테스트로서 계약을 이용하여 프로바이더를 모킹한 스텁을 구성
  - 프로바이더를 실행할 필요 없이 컨슈머 통합 테스트를 작성할 수 있다.
- 프로바이더 측 테스트
  - 프로바이더의 어댑터에 대한 테스트로서 어댑터의 디펜던시를 목으로 잡아 놓고 계약을 이용하여 어댑터를 테스트
  <figure align = "center">
    <img src = "https://user-images.githubusercontent.com/64415489/125203537-b47c4b00-e2b3-11eb-9b09-2090f043c734.png"/>
    <figcaption align="center">출처 : Chris Richardson, 『Microservice Patterns』, p.320</figcaption>
  </figure>


## 영속화 테스트
<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/125310840-e6ea7e80-e36d-11eb-83d6-bd43be9b5bb7.png" width="70%"/>
  <figcaption align="center">영속화 테스트 영역</figcaption>
</figure>

- 서비스의 DB 접근 로직이 잘 동작하는지 확인해야한다. 일반적으로 다음과 같은 절차를 거친다.
  1. 설정 - DB 스키마 생성 및 DB 트랜잭션 시작
  2. 실행 - DB 작업 수행
  3. 확인 - DB 상태, 조회한 객체 assertion
  4. 정리 - 트랜잭션 롤백 등 DB에 변경한 내용 undo

```java
@RunWith(SpringRunner.class)
@SpringBootTest(classes = OrderJpaTestConfiguration.class)
public class OrderJpaTest {

  @Autowired
  private OrderRepository orderRepository;

  @Autowired
  private TransactionTemplate transactionTemplate;

  @Test
  public void shouldSaveAndLoadOrder() {

    long orderId = transactionTemplate.execute((ts) -> {
      Order order = new Order(CONSUMER_ID, AJANTA_ID, chickenVindalooLineItems());
      orderRepository.save(order);
      return order.getId();
    });


    transactionTemplate.execute((ts) -> {
      Order order = orderRepository.findById(orderId).get();

      assertNotNull(order);
      assertEquals(OrderState.APPROVAL_PENDING, order.getState());
      assertEquals(AJANTA_ID, order.getRestaurantId());
      assertEquals(CONSUMER_ID, order.getConsumerId().longValue());
      assertEquals(chickenVindalooLineItems(), order.getLineItems());
      return null;
    });

  }

}
```

```java
@Configuration
@EnableJpaRepositories
@EnableAutoConfiguration
public class OrderJpaTestConfiguration {
}
```

- 테스트에서 사용된 DB를 어떻게 프로비저닝(시스템을 즉시 사용할 수 있는 상태로 준비해 두는 것) 하느냐가 중요하다
  - 테스트 도중에 DB 인스턴스를 실행하는 효과적인 방법은 `도커`를 활용하는 것이다.
  - 이러한 방법을 통해 영속화 통합 테스트를 하는 동안에 MySQL 같은 DB를 실행할 수 있다.

## REST 요청/응답형 상호 작용 테스트
> REST 클라이언트/서비스는 REST 끝점 및 요청/응답 본문의 구조에 대해 합의해야 한다.
> 즉, 클라이언트는 정확한 끝점에 HTTP 요청을 보내야하고 서비스는 기대한 응답을 반환해야 한다.

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/125310035-32e8f380-e36d-11eb-8877-3bbe2ee9da8b.png" width="70%"/>
  <figcaption align="center">REST 요청/응답 테스트 영역</figcaption>
</figure>

- 테스트 구성도
<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/125314112-dee00e00-e370-11eb-975f-46618e3abdef.png" width="80%"/>
  <figcaption align="center">출처 : Chris Richardson, 『Microservice Patterns』, p.323</figcaption>
</figure>

- 컨슈머 측 테스트 : OrderServiceProxy가 주문 서비스를 올바르게 호출했는지
  - OrderServiceProxy ⟷ HTTP 스텁 서버(호출될 도메인 서비스의 동작을 흉내)
  - `WireMock`은 HTTP 서버를 효과적으로 모킹하는 툴로서, HTTP 스텁 서버를 구현할 수 있다.
  - `WireMock`을 관리하고 계약에 명시된 HTTP 요청에 응답하도록 구성하는 작업은 `Spring Cloud Contract`의 몫이다.

  ```java
  @RunWith(SpringRunner.class)
  @SpringBootTest(classes=TestConfiguration.class,
          webEnvironment= SpringBootTest.WebEnvironment.NONE)
  @AutoConfigureStubRunner(ids =
          {"net.chrisrichardson.ftgo:ftgo-order-service-contracts"}
  )
  @DirtiesContext
  public class OrderServiceProxyIntegrationTest {

    @Value("${stubrunner.runningstubs.ftgo-order-service-contracts.port}")
    private int port;
    private OrderDestinations orderDestinations;
    private OrderServiceProxy orderService;

    @Before
    public void setUp() throws Exception {
      orderDestinations = new OrderDestinations();
      String orderServiceUrl = "http://localhost:" + port;
      System.out.println("orderServiceUrl=" + orderServiceUrl);
      orderDestinations.setOrderServiceUrl(orderServiceUrl);
      orderService = new OrderServiceProxy(orderDestinations, WebClient.create());
    }

    @Test
    public void shouldVerifyExistingCustomer() {
      OrderInfo result = orderService.findOrderById("99").block();
      assertEquals("99", result.getOrderId());
      assertEquals("APPROVAL_PENDING", result.getState());
    }

    @Test(expected = OrderNotFoundException.class)
    public void shouldFailToFindMissingOrder() {
      orderService.findOrderById("555").block();
    }

  }
  ```

  ```java
  @Configuration
  public class TestConfiguration {

  }
  ```

- 프로바이더 측 테스트 : REST API 끝점이 OrderController에 제대로 구현되었는지
  - MockMvc/Rest Assured Mock Mvc ⟷ OrderController
  - `Spring Cloud Contract`는 계약을 이용하여 주문 서비스 통합 테스트 코드를 생성

  ```java
  public abstract class BaseHttp {

    private StandaloneMockMvcBuilder controllers(Object... controllers) {
      CommonJsonMapperInitializer.registerMoneyModule();
      MappingJackson2HttpMessageConverter converter = new MappingJackson2HttpMessageConverter(JSonMapper.objectMapper);
      return MockMvcBuilders.standaloneSetup(controllers).setMessageConverters(converter);
    }

    @Before
    public void setup() {
      OrderService orderService = mock(OrderService.class);
      OrderRepository orderRepository = mock(OrderRepository.class);
      OrderController orderController = new OrderController(orderService, orderRepository);

      when(orderRepository.findById(OrderDetailsMother.ORDER_ID)).thenReturn(Optional.of(OrderDetailsMother.CHICKEN_VINDALOO_ORDER));
      when(orderRepository.findById(555L)).thenReturn(empty());
      RestAssuredMockMvc.standaloneSetup(controllers(orderController));

    }
  }
  ```

  ```java
  public class OrderControllerTest extends BaseHttp {

    @Test
    public void test() {
      // do something
    }
  }
  ```

## 발행/구독 상호 작용 테스트
> 발행기/컨슈머가 바라보는 메세지 채널 및 도메인 이벤트 구조가 서로 일치하는지 확인해야한다.

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/125317861-49df1400-e374-11eb-85a2-3e1687877a25.png" width="70%"/>
  <figcaption align="center">발행/구독 테스트 영역</figcaption>
</figure>

- 테스트 구성도
<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/125318235-a2aeac80-e374-11eb-80fc-1bd49a7b1bc4.png" width="80%"/>
  <figcaption align="center">출처 : Chris Richardson, 『Microservice Patterns』, p.327</figcaption>
</figure>

- 프로바이더 측 테스트 : OrderDomainEventPublisher가 계약대로 이벤트를 발행하는지 확인

```java
@RunWith(SpringRunner.class)
@SpringBootTest(classes = MessagingBase.TestConfiguration.class, webEnvironment = SpringBootTest.WebEnvironment.NONE)
@AutoConfigureMessageVerifier
public abstract class MessagingBase {

  @Configuration
  @EnableAutoConfiguration
  @Import({EventuateContractVerifierConfiguration.class, TramEventsPublisherConfiguration.class, TramInMemoryConfiguration.class})
  public static class TestConfiguration {

    @Bean
    public OrderDomainEventPublisher orderAggregateEventPublisher(DomainEventPublisher eventPublisher) {
      return new OrderDomainEventPublisher(eventPublisher);
    }
  }


  @Autowired
  private OrderDomainEventPublisher orderAggregateEventPublisher;

  protected void orderCreated() {
    orderAggregateEventPublisher.publish(CHICKEN_VINDALOO_ORDER,
            Collections.singletonList(new OrderCreatedEvent(CHICKEN_VINDALOO_ORDER_DETAILS, AJANTA_RESTAURANT_NAME)));
  }

}
```

```java
class MessageTest extends MessagingBase {

    @Test
    public void validate_orderCreatedEvent() {
        // 메세지가 기대한 채널로 발행되었는지 확인
    }
}
```

- 컨슈머 측 테스트 : OrderHistoryEventHandlers가 계약대로 이벤트를 소비하는지 확인
  - 각 테스트 메서드는 스플링 클라우드를 호출해서 계약에 명시된 이벤트 발행
  - OrderHistoryEventHandlers가 OrderHistoryDao를 올바르게 호출하는지 확인

```java
@RunWith(SpringRunner.class)
@SpringBootTest(classes = OrderHistoryEventHandlersTest.TestConfiguration.class,
        webEnvironment = SpringBootTest.WebEnvironment.NONE)
@AutoConfigureStubRunner(ids =
        {"net.chrisrichardson.ftgo:ftgo-order-service-contracts"}
        )
@DirtiesContext
public class OrderHistoryEventHandlersTest {

  @Configuration
  @EnableAutoConfiguration
  @Import({OrderHistoryServiceMessagingConfiguration.class,
          TramCommandProducerConfiguration.class,
          TramInMemoryConfiguration.class,
          EventuateContractVerifierConfiguration.class})
  public static class TestConfiguration {

    @Bean
    public ChannelMapping channelMapping() {
      return new DefaultChannelMapping.DefaultChannelMappingBuilder().build();
    }

    @Bean
    public OrderHistoryDao orderHistoryDao() {
      return mock(OrderHistoryDao.class);
    }
  }

  @Autowired
  private StubFinder stubFinder;

  @Autowired
  private OrderHistoryDao orderHistoryDao;

  @Test
  public void shouldHandleOrderCreatedEvent() throws InterruptedException {
    when(orderHistoryDao.addOrder(any(Order.class), any(Optional.class))).thenReturn(false);

    stubFinder.trigger("orderCreatedEvent"); // orderCreatedEvent 스텁을 트리거하여 OrderCreated 이벤트 발생

    eventually(() -> { // OrderHistoryEventHandlers가 orderHistoryDao.addOrder() 호출했는지 확인
      ArgumentCaptor<Order> orderArg = ArgumentCaptor.forClass(Order.class);
      ArgumentCaptor<Optional<SourceEvent>> sourceEventArg = ArgumentCaptor.forClass(Optional.class);
      verify(orderHistoryDao).addOrder(orderArg.capture(), sourceEventArg.capture());

      Order order = orderArg.getValue();
      Optional<SourceEvent> sourceEvent = sourceEventArg.getValue();

      assertEquals("Ajanta", order.getRestaurantName());
    });
  }

}
```

## 비동기 요청/응답 상호 작용 테스트
> 예를 들어, 주문 서비스는 주방 서비스 등 여러 서비스에 커맨드 메세지를 전송하고 수신한 응답 메세지를 사가로 처리한다.
> 따라서, 커맨드를 전송하는 서비스인 '요청자'와 커맨드 처리 후 응답을 반환하는 서비스인 '응답자'가 바라보는
> 커맨드 메세지 채널명과 커맨드/응답 메세지의 구조는 반드시 일치해야 한다.

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/125322455-c542c480-e378-11eb-8222-6e6f339d4b85.png" width="70%"/>
  <figcaption align="center">비동기 요청/응답 테스트 영역</figcaption>
</figure>

- 테스트 구성도
<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/125323131-6a5d9d00-e379-11eb-8f1a-e728a0ea3ea1.png" width="80%"/>
  <figcaption align="center">출처 : Chris Richardson, 『Microservice Patterns』, p.331</figcaption>
</figure>

- 컨슈머 측(주문 서비스) 테스트 : KitchenServiceProxy가 커맨드 메세지를 전송하고 응답 메세지를 제대로 처리하는지 확인

```java
@RunWith(SpringRunner.class)
@SpringBootTest(classes= KitchenServiceProxyIntegrationTest.TestConfiguration.class,
        webEnvironment= SpringBootTest.WebEnvironment.NONE)
@AutoConfigureStubRunner(ids = // 주방 서비스 스텁이 메세지에 응답하도록 구성
        {"net.chrisrichardson.ftgo:ftgo-kitchen-service-contracts"}
        )
@DirtiesContext
public class KitchenServiceProxyIntegrationTest {


  @Configuration
  @EnableAutoConfiguration
  @Import({TramCommandProducerConfiguration.class,
          TramInMemoryConfiguration.class, EventuateContractVerifierConfiguration.class})
  public static class TestConfiguration {

    // TramSagaInMemoryConfiguration

    @Bean
    public DataSource dataSource() {
      EmbeddedDatabaseBuilder builder = new EmbeddedDatabaseBuilder();
      return builder.setType(EmbeddedDatabaseType.H2)
              .addScript("eventuate-tram-embedded-schema.sql")
              .addScript("eventuate-tram-sagas-embedded.sql")
              .build();
    }


    @Bean
    public EventuateTramRoutesConfigurer eventuateTramRoutesConfigurer(BatchStubRunner batchStubRunner) {
      return new EventuateTramRoutesConfigurer(batchStubRunner);
    }

    @Bean
    public SagaMessagingTestHelper sagaMessagingTestHelper() {
      return new SagaMessagingTestHelper();
    }

    @Bean
    public SagaCommandProducer sagaCommandProducer() {
      return new SagaCommandProducer();
    }

    @Bean
    public KitchenServiceProxy kitchenServiceProxy() {
      return new KitchenServiceProxy();
    }
  }

  @Autowired
  private SagaMessagingTestHelper sagaMessagingTestHelper;

  @Autowired
  private KitchenServiceProxy kitchenServiceProxy;

  @Test
  public void shouldSuccessfullyCreateTicket() {
    CreateTicket command = new CreateTicket(AJANTA_ID, OrderDetailsMother.ORDER_ID,
            new TicketDetails(Collections.singletonList(new TicketLineItem(CHICKEN_VINDALOO_MENU_ITEM_ID, CHICKEN_VINDALOO, CHICKEN_VINDALOO_QUANTITY))));
    CreateTicketReply expectedReply = new CreateTicketReply(OrderDetailsMother.ORDER_ID);
    String sagaType = CreateOrderSaga.class.getName();

    CreateTicketReply reply = sagaMessagingTestHelper // 커맨드 전송 및 응답 대기
            .sendAndReceiveCommand(kitchenServiceProxy.create, command, CreateTicketReply.class, sagaType);

    assertEquals(expectedReply, reply); // 응답 확인

  }

}
```

- 프로바이더 측(주방 서비스) 테스트 : KitchenServiceCommandHandler가 커맨드 처리 후 응답을 반환하는지 확인

```java
@RunWith(SpringRunner.class)
@SpringBootTest(classes = AbstractKitchenServiceConsumerContractTest.TestConfiguration.class, webEnvironment = SpringBootTest.WebEnvironment.NONE)
@AutoConfigureMessageVerifier
public abstract class AbstractKitchenServiceConsumerContractTest {

  @Configuration
  @Import({KitchenServiceMessageHandlersConfiguration.class, EventuateContractVerifierConfiguration.class})
  public static class TestConfiguration {

    @Bean
    public KitchenService kitchenService() {
      return mock(KitchenService.class);
    }

  }

  @Autowired
  private KitchenService kitchenService;

  @Before
  public void setup() {
     reset(kitchenService);
     when(kitchenService.createTicket(eq(1L), eq(99L), any(TicketDetails.class)))
             .thenReturn(new Ticket(1L, 99L, new TicketDetails(Collections.emptyList())));
  }

}
```

# 참고자료
---
- 크리스 리처드슨, 『마이크로서비스 패턴』, 길벗(2020), 10장
