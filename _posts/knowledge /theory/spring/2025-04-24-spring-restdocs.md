---
title: Spring - Spring Rest Docs란 ?
date: 2025-04-24 20:25:00 +0900
categories: [지식 더하기, 이론]
tags: [Spring]
---

## Spring REST Docs란 ?
> RESTful 서비스를 문서화하는 데 도움을 주는 도구

- Asciidoctor로 작성한 수동 문서와 Spring MVC Test를 통해 자동 생성된 스니펫을 결합하여 사용
- 이 프로젝트의 핵심 철학 중 하나는 **테스트를 통해 문서를 생성한다**는 점
  - 이는 API의 실제 동작과 항상 일치하는 정확한 문서가 생성되도록 보장
  - 테스트를 실행하면 요청과 그에 대한 응답에 대한 문서 스니펫이 자동으로 생성

**Asciidoctor ?**
> https://asciidoctor.org/
> Asciidoc이라는 마크업 언어를 HTML, PDF 등의 문서로 변환해주는 도구

- Spring REST Docs는 API 설명서의 본문을 Asciidoc 형식으로 작성하게 하고, 이를 Asciidoctor로 변환해서 최종 문서를 생성

**Asciidoctor로 작성한 수동 문서와 Spring MVC Test를 통해 자동 생성된 스니펫 ?**
> Spring REST Docs는 테스트 코드를 실행할 때, API 요청과 응답을 자동으로 캡처해서 "스니펫(snippet)"이라고 불리는 작은 문서 조각들을 생성

- Spring MVC 테스트
```java
@Test
void helloRestDocs() throws Exception {
    mockMvc.perform(get("/api/hello"))
            .andExpect(status().isOk())
            .andDo(document("hello",
                    responseFields(
                            fieldWithPath("message").description("The hello message")
                    )
            ));
}
```

- 스니펫 예시
```
curl-request.adoc: cURL 명령어 예시
http-request.adoc: 요청 헤더/본문
http-response.adoc: 응답 헤더/본문
response-fields.adoc: 응답 JSON의 필드 설명
```

- Asciidoctor로 작성한 수동 문서

```
= API Documentation
:toc: left

= API 문서입니다.

== Hello API

=== `/api/hello`

include::{snippets}/hello/http-request.adoc[]
```

- 생성된 HTML 문서
![image](/assets/img/rest-docs-img1.png)

## 참고 자료
- [https://spring.io/projects/spring-restdocs#overview](https://spring.io/projects/spring-restdocs#overview)
- [https://www.baeldung.com/spring-rest-docs](https://www.baeldung.com/spring-rest-docs)
