---
title: MySQL - PK와 인덱스
date: 2025-03-04 22:00:00 +0900
categories: [지식 더하기, 이론]
tags: [MySQL]
---

# 내가 테이블의 PK를 정할때를 생각해보면 ..
- 일반적으로는 auto_increment seq를 사용하는 것 같다.
  => 왜 ?
  - 음 .. 유의미한 값을 사용하게되면, 추후 요구사항이나 상황이 변함에 따라 PK를 변경해야할 일이 생길 수 있음
    => PK 변경하면 뭐가 안좋음 ?
    => seq말고도 유의미하지 않은 값들은 여럿있지 않나 ?

# PK 변경하면 뭐가 안좋음 ?
> PK에 따라 어떤식으로 데이터가 저장될까 ?

## Clustered Index
> To get the best performance from queries, inserts, and other database operations, it is important to understand how InnoDB uses the clustered index to optimize the common lookup and DML operations.

- When you define a PRIMARY KEY on a table, InnoDB uses it as the clustered index.
- If you do not define a PRIMARY KEY for a table, InnoDB uses the first UNIQUE index with all key columns defined as NOT NULL as the clustered index.
- If a table has no PRIMARY KEY or suitable UNIQUE index, InnoDB generates a hidden clustered index named GEN_CLUST_INDEX on a synthetic column that contains row ID values. The rows are ordered by the row ID that InnoDB assigns. The row ID is a 6-byte field that increases monotonically as new rows are inserted. Thus, the rows ordered by the row ID are physically in order of insertion.

### How the Clustered Index Speeds Up Queries
- Accessing a row through the clustered index is fast because the index search leads directly to the page that contains the row data.
  - 인덱스를 검색하면 곧바로 데이터 페이지를 찾을 수 있음
  - 클러스터 인덱스는 **프라이머리 키(Primary Key)**를 기준으로 B+Tree 구조로 저장됨.
  - 그리고 **리프 노드(Leaf Node)**에 해당 행의 전체 데이터가 직접 저장됨.
  - 따라서 프라이머리 키를 이용해 검색하면, 즉시 해당 데이터가 있는 페이지를 찾을 수 있음.

- If a table is large, the clustered index architecture often saves a disk I/O operation when compared to storage organizations that store row data using a different page from the index record.
  - 테이블이 클수록, 일반적인 인덱스 방식은 인덱스가 저장된 페이지와 실제 데이터가 저장된 페이지가 다를 가능성이 큼.
  - 하지만 클러스터 인덱스는 인덱스 리프 노드에 데이터가 포함되므로, 추가적인 데이터 페이지 검색이 필요 없음.
  - 즉, 디스크 I/O가 줄어들고 검색 속도가 빨라짐.

### Secondary Index
- 클러스터 인덱스 외의 인덱스를 보조 인덱스(Secondary Index)라고 한다.
- InnoDB에서 보조 인덱스를 생성하면, 보조 인덱스에 프라이머리 키 값도 함께 저장됨.
  즉, 보조 인덱스의 리프 노드에는 해당 인덱스에서 검색할 값 + 프라이머리 키 값이 들어감.
   예제: customer_id를 사용해 조회하는 경우

SELECT * FROM orders WHERE customer_id = 200;
customer_id에 대한 보조 인덱스(idx_customer)를 검색하면,
→ 해당 행의 order_id(프라이머리 키 값)를 반환함.
order_id 값을 이용해 클러스터 인덱스를 다시 조회하여 실제 데이터를 가져옴.
→ 즉, "두 번의 검색"이 필요함.
=> 보조 인덱스를 이용한 검색은 프라이머리 키를 통해 원본 데이터에 접근하는 과정이 필요.
따라서 보조 인덱스를 사용할 경우 디스크 I/O가 추가로 발생할 수 있음.

- 프라이머리 키가 길면 보조 인덱스가 더 많은 공간을 차지하므로, 짧은 프라이머리 키를 사용하는 것이 유리하다.
- 보조 인덱스는 프라이머리 키 값을 저장하므로, 프라이머리 키가 길어질수록 보조 인덱스의 크기도 커짐.
  인덱스가 커지면 디스크 공간을 더 차지하고 검색 속도도 느려질 수 있음.
  따라서 짧고 효율적인 프라이머리 키를 선택하는 것이 중요함.

