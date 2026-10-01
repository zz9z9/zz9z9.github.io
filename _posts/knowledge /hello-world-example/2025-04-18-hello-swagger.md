---
title: Swagger 훑어보기
date: 2025-04-18 22:25:00 +0900
categories: [지식 더하기, Hello-World 구현]
tags: [MyBatis]
---


## Swagger2
- Swagger2, Spring-boot 2.7.15 버전에서 발생

Caused by: java.lang.NullPointerException: Cannot invoke "org.springframework.web.servlet.mvc.condition.PatternsRequestCondition.getPatterns()" because "this.condition" is null

Spring Boot 2.6부터 WebMvcConfigurer 내부에서 사용하는 path matching 전략이 ant_path_matcher → path_pattern_parser로 바뀌었어요.

Springfox 3.0.0은 이 변경을 제대로 지원하지 못해서 내부에서 null이 되어 NPE가 발생하는 거예요.

```yaml
spring:
  mvc:
    pathmatch:
      matching-strategy: ant_path_matcher
```

- Next, create Docket Bean to configure Swagger2 for your Spring Boot application.


http://localhost:8080/swagger-ui.html 접속 시 404 Not Found
👉 Springfox 3.0.0부터 접속 경로가 변경됨 => http://localhost:8080/swagger-ui/index.html

http://localhost:8080/v2/api-docs
=> OpenAPI 명세 JSON ?

- OpenAPI랑 swagger 뭔상관 ? OpenAPI는 머지 ??
  - OpenAPI 는 의미가 완전 다릅니다.
    OpenAPI또는 OpenAPI Specification(OAS)라고 부르는데, 이는 RESTful API를 기 정의된 규칙에 맞게 API spec을 json이나 yaml로 표현하는 방식을 의미합니다.
    직접 소스코드나 문서를 보지 않고 서비스를 이해할 수 있다는 장점이 있습니다.

정리하면, RESTful API 디자인에 대한 정의(Specification) 표준이라고 생각하시면 될 것 같습니다.

예전에는 Swagger 2.0와 같은 이름으로 불렸다가 현재는 3.0버전으로 올라오면서 OpenApi 3.0 Specification으로 칭합니다.

```java
// springfox.documentation.spi.DocumentationType
public class DocumentationType extends SimplePluginMetadata {
  public static final DocumentationType SWAGGER_12 = new DocumentationType("swagger", "1.2");
  public static final DocumentationType SWAGGER_2 = new DocumentationType("swagger", "2.0");
  public static final DocumentationType OAS_30 = new DocumentationType("openApi", "3.0");

  ...
}
```

| ff                                                                                                          | ff |
|-------------------------------------------------------------------------------------------------------------| ---- |
| Swagger                                                                                                     | 	REST API를 문서화하기 위한 사양(Spec) 또는 도구 세트. 원래는 Swagger UI, Editor, Codegen, OpenAPI 스펙 등을 포함함 |
| Springfox |	Swagger 사양을 기반으로 Spring MVC/Spring Boot에서 API 문서를 자동 생성하는 라이브러리 (Swagger 2.x 시절부터 등장) |
| OpenAPI	| Swagger 사양이 발전해서 공식 이름이 바뀐 것 (Swagger → OpenAPI 3.x) |
| springdoc-openapi |	Swagger의 후속(OpenAPI 3.x)을 Spring Boot에서 쓰기 쉽게 해주는 새로운 대체 라이브러리 (Springfox의 후속이라고 생각해도 무방) |


## springdoc-openapi
> https://springdoc.org/

Besides generating the OpenAPI 3 specification, we can integrate springdoc-openapi with Swagger UI to interact with our API specification and exercise the endpoints.

- The springdoc-openapi dependency already includes Swagger UI, so we’re all set to access the API documentation at:

http://localhost:8080/swagger-ui/index.html


OpenAPI-specific annotations.

## OpenAPI
- https://www.openapis.org/
- OpenAPI Specification : RESTful API 디자인에 대한 정의(Specification) 표준
  Swagger : OpenAPI를 Implement하기 위한 도구

## 헷갈리는 관계 정리
### Swagger
-  Swagger는 원래 Wordnik이라는 온라인 사전 서비스를 만들던 Tony Tam이라는 개발자가 API 문서를 자동화하기 위해 만든 도구였어요.
- API 명세를 쉽게 작성하고, 사람도 이해하기 쉬운 UI로 표현하려는 목적이었죠.
- 이 도구가 인기를 끌면서 오픈소스로 공개되고 여러 기업에서 사용하게 되었어요.
- 2015년에 Swagger는 SmartBear라는 회사에 인수되었고, 그 이후 큰 변화가 시작됩니다.
- Swagger는 Swagger Editor, Swagger UI, Swagger Codegen 같은 도구를 포함
  - 즉, Swagger는 Word, Excel, Power Point 등을 모아놓은 MS Office같은 느낌

