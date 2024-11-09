---
title: MySQL - MySQL 실행 계획 (3)
date: 2021-10-09 23:00:00 +0900
categories: [지식 더하기, 이론]
tags: [MySQL]
---

# 들어가기 전
---
실행 계획을 나타내는 테이블의 다양한 컬럼들 중 possible_keys, key, key_len, ref, rows, Extra 컬럼에 대해 살펴볼 것이다. <br>
또한 `EXPLAIN` 명령 이외에 `EXPLAIN EXTENDED`, `EXPLAIN PARTITIONS` 대해서도 알아보자.

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
- 사용자가 명시적으로 값을 변환할 때뿐만 아니라 MySQL 서버가 내부적으로 값을 변환해야 할 때도 'func'가 출력된다.
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
컬럼의 이름과 달리, 성능에 관련된 중요한 내용이 자주 표시된다. 다 알아보기엔 너무 많기 때문에 카테고리 별로 나눠서 몇 가지만 살펴보자. <br>

## 1. 쿼리가 요건을 제대로 반영하고 있는지 확인해야 하는 경우
> 아래와 같은 코멘트가 표시된다면 쿼리가 요건을 제대로 반영해서 작성됐는지, 버그가 생길 가능성은 없는지 확인해야 한다.
> 즉, 아래 항목들은 "이런 레코드가 없음"이라는 의미가 강하기 때문에, 이로 인한 버그의 가능성에 대해 검토해야 한다.
> 한 가지 주의할 점은 'Impossible WHERE ...', 'No matching ...' 등의 메시지는 쿼리의 실행 계획을 산출하기 위한 기초 자료가 없음을 표현하는 것이므로
> 실제 쿼리 오류가 발생한다고 생각해서는 안된다.

### Full scan on NULL key
> `col1 IN (SELECT ... FROM ...)`과 같은 조건에서 col1이 NULL인 경우 예비책으로 풀 테이블 스캔을 사용할 것이라는 사실을 알려주는 키워드이다.

- `col1 IN (SELECT ... FROM ...)`과 같은 조건이 포함된 쿼리에서 col1이 NULL이라면?
  - 연산을 수행하기 위해 위 조건은 다음과 같이 비교돼야 한다.
    - 서브 쿼리가 1건이라도 결과 레코드를 가진다면 최종 비교 결과는 NULL
    - 서브 쿼리가 1건도 결과 레코드를 가지지 않는다면 최종 비교 결과는 FALSE
  - 위와 같은 비교 과정은 col1이 NULL이기 때문에, 풀 테이블 스캔을 해야만 결과를 알아낼 수 있다.

```sql
EXPLAIN
SELECT d.dept_no, NULL IN (SELECT id.dpet_name FROM departments id)
FROM departments d;
```

| id | select_type | table | type | key | key_len | ref | rows | Extra |
|----|-------------|-------|------|----|---------|-----|------|-------|
| 1 | PRIMARY | d |index|ux_deptname|123|NULL|9|Using index|
| 1 | DEPENDENT<br>SUBQUERY | id |index_subquery|ux_deptname|123|const|2|Using index;<br>Full scan on NULL key|

- 만약 컬럼이 `NOT NULL`로 정의되지는 않았지만 이러한 NULL 비교 규칙을 무시해도 된다면, col1이 절대 NULL이 될 수 없다는 것을 옵티마이저에게 알려주면 된다.
- 대표적으로 다음과 같은 방법이 있다.
  - col1이 NULL이면 `col1 IS NOT NULL` 조건이 FALSE가 되기 때문에 그 아래 조건은 실행하지 않는다.

```sql
EXPLAIN
SELECT * FROM tb_test1
WHERE col1 IS NOT NULL
    AND col1 IN (SELECT col2 FROM tb_test2);
```

### Impossible HAVING (5.1 버전부터)
> 쿼리에 사용된 `HAVING`절의 조건을 만족하는 레코드가 없는 경우이다. 이런 경우, 쿼리가 제대로 작성되지 못한 경우가 대부분이므로 다시 검토해보는 것이 좋다.

- 아래 쿼리에서 emp_no 컬럼은 프라이머리 키이면서 NOT NULL 타입의 컬럼이다.
- 따라서, 절대 `e.emp_no IS NULL` 조건을 만족할 가능성이 없다.

