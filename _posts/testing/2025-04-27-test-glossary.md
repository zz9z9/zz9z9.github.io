---
title: 테스트 - 테스트 관련 용어 익히기
date: 2025-04-28 00:25:00 +0900
categories: [지식 더하기, 이론]
tags: [Testing]
---

## 단위 테스트

## 통합 테스트

## 인수 테스트

### 테스트 더블
- xUnit Test Patterns의 저자인 제라드 메스자로스(Gerard Meszaros)가 만든 용어로 테스트를 진행하기 어려운 경우 이를 대신해 테스트를 진행할 수 있도록 만들어주는 객체를 말한다.
  - 영화 촬영 시 위험한 역할을 대신하는 스턴트 더블에서 비롯되었다.

- 테스트 더블은 크게 **Dummy, Fake, Stub, Spy, Mock**으로 나눈다.

=> http://martinfowler.com/articles/mocksArentStubs.html
요기도 함 보자

**Dummy**
- Dummy는 아무런 동작도 하지 않는다. 인스턴스화된 객체만 필요하고, 기능까지는 필요하지 않은 경우 Dummy를 사용한다.
- 주로 파라미터로 전달되기 위해 사용된다.

```java
public interface Logger {
    void log();
}
public class LoggerDummy implements Logger {
    @Override
    public void log() {

    }
}
```

**Fake**
- Fake는 실제 동작하는 구현을 가지고 있지만, 프로덕션에서는 사용되기 적합하지 않은 객체이다.
- 예를 들어 `LoginService` 가 실제 프로덕션에서는 `AccountDao`에 의존하여 데이터베이스를 사용하고 있다.
- 하지만 테스트코드에서는 데이터베이스 대신 HashMap 을 사용하는 FakeAccountDao 를 대신 LoginService 에 주입하여, 데이터베이스와 연결을 끊고 테스트할 수 있다.


**Stub**
- 미리 반환할 데이터가 정의되어 있으며, 메소드를 호출하였을 경우 그것을 그대로 반환하는 역할만 수행
- 테스트를 위해 프로그래밍된 내용에 대해서만 **준비된 결과를 제공**하는 객체
- Mockito 프레임워크도 Stub와 같은 역할을 해준다.

```java
public class StubUserRepository implements UserRepository {
    // ...
    @Override
    public User findById(long id) {
        return new User(id, "Test User");
    }
}
```

**Spy**
- 실체 객체를 부분적으로 Stubbing 하면서 동시에 약간의 정보를 기록하는 객체이다.
- 기록하는 정보에는 메소드 호출 여부, 메소드 호출 횟수 등이 포함된다.
- 기존 객체를 부분적으로 감시하거나 일부만 가짜로 바꾼다.
- 진짜 객체의 메서드를 호출한다.
- 필요하면 특정 메서드만 스텁(stub, 가짜 응답)할 수 있다.
- `when(spy.method()).thenReturn(value);`
  - method는 원래대로 동작하는데, 이 메서드만 바꿀 수 있다.

**Mock**
- 호출에 대한 기대를 명세할 수 있고, 그 명세 내용에 따라 동작하도록 프로그래밍된 객체이다.
- Mock 외의 것은 개발자가 임의로 코드를 사용하여 생성할 수 있지만, Mock은 Mocking 라이브러리에 의해 동적으로 생성된다.
- 또한 설정에 따라 Mock은 충분히 Dummy, Stub, Spy 처럼 동작할 수 있다. 즉, 가장 강력한 테스트 더블이라고 할 수 있을 것 같다.
- 객체의 행위를 가짜로 만들어서 정의된 대로만 동작하게 한다.
- 진짜 로직은 수행하지 않고, 정해진 반환값만 제공한다.
- 행위 검증(메서드 호출 여부)만 중점적으로 본다.
- `when(mock.method()).thenReturn(value);`
  - method가 호출돼도 실제 로직은 실행 안 되고 value만 준다.

- 테스트 대상을 SUT(System Under Test)라고하고, SUT가 의존하고 있는 구성요소를 DOC(Depended-on Component) 라고 하는데, 테스트 더블은 이 DOC와 동일한 API를 제공한다.

## Stub vs Mock vs Spy

