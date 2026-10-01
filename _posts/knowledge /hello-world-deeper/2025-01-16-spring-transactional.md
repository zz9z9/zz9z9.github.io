---
title: 스프링 @Transactional 살펴보기 (AOP, ThreadLocal)
date: 2025-01-16 22:25:00 +0900
categories: [지식 더하기, 들여다보기]
tags: [Spring]
---


HelloService$$EnhancerBySpringCGLIB$$ba960935 (hello.springboot.controller)
-> org.springframework.aop.framework.CglibAopProxy.DynamicAdvisedInterceptor#intercept
-> org.springframework.aop.framework.CglibAopProxy.CglibMethodInvocation#proceed
-> org.springframework.aop.framework.ReflectiveMethodInvocation#proceed
-> org.springframework.transaction.interceptor.TransactionInterceptor#invoke
-> org.springframework.transaction.interceptor.TransactionAspectSupport#invokeWithinTransaction


```java
    // TransactionAspectSupport#invokeWithinTransaction

    @Nullable
    protected Object invokeWithinTransaction(Method method, @Nullable Class<?> targetClass, final InvocationCallback invocation) throws Throwable {
            ...

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

## TransactionInfo txInfo = this.createTransactionIfNecessary(ptm, txAttr, joinpointIdentification);

### 리턴값 : org.springframework.transaction.interceptor.TransactionAspectSupport.TransactionInfo
> 트랜잭션 처리에 필요한 정보를 관리하는 객체

- 필요한 정보 ?
  - PlatformTransactionManager
  - TransactionAttribute
  - TransactionStatus
    - 새로운 트랜잭션인지
    - readOnly인지
    - savepoint가 있는지
    - 등등..
  - joinpointIdentification (@Transactional 선언된 메서드명)

- TransactionStatus는 PlatformTransactionManager로부터 얻어온다.
```java
// org.springframework.transaction.interceptor.TransactionAspectSupport#createTransactionIfNecessary

TransactionStatus status = null;
        if (txAttr != null) {
            if (tm != null) {
                status = tm.getTransaction((TransactionDefinition)txAttr);
            } else if (this.logger.isDebugEnabled()) {
                this.logger.debug("Skipping transactional joinpoint [" + joinpointIdentification + "] because no transaction manager has been configured");
            }
        }
```

- TransactionStatus는 `TransactionDefinition`과 `트랜잭션 객체`를 기반으로 만들어진다.
  - TransactionDefinition : 트랜잭션 전파 레벨, 격리 수준을 관리
  - 트랜잭션 객체
    - `AbstractPlatformTransactionManager`의 구현체가 `DataSourceTransactionManager`를 기준으로 `DataSourceTransactionObject`를 의미

```java
// org.springframework.transaction.support.AbstractPlatformTransactionManager#getTransaction

public final TransactionStatus getTransaction(@Nullable TransactionDefinition definition) throws TransactionException {
    TransactionDefinition def = definition != null ? definition : TransactionDefinition.withDefaults();
    Object transaction = this.doGetTransaction();
    boolean debugEnabled = this.logger.isDebugEnabled();
    if (this.isExistingTransaction(transaction)) {
        return this.handleExistingTransaction(def, transaction, debugEnabled);
    }

    ...

    } else {
        SuspendedResourcesHolder suspendedResources = this.suspend((Object)null);
        if (debugEnabled) {
            this.logger.debug("Creating new transaction with name [" + def.getName() + "]: " + def);
        }

        try {
            return this.startTransaction(def, transaction, debugEnabled, suspendedResources);
        } catch (Error | RuntimeException var7) {
            this.resume((Object)null, suspendedResources);
            throw var7;
        }
    }
}
```

- 트랜잭션 객체
  - `TransactionSynchronizationManager`로부터 `ConnectionHolder`를 가져온다.
```java
// org.springframework.jdbc.datasource.DataSourceTransactionManager#doGetTransaction

protected Object doGetTransaction() {
  DataSourceTransactionObject txObject = new DataSourceTransactionObject();
  txObject.setSavepointAllowed(this.isNestedTransactionAllowed());
  ConnectionHolder conHolder = (ConnectionHolder)TransactionSynchronizationManager.getResource(this.obtainDataSource());
  txObject.setConnectionHolder(conHolder, false);
  return txObject;
}
```

- key값을 `DataSource`로해서 `ThreadLocal`에 `org.springframework.jdbc.datasource.ConnectionHolder`가 매핑된다.
```java
public abstract class TransactionSynchronizationManager {
   private static final ThreadLocal<Map<Object, Object>> resources = new NamedThreadLocal("Transactional resources");

   ...

  @Nullable
  public static Object getResource(Object key) {
    Object actualKey = TransactionSynchronizationUtils.unwrapResourceIfNecessary(key);
    return doGetResource(actualKey);
  }