```sql
EXPLAIN
SELECT e.emp_no, COUNT(*) AS cnt
FROM employees e
WHERE e.emp_no=10001
GROUP BY e.emp_no
HAVING e.emp_no IS NULL;
```

| id | select_type | table | type | key | key_len | ref | rows | Extra |
|----|-------------|-------|------|----|---------|-----|------|-------|
| 1 | SIMPLE |||||||Impossible HAVING|


### Impossible WHERE (5.1 버전부터)
> `WHERE` 조건이 항상 FALSE가 될 수 밖에 없는 경우이다.

```sql
EXPLAIN
SELECT * FROM employees WHERE emp_no IS NULL;
```

| id | select_type | table | type | key | key_len | ref | rows | Extra |
|----|-------------|-------|------|----|---------|-----|------|-------|
| 1 | SIMPLE |||||||Impossible WHERE|


### Impossible WHERE noticed after reading const tables
> 쿼리에서 const 접근 방식이 필요한 부분은 실행 계획 수립 단계에서 옵티마이저가 직접 쿼리의 일부를 실행하고, 실행된 결과 값을 원본 쿼리의 상수로 대체한다.
> 이 과정을 마친 뒤, 불가능한 조건으로 판단되는 경우이다.

- 아래의 경우, 실행 계획만 확인했을 뿐인데, 옵티마이저는 사번이 0번인 사원이 없다는 것까지 확인한다.

```sql
EXPLAIN
SELECT * FROM employees WHERE emp_no=0;
```

| id | select_type | table | type | key | key_len | ref | rows | Extra |
|----|-------------|-------|------|----|---------|-----|------|-------|
| 1 | SIMPLE |||||||Impossible WHERE noticed<br>after reading const tables|


### No matching min/max row (5.1 버전부터)
> `MIN()`, `MAX()`와 같은 집합 함수가 있는 쿼리의 조건절에 일치하는 레코드가 한 건도 없는 경우이다,

- 집합 함수의 결과로는 NULL이 반환된다.

```sql
EXPLAIN
SELECT MIN(dept_no), MAX(dept_no)
FROM dept_emp WHERE dept_no='';
 ```

| id | select_type | table | type | key | key_len | ref | rows | Extra |
|----|-------------|-------|------|----|---------|-----|------|-------|
| 1 | SIMPLE |||||||No matching min/max row|

### No matching row in const table (5.1 버전부터)
> 조인에 사용된 테이블에서 const 방식으로 접근할 때, 일치하는 레코드가 없는 경우이다.

```sql
EXPLAIN
SELECT *
FROM dept_emp de,
(SELECT emp_no FROM employees WHERE emp_no=0) tb1
WHERE tb1.emp_no=de.emp_no AND de.dept_no='d005';
 ```

| id | select_type | table | type | key | key_len | ref | rows | Extra |
|----|-------------|-------|------|----|---------|-----|------|-------|
| 1 | PRIMARY |||||||Impossible WHERE noticed<br>after reading const tables|
| 2 | DERIVED |||||||no matching row in const table|

### Unique row not found (5.1 버전부터)
> 두 개의 테이블이 각각 유니크(프라이머리 키 포함) 컬럼으로 아우터 조인을 수행하는 쿼리에서, 아우터 테이블에 일치하는 레코드가 존재하지 않는 경우이다.

- t2 테이블에 프라이머리 키인 fdpk의 값이 1인 레코드만 있다고 가정해보자.

```sql
EXPLAIN
SELECT t1.fdpk
FROM tb_test1 t1
  LEFT JOIN tb_test2 t2 ON t2.fdpk=t1.fdpk
WHERE t1.fdpk=2;
 ```

| id | select_type | table | type | key | key_len | ref | rows | Extra |
|----|-------------|-------|------|----|---------|-----|------|-------|
| 1 | SIMPLE |t1|const|PRIMARY|4|const|1|Using index|
| 2 | SIMPLE |t2|const|PRIMARY|4|const|0|unique row not found|

<br>

## 2. 쿼리의 실행 계획이 좋지 않은 경우
> 아래와 같은 코멘트가 표시된다면 쿼리를 더 최적화할 수 있는지 검토해보는 것이 좋다. 특히, 'Using where'의 경우 대부분의 쿼리에서 표시되기 때문에 그냥 지나치기 쉬운데,
> 만약 실행 계획의 rows 컬럼 값이 실제 SELECT되는 레코드 건수보다 훨씬 더 높은 경우에는 둘의 차이를 줄이는 것이 중요하다.

