---
title: 외부 서버 호출이 실패하면 쿠폰은 발행된 것인가 — 1인 1매 보장 설계
date: 2026-08-13 23:10:00 +0900
categories: [생각해보기, what-if]
tags: [MySQL, InnoDB, Spring, Resilience4j]
---

# 외부 호출 실패 처리 설계 — 질문으로 따라가는 정리

---

> **상황**: 우리 서버가 외부 서버를 호출해 사용자당 쿠폰을 딱 한 장 발행해야 한다.
> 그 호출에서 타임아웃이 나면 어떻게 처리할 것인가?

각 절은 실제로 던졌던 질문에서 출발한다.
**Q.** = 던진 질문 / **A. (내 답변)** = 내가 낸 답 / 그 아래가 확장·정정된 내용.

## 출발점 — 외부 호출 실패는 "실패"가 아니다

---

> 타임아웃은 **"실패"가 아니라 "상태 불명(unknown)"** 이다.

타임아웃 하나에 정반대의 두 상황이 섞여 있다.

- 요청이 상대에게 도달조차 못 함 → **미발행**
- 상대는 정상 처리했는데 응답만 유실됨 → **발행됨**

응답만으로는 이 둘을 구분할 수 없다(Two Generals Problem). 따라서 모든 설계는 "지금 판정하는 것"이 아니라 **"나중에 확인할 수 있게 만드는 것"** 에서 출발한다.

## Q1. 실패건을 언제 저장할 것인가

---

> **Q.** 실패건을 별도 저장한다고 했는데, 그 저장은 정확히 언제 하는가? 호출 직후 응답을 받기 전에 인스턴스가 죽거나 배포로 내려가면?
>
> **A. (내 답변)** 요청 전에 요청 자체를 DB에 저장하고, 호출 후 응답에 따라 처리 결과를 업데이트한다. 처리 결과가 없거나 실패인 건은 배치로 조회 API를 호출해 확인하고, 미처리면 재호출한다.

정석 패턴이 맞다. 이 구조를 **선기록 후호출**이라 부른다. 호출 의도를 먼저 커밋해 두고 별도 프로세스가 전달을 책임진다는 점에서 Transactional Outbox와 같은 계열의 아이디어다.

대신 반대 방향의 부작용이 생긴다.

> **"저장은 됐는데 실제로 요청이 나갔는지조차 모르는 PENDING 레코드"** 가 쌓인다.

호출 직후 응답을 받기 전에 인스턴스가 죽거나 배포로 내려가면 그 레코드는 영원히 PENDING으로 남는다. 그래서 다음 질문이 따라온다.

## Q2. PENDING 건을 배치가 언제 집어들 것인가

---

> **Q.** "아직 응답 대기 중인 정상 건"과 "죽어서 버려진 건"을 어떻게 구분하는가?
>
> **A. (내 답변)** `저장 시각 + connectTimeout + readTimeout + 여유시간(n초)` 이 지났는데도 PENDING이면 버려진 건으로 판단한다.

근거 있는 임계값이다. 여유시간은 GC pause, 스레드 스케줄링 지연 때문에 반드시 필요하다.

다만 **재시도 로직이 있으면 계산에 포함해야 한다.**

```
임계값 = (connectTimeout + readTimeout) × 재시도 횟수 + 백오프 시간 총합 + 여유시간
```

누락하면 앱이 아직 2차 시도 중인데 배치가 끼어들어 중복 호출이 나간다. 애플리케이션 레벨 재시도를 넣는 순간 이 값도 같이 커진다는 점을 잊기 쉽다.

## Q3. `@Transactional` 안에 외부 호출을 넣으면?

---

> **Q.** `@Transactional` 안에 `save → 외부 호출 → update`를 전부 넣으면 어떤 문제가 생기는가?
>
> **A. (내 답변 — 자원 관점)** DB 커넥션이 외부 호출 지연에 묶여 커넥션 풀이 고갈되고, 같은 DB를 쓰는 다른 요청까지 지연된다.
>
> **A. (내 답변 — 유실 관점)** API 호출 중 발생한 예외로 save된 정보가 롤백되면 추적 자체가 불가능해진다.

