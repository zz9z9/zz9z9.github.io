---
title: JDBC / MyBatis / MyBatis-Spring 훑어보기
date: 2023-12-21 22:25:00 +0900
categories: [지식 더하기, Hello-World 구현]
tags: [Mybatis]
---

> JDBC부터 mysql-spring까지 간단하게 사용해보면서 드는 개인적인 생각을 적어보자.

- 시나리오 : 회원 테이블에 회원 정보 저장 후, 회원 이력 테이블에 이력 저장하기 전 예외 발생
  - 상황1 : 회원 정보는 저장됨
  - 상황2 : 회원, 이력 테이블에 모두 저장되지 않음

# JDBC

---

- **상황1**

```java
public class JdbcMemberQueryServiceImpl implements MemberQueryService {

  @Override
  public void createMember(String id, String name) {
      try(Connection con = getConnection()) {
        PreparedStatement createMemberStmt = con.prepareStatement("INSERT INTO member (member_id, member_name) VALUES (?, ?)");
        createMemberStmt.setString(1, id);
        createMemberStmt.setString(2, name);
        createMemberStmt.executeUpdate();

        PreparedStatement createMemberHistStmt = con.prepareStatement("INSERT INTO member_history (member_id, action_type, registered_at) VALUES (?, ?, ?)");
        createMemberHistStmt.setString(1, id);
        createMemberHistStmt.setString(2, "JOIN");

        long epochSec = LocalDateTime.now().atZone(ZoneId.systemDefault()).toInstant().getEpochSecond();
        createMemberHistStmt.setDate(3, new Date(epochSec));

        causeException();

        createMemberHistStmt.executeUpdate();
      } catch (SQLException e) {
        e.printStackTrace();
      }
  }

  private Connection getConnection() throws SQLException {
        String url = "jdbc:mysql://localhost:3306/STUDY";
        String user = "root";
        String password = "root";

        return DriverManager.getConnection(url, user, password);
    }
}
```

- **상황2**

```java
public class JdbcMemberQueryServiceImpl implements MemberQueryService {

    @Override
    public void createMember(String id, String name) {
        try(Connection con = getConnection()) {
            con.setAutoCommit(false);

            // 위와 동일 ...

            causeException();

            createMemberHistStmt.executeUpdate();
            con.commit();
        } catch (SQLException e) {
            e.printStackTrace();
        }
    }

}
```

### 생각하는 문제점
  - 비즈니스 로직(멤버 저장)에 DB관련 로직(커넥션 가져오기, SQL문 만들기 등)이 섞이게된다.
  - 위와 같은 DB관련 코드가 여러 로직에 중복해서 나타나게된다.
  - 쿼리문 작성시 오타날 수 있는 가능성이 있고, 있어도 컴파일 시점에선 알 수 없다.
  - statement에 파라미터 세팅시 해당 파라미터의 데이터 타입을 다 알고있어야한다. 즉, DB에 강하게 결합된 로직이 될 수밖에 없다.
  - java.sql 패키지에 정의된 데이터 타입이 강제된다.


# MyBatis

---

> 의존성 추가 : `implementation 'org.mybatis:mybatis:3.5.14'`

- MyBatis 관련 설정 파일 세팅 : `mybatis-config.xml`

```xml
<?xml version = "1.0" encoding = "UTF-8"?>

<!DOCTYPE configuration PUBLIC "-//mybatis.org//DTD Config 3.0//EN" "http://mybatis.org/dtd/mybatis-3-config.dtd">
<configuration>

    <environments default = "development">
        <environment id = "development">
            <transactionManager type = "JDBC"/>

            <dataSource type = "POOLED">
                <property name = "driver" value = "com.mysql.cj.jdbc.Driver"/>
                <property name = "url" value = "jdbc:mysql://localhost:3306/STUDY"/>
                <property name = "username" value = "root"/>
                <property name = "password" value = "root"/>
            </dataSource>

        </environment>
    </environments>

    <mappers>
        <mapper resource = "mybatis-mapper/member.xml"/>
        <mapper resource = "mybatis-mapper/memberHistory.xml"/>
    </mappers>

</configuration>
```
- 매퍼 파일 세팅

