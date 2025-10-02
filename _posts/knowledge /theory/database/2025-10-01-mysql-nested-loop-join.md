---
title: MySQL - Nested-Loop Join 알아보기
date: 2025-10-01 21:00:00 +0900
categories: [지식 더하기, 이론]
tags: [MySQL]
---

## Nested-Loop Join Algorithm
---

- MySQL은 테이블 간 조인을 수행할 때, **중첩 루프 조인(Nested-Loop Join, NLJ) 알고리즘(및 그 변형)**을 사용한다.
- NLJ : 바깥(outer) 테이블에서 한 행씩 가져와 안쪽(inner) 테이블과 조인한다.
  - outer : driving 테이블 / inner : driven 테이블 이라고도 불림
- 이 과정은 조인해야 할 모든 테이블에 대해 반복된다.
- MySQL 옵티마이저는 **통계 정보(테이블 크기, 인덱스 카디널리티 등)**를 기반으로 자동으로 조인 순서를 선택한다.
- 필요시 `STRAIGHT_JOIN` / 힌트를 이용해 강제할 수 있다.

```sql
FOR each row in Outer {
  FOR each row in Inner matching join condition {
    OUTPUT if row satisfies conditions
  }
}
```

### NLJ 비교

| 알고리즘 |  동작 방식 | 시간 복잡도 | 비고                                                                                |
|----------|---------|--------------|-----------------------------------------------------------------------------------|
| **Simple NLJ** | Outer 행마다 Inner 전체 스캔 | O(N × M) | 인덱스 없고 최적화 불가할 때 (거의 안 씀)                                                         |
| **Index NLJ** |  Outer 행마다 Inner 인덱스 lookup | O(N × logM) | 가장 일반적인 형태, Inner 테이블에 조인 키 인덱스 존재 (데이터가 적은 테이블을 outer, 많은 테이블을 inner로 두는 것이 효율적) |
| **Block NLJ** | Outer 여러 행을 메모리에 담아 Inner 한 번 스캔 | O(N × M) (but buffer 최적화) | Inner에 인덱스 없음, `join_buffer_size` 활용                                              |
| **Batched Key Access** | Outer 여러 키를 모아 batch로 인덱스 lookup | O(N × logM) (batched) | MySQL 5.6+, `optimizer_switch='batched_key_access=on'`                            |
| **Hybrid / Pushdown 변형** | 조건을 가능한 바깥 루프로 이동 | N/A (상황 의존) | `EXISTS`, `IN` 서브쿼리 최적화 등                                                         |


## INNER JOIN과 NLJ
---

```sql
SELECT * FROM T1
    INNER JOIN T2 ON T1.id = T2.id
    INNER JOIN T3 ON T2.key = T3.key
WHERE T1.value > 100
  AND T2.status = 'ACTIVE'
  AND T3.type = 'X';
```

```sql
FOR each t1 in T1 such that (t1.value > 100) {    -- T1에서 바로 필터링
  FOR each t2 in T2 such that (t1.id = t2.id AND t2.status='ACTIVE') {  -- T2 루프에서 바로 필터링
    FOR each t3 in T3 such that (t2.key = t3.key AND t3.type='X') {     -- T3 루프에서 바로 필터링
      OUTPUT t1||t2||t3
    }
  }
}
```

- INNER JOIN은 옵티마이저가 순서를 자유롭게 바꿀 수 있다. (`T1 → T2 → T3` or `T3 → T2 → T1` 등)

### 조건 푸시다운 (Condition Pushdown)
- WHERE 조건은 가능한 경우 바깥 루프로 올려 평가된다.
  - 조건이 참조하는 컬럼이 **이미 읽혀 있는 테이블에만 의존한다면**, 그 조건은 더 바깥쪽 루프로 끌어올려 평가할 수 있다.
  - 이를 통해 각 단계에서 row 수를 줄여, 내부 루프의 불필요한 반복을 줄인다.
  - 위 쿼리에서 `T1.value > 100` 조건은, T1 테이블의 컬럼만 조건에 있으므로 T1을 읽는 가장 바깥 루프에서 바로 필터링 가능.

