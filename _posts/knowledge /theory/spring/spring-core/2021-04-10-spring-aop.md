---
title: 스프링 AOP 배경지식 살펴보기
date: 2021-04-10 22:25:00 +0900
---


# 들어가기 전
---
스프링 컨테이너는 싱글톤 레지스트리다. 따라서 스프링 빈이 싱글톤이 되도록 보장해주어야 한다.
그런데 스프링이 자바 코드까지 어떻게 하기는 어렵다. 저 자바 코드를 보면 분명 3번 호출되어야 하는 것이 맞다.
그래서 스프링은 클래스의 바이트코드를 조작하는 라이브러리를 사용한다.
모든 비밀은 @Configuration 을 적용한 AppConfig 에 있다.

사실 AnnotationConfigApplicationContext 에 파라미터로 넘긴 값은 스프링 빈으로 등록된다. 그래서 AppConfig 도 스프링 빈이 된다.
AppConfig 스프링 빈을 조회해서 클래스 정보를 출력해보자.

```
bean = class hello.core.AppConfig$$EnhancerBySpringCGLIB$$bd479d70
```

CGLIB 가 뭐길래 이런게 가능한거지 ?! 알아보자

# Proxy
Proxy는 일종의 대리자 입니다
디자인 패턴중에서 Proxy 패턴을 들어본적이 있으신가요?

우리가 특정한 Interface를 노출시키지 않고, 외부로부터 감추고 싶을 때 사용하는 것이
바로 Proxy 패턴입니다.

그렇다면 Spring에서 지원하는 Proxy와 디자인 패턴에서의 Proxy 패턴은 유사할까요.?
정답은.. 아닙니다

일반적으로 Proxy는 실제 Target의 기능을 대신 수행하면서, 기능을 확장하거나 추가하는 실제 객체를 의미하고,
Proxy 패턴은 Target에 대한 기능을 확장하지는 않고, Client가 Target에 접근하는 방식을 변경해줍니다.

오히려 Proxy는 Template Method Pattern 과 비슷하다라고 할까요.?
그렇다면 왜 사용할까요?

Proxy를 사용하는 이유는 아주 간단합니다

OCP(Open - Closed Principle)을 지키기 위해서 사용합니다
개방 폐쇄 원칙(=OCP)란 소프트웨어는 확장에 대해서는 열려있어야 하고, 수정에 대해서는 닫혀있어야 한다 라는 원칙입니다

이제 Spring에서 근간이 되면 AOP에 대해서 알아보도록 할게요

# AOP (Aspect Oriented Programming)
---

필연적인 등장배경과 스프링이 그것을 도입한 이유, 이를 통해 얻을 수 있는 장점이 무엇인지 이해해야한다.

Spring 에서는 Proxy를 바탕으로 우리의 관심사를 추출하는 AOP 를 제공하고 있습니다

그럼 도대체 어떻게 관심사별로 추출할 수 있을까요?

바로 Proxy를 이용한 런타임 위빙(Runtime Weaving) 을 통해서 관심사를 추출할 수 있습니다.

