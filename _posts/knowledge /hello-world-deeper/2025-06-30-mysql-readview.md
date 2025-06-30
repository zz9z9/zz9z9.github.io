---
title: MySQL ReadView 알아보기
date: 2025-06-30 22:00:00 +0900
categories: [지식 더하기, 들여다보기]
tags: [Java]
---

> MySQL InnoDB에서 트랜잭션 격리수준이 READ COMMITTED이면 다른 트랜잭션에서 커밋 완료한걸 읽을 수 있고, <br> REPEATABLE READ이면 다른 트랜잭션에서 커밋을 완료했더라도 해당 데이터를 무조건 읽을 수 있는 것은 아니다. <br> 이게 어떻게 가능한걸까 ?

- 결론부터 말하면, MVCC 매커니즘은 현재 트랜잭션 내에서 어떤 레코드(row)를 볼 수 있는지(가시성)를 판단하기 위해 ReadView 객체를 활용한다.
  - READ COMMITTED : 매 SELECT 질의마다 ReadView 생성
  - REPEATABLE READ : 최초 SELECT 질의에서만 ReadView 생성

- REPEATABLE READ 예시

```
-- 트랜잭션 A
BEGIN;
UPDATE users SET ... WHERE id = 1;  -- 아직 SELECT 없음 → ReadView 생성 안 됨
-- 이 사이에 트랜잭션 B가 COMMIT
SELECT * FROM users WHERE age > 30;  -- 이제 ReadView 생성 → B의 결과 보일 수 있음
SELECT * FROM users WHERE age > 30;  -- 위와 동일한 ReadView 사용
COMMIT;
```

## 들어가기전
- InnoDB의 각 레코드는 `db_trx_id`와 `db_roll_pointer`라는 두 개의 숨겨진 컬럼을 가지고 있다.
- 그리고 테이블에 프라이머리 키나 `NULL`을 허용하지 않는 유니크 키가 없다면, 자동 증가하는 숨겨진 컬럼인 `db_row_id`를 생성한다.

**db_trx_id**
- 이 레코드를 최종적으로 수정한 트랜잭션의 ID

**db_roll_pointer**
- 이 레코드의 이전 버전(undo 로그) 위치를 가리키는 포인터

**db_row_id**
- 기본 키(PK)나 NOT NULL 유니크 키가 없을 경우, 내부적으로 레코드를 유일하게 식별하기 위한 ID

![image](/assets/img/mysql-readview-img1.png)
<figure align = "center">
  <figcaption align="center">출처 : <a href="https://xialeistudio.medium.com/understanding-mvcc-in-mysql-innodb-116100a27b65" target="_blank"> https://xialeistudio.medium.com/understanding-mvcc-in-mysql-innodb-116100a27b65</a> </figcaption>
</figure>

