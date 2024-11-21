---
title: DB 롤체인지 후 애플리케이션 헬스체크가 정상적으로 되지 않은 이슈 (feat. DB 커넥션 풀)
date: 2024-10-14 22:25:00 +0900
categories: [경험하기, 이슈 노트]
tags: [DBCP]
---

## 상황
* `L4/L7 스위치 --- WEB --- WAS(애플리케이션)`로 구성된 환경에서 2~3초 간격으로 `L4/L7 스위치`에서 헬스체크 신호를 보냄
* 애플리케이션은 헬스체크를 위해 DB에 `SELECT 1` 질의하게 되어있음
* 인프라팀 작업 이슈로 마스터 DB 서버 메모리 점유율이 너무 높아져 DB가 롤체인지 됨(약 12초 정도 소요)
* 롤체인지 되었는데도 애플리케이션 헬스체크는 down 상태 (DB 연결이 계속 안됨)
* 애플리케이션 재시작하니까 다시 정상 동작
* 이후에 DBA가 롤체인지 했을때 약 2초 정도 소요되었고, 헬스체크 잠깐 down 되었다가 다시 잘 올라옴

***"왜 롤체인지에 12초가 걸렸을 때는 DB가 정상화되었는데도 연결이 안됐고, 2초가 걸렸을 때는 다시 연결이 잘 됐을까 ?"***

## 에러 로그 살펴보기

### 롤체인지 12초

> 1, 2, 3 순서대로 나타난 후, 3번이 계속 반복됨

```
1. com.mysql.cj.exceptions.CJCommunicationsException: Communications link failure
2. java.sql.SQLNonTransientConnectionException: Could not create connection to database server. Attempted reconnect 3 times. Giving up.
3. java.sql.SQLNonTransientConnectionException: No operations allowed after connection closed.
```

### 롤체인지 2초

* `com.mysql.cj.jdbc.exceptions.CommunicationsException: Communications link failure`

## db 관련 설정 살펴보기

* db 접속 정보
> autoReconnect가 사용되고 있음

```
jdbc:mysql://{ip}:{port}/{db}?autoReconnect=true&useLocalSessionState=true
```

* 커넥션 풀([톰캣 DBCP](https://tomcat.apache.org/tomcat-7.0-doc/jdbc-pool.html#Introduction)) eviction 스레드 관련 설정

```java
dataSource.setTestOnBorrow(false);
dataSource.setTestOnReturn(false);
dataSource.setTestWhileIdle(false);
```

## 원인 파악하기
> 디버깅한 것을 바탕으로 간단하게 나타낸 그림 (틀릴 수 있음)

<img src = "/assets/img/after-role-change-issue-img1.png" alt="">

### 롤체인지 12초 때의 애플리케이션 실행 흐름

> 하나의 DB 커넥션 관점에서의 흐름

<img src = "/assets/img/after-role-change-issue-img2.png" alt="">

1. L4에서 헬스체크 요청 들어옴 -> DB에 질의 요청
2. 질의 실패 ( `autoReconnect` true이면, 다음 질의 때 질의 날리기 전 먼저 ping 검사하라는 변수(`needsPing`)를 true로 만듦)
  * ```Communications link failure``` 예외 발생 **(health check down)**
3. L4에서 헬스체크 요청 들어옴 -> DB에 질의 요청전 먼저 ping 검사 수행
4. ping 실패시 DB 세션에 다시 연결(reconnect)하는 과정 수행
5. (먼저 NativeSession close 후) reconnect 최대 재시도 횟수(default : 3)까지 실패
  * ```Could not create connection to database server. Attempted reconnect 3 times. Giving up.``` 예외 발생
6. L4에서 헬스체크 요청 들어옴 -> DB 질의를 위해 `PreparedStatement` 만드는 과정에서 커넥션에 매핑된 `NativeSession`이 닫혀있는지 먼저 확인
  * 5번에서 NativeSession close하고 재연결에도 실패했기 때문에 NativeSession은 닫혀있는 상태이므로, ```No operations allowed after connection closed.``` 예외 발생
  * 즉, NativeSession만 체크하고 예외 던지므로 DB가 롤체인지 되어 살아난 것과는 관계없이 질의를 할 수 없게됨

**※ 롤체인지 2초때는 3또는 4에서 성공한 것으로 보임**

### 실행 흐름 코드 참고

* 1\~4 : `com.mysql.cj.NativeSession#execSQL`
  <img src = "/assets/img/after-role-change-issue-img3.png" alt="">
* 5 : `com.mysql.cj.jdbc.ConnectionImpl#connectWithRetries`
  <img src = "/assets/img/after-role-change-issue-img4.png" alt="">
  <img src = "/assets/img/after-role-change-issue-img5.png" alt="">
* `com.mysql.cj.LocalizedErrorMessage.properties`
  <img src = "/assets/img/after-role-change-issue-img6.png" alt="">
* 6 : `com.mysql.cj.jdbc.ConnectionImpl#prepareStatement`,`com.mysql.cj.NativeSession#checkClosed`
  <img src = "/assets/img/after-role-change-issue-img7.png" alt="">
  <img src = "/assets/img/after-role-change-issue-img8.png" alt="">
* `com.mysql.cj.LocalizedErrorMessage.properties`
  <img src = "/assets/img/after-role-change-issue-img9.png" alt="">


## 조치

> 더 이상 유효하지 않은 DB 세션을 물고있는 커넥션을 커넥션 풀에서 정리

### 커넥션 풀 옵션 변경

* AS-IS

```java
dataSource.setTestOnBorrow(false);
dataSource.setTestOnReturn(false);
dataSource.setTestWhileIdle(false);
```

* TO-BE

> `PoolCleaner`(`org.apache.tomcat.jdbc.pool.ConnectionPool.PoolCleaner`)가 5초(`timeBetweenEvictionRunsMillis` 기본값)에 한번씩 idle 큐에 있는 커넥션들의 DB 세션 유효성 검사

```java
dataSource.setTestOnBorrow(false);
dataSource.setTestOnReturn(false);
dataSource.setTestWhileIdle(true);
dataSource.setValidationQuery("SELECT 1");
dataSource.setMinEvictableIdleTimeMillis(-1);
```

### 헬스체크 방식 변경
* DB에 질의하지 않고 애플리케이션이 실행되고 있는지 여부로 판단하도록 <br>(요청 자체가 못들어오는 것보다는 서버 에러라고 응답 주는게 낫다고 생각)