두 관점 모두 정확하다. 유실 쪽을 한 문장으로 조이면 이렇다.

> 롤백되면 **저장을 먼저 한 의미가 통째로 사라진다.** 호출 후 저장과 동일한 상태가 된다.

최악의 시나리오는 외부에는 쿠폰이 발행됐는데 우리 DB엔 흔적이 없는 경우다. 배치가 주울 대상 자체가 없으므로 영원히 복구되지 않는다. 자원 문제는 여기에 장애 전파(무관한 API까지 사망)를 얹는다.

### 해결 — 트랜잭션 분리

| 단계 | 내용 |
|---|---|
| 트랜잭션 A | 요청 저장 + **커밋** (여기서 확실히 끊는다) |
| 트랜잭션 밖 | 외부 호출 |
| 트랜잭션 B | 결과 update |

### ⚠️ `REQUIRES_NEW`로는 자원 문제가 해결되지 않는다

바깥 메서드가 `@Transactional`인 상태에서 저장만 `REQUIRES_NEW`로 떼어내는 방식은 **유실 문제만 해결하고 커넥션 점유 문제는 그대로 남긴다.**

Spring의 트랜잭션 매니저는 내부 트랜잭션을 시작할 때 바깥 트랜잭션을 *중단(suspend)* 시킬 뿐, 바깥이 쥐고 있던 `ConnectionHolder`를 반납하지 않는다. 즉 외부 호출이 진행되는 동안에도 바깥 트랜잭션의 커넥션은 계속 물려 있고, 내부 트랜잭션이 도는 짧은 순간에는 **요청 하나가 커넥션 2개를 점유한다.** 풀 고갈이 완화되는 게 아니라 악화된다.

> 올바른 형태는 **트랜잭션 없는 파사드**가 트랜잭션 메서드 두 개를 순서대로 호출하는 것이다.

```java
// 파사드 — @Transactional 없음
public CouponResult issue(long userId, long eventId) {
    CouponRequest req = requestService.savePending(userId, eventId); // 트랜잭션 A
    CouponResponse res = couponClient.issue(req.getIdempotencyKey()); // 트랜잭션 밖
    return requestService.markSuccess(req.getId(), res);             // 트랜잭션 B
}
```

`savePending`을 같은 클래스 안의 private/public 메서드로 두고 자기 자신이 호출하면 프록시를 타지 않아 트랜잭션이 아예 걸리지 않는다(**self-invocation 문제**). 반드시 다른 빈으로 분리해야 한다.

## Q4. "사용자당 딱 한 장"을 무엇으로 보장할 것인가

---

> **Q.** 같은 유저의 동시 요청 두 건이 들어오면 지금 설계로 막히는가?
>
> **A. (내 답변)** 사용자 ID를 유니크 키로 지정하고, `SELECT ... FOR UPDATE`로 조회해서 있으면 처리하지 않거나, save 결과에서 `DuplicateKeyException`이 나면 처리하지 않는다.

두 방법이 섞여 있는데, 하나가 명백히 낫다.

> **Q.** `SELECT ... FOR UPDATE`는 **행이 존재할 때** 그 행을 잠근다. 신규 유저라 아직 행이 없다면 무엇을 잠그는가?
>
> **A. (내 답변)** 아직 레코드가 없을 때 `FOR UPDATE` 하면 갭락이 supremum까지 걸리지 않나?

### 맞다 — 직접 확인해 보면

MySQL 8.0.46, InnoDB, `user_id`에 유니크 인덱스가 걸린 테이블로 확인했다.

REPEATABLE READ에서 존재하지 않는 값(`5000`, 기존 최댓값 `300` 초과)을 `FOR UPDATE`로 조회하면 supremum pseudo-record에 락이 잡힌다.

