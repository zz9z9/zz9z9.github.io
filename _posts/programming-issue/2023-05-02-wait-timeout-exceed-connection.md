---
title:  wait_timeout을 초과한 커넥션을 사용해서 겪은 이슈 (The last packet successfully received from the server was ... milliseconds ago)
date: 2023-05-02 10:25:00 +0900
categories: [개발 일기]
tags: [Connection Pool, MySQL]
---

## 상황
- 최근 배치 애플리케이션의 커넥션 풀 관련 설정을 변경한 후 MMS 발송하는 job에서 아래와 같은 에러 발생
```
Cause: com.mysql.jdbc.exceptions.jdbc4.CommunicationsException:
The last packet successfully received from the server was 104,983,345 milliseconds ago.
The last packet sent successfully to the server was 104,983,347 milliseconds ago.
is longer than the server configured value of 'wait_timeout'.
```

## 커넥션 풀 관련 설정
- 변경 전
```
  initial-size: 0 // 커넥션 풀 최초 사이즈
  max-active: 8   // 최대로 활성화할 커넥션 갯수
  max-idle: 8     // 커넥션 풀에 유지할 최대 커넥션 갯수
  min-idle: 0     // 커넥션 풀에 유지할 최소 커넥션 갯수
  max-wait : 3초  // DB 커넥션 얻기위해 대기하는 최대 시간
```

- 변경 후
```
  initial-size: 20 // 커넥션 풀 최초 사이즈
  max-active: 20   // 최대로 활성화할 커넥션 갯수
  max-idle: 20    // 커넥션 풀에 유지할 최대 커넥션 갯수
  min-idle: 20     // 커넥션 풀에 유지할 최소 커넥션 갯수
  max-wait : 5초  // DB 커넥션 얻기위해 대기하는 최대 시간
```


