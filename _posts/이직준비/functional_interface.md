

```java
@FunctionalInterface
public interface Function<T, R> {
    R apply(T t);
}
```
- Function<T, R>는 입력(T)을 받아 출력(R)을 반환하는 함수형 인터페이스입니다.
- 즉, apply(T t) 메서드를 구현하여 T 타입의 입력값을 받아 R 타입의 결과값을 반환합니다.


