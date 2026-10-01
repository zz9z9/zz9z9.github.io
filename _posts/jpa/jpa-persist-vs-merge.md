persist()

**“이건 무조건 새 엔티티다”**라고 선언하는 API

em.persist(order);


의미:

INSERT 전용

이미 DB에 있으면 예외

SELECT 절대 없음

의도가 명확함

👉 새 엔티티일 때 정석

merge()

“새 건지 기존 건지 모르겠으니 알아서 처리해줘”

em.merge(order);


의미:

INSERT 또는 UPDATE

필요하면 SELECT

반환 객체가 새로운 managed 인스턴스

비용 더 큼

의도 모호

👉 detached 재부착용 API

======


Auto Increment 성능 비교
실제 발생하는 쿼리가 동일하니 성능 역시 비슷하게 나옵니다.

1. Merge

mysql-auto_merge

2. Persist

mysql-auto_persist

둘의 수행속도가 비슷하니 Auto Increment인 경우에 써도 되지 않을까? 싶으실텐데요.

실제 Merge는 Entity 복사를 매번 수행합니다.
PersistenceContext에 존재하는 것을 반환하거나 Entity의 새 인스턴스를 만듭니다.
어쨌든 제공된 Entity에서 상태를 복사하고 관리되는 복사본을 반환합니다.
(전달한 인스턴스는 관리되지 않습니다.)

그래서 성능이 비슷하다 하더라도 신규 Entity를 생성할때는 Persist를 사용하는 것이 좋습니다.

==> https://jojoldu.tistory.com/507

====

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
=> copyValues ??
