---
title: JPA/Hibernate ID 생성 전략
date: 2026-01-29 23:00:00 +0900
categories: [지식 더하기, 이론, JPA]
tags: [JPA, Hibernate]
---

## @GeneratedValue
---

> 기본 키(primary key) 값의 생성 전략을 지정하는 데 사용 <br>
> 즉, 데이터베이스에 새 레코드를 삽입할 때 **기본 키 값을 자동으로 생성하는 방법**을 지정

- `@GeneratedValue`는 `@Id`와 함께 엔티티 또는 매핑된 슈퍼클래스의 기본 키 속성이나 필드에 적용할 수 있다.
- `@GeneratedValue`는 단순 기본 키(단일 컬럼으로 구성된 PK)에 대해서만 지원된다.
  - 파생 기본 키(`@MapsId`로 다른 엔티티로부터 파생된 PK)에 대한 `@GeneratedValue` 사용은 지원되지 않는다.

### 생성 전략

| 전략 | 설명 |
|------|------|
| `AUTO` | JPA 구현체가 적절한 전략을 자동 선택 |
| `IDENTITY` | DB의 auto_increment 사용 (MySQL 등) |
| `SEQUENCE` | DB 시퀀스 사용 (Oracle, PostgreSQL 등) |
| `TABLE` | 별도의 키 생성 테이블 사용 |

```java
// 예제 1: 시퀀스 전략
@Id
@GeneratedValue(strategy=SEQUENCE, generator="CUST_SEQ")
@Column(name="CUST_ID")
public Long getId() { return id; }
// → "CUST_SEQ"라는 시퀀스로 ID 생성

// 예제 2: 테이블 전략
@Id
@GeneratedValue(strategy=TABLE, generator="CUST_GEN")
@Column(name="CUST_ID")
Long id;
// → "CUST_GEN"이라는 키 생성 테이블로 ID 생성
```

## @MappedSuperclass
---

> **공통 필드를 상속**시키기 위한 부모 클래스 <br>
> 이 클래스 자체는 테이블로 생성되지 않고, 자식 엔티티들이 필드를 물려받는다.

- `BaseEntity`는 테이블이 생성되지 않음
- 각 자식 엔티티가 `id` 필드와 `@GeneratedValue` 설정을 그대로 상속
- 공통 필드(id, 생성일, 수정일 등)를 한 곳에서 관리할 수 있어 코드 중복 제거

```java
// 매핑된 슈퍼클래스 (테이블로 생성되지 않음)
@MappedSuperclass
public abstract class BaseEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;  // ← 여기에 @GeneratedValue 적용

    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;

    // getter, setter...
}
```

```java
// 자식 엔티티 1
@Entity
@Table(name = "users")
public class User extends BaseEntity {
// id, createdAt, updatedAt 필드를 상속받음

    private String username;
    private String email;
}
```

```java
// 자식 엔티티 2
@Entity
@Table(name = "products")
public class Product extends BaseEntity {
// id, createdAt, updatedAt 필드를 상속받음

    private String name;
    private int price;
}
```

## @MapsId 파생 기본 키
---

### 예시
> User와 UserProfile이 1:1 관계이고, UserProfile의 PK가 User의 PK를 그대로 사용

```java
@Entity
public class User {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;  // PK 자동 생성

    private String username;

    @OneToOne(mappedBy = "user", cascade = CascadeType.ALL)
    private UserProfile profile;
}
```

```java
@Entity
public class UserProfile {
@Id
private Long id;  // User의 id를 그대로 사용 (자동 생성 X)

    @OneToOne
    @MapsId  // ← User의 PK를 이 엔티티의 PK로 매핑
    @JoinColumn(name = "id")
    private User user;

    private String bio;
    private String profileImageUrl;
}
```

**결과 테이블**

| users | | user_profile | |
|-------|------|--------------|------|
| **id (PK)** | username | **id (PK, FK)** | bio |
| 1 | "kim" | 1 | "안녕하세요" |
| 2 | "lee" | 2 | "반갑습니다" |

→ `UserProfile.id`는 항상 `User.id`와 **동일한 값**

### 왜 @GeneratedValue를 사용할 수 없을까 ?
> 파생 기본 키는 **이미 값이 정해져 있으므로** 새로 생성할 필요가 없고, 생성하면 안됨

```java
// 이렇게 하면 안 됨
@Entity
public class UserProfile {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)  // 충돌!
    private Long id;

    @OneToOne
    @MapsId
    private User user;
}
```