```
mysql> SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
mysql> BEGIN;
mysql> SELECT * FROM coupon_req WHERE user_id = 5000 FOR UPDATE;
Empty set

-- 다른 세션에서
mysql> SELECT INDEX_NAME, LOCK_TYPE, LOCK_MODE, LOCK_DATA FROM performance_schema.data_locks;
+------------+-----------+-----------+------------------------+
| INDEX_NAME | LOCK_TYPE | LOCK_MODE | LOCK_DATA              |
+------------+-----------+-----------+------------------------+
| NULL       | TABLE     | IX        | NULL                   |
| uk_user    | RECORD    | X         | supremum pseudo-record |
+------------+-----------+-----------+------------------------+
```

이 상태에서 동시 삽입은 실제로 막힌다. 그런데 **막히는 대상이 `5000`만이 아니다.**

```
-- 전혀 무관한 4700 삽입
mysql> INSERT INTO coupon_req (user_id) VALUES (4700);
ERROR 1205 (HY000): Lock wait timeout exceeded; try restarting transaction
```

### 그래도 권장하지 않는 세 가지 이유

**1. 격리 수준에 의존한다.** READ COMMITTED에서는 갭락이 비활성화된다. 같은 조회를 RC에서 하면 레코드 락이 아예 잡히지 않고, 동시 삽입이 그대로 통과한다.

```
mysql> SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
mysql> BEGIN;
mysql> SELECT * FROM coupon_req WHERE user_id = 5000 FOR UPDATE;
Empty set

-- 다른 세션에서 락 조회: IX 테이블 락 하나뿐, 레코드 락 없음
+------------+-----------+-----------+-----------+
| INDEX_NAME | LOCK_TYPE | LOCK_MODE | LOCK_DATA |
+------------+-----------+-----------+-----------+
| NULL       | TABLE     | IX        | NULL      |
+------------+-----------+-----------+-----------+

-- 그리고 삽입이 그대로 성공한다
mysql> INSERT INTO coupon_req (user_id) VALUES (5000);
Query OK, 1 row affected
```

즉 이 방식은 격리 수준 설정 하나로 **조용히 무력화된다.** 아무 에러도 나지 않고, 그냥 중복이 생긴다. RR 전제가 깔려야 성립하는 방어는 좋은 방어가 아니다.

**2. 무관한 삽입까지 막는다.** 위에서 확인했듯 `user_id = 5000` 조회가 건 갭에 `4700` 삽입이 대기한다. 트래픽이 몰릴수록 락 경합이 커진다.

**3. 데드락이 난다.** 갭락끼리는 서로 충돌하지 않으므로 두 세션이 같은 갭을 동시에 잡을 수 있다. 그 뒤 각자 insert하면 서로의 갭락을 기다리며 교착에 빠진다.

```
-- 세션 A, B가 모두 user_id = 5000을 FOR UPDATE 조회 (둘 다 성공)
-- 이후 각자 INSERT
세션 A: Query OK, 1 row affected
세션 B: ERROR 1213 (40001): Deadlock found when trying to get lock
```

### → 유니크 제약 + `DuplicateKeyException` 이 우세

- **격리 수준과 무관하게** DB 엔진이 보장한다
- 조회 왕복 1회가 사라진다
- **로직 방어가 아니라 스키마 레벨 방어** → 코드 실수로 무너지지 않는다
- 예외를 잡아 **멱등 응답**을 반환하는 형태로 마무리한다

## Q5. 유니크 키를 무엇으로 잡을 것인가

---

> **Q.** `userId` 단독 유니크가 실무에서 문제가 되는 경우는?
>
> **A. (내 답변)** 요구사항이 바뀌어서 `userId`가 중복으로 들어갈 수 있을 때 문제가 된다.

`userId` 단독 유니크는 **"이 사용자는 평생 쿠폰 1장"** 을 의미한다. 현실의 요구사항은 그렇지 않다.

