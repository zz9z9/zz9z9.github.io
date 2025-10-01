
기본적인 것들을 알아보자


## Nested-Loop Join Algorithm
---

- MySQL은 테이블 간 조인을 수행할 때, 중첩 루프(nested-loop) 알고리즘 또는 그 변형들을 사용한다.
- 간단한 중첩 루프 조인(NLJ) 알고리즘은 첫 번째 테이블에서 행(row)을 하나씩 읽고, 그 행을 다음 테이블을 처리하는 중첩 루프에 전달한다. 이 과정은 조인해야 할 테이블이 남아있는 한 반복된다.
- 예를 들어, 세 개의 테이블 t1, t2, t3 사이의 조인이 다음과 같은 조인 유형으로 실행된다고 가정해보자:

```
Table   Join Type
t1      range
t2      ref
t3      ALL
```

- 단순한 NLJ 알고리즘이 사용되면, 조인은 이런식으로 처리된다:

```java
for each row in t1 matching range {
  for each row in t2 matching reference key {
    for each row in t3 {
      if row satisfies join conditions, send to client
    }
  }
```

- Nested Loop Join (NLJ) 은 바깥 루프(outer loop)의 row를 한 줄씩 안쪽 루프(inner loop)에 전달함.
- 그래서 안쪽 테이블(inner table)은 바깥 테이블 row마다 반복해서 읽히게 됨.

- 예시1 : 인덱스 없음

```sql
SELECT *
FROM Customers c
JOIN Orders o ON c.id = o.customer_id;
```

Customers: 100 rows
Orders: 100,000 rows

Case 1: Customers outer
Customers 100개 row 각각 → Orders 100,000개 스캔
→ 총 100 × 100000 = 10,000,000번 비교

Case 2: Orders outer
Orders 100,000개 row 각각 → Customers 100개 스캔
→ 총 100000 × 100 = 10,000,000번 비교

**즉, 풀스캔일 땐 outer/inner 순서 무의미**

- 예시2 : 현실에서는 보통 outer는 작은 테이블, inner는 큰 테이블 + 인덱스 탐색 조합으로 가야 효율적
작은 outer row 수 × (inner 테이블 인덱스 탐색) = 훨씬 적은 비용

Customers : 100 rows (작음)
Orders : 100,000 rows (큼)

Customers.id 와 Orders.customer_id 모두 인덱스 있음

Case 1: Customers outer, Orders inner
for each c in Customers (100 rows) {
probe Orders using index on Orders.customer_id
}


Orders 전체를 스캔하지 않음.

각 고객당 해당하는 주문만 인덱스로 빠르게 찾음.

총 인덱스 탐색 횟수 = 100번.

Case 2: Orders outer, Customers inner
for each o in Orders (100,000 rows) {
probe Customers using index on Customers.id
}


Orders 100,000개 row 각각 Customers 인덱스 lookup → 100,000번 탐색.

비용이 훨씬 큼.

🔹 결론

작은 테이블을 outer로 두고, 큰 테이블을 inner로 두면서 인덱스를 활용하는 게 최적

즉 이 경우는 Customers → outer, Orders → inner가 맞습니다 ✅

🔹 추가로

MySQL 옵티마이저는 **통계정보(테이블 크기, 인덱스 카디널리티)**를 바탕으로 자동으로 join order를 결정합니다.
그래서 실제로는 우리가 굳이 강제하지 않아도 보통은 Customers를 outer로 둡니다.

다만, 통계가 부정확하거나 옵티마이저 판단이 비효율적일 때는 STRAIGHT_JOIN이나 JOIN ORDER 힌트를 써서 순서를 고정하기도 해요.

## INNER JOIN
---
예를 들어, 세 개의 테이블 T1, T2, T3에 대한 조인 쿼리가 다음과 같다고 합시다:

```sql
SELECT * FROM T1 INNER JOIN T2 ON P1(T1,T2)
INNER JOIN T3 ON P2(T2,T3)
WHERE P(T1,T2,T3)
```