```xml
<!-- member.xml-->
<?xml version = "1.0" encoding = "UTF-8"?>

<!DOCTYPE mapper PUBLIC "-//mybatis.org//DTD Mapper 3.0//EN" "http://mybatis.org/dtd/mybatis-3-mapper.dtd">

<mapper namespace = "member">
    <insert id = "save" parameterType = "hello.persistence.model.Member">
        INSERT INTO member (member_id, member_name) VALUES (#{id}, #{name})
    </insert>
</mapper>
```

```xml
<!--memberHistory.xml-->
<?xml version = "1.0" encoding = "UTF-8"?>

<!DOCTYPE mapper PUBLIC "-//mybatis.org//DTD Mapper 3.0//EN" "http://mybatis.org/dtd/mybatis-3-mapper.dtd">

<mapper namespace = "memberHistory">
    <insert id = "save" parameterType = "hello.persistence.model.MemberHistory">
        INSERT INTO member_history (member_id, action_type, registered_at) VALUES (#{member.id}, #{actionType}, NOW())
    </insert>
</mapper>
```
- **상황1**

```java
public class MybatisMemberQueryServiceImpl implements MemberQueryService {
    private static SqlSessionFactory sqlSessionFactory;
    private static Reader reader;

    static {
        try {
            reader = Resources.getResourceAsReader("mybatis-config.xml");
            sqlSessionFactory = new SqlSessionFactoryBuilder().build(reader);
        } catch (IOException e) {
            e.printStackTrace();
        }
    }

    @Override
    public void createMember(String id, String name) {
        try(SqlSession sqlSession = sqlSessionFactory.openSession()) { // autoCommit : true (default)
          Member newMember = new Member(id, name);
          sqlSession.insert("member.save", newMember);

          causeException();

          sqlSession.insert("memberHistory.save", MemberHistory.forJoin(newMember));
        } catch (Exception e) {
          e.printStackTrace();
        }
    }
}
```

- **상황2**

```java
public class MybatisMemberQueryServiceImpl implements MemberQueryService {
    ...

    @Override
    public void createMember(String id, String name) {
        try(SqlSession sqlSession = sqlSessionFactory.openSession(false)) {
            ...

            causeException();

            sqlSession.insert("memberHistory.save", MemberHistory.forJoin(newMember));
            sqlSession.commit();
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}
```

### JDBC와 비교해서 나아졌다고 느끼는 부분
- 비즈니스 로직과 관련없는 DB 관련 로직(커넥션 얻어오기, statement 만들기 등)이 어느정도 분리됨
- `if`, `choose` 등의 기능을 통해 Dynamic 쿼리를 보다 쉽게 작성할 수 있다.

### 생각하는 문제점
- 컴파일 시점에 쿼리 오류 알 수 없음 (+ mapper id도 "member.save"와 같이 문자열로 받는다.)
- 세션을 열고 닫는 부분을 신경써야한다. (비즈니스 로직에 DB 관련 로직이 남아있음)
- 매퍼 파일이 생길때마다 설정에 추가해줘야하는 번거로움


# MyBatis-Spring

---

> 의존성 추가 : implementation 'org.mybatis:mybatis-spring:2.1.2' <br>

