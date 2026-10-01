---
title: Java - record 타입
date: 2025-03-09 15:00:00 +0900
categories: [지식 더하기, 이론]
tags: [Java]
---

## record ?
- 불변(immutable) 데이터 객체를 간결하게 정의할 수 있는 자바의 새로운 클래스 유형입니다.
- 자동으로 `생성자`를 비롯해, equals(), hashCode(), toString()과 같은 메서드를 자동으로 생성합니다.
- 각 필드는 private final로 자동 지정됩니다.
- 모든 필드는 생성자 매개변수 형태로 표현됩니다.
- 기본적인 getter 메서드는 자동으로 생성됩니다. (필드 이름과 동일한 메서드가 getter가 됨: contactNum() 등)


- intelliJ에서 이거 record로 바꾸라고 제안함
```java
@Getter
public class Client {
    private final String contactNum;
    private final String address;
    private final String email;
    private final String name;

    @Builder
    public Client(String contactNum, String address, String email, String name) {
        this.contactNum = contactNum;
        this.address = address;
        this.email = email;
        this.name = name;
    }

    public String getContactNum() {
        return StringUtils.isEmpty(contactNum) ? "" : contactNum.replaceAll("-", "");
    }

    public Client update(Client toClient) {
        return Client.builder()
                .contactNum(this.contactNum)
                .address(StringUtils.isEmpty(toClient.getAddress()) ? this.address : toClient.getAddress())
                .email(StringUtils.isEmpty(toClient.getEmail()) ? this.email : toClient.getEmail())
                .name(StringUtils.isEmpty(toClient.getName()) ? this.name : toClient.getName())
                .build();
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;
        Client client = (Client) o;
        return Objects.equals(contactNum, client.contactNum);
    }

    @Override
    public int hashCode() {
        return Objects.hash(contactNum);
    }

}
```

```java
@Getter
public record Client(String contactNum, String address, String email, String name) {
    @Builder
    public Client {
    }

    @Override
    public String contactNum() {
        return StringUtils.isEmpty(contactNum) ? "" : contactNum.replaceAll("-", "");
    }

    public Client update(Client toClient) {
        return Client.builder()
                .contactNum(this.contactNum)
                .address(StringUtils.isEmpty(toClient.address()) ? this.address : toClient.address())
                .email(StringUtils.isEmpty(toClient.email()) ? this.email : toClient.email())
                .name(StringUtils.isEmpty(toClient.name()) ? this.name : toClient.name())
                .build();
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;
        Client client = (Client) o;
        return Objects.equals(contactNum, client.contactNum);
    }

    @Override
    public int hashCode() {
        return Objects.hash(contactNum);
    }

}
```

```java
@Getter
public class ApiResponse<T> {

    private final int code;
    private final boolean successful;
    private final String message;
    @JsonInclude(JsonInclude.Include.NON_NULL)
    private final T data;

    public ApiResponse(int code, boolean successful, String message, T data) {
        this.code = code;
        this.successful = successful;
        this.message = message;
        this.data = data;
    }

    public static <T> ApiResponse<T> success(T data) {
        return new ApiResponse<>(HttpStatus.OK.value(), true,"success", data);
    }

    public static <T> ApiResponse<T> error(int status, String message) {
        return new ApiResponse<>(status, false, message, null);
    }

}
```

```java
public record ApiResponse<T>(int code, boolean successful, String message,
                             @JsonInclude(JsonInclude.Include.NON_NULL) T data) {

    public static <T> ApiResponse<T> success(T data) {
        return new ApiResponse<>(HttpStatus.OK.value(), true, "success", data);
    }

    public static <T> ApiResponse<T> error(int status, String message) {
        return new ApiResponse<>(status, false, message, null);
    }

}
```