- 푸시다운 불가능한 경우 : `T1.value > T2.some_val`
  - 두 테이블이 모두 읽힌 뒤에만 평가 가능.

```sql
FOR each t1 in T1 {
  FOR each t2 in T2 such that (T1.id = T2.id AND T1.value > T2.some_val) {
    ...
  }
}
```

- WHERE 절에 있는 조건들을 보고, 어떤 조건을 어느 시점에서 평가해야 가장 효율적인지  INNER JOIN / OUTER JOIN의 제약 조건을 만족하면서 푸시 가능한지를 옵티마이저가 판단한다.

## OUTER JOIN과 NLJ
---

- OUTER JOIN에서는 **NULL 보완(NULL-complemented row)**이 추가된다.
- 외부 테이블의 각 행에 대해 내부 테이블과 매칭이 없으면 NULL로 채운 행이 생성된다.
- 따라서 OUTER JOIN은 조인 순서가 강제된다. (외부 테이블이 반드시 바깥 루프에 위치)
- 매칭이 실제 발생했을 때만 조건을 적용해야 하기 때문에(매칭 없을 때는 NULL 보완 행을 살려야 하므로), INNER JOIN처럼 조건 푸시다운을 단순 적용할 수 없다.
  - 플래그(flag) 기반 조건부 푸시다운을 사용한다.

```sql
SELECT * FROM T1
    LEFT JOIN T2 ON T1.id = T2.id AND T2.status = 'ACTIVE' -- C2
    LEFT JOIN T3 ON T2.key = T3.key AND T3.type = 'X' -- C3
WHERE T1.value > 100; -- C1
```

```sql
FOR each t1 in T1 such that (t1.value > 100) {   -- C1은 T1에서 바로 평가 가능
  f1 := FALSE   -- t1이 T2와 매칭됐는지 여부

  FOR each t2 in T2 such that (t1.id = t2.id) {
    f2 := FALSE   -- (t1,t2)가 T3와 매칭됐는지 여부

    FOR each t3 in T3 such that (t2.key = t3.key) {
      IF (t2.status='ACTIVE' AND t3.type='X') {   -- 매칭된 경우에만 조건 검사
        OUTPUT t1||t2||t3
      }
      f2 = TRUE
      f1 = TRUE
    }

    IF !f2 {   -- T3 매칭이 없을 때
      IF (t2.status='ACTIVE') {   -- T2 매칭은 있었으므로, 조건부 평가
        OUTPUT t1||t2||NULL
      }
      f1 = TRUE
    }
  }

  IF !f1 {   -- T2 매칭이 아예 없을 때
    OUTPUT t1||NULL||NULL   -- T2, T3 NULL 보완 행 출력
    -- 단, WHERE 조건에서 C2, C3는 평가하지 않음 (NULL 보완이므로 무조건 통과)
  }
}
```

## 정리
---
> JOIN 사용시 생각해볼만한 것들

- inner 테이블을 인덱스 탐색하는지, outer / inner 순서는 적절한지 확인하자.
- 가능하면 푸시다운이 잘 적용(최대한 많은 행을 사전 필터링)될 수 있도록 WHERE 조건을 구성하자.
  - 즉, WHERE 조건이 최대한 일찍(outer 루프) 평가될 수 있도록
- OUTER JOIN 사용시:
  - `이 조인에서 NULL 보완이 정말 필요한지`, `WHERE 조건 때문에 어차피 INNER JOIN처럼 동작하지 않는지` 생각해보자.
  - 가능하면 INNER JOIN으로 단순화해서 옵티마이저가 **조인 순서 최적화, 조건 푸시다운**을 최대한 활용하도록 유도.
  - **즉, OUTER JOIN이 정말 필요한지** 생각해보자.

## 참고 자료
---
- [https://dev.mysql.com/doc/refman/8.4/en/nested-loop-joins.html](https://dev.mysql.com/doc/refman/8.4/en/nested-loop-joins.html)
- [https://dev.mysql.com/doc/refman/8.4/en/nested-join-optimization.html](https://dev.mysql.com/doc/refman/8.4/en/nested-join-optimization.html)
