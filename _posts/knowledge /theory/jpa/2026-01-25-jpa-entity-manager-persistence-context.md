---
title: EntityManager와 영속성 컨텍스트
date: 2026-01-25 23:00:00 +0900
categories: [지식 더하기, 이론]
tags: [JPA, Hibernate]
---


## Architecture
---

> Hibernate는 ORM 솔루션으로서 Java 애플리케이션의 데이터 접근 계층과 관계형 데이터베이스 사이에 위치 <br>
> Java 애플리케이션은 **Hibernate API**를 사용하여 도메인 데이터를 로드, 저장, 쿼리한다.

```
Data Access Layer (데이터 접근 계층)
                ↓
    ┌─────────────────────────────────┐
    │  Java Persistence  │  Hibernate │
    │       API          │  Native API│
    ├─────────────────────────────────┤
    │           Hibernate             │
    ├─────────────────────────────────┤
    │             JDBC                │
    └─────────────────────────────────┘
                ↓
        Relational Database
```

### JPA와 Hibernate 구현체 관계

| JPA 인터페이스 | Hibernate 인터페이스 | Hibernate 구현체 |
| ------------ | ------------------- | -------------- |
| EntityManagerFactory | SessionFactory | SessionFactoryImpl |
| EntityManager | Session | SessionImpl |
| EntityTransaction | Transaction | TransactionImpl |

### SessionFactory / EntityManagerFactory

| 특성 | 설명 |
| --- | ---- |
| 스레드 안전성 | Thread-safe, 불변(immutable) |
| 역할 | 애플리케이션 도메인 모델과 DB 간의 매핑 정보를 담고 있음 |
| 생성 비용 | 매우 비쌈 → 애플리케이션당 하나만 생성해야 함 |
| 관리하는 것들 | 2차 캐시, 커넥션 풀, 트랜잭션 시스템 통합 등 |

```java
// 애플리케이션 전체에서 하나만!
@Configuration
public class HibernateConfig {
    @Bean
    public LocalSessionFactoryBean sessionFactory() { ... }
}
```

### Session / EntityManager

| 특성 | 설명 |
| ---- | ---- |
| 스레드 안전성 | Thread-safe 아님, 단일 스레드에서만 사용 |
| 수명 | 짧음 (요청당 하나, 트랜잭션 단위) |
| 개념 | "Unit of Work" 패턴 구현 |
| 내부 동작 | JDBC Connection을 감싸고 있음 |
| 핵심 기능 | 영속성 컨텍스트(1차 캐시) 유지 |

```java
// 요청마다 새로 생성, 짧게 사용
@Transactional
public void doSomething() {
    // 이 메서드 실행 동안 Session/EntityManager가 살아있음
    // 메서드 끝나면 닫힘
}
```

### Transaction / EntityTransaction

| 특성 | 설명 |
| ---- | ---- |
| 스레드 안전성 | Thread-safe 아님, 단일 스레드에서만 사용 |
| 수명 | 짧음 |
| 역할 | 물리적 트랜잭션 경계를 구분 |
| 추상화 | JDBC 트랜잭션 또는 JTA 트랜잭션을 추상화 |

```java
Transaction tx = session.beginTransaction();
try {
    // 작업
    tx.commit();
} catch (Exception e) {
    tx.rollback();
}
```

```
┌─────────────────────────────────────────────────────────┐
│                    Application                          │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│  SessionFactory (= EntityManagerFactory)                │
│  • 애플리케이션당 1개                                     │
│  • Thread-safe                                          │
│  • 2차 캐시, 커넥션 풀 관리                               │
└─────────────────────────────────────────────────────────┘
                          │ creates
                          ▼
┌─────────────────────────────────────────────────────────┐
│  Session (= EntityManager)                              │
│  • 요청/트랜잭션당 1개                                   │
│  • Thread-safe 아님                                     │
│  • 영속성 컨텍스트(1차 캐시) 보유                         │
│  • JDBC Connection 래핑                                 │
└─────────────────────────────────────────────────────────┘
                          │ creates
                          ▼
┌─────────────────────────────────────────────────────────┐
│  Transaction (= EntityTransaction)                      │
│  • 트랜잭션 경계 관리                                    │
│  • begin(), commit(), rollback()                        │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│                    Database                             │
└─────────────────────────────────────────────────────────┘
```

