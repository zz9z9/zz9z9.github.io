---
title: 테스트 - 테스트 관련 용어 익히기
date: 2025-04-27 00:25:00 +0900
categories: [지식 더하기, 이론]
tags: [Spring]
---

- A nice feature of the Spring Test support is that the application context is cached between tests. That way, if you have multiple methods in a test case or multiple test cases with the same configuration, they incur the cost of starting the application only once. You can control the cache by using the @DirtiesContext annotation.

- `@SpringBootTest(webEnvironment = WebEnvironment.RANDOM_PORT)`
  - use of webEnvironment=RANDOM_PORT to start the server with a random port (useful to avoid conflicts in test environments) and the injection of the port with @LocalServerPort. Also, note that Spring Boot has automatically provided a TestRestTemplate for you.

**MockMvc**
- to not start the server at all but to test only the layer below that, where Spring handles the incoming HTTP request and hands it off to your controller. That way, almost all of the full stack is used, and your code will be called in exactly the same way as if it were processing a real HTTP request but without the cost of starting the server. To do that, use Spring’s MockMvc and ask for that to be injected for you by using the @AutoConfigureMockMvc annotation on the test case.

**@WebMvcTest**
- Spring Boot instantiates only the web layer rather than the whole context.
- In an application with multiple controllers, you can even ask for only one to be instantiated by using, for example, @WebMvcTest(HomeController.class).

**@MockBean**
=> https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-3.4-Release-Notes#mockbean-and-spybean-deprecation
=> deprecated

@MockBean, @SpyBean이 컨텍스트를 너무 무겁게 만들고, 테스트 속도를 떨어뜨리는 문제를 오래 전부터 인식하고 있었어.

대신에, Spring Framework 자체의 @MockBean (이건 Spring Boot 거랑 다른 것)이나
다른 mocking 전략 (pure Mockito, WebMvcTest 안에서 직접 mock 등록 등)을 권장하게 됐어.

특히 Spring Boot 3.2+부터는 테스트용 Context Customizer가 더 유연하게 바뀌어서, 굳이 @MockBean 필요성이 줄어들었어.


**@MockBean vs @SpyBean**
> @MockBean은 진짜 서비스가 전혀 동작하지 않음. 직접 when().thenReturn() 같은 걸 써야 함. <br>
> @SpyBean은 서비스가 원래처럼 동작하는데, 원하면 특정 메서드만 가짜로 바꿀 수 있음.

| 구분       | @MockBean | @SpyBean |
|----------| ---------- | -------- |
| 정의       | 스프링 빈을 Mock 객체로 대체한다. | 스프링 빈을 Spy 객체로 대체한다. |
| 실제 로직 실행 | 실행 안 함 (가짜로만 동작) | 기본적으로 실제 로직 실행함 (필요 시 특정 메서드만 스텁) |
| 주로 사용 용도 | 외부 시스템, 복잡한 의존성 무시하고 테스트에 집중할 때 | 원래 객체 로직을 살리면서, 일부만 확인하거나 조작하고 싶을 때 |
| 예시 코드    | `@MockBean private UserService userService;` | `@SpyBean private UserService userService;` |

```java
@MockBean
private UserService userService;

@Test
void testMock() {
    when(userService.getUserName(1L)).thenReturn("mockUser");
    String name = userService.getUserName(1L);  // 진짜 로직 안 탐
    assertEquals("mockUser", name);
}
```

```java
@SpyBean
private UserService userService;

@Test
void testSpy() {
    doReturn("spyUser").when(userService).getUserName(1L);
    String name = userService.getUserName(1L);  // getUserName만 가짜, 나머지는 진짜
    assertEquals("spyUser", name);
}
```

## 참고 자료
- https://spring.io/guides/gs/testing-web
