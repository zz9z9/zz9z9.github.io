---
title: MySQL에서 시간,날짜 데이터를 저장할 때 반올림되는 현상 (1)
date: 2023-03-28 22:25:00 +0900
categories: [개발 일기]
tags: [MySQL]
---

## 상황
- 회사에서 판매하는 상품권의 등록만료일시 변경 요청을 받아 작업한 뒤 테스트하던 중 24년 12월 31일 23시 59분 59초로 만료일시를 세팅하려는데 실제 DB에는 25년 1월 1일 0시 0분 0초로 저장되는 현상 발견

## 기존 코드

``` java
import org.apache.commons.lang.time.DateUtils;

public void 상품권생성() {
    Date 등록만료일시 = DateUtils.setMilliseconds(DateUtils.setSeconds(DateUtils.setMinutes(DateUtils.setHours(DateUtils.addYears(new Date(), 5), 23), 59), 59), 0);

    상품권생성정보 info = new 상품권생성정보();
    info.setRegisterExpireYmdt(등록만료일시);

    중략 ...

    giftRepository.save(info);
}
```

## 변경 코드

* 가독성 고려 및 `java.util.Date` 클래스의 사용은 권장되지 않기 때문에  `LocalDateTime` 사용
    * [자바에서 다루는 날짜 클래스 관련 참고글](https://d2.naver.com/helloworld/645609)
* 객체 외부에서 인스턴스 변수의 값을 할당하는 것을 지양하고자, setter 메서드 대신 생성자 내에서 값 할당

``` java
public void 상품권생성() {
    상품권생성정보 info = new 상품권생성정보(param1, param2, ...);

    중략 ...

    giftRepository.save(info);
}
```

``` java
public 상품권생성정보(param1, param2, ...) {
		...
        this.registerExpireYmdt = getExpirationDate();
}

private Date getExpirationDate() {
    LocalDateTime 등록만료일시 = LocalDateTime.now()
                    .plusYears(1)
                    .withMonth(12)
                    .withDayOfMonth(31)
                    .withHour(23)
                    .withMinute(59)
                    .withSecond(59);

    // LocalDateTime -> Date형으로 변환
    Instant instant = 등록만료일시.atZone(ZoneId.systemDefault()).toInstant();
    return Date.from(instant);
}
```

> 상품권생성정보의 `registerExpireYmdt`(인스턴스 변수) 자료형 자체를 `LocalDateTime`으로 변경하고 싶었으나, 사용되고있는 곳이 많아 이 부분까지 수정하지는 못함


## 원인 파악해보기

### 1\. 테이블 스키마 확인

* DB : MySQL 5.7.35
* 등록만료일시 컬럼 자료형 : `DATETIME`

### 2\. 쿼리 로그 확인

* 상품권생성정보에 대한 INSERT 쿼리에 세팅되는 등록만료일시: `2024-12-31 23:59:59.582`

### 3\. MySQL DATETIME 관련 공식 문서 확인

* `TIME`, `DATETIME`, `TIMESTAMP` 자료형에 대해서 'fractional seconds'(분수 초 = 소수점 초?)를 지원한다.
* 최대 마이크로초(소수점 6자리)까지 지원
* **컬럼 자료형에 정의된 소수점 자릿수보다 실제 저장하려는 시간의 소수점 자릿수가 더 크면, 초과되는 부분에서 반올림된다.**
* 예시 : `2018-09-08 17:51:04.777` 저장
    * `DATETIME(2)` : 2018-09-08 17:51:04.78 -> 소수점 세번째 자리에서 반올림됨
    * `DATETIME` : 2018-09-08 17:51:05 -> 소수점 첫번쨰 자리에서 반올림됨

### 이슈 원인

* 등록만료일시를 저장하는 컬럼의 경우 소수점 초를 정의하지 않은 `DATETIME`이다. 따라서, 저장하려는 시간에 소수점이 붙으면 소수점 첫번째 자리에서 반올림된다.
* `LocalDateTime.now()`의 경우 현재 시각을 소수점 3자리까지 표현한다. (ex : `2024-12-31 23:59:59.582`)
    * DB에 `2024-12-31 23:59:59`로 저장된 경우 : `LocalDateTime.now()`가 호출된 시점에 소수점 초가 0.5보다 작았다.
    * DB에 `2025-01-01 00:00:00`로 저장된 경우 : `LocalDateTime.now()`가 호출된 시점에 소수점 초가 0.5 이상이었다.
    * `LocalDateTime`은 소수점 9자리까지 표현 가능

※ 참고

* 이슈의 원인이었던 'fractional seconds'는 MySQL 5.6.4버전부터 지원되는 기능이다.
* [5.7버전 공식문서](https://dev.mysql.com/doc/refman/5.7/en/fractional-seconds.html)
* [8 버전 공식문서](https://dev.mysql.com/doc/refman/8.0/en/fractional-seconds.html)

## 생각해본 해결 방안

1. 쿼리에 세팅되는 등록만료일시의 소수점 초 부분을 0으로 만들기(소수점 부분 제거하기)
2. ~~초 단위까지 반올림 되지 않도록 datetime 자료형을 datetime(n)으로 재정의하기~~
    -  datetime(3)이어도 저장되는 시간이 23:59:59.9995 이런경우 결국 초단위까지 반올림된다.

### 쿼리에 세팅되는 등록만료일시의 소수점 부분 0으로 만들기

* ver1

``` java
LocalDateTime 등록만료일시 = LocalDateTime.now()
                .plusYears(1)
                .withMonth(12)
                .withDayOfMonth(31)
                .withHour(23)
                .withMinute(59)
                .withSecond(59)
                .withNano(0); // 추가
```

* ver2

``` java
int nextYear = LocalDateTime.now().getYear() + 1;
LocalDateTime 등록만료일시 = LocalDateTime.of(nextYear, 12, 31, 23, 59, 59); // of 메서드를 타고 들어가다보면 결국 nanoSecond를 0으로 세팅하는 부분이 있음
```

* INSERT 쿼리 로그 확인
    * 변경 전 : `2024-12-31 23:59:59.582`
    * 변경 후 :`2024-12-31 23:59:59`
* nano초를 일부러 0으로 세팅했다는 것이 명시적으로 좀 더 잘 드러나는 것 같아 ver1 선택

> 이로써 생각보다 간단히 이슈를 해결할 수 있었다.
> 하지만, 한 가지 의문이 들었던 것은 INSERT 쿼리에 세팅되기 전 등록만료일시는 (jdbc에서 다루는) **java.sql.Timestamp** 타입이될텐데
> LocalDateTime의 nano초를 0으로 세팅한 것이 결과적으로 어떻게 Timestamp를 거쳐 쿼리 파라미터의 소수점 초 부분을 없앨 수 있는지였다.
> 그래서 MyBatis와 JDBC 드라이버(mysql-connector-java)가 내부적으로 어떤식으로 값을 변환하고 있는지 디버거를 통해 따라가보았다.
> 해당 글은 다음 포스팅을 통해 살펴보자.

## 다음 포스팅