### ※ 참고 : Spring Data JPA에서는 ?

```java
@Service
public class UserService {

    @Autowired
    private UserRepository userRepository;  // 내부적으로 EntityManager 사용

    @Transactional  // Session, Transaction 자동 관리
    public void createUser(User user) {
        userRepository.save(user);
        // 트랜잭션 끝나면 자동 commit, Session 자동 close
    }
}
```

- Spring이 SessionFactory를 싱글톤으로 관리하고, @Transactional 메서드 진입 시 Session과 Transaction을 생성하고, 메서드 종료 시 정리해줍니다.

## EntityManager
---

> 영속성 컨텍스트에 접근하여 엔티티의 CRUD 작업을 수행하는 API(인터페이스)

### jakarta.persistence.EntityManager
> **영속성 컨텍스트(persistence context)**와 상호작용하는 데 사용되는 인터페이스 <br>
> `EntityManagerFactory`로부터 인스턴스를 얻어야 하며, 연관된 영속성 유닛에 속하는 엔티티만 관리

```java
public interface EntityManager extends AutoCloseable {

    ...

}
```

### EntityManager 생성 방식

**1. 애플리케이션 관리 방식**
- EntityManagerFactory.createEntityManager()를 호출하여 생성
  - 반드시 `close()`를 명시적으로 호출하여 리소스를 정리해야 합니다.
  - 이 방식은 클라이언트에게 정리와 예외 관리의 책임을 거의 전적으로 부여하므로 오류가 발생하기 쉽습니다.
  - 더 안전한 방법으로 `runInTransaction()`과 `callInTransaction()` 메서드 사용을 권장합니다:

```java
entityManagerFactory.runInTransaction(entityManager -> {
    // 영속성 컨텍스트에서 작업 수행
    ...
});
```

**2. 컨테이너 관리 방식 (Jakarta EE 환경)**
> 의존성 주입을 통해 컨테이너가 관리하는 EntityManager를 얻을 수 있습니다.

```java
@PersistenceContext(unitName="orderMgt")
EntityManager entityManager;
```

### 리소스 로컬 트랜잭션 관리
> 영속성 유닛이 리소스 로컬 트랜잭션 관리를 사용하는 경우, `getTransaction()`으로 얻은 **`EntityTransaction`을 사용하여 트랜잭션을 관리**해야 합니다:

```java
EntityManager entityManager = entityManagerFactory.createEntityManager();
EntityTransaction transaction = entityManager.getTransaction();
try {
    transaction.begin();
    // 작업 수행
    ...
    transaction.commit();
}
catch (Exception e) {
    if (transaction.isActive()) transaction.rollback();
    throw e;
}
finally {
    entityManager.close();
}
```

**영속성 유닛**
- JPA에서 관리할 엔티티 클래스들의 묶음과 그 설정을 정의한 것
- 즉, 이 애플리케이션에서 **어떤 엔티티**들을 **어떤 데이터베이스**에 **어떻게 연결**할 것인가를 정의한 설정 단위
- `persistence.xml`에 정의

```xml
<persistence-unit name="orderMgt">
    <class>com.example.Order</class>
    <class>com.example.Customer</class>
    <properties>
        <property name="jakarta.persistence.jdbc.url" value="jdbc:mysql://localhost/mydb"/>
        <!-- 기타 설정 -->
    </properties>
</persistence-unit>
```

**리소스 로컬 트랜잭션**
> JPA에는 두 가지 트랜잭션 관리 방식이 있다:

