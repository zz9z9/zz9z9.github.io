---
title: MySQL에서 시간,날짜 데이터를 저장할 때 반올림되는 현상 (2)
date: 2023-03-29 22:25:00 +0900
categories: [경험하기, 이슈 노트]
tags: [MySQL, MyBatis]
---

## 상황
- [이전 포스팅](https://zz9z9.github.io/posts/mysql-round-up-part1/) 에서 MySQL 반올림 현상으로 인해 겪었던 이슈를 살펴보았다. 이번 포스팅에서는 해당 이슈를 해결하면서 궁금했던 소수점 초가 제거되기까지의 자료형 변환 과정을 들여다보자.

## 소수점 초가 제거되기까지의 과정 살펴보기

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
                    .withSecond(59)
                    .withNano(0);

    // LocalDateTime -> Date형으로 변환
    Instant instant = 등록만료일시.atZone(ZoneId.systemDefault()).toInstant();
    return Date.from(instant);
}
```
![KakaoTalk_Photo_2023-08-06-15-07-20 002](https://github.com/zz9z9/zz9z9.github.io/assets/64415489/4aeeb742-4d37-4241-9ce5-55066e61cc82)

* 실제 DB에 쿼리를 날리기 위해 JDBC 레벨에서 다루는 날짜 관련 자료형은 `java.sql.Timestamp`
* 따라서 만료일시가 쿼리에 세팅되기까지 자료형 변환은 `java.time.LocalDateTime → java.util.Date → java.sql.Timestamp`의 과정을 거침
* `LocalDateTime → Date`로의 변환은 `getExpirationDate`에 있지만 `Date → Timestamp`로의 변환은 MyBatis에서 해준다.

※ 참고

* MySQL 8.0부터는 JDBC 드라이버 이름이 mysql-connector-java -> mysql-connector-j로 변경됨 ([https://dev.mysql.com/doc/relnotes/connector-j/8.0/en/news-8-0-31.html](https://dev.mysql.com/doc/relnotes/connector-j/8.0/en/news-8-0-31.html)


### 1\. java\.time\.LocalDateTime → java\.util\.Date 변환

``` java
Instant instant = 등록만료일시.atZone(ZoneId.systemDefault()).toInstant();
return Date.from(instant);
```

* `Instant instant = 등록만료일시.atZone(ZoneId.systemDefault()).toInstant();`
    * LocalDateTime을 Instant로 변환
    * [Instant](https://docs.oracle.com/javase/8/docs/api/java/time/Instant.html) 는 현재 순간(시각)을 seconds와 nanos로 표현함
        * seconds : 1970-01-01T00:00:00Z부터 현재까지 경과한 시간을 초로 나타낸 것.
            * 참고 : [Epoch Time](https://ko.wikipedia.org/wiki/%EC%9C%A0%EB%8B%89%EC%8A%A4_%EC%8B%9C%EA%B0%84)
        * nanos : 현재 시간을 나노초 정밀도(소수점 9자리까지)로 표현
* `Date.from(instant)`
    * `java.util.Date`의 정밀도는 밀리세컨드

``` java
 public static Date from(Instant instant) {
        try {
            return new Date(instant.toEpochMilli());
        } catch (ArithmeticException ex) {
            throw new IllegalArgumentException(ex);
        }
    }
```

* `toEpochMilli ()`
    * 1970-01-01T00:00:00Z부터의 epoch time을 밀리초 단위로 변환
    * 즉, Instant의 정밀도는 나노초이지만 Date의 정밀도는 밀리초이기 때문에`toEpochMilli()`로 변환.

``` java
    public long toEpochMilli() {
        if (seconds < 0 && nanos > 0) {
            long millis = Math.multiplyExact(seconds+1, 1000);
            long adjustment = nanos / 1000_000 - 1000;
            return Math.addExact(millis, adjustment);
        } else {
            long millis = Math.multiplyExact(seconds, 1000);
            return Math.addExact(millis, nanos / 1000_000);
        }
    }
