---
title: Spring - Spring Boot 알아보기
date: 2025-08-21 21:25:00 +0900
categories: [지식 더하기, 이론]
tags: [Spring]
---

## Spring Boot의 목표
---

1. 모든 Spring 개발에서 극적으로 빠르고 누구나 쉽게 접근 가능한 시작 경험을 제공하는 것.
→ 프로젝트를 시작할 때 복잡한 설정 없이 바로 개발을 시작할 수 있게 한다.

2. 기본적으로는 권장되는(opinionated) 설정을 제공하지만, 개발 요구사항이 기본값에서 벗어나면 쉽게 커스터마이징할 수 있도록 하는 것.

3. 대규모 프로젝트에서 공통적으로 필요한 비기능적 기능들을 제공하는 것.
(예: 내장 서버, 보안, 메트릭 수집, 헬스 체크, 외부화된 설정 등)

4. (네이티브 이미지 타겟이 아닌 경우) 절대 코드 생성에 의존하지 않고, XML 설정을 요구하지 않는 것.
→ 즉, 순수 자바/애너테이션 기반 구성만으로 충분히 개발할 수 있게 한다.

## 핵심 개념
---

### 1. Convention over Configuration (관습이 설정보다 우선)
- 개발자가 모든 걸 세세히 설정하지 않아도, 일반적으로 가장 많이 쓰는 방식대로 자동 설정해 줍니다.
  - 예: spring-boot-starter-web만 추가하면 내장 톰캣, JSON 변환기, DispatcherServlet까지 자동 준비됨.
- 개발자는 원하는 경우에만 설정을 덮어씌우면 됨.

### 2. Opinionated Defaults (권장되는 기본값)
- Spring Boot는 “실무에서 가장 합리적인 기본값”을 미리 선택해 둡니다.
  - 예: HikariCP를 기본 커넥션 풀로 채택, UTF-8 기본 인코딩, actuator로 헬스 체크 제공.
- Spring에서라면 직접 골라야 할 선택지를 Spring Boot가 대신 정해줌.

### 3. Auto Configuration (자동 설정)
- **클래스패스**에 존재하는 라이브러리를 감지해서 관련 Bean을 자동 구성합니다.
  - 예: `spring-boot-starter-data-jpa`를 추가하면 `EntityManager`, `Hibernate`, `JPA Repository` 자동 등록.

### 4. Standalone Application (독립 실행형 애플리케이션)
- 내장 톰캣/Jetty/Undertow를 포함한 실행 가능한 JAR로 배포 가능.
- 외부 WAS 설치 없이 `java -jar`만으로 실행.

### 5. Production-ready Features
- Spring Boot Actuator: 헬스 체크, 메트릭, 로그레벨 조정, 환경 확인 등 운영 친화 기능 제공.
- DevTools: 코드 변경 시 자동 재시작, LiveReload 등 개발 편의 기능.

