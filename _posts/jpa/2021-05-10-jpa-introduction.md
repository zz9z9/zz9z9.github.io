---
title: JPA 입문하기
date: 2021-05-10 00:29:00 +0900
categories: [JPA]
tags: [JAVA, JPA] # TAG names should always be lowercase
---

# 들어가기 전
---
JPA를 회사 프로젝트에서 사용하긴 했지만, 매우 간단한 CRUD에만 사용해서 사실 정확히는 알지 못했다. 따라서, JPA가 정확히 무엇이고 언제, 어디에 사용하는 것인지에 대해 [인프런 김영한님 강의](https://www.inflearn.com/course/ORM-JPA-Basic/dashboard) 를 들으며 공부해보았다.

# JPA란 ?
---
> 'Java Persistence API'를 의미하며 자바 진영의 ORM 기술 표준이다.

- ORM?
  - Object-relational mapping(객체 관계 매핑)
  - 객체는 객체대로 설계 RDB는 RDB대로 설계한다.
    - 각각 설계한 것을 ORM 프레임워크가 중간에서 매핑한다.
    <img src = "https://user-images.githubusercontent.com/64415489/134042057-25bb0484-2ca9-4c7d-8644-34fa77ae0cf5.png" width="70%"/>
  - 대중적인 언어에는 대부분 ORM 기술이 존재한다.

- JPA는 표준 명세이다.
  - 즉, JPA는 인터페이스의 모음이다.
  - JPA 2.1 표준 명세를 구현한 3가지 대표적인 구현체가 있다.
    - Hibernate, EclipseLink, DataNucleus

- 발전 과정 : `JDBC → MyBatis, JdbcTemplate → JPA`

# SQL 중심 코드의 문제점(JPA의 출현 배경)
---
## 1. 생산성
### Without JPA
- 대부분은 객체를 관계형 DB에 관리한다.
- 지속적으로 반복되는 코드
  - 자바 객체 → SQL
  - SQL → 자바 객체
- SQL을 일일이 작성해야한다.

### With JPA
```
- 저장: jpa.persist(member)
- 조회: Member member = jpa.find(memberId)
- 수정: member.setName(“변경할 이름”)
- 삭제: jpa.remove(member)
```

## 2. 유지보수성
### Without JPA
> 필드 변경시 관련된 모든 SQL 수정

```java
public class Member {
  private String memberId;
  private String name;
  private String tel; // 항목 추가
  ...
}
```

```sql
INSERT INTO MEMBER(MEMBER_ID, NAME, TEL) VALUES
    SELECT MEMBER_ID, NAME, TEL FROM MEMBER M
        UPDATE MEMBER SET ... TEL = ?
```

### With JPA
> 필드만 추가하면 됨, SQL은 JPA가 처리

```java
public class Member {
  private String memberId;
  private String name;
  private String tel; // 필드 추가
  ...
}
```

## 3. 패러다임 불일치 발생
> 객체가 나온 사상과, RDB가 나온 사상이 다르다. 하지만, RDB에 맞춰 객체를 다루다보니 사실상 개발자가 <br>
> SQL Mapper의 역할을 하게되었다.

### 3-1. 상속

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/134031370-89ee68e9-cde1-4bf8-805e-8559130bc106.png"/>
  <figcaption align="center">출처 : https://www.inflearn.com/course/ORM-JPA-Basic/dashboard</figcaption>
</figure>

#### Without JPA
- Album 저장
1. 객체 분해
2. INSERT INTO ITEM ...
3. INSERT INTO ALBUM ...

- Album 조회
1. 각각의 테이블에 따른 조인 SQL 작성
2. 각각의 객체 생성

***Album뿐 아니라 다른 자식 객체들도 이러한 작업을 해야한다고 생각하면 매우 번거로울 것이다. <br>
따라서, 일반적으로 DB에 저장할 객체에는 상속 관계를 사용하지 않는다.***

#### With JPA
- Album 저장
  - `jpa.persist(album);`
  - 나머진 JPA가 처리

- Album 조회
  - `Album album = jpa.find(Album.class, albumId);`
  - 나머진 JPA가 처리
  ```sql
   SELECT I.*, A.*
      FROM ITEM I
          JOIN ALBUM A ON I.ITEM_ID = A.ITEM_ID
  ```

### 3-2. 연관관계
- 객체는 참조를 사용(단방향): `member.getTeam()`
- 테이블은 외래 키를 사용(양방향): `JOIN ON M.TEAM_ID = T.TEAM_ID`

#### Without JPA
- 객체를 테이블에 맞추어 모델링

```java
class Member {
    String id; // MEMBER_ID 컬럼 사용
    Long teamId; // TEAM_ID FK 컬럼 사용
    String username;// USERNAME 컬럼 사용
}

class Team {
    Long id; // TEAM_ID PK 사용
    String name; // NAME 컬럼 사용
}
```

`INSERT INTO MEMBER(MEMBER_ID, TEAM_ID, USERNAME) VALUES ...`

- 객체다운 모델링

```java
class Member {
    String id; // MEMBER_ID 컬럼 사용
    Team team; // 참조로 연관관계를 맺는다.
    String username; // USERNAME 컬럼 사용

    Team getTeam() { return team; }
}

class Team {
    Long id; // TEAM_ID PK 사용
    String name; // NAME 컬럼 사용
}
```

```
// TEAM_ID : member.getTeam().getId();
 INSERT INTO MEMBER(MEMBER_ID, TEAM_ID, USERNAME) VALUES ...
```

***이렇게 객체다운 모델링을 했을때의 문제점은 조회시 매우 번거로워질 수 있다는 것이다.***

- 아래 쿼리를 통해 얻은 결과를 `Member` 객체에 세팅하는 상황을 가정해보자.
```sql
SELECT M.*, T.* FROM MEMBER M
    JOIN TEAM T ON M.TEAM_ID = T.TEAM_ID
```

- 조회 결과에 섞여있는 모든 데이터를 Member, Team 각각의 객체에 알맞게 세팅한 뒤, Team 객체는 Member 객체에 세팅해줘야 한다.
  - 따라서, 실무에서는 생산성을 위해 Member와 Team의 필드를 모두 합친 `SuperDTO` 등을 만들거나 하는 일이 비일비재하다.

```java
public Member find(String memberId) {
    //SQL 실행 ...
    Member member = new Member();

    //데이터베이스에서 조회한 회원 관련 정보를 모두 입력
    Team team = new Team();

    //데이터베이스에서 조회한 팀 관련 정보를 모두 입력
    //회원과 팀 관계 설정
    member.setTeam(team);

    return member;
}
```

#### With JPA

```java
Member member = list.get(memberId);
Team team = member.getTeam();

member.setTeam(team);
jpa.persist(member);
```


### 3-3. 객체 그래프 탐색
> 객체는 자유롭게 객체 그래프를 탐색할 수 있어야 한다.

#### Without JPA
- 처음 실행하는 SQL에 따라 객체 그래프 탐색 범위기 결정된다.
  - 만약 아래 쿼리에 대한 결과로 객체 그래프를 탐색한다면 `member.getOrder();`는 null을 반환할 것이다.

```sql
SELECT M.*, T.* FROM MEMBER M
    JOIN TEAM T ON M.TEAM_ID = T.TEAM_ID
```

- 이와 같은 상황은 엔티티 신뢰 문제로 이어진다.
  - 즉, 아래 코드의 경우 `getTeam()`, `getOrder()` 등이 null이 아닌지 확신하려면 `memberDAO.find(memberId)` 내부에 어떤 쿼리가 동작하는지 살펴봐야 한다.

```java
class MemberService {
...
  public void process() {
     Member member = memberDAO.find(memberId);
     member.getTeam(); //???
     member.getOrder().getDelivery(); // ???
  }
}
```

#### With JPA

```java
Member member = jpa.find(Member.class, memberId);
Team team = member.getTeam();
```

- 신뢰할 수 있는 엔티티, 계층
```java
class MemberService {
    ...
    public void process() {
        Member member = memberDAO.find(memberId);
        member.getTeam(); // 자유로운 객체 그래프 탐색
        member.getOrder().getDelivery();
    }
}
```

### 3-4. 객체 비교
#### Without JPA
```java
String memberId = "100";
Member member1 = memberDAO.getMember(memberId);
Member member2 = memberDAO.getMember(memberId);
member1 == member2; //다르다.

class MemberDAO {
    public Member getMember(String memberId) {
        String sql = "SELECT * FROM MEMBER WHERE MEMBER_ID = ?";
        ...
        //JDBC API, SQL 실행
        return new Member(...);
    }
}
```


#### With JPA
> 동일한 트랜잭션에서 조회한 엔티티는 같음을 보장한다.

```java
String memberId = "100";
Member member1 = list.get(memberId);
Member member2 = list.get(memberId);
member1 == member2; //같다.
```


# JPA와 성능
---
## 1. 1차 캐시와 동일성(identity) 보장
  - 같은 트랜잭션 안에서는 같은 엔티티를 반환
    - 약간의 조회 성능이 향상된다. (미미한 수준)
  - DB Isolation Level이 Read Committed라도 애플리케이션에서 Repeatable Read를 보장한다.
  ``` java
  String memberId = "100";
  Member m1 = jpa.find(Member.class, memberId); //SQL
  Member m2 = jpa.find(Member.class, memberId); //캐시
  println(m1 == m2) //true
  // 결과적으로는 SQL 1번만 실행
  ```

## 2. 트랜잭션을 지원하는 쓰기 지연(transactional write-behind)
  - 트랜잭션을 커밋할 때까지 INSERT SQL을 모음
  - JDBC BATCH SQL 기능을 사용해서 한번에 SQL 전송

```java
transaction.begin(); // 트랜잭션 시작

em.persist(memberA);
em.persist(memberB);
em.persist(memberC);
//여기까지 INSERT SQL을 데이터베이스에 보내지 않는다.

//커밋하는 순간 데이터베이스에 INSERT SQL을 모아서 보낸다.
transaction.commit(); // 트랜잭션 커밋
```

## 3. 지연 로딩과 즉시 로딩
> 옵션을 통해 지연 로딩과 즉시 로딩을 자유롭게 선택할 수 있다. <br>
> 만약 SQL 중심이었다면 관련된 쿼리를 모두 변경해야 했을 것이다.

- 지연로딩 : 객체가 실제 사용될 때 로딩
```java
Member member = memberDAO.find(memberId); // SELECT * FROM MEMBER
Team team = member.getTeam();
String teamName = team.getName(); // SELECT * FROM TEAM
```

- 즉시 로딩: JOIN SQL로 한번에 연관된 객체까지 미리 조회
```java
Member member = memberDAO.find(memberId); // SELECT * FROM M.*, T.* FROM MEMBER JOIN TEAM ...
Team team = member.getTeam();
String teamName = team.getName();
```

# 참고자료
---
- [김영한, 자바 ORM 표준 JPA 프로그래밍 - 기본편](https://www.inflearn.com/course/ORM-JPA-Basic/dashboard)

