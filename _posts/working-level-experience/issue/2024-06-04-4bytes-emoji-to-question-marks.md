---
title: MySQL에서 4bytes 이모지가 물음표로 저장되는 이슈
date: 2024-06-04 22:25:00 +0900
categories: [경험하기, 이슈 노트]
tags: [MySQL]
---

## 상황

> MySQL DB에 🎃이모지 저장시 '????'로 저장되었고, connection properties(jdbc url에 쿼리 스트링으로 붙는 값들)를 변경해가며 테스트 해 본 결과는 다음과 같았다.

| connection properties                                    | 현상 | mysql-connector-j 버전 | mysql 버전 |
|----------------------------------------------------------| --- | -------------------- | -------- |
| `characterEncoding=UTF-8`                                | 이모지 저장 안됨 (에러 발생) | 5.1.12 | 8.0.35 |
| `characterEncoding=UTF-8&connectionCollation=utf8mb4_bin` | 이모지가 `????`로 저장됨 | 5.1.12 | 8.0.35 |
| `characterEncoding=UTF-8&connectionCollation=utf8mb4_bin` | 이모지 저장 제대로 됨 | 8.0.28 | 8.0.35 |

※ 들어가기 전 참고 : 유니코드는 문자를 매핑된 **코드 포인트**로 관리

<img src = "/assets/img/emoji-issue-2.png" alt="">

