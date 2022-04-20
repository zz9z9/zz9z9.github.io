---
title: JDBC 알아보기
date: 2022-04-19 00:29:00 +0900
categories: [Java]
tags: [JDBC]
---

# JDBC란?
> [공식 문서](https://docs.oracle.com/javase/8/docs/technotes/guides/jdbc/)에서는 다음과 같이 설명한다. <br>
> <q>JDBC(Java Database Connectivity) API는 Java에서 범용 데이터 액세스를 제공한다.
> 즉, JDBC API를 사용하면 관계형 데이터베이스, 스프레드시트 및 플랫 파일에 이르기까지 거의 모든 데이터 소스에 액세스할 수 있다.</q>

- 한 마디로, JDBC는 데이터소스(특히 데이터베이스)에 연결하여 쿼리를 실행하기 위한 API이다.
- JDBC API는 두 개의 패키지로 구성된다.
  - `java.sql`
  - `javax.sql`

## JDBC가 나오게 된 배경
- 모든 데이터베이스에는 해당 데이터베이스와 상호 작용하는 프로그램을 작성하기 위해 필요한 자체 API가 있다.
  - 따라서 둘 이상의 공급업체에서 제공하는 데이터베이스와 상호 작용할 수 있는 코드를 작성하는 것은 어려운 과제다.
- 마이크로소프트의 ODBC API와 같은 데이터베이스 간 API는 존재했지만, 이들은 특정 플랫폼에 국한되는 경향이 있었다.

## JDBC 사용시 이점
- JDBC는 데이터베이스와 Java 사이에 플랫폼 중립적인 인터페이스를 만들기 위함이다.
  - 즉, JDBC API는 쿼리 실행, 결과 처리 및 구성 정보 결정을 포함하여 주요 데이터베이스 기능을 캡슐화하는 인터페이스 세트를 정의한다.
  - 따라서, JDBC를 사용하면 표준 데이터베이스 액세스 기능과 SQL의 특정 하위 집합인 SQL-92를 사용할 수 있다.

- 데이터베이스 공급업체 또는 타사 개발자가 특정 데이터베이스 시스템에 대해 이러한 인터페이스를 구현하는 클래스 집합인 JDBC 드라이버를 작성한다.
  - 결과적으로, 자바 애플리케이션은 여러 JDBC 드라이버를 바꿔가면서 사용할 수 있다.

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/164041122-e31049d5-d010-4959-8db1-ff20be9bc6b2.png"/>
  <figcaption align="center">출처 : <a href="https://flylib.com/books/en/2.177.1.75/1/">https://flylib.com/books/en/2.177.1.75/1/</a></figcaption>
</figure>

## 코드 레벨에서 살펴보기
- 위 그림을 좀 더 간략하게 만들면 아래와 같을 것이다.

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/164047428-96f035ef-2853-4fe2-bc5c-778a0bd5634e.png"/>
  <figcaption align="center">출처 : <a href="https://javapapers.com/jdbc/jdbc-introduction/">https://javapapers.com/jdbc/jdbc-introduction/</a></figcaption>
</figure>

- 예를 들어, 자바 프로그램을 MySQL DB와 연동하기 위해서는 MySQL을 위한 JDBC 드라이버가 필요할 것이며, 아래와 같이 (gradle)프로젝트에 해당 드라이버 의존성을 추가해 줄 수 있다.
  - `implementation 'mysql:mysql-connector-java:8.0.28'`

- DB와 연결하는 다음 코드를 살펴보자.

```java
Connection con = DriverManager.getConnection("jdbc:mysql://localhost:3306/dbname", "user", "pw")`
```

- `DriverManager`를 통해 얻어오는 `Connection`의 실제 구현체는 `com.mysql.cj.jdbc` 패키지(`mysql-connector-java` 라이브러리에 있는)의 `ConnectionImpl`객체이다.
  - 실제로 해당 클래스의 클래스 다이어그램을 살펴보면, 상위에 `JDBC` 인터페이스(`java.sql.Connection`)를 구현하고 있음을 볼 수 있다.
  <img width="718" alt="image" src="https://user-images.githubusercontent.com/64415489/164254890-68a891bc-6c3a-4455-b150-b84ee7f35847.png">

## JDBC 버전

|출시년도| JDBC 버전 | JSR 스펙 |  JDK  |
|----|  ------------  | ----------------- | ------------------|
|2017|   JDBC 4.3 |      JSR 221          |   Java SE 9|
|2014|   JDBC 4.2 |      JSR 221          |   Java SE 8|
|2011|   JDBC 4.1 |      JSR 221          |   Java SE 7|
|2006|   JDBC 4.0 |      JSR 221          |   Java SE 6|
|2001|   JDBC 3.0 |      JSR 54           |   JDK 1.4|
|1999|   JDBC 2.1 |                       |   JDK 1.2|
|1997|   JDBC 1.2 |                       |   JDK 1.1|


# JDBC 드라이버
> 위에서 그림으로 살펴봤듯이, JDBC 드라이버는 특정 유형의 데이터베이스에 연결하는 데 사용되는 JDBC API 구현이다. <br>

- 특정 DBMS에서 JDBC API를 사용하려면 JDBC 기술과 데이터베이스 사이를 중재할 JDBC 드라이버가 필요하다.
- 다양한 요인에 따라 드라이버는 Java로만 작성되거나, Java와 JNI(Java Native Interface) 네이티브 메소드를 혼합하여 작성될 수 있다.

## 네 가지 타입의 JDBC 드라이버
### Type 1 : JDBC-ODBC bridge driver
- JDBC-ODBC 브리지 드라이버는 ODBC 드라이버를 사용하여 데이터베이스에 연결한다.
- JDBC-ODBC 브리지 드라이버는 JDBC 메서드 호출을 ODBC 함수 호출로 변환한다.
  - Thin 드라이버(Type4)의 출현으로 이제는 권장되지 않는 방법이다.

- **Oracle은 Java 8부터 JDBC-ODBC Bridge를 지원하지 않는다.**
  - Oracle은 JDBC-ODBC Bridge 대신 데이터베이스 벤더에서 제공하는 JDBC 드라이버를 사용할 것을 권장한다.
<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/164260136-15ba6eaa-36fd-4e34-aa0e-76dafd0b4322.png"/>
  <figcaption align="center">출처 : <a href="https://www.javatpoint.com/jdbc-driver">https://www.javatpoint.com/jdbc-driver</a></figcaption>
</figure>


### Type 2 : Native-API driver (부분적으로 자바로 작성됨)
- Native API 드라이버는 데이터베이스의 클라이언트 측 라이브러리를 사용한다.
  - 예를 들어, Oracle 데이터베이스의 경우 원래 C/C++ 프로그래머용으로 설계된 Oracle Call Interface(OCI) 라이브러리를 통해 액세스가 이루어질 수 있다.

- Native API 드라이버는 JDBC 메소드 호출을 API 데이터베이스의 기본 호출로 변환한다.

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/164262182-a395c57e-be7c-4439-bd3c-5c757bb3fe0b.png"/>
  <figcaption align="center">출처 : <a href="https://www.javatpoint.com/jdbc-driver">https://www.javatpoint.com/jdbc-driver</a></figcaption>
</figure>

### Type 3 : Network Protocol driver (자바로만 작성됨)
- 네트워크 프로토콜 드라이버는 JDBC 호출을 벤더별 데이터베이스 프로토콜로 직/간접적으로 변환하는 미들웨어(애플리케이션 서버)를 사용한다.

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/164263024-de4f50e1-3452-41c1-a67f-7e330230b248.png"/>
  <figcaption align="center">출처 : <a href="https://www.javatpoint.com/jdbc-driver">https://www.javatpoint.com/jdbc-driver</a></figcaption>
</figure>

### Type 4 : Thin driver (자바로만 작성됨)
- Thin 드라이버는 JDBC 호출을 벤더별 데이터베이스 프로토콜로 직접 변환한다.
  - 따라서, 얇은(thin) 드라이버로 알려져 있다.
- 가장 많이 사용되는 타입으로, 플랫폼에 독립적이라는 장점이 있다.
- 또한, 데이터베이스 서버에 직접 접속하기 때문에 다른 타입에 비해 더 나은 성능을 제공한다.
- 데이터베이스별 네트워킹 프로토콜을 이해하고 추가 소프트웨어 없이 데이터베이스에 직접 액세스할 수 있다.

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/164263603-03053d98-b865-4b57-b56a-d69da4e19950.png"/>
  <figcaption align="center">출처 : <a href="https://www.javatpoint.com/jdbc-driver">https://www.javatpoint.com/jdbc-driver</a></figcaption>
</figure>


## JDBC URL
- JDBC 드라이버는 `JDBC URL`을 사용하여 특정 데이터베이스를 식별하고 연결한다.
- 이러한 URL은 일반적으로 다음과 같은 형식이다.
  - **`jdbc:driver:databasename`**
    - 예 : `jdbc:mysql://localhost:3306/dbname`

# 참고 자료
---
- [https://www.baeldung.com/java-jdbc](https://www.baeldung.com/java-jdbc)
- [https://en.wikipedia.org/wiki/Java_Database_Connectivity](https://en.wikipedia.org/wiki/Java_Database_Connectivity)
- [https://docs.oracle.com/javase/8/docs/technotes/guides/jdbc/](https://docs.oracle.com/javase/8/docs/technotes/guides/jdbc/)
- [http://www.herongyang.com/JDBC/Overview-JDBC-Version.html](http://www.herongyang.com/JDBC/Overview-JDBC-Version.html)
- [https://flylib.com/books/en/2.177.1.75/1/](https://flylib.com/books/en/2.177.1.75/1/)
- [https://www.javatpoint.com/jdbc-driver](https://www.javatpoint.com/jdbc-driver)
