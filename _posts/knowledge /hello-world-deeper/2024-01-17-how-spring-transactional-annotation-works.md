---
title: 스프링 @Transactional 동작 원리 살펴보기
date: 2024-01-17 20:25:00 +0900
---

## 사전 세팅
```java
public interface MemberQueryService {
    void createMember(String id, String name);
}
```

```java
public class MybatisSpringMemberQueryServiceImpl implements MemberQueryService {

  private final SqlSession sqlSession;

  public MybatisSpringMemberQueryServiceImpl(SqlSession sqlSession) {
    this.sqlSession = sqlSession;
  }

  @Override
  @Transactional
  public void createMember(String id, String name) {
    Member newMember = new Member(id, name);
    sqlSession.insert("hello.persistence.mybatis.mapper.MemberMapper.save", newMember);

    causeException();

    sqlSession.insert("hello.persistence.mybatis.mapper.MemberHistoryMapper.save", MemberHistory.forJoin(newMember));
  }

}
```

```java
public class PersistenceDemoApp {

    public static void main(String[] args) {
        ApplicationContext ctx = new AnnotationConfigApplicationContext(AppConfig.class);
        MemberQueryService memberQueryService = (MemberQueryService) ctx.getBean("memberQueryService");

        memberQueryService.createMember("userId", "userName");
    }

}
```

## memberQueryService.createMember 실행시
- org.springframework.transaction.config.internalTransactionAdvisor

- JdkDynamicAopProxy
- advisor : org.springframework.transaction.interceptor.BeanFactoryTransactionAttributeSourceAdvisor:
- advice org.springframework.transaction.interceptor.TransactionInterceptor@3aaf4f07

- `List<Object> chain`에 `org.springframework.transaction.interceptor.TransactionInterceptor` 담겨있음 그리고 아래 코드 실행됨

```java
MethodInvocation invocation = new ReflectiveMethodInvocation(proxy, target, method, args, targetClass, chain);
retVal = invocation.proceed();
```

- `org.springframework.aop.framework.JdkDynamicAopProxy#invoke`
```java
@Nullable
public Object invoke(Object proxy, Method method, Object[] args) throws Throwable {
    Object oldProxy = null;
    boolean setProxyContext = false;
    TargetSource targetSource = this.advised.targetSource;
    Object target = null;

    Integer var8;
    try {
        ...

        if (this.hashCodeDefined || !AopUtils.isHashCodeMethod(method)) {
            ...

            target = targetSource.getTarget();
            Class<?> targetClass = target != null ? target.getClass() : null;
            List<Object> chain = this.advised.getInterceptorsAndDynamicInterceptionAdvice(method, targetClass); // 리스트에 TransactionInterceptor 담겨있음
            if (chain.isEmpty()) {
                Object[] argsToUse = AopProxyUtils.adaptArgumentsIfNecessary(method, args);
                retVal = AopUtils.invokeJoinpointUsingReflection(target, method, argsToUse);
            } else {
                MethodInvocation invocation = new ReflectiveMethodInvocation(proxy, target, method, args, targetClass, chain);
                retVal = invocation.proceed();
            }

            Class<?> returnType = method.getReturnType();
            if (retVal != null && retVal == target && returnType != Object.class && returnType.isInstance(proxy) && !RawTargetAccess.class.isAssignableFrom(method.getDeclaringClass())) {
                retVal = proxy;
            } else if (retVal == null && returnType != Void.TYPE && returnType.isPrimitive()) {
                throw new AopInvocationException("Null return value from advice does not match primitive return type for: " + method);
            }

            Object var12 = retVal;
            return var12;
        }

        var8 = this.hashCode();
    } finally {
        if (target != null && !targetSource.isStatic()) {
            targetSource.releaseTarget(target);
        }

        if (setProxyContext) {
            AopContext.setCurrentProxy(oldProxy);
        }

    }

    return var8;
}
```


