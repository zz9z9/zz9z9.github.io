---
title: MySQL - LOCK 살펴보기
date: 2025-07-01 21:00:00 +0900
categories: [지식 더하기, 이론]
tags: [MySQL]
---

> 락을 잘 모르면 비효율적인 쿼리를 작성하거나, 데드락을 유발하거나, 불필요한 성능저하 등을 일으킬 수 있다고 생각한다. 또한 디버깅시 실마리를 못잡을 수도 있다.
> 이런 일을 최대한 겪지 않도록 MySQL에서는 어떤 락을 제공하는지 살펴보자.

## 락은 왜 필요한가
---

> 읽기는 MVCC가 처리하고, 락은 **쓰기와 잠금 읽기**를 위해 존재한다.

- InnoDB에서 일반 `SELECT`는 (READ COMMITTED / REPEATABLE READ 기준) 락을 걸지 않는다.
  - 언두 로그로 스냅샷 시점의 버전을 읽는 MVCC로 일관성을 확보하기 때문이다.
- 따라서 락이 필요한 건 쓰기(`INSERT`/`UPDATE`/`DELETE`)와 잠금 읽기(`SELECT ... FOR UPDATE`, `FOR SHARE`)이다.

| 문제 | 해결 수단 |
| --- | --- |
| 일반 `SELECT`의 일관된 읽기 | **MVCC** (락 없음) |
| 같은 행 동시 수정 (lost update) | **레코드 락** |
| 범위 안에 새 행이 끼어듦 (팬텀) | **갭 락 / 넥스트키 락** |

- 레코드 락만으로는 이미 존재하는 행만 지킬 수 있고, **아직 존재하지 않는 행이 나중에 생기는 것은 막지 못한다.**
  - REPEATABLE READ에서 팬텀을 막기 위해 갭 락이 추가로 필요한 이유다.
  - READ COMMITTED가 갭 락을 쓰지 않는 것도 애초에 팬텀을 허용하는 격리 수준이기 때문이다.

**※ SERIALIZABLE은 예외**

- `SERIALIZABLE`에서는 일반 `SELECT`도 락을 건다.
- `autocommit`이 꺼져 있으면 InnoDB가 모든 평범한 **`SELECT`를 암묵적으로 `SELECT ... FOR SHARE`로** 바꿔, 읽은 행과 그 범위에 **S 넥스트키 락**을 건다.
- MVCC 스냅샷 없이 **락만으로** 일관성을 보장하는 셈이다. (`autocommit`이 켜진 단일 `SELECT`는 예외로 락 없는 consistent read로 처리된다)


## 쿼리는 어떤 과정으로 락을 잡는가
---

> 락은 쿼리 시작 시 한꺼번에 잡히는 게 아니라, **스토리지 엔진이 인덱스를 스캔하며 레코드를 만나는 순간마다** 하나씩 잡힌다.

쿼리 한 건이 처리되는 흐름과 각 단계에서 락이 어떻게 관여하는지를 보면, 앞서 나온 "스캔한 인덱스가 잠금 범위를 결정한다"는 얘기가 자연스럽게 이어진다.

```
1. 파싱      SQL 구문 분석
2. 최적화    옵티마이저가 사용할 인덱스와 스캔 범위를 결정  ← 잠금 범위가 여기서 사실상 정해짐
3. 실행      InnoDB가 인덱스를 스캔하며 레코드를 하나씩 읽음
             │
             ├─ 레코드를 읽을 때마다 그 레코드(+ RR이면 앞 갭)에 락 획득
             ├─ 행 락을 걸기 전, 테이블에 IS/IX(의도 락)를 먼저 획득
             └─ 서버 레이어에서 WHERE 조건 평가
4. 커밋/롤백  트랜잭션 종료 시점에 락 해제
```

- **잠금 범위는 2단계(최적화)에서 정해진다.**
  - 옵티마이저가 어떤 인덱스로 어디부터 어디까지 스캔할지 결정하는 순간, 잠글 레코드와 갭의 범위가 사실상 확정된다.
  - 조건에 맞는 인덱스가 없으면 스캔 범위 = 테이블 전체가 되어 잠금도 그만큼 커진다.
- **락은 스캔하면서 점진적으로 획득된다.**
  - 쿼리 시작 시 전부 잡는 게 아니라, 엔진이 레코드를 하나 읽을 때마다 그 레코드에 락을 건다.
  - 그래서 같은 쿼리라도 인덱스를 얼마나 잘 타느냐에 따라 실제로 걸리는 락 수가 달라진다.
- **엔진이 읽은 행은 조건에 안 맞아도 일단 잠긴다.**
  - InnoDB는 서버 레이어의 WHERE 평가보다 먼저 레코드를 잠근다.
  - REPEATABLE READ에서는 조건에 안 맞는 행의 락도 트랜잭션 끝까지 유지되고, READ COMMITTED에서만 평가 후 즉시 해제된다. (인덱스 컨디션 푸시다운으로 조건을 엔진에 내려보내면 애초에 안 읽는 행이 줄어 락도 준다)
- **락은 트랜잭션이 끝나야 풀린다.**
  - 개별 문장이 끝날 때가 아니라 `COMMIT`/`ROLLBACK` 시점에 해제된다.
  - InnoDB는 실행 중에 락을 획득만 하고, 트랜잭션 종료 때 한꺼번에 해제하는 **엄격한 2단계 잠금(strict 2PL)** 을 따른다.
  - 트랜잭션을 짧게 유지해야 하는 이유가 이것이다.

> 즉, "이 쿼리가 무슨 락을 거는가"는 SQL 구문만 봐서는 알 수 없고, **옵티마이저가 어떤 인덱스를 어떻게 타는지**까지 봐야 한다. `EXPLAIN`으로 실행 계획을, `performance_schema.data_locks`로 실제 잡힌 락을 확인하는 습관이 필요하다.

**※ `LIMIT 1`이면 한 행만 잠길까?**

> 아니다. `LIMIT`은 **결과로 돌려주는 행 수**를 제한할 뿐, 잠금은 **그 한 건을 찾기까지 스캔한 범위**에 걸린다.

`LIMIT 1`은 조건에 맞는 행을 하나 찾으면 거기서 **스캔을 멈추게** 한다. 그래서 테이블 전체를 잠그진 않지만, 멈추기 전까지 읽은 행은 다 잠근다. 그 개수는 인덱스에 따라 갈린다.

- **인덱스를 잘 타면 → 적게 잠근다.** 아래 쿼리는 `status` 인덱스로 첫 매칭 행에 바로 도달해 그 행(+RR이면 앞 갭)만 잠그고 멈춘다.

```sql
-- status 컬럼에 인덱스 있음
SELECT * FROM t WHERE status = 'A' ORDER BY id LIMIT 1 FOR UPDATE;
```

- **인덱스를 못 타면 → 스캔한 만큼 다 잠근다.** 아래 쿼리는 처음부터 한 행씩 읽으며 `non_idx = 5`를 찾는데, 그 값이 100번째 행에 있으면 **1~100번째 행이 전부 잠긴다.** 조건에 안 맞는 99개까지 포함해서다. (앞서 본 "읽는 순간 잠기고, 조건 평가는 그 다음"이 그대로 적용)

```sql
-- non_idx 컬럼에 인덱스 없음
SELECT * FROM t WHERE non_idx = 5 LIMIT 1 FOR UPDATE;
```

- 격리 수준에 따라 잔여 락이 다르다. **REPEATABLE READ**는 스캔 중 안 맞은 99개 행과 갭까지 트랜잭션 끝까지 유지하고, **READ COMMITTED**는 조건 평가 후 즉시 풀어 결국 매칭된 1개만 남긴다. (단 RC도 스캔 도중엔 걸었다 푸는 것이라 그 순간의 경합은 있다)