| 방식 | 설명 |
| ---- | ---- |
| JTA (Java Transaction API) | 컨테이너(서버)가 트랜잭션을 관리. | 여러 데이터베이스에 걸친 분산 트랜잭션 가능. Jakarta EE 환경에서 주로 사용. |
| Resource-Local | 애플리케이션이 직접 트랜잭션을 관리. 단일 데이터베이스 연결에 대해서만 동작. Java SE 환경이나 Spring 등에서 주로 사용. |

```java
// 리소스 로컬 방식
EntityTransaction tx = entityManager.getTransaction();
tx.begin();
// 작업
tx.commit();
```

**Spring Data JPA 사용시 영속성 유닛과 리소스 로컬 트랜잭션**
- Spring Data JPA를 사용하면 `application.yml` 또는 `application.properties`로 설정
  - Spring Boot가 자동 설정(Auto Configuration)을 해줌

```groovy
# application.yml
spring:
  datasource:
    url: jdbc:mysql://localhost:3306/mydb
    username: root
    password: 1234
    driver-class-name: com.mysql.cj.jdbc.Driver
  jpa:
    hibernate:
      ddl-auto: update
    properties:
      hibernate:
        dialect: org.hibernate.dialect.MySQLDialect
```

- 이 설정이 곧 영속성 유닛 정의입니다.
- Spring Boot가 이를 기반으로 EntityManagerFactory를 자동 생성합니다.
- 엔티티 클래스는 @Entity 어노테이션이 붙은 클래스들을 자동 스캔하여 등록합니다.

- @Transactional로 선언적 관리
```Java
@Service
@RequiredArgsConstructor
public class OrderService {

    private final UserRepository userRepository;
    private final OrderRepository orderRepository;

    @Transactional  // 이게 begin(), commit(), rollback()을 대신함
    public void createOrder(User user, Order order) {
        userRepository.save(user);
        orderRepository.save(order);
        // 예외 발생 시 자동 롤백, 정상 종료 시 자동 커밋
    }
}
```

## Persistence Context (영속성 컨텍스트)
---

> 엔티티 인스턴스(`@Entity`가 붙은 클래스의 객체)들을 관리하고 변경을 추적하는 1차 캐시 저장소(메모리 공간)

- 각 EntityManager 인스턴스는 고유한 영속성 컨텍스트와 연관됩니다.
- 특정 영속 엔티티 식별자(엔티티 타입 + 기본 키)에 대해 최대 하나의 엔티티 인스턴스만 존재
- 영속성 컨텍스트와 연관된 엔티티 인스턴스는 **관리 객체(managed objects)**로 간주되며, 영속성 제공자의 제어 하에 명확히 정의된 생명주기를 갖습니다.

### 엔티티 생명주기 상태

| 상태 | 설명 |
| ---- | ---- |
| New (비영속) | 영속 식별자가 없고, 어떤 영속성 컨텍스트와도 연관되지 않음 |
| Managed (영속) | 영속 식별자가 있고, 현재 영속성 컨텍스트와 연관됨 |
| Detached (준영속) | 영속 식별자가 있지만, 활성 영속성 컨텍스트와 연관되지 않음 (또는 더 이상 연관되지 않음)|
| Removed (삭제) | 영속 식별자가 있고, 영속성 컨텍스트와 연관되어 있으며, 트랜잭션 커밋 시 DB에서 삭제 예정 |

### EntityManager API 주요 기능
> EntityManager API는 영속성 컨텍스트의 상태에 영향을 주거나 개별 엔티티 인스턴스의 생명주기 상태를 수정하는 작업을 수행

- `persist(Object)` : 엔티티를 영속화
- `remove(Object)` : 엔티티를 삭제 예정 상태로 변경
- `find()` : 기본 키로 엔티티 조회
- 쿼리 실행: 엔티티 타입에 대한 쿼리 수행
- `detach(Object)` : 엔티티를 영속성 컨텍스트에서 분리
- `clear()` : 영속성 컨텍스트를 완전히 비우고 모든 엔티티를 분리
- `merge()` : 준영속 인스턴스의 상태를 동일한 영속 식별자를 가진 관리 인스턴스에 병합