```sql
SELECT *
FROM T1
INNER JOIN T2 ON T1.id = T2.id
INNER JOIN T3 ON T2.key = T3.key
WHERE T1.value > 100    -- C1(T1)
  AND T2.status = 'ACTIVE'  -- C2(T2)
  AND T3.type = 'X';        -- C3(T3)

```

여기서 P1(T1,T2)와 P2(T2,T3)는 조인 조건(ON 표현식)이고, P(T1,T2,T3)는 T1, T2, T3의 컬럼에 대한 조건입니다.

중첩 루프 조인 알고리즘은 위 쿼리를 다음과 같이 실행합니다:
=>
```
FOR each row t1 in T1 {
  FOR each row t2 in T2 such that P1(t1,t2) {
    FOR each row t3 in T3 such that P2(t2,t3) {
      IF P(t1,t2,t3) {
         t:=t1||t2||t3; OUTPUT t;
      }
    }
  }
}
```

여기서 t1||t2||t3 표기는 t1, t2, t3 행의 컬럼을 단순히 이어붙여 만든 결과 행을 의미합니다.

INNER JOIN이 있는 쿼리에서는, 옵티마이저가 중첩 루프의 순서를 다르게 선택할 수도 있습니다. 예를 들어 다음과 같이 실행할 수 있습니다:

```
FOR each row t3 in T3 {
  FOR each row t2 in T2 such that P2(t2,t3) {
    FOR each row t1 in T1 such that P1(t1,t2) {
      IF P(t1,t2,t3) {
         t:=t1||t2||t3; OUTPUT t;
      }
    }
  }
}
```

- INNER JOIN의 중첩 루프 알고리즘을 논의할 때, 성능에 큰 영향을 미칠 수 있는 몇 가지 중 하나가 바로 **“조건 푸시다운(pushed-down conditions)”**입니다.
- 예를 들어 WHERE 조건 P(T1,T2,T3)가 다음과 같은 AND 결합식으로 표현될 수 있다고 합시다:

```
P(T1,T2,T3) = C1(T1) AND C2(T2) AND C3(T3)
```

- 이 경우 MySQL은 INNER JOIN 쿼리를 실제로 다음과 같은 중첩 루프 알고리즘으로 실행합니다:

```
FOR each row t1 in T1 such that C1(t1) {
  FOR each row t2 in T2 such that P1(t1,t2) AND C2(t2) {
    FOR each row t3 in T3 such that P2(t2,t3) AND C3(t3) {
      IF P(t1,t2,t3) {
         t:=t1||t2||t3; OUTPUT t;
      }
    }
  }
}
```

보시는 것처럼, 각 조건식 C1(T1), C2(T2), C3(T3)는 가능한 한 가장 안쪽 루프에서 바깥쪽 루프로 밀어올려(push down) 평가됩니다.

만약 C1(T1)이 매우 제한적인 조건이라면, 이 조건 푸시다운 덕분에 T1에서 내부 루프로 전달되는 행의 수가 크게 줄어듭니다. 그 결과 쿼리 실행 시간이 크게 개선될 수 있습니다.
=> 옵티마이저가 WHERE 조건을 언제 평가하느냐에 있음.  조건 push-down 덕분에 row 수를 줄여서 효율적 실행 가능.
### OUTER JOIN

```sql
SELECT * FROM T1 LEFT JOIN
  (T2 LEFT JOIN T3 ON P2(T2,T3))
  ON P1(T1,T2)
WHERE P(T1,T2,T3)
```

=>

```sql
FOR each row t1 in T1 {
  BOOL f1:=FALSE; -- 현재 t1과 매칭되는 t2가 있었는가 ?

  FOR each row t2 in T2 such that P1(t1,t2) {
    BOOL f2:=FALSE; -- 현재 t2와 매칭되는 t3가 있었는가 ?

    FOR each row t3 in T3 such that P2(t2,t3) {
      IF P(t1,t2,t3) {
        t:=t1||t2||t3; OUTPUT t;
      }
      f2=TRUE;
      f1=TRUE;
    }

    IF (!f2) {
      IF P(t1,t2,NULL) {
        t:=t1||t2||NULL; OUTPUT t;
      }
      f1=TRUE;
    }

  }

  IF (!f1) {
    IF P(t1,NULL,NULL) {
      t:=t1||NULL||NULL; OUTPUT t;
    }
  }

}
```

