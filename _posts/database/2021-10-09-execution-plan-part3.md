---
title: MySQL 실행 계획 (3)
date: 2021-10-09 23:00:00 +0900
categories: [Database]
tags: [MySQL, 실행 계획]
---

# 들어가기 전
---
실행 계획을 나타내는 테이블의 다양한 컬럼들 중 possible_keys, key, key_len, ref, rows, Extra 컬럼에 대해 살펴볼 것이다. <br>
또한 `EXPLAIN` 명령 이외에 `EXPLAIN EXTENDED`, `EXPLAIN FF` 대해서도 알아보자.

※ [실행 계획 1편](https://zz9z9.github.io/posts/execution-plan-part1/), [실행 계획 2편](https://zz9z9.github.io/posts/execution-plan-part2/)을 먼저 읽으실 것을 권장합니다.

# possible_keys 컬럼
---
> 옵티마이저가 최적의 실행 계획을 만들기 위해 후보로 선정했던 접근 방식에서 사용되는 인덱스의 목록이다.

- 즉, 사용될 법했던 인덱스의 목록이다.
- 해당 테이블의 모든 인덱스가 포함되어 나오는 경우가 많기 때문에 쿼리를 튜닝하는 데 도움이 되지 않는다.

# key 컬럼
---
> 최종 선택된 실행 계획에서 사용하는 인덱스이다.

- 쿼리를 튜닝할 때는 key 컬럼에 의도했던 인덱스가 표시되는지 확인하는 것이 중요하다.
- 값이 'PRIMARY'인 경우에는 프라이머리 키를 사용한다는 의미이다.
  - 그 외에는 모두 테이블이나 인덱스를 생성할 때 부여했던 고유 이름이다.
  - 테이블 풀 스캔 방식 처럼 인덱스를 사용하지 못하는 경우에는 'NULL'로 표시된다.
  - type 컬럼의 값이 'index_merge'인 경우에는 2개 이상의 값이 표시된다.


# key_len 컬럼
---
> 단일, 다중 컬럼으로 구성된 인덱스에서 몇 개의 컬럼까지 사용했는지 알려준다. 즉, 각 레코드에서 몇 바이트까지 사용했는지를 알려주는 값이다.

- dept_emp 테이블의 프라이머리 키는 dept_no, emp_no 두 개의 컬럼으로 구성되어있다.
  - dept_no 컬럼의 타입은 `CHAR(4)`이며 UTF8 문자집합을 사용한다.
  - 아래 쿼리는 조회시 dept_no만 사용하고 있으므로 결과적으로 key_len의 값은 12로 표시된다.
  - 즉, UTF8 문자를 위한 메모리 공간은 3바이트이기 때문에 3*4=12(byte) 라는 값이 도출된다.

```sql
EXPLAIN
SELECT * FROM dept_emp WHERE dept_no='d005';
```

| id | select_type | table | type | key | key_len | ref | rows | Extra |
|----|-------------|-------|------|-----|---------|-----|------|-------|
| 1 | SIMPLE | dept_emp |ref|PRIMARY|12|const|53288|Using where|

- 프라이머리 키를 구성하는 두 개의 컬럼을 다 사용한 경우이다.
  - emp_no 컬럼 타입은 `INTEGER`이며 4바이트를 차지한다.

```sql
EXPLAIN
SELECT * FROM dept_emp WHERE dept_no='d005' AND emp_no=10001;
```

| id | select_type | table | type | key | key_len | ref | rows | Extra |
|----|-------------|-------|------|-----|---------|-----|------|-------|
| 1 | SIMPLE | dept_emp |ref|PRIMARY|16|const,const|1||

## MySQL 5.0 vs MySQL 5.1
> 아래와 같은 쿼리가 있을 때 MySQL 5.0 버전과 5.1 버전에서의 결과가 어떤 차이가 있는지 살펴보자.
> dept_emp 테이블의 프라이머리 키는 dept_no, emp_no으로 구성된다.

```sql
EXPLAIN
SELECT * FROM dept_emp WHERE dept_no='d005' AND emp_no <> 10001;
```

- MySQL 5.0 이하
  - 프라이머리 키인 dept_no, emp_no을 모두 사용했지만 key_len은 16이 아닌 12로 표시된다.
  - 그 이유는 key_len에 표시되는 값은 인덱스를 이용해 범위를 제한하는 조건의 컬럼까지만 포함되기 때문이다.
  - 즉, 체크 조건(`emp_no <> 10001`)으로 사용되는 emp_no의 경우는 key_len에 포함되지 않는다.
  - 결과적으로 5.0 이하 버전에서는 key_len 컬럼의 값으로 인덱스의 몇 바이트까지가 범위 제한 조건으로 사용됐는지 판단할 수 있다.

| id | select_type | table | type | key | key_len | ref | rows | Extra |
|----|-------------|-------|------|-----|---------|-----|------|-------|
| 1 | SIMPLE | dept_emp |ref|PRIMARY|12|const|53298|Using where|

- MySQL 5.1 이상
  - 체크 조건에 포함되는 컬럼까지 계산된 값이 key_len에 표시된다.
  - 결과적으로 인덱스의 몇 바이트까지가 범위 제한 조건으로 사용됐는지 알 수 없다.

| id | select_type | table | type | key | key_len | ref | rows | Extra |
|----|-------------|-------|------|-----|---------|-----|------|-------|
| 1 | SIMPLE | dept_emp |range|PRIMARY|16||53298|Using where|

## 컨디션 푸시 다운(Condition push down)
> 위에서 살펴본 차이는 버전이 올라가면서 MySQL 엔진과 InnoDB 스토리지 엔진의 역할 분담에 변화가 생겼기 때문이다.

- 5.0 버전까지는 범위 제한 조건으로 사용되는 컬럼만 스토리지 엔진으로 전달했다.
- 5.1 버전부터는 범위 제한 조건이든 체크 조건이든 인덱스를 이용할 수만 있다면 모두 스토리지 엔진으로 전달한다.
  - 이를 **컨디션 푸시 다운**이라고 한다.

# ref 컬럼
---
> type 컬럼의 값(접근 방식)이 'ref'이면 ref 컬럼에서는 어떤 값이 제공됐는지 표시된다.

- 상수 값을 지정했다면 ref 컬럼의 값은 const로 표시된다.
- 다른 테이블의 컬럼이라면 그 테이블 명과 컬럼 명이 표시된다.

```sql
EXPLAIN
SELECT * FROM employees e, dept_emp de
WHERE e.emp_no=de.emp_no;
```

| id | select_type | table | type | key | key_len | ref | rows | Extra |
|----|-------------|-------|------|-----|---------|-----|------|-------|
| 1 | SIMPLE | de |ALL||||334868||
| 1 | SIMPLE | e |eq_ref|PRIMARY|4|de.emp_no|1||

- 만약 ref 컬럼의 값이 'func'라면 이는 참조용으로 사용되는 값을 그대로 사용한 것이 아니라, 콜레이션 변환이나 값 자체의 연산을 거쳐서 참조됐다는 것을 의미한다.
- 사용자가 명시적으로 값을 변환할 때뿐만 이나리 MySQL 서버가 내부적으로 값을 변환해야 할 때도 'func'가 출력된다.
- 대표적인 경우는 다음과 같다.
  - 문자집합이 일치하지 않는 두 문자열 컬럼을 조인하는 경우
  - 숫자 타입의 컬럼과 문자열 타입의 컬럼으로 조인하는 경우
- 가능한 MySQL이 이런 변환을 하지 않아도 되도록 조인 컬럼의 타입은 일치시키는 것이 좋다.

```sql
EXPLAIN
SELECT * FROM employees e, dept_emp de
WHERE e.emp_no=(de.emp_no-1);
```

| id | select_type | table | type | key | key_len | ref | rows | Extra |
|----|-------------|-------|------|-----|---------|-----|------|-------|
| 1 | SIMPLE | de |ALL||||334868||
| 1 | SIMPLE | e |eq_ref|PRIMARY|4|func|1||


# rows 컬럼
---
> 실행 계획의 효율성 판단을 위해 예측했던 레코드 건수를 보여준다. 각 스토리지 엔진별로 갖고 있는 통계 정보를 참조해 옵티마이저가 산출한 예상 값이라 정확하지는 않다.

- 각 실행 계획의 비용을 산정하는 방법은 각 처리 방식이 얼마나 많은 레코드를 읽고 비교해야 하는지 예측해 보는 것이다.
  - 즉, 대상 테이블에 얼마나 많은 레코드가 포함되는지, 인덱스 값의 분포도가 어떤지를 기준으로 조사해서 예측한다.
- rows 컬럼에 표시되는 값은 반환하는 레코드의 예측치가 아니라, 쿼리를 처리하기 위해 얼마나 많은 레코드를 디스크로부터 읽고 체크해야 하는지를 의미한다.

- 아래 쿼리의 경우 ix_fromdate 인덱스를 사용할 수도 있었지만, 결과적으로는 테이블 풀 스캔(ALL) 방식을 사용한다.
  - dept_emp 테이블의 전체 레코드는 331,603 건이라고 한다.
  - rows 컬럼을 보면 옵티마이저는 이 쿼리를 처리하기 위해 대략 334,868건의 레코드를 읽어야 할 것이라고 예측했다.
    - 즉, 옵티마이저는 전체 레코드의 대부분을 비교해봐야 한다고 판단했기 때문에 인덱스 레인지 스캔이 아닌 'ALL'을 선택했다.

```sql
EXPLAIN
SELECT * FROM dept_emp WHERE from_date>='1985-01-01';
```

| id | select_type | table | type |possible_keys | key | key_len | ref | rows | Extra |
|----|-------------|-------|------|-----|----|---------|-----|------|-------|
| 1 | SIMPLE | dept_emp |ALL|ix_fromdate||||334868|Using<br>where|

- 위의 쿼리에서 범위를 좁혀보자.
  - 옵티마이저는 292 건의 레코드(전체 레코드의 8.8%)를 읽으면 아래 쿼리를 처리할 수 있을 것으로 예측했다.
  - 따라서, 인덱스 레인지 스캔 방식을 선택했다.

```sql
EXPLAIN
SELECT * FROM dept_emp WHERE from_date>='2002-07-01';
```

| id | select_type | table | type |possible_keys | key | key_len | ref | rows | Extra |
|----|-------------|-------|------|-----|----|---------|-----|------|-------|
| 1 | SIMPLE | dept_emp |range|ix_fromdate|ix_fromdate|3||292|Using<br>where|

# Extra 컬럼
---


# 관련 글
---
- [MySQL 실행 계획 (1)](https://zz9z9.github.io/posts/execution-plan-part1/)
- [MySQL 실행 계획 (2)](https://zz9z9.github.io/posts/execution-plan-part2/)

# 참고 자료
---
- 이성욱, 『개발자와 DBA를 위한 Real MySQL』, 위키북스(2012), 6장
