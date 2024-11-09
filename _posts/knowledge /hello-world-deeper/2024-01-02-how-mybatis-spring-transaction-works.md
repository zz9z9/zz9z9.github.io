---
title: MyBatis-Spring 트랜잭션 관리
date: 2024-01-02 22:25:00 +0900
categories: [지식 더하기, 들여다보기]
tags: [MyBatis]
---

> [해당 포스팅](https://zz9z9.github.io/posts/hello-mybatis/)에서 mybatis, mybatis-spring 사용법을 간단히 살펴보았다. <br>
> 이번에는 개인적으로 가장 궁금했던 mybatis-spring에서 트랜잭션을 다루는 부분이 내부적으로 어떻게 동작하는지 살펴보려고 한다. <br>
> (예제 코드는 훑어보기 편에서 사용된 코드)

# 들어가기 전 : 예제 코드 다시 살펴보기

- SqlSession의 구현체로 SqlSessionTemplate 주입해서 사용하는 경우, `sqlSession.insert` 호출하면 auto-commit됨

```java
public class MybatisSpringMemberQueryServiceImpl implements MemberQueryService {

  private final SqlSession sqlSession;

  public MybatisSpringMemberQueryServiceImpl(SqlSession sqlSession) {
    this.sqlSession = sqlSession;
  }

  @Override
  public void createMember(String id, String name) {
    Member newMember = new Member(id, name);
    sqlSession.insert("member.save", newMember);
    sqlSessionTemplate.insert("memberHistory.save", MemberHistory.forJoin(newMember));
  }
}
```

- 반면 위와 동일하게 SqlSessionTemplate 주입해서 사용하더라도, 아래 코드는 `sqlSession.insert` 호출하면 auto-commit 되지 않고 `transactionManager.commit` 시점에서 커밋됨

```java
public class MybatisSpringMemberQueryServiceImpl implements MemberQueryService {

    private final SqlSession sqlSession;
    private final PlatformTransactionManager transactionManager;

    public MybatisSpringMemberQueryServiceImpl(SqlSession sqlSession, PlatformTransactionManager transactionManager) {
        this.sqlSession = sqlSession;
        this.transactionManager = transactionManager;
    }

    @Override
    public void createMember(String id, String name) {
      TransactionStatus txStatus = transactionManager.getTransaction(new DefaultTransactionDefinition());
      Member newMember = new Member(id, name);

      sqlSession.insert("member.save", newMember);
      sqlSession.insert("memberHistory.save", MemberHistory.forJoin(newMember));

      transactionManager.commit(txStatus);
    }

}
```

> 이게 어떻게 가능한 것인지 파악하기 위해 아래 순서로 내부 흐름을 살펴볼 예정이다.
> 1. `transactionManager.getTransaction` <br>
> 2. `sqlSession.insert // 첫번째 insert`  <br>
> 3. `sqlSession.insert // 두번째 insert`  <br>
> 4. `transactionManager.commit`

## 1. transactionManager.getTransaction

> 내부적으로는 다양한 조건들에 의해 더 복잡하게 분기처리 되지만, 위 예제 코드가 어떻게 동작하는지의 흐름을 파악하는 정도로만 시퀀스 다이어그램을 그려봤다. ~~(처음이라 제대로 그린것인지는 잘 모르겠지만 ...)~~ <br>
> `transactionManager.getTransaction` 호출시 흐름을 내가 이해한대로 정리하면,  <br>
> - 추상 클래스인 AbstractPlatformTransactionManager는 실제 구현체인 DataSourceTransactionManager에게 트랜잭션을 다루기 위한 객체를 만들어달라고 요청한다. <br>
> - 동일한 트랜잭션 내부에서는 하나의 커넥션이 사용되어야 하기 때문에, 그러한 커넥션을 관리할 ConnectionHolder가 필요하다(트랜잭션 동기화). 따라서, 트랜잭션을 다루기 위한 객체는 ConnectionHolder를 필요로하고 이를 얻기 위해 TransactionSynchronizationManager에게 요청한다. <br>
> - AbstractPlatformTransactionManager는 얻은 트랜잭션 객체(DataSourceTransactionObject)가 이미 처리하고 있는 트랜잭션이 존재하는지 확인한다.
> - 없는 경우, 트랜잭션 처리를 시작하기 위한 준비를 한다. <br> (트랜잭션 객체에 ConnectionHolder 세팅, ConnectionHolder에 트랜잭션 동기화 여부 세팅, ConnectionHolder에서 관리하는 Connection에 auto-commit `false` 세팅, TransactionSynchronizationManager에 ConnectionHolder 세팅되도록 등)
> - 트랜잭션 및 트랜잭션 동기화와 관련된 속성들을 TransactionSynchronizationManager쪽에 세팅한다. <br><br>
> 즉, `transactionManager.getTransaction`는 **"기존에 처리되고 있는 트랜잭션이 있는지 확인(1)하고, 없으면 트랜잭션 처리를 위해 준비(2)하는 과정"** 이라고 생각하면 될 것 같다.

<img width="1346" alt="image" src="https://github.com/zz9z9/zz9z9.github.io/assets/64415489/d7582312-b86e-47a1-974e-2ef97c540c4c">

- 참고 : `org.springframework.jdbc.datasource.DataSourceTransactionManager#doBegin`

```java
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

- 참고 : `org.springframework.transaction.support.AbstractPlatformTransactionManager#prepareSynchronization`

```java
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

## 2. 첫번째 sqlSession.insert

- TransactionSynchronizationManager에게 트랜잭션 동기화가 활성화 되어있는지 확인.
- 활성화되어 있으면 동기화에 필요한 SqlSessionHolder가 있는지 확인
- SqlSessionHolder가 없으면 생성하여 TransactionSynchronizationManager에 바인딩
- DB에 질의하기 위해 얻어온 SqlSession의 구현체 DefaultSqlSession를 통해 DB에 질의
  - 질의시 1번 단계(`transactionManager.getTransaction`)에서 세팅한 ConnectionHolder의 Connection이 사용된다.
- 트랜잭션 동기화중인지 확인뒤, 동기화 중이지 않으면 질의한 것 바로 commit 후 SqlSession.close()
- 동기화 중이면, commit 하지않고 동기화에 사용되는 SqlSessionHolder의 SqlSession을 release

- 요약하면,
  - (1) 트랜잭션 동기화중인지 확인후 동기화를 위한 SqlSessionHolder 등 준비
  - (2) 동기화 중이면, DB에 질의 후 SqlSession을 commit & close하지 않고, SqlSession을 release

<img width="1598" alt="image" src="https://github.com/zz9z9/zz9z9.github.io/assets/64415489/2459112c-7f85-4491-ab0c-77b4c4abcc15">

- `SqlSession`의 구현체로 사용되는 `SqlSessionTemplate`의 내부에서
  `this.sqlSessionProxy = (SqlSession)Proxy.newProxyInstance(SqlSessionFactory.class.getClassLoader(), new Class[]{SqlSession.class}, new SqlSessionInterceptor());`


## 3. 두번째 sqlSession.insert
=> 트랜잭션 프로파게이션 관련해서 어떻게 처리하는지도 ??
=> 질의시 1번 단계(`transactionManager.getTransaction`)에서 세팅한 ConnectionHolder의 Connection이 사용된다. 이 부분 잘 나타내볼까 ??


## 4. transactionManager.commit

TransactionSynchronizationManager에서 ThreadLocal 사용 하는 부분
=> 여러 스레드에서 동일한 SqlSessionFactory에 접근하는 부분 제어 ??
