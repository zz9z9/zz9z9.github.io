근데 sql을 모아놨다가 한번에 flush하면 어떤 장점이 있는거야 ?

좋은 질문이다.
이건 **write-behind(지연 쓰기)**의 진짜 존재 이유를 묻는 거라서 핵심만 정확히 짚어볼게.

결론 한 줄

SQL을 모아서 flush하는 이유는
“DB 왕복 최소화 + 불필요한 SQL 제거 + 일관된 트랜잭션 처리”
이 세 가지 때문이다.

1️⃣ DB 왕복(Round-trip) 감소
즉시 실행 방식
em.persist(a);  // INSERT 즉시
em.persist(b);  // INSERT 즉시
em.persist(c);  // INSERT 즉시


→ DB 왕복 3번

write-behind + flush
em.persist(a);
em.persist(b);
em.persist(c);
// flush 시점에 한 번에 실행


→ DB 왕복 1번

👉 OLTP에서는 이 차이가 큼

2️⃣ 불필요한 SQL 제거 (진짜 핵심)

이게 가장 중요한 장점이다.

예: 같은 엔티티를 여러 번 수정
Order o = em.find(Order.class, 1L);

o.changeStatus("READY");
o.changeStatus("PAID");
o.changeStatus("DONE");

즉시 실행 방식이라면
UPDATE ... status='READY'
UPDATE ... status='PAID'
UPDATE ... status='DONE'


→ 쓸데없는 UPDATE 2번

write-behind + dirty checking

flush 시점:

UPDATE ... status='DONE'


👉 최종 상태만 반영

이게 write-behind의 진짜 가치다.

3️⃣ 트랜잭션 단위 일관성

write-behind 구조:

객체 상태 변경
→ 메모리에 누적
→ 트랜잭션 끝에서 한 번에 DB 반영


장점:

부분 반영 없음

중간 실패 시:

DB에는 아무것도 안 들어감

ACID 보장에 유리

4️⃣ JDBC batching과 결합 가능

flush 시점에:

INSERT 여러 개

UPDATE 여러 개

→ Hibernate가 JDBC batch로 묶음

즉:

write-behind
+ batch
  = 네트워크/파싱 비용 최소화

5️⃣ 연관관계 처리 단순화
order.addItem(item1);
order.addItem(item2);


flush 시:

FK 순서 자동 정렬

INSERT 순서 자동 처리

👉 개발자가 SQL 순서 고민 안 해도 됨

6️⃣ 그런데 왜 배치에서는 단점이 되냐

여기가 중요하다.

write-behind는 OLTP 최적화다.

배치에서는:

이미 어떤 SQL 나갈지 명확

불필요한 UPDATE 거의 없음

오히려:

엔티티 N개 메모리에 누적
→ flush 시 메모리/GC 부담
→ 성능 저하


그래서 배치에서는:

장점보다 오버헤드가 더 커짐

7️⃣ 상황별 가치 정리
OLTP

요청당 SQL 수 감소

중복 UPDATE 제거

개발 생산성 ↑
→ 매우 큰 장점

Batch

SQL 패턴 이미 단순

메모리 부담 ↑
→ 장점 거의 없음

최종 한 문장

write-behind는
“객체 상태 중심 OLTP”에서는 혁신이고,
“대량 데이터 처리 Batch”에서는 오히려 부담이다.