=>  (T2 ⟕ T3) 결과 자체가 먼저 만들어져서 T1 루프에 들어옴 → T1이 볼 땐 이미 NULL 보정된 row.

```sql
SELECT * FROM T1
  LEFT JOIN T2 ON P1(T1,T2)
  LEFT JOIN T3 ON P2(T2,T3)
WHERE P(T1,T2,T3)
```

```sql
FOR each row t1 in T1 {
  BOOL f1 := FALSE;   -- T1이 T2와 매칭됐는지 체크

  FOR each row t2 in T2 such that P1(t1,t2) {
    BOOL f2 := FALSE;   -- (t1,t2)가 T3와 매칭됐는지 체크

    FOR each row t3 in T3 such that P2(t2,t3) {
      IF P(t1,t2,t3) {
        t := t1 || t2 || t3; OUTPUT t;
      }
      f2 = TRUE;
      f1 = TRUE;
    }

    IF (!f2) {
      -- (t1,t2)와 매칭되는 T3가 없으면 T3=NULL
      IF P(t1,t2,NULL) {
        t := t1 || t2 || NULL; OUTPUT t;
      }
      f1 = TRUE;
    }

  }

  IF (!f1) {
    -- T1과 매칭되는 T2가 아예 없으면 T2=NULL, T3=NULL
    IF P(t1,NULL,NULL) {
      t := t1 || NULL || NULL; OUTPUT t;
    }
  }

}
```

=> (T1 ⟕ T2)가 먼저라서 T2=NULL인 상태가 T3 루프까지 흘러감 → T3 조인 시도가 다르게 동작.


특정 테이블 자리에 NULL이 나타난 경우는 그 테이블의 모든 컬럼이 NULL로 채워진 행을 의미합니다. 예를 들어 t1||t2||NULL은 t1과 t2의 컬럼들을 붙이고, t3의 모든 컬럼에는 NULL을 채워 넣은 행을 나타냅니다. 이런 행을 NULL 보완(NULL-complemented) 행이라고 부릅니다.

일반적으로, OUTER JOIN 연산에서 첫 번째 내부 테이블(inner table)에 대한 중첩 루프에서는 플래그(flag)가 도입됩니다.
이 플래그는 루프 전에 꺼지고(off), 루프 이후에 확인됩니다.
외부 테이블의 현재 행이 내부 테이블과 매칭되면 플래그가 켜집니다(on).
루프가 끝났을 때도 플래그가 꺼져 있으면, 현재 외부 행에 매칭되는 내부 행이 없었다는 뜻입니다. 이 경우, 내부 테이블의 컬럼들은 NULL로 채워져서 결과 행이 생성됩니다.
이 결과 행은 최종 출력 조건 검사를 거치거나, 다음 중첩 루프에 전달됩니다. 단, 그 행이 포함된 모든 OUTER JOIN 조건을 만족할 때만 전달됩니다.

- OUTER JOIN이 포함된 쿼리에서는, 옵티마이저가 루프 순서를 선택할 때 항상 외부 테이블의 루프가 내부 테이블의 루프보다 앞서야 합니다.
- 따라서 OUTER JOIN이 있는 쿼리에서는 가능한 중첩 순서가 하나뿐입니다.

```sql
SELECT * T1 LEFT JOIN (T2,T3) ON P1(T1,T2) AND P2(T1,T3)
  WHERE P(T1,T2,T3)
```

- 이 경우, 옵티마이저는 두 가지 다른 중첩을 평가합니다.
- 두 경우 모두 T1은 OUTER JOIN에 사용되므로, 반드시 외부 루프에서 처리됩니다.
- T2와 T3는 INNER JOIN에 사용되므로, 내부 루프에서 처리됩니다.
- 그러나 INNER JOIN은 순서가 자유롭기 때문에, T2 → T3 또는 T3 → T2 둘 다 가능합니다.

- 한 가지 중첩은 T2를 먼저, 그 다음 T3를 평가합니다:

