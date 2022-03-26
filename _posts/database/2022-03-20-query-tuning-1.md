---
title: (쿼리 튜닝) group by, order by, 드라이빙 테이블 수정을 통한 쿼리 성능 개선하기
date: 2022-03-20 23:00:00 +0900
categories: [Database]
tags: [MySQL, SQL]
---

# 들어가기 전
---
회사에서 개발하면서 처음으로 슬로우 쿼리를 개선해보았다. 제대로 한건지는 모르겠지만 나름대로 공부해서 7초에서 0.4초까지 개선되었다.
그 과정을 간략하게 적어보고 앞으로 또 다른 슬로우 쿼리를 만나게되면 기록할 예정이다.

# 쿼리 튜닝 과정
---
> 최초 쿼리 수행 시간 : 약 7초

- 최초 쿼리는 다음과 같다. (문제가 됐던 부분 기록, 테이블명, 컬럼명은 보안상 변경)

```sql
    SELECT
    (SELECT GROUP_CONCAT(tmp.cnt) FROM
        (SELECT og.컬럼1, count(gu.컬럼2) cnt
             FROM tbl5 og
             LEFT OUTER JOIN (SELECT 컬럼1, 컬럼2 FROM tbl6 WHERE 컬럼3 IS NOT NULL) gu
             ON og.컬럼1 = gu.컬럼1 and og.컬럼2 = gu.컬럼2
                GROUP BY og.컬럼2, og.컬럼1
                ORDER BY og.컬럼2) tmp
        WHERE tmp.컬럼1 = tbl1.컬럼1) as regi_qty,

    ...

    FROM tbl1
    LEFT OUTER JOIN tbl2 ON tbl1.컬럼1 = tbl2.컬럼1
    LEFT OUTER JOIN tbl3 ON tbl1.컬럼1 = tbl3.컬럼1
    LEFT OUTER JOIN tbl4 ON tbl1.컬럼4 = tbl4.컬럼4
    WHERE 1=1
        AND tbl1.등록일 >= '2021-09-20'
        AND tbl1.등록일 < ADDDATE('2022-03-20',1)
        AND tbl1.주문타입 IN ( '값1' , '값2' );
```

## 실행계획
<img width="1086" alt="image" src="https://user-images.githubusercontent.com/64415489/160244695-657aaf1c-9722-40c3-bbc1-09c5394e1d4e.png">

- 문제가 될만한 부분이라고 생각했던 부분에 표시를 했다.
  - og 테이블 인덱스 풀스캔
    - 그로 인해 임시 테이블인 derived7 테이블을 만들기 위해 조인시 많은 레코드에 접근
  - 임시 테이블 생성 및 정렬 (`Using temporary, Using filesort`)

## 튜닝1
> 임시 테이블 생성 및 정렬하는 부분을 제거했다. (수행 시간 : 약 3.5초)

- MySQL은 `GROUP BY`, `ORDER BY` 처리를 위해 임시 테이블을 만들기 때문에, `Using temporary, Using filesort`가 나오게 된다.
- 인덱스는 이미 정렬되어 있기 때문에, `GROUP BY`, `ORDER BY`를 인덱스 기준으로 하면 위해 임시 테이블을 만들 필요가 없다.
  - og 테이블의 인덱스는 `(컬럼1,컬럼2)`로 구성되었기 때문에, `GROUP BY`, `ORDER BY`에 명시된 컬럼 순서를 인덱스가 구성된 순서로 변경했다.


