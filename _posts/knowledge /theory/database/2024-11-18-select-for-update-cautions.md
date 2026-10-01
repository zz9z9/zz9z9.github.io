---
title: MySQL - SELECT FOR UPDATE 알아보기
date: 2024-11-18 21:00:00 +0900
categories: [지식 더하기, 이론]
tags: [MySQL]
---

## SELECT FOR UPDATE
- 비관적락
- InnoDB 엔진에서 지원하는 locking read 중 하나.
  - 다른 하나는 `SELECT ... LOCK IN SHARE MODE` (MySQL5), `SELECT ... FOR SHARE` (MySQL8)
- 트랜잭션의 격리 수준에 따라 교착 상태가 발생할 가능성이 있습니다.
- `FOR SHARE` 및 `FOR UPDATE` 쿼리에 의해 설정된 모든 잠금은 트랜잭션이 커밋되거나 롤백될 때 해제됩니다.
- 검색에서 발견한 인덱스 레코드의 경우 해당 행에 대해 UPDATE 문을 실행한 것과 마찬가지로 행 및 관련 인덱스 항목을 잠급니다.
- 다른 트랜잭션은 해당 행을 업데이트하거나 `SELECT ... FOR SHARE`를 수행하거나 특정 트랜잭션 격리 수준에서 데이터를 읽는 것이 차단됩니다.
- 일관된 읽기(Consistent reads)는 read view에 존재하는 레코드에 설정된 잠금을 무시합니다. (이전 버전의 레코드는 잠글 수 없습니다. 레코드의 메모리 내 복사본에 undo logs를 적용하여 재구성됩니다.)
  - **read view ?**

- `SELECT ... FOR UPDATE` 쿼리는 SELECT 하는 레코드에 쓰기 잠금을 걸어야 하는데, 언두 영역의 레코드에는 잠금을 걸 수 없다. 따라서, 언두 영역이 아닌 실제로 변경된 테이블에서 값을 가져오게 된다.
  - 이로 인해 Phantom Read가 발생할 수 있다. (InnoDB에서는 발생하지 않는다고 한다 => 어떻게?)


### SELECT FOR UPDATE with NOWAIT and SKIP LOCKED
- 요청된 행이 잠겨 있을 때 쿼리가 즉시 반환되기를 원하거나 결과 집합에서 잠긴 행을 제외하는 것이 허용되는 경우 행 잠금이 해제될 때까지 기다릴 필요가 없습니다.
- 다른 트랜잭션이 행 잠금을 해제할 때까지 기다리지 않으려면 `NOWAIT` 및 `SKIP LOCKED` 옵션을 `SELECT ... FOR UPDATE` 또는 `SELECT ... FOR SHARE` 잠금 읽기 문과 함께 사용할 수 있습니다.

- `NOWAIT`
  - NOWAIT를 사용하는 잠금 읽기는 행 잠금 획득을 기다리지 않습니다.
  - 쿼리는 즉시 실행되며, 요청된 행이 잠겨 있으면 오류와 함께 실패합니다.

- `SKIP LOCKED`
  - `SKIP LOCKED`를 사용하는 잠금 읽기는 행 잠금을 획득할 때까지 기다리지 않습니다.
  - 쿼리가 즉시 실행되어 결과 집합에서 잠긴 행이 제거됩니다.
  - 잠긴 행을 건너뛰는 쿼리는 일관되지 않은 데이터 보기를 반환합니다.
  - 따라서 `SKIP LOCKED`는 일반적인 거래 작업에는 적합하지 않습니다.
  - 그러나 여러 세션이 동일한 대기열형 테이블에 액세스할 때 잠금 경합을 피하기 위해 사용될 수 있습니다.

## Consistent Reads
> https://dev.mysql.com/doc/refman/8.4/en/glossary.html#glos_consistent_read

- 동시에 실행되는 **다른 트랜잭션의 변경 사항에 관계없이** 스냅샷 정보를 사용하여 **특정 시점을 기준으로 쿼리 결과를 제시**하는 읽기 작업입니다.
- 쿼리된 데이터가 다른 트랜잭션에 의해 변경된 경우 Undo 로그 내용을 기준으로 원본 데이터를 재구성합니다.
- 이 기술은 트랜잭션이 다른 트랜잭션이 완료될 때까지 기다리도록 하여 동시성을 줄일 수 있는 일부 잠금 문제를 방지합니다.

- 즉, 정리해보면 데이터 일관성을 위해 잠금하고 다른 Tx에서 데이터 변경을 막는게 아닌, 다른 Tx에서 데이터를 변경했으면undo logs에 구성해서 일관된 데이터 읽을 수 있도록.
  - 잠금하지 않으므로 성능에도 이득

## undo logs
> https://dev.mysql.com/doc/refman/8.4/en/glossary.html#glos_undo_log

- 활성 트랜잭션에 의해 수정된 데이터의 복사본을 보관하는 저장 영역입니다.
- 다른 트랜잭션이 원본 데이터를 확인해야 하는 경우(Consistent Reads 작업의 일부로) 수정되지 않은 데이터가 이 스토리지 영역에서 검색됩니다.

## MVCC

## 2PL (Phase-Locking)

## Record Lock
- 레코드 자체만을 잠그는 것
- InnoDB 스토리지 엔진은 레코드 자체가 아니라 **인덱스의 레코드**를 잠근다.
  - 즉, 변경해야 할 레코드를 찾기 위해 검색한 인덱스의 레코드를 모두 잠가야 한다.
  - 인덱스가 하나도 없는 테이블이더라도 내부적으로 자동 생성된 **클러스터 인덱스**를 이용해 잠금 설정
- InnoDB에서는 대부분 보조 인덱스를 이용한 변경 작업은 `넥스트 키 락` 또는 `갭 락`을 사용
- 프라이머리 키 또는 유니크 인덱스에 의한 변경 작업은 레코드 자체에 대해서만 락을 건다.

## Gap Lock
- 레코드 자체가 아닌 레코드와 바로 인접한 레코드 사이의 간격만을 잠그는 것을 의미
- 레코드와 레코드 사이의 간격에 새로운 레코드가 생성되는 것을 제어
- `갭 락`은 개념이기 때문에 자체적으로 사용되지 않고, `넥스트 키 락`의 일부로 사용된다.

## Next-Key Lock
- InnoDB 스토리지 엔진은 MySQL에서 제공하는 잠금과는 별개로 스토리지 엔진 내부에서 **레코드 기반의 잠금** 방식을 탑재하고 있다.
- Record Lock과 Gap Lock의 조합
- InnoDB의 default isolation level인 REPEATABLE READ 에서는 팬텀 리드(phatom read)를 막기 위해 넥스트 키 락을 사용
- 갭 락이나 넥스트 키 락의 주 목적은, 바이너리 로그에 기록되는 쿼리가 슬레이브에서 실행될 때 마스터에서 만들어낸 결과와 동일한 결과를 만들어내도록 보장하는 것

# 참고 자료
---
- 이성욱, 『개발자와 DBA를 위한 Real MySQL』, 위키북스(2012), 4장
- https://dev.mysql.com/doc/refman/8.4/en/innodb-locking-reads.html
- https://dev.mysql.com/doc/refman/8.4/en/glossary.html#glos_locking_read
