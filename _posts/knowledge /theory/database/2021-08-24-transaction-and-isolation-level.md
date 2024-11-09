---
title: MySQL - 트랜잭션과 격리 수준
date: 2021-08-24 23:00:00 +0900
categories: [지식 더하기, 이론]
tags: [MySQL]
---

# 트랜잭션과 ACID
---
- 트랜잭션이란 ?
  - 데이터베이스 상태를 변경시키는 일련의 연산들을 논리적으로 묶을 수 있는 하나의 작업 단위
    - ex) 주문 - 결제 - 결제 승인 - 주문 접수
  - 트랜잭션에는 중요한 두 가지 목적이 있다.
    1. 장애로부터 올바르게 복구하고 데이터베이스를 일관되게 유지할 수 있는 안정적인 작업 단위를 제공
    2. 동시에 데이터베이스에 액세스하는 프로그램 간의 격리 제공

## ACID
> DBMS는 각각의 트랜잭션에 대해 다음 4가지 특징을 보장한다.
> 트랜잭션의 이러한 특징은 ***데이터 정합성***을 보장해준다.

- Atomicity(원자성)
  - 트랜잭션이 한 번에 이루어지거나 전혀 발생하지 않는다. 따라서, 변경이 부분적으로 발생하지 않는다.
  - 다음 두 가지 작업을 포함한다.
    - 중단(abort): 트랜잭션이 중단되면 데이터베이스의 변경 내용이 반영되지 않는다.
    - 커밋(commit): 트랜잭션이 커밋하면 변경 내용이 반영된다.
  - 원자성은 'All or nothing rule'이라고도 한다.

- Consistency(일관성)
  - 트랜잭션 전후에 데이터베이스가 일관되도록 무결성(데이터의 일관성, 유효성)이 유지되어야 한다.
  - 예를 들어 A가 B에게 송금하는 상황이라면, 거래 전후의 두 사람이 갖고 있는 금액의 총합은 동일해야 한다.

- Isolation(고립성)
  - 여러 트랜잭션은 서로 간의 간섭 없이 독립적으로 발생해야 한다.
  - 즉, 특정 트랜잭션에서 발생하는 변경 사항은 해당 트랜잭션의 특정 변경 사항이 메모리에 기록되거나 커밋될 때까지 다른 트랜잭션에서 볼 수 없다.
  - 이로 인해, 데이터베이스 상태의 불일치 없이 여러 트랜잭션이 동시에 발생할 수 있다.

- Durability(영구성)
  - 트랜잭션 실행이 완료되면 데이터베이스에 대한 업데이트 및 수정 내용이 디스크에 저장되고 시스템에 오류가 발생하더라도 유지된다.
  - 이러한 업데이트는 영구적이며 비휘발성 메모리에 저장된다.

# 트랜잭션 격리 수준(Isolation Level)이란 ?
---
- 동시에 여러 트랜잭션이 처리될 때, 특정 트랜잭션이 다른 트랜잭션에서 변경하거나 조회하는 데이터를 볼 수 있도록 허용할지 말지 결정하는 것.
- 격리 수준은 크게 4가지로 나뉜다 (밑으로 갈수록 격리 수준 높아짐)
  - READ UNCOMMITTED(DIRTY READ)
  - READ COMMITTED
  - REPEATABLE READ
  - SERIALIZABLE
- 격리 수준이 높아질수록 동시성이 떨어지는 것이 일반적이다.
  - 하지만, SERIALIZABLE 격리 수준이 아니라면 크게 성능의 개선이나 저하는 발생하지 않는다.

## READ UNCOMMITTED
- 커밋되지 않은 변경에 대해 조회가 가능하다.
- 특정 트랜잭션에서 처리한 작업이 완료되지 않았는데 다른 트랜잭션에서 볼 수 있게 되는 현상을 'Dirty Read'라고 한다.
  - 이로 인해 데이터가 나타났다 사라졌다 하는 현상이 발생할 수 있다.
- RDBMS 표준에서는 트랜잭션의 격리 수준으로 인정하지 않을 정도로 데이터 정합성에 문제가 많은 격리 수준이다.

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/130653958-51a0508a-f094-404e-a336-5eab5b37e65c.png" width="90%"/>
  <figcaption align="center">출처 : <a href="https://lng1982.tistory.com/287" target="_blank"> https://lng1982.tistory.com/287</a> </figcaption>
</figure>

## READ COMMITTED
- 특정 트랜잭션에서 커밋 완료된 데이터만 다른 트랜잭션에서 조회할 수 있다.
- Oracle DBMS에서 기본적으로 사용되는 격리 수준이며, 일반적으로 가장 많이 사용된다.

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/130654723-8ee8c5e9-feba-48a5-b140-c85445fe84cc.png" width="90%"/>
  <figcaption align="center">출처 : <a href="https://lng1982.tistory.com/287" target="_blank"> https://lng1982.tistory.com/287</a> </figcaption>
</figure>

- Dirty Read는 발생하지 않지만, NON-REPEATABLE READ 문제가 발생할 수 있다.
- 즉, 하나의 트랜잭션 내에서 똑같은 SELECT 쿼리를 실행했는데 다른 결과가 나올 수 있게된다. <br>
(Bob이 post 테이블에서 id가 1인 것을 조회하는데 처음엔 Transactions, 그 다음엔 ACID가 조회된다.)

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/130656295-22ae5359-3938-407c-92e9-00680d4fcbbf.png" width="80%"/>
  <figcaption align="center">출처 : <a href="https://vladmihalcea.com/non-repeatable-read/" target="_blank"> https://vladmihalcea.com/non-repeatable-read/</a> </figcaption>