- org.springframework.transaction.interceptor.TransactionInterceptor#invoke
```java
    @Nullable
public Object invoke(final MethodInvocation invocation) throws Throwable {
  Class<?> targetClass = invocation.getThis() != null ? AopUtils.getTargetClass(invocation.getThis()) : null;
  return this.invokeWithinTransaction(invocation.getMethod(), targetClass, new TransactionAspectSupport.CoroutinesInvocationCallback() {
    @Nullable
    public Object proceedWithInvocation() throws Throwable {
      return invocation.proceed();
    }

    public Object getTarget() {
      return invocation.getThis();
    }

    public Object[] getArguments() {
      return invocation.getArguments();
    }
  });
}
```
- org.springframework.transaction.interceptor.TransactionAspectSupport#invokeWithinTransaction
```java
    @Nullable
    protected Object invokeWithinTransaction(Method method, @Nullable Class<?> targetClass, final InvocationCallback invocation) throws Throwable {
        TransactionAttributeSource tas = this.getTransactionAttributeSource();
        TransactionAttribute txAttr = tas != null ? tas.getTransactionAttribute(method, targetClass) : null;
        TransactionManager tm = this.determineTransactionManager(txAttr);
        if (this.reactiveAdapterRegistry != null && tm instanceof ReactiveTransactionManager) {
            boolean isSuspendingFunction = KotlinDetector.isSuspendingFunction(method);
            boolean hasSuspendingFlowReturnType = isSuspendingFunction && "kotlinx.coroutines.flow.Flow".equals((new MethodParameter(method, -1)).getParameterType().getName());
            if (isSuspendingFunction && !(invocation instanceof CoroutinesInvocationCallback)) {
                throw new IllegalStateException("Coroutines invocation not supported: " + method);
            } else {
                CoroutinesInvocationCallback corInv = isSuspendingFunction ? (CoroutinesInvocationCallback)invocation : null;
                ReactiveTransactionSupport txSupport = (ReactiveTransactionSupport)this.transactionSupportCache.computeIfAbsent(method, (key) -> {
                    Class<?> reactiveType = isSuspendingFunction ? (hasSuspendingFlowReturnType ? Flux.class : Mono.class) : method.getReturnType();
                    ReactiveAdapter adapter = this.reactiveAdapterRegistry.getAdapter(reactiveType);
                    if (adapter == null) {
                        throw new IllegalStateException("Cannot apply reactive transaction to non-reactive return type: " + method.getReturnType());
                    } else {
                        return new ReactiveTransactionSupport(adapter);
                    }
                });
                InvocationCallback callback = invocation;
                if (corInv != null) {
                    callback = () -> {
                        return CoroutinesUtils.invokeSuspendingFunction(method, corInv.getTarget(), corInv.getArguments());
                    };
                }

                Object result = txSupport.invokeWithinTransaction(method, targetClass, callback, txAttr, (ReactiveTransactionManager)tm);
                if (corInv != null) {
                    Publisher<?> pr = (Publisher)result;
                    return hasSuspendingFlowReturnType ? TransactionAspectSupport.KotlinDelegate.asFlow(pr) : TransactionAspectSupport.KotlinDelegate.awaitSingleOrNull(pr, corInv.getContinuation());
                } else {
                    return result;
                }
            }
        } else {
            PlatformTransactionManager ptm = this.asPlatformTransactionManager(tm);
            String joinpointIdentification = this.methodIdentification(method, targetClass, txAttr);
            if (txAttr != null && ptm instanceof CallbackPreferringPlatformTransactionManager) {
                ThrowableHolder throwableHolder = new ThrowableHolder();

                Object result;
                try {
                    result = ((CallbackPreferringPlatformTransactionManager)ptm).execute(txAttr, (statusx) -> {
                        TransactionInfo txInfo = this.prepareTransactionInfo(ptm, txAttr, joinpointIdentification, statusx);

                        Object var9;
                        try {
                            Object retVal = invocation.proceedWithInvocation();
                            if (retVal != null && vavrPresent && TransactionAspectSupport.VavrDelegate.isVavrTry(retVal)) {
                                retVal = TransactionAspectSupport.VavrDelegate.evaluateTryFailure(retVal, txAttr, statusx);
                            }

                            var9 = retVal;
                            return var9;
                        } catch (Throwable var13) {
                            if (txAttr.rollbackOn(var13)) {
                                if (var13 instanceof RuntimeException) {
                                    throw (RuntimeException)var13;
                                }

                                throw new ThrowableHolderException(var13);
                            }

                            throwableHolder.throwable = var13;
                            var9 = null;
                        } finally {
                            this.cleanupTransactionInfo(txInfo);
                        }

                        return var9;
                    });
                } catch (ThrowableHolderException var22) {
                    throw var22.getCause();
                } catch (TransactionSystemException var23) {
                    if (throwableHolder.throwable != null) {
                        this.logger.error("Application exception overridden by commit exception", throwableHolder.throwable);
                        var23.initApplicationException(throwableHolder.throwable);
                    }

                    throw var23;
                } catch (Throwable var24) {
                    if (throwableHolder.throwable != null) {
                        this.logger.error("Application exception overridden by commit exception", throwableHolder.throwable);
                    }

                    throw var24;
                }

                if (throwableHolder.throwable != null) {
                    throw throwableHolder.throwable;
                } else {
                    return result;
                }
            } else {
                TransactionInfo txInfo = this.createTransactionIfNecessary(ptm, txAttr, joinpointIdentification);

                Object retVal;
                try {
                    retVal = invocation.proceedWithInvocation();
                } catch (Throwable var20) {
                    this.completeTransactionAfterThrowing(txInfo, var20);
                    throw var20;
                } finally {
                    this.cleanupTransactionInfo(txInfo);
                }

                if (retVal != null && vavrPresent && TransactionAspectSupport.VavrDelegate.isVavrTry(retVal)) {
                    TransactionStatus status = txInfo.getTransactionStatus();
                    if (status != null && txAttr != null) {
                        retVal = TransactionAspectSupport.VavrDelegate.evaluateTryFailure(retVal, txAttr, status);
                    }
                }

                this.commitTransactionAfterReturning(txInfo);
                return retVal;
            }
        }
    }
```