- 신규가입 쿠폰 / 추석 이벤트 쿠폰 / 앱 설치 쿠폰이 각각 존재한다
- 진짜 요구사항은 보통 **"이벤트당 1인 1매"** 다
- 다음 달에 같은 이벤트를 또 열 수도 있다

`(userId, eventId)` 복합 유니크, 혹은 멱등키 컬럼 하나에 유니크를 건다.

```
idempotency_key = "coupon:{eventId}:{userId}"
```

이 키를 **그대로 외부 서버에 전달할 수 있다는 점**이 핵심이다. 우리 DB의 중복 방어와 상대 서버의 중복 방어가 같은 값을 기준으로 움직이게 된다.

## Q6. 상대가 조회 API를 안 준다면 무엇을 요구할 것인가

---

> **Q.** 상대가 조회 API를 제공하지 않는다면, 스펙 협의에서 최소한 무엇을 요구하겠는가?
>
> **A. (내 답변)** 여러 번 요청해도 결과가 같도록 멱등성 보장을 요구한다. 그러면 조회 API로 일일이 확인할 필요가 없다.

방향이 맞다. 조회 API는 "확인 후 분기" 구조라 **확인과 재호출 사이에 또 틈이 생긴다.** 확인 시점엔 미발행이었는데 그사이 이전 요청이 뒤늦게 도착해 발행될 수 있다.

멱등성이 보장되면 확인 없이 그냥 다시 쏘면 끝이므로, 배치가 단순 재시도 루프가 된다. 다만 "멱등성 보장해주세요"만으로는 부족하다. 아래 두 가지를 못박아야 한다.

### 6-1. 키를 누가 만드는가

> **Q.** 멱등키는 우리가 만드는가, 상대가 발급해 주는가?
>
> **A. (내 답변)** 키는 우리 쪽에서 만들어야 한다. 상대가 제공하면 응답을 못 받았을 때 해당 키를 알 수 없기 때문이다.

정확하다. 상대 발급 구조면 "키 발급 호출"이 또 실패할 수 있고, 그 실패는 재시도할 근거가 없어 원점으로 돌아간다. 클라이언트 생성이어야 재시도 전 구간에서 동일 키를 유지할 수 있다.

### 6-2. 중복 요청 시 응답을 어떻게 줄 것인가

> **Q.** 중복 요청에 `409 Conflict`를 주는 계약은 왜 부족한가?
>
> **A. (내 답변)** 에러 코드로 주면 별도 분기 처리 로직이 추가돼야 해서 곤란하다.

분기 추가는 사소하다. 진짜 문제는 **상태가 여전히 불명이라는 것**이다. `409`만 왔을 때 원인 후보를 나열해 보면 드러난다.

| 상황 | 처리해야 할 방향 |
|---|---|
| (1) 내 재시도 때문에 이미 발행됨 | **성공**으로 닫아야 함 |
| (2) `eventId` 재사용 등 우리 키 생성 버그 → 상대는 옛 키로 인식 | 실패 (쿠폰 안 나감) |
| (3) 어드민 수동 발행, 제휴사 등 **다른 채널**에서 이미 발행<br>(상대가 멱등키가 아닌 `(userId, eventId)`로 중복 판단하는 경우) | 확인 필요 |
| (4) 상대가 `409`를 "이벤트 종료" 등 다른 의미로도 사용 | 실패 |

`409`라는 응답만으로는 (1)과 나머지를 구분할 수 없다. 우리가 없애려던 "상태 불명"으로 되돌아온다. 게다가 에러 코드는 상대 입장에서 예외 경로라 정상 흐름보다 훨씬 덜 방어되는 계약이다.

> **올바른 계약**: 같은 멱등키로 재요청이 오면, **최초 요청과 동일한 성공 응답을 그대로 반환한다**(발행된 쿠폰 코드 포함).