- @GeneratedValue: "내가 새 값 만들게!" (예: 100)
- @MapsId:         "User의 id 값 써!" (예: 1)

→ 둘 다 적용하면: id가 100이어야 할지, 1이어야 할지 판단할 수 없음

| | @GeneratedValue | @MapsId |
|---|---|---|
| **값의 출처** | DB가 자동 생성 | 연관된 엔티티(User)로부터 복사 |
| **결정 시점** | INSERT 시 DB가 결정 | 연관 관계 설정 시 결정 |


### 올바른 사용법

```java
@Entity
public class UserProfile {
    @Id  // @GeneratedValue 없이 @Id만!
    private Long id;

    @OneToOne
    @MapsId  // User.id 값이 자동으로 이 엔티티의 id가 됨
    @JoinColumn(name = "id")
    private User user;

}
```

```java
// 사용 예시
User user = new User();
user.setUsername("kim");
// user를 저장하면 id = 1 자동 생성

UserProfile profile = new UserProfile();
profile.setUser(user);  // 이 순간 profile.id도 1이 됨
profile.setBio("안녕하세요");
```

## ID 생성 전략 관련 Hibernate 코드
---

### 주요 클래스

**1. 전략 결정 및 생성기 선택**
- `org.hibernate.id.factory.internal.StandardIdentifierGeneratorFactory`
- `org.hibernate.id.IdentifierGenerator` (인터페이스)

**2. 각 전략별 구현 클래스**

| 전략 | 구현 클래스 |
|------|-------------|
| `IDENTITY` | `org.hibernate.id.IdentityGenerator` |
| `SEQUENCE` | `org.hibernate.id.enhanced.SequenceStyleGenerator` |
| `TABLE` | `org.hibernate.id.enhanced.TableGenerator` |
| `AUTO` | 위 중 하나를 자동 선택 |

### 예시: IdentityGenerator 핵심 코드
```java
// org.hibernate.id.IdentityGenerator (간략화)
public class IdentityGenerator implements IdentifierGenerator {

    @Override
    public Object generate(SharedSessionContractImplementor session, Object object) {
        // IDENTITY 전략은 DB가 값을 생성하므로
        // INSERT 후 생성된 값을 가져옴
        return IdentifierGeneratorHelper.POST_INSERT_INDICATOR;
    }
}
```

## `SimpleJpaRepository.save()`부터 ID 생성까지 흐름
---

### 전체 흐름 개요

```
SimpleJpaRepository.save()
          ↓
EntityManager.persist()
          ↓
SessionImpl.persist()
          ↓
DefaultPersistEventListener
          ↓
AbstractSaveEventListener.saveWithGeneratedId()
          ↓
IdentifierGenerator.generate()
          ↓
INSERT 실행 & ID 반환
```

### 1. SimpleJpaRepository.save()
> Spring Data JPA의 진입점. 새 엔티티인지 판단 후 persist 또는 merge 호출

```java
// org.springframework.data.jpa.repository.support.SimpleJpaRepository
@Transactional
@Override
public <S extends T> S save(S entity) {

    Assert.notNull(entity, "Entity must not be null");

    if (entityInformation.isNew(entity)) {
        // 새 엔티티면 persist
        entityManager.persist(entity);
        return entity;
    } else {
        // 기존 엔티티면 merge
        return entityManager.merge(entity);
    }
}
```

### 2. EntityManager.persist()
> Hibernate Session 구현체. 이벤트 기반으로 persist 처리를 리스너에게 위임

```java
// org.hibernate.internal.SessionImpl
@Override
public void persist(Object object) {
    checkOpen();
    firePersist(new PersistEvent(null, object, this));
}
```

```java
private void firePersist(PersistEvent event) {
    // 이벤트 리스너에게 위임
    fastSessionServices.eventListenerGroup_PERSIST.fireEventOnEachListener(event, PersistEventListener::onPersist);
}
```

**※ Hibernate에서의 이벤트**
> Session 내부에서 발생하는 영속성 행위(persist, merge, delete …)를 **여러 리스너에게 위임**하기 위한 구조적 패턴

- `persist()` 시점에 해야 할 일들:
  - transient → persistent 상태 전이
  - identifier 생성 전략 처리
  - 1차 캐시에 엔티티 등록
  - cascade persist
  - entity 상태 검사
  - Interceptor, Listener 개입
  - flush 시점 작업 준비

