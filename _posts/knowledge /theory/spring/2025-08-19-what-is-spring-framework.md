---
title: Spring - Spring Framework 알아보기
date: 2025-08-19 22:25:00 +0900
categories: [지식 더하기, 이론]
tags: [Spring]
---

## 스프링 ?
- "Spring"이라는 용어는 문맥에 따라 다른 의미를 가진다.
  - 원래는 Spring Framework 프로젝트 자체를 가리키는 말이었으며, 거기서 모든 것이 시작됐다.
  - 시간이 지나면서 Spring Framework 위에 다른 Spring 프로젝트들이 만들어졌다.

- Spring Framework는 여러 모듈로 나누어져 있으며, 애플리케이션은 필요한 모듈만 선택해서 사용할 수 있다.
- 가장 중심에는 설정 모델과 의존성 주입(Dependency Injection) 메커니즘을 포함한 코어 컨테이너 모듈이 있다.
  - 그 외에도 Spring Framework는 메시징, 트랜잭션 처리, 데이터 영속성, 웹 등 다양한 애플리케이션 아키텍처를 지원한다.
  - 또한 서블릿 기반의 Spring MVC 웹 프레임워크와, 리액티브 방식의 Spring WebFlux 웹 프레임워크도 포함되어 있다.

- 모듈 예시:
  - spring-core : 스프링의 핵심 기능(의존성 주입, IoC 컨테이너 등)을 담은 모듈
  - spring-beans : Bean 생성, 설정, 라이프사이클 관리 같은 기능을 담당
  - spring-context : ApplicationContext 같은 고수준 컨테이너 제공, 국제화(i18n), 이벤트 시스템 등 포함
  - spring-aop : 관점 지향 프로그래밍(AOP) 지원을 위한 모듈
  - spring-jdbc : JDBC를 더 쉽게 사용할 수 있도록 도와주는 모듈
  - spring-tx : 트랜잭션 관리 관련 기능 제공
  - spring-web / spring-webmvc / spring-webflux : 서블릿 기반 웹 MVC와 리액티브 웹(WebFlux) 지원 모듈