```
FOR each row t1 in T1 {
  BOOL f1:=FALSE;
  FOR each row t2 in T2 such that P1(t1,t2) {
    FOR each row t3 in T3 such that P2(t1,t3) {
      IF P(t1,t2,t3) {
        t:=t1||t2||t3; OUTPUT t;
      }
      f1:=TRUE
    }
  }
  IF (!f1) {
    IF P(t1,NULL,NULL) {
      t:=t1||NULL||NULL; OUTPUT t;
    }
  }
}
```

- 다른 중첩은 T3를 먼저, 그 다음 T2를 평가합니다:

```
FOR each row t1 in T1 {
  BOOL f1:=FALSE;
  FOR each row t3 in T3 such that P2(t1,t3) {
    FOR each row t2 in T2 such that P1(t1,t2) {
      IF P(t1,t2,t3) {
        t:=t1||t2||t3; OUTPUT t;
      }
      f1:=TRUE
    }
  }
  IF (!f1) {
    IF P(t1,NULL,NULL) {
      t:=t1||NULL||NULL; OUTPUT t;
    }
  }
}
```

- OUTER JOIN이 포함된 쿼리에서는 WHERE 조건은 외부 테이블의 현재 행이 내부 테이블과 매칭된 이후에만 검사됩니다.
- 따라서 INNER JOIN에서처럼 단순히 조건을 푸시다운하는 최적화는 OUTER JOIN 쿼리에는 직접적으로 적용할 수 없습니다.
- 이 경우에는, 매칭이 발견되었을 때 켜지는 플래그(flag)에 의해 제어되는 **조건부(conditionally) 푸시다운 술어(predicate)**를 도입해야 합니다.
- 다시 OUTER JOIN 예제를 보겠습니다:

```sql
SELECT * T1 LEFT JOIN (T2,T3) ON P1(T1,T2) AND P2(T1,T3)
  WHERE P(T1,T2,T3)
```


```
P(T1,T2,T3)=C1(T1) AND C2(T2) AND C3(T3)
```

- 이 경우, 플래그에 의해 제어되는 푸시다운 조건을 사용하는 중첩 루프 알고리즘은 다음과 같이 표현됩니다:

```
FOR each row t1 in T1 such that C1(t1) {
  BOOL f1:=FALSE;
  FOR each row t2 in T2
      such that P1(t1,t2) AND (f1?C2(t2):TRUE) {
    BOOL f2:=FALSE;
    FOR each row t3 in T3
        such that P2(t2,t3) AND (f1&&f2?C3(t3):TRUE) {
      IF (f1&&f2?TRUE:(C2(t2) AND C3(t3))) {
        t:=t1||t2||t3; OUTPUT t;
      }
      f2=TRUE;
      f1=TRUE;
    }
    IF (!f2) {
      IF (f1?TRUE:C2(t2) && P(t1,t2,NULL)) {
        t:=t1||t2||NULL; OUTPUT t;
      }
      f1=TRUE;
    }
  }
  IF (!f1 && P(t1,NULL,NULL)) {
      t:=t1||NULL||NULL; OUTPUT t;
  }
}
```

- 일반적으로, 푸시다운 술어(predicate)는 P1(T1,T2)나 P(T2,T3)와 같은 조인 조건에서 추출될 수 있습니다. 이 경우에도 푸시다운된 술어는 해당 OUTER JOIN 연산에서 생성된 **NULL 보완 행(NULL-complemented row)**에 대해 조건 검사가 수행되지 않도록 플래그에 의해 제어됩니다.

또한 동일한 중첩 조인 안에서, WHERE 조건의 술어로 인해 한 내부 테이블에서 다른 내부 테이블로 키 기반 접근이 유도되는 것은 금지됩니다.

### Driving Table, Driven Table


## 참고 자료
---
- [https://dev.mysql.com/doc/refman/8.4/en/nested-loop-joins.html](https://dev.mysql.com/doc/refman/8.4/en/nested-loop-joins.html)
- [https://dev.mysql.com/doc/refman/8.4/en/nested-join-optimization.html](https://dev.mysql.com/doc/refman/8.4/en/nested-join-optimization.html)