| 구분       | Stub | Mock | Spy                                     |
|----------| ---- | ---- |-----------------------------------------|
| 정의       | 고정된 입력에 대해 미리 정해둔 출력을 주는 객체 | 메서드 호출 여부, 호출 순서 등을 검증하기 위한 객체 (행위 기반 테스트) | 실제 객체를 감시하고 필요하면 일부 메서드를 스텁처럼 바꾼 객체     |
| 목적       | 출력 조작("이 메서드 호출하면 무조건 이 값을 줘") | 행위 검증 + 출력 조작("이 메서드가 제대로 불렸나?"도 검증) | 부분 조작 + 감시("실제 메서드는 돌아가지만 필요하면 일부 조작")  |
| 실제 로직 실행 | 안 함 (미리 정의된 값만 반환) | 안 함 (대부분 가짜로 동작) | 기본적으로 실행함 (특정 메서드만 가짜로 덮어씀) |
| 검증 여부    | 없음 (return만 제공) | 있음 (메서드 호출했는지 확인 가능) | 있음 (Spy도 호출 여부 확인 가능) |
| 구현 도구    | 간단한 hand-made 객체, Mockito stub 기능 등 | Mockito mock 객체 | Mockito spy 객체 |

![Image](https://github.com/user-attachments/assets/e0b831c6-c1fc-4855-bd41-fc86aac7b5b7)
=> https://docs.microsoft.com/en-us/archive/msdn-magazine/2007/september/unit-testing-exploring-the-continuum-of-test-doubles

### 예시

**Stub**
> "로그인 서비스"는 그냥 무조건 "성공"을 반환하게 만든다.
> 진짜 인증 로직은 관심 없음. 그냥 결과만 고정시키는 것.

```java
when(authService.login(anyString(), anyString())).thenReturn(true);  // 무조건 로그인 성공
```

**Mock**
> 로그인 메서드가 호출됐는지 안됐는지를 검증하고 싶다. 어떤 파라미터로 몇 번 불렸는지도 관심 있다.

```java
verify(authService, times(1)).login("user", "password");
```

**Spy**
> 진짜 로그인 로직은 돌리는데, 특정 상황에서는 결과를 조작하고 싶다.
> 예를 들면, 아이디가 "test"일 때만 결과를 바꾼다든가.

```java
doReturn(true).when(authService).login("test", "password");
```

- Sociable Test (협동 테스트)
테스트 대상 유닛이 다른 유닛과 협동하는 관계라면 다른 유닛과 함께 테스트한다.
협동 테스트는 테스트 대상 유닛뿐만 아니라 협동하는 다른 유닛과 함께 테스트하므로 테스트 대상 유닛의 버그가 아닌 다른 유닛의 버그로 테스트 대상 유닛의 실패가 발생할 수 있다.
- Solitary Test (단독 테스트)
테스트 대상 유닛만 테스트한다.
단독 테스트는 테스트 대상 유닛만 테스트하기 때문에 다른 유닛과의 협동이 있다면 테스트 대역(Test double)을 이용한다.
이는 런던파(London school) 와 고전파(Classical school)의 견해에 따른 테스트 스타일과도 관련이 있는데요. 고전파는 협동 테스트를 선호하지만, 런던파는 단독테스트를 선호하는 성향이 있습니다.

## 테스트 커버리지
- 커버리지는 테스트 스위트가 운영 코드를 검증하는 코드 비율을 뜻하는데요. 지표로 표현되어 그런지 생각보다 많은 사람이 테스트 커버리지에 관해 오해하고 있습니다. 어떤 사람들은 테스트 커버리지 100%에 도달하는 것을 맹목적으로 쫓기도 하죠. 하지만 테스트 커버리지는 테스트 중 확인된 운영 코드의 비율을 나타낼 뿐 본질적으로는 테스트의 품질을 측정하는 단위가 아니라고 생각합니다.

따라서 커버리지가 높다고 유용한 테스트가 많이 작성되어 있다는 것을 보장할 순 없습니다.
즉, 커버리지는 테스트 지표로서 우리에게 훌륭한 피드백을 제공하지만, 테스트 스위트의 품질을 측정하는 데는 크게 도움이 되지 않습니다. 하지만 역설적으로 커버리지가 0%에 가까운 시스템은 코드 표준이나 테스트 수준에 대한 잠재적인 위험이 존재한다는 피드백 지표로 도움이 될 수 있습니다.

그래서 테스트 커버리지를 시스템의 테스트 품질에 대한 긍정 지표가 아닌 부정 지표로써 사용하기로 했습니다.커버리지를 통해 여러 도메인에 걸쳐 철저하게 테스트 된 고품질 코드가 얼마나 많이 존재하는지 확인하는 것이 아니라 커버리지가 생각한 수준보다 낮을 때 이 시스템의 테스트가 제대로 되지 않고 있다는 신호로서 받아들이겠다는 것입니다.

## 참고 자료
- https://hudi.blog/test-double/
- http://martinfowler.com/articles/mocksArentStubs.html
- https://techblog.woowahan.com/14874/