- [Spring Framework Repository](https://github.com/spring-projects/spring-framework) <br>
![image](/assets/img/spring-modules.png)


## 스프링 프레임워크의 역사
- 스프링은 초기 J2EE 명세의 복잡성에 대한 대응으로 2003년에 탄생했다.
> [참고 : J2EE 설계와 개발(expert one-on-one)](https://product.kyobobook.co.kr/detail/S000000832643)

- 일부 사람들은 Java EE와 그 후속인 Jakarta EE가 스프링과 경쟁 관계라고 생각하지만, 실제로는 상호 보완적이다.
- 스프링 프로그래밍 모델은 Jakarta EE 플랫폼 전체 명세를 수용하지 않고, 선택적으로 몇 가지 명세를 통합했다:
  - Servlet API (JSR 340) → 서블릿 API
  - WebSocket API (JSR 356) → 웹소켓 API
  - Concurrency Utilities (JSR 236) → 동시성 유틸리티
  - JSON Binding API (JSR 367) → JSON 바인딩 API
  - Bean Validation (JSR 303) → 빈 검증
  - JPA (JSR 338) → 자바 영속성 API
  - JMS (JSR 914) → 자바 메시징 서비스

- 예시

| 구분      | EE (표준)             | Spring (프레임워크)                           |
|---------|-----------------------|-----------------------------------------------|
| 트랜잭션 관리 | JTA (Java Transaction API) | `@Transactional` (내부적으로 필요 시 JTA 호출, 단순화) |
| 데이터 접근  | JPA (스펙, API만 정의) | Spring Data JPA (JPA 위에 얹어 더 편리한 API 제공) |
| 웹       | Servlet API, JSP      | Spring MVC (Servlet 기반, 더 편리한 MVC 모델 제공) |



**※ 참고 : EE 스펙 변화**

| 구분        | J2EE (Java 2 EE)                 | Java EE                          | Jakarta EE                         |
|-------------|----------------------------------|----------------------------------|------------------------------------|
| 시기        | 1999년 ~ 2006년                  | 2006년 ~ 2017년                  | 2018년 ~ 현재                      |
| 명칭 변화   | Java 2 EE                        | J2EE → Java EE로 개명            | Java EE → Jakarta EE로 개명        |
| 주요 기술   | EJB, Servlet, JSP                | JPA, CDI, Bean Validation 추가   | Servlet, JPA, JMS, Bean Validation |
| 특징        | 복잡하고 무거움                  | J2EE보다 단순화, 그래도 복잡함   | Eclipse Foundation 관리, 더 현대화 |
| 관리 주체   | Sun Microsystems                 | Oracle                           | Eclipse Foundation                 |
| 네임스페이스| javax.*                          | javax.*                          | jakarta.* (EE 9부터)               |
| 비고        | 너무 무거워서 Spring 같은 경량 프레임워크 등장 | 생산성 개선, 표준화 강화          | 현재 공식 자바 엔터프라이즈 표준   |

**※ 참고 : 서블릿, 톰캣, Spring MVC**

- Servlet
  - 스펙 = 실제 구현체가 필요
  - Jakarta EE 표준 API → `jakarta.servlet.*`
  - "요청이 들어오면 어떻게 처리해야 하는가?"를 정의한 인터페이스 규칙

- Tomcat = Servlet 컨테이너 (구현체)
  - Servlet 스펙을 구현한 서버 (Servlet 스펙을 실제로 실행하는 엔진)
  - 주요 역할:
    - HTTP 처리: TCP 소켓 열기, HTTP 요청/응답 파싱
    - Servlet 라이프사이클 관리: `init()`, `service()`, `destroy()` 실행
    - 스레드 풀 관리: 요청당 스레드 할당
    - Filter/Listener 실행: Servlet API 표준에 정의된 기능 수행

- Spring MVC = Servlet 기반 프레임워크
  - Spring MVC는 Servlet 스펙을 직접 구현한 게 아니라, Servlet 위에서 동작하는 프레임워크
  - 핵심 클래스: `DispatcherServlet`
    - DispatcherServlet은 Servlet API를 상속받은 클래스 (`extends HttpServlet`)
    - Tomcat 같은 컨테이너가 DispatcherServlet을 실행시켜 줌
    - 그 안에서 `@Controller`, `@RequestMapping` 등을 해석하고 호출
  - 즉, Spring MVC는 Servlet을 활용해 더 편리한 MVC 개발 모델을 제공하는 추상화 계층


## 스프링을 사용한다는 것 ?

**1. 스프링은 Java 엔터프라이즈 애플리케이션을 쉽게 만들 수 있게 해줌**

- 엔터프라이즈 애플리케이션 = 기업용 대규모 시스템 (ex : 쇼핑몰, 은행, ERP 등)
- J2EE 시절:
  - 서블릿, JDBC, 트랜잭션, 보안 등을 개발자가 일일이 처리해야 함.
  - 예: DB 연결, SQL 실행, 커넥션 닫기, 예외 처리, 트랜잭션 롤백 등 전부 수동 관리.
- 스프링 사용 시:
  - Spring JDBC / Spring Data JPA → DB 연결과 트랜잭션 관리 자동 처리
  - Spring Security → 로그인/권한 관리 쉽게 설정
  - Spring MVC → REST API나 웹 화면 쉽게 개발 가능
  - 따라서 개발자는 **비즈니스 로직**에만 집중할 수 있음.

- 예시 : EJB 2.x 스타일 (회원 등록)

```java
public interface MemberServiceHome extends EJBHome {
    MemberService create() throws RemoteException, CreateException;
}

public interface MemberService extends EJBObject {
    void registerMember(String name) throws RemoteException;
}

public class MemberServiceBean implements SessionBean {
    public void registerMember(String name) {
        // DB 연결, SQL 실행...
    }
}
```

- "회원 등록" 하나 하려는데도, Home Interface / Remote Interface / Bean Class를 다 만들어야 했습니다.
- 개발자가 원하는 간단한 비즈니스 로직을 작성하기 위해서,  인터페이스/설정/보일러플레이트 코드를 너무 많이 작성해야 했음
- 배포할 때도 애플리케이션 서버 종속적이라 포터블(portable)하지 않음
- 작은 프로젝트에서는 과잉 설계였음

- EJB vs Spring
  - EJB (초창기): 무겁고 복잡 → 스프링이 “경량 컨테이너(POJO 기반 DI)”를 들고 등장
  - EJB 3.x 이후: 스프링 아이디어를 많이 가져와서 단순화 → 스프링과 어느 정도 닮아짐
  - 현재: 대부분의 기업 프로젝트는 EJB 대신 Spring을 선택


**2. 스프링은 엔터프라이즈 환경에서 자바 언어를 활용하는 데 필요한 모든 것을 제공**
- "엔터프라이즈 환경에서 필요한 모든 것" = DB, 보안, 메시징, 배치, 분산 트랜잭션 등
- 예시: 은행 계좌 이체 시스템
- 필요한 요소:
  - 트랜잭션(계좌에서 돈 빠지고 다른 계좌에 돈 들어가는 것, 반드시 원자성 보장 필요)
  - 메시징(JMS로 다른 금융 기관에 이벤트 전달)
  - 보안(로그인, 2FA, 권한 분리)
  - 스케줄링(매일 자정에 이자 계산 배치 실행)
- 스프링 지원:
  - Spring Transaction Management → 트랜잭션 자동 처리
  - Spring JMS → 메시지 큐 연동
  - Spring Security → 보안 기능
  - Spring Batch → 배치 작업 실행 및 관리
  - 즉, 개발자가 복잡한 인프라(Infra) 코드를 직접 작성하지 않고, 스프링이 제공하는 모듈을 가져다 쓰면 됨.




## 참고 자료
- [https://docs.spring.io/spring-framework/reference/overview.html](https://docs.spring.io/spring-framework/reference/overview.html)