- [공식 문서](https://mybatis.org/spring/index.html) 에 나와있는 버전 호환성

| MyBatis-Spring | MyBatis | Spring Framework | Spring Batch | Java |
| -------------- | ------- | ---------------- | ------------ | ---- |
| 3.0 | 3.5+ |	6.0+| 5.0+| Java 17+|
| 2.1 |	3.5+ | 	5.x | 4.x | Java 8+ |
| 2.0 | 3.5+ |	5.x | 4.x |	Java 8+ |
| 1.3 | 3.4+ | 3.2.2+ |	2.1+ | Java 6+ |

## SqlSessionTemplate 주입

```java
@Configuration
public class AppConfig {

    @Bean
    public DataSource dataSource() {
      String dbUrl = "jdbc:mysql://localhost:3306/STUDY";
      String user = "root";
      String pw = "root";
      DriverManagerDataSource dataSource = new DriverManagerDataSource(dbUrl, user, pw);
      dataSource.setDriverClassName("com.mysql.cj.jdbc.Driver");
      return dataSource;
    }

    @Bean
    public SqlSessionFactory sqlSessionFactory() throws Exception {
      SqlSessionFactoryBean factoryBean = new SqlSessionFactoryBean();
      factoryBean.setDataSource(dataSource());
      factoryBean.setMapperLocations(new PathMatchingResourcePatternResolver().getResources("classpath:mybatis-mapper/*.xml"));
      return factoryBean.getObject();
    }

    @Bean
    public SqlSessionTemplate sqlSession() throws Exception {
        return new SqlSessionTemplate(sqlSessionFactory());
    }

    @Bean
    public MemberQueryService memberQueryService() throws Exception {
      return new MybatisSpringMemberQueryServiceImpl(sqlSession());
    }

}
```

```java
public class PersistenceDemoApp {

    public static void main(String[] args) {
        ApplicationContext ctx = new AnnotationConfigApplicationContext(AppConfig.class);
        MemberQueryService memberQueryService = (MemberQueryService) ctx.getBean("memberQueryService");

        memberQueryService.createMember("user1", "Kevin");
    }

}
```

- **상황1**

```java
public class MybatisSpringMemberQueryServiceImpl implements MemberQueryService {

  private final SqlSession sqlSession;

  public MybatisSpringMemberQueryServiceImpl(SqlSession sqlSession) {
    this.sqlSession = sqlSession;
  }

  @Override
  public void createMember(String id, String name) {
    Member newMember = new Member(id, name);
    sqlSession.insert("member.save", newMember);

    causeException();

    sqlSessionTemplate.insert("memberHistory.save", MemberHistory.forJoin(newMember));
  }
}
```

> 위 예제에서 sqlSession의 구현체인 sqlSessionTemplate에서 commit, rollback을 직접호출하면 `UnsupportedOperationException` 발생, 기본적으로는 autoCommit된다. 또한 SqlSession에는 setAutoCommit하는 부분도 없다.<br>
> 따라서, 상황2를 위해서는 `org.springframework.transaction.TransactionManager`가 필요 <br><br>
> [공식 문서](https://mybatis.org/spring/ko/transactions.html)에 따르면 ***"마이바티스 스프링 연동모듈을 사용하는 중요한 이유중 하나는 마이바티스가 스프링 트랜잭션에 자연스럽게 연동될수 있다는 것이다. 마이바티스에 종속되는 새로운 트랜잭션 관리를 만드는 것보다는 마이바티스 스프링 연동모듈이 스프링의 DataSourceTransactionManager과 융합되는 것이 좋다."*** 라고 되어있는게 mybatis-spring 자체적으로는 트랜잭션 관리하는 부분을 제공하지 않고 스프링쪽의 `TransactionManager`가 필요하다는 얘기인 것 같기도하다.

- AppConfig.java에 PlatformTransactionManager 빈 선언 및 MemberQueryService에 주입

```java
@Bean
public PlatformTransactionManager transactionManager() {
    return new DataSourceTransactionManager(dataSource());
}

@Bean
public MemberQueryService memberQueryService() throws Exception {
  return new MybatisSpringMemberQueryServiceImpl(sqlSession(), transactionManager());
}
```

- **상황2**

```java
public class MybatisSpringMemberQueryServiceImpl implements MemberQueryService {

    private final SqlSession sqlSession;
    private final PlatformTransactionManager transactionManager;

    public MybatisSpringMemberQueryServiceImpl(SqlSession sqlSession, PlatformTransactionManager transactionManager) {
        this.sqlSession = sqlSession;
        this.transactionManager = transactionManager;
    }

    @Override
    public void createMember(String id, String name) {
      TransactionStatus txStatus = transactionManager.getTransaction(new DefaultTransactionDefinition());
      Member newMember = new Member(id, name);
      sqlSession.insert("member.save", newMember);

      causeException();

      sqlSession.insert("memberHistory.save", MemberHistory.forJoin(newMember));
      transactionManager.commit(txStatus);
    }

}
```

### MyBatis와 비교해서 나아졌다고 느끼는 부분
- SqlSessionFactory 사용해서 SqlSession을 매번 생성하고 커밋/롤백후 닫는 작업을 안해줘도된다.
- SqlSessionTemplate은 Thread-safe하다. ([참고](https://mybatis.org/spring/sqlsession.html))

### 생각하는 문제점
- 트랜잭션 처리를 위해 TransactionManager, TransactionStatus 등 이전에 비해 의존해야될 객체들이 더 생긴다.
- 비즈니스 로직에 트랜잭션 관련 처리 코드가 섞인다.
- statement 문자열로 선언

## 위 상황2 개선해보기 : @Transactional 사용
- AppConfig.java에 `@EnableTransactionManagement` 선언

```java
public class MybatisSpringMemberQueryServiceImpl implements MemberQueryService {

    private final SqlSession sqlSession;

    public MybatisSpringMemberQueryServiceImpl(SqlSession sqlSession) {
        this.sqlSession = sqlSession;
    }

    @Override
    @Transactional
    public void createMember(String id, String name) {
      Member newMember = new Member(id, name);
      sqlSession.insert("member.save", newMember);

      causeException();

      sqlSession.insert("memberHistory.save", MemberHistory.forJoin(newMember));
    }

}
```

### 전과 비교해서 나아졌다고 느끼는 부분
- `TransactionStatus`, `PlatformTransactionManager`에 의존하지 않아도된다.
- 비즈니스 로직에서 트랜잭션 관련 부분이 사라진다.

## Statement id 문자열로 입력하는 부분 개선하기 : 매퍼 인터페이스 사용

```java
public interface MemberMapper {
  void save(Member member);
}

public interface MemberHistoryMapper {
  void save(MemberHistory memberHistory);
}
```

- `AppConfig.java`에 Mapper 빈 추가

```java
@Bean
public MemberMapper memberMapper() throws Exception {
    MapperFactoryBean<MemberMapper> factoryBean = new MapperFactoryBean<>(MemberMapper.class);
    factoryBean.setSqlSessionFactory(sqlSessionFactory());
    return factoryBean.getObject();
}

@Bean
public MemberHistoryMapper memberHistoryMapper() throws Exception {
    MapperFactoryBean<MemberHistoryMapper> factoryBean = new MapperFactoryBean<>(MemberHistoryMapper.class);
    factoryBean.setSqlSessionFactory(sqlSessionFactory());
    return factoryBean.getObject();
}

@Bean
public MemberQueryService memberQueryService() throws Exception {
  return new MybatisSpringMemberQueryServiceImpl(memberMapper(), memberHistoryMapper());
}
```

- 또는, `@MapperScan`을 사용하면
```java
@Configuration
@MapperScan("hello.persistence.mybatis.mapper")
public class AppConfig {

    @Bean
    public MemberQueryService memberQueryService() throws Exception {
          // TODO : MapperScan 사용할 때는 의존성 주입 어떻게하지 ??
    }
}
```

- 매퍼 파일의 namespace에는 매퍼 인터페이스의 full package 명을 적어야한다.
  - member.xml : `<mapper namespace = "hello.persistence.mybatis.mapper.MemberMapper">`
  - memberHistory.xml : `<mapper namespace = "hello.persistence.mybatis.mapper.MemberHistoryMapper">`


```java
public class MybatisSpringMemberQueryServiceImpl implements MemberQueryService {

  private MemberMapper memberMapper;
  private MemberHistoryMapper memberHistoryMapper;

  public MybatisSpringMemberQueryServiceImpl(MemberMapper memberMapper, MemberHistoryMapper memberHistoryMapper) {
    this.memberMapper = memberMapper;
    this.memberHistoryMapper = memberHistoryMapper;
  }

  @Override
  @Transactional
  public void createMember(String id, String name) {
    Member newMember = new Member(id, name);
    memberMapper.save(newMember);

    causeException();

    memberHistoryMapper.save(MemberHistory.forJoin(newMember));
  }

}
```

### 전과 비교해서 나아졌다고 느끼는 부분
- DB 관련된 코드가 비즈니스 로직에서 완전히 분리된다.
- Statement id가 잘못 맵핑된 경우 컴파일 시점에서 발견될 수 있다. (즉, 문자열 오타 등으로 인해 없는 Statement 호출할 일은 없음)