※ 참고: 명시적인 "update" 작업은 없습니다. 엔티티는 관리 객체이므로, 활성 영속성 컨텍스트와 연관되어 있는 한 영속 필드 및 속성의 수정이 자동으로 감지됩니다.

### 플러시(Flush) 메커니즘
> Flush : 영속성 컨텍스트의 변경 내용을 DB에 SQL로 전송하는 것 (단, 커밋은 아님)
> 영속성 컨텍스트와 연관된 엔티티 상태 수정은 **즉시 DB와 동기화되지 않습니다.**
> 동기화는 **플러시(flush) 과정에서 발생**합니다.

```
[영속성 컨텍스트]  --flush-->  [DB로 SQL 전송]  --commit-->  [DB 확정]
   (메모리)                    (SQL 실행)                  (트랜잭션 완료)
```

| 플러시 모드 | 동작 |
| --------- | --- |
| FlushModeType.COMMIT | 트랜잭션 커밋 전에 플러시 |
| FlushModeType.AUTO (기본값) | 커밋 전 + 플러시되지 않은 수정 사항의 영향을 받을 쿼리 실행 전에도 플러시 |

**예시**

```java
@Transactional
public void example() {
    Member member = new Member("홍길동");
    em.persist(member);  // ① 영속성 컨텍스트에만 저장 (DB에 INSERT 아직 안 함)

    // ② 이 시점에 조회하면?
    List<Member> members = em.createQuery("SELECT m FROM Member m", Member.class)
                             .getResultList();
}
```

- AUTO 모드 (기본)

```
① persist() → 영속성 컨텍스트에 저장
② 쿼리 실행 직전 → 자동 flush → INSERT 실행
③ SELECT 실행 → "홍길동" 조회됨
```

- COMMIT 모드

```
① persist() → 영속성 컨텍스트에 저장
② 쿼리 실행 → flush 안 함 → INSERT 안 됨
③ SELECT 실행 → "홍길동" 조회 안됨 (아직 DB에 없음)
④ 커밋 시점 → flush → INSERT 실행
```

```java
@Transactional
public void example() {
    // 1. 새 멤버 저장
    Member member = new Member("홍길동");
    em.persist(member);
    // 이 시점: 영속성 컨텍스트에만 있음, DB에는 아직 없음

    // 2. 이름 변경
    member.setName("김철수");
    // 이 시점: 변경 감지됨, 하지만 UPDATE SQL 아직 안 나감

    // 3. JPQL 쿼리 실행
    List<Member> result = em.createQuery("SELECT m FROM Member m").getResultList();
    // AUTO 모드: 쿼리 직전에 flush!
    // → INSERT INTO member (name) VALUES ('김철수') 실행
    // → SELECT * FROM member 실행
    // → 결과에 "김철수" 포함됨

}  // 트랜잭션 종료 → commit
```

```java
@Transactional
public void test() {
    Member member = new Member("홍길동");
    em.persist(member);

    System.out.println("=== Foo 조회 전 ===");
    List<Foo> foos = em.createQuery("SELECT f FROM Foo f", Foo.class)
                       .getResultList();
    System.out.println("=== Foo 조회 후 ===");
}

// 콘솔 출력 (Hibernate):
// === Foo 조회 전 ===
// SELECT f FROM Foo f  ← INSERT 없이 바로 SELECT
// === Foo 조회 후 ===
// (커밋 시점에 INSERT 실행)
```

### 잠금(Locking)
> 영속성 컨텍스트는 특정 시점에 엔티티 인스턴스에 대해 낙관적(optimistic) 또는 비관적(pessimistic) 잠금을 보유할 수 있습니다.

- 명시적 LockModeType을 받는 메서드:
  - `lock(Object, LockModeType)`
  - `refresh(Object, LockModeType)`
  - `find(Class, Object, LockModeType)`