  @Nullable
  private static Object doGetResource(Object actualKey) {
    Map<Object, Object> map = (Map)resources.get();
    if (map == null) {
      return null;
    } else {
      Object value = map.get(actualKey);
      if (value instanceof ResourceHolder && ((ResourceHolder)value).isVoid()) {
        map.remove(actualKey);
        if (map.isEmpty()) {
          resources.remove();
        }

        value = null;
      }

      return value;
    }
  }

}
```

**중간 정리**
- `@Transactional`이 붙은 메서드(또는 클래스 단위)를 가진 클래스는 AOP Proxy 객체 생성된다. (런타임에 ?)
- 해당 메서드가 호출되면 `TransactionInterceptor`에 의해 intercept되어 `TransactionAspectSupport#invokeWithinTransaction`가 실행된다.
- `TransactionAspectSupport#invokeWithinTransaction`의 실행 흐름은 다음과 같다.
  - 트랜잭션 처리에 필요한 정보 가져오기 (기존에 트랜잭션이 없으면 트랜잭션 생성)
  - 타겟 메서드 실행
  - 커밋

- 트랜잭션 처리에 필요한 정보 중 TransactionStatus를 만드는 과정
  - `TransactionDefinition`과 `트랜잭션 객체`이 필요
  - 특히, `트랜잭션 객체`에는 `TransactionSynchronizationManager`에서 `DataSource`를 key값으로 매핑하여 관리하는 `ConnectionHolder` 정보가 담겨있음
     - `ConnectionHolder`는 스레드 단위로 바인딩됨


- 트랜잭션 시작
  - this.doBegin(transaction, definition); --> 트랜잭션 시작이라는건 결국 ConnectionHolder를 현재 스레드에 바인딩 시키는게 가장 키포인트인 것 같다.
  - this.prepareSynchronization(status, definition); --> 트랜잭션 동기화 ? --> 트랜잭션 전파 관련해서 관리하기 위해 ?

```java
// org.springframework.transaction.support.AbstractPlatformTransactionManager#startTransaction

private TransactionStatus startTransaction(TransactionDefinition definition, Object transaction, boolean debugEnabled, @Nullable SuspendedResourcesHolder suspendedResources) {
  boolean newSynchronization = this.getTransactionSynchronization() != 2;
  DefaultTransactionStatus status = this.newTransactionStatus(definition, transaction, true, newSynchronization, debugEnabled, suspendedResources);
  this.doBegin(transaction, definition);
  this.prepareSynchronization(status, definition);
  return status;
}
```

```java
// org.springframework.jdbc.datasource.DataSourceTransactionManager#doBegin

protected void doBegin(Object transaction, TransactionDefinition definition) {
  DataSourceTransactionObject txObject = (DataSourceTransactionObject)transaction;
  Connection con = null;

  try {
    if (!txObject.hasConnectionHolder() || txObject.getConnectionHolder().isSynchronizedWithTransaction()) {
      Connection newCon = this.obtainDataSource().getConnection();
      if (this.logger.isDebugEnabled()) {
        this.logger.debug("Acquired Connection [" + newCon + "] for JDBC transaction");
      }

      txObject.setConnectionHolder(new ConnectionHolder(newCon), true);
    }

    txObject.getConnectionHolder().setSynchronizedWithTransaction(true);
    con = txObject.getConnectionHolder().getConnection();
    Integer previousIsolationLevel = DataSourceUtils.prepareConnectionForTransaction(con, definition);
    txObject.setPreviousIsolationLevel(previousIsolationLevel);
    txObject.setReadOnly(definition.isReadOnly());
    if (con.getAutoCommit()) {
      txObject.setMustRestoreAutoCommit(true);
      if (this.logger.isDebugEnabled()) {
        this.logger.debug("Switching JDBC Connection [" + con + "] to manual commit");
      }

      con.setAutoCommit(false);
    }

    this.prepareTransactionalConnection(con, definition);
    txObject.getConnectionHolder().setTransactionActive(true);
    int timeout = this.determineTimeout(definition);
    if (timeout != -1) {
      txObject.getConnectionHolder().setTimeoutInSeconds(timeout);
    }

    if (txObject.isNewConnectionHolder()) {
      TransactionSynchronizationManager.bindResource(this.obtainDataSource(), txObject.getConnectionHolder());
    }

  } catch (Throwable var7) {
    if (txObject.isNewConnectionHolder()) {
      DataSourceUtils.releaseConnection(con, this.obtainDataSource());
      txObject.setConnectionHolder((ConnectionHolder)null, false);
    }

    throw new CannotCreateTransactionException("Could not open JDBC Connection for transaction", var7);
  }
}
```

```java
// org.springframework.transaction.support.AbstractPlatformTransactionManager#prepareSynchronization

protected void prepareSynchronization(DefaultTransactionStatus status, TransactionDefinition definition) {
    if (status.isNewSynchronization()) {
        TransactionSynchronizationManager.setActualTransactionActive(status.hasTransaction());
        TransactionSynchronizationManager.setCurrentTransactionIsolationLevel(definition.getIsolationLevel() != -1 ? definition.getIsolationLevel() : null);
        TransactionSynchronizationManager.setCurrentTransactionReadOnly(definition.isReadOnly());
        TransactionSynchronizationManager.setCurrentTransactionName(definition.getName());
        TransactionSynchronizationManager.initSynchronization();
    }
}
```

## this.commitTransactionAfterReturning(txInfo);


