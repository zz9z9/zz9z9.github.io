---
title: 스프링 AOP 프록시
date: 2024-01-19 22:25:00 +0900
---

프록시 기초 굳굳
=> https://www.baeldung.com/jdk-com-sun-proxy


# Spring AOP Proxy
> An object created by the AOP framework in order to implement the aspect contracts (advice method executions and so on). <br>
> **In the Spring Framework, an AOP proxy is a JDK dynamic proxy or a CGLIB proxy.**

## JDK dynamic proxy
- Spring AOP defaults to using standard JDK dynamic proxies for AOP proxies.
- **This enables any interface (or set of interfaces) to be proxied.**

## CGLIB proxy
- This is necessary to proxy classes rather than interfaces.
- **By default, CGLIB is used if a business object does not implement an interface.**
- If you want to force the use of CGLIB proxying (for example, to proxy every method defined for the target object, not only those implemented by its interfaces), you can do so.
- However, you should consider the following issues:
  - With CGLIB, `final` methods cannot be advised, as they cannot be overridden in runtime-generated subclasses.
  - As of Spring 4.0, the constructor of your proxied object is NOT called twice anymore, since the CGLIB proxy instance is created through Objenesis. Only if your JVM does not allow for constructor bypassing, you might see double invocations and corresponding debug log entries from Spring’s AOP support.

- To force the use of CGLIB proxies, set the value of the proxy-target-class attribute of the `<aop:config>` element to true, as follows:
```xml
<aop:config proxy-target-class="true">
	<!-- other beans defined here... -->
</aop:config>
```

- To force CGLIB proxying when you use the `@AspectJ` auto-proxy support, set the `proxy-target-class` attribute of the `<aop:aspectj-autoproxy>` element to true, as follows:
```xml
<aop:aspectj-autoproxy proxy-target-class="true"/>
```



## 구현해보기
---
title: Cglib(Code Generation Library) 살펴보기
date: 2024-03-05 20:00:00 +0900
categories: [Java]
tags: [Java, Cglib]
---

> 스프링 AOP Proxy를 살펴보다보니 크게 JdkDynamicAopProxy와 CglibAopProxy로 나뉘는데, Cglib의 원리는 무엇일까 궁금했다.

# Cglib ?
> It is a byte instrumentation library used in many Java frameworks such as Hibernate or Spring.
> The bytecode instrumentation allows manipulating or creating classes after the compilation phase of a program.

```xml
<dependency>
    <groupId>cglib</groupId>
    <artifactId>cglib</artifactId>
    <version>3.2.4</version>
</dependency>
```

## 원리 ?
- **Classes in Java are loaded dynamically at runtime.**
- **Cglib is using this feature of Java language to make it possible to add new classes to an already running Java program.**

- Hibernate uses cglib for generation of dynamic proxies. For example, it will not return full object stored in a database but it will return an instrumented version of stored class that lazily loads values from the database on demand.

- Popular mocking frameworks, like Mockito, use cglib for mocking methods. The mock is an instrumented class where methods are replaced by empty implementations.

### 에제
```java
public class PersonService {
    public String sayHello(String name) {
        return "Hello " + name;
    }

    public Integer lengthOfName(String name) {
        return name.length();
    }
}
```
```java
Enhancer enhancer = new Enhancer();
enhancer.setSuperclass(PersonService.class);
enhancer.setCallback((MethodInterceptor) (obj, method, args, proxy) -> {
    if (method.getDeclaringClass() != Object.class && method.getReturnType() == String.class) {
        return "Hello Tom!";
    } else {
        return proxy.invokeSuper(obj, args);
    }
});

PersonService proxy = (PersonService) enhancer.create();

assertEquals("Hello Tom!", proxy.sayHello(null));
int lengthOfName = proxy.lengthOfName("Mary");

assertEquals(4, lengthOfName);
```