정리하면, `LIMIT 1`이 보장하는 건 "결과 1행"이지 "잠금 1행"이 아니다. **잠금 수 = 매칭을 찾기까지 스캔한 행 수**이고, 이건 인덱스가 결정한다.

**※ "서버 레이어에서 WHERE 조건 평가"란 ?**

> MySQL은 두 계층으로 나뉘고, **락은 아래층(스토리지 엔진)이 걸지만 WHERE 조건 판단은 위층(서버 레이어)이 한다.** <br>
> 이 둘이 분리돼 있어서 "조건에 안 맞는 행도 일단 잠긴다"는 현상이 생긴다.

```
┌─────────────────────────────────────┐
│  Server Layer (서버 레이어)            │
│  - 파서, 옵티마이저                     │
│  - WHERE 조건 평가(일부)                │
├─────────────────────────────────────┤
│  Storage Engine (InnoDB 등)          │
│  - 데이터/인덱스 저장·읽기                │
│  - 락을 거는 주체                       │
└─────────────────────────────────────┘
```

`SELECT * FROM t WHERE age = 20 AND memo LIKE '%urgent%' FOR UPDATE` 를 예로 들면:

```
1. 서버 레이어가 InnoDB에게 "행 하나 줘" 요청
2. InnoDB가 인덱스를 타고 레코드를 읽으며 그 레코드에 락을 건다   ← 락은 여기서
3. 읽은 레코드를 서버 레이어로 올려보냄
4. 서버 레이어가 WHERE(memo LIKE '%urgent%') 평가 → 맞으면 결과, 아니면 버림  ← 평가는 여기서
```

- 4번에서 버려진 행도 2번에서 **이미 락이 걸렸다.** 서버가 조건을 평가하려면 일단 InnoDB가 그 행을 읽어 올려야 하는데, InnoDB는 읽는 순간 락을 걸기 때문이다.
- 그래서 **엔진이 읽은 행 ≠ 최종 결과에 포함된 행**이고, 락은 전자를 기준으로 걸린다. "결과에 안 나온 행인데 왜 잠겨 있지?"의 정체다.
- READ COMMITTED는 이렇게 걸린 락을 조건 평가 직후 풀어주고, REPEATABLE READ는 트랜잭션 끝까지 유지한다.

**인덱스 컨디션 푸시다운(ICP)** 은 이 낭비를 줄이는 최적화다.
- 조건 중 **인덱스만으로 판단 가능한 것**은 서버까지 올리지 않고 InnoDB에 내려보내(push down) 인덱스 단계에서 미리 걸러낸다.
- 안 맞는 행은 읽지도 잠그지도 않으므로 락이 줄어든다.
- 다만 `LIKE '%...%'` 처럼 인덱스로 못 거르는 조건은 여전히 서버 레이어까지 올라가 위 문제가 그대로 남는다.


## Lock 타입 (how)
---

> InnoDB는 기본적으로 **행 수준(row-level) 잠금**을 구현하며(테이블 수준 잠금도 지원), <br> 락을 **어떻게** 쥐느냐에 따라 **공유(S, Shared Lock) 잠금**과 **배타(X, Exclusive Lock) 잠금** 두 가지 타입이 있다.

"어떻게 쥐느냐"는 곧 **남과 같이 쥘 수 있는지** 여부이다.

- **공유(S)**: "같이 읽자." 여러 트랜잭션이 **동시에** 같은 대상을 쥘 수 있다.
- **배타(X)**: "나만 쓴다." 한 트랜잭션이 쥐면 다른 누구도 그 대상을 쥘 수 없다.

이 차이에서 아래 호환성 규칙이 나온다. 요청을 허용할지 말지는 "이미 걸린 락과 지금 요청하는 락을 같이 쥘 수 있는가"로 결정된다.

| 이미 걸림 ↓ / 요청 → | S | X |
| --- | --- | --- |
| **S** | 허용 (같이 읽기) | 대기 |
| **X** | 대기 | 대기 |

> 즉 **S는 읽기끼리만 공존**하고, **X가 하나라도 끼면 무조건 단독**이다. 읽기는 서로 방해되지 않지만, 쓰기는 읽기·쓰기 모두를 밀어낸다.

