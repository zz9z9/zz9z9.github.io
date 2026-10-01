---
title: 스프링 @Transactional 동작 원리 살펴보기
date: 2024-01-17 20:25:00 +0900
---

- Spring Framework의 선언적 트랜잭션(@Transactional)에서 이해해야 할 가장 중요한 개념은 **AOP 프록시**를 통해 활성화되고 **트랜잭션 advice**가 메타데이터에 의해 구동된다는 것입니다.
- **AOP와 트랜잭션 메타데이터의 조합은 메소드 호출을 중심으로 트랜잭션을 구동하기 위해 적절한 `TransactionManager` 구현과 함께 `TransactionInterceptor`를 사용하는 AOP 프록시**를 생성합니다.

![image](https://github.com/zz9z9/zz9z9.github.io/assets/64415489/81c89fa5-d7d7-4520-9fbf-a314101bae42)


- TransactionManager, TransactionTemplate 사용 예시
=> https://www.baeldung.com/spring-programmatic-transaction-management

# org.springframework.transaction.TransactionManager
> Marker interface for Spring transaction manager implementations,
either traditional or reactive.

## org.springframework.transaction.PlatformTransactionManager
```java
public interface PlatformTransactionManager extends TransactionManager {

	TransactionStatus getTransaction(@Nullable TransactionDefinition definition)
			throws TransactionException;

	void commit(TransactionStatus status) throws TransactionException;

	void rollback(TransactionStatus status) throws TransactionException;

}
```

- 이것은 Spring의 명령형 트랜잭션 인프라의 핵심 인터페이스입니다.
- 애플리케이션은 이를 직접 사용할 수 있지만 기본적으로 API로 사용되는 것은 아닙니다. 일반적으로 애플리케이션은 AOP를 통해 `TransactionTemplate` 또는 `선언적 트랜잭션 경계 설정(declarative transaction demarcation) : @Transactional`을 사용하여 작동합니다.

- 구현 클래스의 경우 정의된 전파 동작을 사전 구현하고 트랜잭션 동기화 처리를 처리하는 제공된 `AbstractPlatformTransactionManager` 클래스에서 파생하는 것이 좋습니다.
- 하위 클래스는 기본 트랜잭션의 특정 상태(예: begin, suspend, resume, commit)에 대한 템플릿 메서드를 구현해야 합니다.

- 이 전략 인터페이스의 전형적인 구현은 `JtaTransactionManager`입니다.
- 그러나 일반적인 단일 리소스 시나리오에서는 Spring의 특정 트랜잭션 관리자가 사용됩니다. `JDBC`, `JPA`, `JMS`가 선호됩니다.

## org.springframework.transaction.support.TransactionTemplate
- Template class that simplifies programmatic transaction demarcation and transaction exception handling.
  The central method is execute(org.springframework.transaction.support.TransactionCallback<T>), supporting transactional code that implements the TransactionCallback interface.
- This template handles the transaction lifecycle and possible exceptions such that neither the TransactionCallback implementation nor the calling code needs to explicitly handle transactions.

Typical usage: Allows for writing low-level data access objects that use resources such as JDBC DataSources but are not transaction-aware themselves. Instead, they can implicitly participate in transactions handled by higher-level application services utilizing this class, making calls to the low-level services via an inner-class callback object.

Can be used within a service implementation via direct instantiation with a transaction manager reference, or get prepared in an application context and passed to services as bean reference. Note: The transaction manager should always be configured as bean in the application context: in the first case given to the service directly, in the second case given to the prepared template.

Supports setting the propagation behavior and the isolation level by name, for convenient configuration in context definitions.

# org.springframework.transaction.interceptor.TransactionInterceptor
- 공통 Spring 트랜잭션 인프라(PlatformTransactionManager/ ReactiveTransactionManager)를 사용하는 선언적 트랜잭션 관리를 위한 AOP Alliance `MethodInterceptor`
- Spring의 기본 트랜잭션 API와의 통합을 포함하는 `TransactionAspectSupport` 클래스에서 파생됩니다.
- TransactionInterceptor는 `TransactionAspectSupport.invokeWithinTransaction`과 같은 관련 슈퍼클래스 메서드를 올바른 순서로 호출합니다.
- TransactionInterceptors are thread-safe.

## org.springframework.transaction.interceptor.TransactionAspectSupport
- Base class for transactional aspects, such as the `TransactionInterceptor` or an AspectJ aspect.
- This enables the underlying Spring transaction infrastructure to be used easily to implement an aspect for any aspect system.
- **Subclasses(`TransactionInterceptor`와 같은) are responsible for calling methods in this class in the correct order.**
- If no transaction name has been specified in the TransactionAttribute, the exposed name will be the fully-qualified class name + "." + method name (by default).
- Uses the Strategy design pattern. A PlatformTransactionManager or ReactiveTransactionManager implementation will perform the actual transaction management, and a TransactionAttributeSource (e.g. annotation-based) is used for determining transaction definitions for a particular class or method.
- A transaction aspect is serializable if its TransactionManager and TransactionAttributeSource are serializable.



# @Transactional
- `@Transactional` commonly works with thread-bound transactions managed by `PlatformTransactionManager`, exposing a transaction to all data access operations within the current execution thread.
- Note: This does not propagate to newly started threads within the method.

- The @Transactional annotation is typically used on methods with public visibility.
- As of 6.0, protected or package-visible methods can also be made transactional for class-based proxies by default.
- Note that transactional methods in interface-based proxies must always be public and defined in the proxied interface.
- For both kinds of proxies, only external method calls coming in through the proxy are intercepted.

## @Transactional 선언한 Bean 살펴보기
```java
public class DemoApp {

    public static void main(String[] args) {
        ApplicationContext ctx = new AnnotationConfigApplicationContext(AppConfig.class);
        MemberQueryService memberQueryService = (MemberQueryService) ctx.getBean("memberQueryService");

        memberQueryService.doSomething();
    }
}
```

```java
public class MybatisSpringMemberQueryServiceImpl implements MemberQueryService {

    ...

    @Override
    @Transactional
    public void doSomething() { ... }
```

```java
@Bean
public MemberQueryService memberQueryService() {
    return new MybatisSpringMemberQueryServiceImpl(sqlSession());
}
```

- 실제 `MemberQueryService` 인스턴스 : `java.lang.reflect.Proxy`
- 인스턴스 변수 InvocationHandler h; => `org.springframework.aop.framework.JdkDynamicAopProxy`
- advised : `org.springframework.aop.framework.ProxyFactory` (`org.springframework.aop.framework.AdvisedSupport` 상속)
- target : 내가 구현한 `MybatisSpringmemberQueryServiceImpl`
- advisor : `BeanFactoryTransactionAttributeSourceAdvisor`
  - advice : `TransactionInterceptor`
  - transactionManager

<img width="611" alt="image" src="https://github.com/zz9z9/zz9z9.github.io/assets/64415489/d9174154-a477-46b9-b6d1-d99c8f606fa4">


- 위 코드를 아래 그림에 대입해보면
  - Caller : `main 함수`
  - AOP Proxy : `java.lang.reflect.Proxy` ? `org.springframework.aop.framework.JdkDynamicAopProxy` ?
  - Transaction Advisor : `BeanFactoryTransactionAttributeSourceAdvisor`
  - Custom Advisor(s) : 없음
  - Target Method : `MybatisSpringmemberQueryServiceImpl#doSomething`

![image](https://github.com/zz9z9/zz9z9.github.io/assets/64415489/81c89fa5-d7d7-4520-9fbf-a314101bae42)


## Proxy 통해서 MybatisSpringMemberQueryServiceImpl#doSomething 호출되기까지의 실행흐름 살펴보기
<img width="621" alt="image" src="https://github.com/zz9z9/zz9z9.github.io/assets/64415489/a785022d-eaa2-4464-896c-dc9801495283">

- `org.springframework.transaction.interceptor.TransactionAspectSupport#invokeWithinTransaction` 이게 핵심인듯 하다.
- `org.springframework.transaction.interceptor.TransactionAspectSupport#invokeWithinTransaction` 일부 발췌
```java
		if (txAttr == null || !(ptm instanceof CallbackPreferringPlatformTransactionManager)) {
			// Standard transaction demarcation with getTransaction and commit/rollback calls.
			TransactionInfo txInfo = createTransactionIfNecessary(ptm, txAttr, joinpointIdentification);

			Object retVal;
			try {
				// This is an around advice: Invoke the next interceptor in the chain.
				// This will normally result in a target object being invoked.
				retVal = invocation.proceedWithInvocation();  // 실제 타겟 메서드 실행
			}
			catch (Throwable ex) {
				// target invocation exception
				completeTransactionAfterThrowing(txInfo, ex); // 에러시 롤백
				throw ex;
			}
			finally {
				cleanupTransactionInfo(txInfo);
			}

			if (retVal != null && vavrPresent && VavrDelegate.isVavrTry(retVal)) {
				// Set rollback-only in case of Vavr failure matching our rollback rules...
				TransactionStatus status = txInfo.getTransactionStatus();
				if (status != null && txAttr != null) {
					retVal = VavrDelegate.evaluateTryFailure(retVal, txAttr, status);
				}
			}

			commitTransactionAfterReturning(txInfo);  // 정상적으로 로직 완료되면 커밋
			return retVal;
		}
```

- 타겟 메서드(`invocation.proceedWithInvocation()`)가 정상 수행되면  `commitTransactionAfterReturning`를 거쳐 커밋을 위해 최종적으로 `org.springframework.jdbc.datasource.DataSourceTransactionManager#doCommit`이 호출됨 (JDBC 커넥션을 커밋하는 것을 알 수 있다.)
```java
	@Override
	protected void doCommit(DefaultTransactionStatus status) {
		DataSourceTransactionObject txObject = (DataSourceTransactionObject) status.getTransaction();
		Connection con = txObject.getConnectionHolder().getConnection();
		if (status.isDebug()) {
			logger.debug("Committing JDBC transaction on Connection [" + con + "]");
		}
		try {
			con.commit();
		}
		catch (SQLException ex) {
			throw translateException("JDBC commit", ex);
		}
	}
```

- 타겟 메서드(`invocation.proceedWithInvocation()`) 실행시 예외, 에러 발생하면 `completeTransactionAfterThrowing`를 거쳐 롤백을 위해 최종적으로 `org.springframework.jdbc.datasource.DataSourceTransactionManager#doRollback`이 호출됨 (JDBC 커넥션을 롤백하는 것을 알 수 있다.)
```java
	@Override
	protected void doRollback(DefaultTransactionStatus status) {
		DataSourceTransactionObject txObject = (DataSourceTransactionObject) status.getTransaction();
		Connection con = txObject.getConnectionHolder().getConnection();
		if (status.isDebug()) {
			logger.debug("Rolling back JDBC transaction on Connection [" + con + "]");
		}
		try {
			con.rollback();
		}
		catch (SQLException ex) {
			throw translateException("JDBC rollback", ex);
		}
	}
```
## 참고
- The Spring team recommends that you annotate methods of concrete classes with the `@Transactional` annotation, rather than relying on annotated methods in interfaces, even if the latter does work for interface-based and target-class proxies as of 5.0.
- Since Java annotations are not inherited from interfaces, interface-declared annotations are still not recognized by the weaving infrastructure when using AspectJ mode, so the aspect does not get applied.
- As a consequence, your transaction annotations may be silently ignored: Your code might appear to "work" until you test a rollback scenario.

- In proxy mode (which is the default), only external method calls coming in through the proxy are intercepted.
  - This means that self-invocation (in effect, a method within the target object calling another method of the target object) does not lead to an actual transaction at runtime even if the invoked method is marked with `@Transactional`.
  - Also, the proxy must be fully initialized to provide the expected behavior, so you should not rely on this feature in your initialization code — e.g. in a `@PostConstruct` method.

- The default advice mode for processing `@Transactional` annotations is proxy, which allows for interception of calls through the proxy only.
  - Local calls within the same class cannot get intercepted that way.
  - For a more advanced mode of interception, consider switching to aspectj mode in combination with compile-time or load-time weaving.

# @EnableTransactionManagement
- Enables Spring's annotation-driven transaction management capability, similar to the support found in Spring's `<tx:*>` XML namespace.
- To be used on `@Configuration` classes to configure traditional, imperative transaction management or reactive transaction management.

- 설정 by 자바 코드
```java
 @Configuration
 @EnableTransactionManagement
 public class AppConfig {

     @Bean
     public FooRepository fooRepository() {
         // configure and return a class having @Transactional methods
         return new JdbcFooRepository(dataSource());
     }

     @Bean
     public DataSource dataSource() {
         // configure and return the necessary JDBC DataSource
     }

     @Bean
     public PlatformTransactionManager txManager() {
         return new DataSourceTransactionManager(dataSource());
     }
 }
```

- 설정 by XML

```xml
 <beans>

     <tx:annotation-driven/>

     <bean id="fooRepository" class="com.foo.JdbcFooRepository">
         <constructor-arg ref="dataSource"/>
     </bean>

     <bean id="dataSource" class="com.vendor.VendorDataSource"/>

     <bean id="transactionManager" class="org.sfwk...DataSourceTransactionManager">
         <constructor-arg ref="dataSource"/>
     </bean>

 </beans>
```

- In both of the scenarios above, `@EnableTransactionManagement` and `<tx:annotation-driven/>` are responsible for registering the necessary Spring components that power annotation-driven transaction management, such as the `TransactionInterceptor and the proxy-` or `AspectJ-based advice` that weaves the interceptor into the call stack when `JdbcFooRepository`'s `@Transactional` methods are invoked.

- A minor difference between the two examples lies in the naming of the TransactionManager bean: In the @Bean case, the name is "txManager" (per the name of the method); in the XML case, the name is "transactionManager".
- `<tx:annotation-driven/>` is hard-wired to look for a bean named "transactionManager" by default, however `@EnableTransactionManagement` is more flexible; it will fall back to a by-type lookup for any TransactionManager bean in the container.
- Thus the name can be "txManager", "transactionManager", or "tm": it simply does not matter.

## 주의사항
-  `@EnableTransactionManagement` and <tx:annotation-driven/> look for @Transactional only on beans **in the same application context in which they are defined.**
- This means that, if you put annotation-driven configuration in a WebApplicationContext for a DispatcherServlet, it checks for `@Transactional` beans only in your controllers and not in your services.

# 부록 : 동일한 ServiceImpl 객체 내에 있는 @Transactional 붙지 않은 메서드 실행할때는 어떤게 다를까 ?
- `org.springframework.aop.framework.JdkDynamicAopProxy#invoke`
  - `@Transactional`붙은 메서드 실행시에는 `List<Object> chain = this.advised.getInterceptorsAndDynamicInterceptionAdvice(method, targetClass);`에서 chain에 TransactionInterceptor가 들어가 있음. 그래서 `ReflectiveMethodInvocation.proceed()` 호출됨
  - 반면 `@Transactional`이 붙지 않는 경우 chain에 아무것도 들어있지 않게되고, `AopUtils.invokeJoinpointUsingReflection(target, method, argsToUse);`이게 실행됨

```java
	@Override
	@Nullable
	public Object invoke(Object proxy, Method method, Object[] args) throws Throwable {
		Object oldProxy = null;
		boolean setProxyContext = false;

		TargetSource targetSource = this.advised.targetSource;
		Object target = null;

		try {
			if (!this.equalsDefined && AopUtils.isEqualsMethod(method)) {
				// The target does not implement the equals(Object) method itself.
				return equals(args[0]);
			}
			else if (!this.hashCodeDefined && AopUtils.isHashCodeMethod(method)) {
				// The target does not implement the hashCode() method itself.
				return hashCode();
			}
			else if (method.getDeclaringClass() == DecoratingProxy.class) {
				// There is only getDecoratedClass() declared -> dispatch to proxy config.
				return AopProxyUtils.ultimateTargetClass(this.advised);
			}
			else if (!this.advised.opaque && method.getDeclaringClass().isInterface() &&
					method.getDeclaringClass().isAssignableFrom(Advised.class)) {
				// Service invocations on ProxyConfig with the proxy config...
				return AopUtils.invokeJoinpointUsingReflection(this.advised, method, args);
			}

			Object retVal;

			if (this.advised.exposeProxy) {
				// Make invocation available if necessary.
				oldProxy = AopContext.setCurrentProxy(proxy);
				setProxyContext = true;
			}

			// Get as late as possible to minimize the time we "own" the target,
			// in case it comes from a pool.
			target = targetSource.getTarget();
			Class<?> targetClass = (target != null ? target.getClass() : null);

			// Get the interception chain for this method.
			List<Object> chain = this.advised.getInterceptorsAndDynamicInterceptionAdvice(method, targetClass);

			// Check whether we have any advice. If we don't, we can fallback on direct
			// reflective invocation of the target, and avoid creating a MethodInvocation.
			if (chain.isEmpty()) {
				// We can skip creating a MethodInvocation: just invoke the target directly
				// Note that the final invoker must be an InvokerInterceptor so we know it does
				// nothing but a reflective operation on the target, and no hot swapping or fancy proxying.
				Object[] argsToUse = AopProxyUtils.adaptArgumentsIfNecessary(method, args);
				retVal = AopUtils.invokeJoinpointUsingReflection(target, method, argsToUse);
			}
			else {
				// We need to create a method invocation...
				MethodInvocation invocation =
						new ReflectiveMethodInvocation(proxy, target, method, args, targetClass, chain);
				// Proceed to the joinpoint through the interceptor chain.
				retVal = invocation.proceed();
			}

			// Massage return value if necessary.
			Class<?> returnType = method.getReturnType();
			if (retVal != null && retVal == target &&
					returnType != Object.class && returnType.isInstance(proxy) &&
					!RawTargetAccess.class.isAssignableFrom(method.getDeclaringClass())) {
				// Special case: it returned "this" and the return type of the method
				// is type-compatible. Note that we can't help if the target sets
				// a reference to itself in another returned object.
				retVal = proxy;
			}
			else if (retVal == null && returnType != Void.TYPE && returnType.isPrimitive()) {
				throw new AopInvocationException(
						"Null return value from advice does not match primitive return type for: " + method);
			}
			return retVal;
		}
		finally {
			if (target != null && !targetSource.isStatic()) {
				// Must have come from TargetSource.
				targetSource.releaseTarget(target);
			}
			if (setProxyContext) {
				// Restore old proxy.
				AopContext.setCurrentProxy(oldProxy);
			}
		}
	}
```


## 참고 자료
- https://docs.spring.io/spring-framework/reference/data-access/transaction/declarative/tx-decl-explained.html
- https://docs.spring.io/spring-framework/docs/6.1.3/javadoc-api/org/springframework/transaction/annotation/EnableTransactionManagement.html