## ReadView 살펴보기
- [ReadView 클래스 문서](https://dev.mysql.com/doc/dev/mysql-server/8.4.4/classReadView.html)
- 참고한 소스코드
  - [mysql-server/storage/innobase/include/read0types.h](https://github.com/mysql/mysql-server/blob/ff05628a530696bc6851ba6540ac250c7a059aa7/storage/innobase/include/read0types.h#L48)
  - [mysql-server/storage/innobase/read/read0read.cc](https://github.com/mysql/mysql-server/blob/ff05628a530696bc6851ba6540ac250c7a059aa7/storage/innobase/read/read0read.cc#L524)


### 멤버 변수 및 초기화

```java
// mysql-server/storage/innobase/include/read0types.h

 private:
  trx_id_t m_low_limit_id;

  trx_id_t m_up_limit_id;

  trx_id_t m_creator_trx_id;

  ids_t m_ids;

  trx_id_t m_low_limit_no;
```

```java
// mysql-server/storage/innobase/read/read0read.cc

void ReadView::prepare(trx_id_t id) {
  ut_ad(trx_sys_mutex_own());

  m_creator_trx_id = id;

  m_low_limit_no = trx_get_serialisation_min_trx_no();

  m_low_limit_id = trx_sys_get_next_trx_id_or_no();

  ut_a(m_low_limit_no <= m_low_limit_id);

  if (!trx_sys->rw_trx_ids.empty()) {
    copy_trx_ids(trx_sys->rw_trx_ids);
  } else {
    m_ids.clear();
  }

  /* The first active transaction has the smallest id. */
  m_up_limit_id = !m_ids.empty() ? m_ids.front() : m_low_limit_id;

  ut_a(m_up_limit_id <= m_low_limit_id);

  ut_d(m_view_low_limit_no = m_low_limit_no);
  m_closed = false;
}

```

| 멤버 변수                       | 설명                                                                                                                                                                                                 |
| --------------------------- |----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `ids_t m_ids`               | 스냅샷(ReadView)이 만들어질때 **활성화 되어있던(커밋되지 않은)** Read-Write 트랜잭션의 id 목록. <br>즉, 이 ReadView가 **볼 수 없어야 하는 트랜잭션 ID 목록**.                                                                                   |
| `trx_id_t m_low_limit_id`   | Read View 생성 시점에 아직 시작되지 않은 트랜잭션의 ID **(즉, 다음으로 부여될 trx_id)**. <br> **따라서, 이 값 이상의 trx_id를 가진 레코드는 보이지 않음**                                                                                        |
| `trx_id_t m_up_limit_id`    | Read View 생성 시점에 **활성 상태였던 트랜잭션들 중 가장 작은 trx_id**. <br> **따라서, 이 값 미만의 trx_id를 가진 레코드는 보임**. <br> ※ `m_ids`가 비어있으면, `m_low_limit_id` 값과 같음                                                         |
| `trx_id_t m_creator_trx_id` | 이 ReadView를 만든 트랜잭션의 ID.                                                                                                                                                                           |
| `trx_id_t m_low_limit_no`   | 이 값보다 작은 트랜잭션 id는 Undo 로그를 볼 필요가 없음. <br> 따라서, Undo 로그에서 **삭제해도 되는 최소 트랜잭션 번호 기준** (purge 판단 시 사용). <br> 즉, 현재 열려 있는 모든 ReadView 중 가장 오래된 것의 m_low_limit_no 를 기준으로, <br> 그보다 작은 트랜잭션의 undo 로그는 모두 정리 가능 |


### 가시성 여부 판단

```c
// mysql-server/storage/innobase/include/read0types.h

/** Check whether the changes by id are visible.
@param[in]    id      transaction id to check against the view
@param[in]    name    table name
@return whether the view sees the modifications of id. */
[[nodiscard]] bool changes_visible(trx_id_t id,
                                   const table_name_t &name) const {
  ut_ad(id > 0);

  if (id < m_up_limit_id || id == m_creator_trx_id) {
    return (true);
  }

  check_trx_id_sanity(id, name);

  if (id >= m_low_limit_id) {
    return (false);

  } else if (m_ids.empty()) {
    return (true);
  }

  const ids_t::value_type *p = m_ids.data();

  return (!std::binary_search(p, p + m_ids.size(), id));
}
```

```c
/**
@param id             transaction to check
@return true if view sees transaction id */
bool sees(trx_id_t id) const { return (id < m_up_limit_id); }
```

**레코드의 trx_id가 m_ids에 포함된(즉, 아직 활성화된) 트랜잭션이면 가시성은 false여야 할텐데, 이 부분은 어딨을까 ?**
- `return (!std::binary_search(...))` 이 라인이 **m_ids에 포함되면 false, 포함되지 않으면 true**를 리턴하는 로직
  - `std::binary_search(...)`는 true를 리턴 (trx_id가 m_ids에 포함되어 있음)
  - 즉, `!std::binary_search(...)`이면 포함되어 있지 않다는 뜻 = 가시성 있음

## 참고 자료
- [https://dev.mysql.com/doc/dev/mysql-server/8.4.4/classReadView.html#ac5d400b93acde22a935a34a672641e3c](https://dev.mysql.com/doc/dev/mysql-server/8.4.4/classReadView.html#ac5d400b93acde22a935a34a672641e3c)
- [https://xialeistudio.medium.com/understanding-mvcc-in-mysql-innodb-116100a27b65](https://xialeistudio.medium.com/understanding-mvcc-in-mysql-innodb-116100a27b65)