| 도구 이름             | 역할 |
|-------------------| --- |
| Swagger UI        | OpenAPI 문서를 브라우저에서 시각화해서 보여주는 도구 |
| Swagger Editor    | 브라우저에서 OpenAPI 문서를 직접 작성/편집할 수 있는 도구 |
| Swagger Codegen   | OpenAPI 문서를 기반으로 클라이언트 SDK나 서버 코드 생성 |
| Swagger Inspector | API 호출을 테스트하고 문서로 내보낼 수 있는 도구 |

### OpenAPI
> https://www.openapis.org/

- Swagger 스펙은 2015년에 OpenAPI Specification이라는 이름으로 변경됩니다.
- SmartBear는 Linux Foundation과 함께 OpenAPI Initiative라는 단체를 만들고, Swagger 명세를 여기에 기부했어요.
- OpenAPI Initiative에는 Google, Microsoft, PayPal 같은 대기업들이 참여하고 있어요.
- 현재 OpenAPI는 REST API 명세를 위한 산업 표준 포맷으로 자리 잡았습니다.
- 예전에는 Swagger = API 명세라고 생각했지만 이제는 Swagger는 “도구”의 이름, **OpenAPI는 “API 명세 스펙(표준)”**이에요.
  - 원래는 Swagger Specification이라고 불렸어요.  2015년에 Swagger 명세가 OpenAPI Specification으로 이름이 바뀌면서, Swagger 2.0은 OpenAPI Specification 2.0이 되었어요.

| 버전  | 명칭 | 특징 |
|-----| --- | --- |
| 1.x | Swagger | 초기 버전 (비공식 표준) |
| 2.0 | Swagger 2.0 → OpenAPI 2.0 | 지금도 일부 시스템에서 사용 중 |
| 3.0 | OpenAPI 3.0 | 큰 구조적 변화 (Request body 분리 등) |
| 3.1 | OpenAPI 3.1 | JSON Schema 2020-12 호환 등 최신 명세 반영 |

### springdoc-openapi
- Spring Boot 애플리케이션의 Controller, RequestMapping, DTO 등을 분석해서 자동으로 OpenAPI 3.0 문서를 생성해줍니다.
- Swagger UI와 통합되어, 브라우저에서 인터랙티브한 API 문서 페이지도 같이 제공해줘요.
- `/v3/api-docs`에서 OpenAPI 3.0 JSON 명세를, `/swagger-ui.html`에서 Swagger UI로 확인할 수 있게 해줍니다.

| 항목      | 설명                                                   |
|---------|------------------------------------------------------|
| Swagger |  OpenAPI 문서를 시각화하거나 활용하는 도구 브랜드 (Swagger UI, Codegen 등)              |
| OpenAPI | Swagger 명세를 기반으로 발전한 공식 REST API 명세(스펙)              |
| springdoc-openapi	| Spring Boot 기반 애플리케이션에서 OpenAPI 명세를 자동으로 생성해주는 라이브러리 |

- Springfox (Swagger 2 기반)	과거 많이 쓰였던 Swagger 명세 자동 생성 도구 (Swagger 2.x 기반)
- springdoc-openapi	최신 OpenAPI 3.x 스펙 기반, 더 나은 호환성과 유지보수 상태

- 즉, Swagger UI는 OpenAPI 명세를 기반으로 API를 시각화해주기 때문에 이를 위해서는 Open API 명세가 필요하다.
  - 이러한 명세를 스프링/스프링 부트 기반 애플리케이션에서 생성할 수 있도록 지원하는게 `Springfox`, `springdoc-openapi`와 같은 라이브러리들


## 참고 자료
- [https://www.tutorialspoint.com/spring_boot/spring_boot_enabling_swagger2.htm](https://www.tutorialspoint.com/spring_boot/spring_boot_enabling_swagger2.htm)
- [https://www.baeldung.com/spring-rest-openapi-documentation](https://www.baeldung.com/spring-rest-openapi-documentation)
- [https://nordicapis.com/whats-the-difference-between-swagger-and-openapi/](https://nordicapis.com/whats-the-difference-between-swagger-and-openapi/)