</figure>

- 이러한 부정합 현상은 일반적인 웹 프로그램에서는 크게 문제되지 않을 수 있지만, 하나의 트랜잭션에서 동일한 데이터를 여러 번 읽고 변경하는 작업이 금전적인 처리와 연결되면 문제가 될 수 있다.
  - 예를 들어, 다른 트랜잭션에서 입출금 처리가 계속 진행되는데 또 다른 트랜잭션에서 오늘 입금된 금액의 총합을 조회하는 경우, 조회할 때마다 다른 결과가 나오게된다.

## REPEATABLE READ
- NON-REPEATABLE READ 부정합 문제가 발생하지 않는다.
- MySQL의 InnoDB 스토리지 엔진에서 기본적으로 사용되는 격리 수준이다.
- 트랜잭션이 롤백될 가능성에 대비해 변경 전 데이터를 언두(Undo) 공간에 백업해두고 실제 레코드 값을 변경한다.
  - 이러한 변경 방식을 MVCC(Multi Version Concurrency Control)이라고 한다.
  - READ COMMITTED도 MVCC를 이용해 COMMIT 되기 전의 데이터를 보여준다.
    - 차이는 언두 영역에 백업된 레코드의 여러 버전 가운데 몇 번째 이전 버전까지 찾아 들어가는지에 있다.
- 모든 InnoDB의 트랜잭션은 고유한 트랜잭션 번호(순차적으로 증가하는 값)를 가진다.
- 언두 영역에 백업된 모든 레코드에는 변경을 발생시킨 트랜잭션 번호가 포함된다.
  - 언두 영역의 백업된 데이터는 InnoDB 스토리지 엔진이 불필요하다고 판단하는 시점에 주기적으로 삭제한다.
  - REPEATABLE READ 격리 수준에서는 실행 중인 트랜잭션 가운데 가장 오래된 트랜잭션 번호보다 앞선 트랜잭션 번호를 갖는 레코드를 언두 영역에서 삭제할 수 없다.
- 아래 예에서 T2의 트랜잭션 번호는 10이므로, 해당 트랜잭션 안에서 실행되는 모든 SELECT 쿼리는 트랜잭션 번호가 10보다 작은 트랜잭션 번호에서 변경한 것만 보게 된다.
  - 만약 하나의 트랜잭션이 장시간 동안 지속되면 언두 영역이 백업된 데이터로 무한정 커질 수도 있다.
  - 백업된 레코드가 많아지면 DB 서버의 처리 성능이 떨어질 수 있다.
<img src="https://user-images.githubusercontent.com/64415489/130663971-6832167f-d5c0-40de-a30e-0be7988fb663.png" width="80%"/>

- REPEATABLE READ에서는 PHANTOM READ(PHANTOM ROW) 부정합 문제가 나타날 수 있다.
  - PHANTOM READ : 다른 트랜잭션에서 수행한 변경 작업에 의해 레코드가 보였다 안 보였다 하는 현상
- `SELECT ... FOR UPDATE` 쿼리는 SELECT 하는 레코드에 쓰기 잠금을 걸어야 하는데, 언두 영역의 레코에는 잠금을 걸 수 없다. 따라서, 언두 영역이 아닌 실제로 변경된 테이블에서 값을 가져오게 된다.

<img src="https://user-images.githubusercontent.com/64415489/130666537-1b74668f-19f6-412c-a229-7939242814af.png" width="80%"/>


## SERIALIZABLE
- 가장 단순하면서 엄격한 격리 수준이다.
- 동시 처리 성능도 다른 격리 수준에 비해 떨어진다.
- InnoDB 테이블에서 기본적으로 순수한 SELECT 작업은(`INSERT ... SELECT ...` 또는 `CREATE TABLE ... AS SELECT ...`가 아닌) 아무런 레코드 잠금을 설정하지 않고 실행된다.
  - 하지만 SERIALIZABLE 격리 수준에서는 이러한 읽기 작업도 공유 잠금을 획득해야 한다.
  - 따라서 다른 트랜잭션에서는 절대 접근할 수 없다.

### 참고. DB별 격리 수준(default)
```
MS-SQL : READ COMMITTED
MySQL : REPEATABLE READ
ORACLE : READ COMMITTED
H2 : READ COMMITTED
```

## 격리 수준에 따른 부정합 문제 정리
> 위에서 살펴본 격리 수준별 부정합 문제를 다시 한 번 정리해보자.

1. Dirty Read : 트랜잭션이 아직 커밋되지 않은 데이터를 읽는 것.
2. Non Repeatable read : 동일한 트랜잭션 내에서 실행한 동일한 SELECT 쿼리가 다른 결과를 가져오는 것.
3. Phantom Read :  다른 트랜잭션에서 수행한 변경 작업에 의해 레코드가 보였다 안 보였다 하는 것.

|격리 수준|DIRTY READ|NON-REPEATABLE READ|PHANTOM READ|
|---|----|----|----|
|READ UNCOMMITTED| O | O | O |
|READ COMMITTED| X | O | O |
|REPEATABLE READ| X | X |O (InnoDB는 X) |
|SERIALIZABLE| X | X | X |

# 참고 자료
---
- 이성욱, 『개발자와 DBA를 위한 Real MySQL』, 위키북스(2012), 4장
- [https://www.geeksforgeeks.org/acid-properties-in-dbms/](https://www.geeksforgeeks.org/acid-properties-in-dbms/)
- [https://en.wikipedia.org/wiki/Database_transaction](https://en.wikipedia.org/wiki/Database_transaction)
- [https://lng1982.tistory.com/287](https://lng1982.tistory.com/287)