### 변경된 쿼리
```sql
    SELECT
    (SELECT GROUP_CONCAT(tmp.cnt) FROM
        (SELECT og.컬럼1, count(gu.컬럼2) cnt
             FROM tbl5 og
             LEFT OUTER JOIN (SELECT 컬럼1, 컬럼2 FROM tbl6 WHERE 컬럼3 IS NOT NULL) gu
             ON og.컬럼1 = gu.컬럼1 and og.컬럼2 = gu.컬럼2
                GROUP BY og.컬럼1, og.컬럼2
                ORDER BY og.컬럼1, og.컬럼2) tmp
        WHERE tmp.컬럼1 = tbl1.컬럼1) as regi_qty,

    ...

    FROM tbl1
    LEFT OUTER JOIN tbl2 ON tbl1.컬럼1 = tbl2.컬럼1
    LEFT OUTER JOIN tbl3 ON tbl1.컬럼1 = tbl3.컬럼1
    LEFT OUTER JOIN tbl4 ON tbl1.컬럼4 = tbl4.컬럼4
    WHERE 1=1
        AND tbl1.등록일 >= '2021-09-20'
        AND tbl1.등록일 < ADDDATE('2022-03-20',1)
        AND tbl1.주문타입 IN ( '값1' , '값2' );
```

- `Using temporary, Using filesort`가 없어진 것을 볼 수 있다.
<img width="1193" alt="image" src="https://user-images.githubusercontent.com/64415489/160246160-31631293-46a4-41c7-9135-49f3c7627a7b.png">

## 튜닝2
> 드라이빙 테이블(og)에서 인덱스 풀스캔을 하지 않도록 변경했다. (수행 시간 : 약 0.4초)

- 드라이빙 테이블, 드리븐 테이블 중 하나라도 인덱스 풀스캔을 하게되면 결과적으로 조인 횟수가 많아지기 때문에, 풀스캔 하지 않는 방법을 찾아보았다.
- og, gu 테이블로 인해 생성되는 임시 테이블 `tmp`은 필터 조건(등록일, 주문타입)으로 많은 레코드가 걸러진 `tbl1`의 `컬럼1`이 필터조건이 된다.
  - 즉, `tmp` 테이블은 `tbl1`을 `컬럼1`을 기준으로 많은 부분이 걸러지게된다.
  - 따라서, og 테이블에서 애초에 모든 레코드를 가져올 필요 없이 `tbl1`의 필터 조건을 활용할 수 없을지 생각해보았다.
  - og 테이블 인덱스는 `(컬럼1,컬럼2)`인데 `컬럼1`의 경우, `년월일+a`의 규칙을 갖고 생성되기 때문에, 등록일 부분을 활용하면 될 것으로 생각했다.

### 변경된 쿼리
```sql
    SELECT
    (SELECT GROUP_CONCAT(tmp.cnt) FROM
        (SELECT og.컬럼1, count(gu.컬럼2) cnt
             FROM (SELECT 컬럼1, 컬럼2 FROM tbl5 WHERE 컬럼1 BETWEEN '20210920' AND '20220321') og
             LEFT OUTER JOIN (SELECT 컬럼1, 컬럼2 FROM tbl6 WHERE 컬럼3 IS NOT NULL) gu
             ON og.컬럼1 = gu.컬럼1 and og.컬럼2 = gu.컬럼2
                GROUP BY og.컬럼1, og.컬럼2
                ORDER BY og.컬럼1, og.컬럼2) tmp
        WHERE tmp.컬럼1 = tbl1.컬럼1) as regi_qty,

    ...

    FROM tbl1
    LEFT OUTER JOIN tbl2 ON tbl1.컬럼1 = tbl2.컬럼1
    LEFT OUTER JOIN tbl3 ON tbl1.컬럼1 = tbl3.컬럼1
    LEFT OUTER JOIN tbl4 ON tbl1.컬럼4 = tbl4.컬럼4
    WHERE 1=1
        AND tbl1.등록일 >= '2021-09-20'
        AND tbl1.등록일 < ADDDATE('2022-03-20',1)
        AND tbl1.주문타입 IN ( '값1' , '값2' );
```

- 인덱스 레인지 스캔으로 변경됨과 동시에, (정확한 수치는 아니지만) 접근하는 레코드가 확연히 줄어든 것을 볼 수 있다.
<img width="1160" alt="image" src="https://user-images.githubusercontent.com/64415489/160246410-b501e5b8-4bb0-47df-9155-25ec8de5670d.png">
