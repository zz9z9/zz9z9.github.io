---
title: Spring - @Transactional 살펴보기 (1) - AOP Proxy
date: 2025-05-25 00:25:00 +0900
categories: [지식 더하기, 이론]
tags: [Spring]
---

## AOP Proxy
> 스프링 : [https://docs.spring.io/spring-framework/reference/core/aop/introduction-proxies.html](https://docs.spring.io/spring-framework/reference/core/aop/introduction-proxies.html) <br>
> 스프링 부트 : [https://docs.spring.vmware.com/spring-boot/docs/3.0.14/reference/htmlsingle/#features.aop](https://docs.spring.vmware.com/spring-boot/docs/3.0.14/reference/htmlsingle/#features.aop)

| 프레임워크                     | AOP 프록시 기본값    | 조건                                        | 설명                           |
| ------------------------- | -------------- | ----------------------------------------- | ---------------------------- |
| **Spring Framework**  | **JDK 동적 프록시** | 기본                                        | 인터페이스 기반이 권장되므로 JDK Proxy 선호 |
| **Spring Boot**           | **CGLIB**      | 기본 (`spring.aop.proxy-target-class=true`) | 실용성과 호환성 고려해서 CGLIB이 기본값     |

- Spring Boot 3.4.4 `additional-spring-configuration-metadata.json` 파일 확인해보기
  - `additional-spring-configuration-metadata.json` : Spring Boot의 application.properties / application.yml 자동완성 기능을 지원하기 위한 메타데이터 파일

```json
{
  "name": "spring.aop.proxy-target-class",
  "type": "java.lang.Boolean",
  "description": "Whether subclass-based (CGLIB) proxies are to be created (true), as opposed to standard Java interface-based proxies (false).",
  "defaultValue": true
}
```

**Spring Framework**
- Spring의 철학은 "인터페이스 기반 프로그래밍"을 권장
- 따라서 프록시도 **JDK 동적 프록시 (인터페이스 기반)**을 기본으로 선택
- 클래스에 대해 프록시를 만들려면 `proxyTargetClass = true` 명시적으로 설정해야 함

**Spring Boot**
>  "편의성과 일관성"을 중요시함

- 많은 개발자들이 인터페이스 없이도 AOP 사용을 원함
- 특히 @Transactional, @Async, @Scheduled 같은 어노테이션 기반 기능은 클래스에 붙는 경우가 많음
- 그래서 Spring Boot는 자동 설정으로 CGLIB을 기본으로 사용하도록 설정함


### Cglib (Byte Code Generation Library)
- [github repo](https://github.com/cglib/cglib)에 적힌 설명을 보면 다음과 같다.
> Byte Code Generation Library is high level API to generate and transform Java byte code.
> It is used by AOP, testing, data access frameworks to generate dynamic proxy objects and intercept field access.

> **바이트코드 생성 라이브러리(Byte Code Generation Library)**는  Java 바이트코드를 생성하고 변형하기 위한 고수준 API입니다.
> 이 라이브러리는 AOP(관점 지향 프로그래밍), 테스트, 데이터 접근 프레임워크 등에서 동적 프록시 객체를 생성하거나 필드 접근을 가로채기 위해 사용됩니다.

|              | CGLIB 라이브러리                                   | Spring 내장 CGLIB                            |
| -------------- |-----------------------------------------------| ------------------------------------------ |
| 클래스 경로         | `net.sf.cglib.proxy.Enhancer`                 | `org.springframework.cglib.proxy.Enhancer` |
| 소스             | [cglib GitHub](https://github.com/cglib/cglib) | Spring이 자체적으로 재포장                          |

**왜 Spring은 CGLIB을 내장시켰나 ?**
- 라이브러리 충돌 방지
  - 예전엔 다른 라이브러리도 cglib을 사용했는데, 버전 충돌이 자주 발생
  - Spring은 이를 피하기 위해 패키지를 변경해서 자체 포함 (shading)
- 경량 의존성 구성
  - Spring Boot 사용 시 spring-core 하나로 충분히 동작
  - 개발자가 cglib를 별도로 추가할 필요 없음
- 일관성 보장
  - Spring AOP, ProxyFactory, @Transactional 등 내부 동작이 cglib에 크게 의존
  - 버전 변화나 API 변경의 영향을 줄이기 위해 `org.springframework.cglib.*`로 고정

## Cglib AOP Proxy 살펴보기

> Controller에서 보면 구현체가 `UserService$$SpringCGLIB$$`인 것을 확인할 수 있다.

![image](/assets/img/transactional-proxy-img1.png)

```java
@Service
@RequiredArgsConstructor
public class UserService {

    private final UserRepository userRepository;
    private final UserHistoryRepository userHistoryRepository;

    public List<User> getAllUsers() {
        return userRepository.findAll();
    }

    @Transactional
    public User create(User user) {
        userRepository.save(user);
        userHistoryRepository.save(UserHistory.from(user));

        return user;
    }

}
```

**어디서 생성하는걸까 ?**
```java
// org.springframework.aop.framework.CglibAopProxy#buildProxy
private Object buildProxy(@Nullable ClassLoader classLoader, boolean classOnly) {
  if (logger.isTraceEnabled()) {
    logger.trace("Creating CGLIB proxy: " + String.valueOf(this.advised.getTargetSource()));
  }

  try {
    ...

    this.validateClassIfNecessary(proxySuperClass, classLoader);
    Enhancer enhancer = this.createEnhancer();

    ...

    enhancer.setSuperclass(proxySuperClass);
    enhancer.setInterfaces(AopProxyUtils.completeProxiedInterfaces(this.advised));
    enhancer.setNamingPolicy(SpringNamingPolicy.INSTANCE);
    enhancer.setAttemptLoad(true);
    enhancer.setStrategy(KotlinDetector.isKotlinType(proxySuperClass) ? new ClassLoaderAwareGeneratorStrategy(classLoader) : new ClassLoaderAwareGeneratorStrategy(classLoader, undeclaredThrowableStrategy));
    Callback[] callbacks = this.getCallbacks(rootClass);
    Class<?>[] types = new Class[callbacks.length];

    for(x = 0; x < types.length; ++x) {
      types[x] = callbacks[x].getClass();
    }

    ProxyCallbackFilter filter = new ProxyCallbackFilter(this.advised.getConfigurationOnlyCopy(), this.fixedInterceptorMap, this.fixedInterceptorOffset);
    enhancer.setCallbackFilter(filter);
    enhancer.setCallbackTypes(types);

    Object var22;
    try {
      var22 = classOnly ? this.createProxyClass(enhancer) : this.createProxyClassAndInstance(enhancer, callbacks);
    } finally {
      filter.advised.reduceToAdvisorKey();
    }

    return var22;
  }

  ...
}
```

### Enhancer
> 위 코드에서 보면, `Enhancer`가 프록시 생성에서 중요한 역할을 역할을 하는 것처럼 보인다.
> org.springframework.cglib.proxy.Enhancer (CGLIB의 핵심 클래스)

- CGLIB은 인터페이스가 아닌 클래스 자체를 상속하여 프록시를 만들 때 사용됨
- 이때 프록시 클래스를 만드는 역할을 담당하는 것이 `Enhancer`. **즉, CGLIB 프록시는 항상 Enhancer를 통해 생성됨**
  - Enhancer는 내부적으로 ASM을 사용해서 프록시 클래스를 위한 바이트코드를 생성
  - 이 바이트코드는 JVM의 `defineClass()`를 통해 메모리에 로드됨

| 기능                                  | 설명                           |
| ----------------------------------- | ---------------------------- |
| `setSuperclass(Class)`              | 어떤 클래스를 상속할지 지정 (프록시 대상 클래스) |
| `setCallbacks(Callback[])`          | 메서드 호출 시 실행할 인터셉터 설정         |
| `setCallbackFilter(CallbackFilter)` | 어떤 메서드에 어떤 Callback을 적용할지 결정 |
| `create()`                          | 실제로 프록시 클래스를 생성하고 인스턴스화      |


```java
// org.springframework.cglib.proxy.Enhancer
public void setCallback(final Callback callback) {
    this.setCallbacks(new Callback[]{callback});
}

public void setCallbacks(Callback[] callbacks) {
    if (callbacks != null && callbacks.length == 0) {
        throw new IllegalArgumentException("Array cannot be empty");
    } else {
        this.callbacks = callbacks;
    }
}
```

```java
// org.springframework.cglib.proxy.MethodInterceptor
public interface MethodInterceptor extends Callback {
    Object intercept(Object obj, Method method, Object[] args, MethodProxy proxy) throws Throwable;
}
```

**예제**
```java
public class TempInterceptor implements MethodInterceptor {

    @Override
    public Object intercept(Object obj, Method method, Object[] args, MethodProxy proxy) throws Throwable {
        System.out.println("Before method: " + method.getName());
        Object result = proxy.invokeSuper(obj, args); // 원본 메서드 호출
        System.out.println("After method: " + method.getName());
        return result;
    }

}
```

```java
import org.springframework.cglib.proxy.Enhancer;

public class Main {

    public static void main(String[] args) {
        Enhancer enhancer = new Enhancer();
        enhancer.setSuperclass(TempService.class); // 원본 클래스 지정
        enhancer.setCallback(new TempInterceptor()); // 인터셉터 지정

        // 프록시 인스턴스 생성
        TempService proxy = (TempService) enhancer.create(); // TempService$$EnhancerByCGLIB$$

        // 프록시 메서드 호출 (intercept → invokeSuper → 원본 호출)
        proxy.hello("CGLIB");
    }

}
```

- 결과
```
Before method: hello
Hello, CGLIB
After method: hello
```

- final 클래스는 프록시 생성 안됨 (상속을 못하기 때문에)
```
Caused by: org.springframework.aop.framework.AopConfigException: Could not generate CGLIB subclass of class ... : Common causes of this problem include using a final class or a non-visible class
```


## @Transactional로 인해 생성된 프록시 객체에는 어떤 Interceptor가 세팅될까 ?

![image](/assets/img/transactional-proxy-img2.png)

**DynamicAdvisedInterceptor**
- 실제 프록시 메서드 실행 시 AOP advice를 연결하는 핵심 인터셉터
- `DynamicAdvisedInterceptor#intercept()`는 프록시된 메서드가 호출될 때, 실제 메서드 호출 전 이 메서드가 먼저 실행됨

![image](/assets/img/transactional-proxy-img3.png)

- 실제 호출흐름

![image](/assets/img/transactional-proxy-img4.png)

※ 참고 : AOP 관련 용어
- Advice : 실제로 실행되는 부가 기능 로직 (예: 로깅, 트랜잭션 시작/커밋, 보안 체크 등)
- Pointcut : 어디에 Advice를 적용할지 지정. (예: com.example.service.*.*(..)에 있는 모든 메서드)
- Advisor : Pointcut + Advice의 묶음. 즉, 실행 위치 + 실행할 로직을 함께 보유하는 AOP 구성 단위
- JoinPoint: 애플리케이션 실행 중에 AOP로 가로챌 수 있는 모든 지점 (Spring AOP에서는 오직 메서드 실행만 해당)

### TransactionInterceptor, TransactionAspectSupport

```java
// org.springframework.transaction.interceptor.TransactionInterceptor
public class TransactionInterceptor extends TransactionAspectSupport implements MethodInterceptor, Serializable {
  public TransactionInterceptor() {
  }

  public TransactionInterceptor(TransactionManager ptm, TransactionAttributeSource tas) {
    this.setTransactionManager(ptm);
    this.setTransactionAttributeSource(tas);
  }

  ...

  @Nullable
  public Object invoke(MethodInvocation invocation) throws Throwable {
    Class<?> targetClass = invocation.getThis() != null ? AopUtils.getTargetClass(invocation.getThis()) : null;
    Method var10001 = invocation.getMethod();
    Objects.requireNonNull(invocation);
    return this.invokeWithinTransaction(var10001, targetClass, invocation::proceed);
  }

  ...

}
```

```java
// org.springframework.transaction.interceptor.TransactionAspectSupport#invokeWithinTransaction
@Nullable
protected Object invokeWithinTransaction(Method method, @Nullable Class<?> targetClass, final InvocationCallback invocation) throws Throwable {
  TransactionAttributeSource tas = this.getTransactionAttributeSource();
  TransactionAttribute txAttr = tas != null ? tas.getTransactionAttribute(method, targetClass) : null;
  TransactionManager tm = this.determineTransactionManager(txAttr, targetClass);
  if (this.reactiveAdapterRegistry != null && tm instanceof ReactiveTransactionManager rtm) {
    ...
  } else {
    PlatformTransactionManager ptm = this.asPlatformTransactionManager(tm);
    String joinpointIdentification = this.methodIdentification(method, targetClass, txAttr);
    if (txAttr != null && ptm instanceof CallbackPreferringPlatformTransactionManager cpptm) {
      ...
    } else {
      TransactionInfo txInfo = this.createTransactionIfNecessary(ptm, txAttr, joinpointIdentification);

      Object retVal;
      try {
        retVal = invocation.proceedWithInvocation();
      } catch (Throwable var23) {
        this.completeTransactionAfterThrowing(txInfo, var23);
        throw var23;
      } finally {
        this.cleanupTransactionInfo(txInfo);
      }

      if (retVal != null && txAttr != null) {
        TransactionStatus status = txInfo.getTransactionStatus();
        if (status != null) {
          ...
        }
      }

      this.commitTransactionAfterReturning(txInfo);
      return retVal;
    }
  }
}
```
