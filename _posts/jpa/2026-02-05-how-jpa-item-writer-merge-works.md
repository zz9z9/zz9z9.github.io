---
title: 이슈 - JpaItemWriter로 엔티티 저장시, ChunkSize만큼 SELECT 쿼리 발생하는 상황
date: 2026-01-29 23:00:00 +0900
categories: [JPA]
tags: [JPA, Hibernate]
---

## 상황
---

- 배치 애플리케이션에서 `A 테이블에서 조회 -> 가공 -> B 테이블에 저장` 흐름으로 동작하는 청크 기반의 Job이 있음
- B 테이블에 저장시 [JpaItemWriter](https://docs.spring.io/spring-batch/docs/current/api/org/springframework/batch/item/database/JpaItemWriter.html) 사용
- B 테이블에 저장하는 엔티티의 PK는 A 테이블의 PK와 동일. 즉, A 테이블에서 조회한 엔티티의 PK가 사용됨 (Assigned ID + `@Version` 없음)
- 저장시 `ChunkSize` 만큼의 `SELECT` 쿼리가 발생함

## 원인 파악
---

### 결론
- `JpaItemWriter`는 엔티티 저장시 기본적으로 EntityManager의 `merge()`를 호출 ([usePersist](https://docs.spring.io/spring-batch/docs/current/api/org/springframework/batch/item/database/JpaItemWriter.html#setUsePersist(boolean))가 `true`인 경우는 `persist()` 호출)
- `merge()`는 엔티티가 **영속성 컨텍스트에 없고, DB 존재 여부를 판단할 수 없는 경우** SELECT로 먼저 확인 후 INSERT/UPDATE를 결정할 수 있다

### SELECT가 발생하는 대표적인 상황
- assigned id
- version 없음
- 영속성 컨텍스트에 없음

```java
@Entity
@Table(name = "orders")
public class Order {

    @Id
    private String id;   // ← assigned id

    private String status;

    // @Version 없음

    protected Order() {}

    public Order(String id, String status) {
        this.id = id;
        this.status = status;
    }

    public void changeStatus(String status) {
        this.status = status;
    }
}
```

```java
@Transactional
public void detachedMerge(EntityManager em) {

    // 이미 DB에 존재하는 엔티티 조회
    Order managed = em.find(Order.class, "ORD-1");

    // 영속성 컨텍스트 비움 → detached 상태
    em.clear();

    // detached 객체 수정
    managed.changeStatus("DONE");

    // 다시 merge
    em.merge(managed);  // ← 여기서 SELECT 가능
}
```

### SELECT가 발생하지 않는 대표적인 상황

**이미 영속성 컨텍스트에 있음**

```java
@Transactional
public void mergeWithoutSelect(EntityManager em) {

  // 이미 조회됨 → 영속 상태
  Order managed = em.find(Order.class, "ORD-1");

  // 값 변경
  managed.changeStatus("DONE");

  // merge 호출
  em.merge(managed);
}
```

**version 기반**

```java
@Entity
public class Order {

  @Id
  private String id;

  @Version
  private Long version;

  private String status;

  protected Order() {}

  public Order(String id, String status) {
    this.id = id;
    this.status = status;
  }
}
```

```java
@Transactional
public void mergeNewEntity(EntityManager em) {
  // version == null → Hibernate가 "무조건 새 엔티티"라고 판단 가능
  Order order = new Order("ORD-2", "READY");

  // merge 호출 (설명 목적, 실제로는 새 엔티티이므로 persist()가 더 자연스럽다.)
  // - DB 존재 여부를 version으로 판단 가능
  // - SELECT 없이 바로 INSERT 수행됨
  // - 즉, 이 케이스에서는 merge라도 SELECT 발생하지 않음
  em.merge(order);
}

```

**generated id 전략**

```java
@Entity
public class Order {

    @Id
    @GeneratedValue(strategy = GenerationType.SEQUENCE) // 또는 IDENTITY, AUTO
    private Long id;

    private String status;
}
```

```java
@Transactional
public void mergeGeneratedId(EntityManager em) {
  // id == null → Hibernate가 새 엔티티로 확정 가능
  Order order = new Order();
  order.changeStatus("READY");

  // merge 호출 (설명 목적, 실제로는 새 엔티티이므로 persist()가 더 자연스럽다.)
  // - ID null만으로 unsaved 판단 가능
  // - SELECT 없이 바로 INSERT 수행
  // - 따라서 이 케이스도 SELECT 발생하지 않음
  em.merge(order);
}

```

## Assigned ID + @Version이 없는 엔티티 저장시 코드 흐름 살펴보기
---

```
org.springframework.batch.item.database.JpaItemWriter
└── entityManger.merge()
│
▼
org.hibernate.internal.SessionImpl
└── merge()
└── fireMerge()
│
▼
org.hibernate.event.internal.DefaultMergeEventListener
└── onMerge(MergeEvent)
└── onMerge(MergeEvent, MergeContext)
└── doMerge()
└── merge()
│
├── EntityState 판단 (DETACHED / TRANSIENT / PERSISTENT)
│
▼
└── entityIsDetached()
│
▼
source.get(entityName, id)  ⚠️ SELECT 발생!
│
├── 결과 없음 → entityIsTransient() → INSERT
└── 결과 있음 → copyValues() → UPDATE
```

**1단계 : `entityManger.merge()`**

```java
// org.springframework.batch.item.database.JpaItemWriter
protected void doWrite(EntityManager entityManager, Chunk<? extends T> items) {
    if (logger.isDebugEnabled()) {
        logger.debug("Writing to JPA with " + items.size() + " items.");
    }

    if (!items.isEmpty()) {
        long addedToContextCount = 0L;
        Chunk.ChunkIterator var5 = items.iterator();

        while(var5.hasNext()) {
            T item = (T)var5.next();
            if (!entityManager.contains(item)) {
                if (this.usePersist) {
                    entityManager.persist(item);
                } else {
                    entityManager.merge(item);
                }

                ++addedToContextCount;
            }
        }

        ...
    }

}
```

**2단계 : `merge() 진입점`**

```java
// org.hibernate.internal.SessionImpl
public <T> T merge(T object) throws HibernateException {
  this.checkOpen();
  return this.fireMerge(new MergeEvent((String) null, object, this));
}

private Object fireMerge(MergeEvent event) {
  // ...
  this.fastSessionServices.eventListenerGroup_MERGE
    .fireEventOnEachListener(event, MergeEventListener::onMerge);
  // ...
  return event.getResult();
}

```

**3단계 : `MergeEventListener` 호출**

```java
// org.hibernate.event.internal.DefaultMergeEventListener
public void onMerge(MergeEvent event) throws HibernateException {
  EventSource session = event.getSession();

  EntityCopyObserver entityCopyObserver = this.createEntityCopyObserver(session);
  MergeContext mergeContext = new MergeContext(session, entityCopyObserver);

  try {
    // 실제 merge 처리 진입
    this.onMerge(event, mergeContext);

    entityCopyObserver.topLevelMergeComplete(session);

  } finally {
    entityCopyObserver.clear();
    mergeContext.clear();
  }
}

public void onMerge(MergeEvent event, MergeContext copiedAlready) throws HibernateException {

  Object original = event.getOriginal();

  if (original != null) {
    // proxy 체크 등 선행 처리 (생략된 부분)
    this.doMerge(event, copiedAlready, original);
  }
}

```

**4단계 : EntityState 판단**

```java
// org.hibernate.event.internal.DefaultMergeEventListener
private void merge(MergeEvent event, MergeContext copiedAlready, Object entity) {
EventSource source = event.getSession();

    // org.hibernate.engine.spi.PersistenceContext
    PersistenceContext persistenceContext = source.getPersistenceContextInternal();

    // org.hibernate.engine.spi.EntityEntry - 1차 캐시에서 조회
    EntityEntry entry = persistenceContext.getEntry(entity);

    EntityState entityState;

    if (entry == null) {
        // 1차 캐시에 없음
        // org.hibernate.persister.entity.EntityPersister
        EntityPersister persister = source.getEntityPersister(event.getEntityName(), entity);
        originalId = persister.getIdentifier(entity, copiedAlready);

        if (originalId != null) {
            // ID가 있으면 EntityKey 생성 후 다시 확인
            // org.hibernate.engine.spi.EntityKey
            EntityKey entityKey = source.generateEntityKey(originalId, persister);
            Object managedEntity = persistenceContext.getEntity(entityKey);
            entry = persistenceContext.getEntry(managedEntity);

            if (entry != null) {
                entityState = EntityState.DETACHED;
            } else {
                // org.hibernate.event.internal.EntityState
                entityState = EntityState.getEntityState(entity, event.getEntityName(), entry, source, false);
            }
        }
    }

    // EntityState에 따른 분기
    switch (entityState) {
        case DETACHED:
            this.entityIsDetached(event, copiedId, originalId, copiedAlready);  // ⚠️ SELECT 발생
            break;
        case TRANSIENT:
            this.entityIsTransient(event, copiedId, copiedAlready);  // SELECT 없이 INSERT
            break;
        case PERSISTENT:
            this.entityIsPersistent(event, copiedAlready);
            break;
    }
}
```

- `DETACHED`로 판별되는 이유

```java
// org.hibernate.event.internal.EntityState#getEntityState
public static EntityState getEntityState(Object entity, String entityName, EntityEntry entry, SessionImplementor source, Boolean assumedUnsaved) {

    // 영속성 컨텍스트에 EntityEntry 존재 여부 확인
    if (entry != null) {
        // → 이미 영속 상태 (managed)
        if (entry.getStatus() != Status.DELETED) {
            return PERSISTENT;
        }
        return DELETED;
    }

    // Hibernate가 'unsaved(= TRANSIENT)' 여부를 먼저 판단 시도
    // 핵심 메서드:
    // ForeignKeys.isTransient(...)
    //
    // 여기서 보는 것:
    // - @Version 값
    // - unsaved-value 설정
    // - identifier generator 전략
    // - interceptor
    //
    // assigned id + @Version 없음이면
    // → TRANSIENT라고 확정할 근거가 없음
    if (ForeignKeys.isTransient(entityName, entity, assumedUnsaved, source)) {
        // → "새 엔티티"로 확정 가능한 경우만 여기로 들어옴
        // (예: version == null, id == null 등)
        return TRANSIENT;
    }

    //  삭제된 엔티티 키인지 추가 확인 (특수 케이스)
    final PersistenceContext persistenceContext = source.getPersistenceContextInternal();
    if (persistenceContext.containsDeletedUnloadedEntityKeys()) {

        final EntityPersister entityPersister = source.getEntityPersister(entityName, entity);

        // assigned id이므로 identifier는 null이 아님
        final Object identifier = entityPersister.getIdentifier(entity, source);

        final EntityKey entityKey = source.generateEntityKey(identifier, entityPersister);

        // "삭제된 상태"로 표시된 엔티티인지 확인
        if (persistenceContext.containsDeletedUnloadedEntityKey(entityKey)) {
            return EntityState.DELETED;
        }
    }


    // - PC에 없음
    // - TRANSIENT라고 확정 못함
    // - 삭제 상태도 아님
    //
    // ⇒ Hibernate 결론:
    //     "DB에는 존재하는 DETACHED 엔티티일 가능성이 가장 높다"
    return DETACHED;
}

```

**5단계: SELECT 발생 지점 (DETACHED 처리)**

```java
// org.hibernate.event.internal.DefaultMergeEventListener
protected void entityIsDetached(MergeEvent event, Object copiedId, Object originalId, MergeContext copyCache) {
    LOG.trace("Merging detached instance");

    Object entity = event.getEntity();

    // org.hibernate.event.spi.EventSource
    EventSource source = event.getSession();

    // org.hibernate.persister.entity.EntityPersister
    EntityPersister persister = source.getEntityPersister(event.getEntityName(), entity);

    Object clonedIdentifier = persister.getIdentifierType().deepCopy(originalId, event.getFactory());

    // ⚠️️ SELECT 발생 지점
    // org.hibernate.engine.spi.LoadQueryInfluencers
    Object result = source.getLoadQueryInfluencers()
        .fromInternalFetchProfile(CascadingFetchProfile.MERGE, () -> {
            return source.get(entityName, clonedIdentifier);  // DB 조회!
        });

    if (result == null) {
        // DB에 없음
        // → TRANSIENT 경로로 전환 (INSERT 대상 등록)
        // → 실제 INSERT SQL은 flush 시점에 실행됨
        LOG.trace("Detached instance not found in database");
        this.entityIsTransient(event, clonedIdentifier, copyCache);
    } else {
        // DB에 있음
        // → 기존 managed 엔티티에 값 복사 (UPDATE 대상 준비)
        // → 실제 UPDATE SQL은 flush 시점의 dirty checking 시 실행됨
        copyCache.put(entity, result, true);
        this.copyValues(persister, entity, target, source, copyCache);
        event.setResult(result);
    }
}
```