![image](https://user-images.githubusercontent.com/64415489/131216417-b7f408b4-a6d1-4974-b117-be279f85e738.png)
출처 : https://huisam.tistory.com/entry/springAOP

여기서 Runtime Weaving 이란?

Weaving is the process of applying aspects to a target object to create a new, proxied object.
-> Weaving은 target 객체를 새로운 proxied 객체로 적용시키는 과정이다.

그래서 Runtime Weaving은?
Runtime시에 이러한 Weaving이 진행되는 방식이다.!

Spring AOP에서는 이러한 기능을 2가지 방법으로 구사하고 있는데요.

JDK Dynamic Proxy
CGlib Proxy


## JDK Dynamic Proxy
JDK 에서 제공하는 Dynamic Proxy는 1.3 버젼부터 생긴 기능이며,

Interface를 기반으로 Proxy를 생성해주는 방식입니다.!

그렇기 때문에 Interface를 강제화 한다는 단점이 있다는...

Dynamic Proxy는 Invocation Handler를 상속받아서 실체를 구현하게 되는데,

이 과정에서 특정 Object에 대해 Reflection을 사용하기 때문에 성능이 조금 떨어지는 크리티컬한 단점이 있습니다.

```java
import core.aop.pointcut.MethodMatcher;
import lombok.RequiredArgsConstructor;

import java.lang.reflect.InvocationHandler;
import java.lang.reflect.Method;

@RequiredArgsConstructor
public class UpperCaseHandler implements InvocationHandler {

    private final Car car;
    private final MethodMatcher methodMatcher;

    @Override
    public Object invoke(Object proxy, Method method, Object[] args) throws Throwable {
        final String methodName = (String) method.invoke(car, args);
        if (methodMatcher.matches(method)) {
            return methodName.toUpperCase();
        }
        return methodName;
    }
}
```

실제로 Invocation Handler를 상속받아서 구현한 예시인데요..
Car 라는 인터페이스를 상속받아서 의존성 주입을 해준 모습입니다.

여기서는 MethodMatcher라는 인터페이스도 같이 주입해준 모습인데요.

해당 인터페이스는 Method 를 선택적으로 Proxy화 하기 위해서, 의존성 주입으로 설정해 주었습니다.!
위 Invocation Handler는 invoke를 통해서 proxy 로직이 진행되는데요,

invoke 라는 메서드 내부 로직에 Reflection을 해야하는 아쉬움이 있습니다.

## CGlib Proxy
CGlib Proxy는 Enhancer를 바탕으로 Proxy를 구현하는 방식입니다
이 방식은 JDK Dynamic Proxy와는 다르게 Reflection을 사용하지 않고,
Extends(상속) 방식을 이용해서 Proxy화 할 메서드를 오버라이딩 하는 방식입니다

1. Proxy화를 진행할 Target Class를 생성
```java
public class CarTarget implements Car {
    @Override
    public String start(String name) {
        return "Car " + name + " started!";
    }

    @Override
    public String stop(String name) {
        return "Car " + name + " stopped!";
    }
}
```

2. start 메서드만 Proxy 화를 진행하고 싶은데요..
```java
import core.aop.pointcut.MethodMatcher;

import java.lang.reflect.Method;

public class StartMethodMatcher implements MethodMatcher {
    private static final String TALK_PREFIX = "start";

    @Override
    public boolean matches(Method method) {
        final String methodName = method.getName();

        return methodName.startsWith(TALK_PREFIX);
    }
}
```

3. 실제 Proxy로 핸들링할 Handler가 필요
- CGlib 에서는 이를 MethodInterceptor 라는 인터페이스로 정의되어 있습니다


# 비즈니스 로직과 그 이외의 관심사가 혼재된 코드

- 아래 코드처럼 비즈니스 로직을 담당하는 클래스에 비즈니스 로직과 트랜잭션 로직(그 이외의 관심사)이 섞여 있는 코드가 있다고 가정하자.
  - 즉, 실제 비즈니스 로직을 수행하는 `upgradeLevel(user);` 아래 위로 트랜잭션 경계를 설정하는 로직이 들어가 있다.
  - 두 로직은 서로 독립적이다.
```java
	public void upgradeLevels() {
		TransactionStatus status =
			this.transactionManager.getTransaction(new DefaultTransactionDefinition());
		try {
			List<User> users = userDao.getAll();
			for (User user : users) {
				if (canUpgradeLevel(user)) {
					upgradeLevel(user);
				}
			}
			this.transactionManager.commit(status);
		} catch (RuntimeException e) {
			this.transactionManager.rollback(status);
			throw e;
		}
	}
```

- 문제점
  - 비즈니스 로직이 주가 되어야할 클래스에 트랜잭션 관련된 코드가 더 많아진다.
  - 비즈니스 로직만 따로 테스트 하기 어렵다.

# 비즈니스 로직과 그 이외의 관심사 코드 분리하기
## 1. DI 활용
- UserSerivceTx에서 실제 비즈니스 로직을 담당하는 부분은 UserServiceImpl에게 위임
- 결과적으로 비즈니스 로직을 담당하는 UserServiceImpl에는 트랜잭션과 관련된 코드를 찾아볼 수 없다.
  - 독립적으로 비즈니스 로직만 테스트 하기에 용이하다.
- 한계점
  - 클라이언트가 UserServiceImpl을 바로 호출하게 되면 부가기능(트랜잭션 설정)이 적용되지 않는다.

<img src = "https://user-images.githubusercontent.com/64415489/131223219-da6c26dd-e7fd-4150-b014-b5c272094dc9.png" width="70%"/>

### Client (호출하는 코드)
```java
public void upgradeAllOrNothing() {
    UserServiceTx txUserService = new UserServiceTx();
	txUserService.setTransactionManager(transactionManager);
	txUserService.setUserService(new UserServiceImpl());

	userDao.deleteAll();
	for(User user : users) userDao.add(user);

	try {
		txUserService.upgradeLevels();
		fail("TestUserServiceException expected");
	}
	catch(TestUserServiceException e) {
	}

	checkLevelUpgraded(users.get(1), false);
}
```

### UserSerivceTx
```java
public class UserServiceTx implements UserService {
	UserService userService;
	PlatformTransactionManager transactionManager;

	public void setTransactionManager(
			PlatformTransactionManager transactionManager) {
		this.transactionManager = transactionManager;
	}

	public void setUserService(UserService userService) {
		this.userService = userService;
	}

	public void add(User user) {
		this.userService.add(user);
	}

	public void upgradeLevels() {
		TransactionStatus status = this.transactionManager
				.getTransaction(new DefaultTransactionDefinition());
		try {

			userService.upgradeLevels();

			this.transactionManager.commit(status);
		} catch (RuntimeException e) {
			this.transactionManager.rollback(status);
			throw e;
		}
	}
}
```

### UserServiceImpl
```java
public class UserServiceImpl implements UserService {
	public static final int MIN_LOGCOUNT_FOR_SILVER = 50;
	public static final int MIN_RECCOMEND_FOR_GOLD = 30;

	public void upgradeLevels() {
		List<User> users = userDao.getAll();
		for (User user : users) {
			if (canUpgradeLevel(user)) {
				upgradeLevel(user);
			}
		}
	}

	private boolean canUpgradeLevel(User user) {
		Level currentLevel = user.getLevel();
		switch(currentLevel) {
		case BASIC: return (user.getLogin() >= MIN_LOGCOUNT_FOR_SILVER);
		case SILVER: return (user.getRecommend() >= MIN_RECCOMEND_FOR_GOLD);
		case GOLD: return false;
		default: throw new IllegalArgumentException("Unknown Level: " + currentLevel);
		}
	}

	protected void upgradeLevel(User user) {
		user.upgradeLevel();
		userDao.update(user);
		sendUpgradeEMail(user);
	}

	public void add(User user) {
		if (user.getLevel() == null) user.setLevel(Level.BASIC);
		userDao.add(user);
	}
}
```

## 2. 프록시
- 부가기능은 마치 자신이 핵심 기능을 가진 클래스인 것처럼 꾸며서, 클라이언트가 자신을 거쳐서 핵심기능을 사용하도록
- Proxy : 대리인
  - 마치 자신이 클라이언트가 사용하려고 하는 실제 대상인 것처럼 위장해서 클라이언트의 요청을 받아준다.
  - 프록시를 통해 최종적으로 요청을 위임받아 처리하는 실제 오브젝트를 '타깃(target)' 또는 '실체(real object)'라고 부른다.
- 이를 가능하게 하려면, 클라이언트는 인터페이스를 통해서만 핵심 기능을 사용하게 하고, 부가기능도 같은 인터페이스를 구현한 뒤에 그 사이에 끼어들어야 한다.

<img src = "https://user-images.githubusercontent.com/64415489/131224765-eb291c4a-e50f-4ed3-83a5-4bbc6af5d267.png" width="70%"/>

- 한계점
  - 작성해야할 코드 양이 너무 많아질 수 있다.
    - 예를 들어, 트랜잭션 담당 데코레이터를 각 타깃별로 만들어줘야 한다면 `UserServiceTx`, `OrderServiceTx`, ... 등을 일일이 생성해줘야 하고,
    구현해야할 인터페이스 각각의 메서드에 부가 기능을 추가하고, 타깃 메서드에 실제 비즈니스 로직을 위임하는 코드도 작성해야 한다.

- 프록시는 사용 목적에 따라 두 가지로 구분할 수 있다.
  1. 타깃에 부가적인 기능을 부여하기 위한 프록시
  2. 클라이언트가 타깃에 접근하는 방법 제어를 위한 프록시

- 두 가지 모두 대리인 개념의 프록시를 두고 사용한다는 점은 동일하지만, 디자인 패턴에서는 다른 패턴으로 구분한다.

### 데코레이터 패턴
> 타깃에 부가적인 기능을 런타임시 다이내믹하게 부여하기 위해 프록시를 사용하는 패턴
> '다이내믹'하다는 의미는 컴파일 시점, 즉 코드상에서는 어떤 방법과 순서로 프록시와 타깃이 연결되어 사용되는지 알 수 없다는 뜻이다.

- 데코레이터
  - 마치 실제 내용물을 포장하고 꾸미듯, 부가적인 효과를 부여해줄 수 있기 때문이다.
  - 따라서, 프록시가 한 개 이상일 수 있다.
  - `InputStream is = new BufferedInputStream(new FileInputStream("a.txt"));`
    - BufferedInputStream : 데코레이터
    - FileInputStream : 타깃
- 프록시로서 동작하는 각 데코레이터는 위임하는 대상에도 인터페이스로 접근하기 때문에 자신이 최종 타깃으로 위임하는지,
다음 단계의 데코레이터 프록시로 위임하는지 알지 못한다.
  - 따라서 데코레이터의 다음 위임 대상은 인터페이스로 선언하고 생성자나 수정자 메서드를 통해 위임 대상을 외부에서 런타임 시에 주입받을 수 있도록 해야한다.
  ![image](https://user-images.githubusercontent.com/64415489/131225118-78a16b7b-5138-4487-8d3d-19b1f3556b74.png)
- 타깃의 코드, 클라이언트가 호출하는 방법을 변경하지 않은 채로 새로운 기능을 추가할 때 유용한 방법이다.

### 프록시 패턴
> '프록시'는 대리 역할을 맡은 오브젝트를 총칭한다면, '프록시 패턴'은 디자인 패턴으로써 타깃에 대한 클라이언트의 접근 방법을 제어하기 위해
> 프록시를 사용하는 경우 사용된다.

- 예를 들어, 타깃이 생성하기가 복잡하거나 당장 필요하지 않은 경우에는 꼭 필요한 시점까지 객체를 생성하지 않는게 좋다.
- 프록시를 활용하면 실제 타깃을 만드는 대신 타깃에 대한 레퍼런스를 클라이언트에게 전달할 수 있다.
  - 프록시의 메서드를 통해 타깃을 사용하려고 할 때, 프록시가 타깃을 생성하고 요청을 위임해준다.
- 타깃에 대한 접근권한을 제어하기 위해 사용할 수도 있다.
  - 프록시의 특정 메서드를 사용하려고 하면 접근이 불가능하다고 예외를 발생시키면 된다.
  - `Collections`의 `unmodifiableCollection()`을 통해 만들어지는 객체가 접근권한 제어용 프록시다.
    - 즉, Collection 객체의 프록시를 만들어서, `add()`나 `remove()` 같이 정보를 수정하는 메서드를 호출할 경우
    `UnsupportedOperationException` 예외가 발생하게 해준다.

## 3. 다이내믹 프록시


# 참고 자료
---
토비의 스프링
https://huisam.tistory.com/entry/springAOP
