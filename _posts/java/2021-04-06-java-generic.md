---
title: 자바 제네릭
date: 2021-04-06 23:00:00 +0900
categories: [Java]
tags: [Java, Generic]
---

# 제네릭
---
* **generic : 포괄적인, 총칭[통칭]의**

> 자바는 여러 타입이 존재하기 때문에, 형 변환을 하면서 많은 예외가 발생할 수 있다.
> 따라서, Java5 부터 도입된 제네릭을 통해 타입 형 변환에서 발생할 수 있는 문제점을 사전에 방지해준다.
> 즉, 컴파일 시 이러한 부분을 점검할 수 있도록 해준다.

```java
public class CastingGenericDTO<T> implements Serialiazble {
	private T object;
    public void setObject(T obj) {
    	this.object= obj;
    }
    public T getObejct() {
    	return object;
    }
}
```

```java
public class GenricTester {
	public static void main(String[] args) {
    	CastingGenericDTO<String> dto1 = new CastingGenericDTO<>();
        dto1.setObject("string type");
		dto1.setObject(new StringBuilder("builder")); // 형 불일치로 컴파일 에러 발생 !

        CastingGenericDTO<StringBuilder> dto2 = new CastingGenericDTO<>();
        dto2.setObject(new StringBuilder("builder type"));

        String val1 = dto2.getObject(); // 형 불일치로 컴파일 에러 발생 !
        StringBuilder val2 = dto1.getObject(); // 형 불일치로 컴파일 에러 발생 !
    }
}
```

## 제네릭 타입의 이름
> 아래 규칙을 따라야 컴파일 되는 것은 아니지만, 통상적으로 쓰이는 것이므로 다른 사람이 보기에도 이해하기 쉽도록 해당 규칙을 따르는게 좋다.

- E : 요소 (Element, 자바 컬렉션에서 주로 사용됨)
- K : 키
- N : 숫자
- T : 타입
- V : 값
- S,U,V : 두 번째, 세 번째, 네 번째에 선언된 타입

### wildcard : ?
- 만약 어떤 메서드에서 CastingGenericDTO 타입의 파라미터를 받고 싶으면 어떻게 해야할까 ?
- 다음과 같이 할 수 있다.
```java
public void printValue(CastingGenericDTO<?> dto) {
   	System.out.println(dto.getObejct());
}
```

- 하지만 위와 같이 하게 되면, CastingGenericDTO 타입의 파라미터에 값을 추가하거나 하는 동작을 할 수는 없다.
- 만약 그러한 로직을 처리해야 한다면 아래와 같이 메서드를 선언할 수 있다.
```java
    public <T> void setValue(CastingGenericDTO<T> dto, T newValue) {
        dto.setObject(newValue);
        System.out.println(dto.getObejct());
    }
```

## 제네릭 선언에 사용하는 타입 범위 지정하기
- <> 안에 어떤 타입도 상관 없지만, wildcard로 사용하는 타입을 제한할 수는 있다.
- 다음과 같이 하면 Car 클래스를 상속받거나, Car 인터페이스를 구현하는 클래스만 파라미터로 받을 수 있다.
```java
    public void printCarType(CastingGenericDTO<? extends Car> car) {
        System.out.println(car.getType());
    }
```
```java
    public <T extends Car> void setCarType(CastingGenericDTO<T> car, T newType) {
        car.setType(newType);
        System.out.println(car.getObejct());
    }
```

### 멀티 제네릭 타입
```java
    public <S,T extends Car> void multiValues(CastingGenericDTO<S> dto, T newCar, S value) {

    }
```

# 실제로 적용하기
> [간단한 웹 서버를 구현해본 토이 프로젝트](https://github.com/zz9z9/nextstep-web-application-server)에서 사용해보았다.

- 클라이언트 측으로 HTTP 응답을 보낼 때, `setStatusCode()`로 상태 코드 세팅시 엉뚱한 값이 들어오지 못하도록
`HttpStatusCode` 타입인 값만 세팅될 수 있게 했다.

```java
public <T extends HttpStatusCode> void setStatusCode(T statusCode) throws IOException {
    dos.writeBytes(String.format("HTTP/1.1 %s \r\n", statusCode.getValue()));
}
```
```java
public interface HttpStatusCode {
    String getValue();
}
```
```java
public enum HttpStatusCode2xx implements HttpStatusCode {
    OK("200 OK"),
    Created("201 Created"),
    Accepted("202 Accepted"),
    NonAuthoritativeInformation("203 Non-Authoritative Information"),
    NoContent("204 No Content"),
    ResetContent("205 Reset Content"),
    PartialContent("206 Partial Content");

    private String statusCode;

    HttpStatusCode2xx(String statusCode) {
        this.statusCode = statusCode;
    }

    @Override
    public String getValue() {
        return this.statusCode;
    }
}
```

# 참고 자료
---
- 이상민, 『자바의 신 2』, 로드북(2017), 21장
