---
title: 스프링 트랜잭션 살펴보기
date: 2024-01-10 22:25:00 +0900
---

# Synchronizing resources with transactions
## High-level synchronization approach
- The preferred approach is to use Spring’s highest level template based persistence integration APIs or to use native ORM APIs with transaction-aware factory beans or proxies for managing the native resource factories.
- These transaction-aware solutions internally handle resource creation and reuse, cleanup, optional transaction synchronization of the resources, and exception mapping.
- Thus user data access code does not have to address these tasks, but can be focused purely on non-boilerplate persistence logic.
- Generally, you use the native ORM API or take a template approach for JDBC access by using the `JdbcTemplate`.

## Low-level synchronization approach
- Classes such as DataSourceUtils (for JDBC), EntityManagerFactoryUtils (for JPA), SessionFactoryUtils (for Hibernate), PersistenceManagerFactoryUtils (for JDO), and so on exist at a lower level.
- When you want the application code to deal directly with the resource types of the native persistence APIs, you use these classes to ensure that proper Spring Framework-managed instances are obtained, transactions are (optionally) synchronized, and exceptions that occur in the process are properly mapped to a consistent API.
- For example, in the case of JDBC, instead of the traditional JDBC approach of calling the getConnection() method on the DataSource, you instead use Spring’s org.springframework.jdbc.datasource.DataSourceUtils class as follows : `Connection conn = DataSourceUtils.getConnection(dataSource);`
- **If an existing transaction already has a connection synchronized (linked) to it, that instance is returned. Otherwise, the method call triggers the creation of a new connection, which is (optionally) synchronized to any existing transaction, and made available for subsequent reuse in that same transaction.**

- As mentioned, any `SQLException` is wrapped in a Spring Framework `CannotGetJdbcConnectionException`, one of the Spring Framework’s hierarchy of unchecked `DataAccessExceptions`.
- This approach gives you more information than can be obtained easily from the `SQLException`, and ensures portability across databases, even across different persistence technologies.
- This approach also works without Spring transaction management (transaction synchronization is optional), so you can use it whether or not you are using Spring for transaction management.
- Of course, once you have used Spring’s JDBC support, JPA support or Hibernate support, you will generally prefer not to use `DataSourceUtils` or the other helper classes, because you will be much happier working through the Spring abstraction than directly with the relevant APIs.
- For example, if you use the Spring JdbcTemplate or jdbc.object package to simplify your use of JDBC, correct connection retrieval occurs behind the scenes and you won’t need to write any special code.

## 참고 자료
- https://docs.spring.io/spring-framework/docs/4.2.x/spring-framework-reference/html/transaction.html
- https://spring.academy/courses/spring-framework-essentials/lessons/agenda => 스프링 사이트에 강의도 있음 Module9에 트랜잭션 관련 내용 있음