응답에 담긴 쿠폰 코드가 곧 "그 키로 발행된 것이 존재한다"는 증거가 되어, 분기 자체가 사라진다. Stripe의 `Idempotency-Key` 설계가 이 형태다.

## Q7. 재시도 폭주를 어떻게 막을 것인가

---

> **Q.** 상대 서버가 계속 5xx, 배치는 5분마다, 미결 건 1만 건. 어떤 문제가 생기고 어떻게 방어하는가?
>
> **A. (내 답변)** 5분마다 계속 부하를 가중시켜 상대 서버 회복을 어렵게 만든다. 배치 job에 임계치를 두고 5xx가 임계치를 넘으면 job 실패로 종료한다. 서킷 브레이커도 생각했지만 배치는 매번 jar 실행 구조라 상태가 유지 안 될 것 같다.

이 현상이 **retry storm / thundering herd**다. 상대가 회복하려는 순간 1만 건이 다시 쏟아져 재차 붕괴한다.

**임계치 종료의 한계** — "job 실패로 끝"만으로는 다음 5분 뒤 똑같이 임계치까지 때리고 죽는다. 시도 횟수는 줄지만 0은 아니다. **실패 상태를 다음 실행까지 전달**해야 한다.

**서킷 브레이커에 대한 우려는 정확하다.** Resilience4j를 포함한 대부분의 구현이 인메모리 상태 머신이라 프로세스가 죽으면 CLOSED로 초기화된다. 다만 두 가지로 보완할 수 있다.

- **단일 배치 실행 내에서는 유효하다** — 1만 건을 도는 중 100건 연속 실패하면 나머지 9,900건은 쏘지 않고 종료한다. 사실상 임계치 종료의 개선판이다.
- **상태를 외부화한다** — Redis나 DB에 "대상 서버 OPEN, 해제 예정 시각 T"를 기록하고 배치 시작 시 확인하면 실행 간에도 유지된다.

## Q8. 특정 건만 계속 실패하면 (독성 메시지)

---

> **Q.** 9,990건은 정상 처리되는데 특정 10건만 계속 5xx라면? 실패율이 낮아 서킷은 안 열린다.
>
> **A. (내 답변)** n일 동안 처리 안 된 건은 별도 테이블로 분리하거나 운영자 알림으로 상대측 담당자 확인을 요청한다.

방향이 정석 종착지다. 그 별도 테이블이 곧 **DLQ(Dead Letter Queue)** 다.

다만 기준은 **"n일" 대신 "n회 시도 후"** 로 잡는 게 일반적이다. 시간 기준은 배치가 멈춰 있던 구간까지 카운트되어, 실제로는 한 번도 안 쏴본 건이 DLQ로 떨어질 수 있다.

시스템적으로 더 할 수 있는 것들이 있다.

1. **격리(bulkhead)** — 재시도 횟수가 많은 건과 신규 건을 다른 워커/배치로 분리한다. 독성 메시지가 정상 흐름 처리를 지연시키지 않게 한다.
2. **실패 원인 분류 저장** — 응답 코드·에러 메시지·바디를 매 시도마다 기록한다. 실무에선 대개 데이터 문제(탈퇴 회원, 종료된 이벤트, 인코딩 깨진 필드)다. 원인이 보이면 재시도가 아니라 데이터 보정으로 해결된다.
3. **재시도 불가 건 즉시 제외** — 4xx는 몇 번을 쏴도 결과가 같다. 상태 코드로 retryable / non-retryable을 나눠 재시도 횟수 낭비를 막는다.
4. **수동 재처리 창구** — 어드민에서 DLQ 조회, 개별/일괄 재시도, **강제 성공 처리**(상대측이 수동 발행해준 케이스를 닫기 위해).

## Q9. 재시도 간격을 어떻게 잡을 것인가

---

> **Q.** 1만 건을 5분마다 전부 재시도하는 게 맞는가? 방금 실패한 건과 300번 실패한 건을 같은 빈도로?
>
> **A. (내 답변)** n번 이상 재시도되면 DLQ로 빠질 테니 간격은 동일해도 되지 않나?

