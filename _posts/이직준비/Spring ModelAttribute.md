
- @ModelAttribute는 스프링 MVC에서 컨트롤러 메서드의 파라미터 또는 메서드에 사용되는 어노테이션으로, 요청 데이터를 자바 객체에 자동으로 바인딩하거나, 공통적으로 사용할 데이터를 뷰로 전달할 때 사용하는 기능

- 즉, 스프링 MVC는 요청 파라미터(?email=xxx&name=xxx)를 자바 객체로 변환할 때 **Setter 메서드 또는 생성자를 통해 값을 주입**하는 방식으로 객체를 생성하고 관리해.

### 파라미터에서의 @ModelAttribute

```java
@GetMapping("/search")
public String searchClients(@ModelAttribute ClientSearchRequestDto requestDto, Model model) {
    // requestDto는 자동으로 쿼리스트링과 바인딩됨
    List<Client> clients = clientService.search(requestDto.toSearchParams());
    model.addAttribute("clients", clients);
    return "clientList";
}
```
`GET /search?email=test@example.com&name=John`
=> 이러한 요청에 대해 스프링은 자동으로 아래와 같은 처리를 해줘.

```java
ClientSearchRequestDto requestDto = new ClientSearchRequestDto();
requestDto.setEmail("test@example.com");
requestDto.setName("John");
```

- 파라미터 바인딩 원리 순서
  - 스프링 MVC는 요청을 받고 컨트롤러 메서드를 호출할 때 파라미터를 확인.
  - 파라미터가 @ModelAttribute로 선언되면 객체를 생성하고 HTTP 요청 데이터와 바인딩함.
  - 객체 생성 및 초기화 → 요청 파라미터 → 객체 필드 매핑(setter 또는 생성자) → Validation(옵션) → 컨트롤러 메서드 호출.

### 동작 원리
- @ModelAttribute는 내부적으로 WebDataBinder를 사용하여 HTTP 요청 파라미터를 DTO 객체의 프로퍼티로 바인딩함.
- 바인딩 가능한 데이터 소스는?
  - 쿼리 스트링(?email=xxx)
  - Form 데이터 (HTML 폼에서 POST 방식으로 넘어오는 데이터)
  - PathVariable, SessionAttribute 등 다양한 형태로부터 데이터를 가져올 수 있음.

**※ @ModelAttribute가 없어도 ClientSearchRequestDto에 @Setter나 @AllArgsConstructor가 선언되어 있으면 데이터 바인딩이 잘된다 ?**
> Spring MVC에서 기본적으로 요청 파라미터를 객체로 바인딩할 때 @ModelAttribute를 암시적으로 사용하기 때문

- Spring MVC에서 컨트롤러 메서드의 파라미터 타입을 보고 다음과 같이 동작해:
- 기본 타입 (int, String, Long 등)
  - @RequestParam을 기본적으로 적용해서 매핑함.
  - 예) ?name=John → @RequestParam String name

- DTO (POJO 객체)
  - @ModelAttribute를 기본적으로 적용해서 자동으로 바인딩.
  - 예) ?name=John&email=test@example.com → ClientSearchRequestDto에 자동 매핑
  - 이 경우 DTO에 @Setter, @AllArgsConstructor가 선언되어 있으면 Spring이 내부적으로 `WebDataBinder`를 사용해 값을 넣어줌.

- 쿼리스트링을 DTO로 받을 때는 @ModelAttribute를 생략해도 자동으로 바인딩됨.
- POST 요청에서 폼 데이터를 받을 때는 @ModelAttribute를 명시하는 게 더 직관적.



### 메서드 수준에서의 @ModelAttribute

```java
@Controller
public class ClientController {

    @ModelAttribute("currentUser")
    public User currentUser() {
        return userService.getCurrentUser();
    }

    @GetMapping("/profile")
    public String profile() {
        return "profile"; // "currentUser"가 모델에 자동으로 들어가있음
    }

    @GetMapping("/dashboard")
    public String dashboard() {
        return "dashboard"; // 여기도 "currentUser"가 들어가있음
    }
}
```

- 위의 예시처럼 하면 currentUser는 자동으로 뷰 모델에 포함되어, JSP나 Thymeleaf 등 뷰에서 바로 사용할 수 있게 돼.
- 이렇게 하면 모든 요청 처리 메서드마다 모델에 데이터를 넣어주는 중복을 방지할 수 있어.
