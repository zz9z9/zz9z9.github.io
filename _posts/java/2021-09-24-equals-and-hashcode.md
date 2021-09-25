---
title: 왜 equals()와 hashCode()는 함께 오버라이딩 해야할까 ?
date: 2021-09-24 22:25:00 +0900
categories: [Java]
tags: [Java, Equals, Hashcode]
---

# 들어가기 전
---
실무에서는 `equals()`, `hashCode()` 메서드를 오버라이드 할 일이 별로 없었던 것 같다. 하지만 몇 달 전 간단한 웹 서버를 만들어보는 토이 프로젝트를 진행하던 중, 클라이언트로부터 받은 요청을 유틸 클래스의 메서드를 사용해서 `HttpRequest` 객체를 만드는 부분에 대한 테스트 코드를 작성했는데 원하는 결과가 나오지 않았다.객체간의 비교를 수행했는데 `equals()`가 오버라이드 되지 않아 발생했던 문제였다. 그런데 `equals()`를 오버라이드하면 `hashCode()`도 반드시 함께 오버라이드 해야한다고 한다. 왜 그래야하는 것인지 살펴보자.
<br><br>
**※ 작성했던 테스트 코드**
```java
@Test
public void getHttpRequest() throws Exception {
    Map<String, HttpRequest> requests = new HashMap<>();
    String request1 = "GET /index.html HTTP/1.1";
    String request2 = "POST /user/create HTTP/1.1";
    requests.put(request1, new HttpRequest(GET, "/index.html"));
    requests.put(request2, new HttpRequest(POST, "/user/create"));

    for (String req : requests.keySet()) {
        HttpRequest answer = requests.get(req);
        HttpRequest getObj = HttpRequestUtils.getHttpRequest(new ByteArrayInputStream(req.getBytes()));

        assertThat(getObj, is(answer)); // equals 오버라이드 전 원하는 결과가 나오지 않았음
    }
}
```

# equals()
---
> Object 클래스에서의 `equals()` 메서드는 기본적으로 '==' 연산자를 통해 메모리 주소 비교(동일성 비교)를 한다.

```java
public boolean equals(Object obj) {
    return (this == obj);
}
```

- equals 메소드는 null이 아닌 객체에 대해 아래의 등가 관계가 성립되어야 한다.
  - reflexive : `x.equals(x)`는 항상 성립한다.
  - symmetric : `x.equals(y)`와 `y.equals(x)`는 동일한 결과를 반환한다.
  - transitive : `x.equals(y)`가 성립하면 `y.equals(z)`도 성립한다.
  - consistent : `equals()`의 값은 `equals()`에 포함된 속성이 변경되는 경우에만 변경되어야 한다.

## 위 규칙을 위반하는 예시(`x.equals(y)!=y.equals(x)` 인 경우)

```java
class Money {
    int amount;
    String currencyCode;

    @Override
    public boolean equals(Object o) {
        if (o == this)
            return true;
        if (!(o instanceof Money))
            return false;
        Money other = (Money)o;
        boolean currencyCodeEquals = (this.currencyCode == null && other.currencyCode == null)
          || (this.currencyCode != null && this.currencyCode.equals(other.currencyCode));
        return this.amount == other.amount && currencyCodeEquals;
    }
}
```

```java
class WrongVoucher extends Money {

    private String store;

    @Override
    public boolean equals(Object o) {
        if (o == this)
            return true;
        if (!(o instanceof WrongVoucher))
            return false;
        WrongVoucher other = (WrongVoucher)o;
        boolean currencyCodeEquals = (this.currencyCode == null && other.currencyCode == null)
          || (this.currencyCode != null && this.currencyCode.equals(other.currencyCode));
        boolean storeEquals = (this.store == null && other.store == null)
          || (this.store != null && this.store.equals(other.store));
        return this.amount == other.amount && currencyCodeEquals && storeEquals;
    }
}
```

```java
Money cash = new Money(42, "USD");
WrongVoucher voucher = new WrongVoucher(42, "USD", "Amazon");

voucher.equals(cash) => false // As expected.
cash.equals(voucher) => true // That's wrong.
```

## 동등성(equality)과 동일성(identity)
> 실생활의 예를 생각해본다면, 같은 날 입대한 두 군인의 경우 '동등한' 훈련병의 입장이라고 생각할 수 있다. <br>
> 하지만, 두 훈련병은 각각 다른 사람이기에 '동일'하진 않다.

- 동등성(equality)
  - 두 객체가 동일한 상태(속성)를 포함하는지 여부

- 동일성(identity)
  - 두 객체가 동일한 메모리 주소를 공유하는지 여부

- 두 객체가 동일하면 동등하지만, 동등하다고 해서 동일하지는 않다.

