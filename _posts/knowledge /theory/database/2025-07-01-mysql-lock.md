---
title: MySQL - LOCK 살펴보기
date: 2025-07-01 21:00:00 +0900
categories: [지식 더하기, 이론]
tags: [MySQL]
---

> 락을 잘 모르면 비효율적인 쿼리를 작성하거나, 데드락을 유발하거나, 불필요한 성능저하 등을 일으킬 수 있다고 생각한다. 또한 디버깅시 실마리를 못잡을 수도 있다.
> 이런 일을 최대한 겪지 않도록 MySQL에서는 어떤 락을 제공하는지 살펴보자.

## Lock 유형
---

> InnoDB는 **행 수준(row-level) 잠금**을 구현하며(테이블 수준 잠금도 지원), **공유(S, Shared Lock) 잠금**과 **배타(X,  Exclusive Lock) 잠금** 두 가지 유형이 있다.


### Shared Lock
> 공유(S) 잠금

- 해당 잠금을 보유한 트랜잭션이 행을 **읽을 수 있도록 허용**
- 트랜잭션 T1이 행 r에 대해 공유(S) 잠금을 보유하고 있는 경우, 별개의 트랜잭션 T2가 행 r에 대해 잠금을 요청하면 다음과 같이 처리된다:
- T2가 S 잠금을 요청한 경우, 즉시 허용한다.
    - **그 결과, T1과 T2는 모두 r에 대해 S 잠금을 보유하게 된다.**
- T2가 X 잠금을 요청한 경우는 허용하지 않는다.


### Exclusive Lock
> 배타(X) 잠금

- 해당 잠금을 보유한 트랜잭션이 행을 **수정하거나 삭제할 수 있도록 허용**
- 트랜잭션 T1이 행 r에 대해 배타(X) 잠금을 보유하고 있는 경우, 별개의 트랜잭션 T2가 r에 대해 **어떤 종류의 잠금(S 또는 X)을 요청하더라도 허용하지 않는다.**
- 즉, 트랜잭션 T2는 T1이 행 r에 대한 잠금을 해제할 때까지 기다려야 한다.


## Lock 종류
---

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
| **X**             | ❌      | ❌                  | ❌    | ❌               |
| **IX**            | ❌      | ✅                 | ❌    | ✅              |
| **S**             | ❌      | ❌                  | ✅   | ✅              |
| **IS**            | ❌      | ✅                 | ✅   | ✅              |


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
- **유니크 인덱스**를 통해 **특정 행을 찾는 쿼리는 갭 락이 필요 없다.**
- 단, 다중 열 유니크 인덱스 중 **일부 열만 조건에 포함된 경우**에는 예외로, **갭 락이 발생**한다.
- 예를 들어, id 컬럼에 유니크 인덱스가 있다면 다음 쿼리는 id가 100인 행에만 레코드 잠금만 걸리고, 다른 세션이 그 앞에 값을 삽입하더라도 문제되지 않는다.

```sql
SELECT * FROM child WHERE id = 100;
```

- 만약 id가 인덱스가 없거나 유니크하지 않은 인덱스라면, 해당 쿼리는 앞쪽 갭에도 잠금을 건다.
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
- S Gap Lock과 X Gap Lock은 MySQL 사용자의 관점에서는 구분되지만, 내부적으로는 **"갭에 대한 삽입 차단"**이라는 동일한 효과를 가짐.
- 따라서 실제로는 갭을 잠갔는지 여부만 중요. 즉, 삽입이 가능/불가능이 핵심이지, "공유냐 배타냐"는 큰 의미가 없음
- 다만, 사용자 또는 SQL 구문 단위로는 정확한 트랜잭션 격리 수준 표현을 위해 구분함.
  - 즉, **쿼리의 의도(intent)**를 명확히 하기 위해 SQL 레벨에서 구분하는 것

```sql
SELECT ... FOR UPDATE: "나는 값을 수정할 수도 있어" → X Gap Lock
SELECT ... LOCK IN SHARE MODE: "나는 읽기만 할 거야" → S Gap Lock
```

**※ 필터링 조건과 갭 락**
- 유니크 인덱스를 통해 특정 행을 찾는 쿼리는 갭 락이 필요 없다.
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
SELECT * FROM product WHERE id = 123 FOR UPDATE LIMIT 1;
```

- 정확한 유니크 인덱스를 이용한 조건 + LIMIT
- 이 경우는 정확히 한 row만 찾아서 그 row만 record lock (X) 걸림

### Next-Key Lock
> 인덱스 레코드에 대한 레코드 락과, 그 앞에 있는 갭에 대한 갭 락의 조합

- InnoDB는 테이블 인덱스를 검색하거나 스캔할 때, **발견한 인덱스 레코드에 공유 또는 배타 잠금을 설정**하는 방식으로 행 수준 잠금을 수행한다.
  - 따라서, 행 수준 잠금은 실제로는 인덱스 레코드 잠금이다.

| 인덱스 유형 | next-key lock 기준 컬럼 |
| ------------------- | -------------------------------------------------------------- |
| **유니크 인덱스** (단일/복합) | **모든 인덱스 컬럼이 완전히 조건에 포함되어야** 정확히 1건만 잠금 (→ gap lock 없음)        |
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
  - Gap Lock만 발생한 경우로, 보통 범위 조건이나 범위 외 레코드가 없을 때 발생

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
- [https://dev.mysql.com/doc/refman/8.4/en/innodb-locking.html](https://dev.mysql.com/doc/refman/8.4/en/innodb-locking.html)
