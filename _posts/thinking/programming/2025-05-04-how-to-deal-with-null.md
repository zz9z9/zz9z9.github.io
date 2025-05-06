---
title: 자바에서 null 처리에 대해 생각해보기
date: 2025-05-04 10:25:00 +0900
categories: [생각해보기, 코드 작성]
---

## 나는 언제 주로 `null`을 사용했을까 ?
- 참조값이 '없음'을 표현하는 경우
- 따라서, 보통 있는 경우와 없는 경우를 구분해서 처리하기 일반적으로 아래와 같이 코드를 작성하게 되는 것 같다.

```java
if (obj == null) {
    // do something
    // 또는, null인게 비정상적인 상황이라면 적절한 예외 발생시키기
} else {
    // do something
}
```

## 그렇다면, `null`의 단점은 뭐가 있을까 ?
- 해당 객체를 다룰 때 주의하지 않으면 NPE가 발생한다.
  - 따라서, null인지를 확인하는 코드가 반복적으로 나타나야하고 이로 인해 코드가 지저분해질 수 있다.
  - 또한, 이런 null 객체들이 코드 이곳 저곳에 돌아다니면 NPE가 발생할 확률은 높아질 것이고 이로 인해 서비스의 신뢰성이 낮아질 수 있다.
- `null`을 리턴받는 입장에서는 이게 진짜 값이 없는 것인지, 어떤 에러가 발생한 것인지 등 해당 값만으로는 정확한 맥락을 파악할 수가 없거나, 상세 구현을 확인해봐야 한다.
  - 정확한 맥락을 파악할 수 없다는 것은, 그에 따른 적절한 처리를 하기가 어렵다는 것


## 그럼 어떤식으로 처리하면 좋을까 ?

**null 리턴**
- private 메서드와 같이 사용 범위가 제한적인 경우

**예외 발생**
- 참조값이 없는게 예외로 간주되어야하는 경우

**Optional**
- 이펙티브 자바를 참고해보면, null인게 예외인지 아닌지 등을 호출한 쪽에서 맥락에 따라 판단해야하는 경우 `Optional`이 괜찮은 선택일 수 있음 <br>
(CheckedException처럼 호출자에게 이 메서드를 호출할시 '리턴값이 없을 수 있음'을 명확하게 알릴 수 있기 때문에)

**빈 컬렉션**
- `new ArrayList<>();`, `Collections.emptyList();` 등
  - NPE가 발생하지 않는다. 이에 따라, 코드가 조금 더 깔끔해질 수 있다.

```java
List<Item> items = getItems();
// if (items != null && !items.isEmpty()) -> 이런 체크가 불필요
for (Item item : items) {
  ...
}
```

**null 오브젝트 패턴**
```java
public interface Result {
  void doSomething();
}
```

```java
public class RealResult implements Result {
  @Override
  public void doSomething() {
    System.out.println("Doing real work");
  }
}
```

```java
public class NullResult implements Result {
  @Override
  public void doSomething() {
    // do nothing
  }
}
```

```java
public Result findById(String id) {
  if (/* not found */) {
    return new NullResult();
  } else {
    return new RealResult();
  }
}
```

```java
Result result = findById("someId");
result.doSomething(); // null 체크 없이 안전하게 호출
```