# hashCode()
---
> 객체에 대한 해시 코드 값을 반환한다. 이 값은 해시 테이블을 사용할 때 주어진 키에 대한 해시 값으로 사용된다.
> 이를 활용해 데이터에 효율적으로 접근하기 위해, 해당 값을 사용하여 데이터를 저장한다.

- `hashCode()` 메서드는 가상 머신에 의해 native operation으로 구현된다. `hashCode()` 값은 (32비트 아키텍처에서) 메모리 참조 또는 (64비트 아키텍처에서) 메모리 참조에 대한 modulo 32 표현을 반환하는 것으로 구현되는 경우가 많다.


```java
public native int hashCode();
```

- `hashCode()`가 준수해야 할 사항은 다음과 같다.
  - internal consistency : `hashCode()`의 값은 `equals()`에서 비교하는 속성이 변경되는 경우에만 변경될 수 있다.
  - equals consistency : `x.equals(y)`이면 x,y의 `hashCode()`는 동일한 값을 반환해야 한다.
  - collisions : `x.equals(y)`가 성립하지 않더라도 x,y의 `hashCode()`는 동일한 값을 반환할 수도 있다.


## equals()와 hashCode()를 함께 오버라이드 해야하는 이유
- `hashCode()`가 준수해야 할 사항의 두 번째 항목을 주목해보자. 만약, 어떤 클래스에서 `equals()` 메서드만 오버라이드 되었다면 `hashCode()`의 경우엔 메모리 주소에 기반한 값이 나오기 때문에 `x.equals(y)`가 성립하더라도 x,y의 `hashCode()` 값은 다를 수 있다.

***이런 상황으로 인해 발생되는 문제는 ?*** <br>
  ***→ 해시맵을 사용할 때 의도치 않은 결과를 얻게된다.***

```java
class Team {
    String city;
    String department;

    public Team(String city, String department) {
        this.city = city;
        this.department = department;
    }

    @Override
    public final boolean equals(Object o) {
        if (o == this)
            return true;
        if (!(o instanceof Team))
            return false;
        Team other = (Team) o;
        boolean isSameCity = (this.city == null && other.city == null)
                || (this.city != null && this.city.equals(other.city));
        boolean isSameDept = (this.department == null && other.department == null)
                || (this.department != null && this.department.equals(other.department));
        return isSameCity && isSameDept;
    }
}
```

```java
Map<Team,String> leaders = new HashMap<>();
leaders.put(new Team("New York", "development"), "Anne");
leaders.put(new Team("Boston", "development"), "Brian");
leaders.put(new Team("Boston", "marketing"), "Charlie");

Team myTeam = new Team("New York", "development");
String myTeamLeader = leaders.get(myTeam); // "Anne"를 기대하지만 결과는 null이 나온다.
```

# equals(), hashCode() 작성하기
---
> 일반적으로 직접 일일이 작성하진 않고, IDE의 자동완성이나 Lombok 또는 Java7 부터 도입된 java.util 패키지의 Objects 클래스의 메서드를 활용한다.

## IntelliJ Default

```java
class Team {
    String city;
    String department;

    public Team(String city, String department) {
        this.city = city;
        this.department = department;
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;

        Team team = (Team) o;

        if (city != null ? !city.equals(team.city) : team.city != null) return false;
        return department != null ? department.equals(team.department) : team.department == null;
    }

    @Override
    public int hashCode() {
        int result = city != null ? city.hashCode() : 0;
        result = 31 * result + (department != null ? department.hashCode() : 0);
        return result;
    }
}
```

## Objects 유틸 활용

```java
import java.util.Objects;

class Team {
    String city;
    String department;

    public Team(String city, String department) {
        this.city = city;
        this.department = department;
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;
        Team team = (Team) o;
        return Objects.equals(city, team.city) &&
                Objects.equals(department, team.department);
    }

    @Override
    public int hashCode() {
        return Objects.hash(city, department);
    }
}
```

## Lombok 활용

```java
import lombok.EqualsAndHashCode;

@EqualsAndHashCode
class Team {
    String city;
    String department;

    public Team(String city, String department) {
        this.city = city;
        this.department = department;
    }
}
```

# 참고 자료
---
- [https://docs.oracle.com/javase/7/docs/api/java/lang/Object.html#hashCode()](https://docs.oracle.com/javase/7/docs/api/java/lang/Object.html#hashCode())
- [https://stackoverflow.com/questions/1692863/what-is-the-difference-between-identity-and-equality-in-oop](https://stackoverflow.com/questions/1692863/what-is-the-difference-between-identity-and-equality-in-oop)
- [https://www.baeldung.com/java-equals-hashcode-contracts](https://www.baeldung.com/java-equals-hashcode-contracts)
- [https://www.javacodegeeks.com/2016/03/equality-vs-identity.html](https://www.javacodegeeks.com/2016/03/equality-vs-identity.html)
- [https://www.baeldung.com/java-hashcode](https://www.baeldung.com/java-hashcode)