**※ 디스크 공간 사용량이 커지면 검색 속도가 느려지는 이유**
📌 1. 인덱스 크기가 커지면 더 많은 디스크 I/O가 발생함
🔹 B+Tree 인덱스는 계층 구조를 가지므로, 크기가 커질수록 트리 깊이가 증가함
MySQL(InnoDB)에서 사용하는 B+Tree 인덱스는 계층 구조를 가짐.
인덱스 크기가 커지면 트리의 높이(Depth)가 증가하게 됨.
검색을 수행할 때 루트 노드 → 내부 노드 → 리프 노드를 거쳐야 하는데,
트리 깊이가 깊어질수록 검색 시 더 많은 디스크 페이지를 읽어야 함.
📌 예제: 프라이머리 키가 짧은 경우 vs 긴 경우

INT 타입의 PRIMARY KEY 사용:
B+Tree의 한 페이지에 더 많은 키 값을 저장 가능.
트리의 높이가 작아지고 검색 속도가 빨라짐.
VARCHAR(255)를 PRIMARY KEY로 사용:
각 키가 차지하는 공간이 크므로, B+Tree의 한 페이지에 들어갈 수 있는 키 개수가 줄어듦.
트리 깊이가 증가하면서 검색 시 더 많은 페이지를 읽어야 함 → 검색 속도 저하.
📌 트리 깊이에 따른 검색 비용 차이

트리 깊이 = 3 (작은 인덱스) → 검색 시 3번의 디스크 접근.
트리 깊이 = 5 (큰 인덱스) → 검색 시 5번의 디스크 접근.
트리 깊이가 클수록 검색 속도 저하!
📌 2. 디스크에서 더 많은 페이지를 읽어야 함
🔹 인덱스 크기가 커지면, 한 번의 검색에 필요한 페이지 수가 증가
디스크는 기본적으로 블록(Block) 단위로 데이터를 읽음.
인덱스 크기가 크면, 한 번의 검색을 위해 필요한 블록(페이지) 수도 증가함.
즉, 디스크에서 데이터를 가져오는 과정(Disk I/O)이 더 많이 발생하게 됨.
📌 디스크 I/O의 영향

데이터베이스는 디스크에서 데이터를 읽는 것이 가장 느린 작업.
CPU 연산보다 디스크 읽기가 훨씬 느리므로, 인덱스 크기가 클수록 검색 성능 저하 가능성 증가.


📌 3. 데이터 캐싱(메모리 히트율)이 낮아짐
🔹 디스크 공간을 많이 차지하면, 메모리(버퍼 풀)에서 인덱스를 캐싱하기 어려워짐
MySQL의 InnoDB Buffer Pool(메모리)은 자주 사용되는 데이터를 캐싱하여 디스크 I/O를 줄임.
하지만 인덱스 크기가 크면, 전체 인덱스를 메모리에 올려두기 어려워짐.
결국, 디스크에서 데이터를 읽어오는 빈도가 증가하여 검색 속도가 느려짐.
📌 비교 예시

작은 인덱스: 전체 인덱스를 메모리에 캐싱할 수 있어, 디스크 I/O 없이 빠른 검색 가능.
큰 인덱스: 캐싱이 어렵고, 검색할 때마다 디스크에서 데이터를 읽어야 하므로 속도 저하.

# ## PK 목적 ?
- row를 유일하게 식별
  - 왜 식별해야할까 ?
- PK가 없으면 ?
  - mysql에서는 (내부적으로) 자동으로 생성됨

## PK 변경하면 뭐가 안좋음 ?


- 인덱스 재구성 ?

###

## seq말고도 유의미하지 않은 값들은 여럿있지 않나 ?



# 참고 자료
- [https://dev.mysql.com/doc/refman/8.0/en/innodb-index-types.html](https://dev.mysql.com/doc/refman/8.0/en/innodb-index-types.html)