### Range checked for each record (index map:N)
> 매 레코드마다 인덱스 레인지 스캔을 할지, 풀 테이블 스캔을 할지 결정한다.

- 아래 쿼리 처럼 조인 조건에 상수가 없고 둘 다 변수인 경우, e1 테이블의 레코드를 하나씩 읽을 때 마다 e1.emp_no 값이 계속 바뀌므로 쿼리의 비용 계산을 위한 기준값이 계속 변한다.
  - 따라서, 어떤 접근 방법으로 e2 테이블을 읽는 것이 좋을지 판단할 수 없는 것이다.
- '(index map: 0x1)'은 사용할지 말지를 판단하는 후보 인덱스의 순번을 나타낸다.
  - 어떤 인덱스인지 확인하려면 16진수를 2진수로 바꿔야한다.
  - 0x1은 이진수 1이기 때문에 이는 첫 번째 인덱스를 의미힌다.
  - `SHOW CREATE TABLE employees` 명령어를 통해 인덱스 순서를 확인할 수 있다.
- type에 'ALL'로 표시되었지만 무조건 풀 테이블 스캔을 하는 것은 아니다.
  - 즉, 'Range checked for each record'인 경우에는 후보 인덱스를 사용할지를 검토해서, 인덱스를 사용하지 않는 경우 'ALL' 접근 방법을 사용한다.

```sql
EXPLAIN
SELECT *
FROM employees e1, employees e2
WHERE e2.emp_no >= e1.emp_no;
 ```

| id | select_type | table | type | key | key_len | ref | rows | Extra |
|----|-------------|-------|------|----|---------|-----|------|-------|
| 1 | SIMPLE |e1|ALL||3||300584|Using index|
| 2 | SIMPLE |e2|ALL||3||300584|Range checked for<br>each record<br>(index map: 0x1)|


### Using filesort
> `ORDER BY` 처리가 인덱스를 사용하지 못하는 경우이다.

- 조회된 레코드를 정렬하기 위해, 정렬용 메모리 버퍼(sort buffer)에 복사해서 퀵 소트 알고리즘을 수행한다.
- 이러한 경우는 많은 부하를 일으킬 수 있으므로, 쿼리를 튜닝하거나 인덱스를 생성하는 것이 좋다.

### Using join buffer (5.1 버전부터)
> 조인 버퍼가 사용되는 실행 계획이다. 조인 버퍼는 읽은 레코드를 임시로 보관해두는 메모리 공간이다.

- 실제로 조인에 필요한 인덱스는 조인에서 뒤에 읽는 테이블(드리븐 테이블)의 컬럼에만 필요하다.
  - 드리븐 테이블은 검색 위주로 사용되기 때문에, 인덱스가 없으면 성능에 미치는 영향이 매우 크다.
  - 드리븐 테이블에 적절한 인덱스가 없다면, 드라이빙 테이블로부터 읽은 레코드의 건수만큼 매번 드리븐 테이블을 풀 테이블 스캔이나 인덱스 풀 스캔해야 할 것이다.
  - 이러한 비효율성을 보완하기 위해, MySQL 서버는 드라이빙 테이블에서 읽은 레코드를 임시 공간에 보관해두고 필요할 때 재사용할 수 있게 해준다.
  - `join_buffer_size` 시스템 설정 변수를 활용하여 버퍼 크기를 설정할 수 있다.
- 옵티마이저는 조인되는 두 테이블에 있는 인덱스를 조사하고, 인덱스가 없는 테이블이 있으면 그 테이블을 먼저 읽어서 조인을 실행한다.
- 다음과 같은 카테시안 조인을 수행하는 쿼리는 항상 조인 버퍼를 사용한다.

```sql
EXPLAIN
SELECT *
FROM dept_emp de, employees e
WHERE de.from_date>'2005-01-01' AND e.emp_no<10904;
 ```

| id | select_type | table | type | key | key_len | ref | rows | Extra |
|----|-------------|-------|------|----|---------|-----|------|-------|
| 1 | SIMPLE |de|range|ix_fromdate|3||1|Using where|
| 2 | SIMPLE |e|range|PRIMARY|4||1520|Using where;<br>Using join buffer|