두 가지가 빠졌다.

### (1) 재시도가 커버하는 시간이 급감한다

최대 10회, base 5분 기준으로 계산해 보면 차이가 극단적이다.

| 방식 | 간격 | 10회 소진까지 |
|---|---|---|
| 고정 | 5분 × 10 | 50분 |
| 지수 백오프 | 5 → 10 → 20 → … → 2560분 | 약 85시간 (3.5일) |

상대 장애가 2시간만 이어져도 고정 간격이면 1만 건 전부가 복구 전에 DLQ로 떨어진다. 자동 복구 가능했던 건이 전부 수동 처리 대상이 된다. **재시도 횟수는 그대로인데 견딜 수 있는 장애 시간이 100배 늘어난다.**

다만 지수 백오프는 상한(cap)을 같이 둬야 한다. 위 표의 2560분(약 43시간)처럼 간격이 무한정 벌어지면 상대가 이미 복구됐는데도 하루 넘게 방치된다. `min(base * 2^attempts, maxInterval)` 형태로 30분~1시간쯤에서 자르는 게 보통이다.

### (2) 시도할수록 성공 확률이 낮아진다

1회차 실패는 일시적 네트워크 요동일 확률이 높고, 5회차까지 실패한 건은 구조적 문제일 확률이 높다. 실패가 누적될수록 간격을 벌려 자원을 성공 확률 높은 쪽으로 몰아주는 것이 합리적이다.

### (3) 지터(jitter)가 필수다

백오프만 있으면 같은 시각에 실패한 1만 건이 정확히 같은 시각에 재시도한다. 랜덤을 섞어 분산시켜야 상대가 회복하는 순간 다시 무너지지 않는다.

이때 랜덤 폭을 고정값(`random(0 ~ base)`)으로 두면 시도가 거듭돼도 분산 폭은 5분 그대로인데 간격만 벌어져서, 회차가 올라갈수록 사실상 동시에 몰린다. **랜덤 폭도 백오프에 비례해야 한다.** AWS가 정리한 Full Jitter가 이 형태다.

```
interval     = min(base * 2^attempts, maxInterval)
next_retry_at = now + random(0, interval)          -- Full Jitter

배치 조회: WHERE status = 'PENDING' AND next_retry_at <= now()
```

"5분마다 전부"가 아니라 **"지금 쏠 때가 된 것만"** 가져오게 된다.

## Q10. 사용자에게 무엇을 보여줄 것인가

---

> **Q.** 타임아웃이 난 첫 호출 시점에 사용자에게 무엇을 보여주겠는가? 그 선택이 만드는 부담은?
>
> **A. (내 답변)** "죄송합니다, 잠시 후 다시 요청해주세요"로 두면 반복될 때 고객센터 문의가 많아질 것 같다. 사용자 재시도와 배치 재시도가 겹칠 수도 있지 않을까?

**중복 발행은 나지 않는다.** 사용자가 다시 눌러도 멱등키가 동일해 유니크 제약에 걸리고, 요청이 나가더라도 상대가 같은 응답을 돌려준다. 여기까지가 앞에서 만든 방어의 효과다.

진짜 문제는 **사용자가 영원히 결과를 못 보는 것**이다. 재요청 시 이미 PENDING 레코드가 있어 `DuplicateKeyException`이 나는데 거기에 "이미 처리 중입니다"만 뱉으면, 배치가 처리를 끝냈는데도 사용자는 계속 같은 메시지만 본다.

### 재요청 시 레코드 상태를 보고 분기한다

| 상태 | 사용자에게 |
|---|---|
| SUCCESS | 저장된 쿠폰 코드를 그대로 노출 (사용자 입장에선 그냥 성공) |
| PENDING | "처리 중입니다. 완료되면 알림을 드립니다" |
| DLQ / FAILED | 고객센터 안내 |

