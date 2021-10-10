---
title: MySQL 실행 계획 (2)
date: 2021-10-07 23:00:00 +0900
categories: [Database]
tags: [MySQL, 실행 계획]
---

# 들어가기 전
---
실행 계획을 나타내는 테이블의 다양한 컬럼들을 차례대로 살펴보자. <br>

※ [이전 글](https://zz9z9.github.io/posts/execution-plan-part1/)을 읽지 않으신 분들은 먼저 읽으실 것을 권장합니다.

# id 컬럼
---
> 단위 SELECT 쿼리별로 부여되는 식별자 값을 나타내는 컬럼이다.

```sql
SELECT...
FROM (SELECT ... FROM tb_test1) tb1,
  tb_test2 tb2
WHERE tb1.id=tb2.id;
```

- 위 쿼리는 아래와 같이 `SELECT` 단위로 분리해서 생각해볼 수 있다.

```sql
SELECT ... FROM tb_test1;
SELECT ... FROM tb1, tb_test2 tb2 WHERE tb1.id=tb2.id;
```

- 하나의 SELECT 문장 안에서 여러 개의 테이블을 조인하면 각 레코드별로 같은 id가 부여된다.

```sql
EXPLAIN
SELECT e.emp_no, e.first_name, s.from_date, s.salary
FROM employees e, salaries s
WHERE e.emp_no=s.emp_no
LIMIT 10;
```

| id | select_type | table | type | key | key_len | ref | rows | Extra |
|----|-------------|-------|------|-----|---------|-----|------|-------|
| 1 | SIMPLE | e |index|ix_firstname|44||300584|Using index|
| 1 | SIMPLE | s |ref|PRIMARY|4|employees, e.emp_no|4||

- 다음과 같이 3개의 단위 SELECT 쿼리로 구성된 경우는 아래와 같은 실행 계획을 나타낼 것이다.

```sql
EXPLAIN
SELECT
( (SELECT COUNT(*) FROM employees) +
(SELECT COUNT(*) FROM departments) ) AS total_count;
```

| id | select_type | table | type | key | key_len | ref | rows | Extra |
|----|-------------|-------|------|-----|---------|-----|------|-------|
| 1 | PRIMARY |  ||||||No tables used|
| 2 | SUBQUERY | employees |index|ix_hiredate|3||300584|Using index|
| 3 | SUBQUERY | departments |index|ux_deptname|123||9|Using index|

# select_type 컬럼
---
> 각 단위 SELECT 쿼리가 어떤 타입의 쿼리인지 표시되는 컬럼이다.

## SIMPLE
- `UNION`이나 서브 쿼리를 사용하지 않는 단순한 `SELECT` 쿼리인 경우이다.
- 실행 계획에서 select_type이 'SIMPLE'인 단위 쿼리는 반드시 하나만 존재한다.
- 일반적으로 제일 바깥 `SELECT` 쿼리의 select_type이 'SIMPLE'로 표시된다.

## PRIMARY
- `UNION`이나 서브 쿼리가 포함된 `SELECT` 쿼리의 실행 계획에서 가장 바깥쪽(Outer)에 있는 단위 쿼리인 경우이다.
- 실행 계획에서 select_type이 'PRIMARY'인 단위 쿼리는 반드시 하나만 존재한다.

## UNION
- `UNION`으로 결합하는 단위 `SELECT` 쿼리 가운데 첫 번째를 제외한 두 번째 이후 단위 `SELECT` 쿼리는 `UNION`으로 표시된다.
- `UNION`의 첫 번째 단위 `SELECT`는 `UNION` 쿼리로 결합된 전체 집합의 select_type이 표시된다.

```sql
EXPLAIN
SELECT * FROM (
  (SELECT emp_no FROM employees e1 LIMIT 10)
  UNION ALL
  (SELECT emp_no FROM employees e2 LIMIT 10)
  UNION ALL
  (SELECT emp_no FROM employees e3 LIMIT 10)
) tb;
```

| id | select_type | table | type | key | key_len | ref | rows | Extra |
|----|-------------|-------|------|-----|---------|-----|------|-------|
| 1 | PRIMARY | < derived2 > |ALL||||30||
| 2 | DERIVED | e1 |index|ix_hiredate|3||300584|Using index|
| 3 | UNION | e2 |index|ix_hiredate|3||300584|Using index|
| 4 | UNION | e3 |index|ix_hiredate|3||300584|Using index|
|   | UNION RESULT | <union2,3,4> |ALL||||||

## DEPENDENT UNION
- `UNION`이나 `UNION ALL`로 집합을 결합하는 쿼리에서 표시된다.
- 'DEPENDENT'는 `UNION`이나 `UNION ALL`로 결합된 단위 쿼리가 외부의 영향을 받은 것을 의미한다.
  - 외부의 영향이란, 내부 쿼리가 외부의 값을 참조해서 처리하는 것을 의미한다.
- 일반적으로 외부 쿼리보다 서브 쿼리가 먼저 실행되며, 대부분 이러한 방식이 반대의 경우보다 더 빠르다.
  - 하지만 'DEPENDENT' 키워드가 포함되는 경우, 서브 쿼리는 외부 쿼리에 의존적이므로 절대 외부 쿼리보다 먼저 실행될 수가 없다.
  - 따라서 이러한 쿼리는 비효율적인 경우가 많다.
- 아래 쿼리에서는 내부 쿼리에서 외부에 있는 employees 테이블의 emp_no 컬럼이 사용된다.

```sql
EXPLAIN
SELECT
 e.first_name,
 ( SELECT ... FROM salaries s WHERE s.emp_no = e.emp_no
   UNION
   SELECT ... FROM dept_emp de WHERE de.emp_no = e.emp_no
 ) AS msg
FROM employees e
WHERE e.emp_no=10001;
```

| id | select_type | table | type | key | key_len | ref | rows | Extra |
|----|-------------|-------|------|-----|---------|-----|------|-------|
| 1 | PRIMARY | e |const|PRIMARY|4|const|1||
| 2 | DEPENDENT<br>SUBQUERY | s |ref|PRIMARY|4|const|17|Using index|
| 3 | DEPENDENT<br>UNION | de |ref|ix_empno_fromdate|4||1|Using where;<br>Using index|
|   | UNION RESULT | <union2,3> |ALL||||||

## UNION RESULT
- MySQL에서 `UNION`이나 `UNION ALL` 쿼리는 모두 병합 결과를 임시 테이블로 생성한다.
- 'UNION RESULT'는 이러한 임시 테이블을 의미한다.
  - 단위 쿼리가 아니기 때문에 별도 id 값은 부여되지 않는다.
- table 컬럼의 `<union n,m>`의 의미는 id가 n번, m번인 단위 쿼리의 결과를 `UNION` 했다는 것을 의미한다.

## SUBQUERY
- 여기서 'SUBQUERY'라고 하는 것은 `FROM` 절 이외에서 사용되는 서브 쿼리만을 의미한다.
- `FROM` 절에 사용된 서브 쿼리는 'DERIVED'라고 표시된다.

```sql
EXPLAIN
SELECT
  e.first_name,
  ( SELECT ... FROM dept_emp de, dept_manager dm WHERE ...) AS cnt
FROM employees e
WHERE e.emp_no = 10001;
```

| id | select_type | table | type | key | key_len | ref | rows | Extra |
|----|-------------|-------|------|-----|---------|-----|------|-------|
| 1 | PRIMARY | e |const|PRIMARY|4|const|1||
| 2 | SUBQUERY | dm |index|PRIMARY|16||24|Using index|
| 2 | SUBQUERY | de |ref|PRIMARY|12|dm.dept_no|18603|Using index|

## DEPENDENT SUBQUERY
- 서브 쿼리가 바깥쪽(Outer) SELECT 쿼리에서 정의된 컬럼을 사용하는 경우이다.
- 'DEPENDENT UNION'처럼 'DEPENDENT SUBQUERY' 또한 외부 쿼리가 먼저 수행된 후 내부 쿼리(서브 쿼리)가 실행되어야 하므로 일반 서브 쿼리보다는 처리 속도가 느릴 때가 많다.

```sql
EXPLAIN
SELECT
  e.first_name,
  ( SELECT ... FROM dept_emp de, dept_manager dm WHERE ... AND de.emp_no=e.emp_no) AS cnt
FROM employees e
WHERE e.emp_no = 10001;
```

| id | select_type | table | type | key | key_len | ref | rows | Extra |
|----|-------------|-------|------|-----|---------|-----|------|-------|
| 1 | PRIMARY | e |const|PRIMARY|4|const|1||
| 2 | DEPENDENT<br>SUBQUERY | de |ref|ix_empno_fromdate|4||1|Using<br>index|
| 2 | DEPENDENT<br>SUBQUERY | dm |ref|PRIMARY|12|dm.dept_no|1|Using<br>index|

## DERIVED
- 서브 쿼리가 `FROM` 절에 사용된 경우이다.
- 'DERIVED'인 경우, 쿼리의 실행 결과를 메모리나 디스크에 임시 테이블로 생성한다.
  - 이러한 임시 테이블을 '파생 테이블'이라고도 한다.
  - 파생 테이블에는 인덱스가 없으므로 다른 테이블과 조인할 때 성능상 불리할 때가 많다.
- MySQL은 이러한 서브 쿼리를 최적화하지 못할 때가 대부분이다. (MySQL 5 기준)
- 쿼리를 튜닝하기 위해 가장 먼저하는 것 중 하나가 select_type 값이 'DERIVED'인 것이 있는지 찾는 것이다.
  - 이 경우, 조인으로 해결할 수 있는 경우라면 서브 쿼리보다는 조인을 사용하는 것이 권장된다.

```sql
EXPLAIN
SELECT *
FROM (SELECT de.emp_no FROM dept_emp de) tb,
    employees e
WHERE e.emp_no=tb.emp_no;
```

| id | select_type | table | type | key | key_len | ref | rows | Extra |
|----|-------------|-------|------|-----|---------|-----|------|-------|
| 1 | PRIMARY | < derived2 > |ALL||||331603||
| 1 | PRIMARY | e |eq_ref|PRIMARY|4|tb.emp_no|1|Using<br>index|
| 2 | DERIVED | de |index|ix_fromdate|3||334868|Using<br>index|

## UNCACHEABLE SUBQUERY
- 일반적으로 조건이 똑같은 서브 쿼리가 실행될 때, 이전의 실행 결과를 그대로 사용한다.
  - 재사용을 위해 서브 쿼리의 결과를 내부적인 캐시 공간에 담아둔다.
  - 쿼리 캐시나 파생 테이블과는 무관하다.
- 하지만 'UNCACHEABLE SUBQUERY'로 표시될 때는 캐싱된 결과를 사용할 수 없는 경우이다.
  - 사용자 변수가 서브 쿼리에 사용된 경우
  - `NOT-DETERMINISTIC` 속성의 스토어드 루틴이 서브 쿼리에 내에 사용된 경우
  - `UUID()`나 `RAND()`와 같이 결과값이 호출할 때마다 달라지는 함수가 서브 쿼리에 사용된 경우

## UNCACHEBLE UNION
- `UNION`을 사용한 쿼리 중 위에서 언급한 캐싱할 수 없는 조건에 해당하는 경우이다.
- MySQL 5.1부터 추가된 select_type이다.

# table 컬럼
---
> MySQL의 실행 계획은 테이블 기준으로 표시된다. 별도의 테이블을 사용하지 않는 경우에는 `NULL`이 표시된다.

- table 컬럼에 "<>"로 둘러싸인 이름이 표시되는 경우는 임시 테이블을 의미한다.
- 지금까지 공부한 내용을 토대로 다음 실행 계획을 분석해보자.

| id | select_type | table | type | key | key_len | ref | rows | Extra |
|----|-------------|-------|------|-----|---------|-----|------|-------|
| 1 | PRIMARY | `<derived2>` |ALL||||10420||
| 1 | PRIMARY | e |eq_ref|PRIMARY|4|de1.emp_no|1||
| 2 | DERIVED | dept_emp |range|ix_fromdate|3||20550||

1. 첫 번째 라인의 테이블이 `<derived2>`이므로 id가 2번인 라인이 먼저 실행되고 그 결과로 파생 테이블이 만들어진다.
2. id 2번에 table이 dept_emp인 것으로 보아, dept_emp 테이블을 읽어 파생 테이블을 생성한다.
3. id가 1번으로 같은 두 개의 테이블 `<derived2>`, e는 조인됐다는 것을 알 수 있다.
- `<derived2>`가 e보다 먼저 표시됐기 때문에, `<derived2>`가 드라이빙 테이블, e가 드리븐 테이블이 된다.
- 즉, `<derived2>` 테이블을 먼저 읽고 이 결과를 기준으로 e와 조인을 한다.


# type 컬럼
---
> type 컬럼과 그 이후의 컬럼들은 MySQL 서버가 각 테이블의 레코드를 어떤 방식으로 읽었는지를 나타낸다. 즉, 인덱스를 사용해 읽었는지, 풀 테이블 스캔으로 읽었는지 등을 의미한다.
> 일반적으로 쿼리를 튜닝할 때 인덱스를 효율적으로 사용하는지 확인하는 것이 중요하기 때문에, type 컬럼은 반드시 체크해야 할 중요한 정보이다.

<br>
이제 type 컬럼에서 나타날 수 있는 값들에 대해 살펴보자.

## system
- 레코드가 1건 이하인 테이블을 참조하는 형태의 접근 방법이다.
- MyISAM이나 MEMORY 테이블에서만 사용되는 접근 방법이다.

```sql
EXPLAIN
SELECT * FROM tb_dual;
```

| id | select_type | table | type | key | key_len | ref | rows | Extra |
|----|-------------|-------|------|-----|---------|-----|------|-------|
| 1 | SIMPLE | tb_dual |system||||1||


## const
- 쿼리가 프라이머리 키나 유니크 키 컬럼을 이용하는 `WHERE` 조건절을 가지고 있으며, 반드시 1건을 반환하는 쿼리의 처리 방식이다.
- 쿼리의 해당 값은 옵티마이저에 의해 상수(const)화된 다음 쿼리 실행기로 전달된다.
- 다른 DBMS에서는 'UNIQUE INDEX SCAN'이라고도 표현한다.

```sql
EXPLAIN
SELECT * FROM employees WHERE emp_no=10001;
```

| id | select_type | table | type | key | key_len | ref | rows | Extra |
|----|-------------|-------|------|-----|---------|-----|------|-------|
| 1 | SIMPLE | employees |const|PRIMARY|4|const|1||

- 다중 컬럼으로 구성된 프라이머리 키, 유니크 키 중에서 인덱스의 일부 컬럼만 조건으로 사용할 때는 const 타입의 접근 방법을 사용할 수 없다.

## eq_ref
- 조인에서 처음 읽은 테이블의 컬럼 값을 그다음 읽어야 할 테이블의 프라이머리 키나 유니크 키 컬럼의 검색 조건에 사용하는 경우이다.
- 다중 컬럼으로 만들어진 프라이머리 키나 유니크 인덱스라면 인덱스의 모든 컬럼이 비교 조건에 사용돼야만 eq_ref 접근 방법이 사용될 수 있다.
  - 즉, 조인에서 두 번째 이후에 읽는 테이블에서 반드시 1건만 존재한다는 보장이 있어야한다.

```sql
EXPLAIN
SELECT * FROM dept_emp de, employees e
WHERE e.emp_no=de.emp_no AND de.dept_no='d005';
```

| id | select_type | table | type | key | key_len | ref | rows | Extra |
|----|-------------|-------|------|-----|---------|-----|------|-------|
| 1 | SIMPLE | de |ref|PRIMARY|12|const|53288|Using<br>where|
| 1 | SIMPLE | e |eq_ref|PRIMARY|4|employees.de.emp_no|1||

## ref
- 인덱스의 종류와 관계없이 동등 조건으로 검색할 때 ref 접근 방법이 사용된다.
- eq_ref와는 달리 조인의 순서와 관계없이 사용된다.
- 프라이머리 키나 유니크 키 등의 제약 조건도 없다.
- 반환되는 레코드가 반드시 1건이라는 보장이 없으므로 const나 eq_ref보다는 빠르지 않다.
- const, eq_ref, ref 모두 인덱스의 분포도가 나쁘지 않다면 성능 문제를 일으키지 않는 좋은 접근 방법이다.

```sql
EXPLAIN
SELECT * FROM dept_emp WHERE dept_no='d005';
```

| id | select_type | table | type | key | key_len | ref | rows | Extra |
|----|-------------|-------|------|-----|---------|-----|------|-------|
| 1 | SIMPLE | dept_emp |ref|PRIMARY|12|const|53288|Using<br>where|

## fulltext
- MySQL의 전문 검색(Fulltext) 인덱스를 사용해 레코드를 읽는 접근 방법을 의미한다.
- 전문 검색 인덱스는 통계 정보가 관리되지 않는다.
  - 따라서, 옵티마이저는 전문 인덱스를 사용할 수 있는 쿼리에서는 비용과는 관계 없이 거의 fulltext 접근 방법을 사용한다.
  - 물론, 성능상 더 빠른 const, eq_ref, ref 접근 방법을 사용할 수 있는 경우에는 굳이 fulltext를 사용하지 않는다.
- 전문 검색은 `MATCH .. AGAINST ...` 구문을 사용해서 실행하며, 반드시 해당 테이블에 전문 검색용 인덱스가 준비돼 있어야 한다.

```sql
EXPLAIN
SELECT *
FROM employee_name WHERE emp_no=10001
    AND emp_no BETWEEN 10001 AND 10005
    AND MATCH(first_name, last_name) AGAINST('Facello' IN BOOLEAN MODE);
```

## ref_or_null
- ref 접근 방식과 같은데, NULL 비교가 추가된 형태다.

```sql
EXPLAIN
SELECT * FROM titles
WHERE to_date='1985-03-01' OR to_date IS NULL;
```

| id | select_type | table | type | key | key_len | ref | rows | Extra |
|----|-------------|-------|------|-----|---------|-----|------|-------|
| 1 | SIMPLE | titles |ref_or_null|ix_todate|4|const|2|Using where;<br>Using index|

## unique_subquery
- `WHERE` 조건절에서 사용될 수 있는 `IN` (subquery) 형태의 쿼리를 위한 접근 방식이다.
- 서브 쿼리에서 중복되지 않은 유니크한 값만 반환할 때 사용한다.
- 아래 쿼리의 경우, dept_emp 테이블의 프라이머리 키가 (dept_no, emp_no)이므로 `emp_no=10001`인 레코드 중에서 dept_no는 중복이 없다.

```sql
EXPLAIN
SELECT * FROM departments WHERE dept_no IN (
    SELECT dept_no FROM dept_emp WHERE emp_no=10001);
```

| id | select_type | table | type | key | key_len | ref | rows | Extra |
|----|-------------|-------|------|-----|---------|-----|------|-------|
| 1 | PRIMARY | departments |index|PRIMARY|123||9|Using index;<br>Using where|
| 2 | DEPENDENT<br>SUBQUERY | dept_emp |unique_subquery|PRIMARY|16|func,const|1|Using index;<br>Using where|

## index_subquery
- IN (subquery)에서 서브 쿼리가 중복된 값을 반환할 수는 있지만 중복된 값을 인덱스를 이용해 제거할 수 있을 때 이 접근 방법이 사용된다.

```sql
EXPLAIN
SELECT * FROM departments WHERE dept_no IN (
    SELECT dept_no FROM dept_emp WHERE dept_no BETWEEN 'd001' AND 'd003');
```

| id | select_type | table | type | key | key_len | ref | rows | Extra |
|----|-------------|-------|------|-----|---------|-----|------|-------|
| 1 | PRIMARY | departments |index|ux_deptname|122||9|Using where;<br>Using index|
| 2 | DEPENDENT<br>SUBQUERY | dept_emp |index_subquery|PRIMARY|12|func|18626|Using index;<br>Using where|

## range
- 인덱스 레인지 스캔 형태의 접근 방법이다.
- 인덱스를 하나의 값이 아닌 범위로 검색하는 경우이다.
  - `<`, `>`, `IS NULL`, `BETWEEN`, `IN`, `LIKE` 등의 연산자를 이용해 검색하는 경우
- 일반적으로, const, ref, range 세 가지 접근 방법을 모두 '인덱스 레인지 스캔' 방식이라고 한다.

```sql
EXPLAIN
SELECT dept_no FROM dept_emp WHERE dept_no BETWEEN 'd001' AND 'd003';
```

| id | select_type | table | type | key | key_len | ref | rows | Extra |
|----|-------------|-------|------|-----|---------|-----|------|-------|
| 1 | SIMPLE | dept_emp |range|PRIMARY|12||121890|Using where;<br>Using index|

## index_merge
- 유일하게 2개 이상의 인덱스를 이용하는 접근 방식이다.
- 각각의 인덱스를 이용해 검색 결과를 만들어낸 후 그 결과를 병합한다.
- 'index_merge' 접근 방식에는 다음과 같은 특징이 있다.
  - 여러 인덱스를 읽어야 하므로 일반적으로 range 접근 방식보다는 효율성이 떨어진다.
  - `AND`, `OR` 연산이 복잡하게 연결된 쿼리에서는 최적화되지 못할 때가 많다.
  - 전문 검색 인덱스를 사용하는 쿼리에서는 적용되지 않는다.
  - 병합된 처리 결과는 항상 2개 이상의 집합이 되기 때문에 교집합, 합집합 또는 중복 제거와 같은 부가적인 작업이 더 필요하다.

```sql
EXPLAIN
SELECT * FROM employees
WHERE emp_no BETWEEN 10001 AND 11000
    OR first_name='Smith';
```

| id | select_type | table | type | key | key_len | ref | rows | Extra |
|----|-------------|-------|------|-----|---------|-----|------|-------|
| 1 | SIMPLE | employees |index_merge|PRIMARY, ix_firstname|4,44||1521|Using union(PRIMARY ,ix_firstname); <br> Using where|

## index
- 인덱스를 처음부터 끝까지 읽는 '인덱스 풀 스캔' 방식을 의미한다.
- 많은 사람들이 'index'라는 이름 때문에 효율적이라고 오해하지만, range 접근 방식과 같이 인덱스의 필요한 부분만 읽는 것이 아니기 때문에 비효율적일 수 있다.
- 테이블을 처음부터 끝까지 읽는 '풀 테이블 스캔' 방식과 비교하는 데이터 건수는 같다.
  - 하지만, 인덱스는 일반적으로 데이터 파일 전체 크기보다는 작아서 풀 테이블 스캔 보다는 빠르다.
- 다음 조건 중, (1,2) 또는 (1,3)인 경우 index 접근 방법이 사용된다.
1. range나 const 또는 ref와 같은 접근 방식으로 인덱스를 사용하지 못하는 경우
2. 인덱스에 포함된 컬럼만으로 처리할 수 있는 쿼리인 경우(데이터 파일 읽지 않아도 되는 경우)
3. 인덱스를 이용해 정렬이나 그룹핑 작업이 가능한 경우(별도의 정렬 작업 필요 없는 경우)

```sql
EXPLAIN
SELECT * FROM departments
ORDER BY dept_name DESC LIMIT 10;
```

| id | select_type | table | type | key | key_len | ref | rows | Extra |
|----|-------------|-------|------|-----|---------|-----|------|-------|
| 1 | SIMPLE | departments |index|ux_firstname|123||9|Using index|

## ALL
- 테이블을 처음부터 끝까지 읽는 '풀 테이블 스캔' 방식이다.
- 위에서 살펴본 모든 방법을 사용할 수 없는 경우 마지막으로 선택되는 가장 비효율적인 방법이다.
- 일반적으로 DBMS에는 이러한 풀 스캔 방식으로 인한 대량의 디스크 I/O를 유발하는 작업을 위해 **Read Ahaed**라는 기능을 제공한다.
  - Read Ahead : 한 번에 여러 페이지를 읽어서 처리하는 기능
- 쿼리를 튜닝한다는 것이 무조건 인덱스 풀 스캔이나, 테이블 풀 스캔을 사용하지 못하게 하는 것은 아니다.

# 관련 글
---
- [MySQL 실행 계획 (1)](https://zz9z9.github.io/posts/execution-plan-part1/)

# 참고 자료
---
- 이성욱, 『개발자와 DBA를 위한 Real MySQL』, 위키북스(2012), 6장