### Using temporary
> 쿼리를 처리하기 위해 임시 테이블을 사용한 것이다.

- MySQL은 쿼리를 처리하는 동안 중간 결과를 담아 두기 위해 임시 테이블을 사용한다.
  - 임시 테이블이 메모리에 생성됐는지, 디스크에 생성됐는지 여부는 실행 계획만으로는 판단할 수 없다.
- 아래 쿼리는 `GROUP BY` 컬럼과 `ORDER BY` 컬럼이 다르기 때문에 임시 테이블이 필요한 작업이다.

| id | select_type | table | type | key | key_len | ref | rows | Extra |
|----|-------------|-------|------|----|---------|-----|------|-------|
| 1 | SIMPLE |employees|ALL||||300584|Using temporary;<br>Using filesort|

- Extra 컬럼에 'Using temporary'가 표시되지는 않지만, 내부적으로 임시 테이블을 사용할 때도 많다.
  - `FROM` 절에 사용된 서브쿼리는 무조건 임시 테이블(파생 테이블)을 생성한다.
  - `COUNT(DISTINCT col1)`을 포함하는 쿼리는 인덱스를 사용할 수 없는 경우 임시 테이블을 생성한다.
  - `UNION`, `UNION ALL`이 사용된 쿼리도 임시 테이블을 사용하여 결과를 병합한다.
  - 정렬에 버퍼가 사용되는 경우, 버퍼의 실체도 결국은 임시 테이블이다.

### Using where
> MySQL 엔진 레이어에서 별도의 가공을 해서 필터링 작업을 처리한 경우이다.

- 스토리지 엔진은 디스크나 메모리상에서 필요한 레코드를 읽거나 저장한다.
- MySQL 엔진은 스토리지 엔진으로부터 받은 레코드를 가공 또는 연산한다.
- 작업 범위 제한 조건은 스토리지 엔진 레벨에서, 체크 조건은 MySQL 엔진 레벨에서 처리된다.
  - 아래 쿼리의 경우, 스토리지 엔진에서 100개의 레코드를 MySQL 엔진으로 넘겨준다.
  - MySQL 엔진은 체크 조건(`gender='F'`)을 통해 레코드를 필터링한다.
    - 'Using where'는 필터링돼서 레코드를 버리는 처리를 의미한다.

```sql
EXPLAIN
SELECT * FROM employees
WHERE emp_no BETWEEN 10001 AND 10100 AND gender='F';
 ```

| id | select_type | table | type | key | key_len | ref | rows | Extra |
|----|-------------|-------|------|----|---------|-----|------|-------|
| 1 | SIMPLE |employees|range|PRIMARY|4|NULL|100|Using where|

- 'Using where'가 성능상의 문제를 일으킬지 아닐지는 5.1 버전부터 추가된 'Filtered' 컬럼을 통해 확인할 수 있다.

<br>

## 3. 쿼리의 실행 계획이 좋은 경우

### Distinct
- 아래 쿼리는 departments 테이블과 dept_emp 테이블에 모두 존재하는 dept_no만 유니크하게 가져오기 위한 쿼리이다.
- `DISTINCT`를 처리하기 위해 조인하지 않아도 되는 항목은 모두 무시하고 필요한 것만 조인한다(필요한 레코드만 읽는다).

```sql
EXPLAIN
SELECT DISTINCT d.dept_no
FROM departments d, dept_emp de WHERE de.dept_no=d.dept_no;
```

| id | select_type | table | type | key | key_len | ref | rows | Extra |
|----|-------------|-------|------|----|---------|-----|------|-------|
| 1 | SIMPLE | d |index|ux_deptname|123|NULL|9|Using index;<br>Using temporary|
| 1 | SIMPLE | de |ref|PRIMARY|12|d.dept_no|18603|Using index;<br>Distinct|

### Using index(커버링 인덱스)
> 인덱스만 읽어서 쿼리를 모두 처리할 수 있는 경우이다.

