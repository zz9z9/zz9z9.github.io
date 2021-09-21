---
title: JPA 내부 구조 살펴보기
date: 2021-05-12 00:29:00 +0900
categories: [JPA]
tags: [JAVA, JPA]
---

# 들어가기 전
---
JPA 내부 구조를 제대로 모르고 사용하면, 오히려 성능 저하를 발생시킬 수도 있다고 한다. 따라서, JPA는 내부적으로 어떻게 동작하는 것인지 알기 위해
[인프런 김영한님 강의](https://www.inflearn.com/course/ORM-JPA-Basic/dashboard) 를 들으며 공부해보았다.

# JPA 구동 방식
---

<img src = "https://user-images.githubusercontent.com/64415489/134194538-0d91d2c0-96c5-4a83-bd09-e1dd2e3cf91c.png" width="80%"/>

- persistence.xml 예시

```xml
<?xml version="1.0" encoding="UTF-8"?>
<persistence version="2.2"
             xmlns="http://xmlns.jcp.org/xml/ns/persistence" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
             xsi:schemaLocation="http://xmlns.jcp.org/xml/ns/persistence http://xmlns.jcp.org/xml/ns/persistence/persistence_2_2.xsd">
    <persistence-unit name="hello">
        <properties>
            <!-- 필수 속성 -->
            <property name="javax.persistence.jdbc.driver" value="org.h2.Driver"/>
            <property name="javax.persistence.jdbc.user" value="sa"/>
            <property name="javax.persistence.jdbc.password" value=""/>
            <property name="javax.persistence.jdbc.url" value="jdbc:h2:tcp://localhost/~/test"/>
            <property name="hibernate.dialect" value="org.hibernate.dialect.H2Dialect"/>
            <!-- 옵션 -->
            <property name="hibernate.show_sql" value="true"/>
            <property name="hibernate.format_sql" value="true"/>
            <property name="hibernate.use_sql_comments" value="true"/>
            <property name="hibernate.hbm2ddl.auto" value="create" />
        </properties>
    </persistence-unit>
</persistence>
```

- `EntityManagerFactory`, `EntityManager` 사용

```java
public class JpaMain {
    public static void main(String[] args) {
        EntityManagerFactory emf = Persistence.createEntityManagerFactory("hello");

        EntityManager em = emf.createEntityManager();

        EntityTransaction tx = em.getTransaction();
        tx.begin();

        try {
            Order order = new Order();
            order.setId(1L);
            em.persist(order);

            tx.commit();
        } catch (Exception e) {
            tx.rollback();
        } finally {
            em.close();
        }

        emf.close();
    }
}
```

## 주의사항
- 엔티티 매니저 팩토리는 하나만 생성해서 애플리케이션 전체에서 공유된다.
- 엔티티 매니저는 쓰레드간에 공유X (그렇지 않으면 데이터 정합성이 깨질 수 있다).
- JPA의 모든 데이터 변경은 트랜잭션 안에서 실행되어야 한다.

![image](https://user-images.githubusercontent.com/64415489/134196318-b1ac6fed-6aed-41a3-947f-ff7dd2eeb0b0.png)

# 영속성 컨텍스트(Peristence Context)
---
> “엔티티를 영구 저장하는 환경”이라는 뜻으로 논리적인 개념이다.
> Hibernate와 같은 Persistence provider는 영속성 컨텍스트를 사용하여 애플리케이션의 엔티티 라이프사이클을 관리한다.

- `EntityManager.persist(entity);`
  - `EntityManager`는 영속성 컨텍스트와 상호작용할 수 있게 해주는 인터페이스이다.
    - 즉, `EntityManager`를 통해 영속성 컨텍스트와 상호작용 할 수 있다.
  - `persist(entity)`는 DB가 아닌 영속성 컨텍스트에 저장하는 것.

## 엔티티의 라이프사이클

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/134197321-50dc6c38-35d2-4a6f-9ce9-76f93034b1cb.png"/>
  <figcaption align="center">출처 : https://thorben-janssen.com/entity-lifecycle-model/</figcaption>
</figure>

### 1.비영속 (new/transient)
> 영속성 컨텍스트와 전혀 관계가 없는 새로운 상태로, 객체를 생성만 해놓은 상태이다.

```java
//객체를 생성한 상태(비영속)
Member member = new Member();
member.setId("member1");
member.setUsername("회원1");
```

### 2. 영속 (managed)
> 영속성 컨텍스트에 관리되는 상태이다. 영속 상태가 된다고해서 DB에 바로 쿼리가 날라가지 않는다. <br>
> 쿼리는 트랜잭션 커밋시 날라간다.

```java
//객체를 생성한 상태(비영속)
Member member = new Member();
member.setId("member1");
member.setUsername(“회원1”);
EntityManager em = emf.createEntityManager();
em.getTransaction().begin();

//객체를 저장한 상태(영속)
em.persist(member);

// DB에 쿼리 날린다.
tx.commit();
```

### 3. 준영속 (detached)
> 영속성 컨텍스트에 저장되었다가 분리된 상태이다.

- 준영속 상태
  - 영속 -> 준영속
  - 영속 상태의 엔티티가 영속성 컨텍스트에서 분리(detached)
  - 영속성 컨텍스트가 제공하는 기능을 사용 못함

- 준영속 상태로 만드는 방법
  - `em.detach(entity)`
    - 특정 엔티티만 준영속 상태로 전환
  - `em.clear()`
    - 영속성 컨텍스트를 완전히 초기화
  - `em.close()`
    - 영속성 컨텍스트를 종료

```java
//회원 엔티티를 영속성 컨텍스트에서 분리, 준영속 상태
em.detach(member);
```

### 4. 삭제 (removed)
> 엔티티가 영속성 컨텍스트에서 삭제된 상태이다.

```java
//객체를 삭제한 상태(삭제)
em.remove(member);
```

# 영속성 컨텍스트의 이점
---
## 1. 1차 캐시
> 같은 트랜잭션 내에서만(하나의 사용자 요청) 유효하다. 즉, 엔티티 매니저는 트랜잭션 종료와 동시에 사라진다.

- 조회시

```java
Member member = new Member();
member.setId("member1");
member.setUsername("회원1");

//1차 캐시에 저장됨
em.persist(member);

//1차 캐시에서 조회
Member findMember = em.find(Member.class, "member1");
```

<img src="https://user-images.githubusercontent.com/64415489/134203936-863f7775-d020-4c83-b9c6-8e1178e52946.png" width="80%"/>


- 1차 캐시에 없는 데이터 조회시
```java
Member findMember2 = em.find(Member.class, "member2");
```
![image](https://user-images.githubusercontent.com/64415489/134204901-8eddb060-7ba1-4658-9344-d0e3ab6254d6.png)


## 2. 동일성(identity) 보장
> 1차 캐시로 반복 가능한 읽기(REPEATABLE READ) 등급의 트랜잭션 격리 수준을 데이터베이스가 아닌 애플리케이션 차원에서 제공

```java
Member a = em.find(Member.class, "member1");
Member b = em.find(Member.class, "member1");

System.out.println(a == b); //동일성 비교 true
```

## 3. 트랜잭션을 지원하는 쓰기 지연(transactional write-behind)

```java
EntityManager em = emf.createEntityManager();
EntityTransaction transaction = em.getTransaction();

//엔티티 매니저는 데이터 변경시 트랜잭션을 시작해야 한다.
transaction.begin(); // [트랜잭션] 시작

em.persist(memberA);
em.persist(memberB);
//여기까지 INSERT SQL을 데이터베이스에 보내지 않는다.

//커밋하는 순간 데이터베이스에 INSERT SQL을 보낸다.
transaction.commit(); // [트랜잭션] 커밋
```

- 영속성 컨텍스트 내부에는 '쓰기 지연 SQL 저장소'라는 것도 있다.
  - `hibernate.jdbc.batch_size` 옵션을 주게되면 해당 사이즈만큼 쿼리를 쌓아뒀다가 트랜잭션 커밋시 DB로 날리게된다.

## 4. 변경 감지(Dirty Checking)
> 자바 컬렉션 다루듯이 다룬다고 생각하면 된다.

```java
EntityManager em = emf.createEntityManager();
EntityTransaction transaction = em.getTransaction();
transaction.begin(); // [트랜잭션] 시작

// 영속 엔티티 조회
Member memberA = em.find(Member.class, "memberA");

// 영속 엔티티 데이터 수정
memberA.setUsername("hi");
memberA.setAge(10);

//em.update(member) 불필요한 코드

transaction.commit(); // [트랜잭션] 커밋
```

- DB 트랜잭션을 커밋하게 되면 내부적으로 flush()
- 앤티티와 스냅샷 비교
  - 스냅샷 : 1차 캐시에 최초로 들어왔을 때의 값

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/134151431-e01a97f8-5199-4c12-aa3f-61fa04f8b17e.png"/>
  <figcaption align="center">출처 : https://www.inflearn.com/course/ORM-JPA-Basic/dashboard</figcaption>
</figure>

### flush
> 영속성 컨텍스트의 '쓰기 지연 SQL 저장소'에 있는 내용을 데이터베이스에 반영 <br>
> (1차 캐시를 비우는게 아님)

- 트랜잭션이라는 작업 단위가 중요하다.
  - 즉, 커밋 직전에만 동기화 하면 됨

- 플러시 발생 과정
1. 변경 감지
2. 수정된 엔티티를 쓰기 지연 SQL 저장소에 등록
3. 쓰기 지연 SQL 저장소의 쿼리를 데이터베이스에 전송 (등록, 수정, 삭제 쿼리)

- 영속성 컨텍스트를 플러시하는 방법
  - 직접 호출
    - `em.flush()`
  - 플러시 자동 호출
    - 트랜잭션 커밋
    - JPQL 쿼리 실행

- 플러시 모드 옵션
  - `em.setFlushMode(FlushModeType.COMMIT)`
  - `FlushModeType.AUTO`
    - 커밋이나 쿼리를 실행할 때 플러시 (기본값)
  - `FlushModeType.COMMIT`
    - 커밋할 때만 플러시

# 참고자료
---
- [김영한, 자바 ORM 표준 JPA 프로그래밍 - 기본편](https://www.inflearn.com/course/ORM-JPA-Basic/dashboard)
- [https://www.baeldung.com/jpa-hibernate-persistence-context](https://www.baeldung.com/jpa-hibernate-persistence-context)