단, 이 호환성 표는 **레코드 락**(과 넥스트키 락의 레코드 부분)에만 해당한다. **갭 락은 여기서 예외로, S/X가 서로 충돌하지 않는다.** 갭 락은 다른 락을 막는 게 아니라 오직 삽입을 막는 억제용이기 때문인데, 자세한 건 [Gap Lock](#gap-lock) 절에서 다룬다.

### Shared Lock
> 공유(S) 잠금 — "같이 읽어도 되지만, 아무도 못 쓰게"

- 해당 잠금을 보유한 트랜잭션이 행을 **읽을 수 있도록 허용**
- 여러 트랜잭션이 같은 행에 동시에 S 잠금을 쥘 수 있다. 대신 그동안 누구도 그 행을 **수정(X 잠금)** 하지는 못한다.
- 트랜잭션 T1이 행 r에 대해 공유(S) 잠금을 보유하고 있는 경우, 별개의 트랜잭션 T2가 행 r에 대해 잠금을 요청하면 다음과 같이 처리된다:
  - T2가 S 잠금을 요청한 경우, 즉시 허용한다.
    - **그 결과, T1과 T2는 모두 r에 대해 S 잠금을 보유하게 된다.**
  - T2가 X 잠금을 요청한 경우는 허용하지 않는다.
- 획득: `SELECT ... FOR SHARE`

### Exclusive Lock
> 배타(X) 잠금 — "나만 쓴다, 읽기도 못 끼게"

- 해당 잠금을 보유한 트랜잭션이 행을 **수정하거나 삭제할 수 있도록 허용**
- 한 트랜잭션이 X 잠금을 쥐면, 다른 트랜잭션은 그 행을 읽으려고(S) 하든 쓰려고(X) 하든 **모두 대기**한다.
- 트랜잭션 T1이 행 r에 대해 배타(X) 잠금을 보유하고 있는 경우, 별개의 트랜잭션 T2가 r에 대해 **어떤 종류의 잠금(S 또는 X)을 요청하더라도 허용하지 않는다.**
- 즉, 트랜잭션 T2는 T1이 행 r에 대한 잠금을 해제할 때까지 기다려야 한다.
- 획득: `SELECT ... FOR UPDATE`, `UPDATE`, `DELETE`


## Lock 종류 (what)
---

> 락은 **타입(how, S/X)** 과 **종류(what, 무엇을 잠그나)** 라는 두 축의 조합이다.

- 앞의 S/X는 "어떻게 잠그나"를 나타내는 **타입(how)** 이고, 실제 잠금 대상의 형태가 **종류(what)** 다.
- 아래는 InnoDB가 제공하는 잠금 전체를 **레벨 · 종류 · 타입**과 함께 정리한 것이다. 이 글에서 하나씩 다룬다.
- `LOCK_MODE 표기`는 `performance_schema.data_locks`의 `LOCK_MODE` 컬럼에 찍히는 값으로, 타입(S/X)과 종류가 **한 문자열에 합쳐져** 나온다.

| 레벨 | 잠금 종류 (what) | 타입 (how) | `LOCK_MODE` 표기 예 | 한 줄 설명 |
| --- | --- | --- | --- | --- |
| 테이블 | **Intention Lock** | IS / IX | `IS`, `IX` | 행 락을 걸기 전 "행 단위로 잠글 것"임을 테이블에 표시 |
| 테이블 | **AUTO-INC Lock** | 특수 (S·X 아님) | `AUTO_INC` | `AUTO_INCREMENT` 값 채번용 |
| 행 | **Record Lock** | S / X | `X,REC_NOT_GAP` | 인덱스 레코드 하나를 잠금 (갭 제외) |
| 행 | **Gap Lock** | S / X (서로 충돌 안 함) | `X,GAP` | 레코드 사이 빈 공간(갭)을 잠금 → 삽입 차단 |
| 행 | **Next-Key Lock** | S / X | `X` (접미사 없음) | 레코드 락 + 그 앞 갭 락 (RR의 기본형) |
| 행 | **Insert Intention Lock** | X | `X,GAP,INSERT_INTENTION` | INSERT 직전에 거는 특수한 갭 락 |
| 행 | **Predicate Lock** | S / X | (공간 인덱스 전용) | `SPATIAL` 인덱스에서 MBR 값 기준 잠금 |

- **종류(what)와 타입(how)은 서로 독립이다.**
  - 무엇을 잠그는지와 어떻게 잠그는지가 따로 정해져 자유롭게 조합된다. 대부분의 행 락은 같은 종류라도 `FOR SHARE`면 S, `FOR UPDATE`면 X로 갈린다.
- **`LOCK_MODE`는 이 두 축을 한 문자열에 담는다.**
  - `X,GAP` = 타입 `X` + 종류 `GAP`. 같은 갭을 `S,GAP`으로 잠글 수도 있다.
  - 넥스트키 락만은 기본형이라 접미사 없이 `X`/`S`로 표기된다.
- **성격이 고정된 예외가 있다.**
  - `IS`/`IX`(intention)는 record/gap과 같은 층위가 아니라 **테이블 레벨**이고, 행 락을 걸기 전에 "행 단위로 뭔가 잠글 것"임을 표시하는 용도라 IS/IX 형태로만 존재한다.
  - **AUTO-INC**는 채번 전용이라 S/X 구분이 없다.
  - **Insert Intention**은 삽입(쓰기) 직전 락이라 사실상 X로 쓰인다.
- 참고로 MySQL 공식 문서(InnoDB Locking)는 S/X를 "두 **유형**(types)의 락"이라 부른다.
- 이 글은 S/X를 "타입(how)", 잠금 대상의 형태를 "종류(what)"로 구분해 설명한다. (`data_locks`의 컬럼명이 `LOCK_MODE`인 것과는 용어가 어긋나지만, 값 자체는 위 표처럼 두 축을 다 담고 있다)

### Intention Lock

> 트랜잭션이 테이블의 **특정 행**에 대해 **나중에 어떤 종류의 잠금(공유 또는 배타)을 설정할 것인지**를 나타내는 **테이블 수준의 잠금**

**목적**
- **다중 세분화 잠금(multiple granularity locking)**을 지원하여 행 잠금(row locks) 과 테이블 잠금(table locks) 이 **공존하며 효율적으로 작동**할 수 있게 하기 위함

**예시를 통해 의도 잠금 필요성 이해하기**
```
A 트랜잭션이 IX 락을 테이블에 걸고 있는 상태
B 트랜잭션이 LOCK TABLE my_table WRITE로 테이블 전체 락을 요청
→ IX 락이 이미 있기 때문에, 바로 충돌 판단 후 B는 block됨
→ 전체 행 잠금 목록을 다 뒤져볼 필요 없음
```

※ 다중 세분화 잠금(Multiple Granularity Locking) ?
- 데이터베이스에서 여러 수준(granularity)의 객체에 대해 동시에 잠금을 설정할 수 있도록 하는 메커니즘
- 즉, 테이블(table), 페이지(page), 행(row)과 같이 데이터 구조의 다양한 수준에 대해 서로 다른 크기의 잠금을 동시에 적용할 수 있게 만드는 기법

**종류**
- 의도 공유 잠금(IS 잠금)
  - 트랜잭션이 테이블 내 개별 행들에 대해 공유 잠금을 설정하려고 의도하고 있음을 나타낸다.
  - ex : `SELECT ... FOR SHARE` 는 IS 잠금을 설정

- 의도 배타 잠금(IX 잠금)
  - 트랜잭션이 테이블 내 개별 행들에 대해 배타 잠금을 설정하려고 의도하고 있음을 나타낸다.
  - ex : `SELECT ... FOR UPDATE`는 IX 잠금을 설정

**동작 방식**
- 트랜잭션이 테이블의 **행에 대해 공유 잠금을 획득하려면**, 먼저 해당 테이블에 대해 IS 잠금 또는 그보다 강한 잠금을 획득해야 한다.
- 트랜잭션이 테이블의 **행에 대해 배타 잠금을 획득하려면**, 먼저 해당 테이블에 대해 IX 잠금을 획득해야 한다.
- 트랜잭션은 충돌하는 잠금이 해제될 때까지 대기한다.
- 하지만, 잠금 요청이 기존 잠금과 충돌하고 이로 인해 데드락(deadlock) 이 발생할 수 있다면, 에러가 발생한다.

**잠금 호환성**

> 의도 잠금은 **전체 테이블 잠금 요청(예: LOCK TABLES ... WRITE)**을 제외하고는 아무것도 차단하지 않는다.

| 현재 잠금 ↓ / 요청 잠금 → | **X**  | **IX** | **S** | **IS** |
| ----------------- | ---------------- | ---------------------------- | -------------- | ------------------------- |
| **X**             | 대기      | 대기                  | 대기    | 대기               |
| **IX**            | 대기      | 허용                 | 대기    | 허용              |
| **S**             | 대기      | 대기                  | 허용   | 허용              |
| **IS**            | 대기      | 허용                 | 허용   | 허용              |


```
-- 트랜잭션 A
START TRANSACTION;
SELECT * FROM my_table WHERE id = 1 FOR UPDATE;  -- IX (on table) + X (on row id=1)

-- 트랜잭션 B
START TRANSACTION;
SELECT * FROM my_table WHERE id = 2 FOR UPDATE; -- IX (on table) + X (on row id=2)
```

- 둘 다 같은 테이블에서 작업하지만 각각 다른 row에 row-level X 락을 요청
- 그래서 InnoDB는 테이블에 각각 IX 잠금을 설정함
- IX와 IX는 호환되기 때문에 동시에 작업 가능

### Record Lock
> **인덱스 레코드**에 설정되는 잠금

- 예를 들어, `SELECT c1 FROM t WHERE c1 = 10 FOR UPDATE;` 는 `t.c1`이 10인 행을 다른 트랜잭션이 삽입, 수정, 삭제하지 못하도록 막는다.
- 레코드 락은 항상 인덱스 레코드를 대상으로 작동하며, **테이블에 인덱스가 없어도 마찬가지이다.**
- 인덱스가 없는 경우, InnoDB는 숨겨진 클러스터형 인덱스를 자동으로 생성하고, 이를 사용해 레코드 잠금을 수행한다.

**※ 인덱스 레코드 ?**

> 인덱스에 저장된 각 항목(=행의 위치를 가리키는 엔트리)
> 즉, 실제 행 데이터가 아닌 **인덱스 내부의 키와 포인터로 구성된 데이터 구조**


- InnoDB는 모든 테이블을 클러스터형 인덱스(Primary Key 기반 B+트리) 구조로 저장
- 따라서, 어떤 행(row)을 찾고 수정할 때도 **항상 인덱스를 통해 위치를 찾고 작업**
- 잠금의 대상이 되는 행은 곧 인덱스 레코드 상에 존재하는 엔트리이기 때문에, 인덱스 레코드 단위 락을 거는 것이 정확하고 효율적
- gap lock, next-key lock 같은 락 전략도 전부 **인덱스 레코드 사이 또는 레코드 + 갭 을 기준**으로 동작

### Gap Lock
> 인덱스 레코드들 **사이의 간격**이나, **첫 번째 이전 또는 마지막 이후의 간격**에 설정되는 잠금이다.

- 예를 들어 `SELECT c1 FROM t WHERE c1 BETWEEN 10 and 20 FOR UPDATE;` 쿼리는, 해당 범위 내의 기존 값이 존재하든 아니든 관계없이, 다른 트랜잭션이 c1에 15를 삽입하지 못하게 막는다.
- 이는 **해당 범위 내 모든 값들 사이의 간격**에 갭 락이 걸리기 때문이다.
- 갭은 하나의 인덱스 값 사이일 수도 있고, 여러 값 사이일 수도 있으며, 심지어 아무 값이 없어도 갭이 존재할 수 있다.
- 갭 락은 성능과 동시성 간의 절충의 일부로, 일부 트랜잭션 격리 수준에서만 사용되고 다른 수준에서는 사용되지 않는다.
- **유니크 인덱스**의 **모든 컬럼을 등치(`=`) 조건으로 지정해 실제로 존재하는 행 하나를 찾는 쿼리는 갭 락이 필요 없다.**
- 다만 다음 두 경우는 유니크 인덱스라도 **갭 락이 발생**한다.
  - 다중 열 유니크 인덱스 중 **일부 열만 조건에 포함된 경우** (몇 건이 걸릴지 확정할 수 없음)
  - 조건에 맞는 **행이 실제로 존재하지 않는 경우** (그 자리에 다른 트랜잭션이 값을 끼워 넣는 걸 막아야 하므로, 해당 위치의 갭을 잠근다)
- 예를 들어, id 컬럼에 유니크 인덱스가 있고 id가 100인 행이 존재한다면 다음 쿼리는 그 행에만 레코드 잠금이 걸리고, 다른 세션이 그 앞에 값을 삽입하더라도 문제되지 않는다.

```sql
SELECT * FROM child WHERE id = 100 FOR UPDATE;
```

- 만약 id가 유니크하지 않은 인덱스라면, 해당 쿼리는 앞쪽 갭에도 잠금을 건다.
- id에 인덱스가 아예 없다면 풀 스캔이 되므로, **테이블의 모든 레코드와 모든 갭**이 잠긴다. (사실상 테이블 전체가 잠기는 것과 같다)
- 여기서 주목할 점은, 서로 충돌하는 락이 같은 갭에 대해 서로 다른 트랜잭션에 의해 유지될 수 있다는 것이다.
- 즉, **갭 락(gap lock)은 공유/배타(S/X)라는 구분이 있지만, 실제로는 충돌하지 않는다.**
  - 예를 들어, 트랜잭션 A가 어떤 갭에 대해 공유 갭 락을 걸고 있는 동시에, 트랜잭션 B가 배타 갭 락을 같은 갭에 걸 수도 있다.
- 서로 충돌하는 갭 락이 허용되는 이유는, 인덱스에서 어떤 레코드가 제거될 경우, 해당 레코드에 걸린 여러 트랜잭션의 갭 락을 병합해야 하기 때문이다.
- InnoDB의 갭 락은 “순수하게 억제용” 으로, 그 목적은 다른 트랜잭션이 **해당 갭에 값을 삽입하지 못하게 막는 것**뿐이다.
  - **공유 갭 락과 배타 갭 락은 실제로 차이가 없으며**, 서로 충돌하지 않고, 같은 역할을 한다.

- 갭 락은 명시적으로 비활성화될 수 있으며, 이는 트랜잭션 격리 수준을 `READ COMMITTED`로 바꿀 때 발생한다.
  - 이 경우, 갭 락은 검색이나 인덱스 스캔에서는 사용되지 않으며, 외래 키 제약 조건이나 중복 키 검사에만 사용된다.

- READ COMMITTED 격리 수준을 사용할 경우 기타 부수적인 효과들도 있다.
  - WHERE 조건에 맞지 않는 레코드에 걸린 잠금은, MySQL이 조건을 평가한 후 즉시 해제된다.
  - UPDATE 문에 대해서 InnoDB는 “세미 일관성(semi-consistent)” 읽기를 수행하는데, 이는 MySQL에게 가장 최근 커밋된 버전을 전달하여 해당 행이 WHERE 조건에 맞는지 판단하도록 하는 방식이다.


**※ S/X 갭 락 차이가 없는데 구분하는 이유 ?**

정확히는 "구분이 아예 없다"가 아니라 **충돌 판정에서만 무의미**하다는 뜻이다. 핵심은 **갭 락이 다른 갭 락을 막는 물건이 아니라 INSERT를 막는 물건**이라는 점이다.

| 이미 걸린 락 → <br> 요청하는 락 ↓ | 갭 락 (S든 X든) |
| --- | --- |
| 갭 락 (S든 X든) | **호환** (대기 안 함) |
| insert intention | **대기** |

갭 락이 참여하는 충돌은 사실상 `insert intention ↔ gap` 한 줄뿐이라, S인지 X인지가 판정에 끼어들 여지가 없다. 이 충돌은 **비대칭**이라는 점도 유의한다. insert intention은 기존 갭 락을 기다리지만, 갭 락 요청은 기존 insert intention을 기다리지 않는다.

> 갭 락은 "이 빈 공간을 내가 점유한다"가 아니라 **"이 빈 공간에 아무도 새 행을 넣지 마라"** 라는 선언이다. 점유가 아니라 억제라서, 여러 트랜잭션이 같은 갭에 동시에 선언해도 서로 방해되지 않는다.

**그럼 왜 S/X 라벨을 붙여두나?** 넥스트키 락 = 레코드 락 + 갭 락이고 이 둘이 하나의 락 객체로 관리되는데, **레코드 부분에서는 S/X가 실제로 의미가 있기** 때문에 S/X 라벨을 뗄 수 없다. 갭 부분이 그 라벨을 무시할 뿐이다. S/X(타입) 자체는 쿼리가 결정한다.

```sql
SELECT ... FOR UPDATE: "나는 값을 수정할 수도 있어" → X Gap Lock
SELECT ... LOCK IN SHARE MODE: "나는 읽기만 할 거야" → S Gap Lock
```

**※ 필터링 조건과 갭 락**
- 유니크 인덱스의 모든 컬럼을 등치 조건으로 지정해 존재하는 행 하나를 찾는 쿼리는 갭 락이 필요 없다.
- 왜냐하면 이 경우 InnoDB는 정확히 하나의 행만 잠그면 되므로, 범위 전체를 잠글 필요가 없음
- 단, 다중 열 유니크 인덱스 중 일부 열만 조건에 포함된 경우에는 예외로, 갭 락이 발생한다.
  - 왜냐하면 조건이 애매하거나 불완전하면 MySQL이 정확히 하나의 행을 찾았는지 확신할 수 없기 때문


```sql
CREATE TABLE product (
  category_id INT,
  code VARCHAR(50),
  price INT,
  UNIQUE(category_id, code)
);

-- 쿼리
SELECT * FROM product WHERE category_id = 1 FOR UPDATE;
```

- `(category_id, code)`는 복합 유니크 인덱스
- 그런데 검색 조건은 category_id = 1만 포함됨 (불완전 조건)
  - InnoDB는 "정확히 하나의 행만" 찾았는지 보장할 수 없음
  - 따라서, 검색된 범위 전체에 next-key lock (record + gap) 걸게됨

```sql
SELECT * FROM product WHERE category_id = 1 AND code = 'A-100' FOR UPDATE;
```

- 유니크 인덱스 `(category_id, code)`의 **모든 컬럼이 등치 조건으로 지정됨**
- 해당 행이 실제로 존재한다면 정확히 한 row만 찾으므로 그 row에만 record lock (X) 걸림
- 갭 락 여부를 가르는 건 `LIMIT` 같은 게 아니라 **유니크 인덱스 전체 컬럼의 등치 조건 + 행의 존재 여부**다.

**※ 인덱스 없는 컬럼을 조건으로 걸면 ?**

> 갭 락의 범위는 **WHERE 조건**이 아니라 **실제로 스캔한 인덱스와 그 스캔 범위**가 결정한다.

`random` 컬럼(PK 아님, 인덱스 없음)에 대해 다음 잠금 읽기를 한다고 하자.

```sql
SELECT * FROM foo WHERE random < 5 FOR UPDATE;
```

`FOR UPDATE` 없는 평범한 `SELECT`라면 REPEATABLE READ에서 consistent read(MVCC 스냅샷)이므로 아무 잠금도 걸리지 않는다. 잠금 읽기일 때만 아래 얘기가 성립한다.

**"random < 5 인 구간"이라는 건 존재하지 않는다**

`random`에 인덱스가 없으므로 스캔은 클러스터형 인덱스(PK) 풀 스캔이 된다. 그런데 조건을 만족하는 행들은 PK 순서상 흩어져 있다.

```
PK:      1     2     3     4     5     6     7
random: 100    3    77     1    42    99     2
                ^           ^                 ^
              조건 만족    조건 만족        조건 만족
```

갭 락은 `(2, 3)` 처럼 **스캔하는 인덱스의 키 순서상 연속된 빈 공간**에만 걸 수 있다. `random < 5`는 PK 순서에서 연속 구간이 아니라 산발적인 집합이므로, "그 영역만" 잠글 수단 자체가 없다.

**그래서 모든 갭을 잠근다**

막아야 하는 건 팬텀, 즉 다른 트랜잭션이 `random = 3` 인 행을 INSERT하는 것이다. 그런데 그 행이 **PK 순서상 어디에 꽂힐지 알 수 없다.** `random` 값과 PK 값은 아무 상관이 없기 때문이다. 어느 갭이든 조건에 맞는 행이 들어올 수 있으므로 InnoDB는 모든 갭을 다 잠가야 한다.

- 결과적으로 `(-∞, 첫 PK]` 부터 `(마지막 PK, supremum)` 까지 전 구간이 잠긴다 → 사실상 테이블 락과 같은 효과
- 특히 PK가 AUTO_INCREMENT라면 새 행은 거의 항상 마지막 갭에 들어오므로, `(마지막 PK, supremum)` 을 잠그지 않으면 팬텀 방지가 무의미해진다
- 조건에 맞는 행이 한 건뿐이어도 나머지 행이 전부 잠기고, 다른 트랜잭션의 INSERT도 전부 막힌다

**인덱스를 만들면**

```sql
CREATE INDEX idx_random ON foo(random);
```

이제 스캔이 `idx_random`을 타므로 갭 락도 `random` 순서 위에 걸린다.

```
idx_random 순서: 1  2  3  42  77  99  100
                 └──────┘ ^
                조건 만족  여기까지만 잠금 → (-∞, 42]
```

`(-∞, 42]` 만 잠기고 그 뒤 레코드와 갭은 자유롭다. 잠금 범위가 조건 범위와 일치하게 된다.

**격리 수준에 따른 차이**

| | REPEATABLE READ | READ COMMITTED |
| --- | --- | --- |
| 갭 락 | 걸림 (전 구간) | 안 걸림 |
| 조건 불일치 행의 락 | 트랜잭션 끝까지 유지 | 조건 평가 후 즉시 해제 |

READ COMMITTED에서는 서버가 `random < 5`를 평가한 뒤 안 맞는 행의 락을 바로 풀어주므로, 최종적으로는 조건에 맞는 행들만 잠긴 채 남는다. 다만 **스캔 도중에는 여전히 모든 행에 락을 걸었다 푸는** 것이라 경합 자체가 사라지지는 않는다.

### Next-Key Lock
> 인덱스 레코드에 대한 레코드 락과, 그 앞에 있는 갭에 대한 갭 락의 조합

- InnoDB는 테이블 인덱스를 검색하거나 스캔할 때, **발견한 인덱스 레코드에 공유 또는 배타 잠금을 설정**하는 방식으로 행 수준 잠금을 수행한다.
  - 따라서, 행 수준 잠금은 실제로는 인덱스 레코드 잠금이다.

| 인덱스 유형 | next-key lock 기준 컬럼 |
| ------------------- | -------------------------------------------------------------- |
| **유니크 인덱스** (단일/복합) + **등치 조건** | **모든 인덱스 컬럼이 완전히 조건에 포함되고 해당 행이 존재해야** 정확히 1건만 잠금 (→ gap lock 없음) |
| **유니크 인덱스** + **범위 조건** | 유니크여도 `BETWEEN`, `>` 같은 범위 조건이면 스캔된 범위에 **next-key lock** 발생 |
| **비유니크 복합 인덱스**     | **첫 번째 컬럼 기준으로 범위 스캔**, 스캔된 범위의 **모든 레코드에 next-key lock** 발생 |

- 인덱스 레코드에 설정된 넥스트키 락은 **해당 인덱스 레코드 바로 앞의 갭**에도 영향을 미친다.
- 즉, 넥스트키 락은 **인덱스 레코드 잠금 + 그 앞 갭에 대한 갭 락**이다.
- 따라서, 한 세션이 인덱스에서 레코드 R에 대해 공유 또는 배타 잠금을 가지고 있다면, 다른 세션은 R 바로 앞의 갭에 새로운 인덱스 레코드를 삽입할 수 없다.

**예시**

```
-- 인덱스에 값이 10, 11, 13, 20이 있다고 가정
-- 이 인덱스에 대해 가능한 넥스트키 락은 다음 구간들을 포함
-- (소괄호는 끝점 제외, 대괄호는 끝점 포함)

(-무한대, 10]
(10, 11]
(11, 13]
(13, 20]
(20, +무한대)
```

- 마지막 구간에서는, 넥스트키 락이 인덱스에서 가장 큰 값보다 위에 있는 갭과, 실제 인덱스 값보다 큰 값을 가지는 "supremum" 가상 레코드를 잠근다.
- supremum은 실제 인덱스 레코드가 아니므로, 결국 이 넥스트키 락은 가장 큰 인덱스 값 이후의 갭만 잠그는 것과 같다.
- 기본적으로 InnoDB는 REPEATABLE READ 트랜잭션 격리 수준에서 동작한다.
- 이 경우 InnoDB는 검색과 인덱스 스캔에 넥스트키 락을 사용하여, **팬텀 레코드(phantom row)의 발생을 방지**한다.

**※ 팬텀이 실제로 문제가 되는 상황**

> InnoDB의 RR에서 일반 `SELECT`는 애초에 팬텀을 보지 못한다. 팬텀이 문제가 되는 건 **읽은 결과를 근거로 쓰기를 하는** 경우다.

일반 `SELECT`는 MVCC 스냅샷을 읽으므로, "같은 쿼리를 두 번 돌렸더니 행 수가 달라진다"는 교과서적 설명은 InnoDB에 잘 들어맞지 않는다. 반면 잠금 읽기(`FOR UPDATE`, `FOR SHARE`)와 `UPDATE`/`DELETE`는 스냅샷이 아니라 **최신 커밋 버전**을 대상으로 동작한다. 여기서 "내가 본 것"과 "내가 쓰는 대상"이 어긋나면 비즈니스 규칙이 깨진다.

**예시1 - 회의실 중복 예약**

```sql
CREATE TABLE reservation (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  room_id INT,
  start_at DATETIME,
  KEY idx_room_start (room_id, start_at)
);
```

```sql
-- 1) 겹치는 예약이 있는지 확인
SELECT COUNT(*) FROM reservation
WHERE room_id = 1 AND start_at BETWEEN '2026-07-21 10:00' AND '2026-07-21 11:00'
FOR UPDATE;

-- 2) 0건이면 삽입
INSERT INTO reservation (room_id, start_at) VALUES (1, '2026-07-21 10:30');
```

갭 락이 없다면(READ COMMITTED) 다음과 같이 진행된다.

| | 트랜잭션 A | 트랜잭션 B |
| --- | --- | --- |
| 1 | `SELECT ... FOR UPDATE` → **0건** | |
| 2 | | `SELECT ... FOR UPDATE` → **0건** |
| 3 | `INSERT 10:30` → 성공 | |
| 4 | | `INSERT 10:45` → 성공 |
| 5 | COMMIT | COMMIT |

중복 예약이 생긴다. 잠글 행이 0건이라 `FOR UPDATE`가 아무것도 막지 못했기 때문이다. 레코드 락은 **이미 존재하는 행**만 지킬 수 있는데, 여기서 막아야 하는 건 **아직 없는 행이 생기는 것**이다.

REPEATABLE READ라면 A의 `SELECT ... FOR UPDATE`가 0건이어도 `10:00~11:00` 구간의 갭에 `X,GAP`을 건다. B의 INSERT는 그 갭에 insert intention을 요청하다 대기하게 되고, A가 커밋한 뒤 다시 확인하면 중복을 잡아낸다.

> 갭 락은 **"조건에 맞는 행이 0건이다"라는 사실 자체를 잠그는** 유일한 수단이다.

다만 위 표처럼 A와 B가 **둘 다 `SELECT ... FOR UPDATE`를 먼저** 실행하면, 서로의 갭 락 때문에 양쪽 INSERT가 맞물려 **데드락**이 난다. MySQL이 감지해 한쪽을 롤백시키므로 중복 예약은 여전히 막히지만, 이 패턴에서 데드락 로그가 자주 보이는 이유가 이것이다.

**예시2 - 유니크 제약을 걸 수 없는 중복 방지**

"한 사용자당 활성 구독은 하나만" 같은 규칙이다.

```sql
SELECT * FROM subscription
WHERE user_id = 42 AND status = 'ACTIVE' FOR UPDATE;
-- 0건이면
INSERT INTO subscription (user_id, status) VALUES (42, 'ACTIVE');
```

해지된 구독 이력이 남아야 하므로 `UNIQUE(user_id)`를 걸 수 없다. 조건부 유니크 제약은 MySQL에 없으므로, **DB 제약 대신 갭 락에 의존**하게 되는 전형적인 케이스다.

**예시3 - 집계 후 마감**

```sql
-- 1) 7월 매출 합계
SELECT SUM(amount) FROM orders WHERE ordered_at BETWEEN '2026-07-01' AND '2026-07-31';

-- 2) 그 합계로 정산 레코드 생성
INSERT INTO settlement (month, total) VALUES ('2026-07', @sum);
```

집계와 마감 사이에 7월 주문이 하나 더 들어오면 정산 금액과 실제 주문 합계가 어긋난다. 넥스트키 락이 7월 범위 전체를 동결하는 역할을 한다.

**정리**

| 상황 | 레코드 락으로 충분? |
| --- | --- |
| 특정 주문의 상태 변경 | **O** (대상 행이 이미 존재) |
| 잔액 차감 | **O** |
| "겹치는 예약 없음"을 근거로 삽입 | **X** — 잠글 행이 없음 |
| "활성 구독 없음"을 근거로 삽입 | **X** |
| 범위 집계 후 그 값으로 쓰기 | **X** |

공통점은 전부 **"없다"는 사실에 기대어 쓰기를 하는** check-then-act 패턴이라는 것이다. 없는 것은 레코드 락으로 잠글 수 없으므로, 그 **빈 공간**을 잠그는 갭 락이 필요하다.

가능하면 유니크 제약으로 DB에 맡기고(갭 락보다 비용이 적고 데드락도 덜하다), 제약으로 표현할 수 없는 규칙에서만 갭 락/넥스트키 락에 의존하는 편이 낫다.

### Insert Intention Locks

> INSERT 작업이 행을 실제로 **삽입하기 전**에 설정하는 일종의 **갭 락(gap lock)**

- 이 잠금은 **같은 인덱스 갭**에 삽입하려는 의도를 표시하며, 서로 다른 위치에 삽입하는 경우에는 트랜잭션끼리 서로 **대기하지 않도록** 해준다.

**예시1**

```sql
-- 데이터 세팅

mysql> CREATE TABLE child (id int(11) NOT NULL, PRIMARY KEY(id)) ENGINE=InnoDB;
mysql> INSERT INTO child (id) values (90),(102);
```

```sql
-- 트랜잭션 A

START TRANSACTION;
INSERT INTO child (id) VALUES (101); -- (90, 102) 갭에 Insert Intention Lock이 걸림
```

```sql
-- 트랜잭션 B

START TRANSACTION;
INSERT INTO child (id) VALUES (95);
```

- 트랜잭션 B에서 동일하게 (90, 102) 갭에 Insert Intention Lock을 잡지만 Insert Intention Lock끼리는 호환되므로 대기없이 바로 Insert 가능

**예시2**

```sql
-- 데이터 세팅

mysql> CREATE TABLE child (id int(11) NOT NULL, PRIMARY KEY(id)) ENGINE=InnoDB;
mysql> INSERT INTO child (id) values (90),(102);
```


```sql
-- 트랜잭션 A

mysql> CREATE TABLE child (id int(11) NOT NULL, PRIMARY KEY(id)) ENGINE=InnoDB;
mysql> INSERT INTO child (id) values (90),(102);

mysql> START TRANSACTION;

mysql> SELECT * FROM child WHERE id > 100 FOR UPDATE; -- 102 레코드에 배타 잠금 + 그 앞 갭에 갭 락 발생

+-----+
| id  |
+-----+
| 102 |
+-----+
```

```sql
-- 트랜잭션 B

mysql> START TRANSACTION;
mysql> INSERT INTO child (id) VALUES (101);
```

- 트랜잭션 B에서 101을 삽입하려고 하지만, A의 `FOR UPDATE가 id > 100` 범위의 갭을 이미 잠가버렸기 때문에, B는 insert intention lock을 걸고 기다리게 됨.<br> (즉, 갭 락과는 호환되지 않음)

### AUTO-INC Lock

> `AUTO_INCREMENT` 컬럼이 있는 테이블에 INSERT할 때, 채번(값 발급)을 위해 InnoDB가 잡는 특수한 **테이블 수준 잠금**

- 가장 단순한 경우, 한 트랜잭션이 INSERT 중이면 다른 트랜잭션의 INSERT는 대기해야 한다. 그래야 먼저 INSERT한 트랜잭션이 **연속된(consecutive) 기본 키 값**을 받는다.
- 이 동작은 `innodb_autoinc_lock_mode` 시스템 변수로 조절한다. **채번 값의 예측 가능성**과 **INSERT 동시성** 사이의 절충을 고르는 설정이다.

| 값 | 이름 | 테이블 락 유지 | 값의 간격(gap) | statement 기반 복제 |
| --- | --- | --- | --- | --- |
| 0 | traditional | 모든 INSERT가 **문장 끝까지** 유지 | 없음 | 안전 |
| 1 | consecutive | bulk insert만 문장 끝까지, simple insert는 mutex로 **빠르게 채번 후 해제** | 문장 사이엔 생길 수 있음 | 안전 |
| 2 | interleaved | **테이블 락 없음**, 여러 문장 동시 실행 | 문장 내에서도 생길 수 있음 | **불안전** |

- **MySQL 8.0의 기본값은 `2`(interleaved)** 다. (8.0 이전 기본값은 `1`) 복제 기본 방식이 statement 기반에서 row 기반으로 바뀌면서 변경됐다.
- `bulk insert`는 삽입할 행 수를 미리 알 수 없는 `INSERT ... SELECT`, `LOAD DATA` 등을, `simple insert`는 행 수를 미리 아는 단순 `INSERT`를 가리킨다.
- 값에 간격이 생긴다는 건 곧 **AUTO_INCREMENT 값이 반드시 빈틈없이 이어지지는 않는다**는 뜻이다. 롤백이나 mode 1·2의 과대추정(overestimation) 때문에 중간 값이 버려질 수 있으므로, 연속성을 전제로 로직을 짜면 안 된다.

### Predicate Lock (공간 인덱스)

> `SPATIAL` 인덱스에서 격리 수준을 지원하기 위해 InnoDB가 사용하는 잠금. **MBR(최소 경계 사각형) 값**을 기준으로 잠근다.

- 넥스트키 락은 공간 데이터에 잘 맞지 않는다. **다차원 데이터에는 절대적인 순서 개념이 없어서**, 무엇이 "다음(next)" 키인지 정할 수 없기 때문이다.
- 그래서 `SPATIAL` 인덱스가 있는 테이블에서 `REPEATABLE READ`/`SERIALIZABLE`을 지원하기 위해 InnoDB는 predicate lock을 쓴다.
- `SPATIAL` 인덱스는 MBR 값을 담고 있는데, InnoDB는 쿼리에 사용된 **MBR 값에 predicate lock을 걸어** 일관된 읽기를 보장한다. 다른 트랜잭션은 그 쿼리 조건에 매칭될 행을 삽입·수정할 수 없다.
- 즉, 넥스트키 락에서 "레코드 + 앞 갭"으로 팬텀을 막던 것을, 공간 데이터에서는 "질의 영역(MBR)과 겹치는 삽입을 막는" 방식으로 대체한 것이다.

### 테이블 수준 잠금

지금까지의 record/gap/next-key는 모두 행 수준 잠금이다. 테이블 수준 잠금은 따로 있는데, "테이블이 잠긴 것처럼 보이는" 상황과 구분해야 한다.

**(a) 진짜 테이블 락**

- `LOCK TABLES foo WRITE` 명시적 실행
- DDL (`ALTER TABLE` 등) → 메타데이터 락(MDL)
- AUTO-INC 락 (`innodb_autoinc_lock_mode` 설정에 따라)

**(b) 테이블 락처럼 보이지만 사실은 행 락 전부**

앞서 본 인덱스 없는 컬럼에 대한 `WHERE random < 5 FOR UPDATE` 가 여기에 해당한다. 이건 테이블 락이 아니라 **모든 행의 레코드 락 + 모든 갭의 갭 락**이다. 효과는 비슷해도 실체가 다르다.

| | 진짜 테이블 락 | 전체 행 락 |
| --- | --- | --- |
| `data_locks` 표시 | `TABLE` 1건 | `RECORD` N건 |
| 메모리 | 일정 | 행 수만큼 증가 |
| 락 에스컬레이션 | — | **InnoDB에는 없음** |

특히 **InnoDB에는 락 에스컬레이션이 없다.** 행 락이 아무리 많아져도 자동으로 테이블 락으로 승격되지 않고, 락 개수만 계속 늘어난다. (SQL Server 등과 다른 점)

## 확인해보기

> 데이터 세팅

```sql
CREATE TABLE students (
    id INT AUTO_INCREMENT PRIMARY KEY,
    class_no INT NOT NULL,
    name VARCHAR(100) NOT NULL,
    age INT,
    INDEX idx_class_no_name (class_no, name)
);

INSERT INTO students (class_no, name, age) VALUES

(1, 'Alice', 14),
(1, 'Bob', 15),
(2, 'Charlie', 13),
(2, 'Alice', 14),
(3, 'David', 16),
(1, 'Eve', 14),
(2, 'Frank', 15),
(3, 'Grace', 13),
(1, 'Bob', 15),
(3, 'Heidi', 14);
```

```sql
SELECT * FROM students
ORDER BY class_no;
```

| id | class_no | name    | age |
|----|----------|---------|-----|
| 1  | 1        | Alice   | 14  |
| 2  | 1        | Bob     | 15  |
| 6  | 1        | Eve     | 14  |
| 9  | 1        | Bob     | 15  |
| 3  | 2        | Charlie | 13  |
| 4  | 2        | Alice   | 14  |
| 7  | 2        | Frank   | 15  |
| 5  | 3        | David   | 16  |
| 8  | 3        | Grace   | 13  |
| 10 | 3        | Heidi   | 14  |

※ 참고
- 쿼리 수행후 락 관련 정보는 다음 쿼리로 확인

```sql
SELECT object_name, index_name, lock_type, lock_mode, lock_data
FROM performance_schema.data_locks;
```

**performance_schema.data_locks에서의 lock_mode 해석**
- `X`
  - 보통 Next-Key Lock을 의미
  - 하지만, 이 정보만으로는 정확하게 Record-only Lock인지 Next-Key Lock인지 구분이 안 될 수도 있음

- `X_REC_NOT_GAP`
  - 명확하게 Record-only Lock을 의미
  - 즉, 해당 레코드만 잠그고 GAP은 잠그지 않음
  - 대표적으로 Unique Index로 정확하게 일치하는 값을 조회할 때 발생

- `X,GAP`
  - Gap Lock만 발생한 경우. 넥스트키 락에서 **레코드 부분만 떼어낸 것**으로, 갭은 지켜야 하지만 레코드는 조건 밖이라 잠글 필요가 없을 때 나온다.
  - 대표적으로 **스캔 범위 바로 바깥의 경계 레코드**에 걸린다. InnoDB는 스캔을 멈추려면 "조건이 끝났다"를 확인해야 하므로 범위 밖 첫 레코드까지 읽는데, 이 레코드는 조건에 안 맞으니 레코드는 잠그지 않고 **그 앞 갭만** 잠근다. (안 그러면 그 갭에 조건에 맞는 행이 삽입되어 팬텀이 발생)
  - 유니크 인덱스 등치 조건인데 **해당 값의 행이 존재하지 않는 경우**에도 발생 (잠글 레코드가 없으므로 그 값이 들어갈 자리의 갭만 잠금)

### TEST1

```sql
SELECT * FROM students
WHERE class_no = 1
FOR UPDATE;
```

| object\_name | index\_name          | lock\_type | lock\_mode       | lock\_data    |
| ------------ | -------------------- | ---------- | ---------------- | ------------- |
| students     | *(NULL)*             | TABLE      | IX               | *(NULL)*      |
| students     | idx\_class\_no\_name | RECORD     | X,GAP            | 2, 'Alice', 4 |
| students     | idx\_class\_no\_name | RECORD     | X                | 1, 'Alice', 1 |
| students     | idx\_class\_no\_name | RECORD     | X                | 1, 'Bob', 2   |
| students     | idx\_class\_no\_name | RECORD     | X                | 1, 'Eve', 6   |
| students     | idx\_class\_no\_name | RECORD     | X                | 1, 'Bob', 9   |
| students     | PRIMARY              | RECORD     | X\_REC\_NOT\_GAP | 1             |
| students     | PRIMARY              | RECORD     | X\_REC\_NOT\_GAP | 2             |
| students     | PRIMARY              | RECORD     | X\_REC\_NOT\_GAP | 6             |
| students     | PRIMARY              | RECORD     | X\_REC\_NOT\_GAP | 9             |


### TEST2

```sql
SELECT * FROM students
WHERE class_no = 1
AND age < 15
FOR UPDATE;
```

| object\_name | index\_name          | lock\_type | lock\_mode       | lock\_data    |
| ------------ | -------------------- | ---------- | ---------------- | ------------- |
| students     | *(NULL)*             | TABLE      | IX               | *(NULL)*      |
| students     | idx\_class\_no\_name | RECORD     | X,GAP            | 2, 'Alice', 4 |
| students     | idx\_class\_no\_name | RECORD     | X                | 1, 'Alice', 1 |
| students     | idx\_class\_no\_name | RECORD     | X                | 1, 'Bob', 2   |
| students     | idx\_class\_no\_name | RECORD     | X                | 1, 'Eve', 6   |
| students     | idx\_class\_no\_name | RECORD     | X                | 1, 'Bob', 9   |
| students     | PRIMARY              | RECORD     | X\_REC\_NOT\_GAP | 1             |
| students     | PRIMARY              | RECORD     | X\_REC\_NOT\_GAP | 2             |
| students     | PRIMARY              | RECORD     | X\_REC\_NOT\_GAP | 6             |
| students     | PRIMARY              | RECORD     | X\_REC\_NOT\_GAP | 9             |


- `age < 15`인 조건에 포함되는 레코드는 2개지만, `age = 15`인 레코드도 스캔 대상에 들어가서 불필요하게 락이 잡히게된다.

### TEST3

```sql
SELECT * FROM students
WHERE class_no = 1
LIMIT 2
FOR UPDATE;
```

| object\_name | index\_name          | lock\_type | lock\_mode       | lock\_data    |
| ------------ | -------------------- | ---------- | ---------------- | ------------- |
| students     | *(NULL)*             | TABLE      | IX               | *(NULL)*      |
| students     | idx\_class\_no\_name | RECORD     | X                | 1, 'Alice', 1 |
| students     | idx\_class\_no\_name | RECORD     | X                | 1, 'Bob', 2   |
| students     | PRIMARY              | RECORD     | X\_REC\_NOT\_GAP | 1             |
| students     | PRIMARY              | RECORD     | X\_REC\_NOT\_GAP | 2             |

- 처음부터 2개만 스캔하기 때문에, 정렬된 순서대로 2개만 락이 걸림

```sql
SELECT * FROM students
WHERE class_no = 1
LIMIT 2, 2
FOR UPDATE;
```

| object\_name | index\_name          | lock\_type | lock\_mode       | lock\_data    |
| ------------ | -------------------- | ---------- | ---------------- | ------------- |
| students     | *(NULL)*             | TABLE      | IX               | *(NULL)*      |
| students     | idx\_class\_no\_name | RECORD     | X                | 1, 'Alice', 1 |
| students     | idx\_class\_no\_name | RECORD     | X                | 1, 'Bob', 2   |
| students     | idx\_class\_no\_name | RECORD     | X                | 1, 'Eve', 6   |
| students     | idx\_class\_no\_name | RECORD     | X                | 1, 'Bob', 9   |
| students     | PRIMARY              | RECORD     | X\_REC\_NOT\_GAP | 1             |
| students     | PRIMARY              | RECORD     | X\_REC\_NOT\_GAP | 2             |
| students     | PRIMARY              | RECORD     | X\_REC\_NOT\_GAP | 6             |
| students     | PRIMARY              | RECORD     | X\_REC\_NOT\_GAP | 9             |

- LIMIT으로 2개만 리턴하지만 2부터이므로, 결국 4개 스캔하는거라 4개 모두 락 걸림

### TEST4

```sql
SELECT * FROM students
WHERE id < 5
FOR UPDATE;
```

| object\_name | index\_name | lock\_type | lock\_mode | lock\_data |
| ------------ |-------------| ---------- |------------|------------|
| students     | *(NULL)*    | TABLE      | IX         | *(NULL)*   |
| students     | PRIMARY     | RECORD     | X,GAP      | 5          |
| students     | PRIMARY     | RECORD     | X          | 1          |
| students     | PRIMARY     | RECORD     | X          | 2          |
| students     | PRIMARY     | RECORD     | X          | 3          |
| students     | PRIMARY     | RECORD     | X          | 4          |


- 4,5 사이에 아무것도 들어갈 수 없는데 왜 갭락이 걸릴까 ?
  - 사용자가 어떤 제약 조건을 갖고 있든 간에, InnoDB는 B+Tree 인덱스 구조만 보고 범위를 판단하고 잠금을 건다.
  - 즉, id가 AUTO_INCREMENT든, PRIMARY KEY든, 중간 삽입이 불가능하든 그건 InnoDB 입장에서 알 수 없는 정보

| 범위        | 걸리는 잠금 종류             |
| --------- | --------------------- |
| `(-∞, 1)` | `GAP` only            |
| `[1]`     | `X` (Next-Key Lock)   |
| `(1, 2)`  | `GAP` 포함 → \[2]도 마찬가지 |
| `[2]`     | `X` (Next-Key Lock)   |
| ...       | ...                   |
| `[4]`     | `X` (Next-Key Lock)   |
| `(4, 5)`  | → `id=5`에 `X,GAP`     |

### TEST5
> 유니크 인덱스 `email` 추가

- Tx1
   - `INSERT STUDENTS (class_no, email, name, age, flag) VALUES (5, 'email@test.com', 'lee', 10, 'N');`

| object\_name | index\_name          | lock\_type | lock\_mode       | lock\_data    |
| ------------ | -------------------- | ---------- | ---------------- | ------------- |
| students     | *(NULL)*             | TABLE      | IX               | *(NULL)*      |

- Tx2
  - `INSERT STUDENTS (class_no, email, name, age, flag) VALUES (5, 'email@test.com', 'kim', 10, 'N');`

| object\_name | index\_name          | lock\_type | lock\_mode       | lock\_data    |
| ------------ | -------------------- | ---------- | ---------------- | ------------- |
| students     | *(NULL)*             | TABLE      | IX               | *(NULL)*      |
| students     | *(NULL)*             | TABLE      | IX               | *(NULL)*      |
| students     | idx_email             | RECORD      | X,REC_NOT_GAP  | 'email@test.com', 17      |
| students     | idx_email             | RECORD      | S  | 'email@test.com', 17      |

- Tx2도 동일한 이메일로 INSERT를 시도함.
- MySQL은 UNIQUE 제약 위반 가능성이 있으므로 다음을 수행:
  - UNIQUE 인덱스를 조회하여 `email@test.com`이 존재하는지 확인
  - 이 과정에서 인덱스 키 `email@test.com'에`대해 S Lock (공유 잠금)을 걸어 존재 유무를 확인
  - 하지만, Tx1이 이미 인덱스 레코드 락 (X, REC_NOT_GAP)을 잡고 있어서, Tx2는 대기(blocking) 상태

## 참고 자료
- [InnoDB Locking (dev.mysql.com/doc/refman/8.4/en/innodb-locking.html)](https://dev.mysql.com/doc/refman/8.4/en/innodb-locking.html)
- [InnoDB Locking (dev.mysql.com/doc/refman/8.0/en/innodb-locking.html)](https://dev.mysql.com/doc/refman/8.0/en/innodb-locking.html)
- [AUTO_INCREMENT Handling in InnoDB (dev.mysql.com/doc/refman/8.0/en/innodb-auto-increment-handling.html)](https://dev.mysql.com/doc/refman/8.0/en/innodb-auto-increment-handling.html)
