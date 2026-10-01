---
title: null 리턴은 왜 안티패턴일까 ?
date: 2024-02-20 10:25:00 +0900
---

> null이 안티 패턴이라는 얘기를 자주 듣고 관련 글도 접하게되었다.
> 크게 생각하지 않고 개발하던 부분이라, 어떤게 좋지 않을지, 어떤 상황에 사용할지 말지 생각해보자.

## 내가 언제 null 리턴했는지 생각해보기

### 1. 외부에 제공한 api
- 요청에 대해 리턴해줄 데이터가 없는 경우 (잘못된 요청, 서버 에러 등)
```json
{
  "code" : 1000,
  "successful" : false,
  "result" : null
}
```

### 2. 화면에 제공하는 값 객체에서 해당 값 없을때
```java
public class UserProfileView {
  private String name;
  private String age;
  private List<String> hobbies; // 없으면 null
  ...
}
```

### 3. 서비스 레이어 등에서 메서드 만들 때
```java
// UserService.java
public User find(String userId) {
  return userRepository.select(userId);
}
```

```java
// OrderService.java
public Order findOrderBy(String userId) {
  User user = userRepository.select(userId);
  if (user == null) {
     throw new IllegalArgumentException("아이디를 확인해주세요");
  }

  // doSomething ...
}
```

> 즉, 어떤 요청에 대한 결과로 `내어줄 값이 없음`에 대해 null로 처리했던 것 같다.

## null 리턴하면 뭐가 안좋을까 ?
- null이면 호출한 입장에서 빈 객체, 빈 배열 등을 바로 만들 수가 없다 ? (null인지 체크하는 로직이 항상 들어가야함)
- NPE 발생 가능성 ?
=> null일 때 예외 처리를 하면서 왜 null인지에 대한 부분이 없고 그냥 NPE가 발생하면, 왜 이 값이 null이 되었는지에 대해 추적하는 것도 비용이다.
=> 실수로 아래코드 짜도 컴파일 타임에 못잡음
```java
String s = null;
s = s.trim(); //throws NullPointerException
```

- 결과값 null로 내려 받는 입장에선 뭐가 안좋을까 ??
  - null 자체가 문제는 아닌 것 같고, 왜 이게 null인지에 대한 이유가 함께 리턴되는 code, message 같은데(외부 api 호출인 경우)에 들어있지 않으면 클라이언트 입장에서는 다시 호출을 해야할지, 그냥 넘겨야할지 등에 대한 판단을 할 수 없을 것 같다.
  - 왜 null인지 코드를 들어가서 확인해봐야 한다. => 생산성 저하될 수 있음

(토스 글보고 배움)
- **"왜" 해당 값이 없는지에 대한 부분을 표현할 수 없다. 즉 null이 리턴되기까지의 컨텍스트가 표현되지 않음**
=> 이로 인해 .. 세부 구현을 들여다보기 시작하는 순간 개발자의 생산성은 이미 떨어집니다.
=> 이런 문제를 만들지 않으려면 코드에 담긴 다양한 의미를 축약하거나 없애지 않고 자세히 풀어 코드에 녹여내면 됩니다
- 아래처럼하면 null인 경우 왜 null인지 굳이 UserRepository를 뒤져보지 않아도되는 장점이 있을 것 같고, 시스템에 동기화하는 로직을 수행할지, 월요일이 될때까지 기다릴지 등 선택할 수 있어서 좋을 것 같다.
- 반면, 시스템에서 해당 관련 정책이 변경될때 (ex : 화 -> 수) 이 메세지도 변경해야한다는 단점도 있긴 할 것 같다.

