---
title: 엔티티에서 데이터베이스 키워드/예약어 사용시 발생하는 문제
date: 2021-07-07 00:29:00 +0900
categories: [개발 이슈]
tags: [JPA]
---

# 상황
---
- 주문 테이블에 맵핑되는 엔티티를 만들기 위해 ORDER 라는 엔티티를 생성
```java
@Getter
@Setter
@Entity
public class Order {
    @Id
    private Long id;
    private OrderStatus orderStatus;
}
```

- 스프링 부트 실행하고 h2 db에 테이블 생성되나 확인하려고 하는데 아래와 같은 에러 발생하면서 테이블 생성이 안됨
```
Caused by: org.h2.jdbc.JdbcSQLSyntaxErrorException: Syntax error in SQL statement "
    CREATE TABLE ORDER[*] (
       ID BIGINT NOT NULL,
        ORDER_STATUS INTEGER,
        PRIMARY KEY (ID)
    ) "; expected "identifier"; SQL statement:
```

# 원인
---
- `ORDER`라는 클래스 이름이 데이터베이스 키워드/예약어(예. ORDER, GROUP, SELECT, WHERE 등)에 이미 있기 때문에 스키마 생성에 실패한 것

# 해결방법
---
## 1. escape 문자 사용

## 2. backtick 문자 사용

## 3. globally_quoted_identifiers 설정값 세팅

## 4. 키워드/예약어 사용하지 않기

# 선택한 방법
---
- 네이티브 쿼리 사용시에도 불편하고, 김영한님 강의에서도 관례적으로 `ORDERS`라는 이름으로 사용한다고 하니 ORDER → ORDERS로 바꾸자

# 참고 자료
---
- [https://www.chrouki.com/posts/escape-sql-reserved-keywords-jpa-hibernate/](https://www.chrouki.com/posts/escape-sql-reserved-keywords-jpa-hibernate/)
- [popit.kr/가짜뉴스아웃-하이버네이트-데이터베이스-스키마/](popit.kr/가짜뉴스아웃-하이버네이트-데이터베이스-스키마/)
