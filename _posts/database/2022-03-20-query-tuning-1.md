---
title: (쿼리 튜닝) group by, order by, 드라이빙 테이블 수정을 통한 쿼리 성능 개선하기
date: 2022-03-20 23:00:00 +0900
categories: [Database]
tags: [MySQL, SQL]
---

# 들어가기 전
---
회사에서 개발하면서 처음으로 슬로우 쿼리를 개선해보았다. 제대로 한건지는 모르겠지만 나름대로 공부해서 7초에서 1초 미만으로 개선되었다.
그 과정을 간략하게 적어보고 앞으로 또 다른 슬로우 쿼리를 만나게되면 기록할 예정이다.

# 최초 쿼리
---
> 수행 시간 : 약 7초

- 쿼리는 다음과 같다. (문제가 됐던 부분 위주로, 테이블명시, 컬럼명은 보안상 변경)

```sql
    SELECT
    (SELECT GROUP_CONCAT(tmp.cnt) FROM
        (SELECT og.컬럼1, count(gu.컬럼2) cnt FROM tbl5 og
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


최초 : 7초

group by, order by 인덱스 순서로 변경
-> 3.5초

드라이빙 테이블 건수 줄이기
-> 0.5초

order 전체 건수 : 16940
필터 건수 : 1093

order_gift 전체 건수 : 21158
필터 건수 : 2710

gift_user 전체 건수 : 5106001
필터 건수 : 3569796