(https://medium.com/swlh/we-need-to-stop-using-null-heres-why-c56ff3ac72dd)
- The problem with things allowed to be null is that you need to check for their null case every time. For example, in Java, an empty check for a string always looks like this:
```java
String s = "hello";
if (s == null || s.length() == 0) {
   //do stuff
}
```
- your logic becomes polluted with multiple checks and if/then/else forks:


```kotlin
class UserRepository {
  fun findByName(name: String): User {
    val result: User? = db.getUserBy(name)
	  if (result == null) {
		throw IllegalStateException("""|
	      |인사관리 시스템과 동기화 되지 않은 유저의 이름을 입력한 경우 이 메시지를 볼 수 있습니다.
	      |매주 월->화 넘어가는 자정에 인사 관리 시스템과의 데이터 동기화가 수행되므로, 새로운 사람이 월요일이 아닌 다른 날짜에 입사하지 않았는지 확인하십시오.
	      |다음 주 월요일까지 기다리거나, 수동 동기화를 실행하면 문제가 해결될 수 있습니다.
	      |
	      |인사 관리 시스템과의 데이터 동기화 로직은 UserRepositorySync 클래스를 참고하십시오.
	      |문제가 된 name=[$name]
	      """.trimMargin())
	  }
      return result
  }
}
```

(https://www.quora.com/Is-it-a-bad-practice-to-use-null-in-Java)
- Returning or accepting null values in a public API method is evil. The resulting code is not self-explanatory as the user, if don't read the spec, does not which argument are nullable and which are not based on the method signature.

If instead the argument are an instance of a nullable type like the Java8 or Guava Optional, the method signature speak by itself.

Even worst is when a member of a Value class is null. It may exist across several application layer, and this nullable value need to be checked in any layer, causing a lot of boilerplate code, that will distract form the actual code logic.

It is also true that a private method that expect/return null does not cause to much problem as the context is contained.

(https://www.lucidchart.com/techblog/2015/08/31/the-worst-mistake-of-computer-science/)
Now suppose our program has a slow or resource-intensive way of finding out someone’s phone number—perhaps by contacting a web service.

To improve performance, we’ll use a local Store as a cache, mapping a person’s name to his phone number.

```
store = Store.new()
store.set('Bob', '801-555-5555')
store.get('Bob') # returns '801-555-5555', which is Bob’s number
```

store.get('Alice') # returns nil, since it does not have Alice
However, some people won’t have phone numbers (i.e. their phone number is nil). We’ll still cache that information, so we don’t have to repopulate it later.

```
store = Store.new()
store.set('Ted', nil) # Ted has no phone number
store.get('Ted') # returns nil, since Ted does not have a phone number
```

But now the meaning of our result is ambiguous! It could mean:

the person does not exist in the cache (Alice)
the person exists in the cache and does not have a phone number (Tom)
One circumstance requires an expensive recomputation, the other an instantaneous answer. But our code is insufficiently sophisticated to distinguish between these two.

## null 리턴이 적절한 경우 ?
- private 메서드 내에서 ?
- 적절하다기 보다는 만약 여러 클라이언트에서 호출하는데 리턴값이 없을때 클라이언트마다 처리해야되는게 다른 경우 ??
=> 클라이언트로부터 null일 때 default action 또는 value에 대한 부분을 인자로 넘겨받는다 ??

## null 리턴 대신 '값 없음'에 대해 어떻게 하면되나 ?


## null 원래 목적 ? (백만달러짜리 실수?)
- null의 근본적인 문제는 값으로 할당되면서 값이 아니라는 사실을 표현하려고 한다는 점이다.
### Null References: The Billion Dollar Mistake
=> https://www.infoq.com/presentations/Null-References-The-Billion-Dollar-Mistake-Tony-Hoare/


## 참고 자료
- 엘레강트 오브젝트
- [토스 기술블로그](https://toss.tech/article/engineering-note-2)
- https://medium.com/swlh/we-need-to-stop-using-null-heres-why-c56ff3ac72dd
- https://www.yegor256.com/2014/05/13/why-null-is-bad.html
- https://www.lucidchart.com/techblog/2015/08/31/the-worst-mistake-of-computer-science/
- 이펙티브 자바 3/E의 아이템 54