```

* 요약
    * `LocalDateTime`, `Instant`는 나노초 정밀도(`2024-12-31 23:59:59.123456789`) 까지 표현할 수 있고 `Date`는 밀리초 정밀도(`2024-12-31 23:59:59.123`) 까지 표현할 수 있다.
    * LocalDateTime의 nano가 0이면 Date가 표현할 수 있는 밀리초 부분도 0이 된다.

### 2\. java\.util\.Date → java\.sql\.Timestamp 변환

* `org.apache.ibatis.type.DateTypeHandler`가 중간에서 변환해줌
![image](https://user-images.githubusercontent.com/64415489/228099550-9f8fb5df-a3b4-413a-8bce-8fc357bda40b.png)
* `parameter.getTime()`

``` java
// java.util.Date
    public long getTime() {
        return getTimeImpl();
    }

    private final long getTimeImpl() {
        if (cdate != null && !cdate.isNormalized()) {
            normalize();
        }
        return fastTime;
    }
```

* `new Timestamp(parameter.getTime())` \- \([java.sql.Timestamp](https://docs.oracle.com/javase/8/docs/api/java/sql/Timestamp.html) 는 나노초 정밀도를 갖는다.)

``` java
// java.sql.Timestamp
    public Timestamp(long time) {
        super((time/1000)*1000);
        nanos = (int)((time%1000) * 1000000);
        if (nanos < 0) {
            nanos = 1000000000 + nanos;
            super.setTime(((time/1000)-1)*1000);
        }
    }
```

> 정확히 이게 어떤 동작을 하는 것인지 파악하기가 어려워서 코드 실행결과를 확인해보았다.

* 예시
    * Date : 2024년 12월 31일 23시 59분 59.123초
        * Date.getTime() : 1735657199123            // Epoch Time (밀리초 단위까지 표현)
        * new Timestamp(Date.getTime())
            * Timestamp.getTime() : 1735657199123 // Epoch Time (밀리초 단위까지 표현)
            * Timestamp.getNanos() : 123000000       // 나노초 정밀도까지 표현 (밀리초 단위까지만 갖는 Date로부터 변환되었기 때문에 밀리초 이후로는 0)
    * Date : 2024년 12월 31일 23시 59분 59초.000초
        * Date.getTime() : 1735657199000
        * new Timestamp(Date.getTime())
            * Timestamp.getTime() : 1735657199000
            * Timestamp.getNanos() : 0
* `LocalDateTime → Date → Timestamp` 변환과정을 요약하면 **"LocalDateTime에서의 nano초가 0이면 Date의 밀리초가 0이되고, 이를 기반으로 생성한 Timestamp의 nano초 또한 0이다."**

### 3\. 쿼리문에 값 세팅

> 로그에 찍혔던 `2024-12-31 23:59:59`, 즉 쿼리문에 실제로 세팅되는 값이 어떤식으로 만들어지는 것인지 확인해보기.

* 2번에서 살펴본 `org.apache.ibatis.type.DateTypeHandler`에서 `ps.setTimestamp`를 타고 들어가다보면 아래 코드가 나옴
* `com.mysql.jdbc.PreparedStatement.setTimestampInternal` 에서 **Timestamp의 nanos부분이 0인지 아닌지에 따라 소수점 초가 붙을지 안붙을지 결정된다.**
![KakaoTalk_Photo_2023-08-06-15-07-20 001](https://github.com/zz9z9/zz9z9.github.io/assets/64415489/40c72217-e749-4f08-b1a6-2fb49b2f3130)
* 5.6.4버전부터 fractional second 기능이 지원되는 것을 코드 레벨에서 확인할 수도 있다.
![image](https://user-images.githubusercontent.com/64415489/227974160-2a34ee58-a9fd-4a85-8cb3-62910af528fc.png)

## 정리
* 컴퓨터에서 시간을 다루기 위해 Epoch Time이란 개념을 사용한다.
* Epoch Time과 더불어 시간을 특정 정밀도 단위까지 표현할 수 있다.
    * LocalDateTime와 Timestamp의 정밀도는 나노초, Date는 밀리초이다.
* Timestamp의 nanos가 0보다 크면 MySQL 5.6.4버전 이상부터는 소수점 초가 붙어서 쿼리 파라미터에 세팅된다.
    * LocalDateTime의 nano초 부분이 0이면 결과적으로 Timestamp의 nano초 부분도 0이되었다.
    * `DATETIME`과 같은 날짜/시간 자료형에 정의된 소수점 자릿수를 초과하는 부분은 반올림된다.

## 이전 포스팅
- [MySQL에서 시간,날짜 데이터를 저장할 때 반올림되는 현상 (1)](https://zz9z9.github.io/posts/mysql-round-up-part1/)