- 인덱스를 이용해 처리하는 쿼리에서 가장 큰 부하를 차지하는 부분은 인덱스를 검색해 일치하는 레코드의 나머지 컬럼 값을 가져오기 위해 데이터 파일을 찾아서 가져오는 작업이다.
- 최악의 경우에는 인덱스를 통해 검색된 결과 레코드 한 건 한 건마다 디스크를 한 번씩 읽어야 할 수도 있다.
- InnoDB의 모든 테이블은 클러스터링 인덱스로 구성돼 있다.
  - 즉, InnoDB 테이블의 모든 보조 인덱스는 데이터 레코드의 주소 값으로 프라이머리 키 값을 가진다.
  - 이러한 특성 때문에 쿼리가 커버링 인덱스로 처리될 가능성이 상당히 높다.
- 하지만 무조건 커버링 인덱스로 처리하려고 인덱스에 많은 컬럼을 추가하게 되면, 과도하게 인덱스의 컬럼이 많아져 메모리 낭비가 심해질 수 있다.
  - 또한, 레코드를 저장하거나 변경하는 작업이 매우 느려질 수 있다.

### Using index for group-by
> `GROUP BY` 처리가 인덱스를 이용하는 경우이다. 이러한 방법을 '루스 인덱스 스캔'이라고 한다.

- 루스 인덱스 스캔은 인덱스에서 필요한 부분만 읽는다.
  - salaries 테이블의 인덱스는 emp_no, from_date로 구성되어 있다.
  - 아래의 쿼리의 경우 emp_no 그룹별로 첫 번째 from_date 값(최솟값)과 마지막 from_date 값(최댓값)을 인덱스로부터 읽으면 된다.
  - 따라서, '루스 인덱스 스캔' 방식으로 처리할 수 있다.

```sql
EXPLAIN
SELECT emp_no, MIN(from_date) AS first_changed_date, MAX(from_date) AS last_changed_date
FROM salaries
GROUP BY emp_no;
```

| id | select_type | table | type | key | key_len | ref | rows | Extra |
|----|-------------|-------|------|----|---------|-----|------|-------|
| 1 | SIMPLE | salaries |range|PRIMARY|4||711129|Using index for<br>group-by|


# EXPLAIN EXTENDED
---
> MySQL 5.1.12 미만의 버전에서는 MySQL 엔진에 의해 필터링 과정을 거치면서 얼마나 많은 레코드가 버려졌는지 알 수 없었다.
> 5.1.12 버전부터는 필터링이 얼마나 효율적으로 실행됐는지 알려주기 위해 'Filtered' 컬럼이 추가되었다.
> 이를 확인하려면 `EXPLAIN EXTENDED` 명령어를 사용한다.

- 필터링된 레코드는 제외하고 최종적으로 레코드가 얼마나 남았는지 비율이 표시된다.
  - 즉, 전체 레코드 100건 중 20% (20건)만이 남았다는 의미다.
- 이 값은 실제 값이 아닌 통계 정보로부터 예측된 값이다.

```sql
EXPLAIN EXTENDED
SELECT * FROM employees
WHERE emp_no BETWEEN 10001 AND 10100 AND gender='F';
```

| id | select_type | table | type | key | key_len | ref | rows | filtered | Extra |
|----|-------------|-------|------|----|---------|-----|------|--------|-------|
| 1 | SIMPLE |employees|range|PRIMARY|4|NULL|100|20|Using where|

# EXPLAIN PARTITIONS
---
> `EXPLAIN PARTITIONS` 명령을 통해 파티션 테이블의 실행 계획 정보를 좀 더 자세히 확인할 수 있다.

- 파티션이 여러 개인 테이블에서 불필요한 파티션을 빼고 쿼리를 수행하기 위해 접근해야 할 것으로 판단되는 테이블만 골라내는 과정을 '파티션 프루닝(Partition pruning)'이라고 한다.
- 이를 확인하기 위해 옵티마이저가 실제로 접근하는 파티션 테이블을 확인해 볼 수 있다.

| id | select_type | table | partitions | type | key | key_len | ref | rows | Extra |
|----|-------------|-------|-----------|------|----|---------|-----|------|-------|
| 1 | SIMPLE |tb_partition|p3|ALL||||2|Using where|

# 관련 글
---
- [MySQL 실행 계획 (1)](https://zz9z9.github.io/posts/execution-plan-part1/)
- [MySQL 실행 계획 (2)](https://zz9z9.github.io/posts/execution-plan-part2/)

# 참고 자료
---
- 이성욱, 『개발자와 DBA를 위한 Real MySQL』, 위키북스(2012), 6장