> 출처 : [https://www.iemoji.com/view/emoji/256/smileys-people/jack-o-lantern](https://www.iemoji.com/view/emoji/256/smileys-people/jack-o-lantern)

## MySQL에 문자가 저장되기까지의 과정

> [공식 문서](https://dev.mysql.com/doc/refman/8.4/en/charset-connection.html) 및 chat gpt 답변 참고하여 추측 <br>
> 다음 시스템 변수가 중요 : [character_set_client](https://dev.mysql.com/doc/refman/8.4/en/server-system-variables.html#sysvar_character_set_client), [character_set_connection](https://dev.mysql.com/doc/refman/8.4/en/server-system-variables.html#sysvar_character_set_connection)

1. 애플리케이션(클라이언트)에서 쿼리문 보냄
2. 서버에서는 수신한 쿼리문을 `character_set_client`에 정의된 방식으로 디코딩하여 유니코드 코드 포인트로 만듦
3. 만들어진 코드 포인트를 `character_set_connection`에 정의된 방식으로 인코딩하여 최종 값 저장

<img src = "/assets/img/emoji-issue-3.jpg" alt="">

- 내용 추가 : [포스팅1](https://blog.naver.com/didim365_/220311456806)과 [포스팅2](https://intomysql.blogspot.com/2010/12/mysql-character-set.html)를 보니 `character_set_client`와 `character_set_connection`이 동일한 경우에는 변환이 일어나지 않는다고 한다. 즉, 그림에서 아래 흐름은 틀림

### 이모지 저장 실패 흐름

* MySQL은 질의문이 최대 3바이트 UTF-8로 인코딩 됐다고 생각(`character_set_client=utf8 (utf8mb3)`)
* utf8mb3은 코드 포인트 `U+0000 ~ U+FFFF`(BMP 문자)의 유니코드 문자만 지원 (최대 3바이트) - [공식문서 참고](https://dev.mysql.com/doc/refman/8.4/en/charset-unicode-utf8mb3.html)
* 하지만, 4바이트 문자는 일반적으로 유니코드 코드 포인트 `U+10000 ~ U+10FFFF`에 해당 (🎃 --> U+1F383)
* 따라서, `character_set_client=utf8 (utf8mb3)`인 경우 최대 3바이트 문자만 처리할 수 있으므로 4바이트 문자를 유니코드 코드 포인트로 디코딩하지 못함
* 이 실패로 인해 오류가 발생하거나 지원되지 않는 문자가 종종 `????`로 대체됨

※ 참고

* [utf8mb3은 deprecated됨](https://dev.mysql.com/doc/refman/8.4/en/charset-unicode-utf8.html)
* 위에서 언급한 [공식문서](https://dev.mysql.com/doc/refman/8.4/en/charset-unicode-utf8mb3.html)에도 `UTF-8 데이터를 사용하지만 supplementary character(이모지 같은 BMP이외의 문자)에 대한 지원이 필요한 애플리케이션은 utf8mb3 대신 utf8mb4를 사용해야 합니다.`라고 되어있음

## 상황별 character_set_client, character_set_connection 살펴보기
> MySQL 버전은 `8.0.35`로 동일

| connection properties                                    |  mysql-connector-j 버전 | mysql 버전 | character_set_client | character_set_connection |
|----------------------------------------------------------| ------------------- | -------- |----------------------| --------- |
| `characterEncoding=UTF-8`                                |  5.1.12 | 8.0.35 | utf8   | utf8 |
| `characterEncoding=UTF-8&connectionCollation=utf8mb4_bin` | 5.1.12 | 8.0.35 | utf8   | utf8mb4 |
| `별도 세팅 없음`                                             | 8.0.28 | 8.0.35 | utf8mb4 | utf8mb4 |
| `characterEncoding=UTF-8`                                |  8.0.28 | 8.0.35 | utf8mb4   | utf8mb4 |
| `characterEncoding=UTF-8&connectionCollation=utf8mb4_bin` | 8.0.28 | 8.0.35 | utf8mb4 | utf8mb4 |

mysql-connector-j 5.1.12 버전에서는 `character_set_client`가 `utf8` 즉, `utf8mb3`이라 최대 3바이트까지 밖에 지원이 안돼서
위 실패 흐름에서 살펴본 것처럼 4바이트 이모지가 제대로 저장되지 않았던 것


※ character_set_client, character_set_connection 확인 쿼리
```sql
SELECT * FROM performance_schema.session_variables
WHERE VARIABLE_NAME IN ('character_set_client', 'character_set_connection');
```

## character\_set\_client과 character\_set\_connection 값에 영향을 미치는 요소

> [https://dev.mysql.com/doc/connector-j/en/connector-j-connp-props-session.html](https://dev.mysql.com/doc/connector-j/en/connector-j-connp-props-session.html)

### characterEncoding

* `character_set_client` 및 `character_set_connection`을 지정된 Java 문자 인코딩에 대해 MySQL이 지원하는 기본 문자 집합으로 설정
   * `characterEncoding=UTF-8` (java) => `utf8` or `utf8mb4` (mysql)
   * `characterEncoding=ISO-8859-1` (java) => `latin1` (mysql)
* `collation_connection`을 이 문자 집합의 기본 collation으로 설정

※ 참고 (문자 집합별 기본 collation 확인)

> SHOW CHARACTER SET

### connectionCollation

* 세션 시스템 변수 `collation_connection`을 지정된 collation으로 설정하고 `character_set_client` 및 `character_set_connection`을 상응하는 문자 집합으로 설정
* 이 속성은 `characterEncoding`이 구성되지 않았거나 collation과 호환되지 않는 문자 집합으로 구성된 경우에만 이 collation이 속한 기본 문자 집합으로 `characterEncoding` 값을 재정의

**※ 이 케이스 다시 생각해보기**

| connection properties                                    |  mysql-connector-j 버전 | mysql 버전 | character_set_client | character_set_connection |
|----------------------------------------------------------| ------------------- | -------- |----------------------| --------- |
| `characterEncoding=UTF-8&connectionCollation=utf8mb4_bin` | 5.1.12 | 8.0.35 | utf8   | utf8mb4 |

* `connectionCollation=utf8mb4_bin`에 상응하는 문자 집합이면 `character_set_client`도 `utf8mb4`이 되어야하지 않나?
* **[connector/j 5.1.13 부터 변경된 부분](https://downloads.mysql.com/docs/connector-j-5.1-relnotes-en.a4.pdf)**
    * **(5.1.12 버전까지는) Connector/J는 mysql 서버 5.5.2 이상에 대해 `utf8mb4`를 지원하지 않았음**
    * 5.1.13 버전부터 Connector/J는 `character_set_server=utf8mb4`로 구성된 서버를 자동 감지
    * 또는, `characterEncoding=UTF-8`을 사용하여 전달된 Java 인코딩 utf-8을 `utf8mb4`로 처리

### characterEncoding, connectionCollation 둘 다 설정 안되어있는 경우

* Connector/J 8.0.25 이하 : 서버의 기본 문자 집합을 사용(`character_set_server` 값)
* Connector/J 8.0.26 이상 : `utf8mb4` 사용