### org.springframework.cglib.proxy.Enhancer
> [공식 문서](https://docs.spring.io/spring-framework/docs/current/javadoc-api/org/springframework/cglib/proxy/Enhancer.html)의 설명은 다음과 같다.

- 메서드 가로채기(interception)를 활성화하기 위해 동적 서브클래스를 생성합니다.
- 이 클래스는 JDK 1.3에 포함된 표준 동적 프록시(Dynamic Proxy) 지원을 대체하기 위해 시작되었지만 인터페이스 구현 외에도 프록시가 구체 클래스를 확장할 수 있도록 허용했습니다.
- 동적으로 생성된 하위 클래스는 상위 클래스의 `final`이 아닌 메서드를 재정의하고 사용자 정의 인터셉터 구현을 콜백하는 후크를 갖습니다.

- 원래의 가장 일반적인 콜백 유형은 `MethodInterceptor`입니다. 이는 AOP 용어로 "Around Advice"를 가능하게 합니다.
- 즉, "super" 메소드 호출 전후에 사용자 정의 코드를 호출할 수 있습니다.
- 또한 super 메서드를 호출하기 전에 인수를 수정하거나 전혀 호출하지 않을 수도 있습니다.

- `MethodInterceptor`는 메서드 interception 요구 사항을 충족할 만큼 충분히 일반적이지만 종종 과잉입니다.
- 단순성과 성능을 위해 LazyLoader와 같은 추가 특수 콜백 유형도 사용할 수 있습니다.
- 강화된 클래스(enhanced class)별로 단일 콜백이 사용되는 경우가 많지만 `CallbackFilter`를 사용하면 메서드별로 어떤 콜백이 사용되는지 제어할 수 있습니다.

## 스프링 코드 보기
- org.springframework.aop.framework.CglibAopProxy#getProxy(java.lang.ClassLoader)
  - 내부적으로 Enhancer 사용하는 것을 알 수 있다.
```java
	@Override
public Object getProxy(@Nullable ClassLoader classLoader) {
  if (logger.isTraceEnabled()) {
    logger.trace("Creating CGLIB proxy: " + this.advised.getTargetSource());
  }

  try {
    Class<?> rootClass = this.advised.getTargetClass();
    Assert.state(rootClass != null, "Target class must be available for creating a CGLIB proxy");

    Class<?> proxySuperClass = rootClass;
    if (rootClass.getName().contains(ClassUtils.CGLIB_CLASS_SEPARATOR)) {
      proxySuperClass = rootClass.getSuperclass();
      Class<?>[] additionalInterfaces = rootClass.getInterfaces();
      for (Class<?> additionalInterface : additionalInterfaces) {
        this.advised.addInterface(additionalInterface);
      }
    }

    // Validate the class, writing log messages as necessary.
    validateClassIfNecessary(proxySuperClass, classLoader);

    // Configure CGLIB Enhancer...
    Enhancer enhancer = createEnhancer();
    if (classLoader != null) {
      enhancer.setClassLoader(classLoader);
      if (classLoader instanceof SmartClassLoader &&
        ((SmartClassLoader) classLoader).isClassReloadable(proxySuperClass)) {
        enhancer.setUseCache(false);
      }
    }
    enhancer.setSuperclass(proxySuperClass);
    enhancer.setInterfaces(AopProxyUtils.completeProxiedInterfaces(this.advised));
    enhancer.setNamingPolicy(SpringNamingPolicy.INSTANCE);
    enhancer.setStrategy(new ClassLoaderAwareGeneratorStrategy(classLoader));

    Callback[] callbacks = getCallbacks(rootClass);
    Class<?>[] types = new Class<?>[callbacks.length];
    for (int x = 0; x < types.length; x++) {
      types[x] = callbacks[x].getClass();
    }
    // fixedInterceptorMap only populated at this point, after getCallbacks call above
    enhancer.setCallbackFilter(new ProxyCallbackFilter(
      this.advised.getConfigurationOnlyCopy(), this.fixedInterceptorMap, this.fixedInterceptorOffset));
    enhancer.setCallbackTypes(types);

    // Generate the proxy class and create a proxy instance.
    return createProxyClassAndInstance(enhancer, callbacks);
  }
  catch (CodeGenerationException | IllegalArgumentException ex) {
    throw new AopConfigException("Could not generate CGLIB subclass of " + this.advised.getTargetClass() +
      ": Common causes of this problem include using a final class or a non-visible class",
      ex);
  }
  catch (Throwable ex) {
    // TargetSource.getTarget() failed
    throw new AopConfigException("Unexpected AOP exception", ex);
  }
}
```


### CGlib
> Enhancer, MethodInterceptor

```java
public interface MyInterface {
    void doSomething();
}

public class MyInterfaceImpl implements MyInterface {
  @Override
  public void doSomething() {
    System.out.println("doSomething in target!");
  }
}
```

```java
import org.aopalliance.intercept.MethodInterceptor;
import org.aopalliance.intercept.MethodInvocation;

public class MyInterceptor implements MethodInterceptor {

    public Object invoke(MethodInvocation invocation) throws Throwable {
        System.out.println("Before method " + invocation.getMethod().getName());
        Object result = invocation.proceed();
        System.out.println("After method " + invocation.getMethod().getName());

        return result;
    }

}
```

```java
import org.springframework.aop.framework.ProxyFactory;

public class CglibProxyDemoApp {

    public static void main(String[] args) {
        MyInterface target = new MyInterfaceImpl();
        MyInterceptor interceptor = new MyInterceptor();
        ProxyFactory factory = new ProxyFactory(target);
        factory.addAdvice(interceptor);

        MyInterface proxy = (MyInterface) factory.getProxy();
        proxy.doSomething();
    }

}
```


## JdkDynamicProxy

### InvocationHandler
- `InvocationHandler`는 프록시 인스턴스의 invocation handler에 의해 구현되는 인터페이스입니다.
- 각 프록시 인스턴스에는 연관된 invocation handler가 있습니다.
- 프록시 인스턴스에서 메소드가 호출되면 메소드 호출이 인코딩되어 해당 invocation handler의 호출(invoke) 메소드로 전달됩니다.

- Dynamic proxies allow one single class with one single method to service multiple method calls to arbitrary classes with an arbitrary number of methods. A dynamic proxy can be thought of as a kind of Facade, but one that can pretend to be an implementation of any interface. Under the cover, it routes all method invocations to a single handler – the invoke() method.

- While it’s not a tool meant for everyday programming tasks, dynamic proxies can be quite useful for framework writers.
- It may also be used in those cases where concrete class implementations won’t be known until run-time.

### 기본

```java
public class DynamicProxyEx2App {

    public static void main(String[] args) {
        Map mapProxyInstance = (Map) Proxy.newProxyInstance(
                DynamicProxyEx2App.class.getClassLoader(), new Class[] { Map.class },
                new TimingDynamicInvocationHandler(new HashMap<>()));

        mapProxyInstance.put("hello", "world");

    }

}
```

```java
public class TimingDynamicInvocationHandler implements InvocationHandler {

    private static Logger LOGGER = LoggerFactory.getLogger(
            TimingDynamicInvocationHandler.class);

    private final Map<String, Method> methods = new HashMap<>();

    private Object target;

    public TimingDynamicInvocationHandler(Object target) {
        this.target = target;

        for(Method method: target.getClass().getDeclaredMethods()) {
            this.methods.put(method.getName(), method);
        }
    }

    @Override
    public Object invoke(Object proxy, Method method, Object[] args)
            throws Throwable {
        long start = System.nanoTime();
        Object result = methods.get(method.getName()).invoke(target, args);
        long elapsed = System.nanoTime() - start;

        LOGGER.info("Executing {} finished in {} ns", method.getName(), elapsed);

        return result;
    }

}
```

### JdkDynamicProxy 살펴보기
> InvocationHandler를 구현하고 있는 것을 볼 수 있다. 위에처럼 `Proxy.newProxyInstance` 활용하여 프록시 생성
- `org.springframework.aop.framework.JdkDynamicAopProxy#getProxy(java.lang.ClassLoader)`
```java
final class JdkDynamicAopProxy implements AopProxy, InvocationHandler, Serializable {
  ...

  @Override
  public Object getProxy(@Nullable ClassLoader classLoader) {
    if (logger.isTraceEnabled()) {
      logger.trace("Creating JDK dynamic proxy: " + this.advised.getTargetSource());
    }
    return Proxy.newProxyInstance(classLoader, this.proxiedInterfaces, this);
  }

  ...
}
```

### AopProxyFactory
- `org.springframework.aop.framework.DefaultAopProxyFactory#createAopProxy`
```java
public class DefaultAopProxyFactory implements AopProxyFactory, Serializable {

	private static final long serialVersionUID = 7930414337282325166L;

	@Override
	public AopProxy createAopProxy(AdvisedSupport config) throws AopConfigException {
		if (!NativeDetector.inNativeImage() &&
				(config.isOptimize() || config.isProxyTargetClass() || hasNoUserSuppliedProxyInterfaces(config))) {
			Class<?> targetClass = config.getTargetClass();
			if (targetClass == null) {
				throw new AopConfigException("TargetSource cannot determine target class: " +
						"Either an interface or a target is required for proxy creation.");
			}
			if (targetClass.isInterface() || Proxy.isProxyClass(targetClass) || AopProxyUtils.isLambda(targetClass)) {
				return new JdkDynamicAopProxy(config);
			}
			return new ObjenesisCglibAopProxy(config);
		}
		else {
			return new JdkDynamicAopProxy(config);
		}
	}

	/**
	 * Determine whether the supplied {@link AdvisedSupport} has only the
	 * {@link org.springframework.aop.SpringProxy} interface specified
	 * (or no proxy interfaces specified at all).
	 */
	private boolean hasNoUserSuppliedProxyInterfaces(AdvisedSupport config) {
		Class<?>[] ifcs = config.getProxiedInterfaces();
		return (ifcs.length == 0 || (ifcs.length == 1 && SpringProxy.class.isAssignableFrom(ifcs[0])));
	}

}
```


## 참고 자료
- https://docs.spring.io/spring-framework/reference/core/aop/introduction-proxies.html
- https://gmoon92.github.io/spring/aop/2019/04/20/jdk-dynamic-proxy-and-cglib.html => 비교 대박쓰
- https://docs.spring.io/spring-framework/reference/core/aop/proxying.html
- https://www.baeldung.com/cglib
- https://docs.spring.io/spring-framework/docs/current/javadoc-api/org/springframework/cglib/proxy/Enhancer.html
- https://www.baeldung.com/java-dynamic-proxies