### 첫 타임아웃에 "실패"라고 말하지 않는다

> "쿠폰 발행을 접수했습니다. 완료되면 알려드릴게요."

이렇게 응답하고 **비동기 완료 모델**로 간다(`202 Accepted` + 폴링 또는 푸시). 대부분은 몇 초 뒤 쿠폰함에서 확인하므로 CS 문의가 가장 크게 줄어든다.

이 선택은 UX 문제만이 아니다. "실패"라고 말했는데 나중에 발행되면 사용자는 못 받은 줄 알고 문의하고, CS가 수동 발행해서 **진짜 중복이 발생한다.** 시스템은 멱등한데 사람이 우회로를 만들어 깨뜨리는 케이스다. 애초에 "실패"라는 단어를 쓰지 않는 것이 중요한 이유다.

## 정리 — 비용 낮은 순으로

---

> 같은 목표를 여러 층위에서 달성할 수 있다. 아래로 갈수록 비용이 커지므로, 위에서부터 채우고 필요할 때 내려간다.

### 1단계 — 코드만으로 가능 (비용 최저)

- **타임아웃 명시 설정** (`connectTimeout`, `readTimeout`). 미설정이 실무 사고의 절반이다.
- **트랜잭션 분리.** 외부 호출은 절대 트랜잭션 안에 넣지 않는다. `REQUIRES_NEW`가 아니라 트랜잭션 없는 파사드로 분리한다.
- **유니크 제약 + `DuplicateKeyException` 처리.** `(userId, eventId)` 복합 유니크.
- **애플리케이션 레벨 재시도 1~2회.** 단, 두 조건을 만족할 때만 넣는다. 멱등키가 이미 확보돼 있을 것, 그리고 즉시가 아니라 짧은 백오프를 둘 것. 타임아웃 직후의 즉시 재시도는 상대가 과부하로 느려진 상황에서 부하를 배로 얹는다. 그리고 이 재시도를 넣는 순간 Q2의 배치 임계값도 같이 늘려야 한다.

### 2단계 — 테이블 하나 추가

- **요청 이력 테이블** — `idempotency_key`, `status`, `attempts`, `next_retry_at`, `last_error`, `response_body`
- **선기록 후호출** — PENDING 커밋 → 호출 → SUCCESS/FAILED 갱신
- **재시도 배치** — 타임아웃 총합 + 여유시간이 지난 PENDING만 대상
- **지수 백오프 + 상한 + Full Jitter**
- **재시도 횟수 초과 시 DLQ 마킹 + 운영자 알림**

### 3단계 — 상대 서버와 협의 (조직 비용)

- **멱등키 계약** — 우리가 생성, 헤더/바디로 전달
- **재요청 시 최초와 동일한 성공 응답 반환** (에러 아님)
- **조회 API** — 멱등성이 있으면 필수는 아니나 대사(reconciliation)용으로 유용
- **재시도 가능/불가능 에러 코드 구분**

### 4단계 — 인프라·운영 (비용 최고)

- **서킷 브레이커** (Resilience4j). 상태를 Redis로 외부화하면 배치 실행 간에도 유지된다.
- **어드민 재처리 화면** — DLQ 조회, 개별/일괄 재시도, 강제 완료 처리
- **일일 대사 배치** — 우리 SUCCESS 건과 상대 발행 내역 대조, 유령 건 탐지
- **비동기 완료 UX** — 접수 응답 + 폴링 또는 푸시 알림
- **모니터링** — PENDING 건수, DLQ 유입률, 평균 재시도 횟수 알람

## 한 줄 요약

---

> 외부 호출 실패는 "실패"가 아니라 **"상태 불명"** 이므로,
> ① 요청을 먼저 커밋해 추적 가능하게 만들고
> ② 멱등키로 중복 발행을 차단한 뒤
> ③ 백오프 재시도로 최종 일관성을 확보하고
> ④ 끝내 안 되는 건은 DLQ로 빼서 사람이 처리한다.