## 에러 원인 찾기
- 출처 : [https://kakaocommerce.tistory.com/45](https://kakaocommerce.tistory.com/45)
```
MySQL 서버 입장에서 JDBC 커넥션이 Idle인 상태로 wait_timeout(default 28800초) 이상 사용되지 않을 경우
해당 커넥션을 close 하여 할당된 리소스를 회수하게 된다.
이런 경우 TCP 레벨에서 해당 socket이 정리가 되더라도 JDBC 드라이버나 커넥션 풀에서는 close 여부를 바로 알 수 없고
해당 커넥션을 사용하려고 시도 할 때에서야 비로소 커넥션에 문제가 있는 것을 알게 된다.
이런 상황일 경우 최근에 성공한 통신이 XXX,XXX milliseonds 이전이라고 위와 같은 에러 메시지를 출력하게 된다.
```

![KakaoTalk_Photo_2023-08-24-23-17-31 001](https://github.com/zz9z9/zz9z9.github.io/assets/64415489/2937d57c-88a2-412f-9c9b-b20a01a572e0)

**※ 참고**
- CUBRID는 자체적으로 커넥션을 관리하고 자동으로 다시 연결하도록 구현되어있다고 한다. (출처 : [https://d2.naver.com/helloworld/5102792](https://d2.naver.com/helloworld/5102792))

## 에러 재현해보기
- 검증해보고 싶은 부분
  - idle 상태인 커넥션중 `wait_timeout` 지나면 mysql 서버에서 해당 커넥션 만큼의 세션(스레드) 갯수가 감소한 것을 확인할 수 있다.
  - 닫힌 세션에 맵핑된 커넥션으로 질의 요청하는 경우 위 에러가 발생한다.

- 검증 코드
![KakaoTalk_Photo_2023-08-24-23-17-31 002](https://github.com/zz9z9/zz9z9.github.io/assets/64415489/52d4bdb0-3e90-45fe-bcbf-da0650a37f29)

- 검증 과정
  - 코드 실행 전 mysql workbench에서 확인한 현재 열려있는 커넥션 갯수 (`show status where variable_name = 'Threads_connected';`)
    - ![KakaoTalk_Photo_2023-08-24-23-17-31 003](https://github.com/zz9z9/zz9z9.github.io/assets/64415489/1f240e48-9337-4591-bf75-8ca3c5d82347)
  - 커넥션 연결 (두 개의 커넥션 중 하나의 커넥션에만 wait_timeout 5초 설정 : ①, 나머지 하나는 default 값인 28800초)
    - ![KakaoTalk_Photo_2023-08-24-23-17-31 004](https://github.com/zz9z9/zz9z9.github.io/assets/64415489/0bb4e418-3b84-4d5f-b2da-0df65e0fda18)
  - `wait_timeout` 이상 대기 (②)
    - ![KakaoTalk_Photo_2023-08-24-23-17-31 005](https://github.com/zz9z9/zz9z9.github.io/assets/64415489/72d4019d-0f25-4142-8374-dbfda759341e)
    - **"idle 상태인 커넥션중 `wait_timeout` 지나면 mysql 서버에서 해당 커넥션 만큼의 세션(스레드) 갯수가 감소한 것을 확인할 수 있다."** 에 대해 검증 완료
  - mysql 서버에서 닫힌 커넥션에 질의할시 동일한 에러 발생(③)
    - **"닫힌 세션에 맵핑된 커넥션으로 질의 요청하는 경우 위 에러가 발생한다."** 에 대해 검증 완료
    ```
    Exception in thread "main" com.mysql.cj.jdbc.exceptions.CommunicationsException:
    The last packet successfully received from the server was 107,054 milliseconds ago. (중략 ...)
    ```


### 의문점
> MMS 발송 job은 5분마다 돌면서 발송 대상이 있는지 조회한다. 그리고 발송 job 이외에도 주기적으로 도는 다른 job들도 있기 때문에 커넥션 풀에 있는 커넥션들이 주기적으로 사용될 것 같은데 왜 커넥션이 끊어진걸까 ?

## 커넥션 풀 내부 살펴보기
> tomcat-jdbc-7.0.56

- `org.apache.tomcat.jdbc.pool.ConnectionPool`
![KakaoTalk_Photo_2023-08-24-23-32-29](https://github.com/zz9z9/zz9z9.github.io/assets/64415489/09089ac7-c614-4733-bc85-39f3d738780a)

### 커넥션 풀 초기화
- `BlockingQueue` 구현 클래스 할당
![KakaoTalk_Photo_2023-08-24-23-33-09](https://github.com/zz9z9/zz9z9.github.io/assets/64415489/9c4a350b-cfb0-40b4-897e-9f40b5bdbd91)

  - idle 커넥션 큐는 `FairBlockingQueue`(https://tomcat.apache.org/tomcat-7.0-doc/api/org/apache/tomcat/jdbc/pool/FairBlockingQueue.html)

- 실제 커넥션 할당 (busy 큐에 들어가게됨)
![KakaoTalk_Photo_2023-08-24-23-33-16](https://github.com/zz9z9/zz9z9.github.io/assets/64415489/1bf3d3a1-aeb6-465b-89e8-50fcfdeef6df)

- busy 큐 -> idle 큐로 이동
![KakaoTalk_Photo_2023-08-24-23-35-11](https://github.com/zz9z9/zz9z9.github.io/assets/64415489/d5af625c-9eb8-4e60-9667-decf58ac630f)


### 커넥션 가져오기
- idle 큐의 맨 앞에 있는 커넥션 가져옴
![KakaoTalk_Photo_2023-08-24-23-35-18](https://github.com/zz9z9/zz9z9.github.io/assets/64415489/6b24ce08-018e-4dd4-9a62-6bd821462df2)


### 커넥션 반납
- idle 큐의 `offer` 메서드 호출
![KakaoTalk_Photo_2023-08-24-23-36-38](https://github.com/zz9z9/zz9z9.github.io/assets/64415489/83279d85-cf05-46ae-a3b7-fc2a0d137dbe)

- 반납된 커넥션이 맨 앞에 들어가는 것을 볼 수 있다.
![KakaoTalk_Photo_2023-08-24-23-36-44](https://github.com/zz9z9/zz9z9.github.io/assets/64415489/e7b9a2e7-59f7-4e6c-b759-5097e0ce67b8)

## 의문점 해결하기
> MMS 발송 job은 5분마다 돌면서 발송 대상이 있는지 조회한다. 그리고 발송 job 이외에도 주기적으로 도는 다른 job들도 있기 때문에 커넥션 풀에 있는 커넥션들이 주기적으로 사용될 것 같은데 왜 커넥션이 끊어진걸까 ?

- MMS 발송 로직
  - 발송 대상 조회(커넥션1) -> 발송 & 발송 관련 정보 업데이트(비동기 호출, 커넥션2..n)

- 사용되는 커넥션 갯수 추정해보기
  - idle 큐에 보관되는 커넥션 중 MMS 발송 건이 없는 경우엔 맨 앞 커넥션 하나 또는 있더라도 맨 앞부터 n개의 커넥션이 사용될 것 (동시 발송 건수가 많지 않으면 n의 크기가 작을 것.)
  - MMS 발송 job 이외에 커넥션을 여러 개 사용하는 job들은 거의 없고 또한 동시에 job들이 도는 경우도 많지 않기 때문에 n개의 커넥션이 사용된다 하더라도 n의 크기는 작을 것이다.

![KakaoTalk_Photo_2023-08-24-23-36-51](https://github.com/zz9z9/zz9z9.github.io/assets/64415489/59b7c5e9-fdc7-407d-b344-ebb374bb87e8)

- 위에서 살펴보았듯이 커넥션 반납시 큐의 맨 뒤가 아닌 맨 앞에 추가되기 때문에, 사용되는 커넥션만 계속 사용될 것
- **결과적으로, 앞에 몇 개의 커넥션만 계속 사용되다가 MMS 발송건이 여러 건인 경우 8시간(`wait_timeout`)이상 사용되지 않았던 뒤쪽의 커넥션(이미 세션이 닫힌)까지 사용하기 때문에 에러가 발생했던 것**

## 문제 해결하기

### 1. 커넥션 풀에 idle 커넥션 갯수 0개로 유지

- 커넥션 정리는 `ConnectionPool.PoolCleaner`에서 담당 (Evictor 스레드)

![KakaoTalk_Photo_2023-08-24-23-36-57](https://github.com/zz9z9/zz9z9.github.io/assets/64415489/7f763431-c90d-4ef1-a3fd-f97effcc78cf)

- **사실상 커넥션 풀 사용하는 이점이 사라지는 것(?)**
- 트래픽 많지 않아서 현재로서 운영상 이슈는 없음


### 2. PoolCleaner에서 주기적으로 커넥션 유효성 체크하도록
- `validationQuery`, `timeBetweenEvictionRunsMillis`, `testWhileIdle` 등의 속성 활용하여 주기적으로 커넥션 유효성 검사

- 유의사항 (출처 : [https://d2.naver.com/helloworld/5102792]([https://d2.naver.com/helloworld/5102792])) - commons dbcp 1.x 기준
  - Evictor 스레드는 동작 시에 커넥션 풀에 잠금(lock)을 걸고 동작하기 때문에 너무 자주 실행하면 서비스 실행에 부담을 줄 수 있다.
  - 또한 numTestsPerEvictionRun 값을 크게 설정하면 Evictor 스레드가 검사해야 하는 커넥션 개수가 많아져 잠금 상태에 있는 시간이 길어지므로 역시 서비스 실행에 부담을 줄 수 있다.
  - 게다가 커넥션 유효성 검사를 위한 테스트 옵션(testOnBorrow, testOnReturn, testWhileIdle)을 어떻게 설정하느냐에 따라 애플리케이션의 안정성과 DBMS의 부하가 달라질 수 있다. 그러므로 Evictor 스레드와 테스트 옵션을 사용할 때는 데이터베이스 관리자와 상의해서 사용하는 DBMS에 최적화될 수 있는 옵션으로 설정해야 한다.


### ~~3. autoReconnect ?~~

- 동작 방식
  - 커넥션이 끊어진 경우 예외를 발생시키고 해당 트랜잭션 종료시킴.
  - 이후 새로운 트랜잭션에서 해당 커넥션 사용하는 경우 다시 연결 시도.
- 따라서, `autoReconnect` 속성이 `true`이더라도 커넥션이 끊겨서 발생하는 최초의 에러를 막을수는 없다.

- [공식 문서](https://dev.mysql.com/doc/connector-j/8.0/en/connector-j-connp-props-high-availability-and-clustering.html#cj-conn-prop_autoReconnect) 에서는 데이터 일관성, 세션 상태 등의 이유로 사용하는 것을 추천하지 않는다.

