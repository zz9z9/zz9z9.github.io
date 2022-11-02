---
title: MySQL의 lock과 deadlock 살펴보기
date: 2022-11-02 23:00:00 +0900
categories: [Database]
tags: [MySQL, Deadlock]
---

## Locking
- 다른 트랜잭션에 의해 조회되거나 변경되는 데이터를 보거나 변경하지 못하도록 트랜잭션을 보호하는 시스템
- The system of protecting a transaction from seeing or changing data that is being queried or changed by other transactions.
- The locking strategy must balance reliability and consistency of database operations (the principles of the ACID philosophy) against the performance needed for good concurrency.
- Fine-tuning the locking strategy often involves choosing an isolation level and ensuring all your database operations are safe and reliable for that isolation level.

##

## Table Lock

## Row Lock

## Deadlock
- A deadlock is a situation when two or more transactions mutually hold and request a lock that the other needs. As a result, a cycle of dependencies is created and the transactions cannot proceed. By default, InnoDB automatically detects deadlocks and rolls back one transaction (the victim) to break the cycle. Normally, the transaction that infects a smaller number of rows will be picked.


# 참고 자료
---
- [https://lynn-kwong.medium.com/understand-the-basics-of-locks-and-deadlocks-in-mysql-part-i-92f229db0a](https://lynn-kwong.medium.com/understand-the-basics-of-locks-and-deadlocks-in-mysql-part-i-92f229db0a)
- [https://dev.mysql.com/doc/refman/8.0/en/innodb-deadlocks.html](https://dev.mysql.com/doc/refman/8.0/en/innodb-deadlocks.html)
- [https://dev.mysql.com/doc/refman/8.0/en/glossary.html#glos_locking](https://dev.mysql.com/doc/refman/8.0/en/glossary.html#glos_locking)
