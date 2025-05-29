---
title: MySQL - CHAR vs VARCHAR
date: 2025-05-29 23:00:00 +0900
categories: [지식 더하기, 이론]
tags: [MySQL]
---

## CHAR vs VARCHAR

- 데이터를 저장하고 조회하는 방식에서 차이가 있음
- 또한, 최대 길이와 후행 공백(trailing spaces) 유지 여부에서도 차이가 있음
- 엄격한(Strict) SQL 모드가 활성화되어 있지 않은 경우, CHAR 또는 VARCHAR 열에 해당 열의 최대 길이를 초과하는 값을 할당하면, 그 값은 열의 크기에 맞게 잘리고(truncated) 경고가 발생
- 공백이 아닌 문자가 잘릴 경우에는, Strict SQL 모드를 사용하면 경고 대신 오류를 발생시키고 해당 값을 삽입하지 않도록 할 수 있음

### CHAR
- `CHAR(n)`
  -  실제 데이터 길이에 상관없이 저장되는 데이터 길이가 n으로 고정
  -  n은 0 ~ 255까지 가능

| 문자셋              | 문자당 바이트 수  | CHAR(255)의 최대 바이트 |
| ---------------- | ---------- | ----------------- |
| `latin1`         | 1 byte     | 255 bytes         |
| `utf8` (3바이트)    | 최대 3 bytes | 최대 765 bytes      |
| `utf8mb4` (4바이트) | 최대 4 bytes | 최대 1020 bytes     |


- 저장될때 n보다 작으면 나머지 부분은 공백으로 right-padded됨
- 값이 조회될때 `PAD_CHAR_TO_FULL_LENGTH`가 활성화되어 있지 않는이상 (기본은 비활성화), right-padded된 공백은 제거돼서 조회된다.
  - [`PAD_CHAR_TO_FULL_LENGTH` 속성은 deprecated됨](https://dev.mysql.com/doc/refman/8.4/en/sql-mode.html#sqlmode_pad_char_to_full_length)
- 초과된 후행 공백은 SQL 모드와 관계없이 조용히(silently) 잘린다.

### VARCHAR
- 가변길이 데이터
- 길이는 0 ~ 65,535까지 가능
  - VARCHAR의 실질적인 최대 길이는 **전체 행(Row)의 최대 크기인 65,535바이트**와, 사용하는 문자셋에 따라 달라진다.

| 문자셋       | 문자당 바이트    | 실질 최대 VARCHAR 길이 (단일 컬럼 기준) |
| --------- | ---------- | --------------------------- |
| `latin1`  | 1 byte     | 약 65,532자                   |
| `utf8`    | 최대 3 bytes | 약 21,844자                   |
| `utf8mb4` | 최대 4 bytes | 약 16,383자                   |


- CHAR와 다르게 저장되는 값의 바이트를 알려주는 1바이트 또는 2바이트의 prefix 데이터가 따라 붙는다.
  - 저장되는 형태 : `[길이 prefix] + [실제 문자열]`
    - 길이 prefix
      - 1바이트 : 저장되는 값이 255바이트 이하
      - 2바이트 : 저장되는 값이 255바이트 초과
- 저장되는 데이터의 길이가 `char(n)`의 n보다 작아도 공백이 right-padded되지 않는다.
-  열 길이를 초과하는 후행 공백은 삽입 전에 잘리며, 이때 SQL 모드와 상관없이 경고가 발생
-  후행 공백은 그대로 저장 및 조회된다.
  - 따라서, `abc`뒤에 공백이 붙은 상태로 VARCHAR 컬럼에 저장되면 `SELECT * FROM test WHERE col_varchar = 'abc';` 쿼리는 **col_varchar에 저장된 값이 'abc '이므로 매칭되지 않음**.
  - CHAR는 조회시 후행 공백이 제거되므로 조회됨

**※ 참고 : CHAR(n) 또는 VARCHAR(n)에서 n이 0인 경우 ?**
- 비어 있는 문자열만 허용되는 컬럼

> GPT에게 언제 필요할 것 같은지 물어보았다.

```sql
-- 지금은 type이 의미 없지만,
-- 나중에 type이 'coupon', 'event', 'system' 등의 의미를 가질 수 있음

CREATE TABLE event_flags (
    user_id INT,
    type VARCHAR(16), -- 지금은 VARCHAR(0)이지만 확장 가능
    UNIQUE (user_id, type)
);
```

- 처음에는 type이 항상 공백이지만, 미래에는 다양한 type을 넣고, 한 user_id에 여러 row를 허용할 수 있게 확장 가능
- 이럴 경우 기존 인덱스/제약 조건 구조를 변경하지 않고도 확장 가능

## 기타
- InnoDB는 768바이트 이상인 고정 길이 필드를 내부적으로 가변 길이 필드로 인코딩하여 데이터 페이지 외부(off-page)에 저장
  - 예를 들어 CHAR(255) 컬럼은 utf8mb4 같이 한 글자가 최대 4바이트인 문자셋을 사용하면, 전체 길이가 1020바이트까지 될 수 있어 768바이트를 초과
- CHAR, VARCHAR, TEXT 컬럼 값은 해당 컬럼에 지정된 문자셋의 collation 규칙에 따라 정렬 및 비교
- MySQL의 대부분의 Collation은 `PAD SPACE` 속성을 가짐
  - 단, UCA 9.0.0 이상을 기반으로 한 Unicode Collation은 `NO PAD` 속성을 가짐
  - `NO PAD` 속성에서는 문자열 뒤의 공백도 의미 있는 문자로 취급되어 비교 시 영향을 미침
  - `PAD SPACE` 속성에서는 문자열 뒤의 공백은 무시되며, 비교 시 없는 것처럼 취급됨

**예시 : NO PAD vs PAD SPACE**

```sql
-- 두 테이블은 같은 구조지만 다른 collation 사용
CREATE TABLE pad_space_test (
val VARCHAR(10) COLLATE utf8mb4_general_ci -- PAD SPACE (기본값)
);

CREATE TABLE no_pad_test (
val VARCHAR(10) COLLATE utf8mb4_0900_as_cs -- NO PAD
);

-- 동일한 문자지만 후행 공백이 다른 값을 삽입
INSERT INTO pad_space_test VALUES ('abc'), ('abc ');
INSERT INTO no_pad_test VALUES ('abc'), ('abc ');
```

```sql
-- 비교 결과
SELECT 'PAD SPACE' AS collation, val FROM pad_space_test WHERE val = 'abc';
SELECT 'NO PAD' AS collation, val FROM no_pad_test WHERE val = 'abc';
```

- PAD SPACE: 'abc'와 'abc '는 동일하다고 판단, 따라서 둘 다 조회됨

| collation | val |
| --------- | --- |
| PAD SPACE | abc |
| PAD SPACE | abc |

- NO PAD: 'abc '는 다르다고 판단됨, 따라서 'abc'만 조회됨

| collation | val |
| --------- | --- |
| NO PAD    | abc |


## 참고 자료
- [https://dev.mysql.com/doc/refman/8.4/en/char.html](https://dev.mysql.com/doc/refman/8.4/en/char.html)