### 캐시 상호작용
- 영속성 컨텍스트(1차 캐시)와 2차 캐시 간의 상호작용은 다음 메서드로 제어할 수 있습니다:
  - `setCacheRetrieveMode(CacheRetrieveMode)`
  - `setCacheStoreMode(CacheStoreMode)`


### 코드로 살펴보는 영속성 컨텍스트
> ex : `EntityManager.persist()` 호출시 흐름

```
EntityManager.persist(user)
    ↓
SessionImpl.persist(user)          // Hibernate의 EntityManager 구현체
    ↓
DefaultPersistEventListener.onPersist()
    ↓
StatefulPersistenceContext.addEntity(entityKey, user)  // 여기서 Map에 저장!
```

```java
public class StatefulPersistenceContext implements PersistenceContext {
    private static final CoreMessageLogger LOG = (CoreMessageLogger)Logger.getMessageLogger(CoreMessageLogger.class, StatefulPersistenceContext.class.getName());
    private static final int INIT_COLL_SIZE = 8;
    private final SharedSessionContractImplementor session;
    private EntityEntryContext entityEntryContext;
    private HashMap<EntityKey, EntityHolderImpl> entitiesByKey;

    ...

    private Map<EntityKey, EntityHolderImpl> getOrInitializeEntitiesByKey() {
        if (this.entitiesByKey == null) {
            this.entitiesByKey = CollectionHelper.mapOfSize(8);
        }

        return this.entitiesByKey;
    }

    public void addEntity(EntityKey key, Object entity) {
        this.addEntityHolder(key, entity);
    }

    public EntityHolder addEntityHolder(EntityKey key, Object entity) {
        Map<EntityKey, EntityHolderImpl> entityHolderMap = this.getOrInitializeEntitiesByKey();
        EntityHolderImpl oldHolder = (EntityHolderImpl)entityHolderMap.get(key);
        EntityHolderImpl holder;
        if (oldHolder != null) {
            oldHolder.entity = entity;
            holder = oldHolder;
        } else {
            entityHolderMap.put(key, holder = StatefulPersistenceContext.EntityHolderImpl.forEntity(key, key.getPersister(), entity));
        }

        holder.state = StatefulPersistenceContext.EntityHolderState.INITIALIZED;
        BatchFetchQueue fetchQueue = this.batchFetchQueue;
        if (fetchQueue != null) {
            fetchQueue.removeBatchLoadableEntityKey(key);
        }

        return holder;
    }

    ...
}
```

```java
public final class EntityKey implements Serializable {
    private final @UnknownKeyFor @NonNull @Initialized Object identifier;
    private final @UnknownKeyFor @NonNull @Initialized int hashCode;
    private final @UnknownKeyFor @NonNull @Initialized EntityPersister persister;

    ...

}
```

**요약**

```
SessionImpl (EntityManager 구현체)
    │
    └── StatefulPersistenceContext (영속성 컨텍스트 구현체)
            │
            └── Map<EntityKey, Object> entitiesByKey  ← 이게 1차 캐시!
                    │
                    ├── Key: EntityKey(User, 1L)
                    │   Value: User(id=1, name="홍길동")
                    │
                    ├── Key: EntityKey(User, 2L)
                    │   Value: User(id=2, name="김철수")
                    │
                    └── Key: EntityKey(Order, 100L)
                        Value: Order(id=100, ...)
```

## 참고자료
- [https://jakarta.ee/specifications/persistence/3.2/apidocs/jakarta.persistence/jakarta/persistence/entitymanager](https://jakarta.ee/specifications/persistence/3.2/apidocs/jakarta.persistence/jakarta/persistence/entitymanager)
- [https://docs.hibernate.org/orm/6.6/userguide/html_single/](https://docs.hibernate.org/orm/6.6/userguide/html_single/)
- [https://docs.hibernate.org/stable/entitymanager/reference/en/html_single/#d0e61](https://docs.hibernate.org/stable/entitymanager/reference/en/html_single/#d0e61)