- 이걸 `if-else` 덩어리로 `SessionImpl` 안에 작성하면 확장성, 유지보수성이 매우 떨어짐
- 그래서 Hibernate는:
  - “행위 = 이벤트”
  - “행위에 반응하는 로직 = 이벤트 리스너” 구조를 택함.


### 3. DefaultPersistEventListener
> persist 이벤트 처리. 엔티티 상태(TRANSIENT, DETACHED 등)에 따라 분기

```java
// org.hibernate.event.internal.DefaultPersistEventListener
@Override
public void onPersist(PersistEvent event) throws HibernateException {
    onPersist(event, IdentityHashMap.newInstance(10));
}

@Override
public void onPersist(PersistEvent event, PersistContext createdAlready) {
final Object object = event.getObject();

    // 엔티티 상태 확인
    final EntityEntry entityEntry = event.getSession()
        .getPersistenceContextInternal()
        .getEntry(object);

    EntityState entityState = EntityState.getEntityState(object, ...);

    switch (entityState) {
        case TRANSIENT:
            // 새 엔티티 → 저장 처리
            entityIsTransient(event, createdAlready);
            break;
        // ... 다른 상태들
    }
}

protected void entityIsTransient(PersistEvent event, PersistContext createdAlready) {
    // AbstractSaveEventListener의 메서드 호출
    saveWithGeneratedId(...);
}
```
- Entity 상태
> [https://docs.hibernate.org/orm/6.1/javadocs/org/hibernate/event/internal/EntityState.html](https://docs.hibernate.org/orm/6.1/javadocs/org/hibernate/event/internal/EntityState.html)

| Hibernate  | JPA      |
| ---------- | -------- |
| TRANSIENT  | New      |
| PERSISTENT | Managed  |
| DETACHED   | Detached |
| DELETED    | Removed  |

### 4. AbstractSaveEventListener.saveWithGeneratedId()
> ID 생성기를 통해 ID를 생성하고 저장 수행

```java
// org.hibernate.event.internal.AbstractSaveEventListener
protected Object saveWithGeneratedId(Object entity, String entityName, Object anything,
EventSource source, boolean requiresImmediateIdAccess) {

    // 엔티티 메타데이터 가져오기
    EntityPersister persister = source.getEntityPersister(entityName, entity);

    // ★ ID 생성기 가져와서 ID 생성
    Object generatedId = persister.getIdentifierGenerator()
        .generate((SharedSessionContractImplementor) source, entity);

    // IDENTITY 전략인 경우 (POST_INSERT_INDICATOR 반환됨)
    if (generatedId == IdentifierGeneratorHelper.POST_INSERT_INDICATOR) {
        // INSERT 후 ID를 가져와야 함
        return performSaveWithId(entity, null, persister, ...);
    }

    // SEQUENCE, TABLE 전략인 경우 (이미 ID가 생성됨)
    return performSaveWithId(entity, generatedId, persister, ...);
}
```

### 5. IdentifierGenerator 구현체들
> 각 전략에 맞게 실제 ID 값을 생성

#### IDENTITY

```java
// org.hibernate.id.IdentityGenerator
public class IdentityGenerator implements IdentifierGenerator {

    @Override
    public Object generate(SharedSessionContractImplementor session, Object object) {
        // DB가 ID를 생성하므로 "나중에 가져올게" 표시만 반환
        return IdentifierGeneratorHelper.POST_INSERT_INDICATOR;
    }
}
```

#### SEQUENCE

```java
// org.hibernate.id.enhanced.SequenceStyleGenerator
public class SequenceStyleGenerator implements IdentifierGenerator {

    @Override
    public Object generate(SharedSessionContractImplementor session, Object object) {
        // DB 시퀀스에서 다음 값 조회
        // SELECT nextval('hibernate_sequence')
        return optimizer.generate(
            accessCallback  // 실제 시퀀스 호출
        );
    }
}
```

#### TABLE 전략

```java
// org.hibernate.id.enhanced.TableGenerator
public class TableGenerator implements IdentifierGenerator {

    @Override
    public Object generate(SharedSessionContractImplementor session, Object object) {
        // 키 생성 테이블에서 값 조회 및 업데이트
        // SELECT, UPDATE 실행
        return optimizer.generate(accessCallback);
    }
}
```

### 6. INSERT 실행 (IDENTITY 전략의 경우)
> 실제 INSERT SQL 실행 후 DB가 생성한 ID를 조회하여 반환

```java
// org.hibernate.id.insert.AbstractReturningDelegate
public Object performInsert(PreparedStatementDetails insertStatementDetails,
JdbcValueBindings jdbcValueBindings, Object entity, SharedSessionContractImplementor session) {

    // INSERT 실행
    session.getJdbcCoordinator()
        .getResultSetReturn()
        .executeUpdate(insertStatement);

    // DB에서 생성된 ID 조회
    // MySQL: SELECT LAST_INSERT_ID()
    // PostgreSQL: RETURNING id
    ResultSet rs = getInsertGeneratedIdentifierDelegate()
        .executeAndExtract(insertStatement, session);

    return rs.getLong(1);  // 생성된 ID 반환
}
```

### 7. 엔티티에 ID 설정

```java
// org.hibernate.event.internal.AbstractSaveEventListener
protected Object performSaveOrReplicate(Object entity, Object id, EntityPersister persister, ...) {

    // 생성된 ID를 엔티티에 설정
    persister.setIdentifier(entity, id, session);

    // 영속성 컨텍스트에 등록
    source.getPersistenceContextInternal()
        .addEntity(entity, Status.MANAGED, ...);
}
```

### 전략별 SQL 실행 시점 비교

```
┌─────────────┬──────────────────────────────────────────────┐
│   전략      │                실행 흐름                      │
├─────────────┼──────────────────────────────────────────────┤
│ IDENTITY    │ generate() → INSERT → SELECT LAST_INSERT_ID  │
│             │ (ID는 INSERT 후에 알 수 있음)                 │
├─────────────┼──────────────────────────────────────────────┤
│ SEQUENCE    │ SELECT nextval() → generate() → INSERT       │
│             │ (ID를 먼저 조회 후 INSERT)                    │
├─────────────┼──────────────────────────────────────────────┤
│ TABLE       │ SELECT & UPDATE → generate() → INSERT        │
│             │ (키 테이블에서 ID 확보 후 INSERT)             │
└─────────────┴──────────────────────────────────────────────┘
```

### 디버깅 브레이크포인트 추천 위치

```
1. SimpleJpaRepository.save()              // 진입점
2. SessionImpl.persist()                   // Hibernate 진입
3. AbstractSaveEventListener.saveWithGeneratedId()  // ★ 핵심
4. IdentityGenerator.generate()            // 전략별 분기
5. AbstractReturningDelegate.performInsert() // 실제 INSERT
```

## IDENTITY 전략에서 Bulk Insert가 안 되는 이유
---
> IDENTITY 전략은 **INSERT를 실행해야만 ID를 알 수 있기 때문**에, Hibernate가 batch insert를 비활성화한다.

### 1. ActionQueue에서 batch 가능 여부 판단

```java
// org.hibernate.engine.spi.ActionQueue
public void addAction(EntityInsertAction action) {

    // ★ 핵심: ID 생성 방식 확인
    if (action.isEarlyInsert()) {
        // IDENTITY 전략 → 즉시 INSERT 실행해야 함
        executeInsertNow(action);
    } else {
        // SEQUENCE, TABLE → 나중에 batch로 모아서 실행 가능
        addToInsertQueue(action);
    }
}
```

### 2. isEarlyInsert() 판단 로직

```java
// org.hibernate.action.internal.EntityInsertAction
public boolean isEarlyInsert() {
  // ID 생성기가 POST_INSERT 타입인지 확인
  return persister.getIdentifierGenerator() instanceof PostInsertIdentifierGenerator;
}
```

```java
// org.hibernate.id.IdentityGenerator
public class IdentityGenerator implements PostInsertIdentifierGenerator {  // ← 이 인터페이스!

    // IDENTITY는 PostInsertIdentifierGenerator를 구현
    // = INSERT 후에야 ID를 알 수 있다는 의미
}
```

### 3. Batch 비활성화

```java
// org.hibernate.engine.jdbc.batch.internal.BatchBuilderImpl
public Batch buildBatch(BatchKey key, JdbcCoordinator jdbcCoordinator) {

    // IDENTITY 전략이면 batch size를 1로 강제
    if (isIdentityInsert(key)) {
        return new NonBatchingBatch(key, jdbcCoordinator);
    }

    // 다른 전략은 설정된 batch size 사용
    return new BatchingBatch(key, jdbcCoordinator, batchSize);
}
```

```java
// org.hibernate.id.insert.AbstractReturningDelegate
public Object performInsert(...) {

    // IDENTITY: 각 INSERT마다 즉시 실행하고 ID 조회
    jdbcCoordinator.getResultSetReturn().executeUpdate(insertStatement);

    // 생성된 ID 즉시 조회 (이게 batch를 막는 원인)
    ResultSet rs = statement.getGeneratedKeys();
    return rs.getLong(1);
}
```

### 예시

```
┌─────────────────────────────────────────────────────────────────┐
│                    SEQUENCE 전략 (Batch 가능)                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. SELECT nextval() → ID = 1                                   │
│  2. SELECT nextval() → ID = 2                                   │
│  3. SELECT nextval() → ID = 3                                   │
│                                                                 │
│  이 시점에 모든 엔티티의 ID를 알고 있음!                          │
│  → 영속성 컨텍스트에 등록 가능                                    │
│  → 연관관계 설정 가능                                            │
│                                                                 │
│  4. INSERT 3개를 한 번에 batch 실행                              │
│     INSERT INTO user (id, name) VALUES (1, 'A'), (2, 'B')...    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                    IDENTITY 전략 (Batch 불가)                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. INSERT user1 → ID = ? (모름)                                │
│                                                                 │
│     문제: ID를 모르면...                                      │
│        - 영속성 컨텍스트에 등록 불가 (1차 캐시 key가 없음)        │
│        - 연관관계 FK 설정 불가                                   │
│        - 다음 엔티티 처리 불가                                   │
│                                                                 │
│     → INSERT 실행하고 LAST_INSERT_ID() 조회해야 함               │
│     → 그래야 다음 단계 진행 가능                                 │
│                                                                 │
│  2. INSERT user2 → 마찬가지로 즉시 실행 필요                     │
│  3. INSERT user3 → 마찬가지                                     │
│                                                                 │
│  결과: 각각 개별 INSERT 실행 (batch 불가능)                      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 영속성 컨텍스트 등록 시 ID 필요

```java
// org.hibernate.engine.internal.StatefulPersistenceContext
public void addEntity(EntityKey key, Object entity) {
    // ★ EntityKey 생성에 ID가 필수!
    // ID가 없으면 1차 캐시에 등록 자체가 불가능
    entitiesByKey.put(key, entity);
}
```

```java
// org.hibernate.engine.spi.EntityKey
public EntityKey(Object id, EntityPersister persister) {
    this.identifier = id;  // ← ID가 반드시 있어야 함
    this.persister = persister;
}
```

### 연관관계에서의 문제

```java
@Entity
public class Order {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @OneToMany(mappedBy = "order", cascade = CascadeType.ALL)
    private List<OrderItem> items;
}
```

```java
@Entity
public class OrderItem {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne
    @JoinColumn(name = "order_id")
    private Order order;  // ← FK로 Order.id 필요!
}
```

```java
// 저장 시
Order order = new Order();
OrderItem item1 = new OrderItem();
OrderItem item2 = new OrderItem();
order.addItem(item1);
order.addItem(item2);

entityManager.persist(order);
```

```
1. INSERT order → ID 조회 (예: 100)
   → order.id = 100 설정
   → 영속성 컨텍스트에 등록

2. INSERT orderItem1 (order_id = 100) → ID 조회
   → Order.id를 알아야 FK 설정 가능!

3. INSERT orderItem2 (order_id = 100) → ID 조회

∴ Order INSERT가 먼저 완료되어야 OrderItem INSERT 가능
∴ Batch로 묶을 수 없음
```

### 정리

| 전략 | ID 획득 시점 | Batch 가능 | 이유 |
|------|-------------|----------|------|
| **IDENTITY** | INSERT 후 | X        | ID를 몰라서 영속성 컨텍스트 등록, FK 설정 불가 |
| **SEQUENCE** | INSERT 전 | O        | 미리 ID 확보 → 모아서 batch 실행 가능 |
| **TABLE** | INSERT 전 | O        | 미리 ID 확보 → 모아서 batch 실행 가능 |

**결론**: IDENTITY는 "INSERT 해봐야 ID를 안다"는 근본적 특성 때문에, Hibernate가 아무리 최적화해도 batch insert가 불가능하다.


## ※ 참고 : Hibernate 6.6 BulkInsertionCapableIdentifierGenerator
---

### IdentityGenerator (Hibernate 6.6.x)

```java
public class IdentityGenerator
implements PostInsertIdentifierGenerator,
BulkInsertionCapableIdentifierGenerator,  // ← 이게 있어서 bulk 가능?
StandardGenerator {

    public boolean referenceColumnsInSql(Dialect dialect) {
        return dialect.getIdentityColumnSupport().hasIdentityInsertKeyword();
    }

    public String[] getReferencedColumnValues(Dialect dialect) {
        return new String[]{dialect.getIdentityColumnSupport().getIdentityInsertString()};
    }

    // ... 나머지 코드
}
```

### 결론부터 말하면
1. BulkInsertionCapableIdentifierGenerator는 **HQL/JPQL의 `INSERT ... SELECT` 벌크 구문**을 IDENTITY 테이블에서도 사용할 수 있게 해주는 인터페이스
2. 일반적인 `persist()` 호출의 JDBC batch insert와는 **무관**
3. 따라서 IDENTITY 전략에서 `persist()` 루프의 batch insert는 **여전히 불가능**

- 즉, 여전히 일반적인 `entityManager.persist()` 루프에서는 batch insert가 안됨

### BulkInsertionCapableIdentifierGenerator 인터페이스 확인

```java
// org.hibernate.id.BulkInsertionCapableIdentifierGenerator
public interface BulkInsertionCapableIdentifierGenerator extends IdentifierGenerator {

    /**
     * SQL 구문에서 ID 컬럼을 참조해야 하는지?
     * (INSERT 구문에 ID 컬럼을 명시적으로 포함할지 여부)
     */
    boolean referenceColumnsInSql(Dialect dialect);

    /**
     * ID 컬럼에 들어갈 값 (키워드 등)
     * 예: Oracle의 "DEFAULT", SQL Server의 "DEFAULT" 등
     */
    String[] getReferencedColumnValues(Dialect dialect);
}
```

### 이 인터페이스의 실제 용도

**HQL/JPQL의 bulk insert 구문 지원**

```java
String hql = "INSERT INTO UserArchive (id, name, email) " +
"SELECT u.id, u.name, u.email FROM User u WHERE u.status = 'INACTIVE'";

entityManager.createQuery(hql).executeUpdate();
```

- 생성되는 SQL:sql

```sql
-- IDENTITY 컬럼이 있어도 bulk INSERT ... SELECT 가능하게 함
INSERT INTO user_archive (id, name, email)
SELECT id, name, email FROM user WHERE status = 'INACTIVE'
```

### 코드 분석: referenceColumnsInSql()

```java
// IdentityGenerator
public boolean referenceColumnsInSql(Dialect dialect) {
    return dialect.getIdentityColumnSupport().hasIdentityInsertKeyword();
}
```

```java
// 예: SQL Server의 IdentityColumnSupport
public class SQLServerIdentityColumnSupport extends IdentityColumnSupportImpl {

    @Override
    public boolean hasIdentityInsertKeyword() {
        return true;  // SQL Server는 IDENTITY_INSERT 키워드 있음
    }

    @Override
    public String getIdentityInsertString() {
        return "default";  // INSERT 시 'DEFAULT' 키워드 사용
    }
}
```

```java
// MySQL의 경우
public class MySQLIdentityColumnSupport extends IdentityColumnSupportImpl {

    @Override
    public boolean hasIdentityInsertKeyword() {
        return false;  // MySQL은 없음
    }
}
```

### 정리: 두 가지 "Bulk Insert"의 차이

| 구분 | JDBC Batch Insert | HQL Bulk Insert                           |
|------|-------------------|-------------------------------------------|
| **사용법** | `persist()` 여러 번  | `INSERT INTO ... SELECT`                  |
| **관련 인터페이스** | 없음 (batch 설정)     | `BulkInsertionCapableIdentifierGenerator` |
| **IDENTITY에서** | X                 | O                                         |
| **영속성 컨텍스트** | 각 엔티티 관리됨         | 관리 안 됨 (벌크 연산)                            |

```java
// JDBC Batch - IDENTITY에서 불가
for (User u : users) {
em.persist(u);  // 개별 INSERT
}
```

```java
// HQL Bulk - IDENTITY에서 가능 (BulkInsertionCapableIdentifierGenerator 덕분)
em.createQuery("INSERT INTO Archive SELECT u FROM User u").executeUpdate();
```