## 주요 모듈
---
> [Spring Boot Repository](https://github.com/spring-projects/spring-boot) README 참고

## spring-boot
> Spring Boot의 다른 부분들을 지원하는 기능들을 제공하는 메인 라이브러리

**1. SpringApplication 클래스**
- 독립 실행형 Spring 애플리케이션을 작성할 때 사용할 수 있는 정적 편의 메서드(`SpringApplication.run(Application.class, args` 등) 를 제공.
- 이 클래스의 유일한 역할은 적절한 Spring ApplicationContext를 생성하고 갱신(refresh)하는 것.

**2. 내장 웹 애플리케이션**
- Tomcat, Jetty 같은 컨테이너 선택 가능.

**3. 외부 설정 지원**
- 설정값을 코드에 하드코딩하지 않고, 외부에서 주입받을 수 있도록 디자인되어 있음
  - 예: `application.properties`, 환경 변수 (OS level), 커맨드라인 인자 (`--server.port=8081`)

**4. 편리한 ApplicationContext 초기화 도구**
- Spring Boot는 `ApplicationContextInitializer`를 미리 구현해 두어서, 로깅이나 환경설정 같은 것들이 애플리케이션 시작 시 자동으로 초기화되도록 해줍니다.
  - 예: SpringApplication 실행 시 자동으로 `LoggingApplicationListener` 같은 리스너를 붙여줌.

**5. 로깅 기본값 지원 포함**
- 별도 설정을 하지 않아도 기본 로깅이 작동합니다.
  - 기본 로깅 프레임워크는 `SLF4J + Logback`
- 로그 포맷, 로그 레벨(INFO), 출력 대상(Console) 등이 자동 지정
  - 필요하면 `application.properties`에서 간단히 바꿀 수 있음.

## spring-boot-autoconfigure
- Spring Boot는 클래스패스에 포함된 내용에 따라 애플리케이션의 많은 부분을 자동으로 설정
  - 예 : 클래스패스에 `spring-webmvc`가 있으면 자동으로 `DispatcherServlet`이 등록 (`org.springframework.boot.webmvc.autoconfigure.DispatcherServletAutoConfiguration`을 통해)
- `@EnableAutoConfiguration` 애너테이션이 Spring 컨텍스트의 자동 설정을 트리거
- 자동 설정은 사용자가 필요로 할 수 있는 Bean을 추론하려고 시도
  - 예를 들어, HSQLDB가 클래스패스에 있고 사용자가 어떤 데이터베이스 연결도 설정하지 않았다면, 인메모리 데이터베이스를 정의하길 원한다고 추정
  - 사용자가 직접 Bean을 정의하면 자동 설정은 덮어씌워진다.

## spring-boot-starters

- 스타터(Starters)는 애플리케이션에 포함시킬 수 있는 편리한 **의존성(descriptor) 집합**입니다.
- 이를 통해 필요한 Spring 및 관련 기술을 일일이 샘플 코드에서 찾아 붙이거나 의존성을 복사/붙여넣기 할 필요가 없습니다.
- 예를 들어, Spring과 JPA를 이용한 데이터베이스 접근을 시작하고 싶다면 `spring-boot-starter-data-jpa` 의존성을 프로젝트에 추가하면 됩니다.

## spring-boot-actuator
- Actuator 엔드포인트를 사용하면 애플리케이션을 모니터링하고 상호작용할 수 있습니다.
- Spring Boot Actuator는 이러한 엔드포인트를 위한 기반 인프라를 제공합니다.
- Actuator 엔드포인트용 애너테이션 지원을 포함하고 있으며, `HealthEndpoint`, `EnvironmentEndpoint`, `BeansEndpoint` 등 다양한 엔드포인트를 제공합니다.
  - `/actuator/health` → 애플리케이션 헬스 체크
  - `/actuator/env` → 환경 변수 확인
  - `/actuator/beans` → 스프링 빈 목록 확인

## spring-boot-actuator-autoconfigure
- 이 모듈은 클래스패스 내용과 속성 집합에 기반하여 actuator 엔드포인트의 자동 설정을 제공합니다.
- 예를 들어, Micrometer가 클래스패스에 있으면 MetricsEndpoint를 자동으로 설정합니다.
- HTTP나 JMX를 통한 엔드포인트 노출을 위한 설정을 포함합니다.
- Spring Boot AutoConfigure와 마찬가지로 사용자가 직접 Bean을 정의하기 시작하면 자동 설정은 물러납니다.

## spring-boot-test
- 이 모듈은 애플리케이션을 테스트할 때 도움이 될 수 있는 핵심 항목과 애너테이션을 포함합니다.
  - 예 : `@SpringBootTest`, `@MockBean`

## spring-boot-test-autoconfigure
- 다른 Spring Boot 자동 설정 모듈과 마찬가지로, spring-boot-test-autoconfigure는 클래스패스를 기반으로 테스트를 위한 자동 설정을 제공합니다.
- 테스트하려는 애플리케이션의 일부만 자동으로 구성할 수 있는 많은 애너테이션을 포함합니다.
  - 예 : `@WebMvcTest`, `@DataJpaTest` 등을 통해 전체 컨텍스트를 띄우지 않고 필요한 부분만 테스트 가능.

## spring-boot-loader
- Spring Boot Loader는 `java -jar`를 사용하여 실행할 수 있는 단일 jar 파일을 빌드할 수 있게 해주는 비밀 소스(secret sauce)를 제공합니다.
  - Fat JAR (모든 의존성 포함 JAR)을 만들어서 독립 실행 가능.
- 일반적으로는 spring-boot-loader를 직접 사용할 필요는 없으며, 대신 Gradle이나 Maven 플러그인과 함께 사용합니다.

## spring-boot-devtools
- spring-boot-devtools 모듈은 자동 재시작과 같은 추가 개발 시 기능을 제공하여 원활한 애플리케이션 개발 경험을 제공합니다.
- 이 개발자 도구는 완전히 패키징된 애플리케이션을 실행할 때는 자동으로 비활성화됩니다.

정리하면, Spring Boot는 위 모듈들이 조합되어:
- 실행(boot, loader)
- 자동 설정(autoconfigure)
- 의존성 관리(starters)
- 운영(actuator)
- 테스트(test)
- 개발 편의(devtools)

까지 전 과정(개발–운영–테스트–배포)을 지원하는 풀 패키지 프레임워크이다.

## 스프링 부트로 개발한다는 것 ?
---

### Spring Boot 없이 Spring MVC + Spring Data JPA 사용

```xml
<dependencies>
    <!-- Spring Web MVC -->
    <dependency>
        <groupId>org.springframework</groupId>
        <artifactId>spring-webmvc</artifactId>
        <version>5.3.32</version>
    </dependency>

    <!-- Spring Data JPA -->
    <dependency>
        <groupId>org.springframework.data</groupId>
        <artifactId>spring-data-jpa</artifactId>
        <version>2.7.18</version>
    </dependency>

    <!-- Hibernate (JPA 구현체) -->
    <dependency>
        <groupId>org.hibernate</groupId>
        <artifactId>hibernate-core</artifactId>
        <version>5.6.15.Final</version>
    </dependency>

    <!-- MySQL Driver -->
    <dependency>
        <groupId>mysql</groupId>
        <artifactId>mysql-connector-java</artifactId>
        <version>8.0.33</version>
    </dependency>
</dependencies>
```

```java
@Configuration
@EnableTransactionManagement
@EnableJpaRepositories(basePackages = "com.example.repo")
@ComponentScan(basePackages = "com.example")
public class AppConfig {

    @Bean
    public DataSource dataSource() {
        DriverManagerDataSource ds = new DriverManagerDataSource();
        ds.setDriverClassName("com.mysql.cj.jdbc.Driver");
        ds.setUrl("jdbc:mysql://localhost:3306/testdb");
        ds.setUsername("root");
        ds.setPassword("1234");
        return ds;
    }

    @Bean
    public LocalContainerEntityManagerFactoryBean entityManagerFactory() {
        LocalContainerEntityManagerFactoryBean emf = new LocalContainerEntityManagerFactoryBean();
        emf.setDataSource(dataSource());
        emf.setPackagesToScan("com.example.entity");
        emf.setJpaVendorAdapter(new HibernateJpaVendorAdapter());
        return emf;
    }

    @Bean
    public PlatformTransactionManager transactionManager(EntityManagerFactory emf) {
        return new JpaTransactionManager(emf);
    }
}
```

```java
@Configuration
@EnableWebMvc
public class WebConfig implements WebMvcConfigurer {

    // JSON MessageConverter 수동 등록
    @Override
    public void configureMessageConverters(List<HttpMessageConverter<?>> converters) {
        converters.add(new MappingJackson2HttpMessageConverter());
    }

    // 뷰 리졸버 (JSP 예시)
    @Bean
    public InternalResourceViewResolver viewResolver() {
        InternalResourceViewResolver resolver = new InternalResourceViewResolver();
        resolver.setPrefix("/WEB-INF/views/");
        resolver.setSuffix(".jsp");
        return resolver;
    }
}
```

```java
public interface UserRepository extends JpaRepository<User, Long> {
}
```

```java
@Entity
public class User {
    @Id @GeneratedValue
    private Long id;
    private String name;
}
```

```java
@RestController
public class UserController {
    @Autowired
    private UserRepository repo;

    @PostMapping("/users")
    public String addUser(@RequestBody User user) {
        repo.save(user);
        return "saved";
    }

    @GetMapping("/users")
    public List<User> getUsers() {
        return repo.findAll();
    }
}
```

- DB 연결, EntityManagerFactory, TransactionManager, JSON MessageConverter, ViewResolver 등 전부 직접 Bean으로 등록해야 함.
- 실행도 WAR 파일 만들어서 외부 Tomcat 같은 WAS에 배포해야 함.

### Spring Boot 사용

```xml
<dependencies>
    <!-- Spring Boot Starter Web (MVC + Jackson + 내장 톰캣) -->
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-web</artifactId>
    </dependency>

    <!-- Spring Boot Starter Data JPA (Spring Data JPA + Hibernate) -->
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-data-jpa</artifactId>
    </dependency>

    <!-- MySQL Driver -->
    <dependency>
        <groupId>mysql</groupId>
        <artifactId>mysql-connector-j</artifactId>
    </dependency>
</dependencies>
```

```properties
# application.properties
spring.datasource.url=jdbc:mysql://localhost:3306/testdb
spring.datasource.username=root
spring.datasource.password=1234

spring.jpa.hibernate.ddl-auto=update
spring.jpa.show-sql=true
```

```java
@SpringBootApplication
public class Application {
    public static void main(String[] args) {
        SpringApplication.run(Application.class, args);
    }
}
```

```java
// UserRepository, User Entity, UserController는 동일하게 작성
```

- spring-boot-starter-data-jpa 덕분에 DataSource, EntityManager, TxManager 자동 설정
- spring-boot-starter-web 덕분에 DispatcherServlet, JSON 변환기(Jackson), 내장 톰캣 자동 설정
- 실행은 mvn spring-boot:run 또는 java -jar app.jar


| Spring Boot 핵심 개념                              | Spring                                               | Spring Boot                                                       | 차이 포인트                                                 |
| ---------------------------------------------- | ---------------------------------------------------------------- | --------------------------------------------------------------------------- | ------------------------------------------------------ |
| **1. Convention over Configuration (관습 > 설정)** | DispatcherServlet, ViewResolver, MessageConverter를 개발자가 전부 수동 등록 | `spring-boot-starter-web`으로 자동 구성 (DispatcherServlet, Jackson, 정적 리소스 매핑 등) | **흔히 쓰는 관례적 설정을 Boot가 자동 제공 → 개발자는 설정 대신 비즈니스 로직에 집중** |
| **2. Opinionated Defaults (권장 기본값)**           | DataSource 풀, Hibernate 옵션, 로깅 설정 등 개발자가 선택                      | HikariCP(커넥션풀), Logback, UTF-8, Hibernate ddl-auto 등 합리적인 기본값 제공            | **실무에서 검증된 “좋은 선택지”를 기본값으로 지정해줌**                      |
| **3. Auto-Configuration (자동 설정)**              | DataSource, EntityManagerFactory, TransactionManager 직접 Bean 등록  | `spring.datasource.*`, `spring.jpa.*` 프로퍼티만 작성 → 자동 Bean 등록                 | **클래스패스 기반 자동 설정 → Bean 수동 설정 필요 최소화**                 |
| **4. Standalone Application (독립 실행형)**         | WAR 빌드 후 외부 Tomcat 같은 WAS에 배포해야 실행 가능                            | 내장 Tomcat/Jetty 포함 → `java -jar` 한 줄로 실행                                    | **운영 환경에서 바로 실행 가능한 독립 실행형 애플리케이션**                    |
| **5. Production-ready Features (운영 친화 기능)**    | 운영 모니터링/헬스체크 기능 없음 → 직접 구현해야 함                                   | `spring-boot-starter-actuator` 추가만 하면 `/actuator/health`, `/metrics` 등 제공   | **운영 환경에서 필요한 기능(헬스체크, 메트릭, 로그관리)을 내장**                |


## 참고 자료
- [https://github.com/spring-projects/spring-boot/wiki](https://github.com/spring-projects/spring-boot/wiki)
- [https://docs.spring.io/spring-boot/index.html](https://docs.spring.io/spring-boot/index.html)
- [https://github.com/spring-projects/spring-boot](https://github.com/spring-projects/spring-boot)
