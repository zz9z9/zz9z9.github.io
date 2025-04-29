---
title: Controller는 어떤 부분을 테스트 해야할까 ?
date: 2025-04-29 22:20:00 +0900
categories: [생각해보기, 테스트코드]
tags: []
---

> 웹 서비스에서 보편적으로 사용되는 레이어 구조(`Controller - Service - Repository`)에서 Controller는 어떤 부분을 테스트하면 좋을지 생각해보자.

## 테스트 코드의 필요성 ?
> 내가 생각하기에 테스트 코드가 필요한 이유는 크게 두 가지가 있을 것 같다.

1. 코드가 변경됐을 때, 변경된 부분은 의도한대로 잘 동작하는지, 관련이 없는 부분은 원래대로 잘 동작하는지에 대한 보장을 받을 수 있다. 이를 통해 불필요하게 발생하는 운영 이슈를 줄이고 시스템 장애를 예방함으로 좀 견고하고 안정적인 서비스가 될 수 있다.
2. 테스트하고자 하는 대상(기능, 클래스 등)이 어떻게 동작해야하는지에 대한 최신화된 명세서가 될 수 있다. 이를 통해 코드 내부를 일일이 다 살펴보지 않아도 어떤 역할을 하는 코드인지에 대한 파악이 가능하다.

## Controller
> 그렇다면, Controller의 어떤 부분에 대한 테스트를 작성해야 좀 더 안정적인 서비스가 될 수 있을까

- 내가 생각하는 Controller의 주된 역할은 클라이언트의 요청을 받고, 요청에 대한 처리 응답을 내주는 것이다.
- 클라이언트와 맞닿아 있기 때문에, Controller가 의도와 다르게 동작하면 호출하는 클라이언트에서도 예기치 못한 이슈가 발생할 수 있다.

**정상 케이스**
- 정상적인 요청이 왔을때 정상적인 응답이 반환되는지 확인. 즉, 호출하는 입장에서 기대한 응답값이 있는 것을 보장.
  - 이를 통해, 의도치않게 응답 필드가 변경되거나 빠지는 것 또는 추가되는 것 방지
  - 반드시 존재해야하는 응답값 검증 가능

```java
@WebMvcTest(FooController.class)
class FooControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private FooService fooService;

    @Test
    void 정상_응답에_a_b만_포함되고_c는_없어야_한다() throws Exception {
        // Given
        ResultObject resultObject = new ResultObject("valueA", "valueB", "valueC", "valueD");
        given(fooService.doSomething(any(), any(), any())).willReturn(resultObject);

        RequestDTO requestDTO = new RequestDTO("param1", "param2", "param3");

        // When & Then
        mockMvc.perform(post("/api/foo")
                .contentType(MediaType.APPLICATION_JSON)
                .content(new ObjectMapper().writeValueAsString(requestDTO)))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.data.a").value("valueA"))
            .andExpect(jsonPath("$.data.b").value("valueB"))
            .andExpect(jsonPath("$.data.c").doesNotExist());
    }
}
```

**비정상 케이스**
- 비정상적인 요청이 왔을때 1차적으로 Controller에서 막을 부분과 그에 대한 응답 처리가 적절하게 되는지 확인.
  - 이를 통해 비정상적인 요청으로 인한 시스템에 이슈가 생길 수 있는 부분(데이터가 꼬이거나, 불필요한 데이터가 쌓이거나, 의도치않게 데이터가 삭제되거나, 페이징 사이즈 너무 커서 DB에 부하가 발생하는 등) 방지
  - 호출하는 쪽에서 실수로 특정 값을 누락하는 등의 상황에서 응답에 포함된 적절한 메세지로 어떤 문제인지 인지할 수 있음
  - 적절한 status code가 응답되는지

```java
@WebMvcTest(SearchController.class)
class SearchControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private SearchService searchService;

    @Test
    void 필수값_누락시_400과_에러메세지를_반환한다() throws Exception {
        // Given: 필수 필드 빠진 요청
        String invalidRequestJson = """
            {
                "page": 1,
                "size": 100
                // "keyword" 빠짐
            }
        """;

        // When & Then
        mockMvc.perform(post("/api/search")
                .contentType(MediaType.APPLICATION_JSON)
                .content(invalidRequestJson))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.success").value(false))
            .andExpect(jsonPath("$.errors").isArray())
            .andExpect(jsonPath("$.errors", hasItem("검색어는 필수입니다.")));
    }

    @Test
    void 사이즈가_500을_초과하면_400과_에러메세지를_반환한다() throws Exception {
        // Given: size가 501로 너무 큰 요청
        PagingRequestDTO request = new PagingRequestDTO(1, 501, "검색어");

        // When & Then
        mockMvc.perform(post("/api/search")
                .contentType(MediaType.APPLICATION_JSON)
                .content(new ObjectMapper().writeValueAsString(request)))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.success").value(false))
            .andExpect(jsonPath("$.errors", hasItem("size는 최대 500까지만 허용합니다.")));
    }
}
```


- 이런 테스트들을 기반으로 [Spring Rest Docs](https://spring.io/projects/spring-restdocs) 등을 활용하여 API 명세까지 제공한다면, 호출하는 입장에서도 우리 서비스가 좀 더 예측 가능하지 않을까하는 생각이든다.