## 더 파볼 키워드

---

> 위 논의에서 이름만 스치고 지나간 것들. 각각이 별도의 글감이다.

### 분산 시스템 / 신뢰성

- **Idempotency (멱등성)** — Idempotency Key, 클라이언트 생성 vs 서버 발급
- **Exactly-once vs At-least-once delivery** — 왜 exactly-once는 사실상 불가능한가
- **Eventual Consistency (최종 일관성)**
- **Two Generals Problem** — 응답 유실 시 상태를 알 수 없는 근본 이유
- **Transactional Outbox Pattern** / Inbox Pattern
- **Saga Pattern**, Compensating Transaction (보상 트랜잭션)
- **Reconciliation (대사)** — 양측 데이터 정합성 대조

### 재시도 / 장애 격리

- **Retry Storm / Thundering Herd**
- **Exponential Backoff + Jitter** (Full Jitter, Equal Jitter, Decorrelated Jitter)
- **Circuit Breaker** — CLOSED / OPEN / HALF_OPEN 상태 전이, 상태 외부화
- **Bulkhead Pattern** (격리)
- **Rate Limiting / Throttling**
- **Dead Letter Queue (DLQ)**, Poison Message
- **Timeout 설계** — `connectTimeout` vs `readTimeout` vs 전체 타임아웃
- **Resilience4j** (또는 Hystrix, Sentinel)

### DB / 동시성

- **트랜잭션 격리 수준** — READ COMMITTED vs REPEATABLE READ
- **InnoDB 락** — Record Lock, **Gap Lock**, Next-Key Lock, Supremum Pseudo-record
- **Insert Intention Lock**, Deadlock 발생 패턴
- **`SELECT ... FOR UPDATE`** vs **Unique Constraint** 기반 동시성 제어
- **낙관적 락 vs 비관적 락**
- **DB Connection Pool** — HikariCP, 풀 고갈과 장애 전파
- **분산 락** — Redisson, Redlock 논쟁

### Spring 실무

- **`@Transactional` 전파 속성** — `REQUIRES_NEW`, `REQUIRED`, 그리고 suspend 시 커넥션이 반납되지 않는 이유
- **AOP Proxy self-invocation 문제**
- **`DuplicateKeyException` / `DataIntegrityViolationException`** 처리
- **Spring Retry**, `@Retryable`
- **Spring Batch** — Chunk 처리, Skip/Retry 정책, JobParameters

### API 설계

- **HTTP 상태 코드 시맨틱** — 409 Conflict, 429, 503 + `Retry-After`
- **Retryable vs Non-retryable 에러 구분**
- **`Idempotency-Key` 헤더** (Stripe API 설계가 사실상 표준 레퍼런스)
- **비동기 API 설계** — 202 Accepted, Polling, Webhook, Push

## 참고 자료

---

- [Idempotent Requests (docs.stripe.com/api)](https://docs.stripe.com/api/idempotent_requests)
- [Exponential Backoff And Jitter (aws.amazon.com/blogs/architecture)](https://aws.amazon.com/blogs/architecture/exponential-backoff-and-jitter/)
- [InnoDB Locking (dev.mysql.com/doc/refman/8.0)](https://dev.mysql.com/doc/refman/8.0/en/innodb-locking.html)
- [Transaction Isolation Levels (dev.mysql.com/doc/refman/8.0)](https://dev.mysql.com/doc/refman/8.0/en/innodb-transaction-isolation-levels.html)
- [Transaction Propagation (docs.spring.io/spring-framework)](https://docs.spring.io/spring-framework/reference/data-access/transaction/declarative/tx-propagation.html)
- [CircuitBreaker (resilience4j.readme.io)](https://resilience4j.readme.io/docs/circuitbreaker)
- [Handling Overload — Google SRE Book (sre.google/sre-book)](https://sre.google/sre-book/handling-overload/)
