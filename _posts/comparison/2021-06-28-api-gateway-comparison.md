---
title: API Gateway 비교해보기
date: 2021-06-27 00:25:00 +0900
categories: [비교하고 선택하기]
tags: [MSA, API Gateway, Spring Cloud Gateway, Netflix Zuul, AWS API Gateway, AWS ALB]
---

> '나만의 웨딩 플래너'라는 MSA 기반의 토이 프로젝트를 진행하는데 필요한 API Gateway를 만들기 위해 어떤 프레임워크를 선택해야할지
> 몇 가지 API Gateway 프레임워크에 대해 알아보고 결정하자

# API Gateway 역할
---
1. 요청 라우팅
  - 요청을 HTTP 메서드, 경로에 따라 서비스로 라우팅
2. API 조합
  - 여러 서비스를 호출한 결과를 조합
3. 엣지 기능
  - 인증, 인가, 캐싱, 로깅 등
4. 프로토콜 변환
  - 클라이언트 친화적인 프로토콜과 비친화적인 프로토콜간에 상호 변환

# Spring Cloud Netflix Zuul
---
- Spring Cloud 프로젝트에서 `Netflix Zuul`을 병합시켜 만든 프레임워크
- 동기/블로킹 특성을 갖는다.
- Tomcat 서버를 사용한다
- [공식적으로](https://spring.io/blog/2018/12/12/spring-cloud-greenwich-rc1-available-now) 2018년 12월부터 더 이상의 개발은 없고 유지보수만 지원한다.
- Spring boot 2.4.X부터는 zuul이 더 이상 지원되지 않는다.
- 경로 기반의 라우팅만 지원된다.
- 쿼리 아키텍처가 지원되지 않는다.

<figure align = "center">
  <img src = "https://miro.medium.com/max/1920/1*9IeEGHSRMGfAnhqM49TLpQ.png"/>
  <figcaption align="center">출처 : https://netflixtechblog.com/announcing-zuul-edge-service-in-the-cloud-ab3af5be08ee</figcaption>
</figure>


# Spring Cloud Gateway
---
- 스프링5, 스프링 부트2, 스프링 웹플럭스 등의 프레임워크를 토대로한 프레임워크
- Gateway Handler를 사용하여 수신 요청을 적절한 대상으로 간단하고 효과적으로 라우팅
- Netty 서버를 사용하여 반응형/비동기 특성을 지원

<figure align = "center">
  <img src = "https://cloud.spring.io/spring-cloud-gateway/reference/html/images/spring_cloud_gateway_diagram.png"/>
  <figcaption align="center">출처 : https://cloud.spring.io/spring-cloud-gateway/reference/html/</figcaption>
</figure>

# Netflix Zuul2
---
- Netty 서버를 사용하여 반응형/비동기 특성을 지원
- HTTP2, WebSocket 지원
- Zuul2에는 Spring Cloud Neflix Zuul(Zuul1.x)과 같은 내장 지원이 없다. 따라서, 사용하고자 할 경우 Zuul만 따로 서비스를 운영해야 한다.
즉, 기존의 다른 스프링 마이크로 서비스와 통합할 수 없다.

<figure align = "center">
  <img src = "https://miro.medium.com/max/1400/0*ycjEWsSKCaPemEg3."/>
  <figcaption align="center">출처 : https://netflixtechblog.com/open-sourcing-zuul-2-82ea476cb2b3</figcaption>
</figure>


# 나의 선택은 ?
---
- 일단은 토이 프로젝트이고 API Gateway를 처음 적용해보는 것이므로 러닝 커브가 비교적 낮을 것 같은 `Spring Cloud Zuul`을 사용하기로 결정
- [공식 문서](https://cloud.spring.io/spring-cloud-gateway/multi/multi_gateway-starter.html) 에도 나와있지만
Spring Boot 2.0, Spring WebFlux, and Project Reactor 등에 익숙하지 않으면 이것들에 먼저 익숙해져야 한다고 나와있다.
- 다음 프로젝트에서는 반응형 프로그래밍, WebFlux, Netty 등에 대해 학습하고 `Spring Cloud Gateway`를 사용해보자
- [적용 프로젝트 repo](https://github.com/zz9z9/wedding-manager)

# 더 공부해야할 부분
---
- 반응형 프로그래밍
- WebFlux
- Netty
- Spring Cloud Gateway

# 참고 자료
---
- 크리스 리처드슨, 『마이크로서비스 패턴』, 길벗(2020), 8장
- [https://www.programmersought.com/article/28121145498/](https://www.programmersought.com/article/28121145498/)
- [https://cloud.spring.io/spring-cloud-gateway/multi/multi_gateway-starter.html](https://cloud.spring.io/spring-cloud-gateway/multi/multi_gateway-starter.html)
- [novatec-gmbh.de/en/blog/api-gateways-an-evaluation-of-zuul-2/](novatec-gmbh.de/en/blog/api-gateways-an-evaluation-of-zuul-2/)
- [https://medium.com/@niral22/spring-cloud-gateway-tutorial-5311ddd59816](https://medium.com/@niral22/spring-cloud-gateway-tutorial-5311ddd59816)
