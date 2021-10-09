---
title: MySQL 실행 계획 (2)
date: 2021-10-07 23:00:00 +0900
categories: [Database]
tags: [MySQL, 실행 계획]
---

# 들어가기 전
---
실행 계획을 나타내는 테이블에 다양한 컬럼들을 차례대로 살펴보자. <br>

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
| 3 | DEPENDENT<br>UNION | de |ref|ix_empno<br>ix_fromdate|4||1|Using where;<br>Using index|
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

## DERIVED

## UNCACHEABLE SUBQUERY

## UNCACHEBLE UNION

# table 컬럼
---


# type 컬럼
---

# 관련 글
---
- [MySQL 실행 계획 (1)](https://zz9z9.github.io/posts/execution-plan-part1/)

# 참고 자료
---
- 이성욱, 『개발자와 DBA를 위한 Real MySQL』, 위키북스(2012), 6장
