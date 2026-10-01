
## QueryDSL ?
---

> Querydsl is a framework which enables the construction of type-safe SQL-like queries for multiple backends including JPA, MongoDB and SQL in Java.
> Instead of writing queries as inline strings or externalizing them into XML files they are constructed via a fluent API.


### JPA와의 관계 ?

- Querydsl for JPA is an alternative to both JPQL and Criteria queries. It combines the dynamic nature of Criteria queries with the expressiveness of JPQL and all that in a fully typesafe manner.

- JPA 자체는 데이터를 조회할 때 보통 JPQL(Java Persistence Query Language) 을 사용
- 예를 들어:

```java
TypedQuery<Member> query = em.createQuery("select m from Member m where m.grade = :grade", Member.class);
query.setParameter("grade", "GOLD");
List<Member> result = query.getResultList();
```

- 문자열 기반이라서:
  - 오타 나도 컴파일 에러가 안 남
  - 필드명 변경 시 IDE refactor 불가
  - 조건이 많아지면 동적 쿼리 조합이 어려움

- QueryDSL을 사용하면 위 쿼리를 이렇게 바꿉니다

```java
QMember m = QMember.member;

List<Member> result = queryFactory
    .selectFrom(m)
    .where(m.grade.eq("GOLD"))
    .fetch();
```

즉, QueryDSL은 JPA를 대체하는 프레임워크가 아니라, JPA 위에서 작동하는 타입 안전한(type-safe) 쿼리 빌더


```
┌────────────────────────────────────┐
│           Your Application         │
│  (Service / Repository Layer)      │
└────────────────────────────────────┘
                 │
                 ▼
┌────────────────────────────────────┐
│          QueryDSL (JPAQuery)       │
│  - 타입 안전한 쿼리 빌더                │
│  - JPQL 동적 생성                    │
└────────────────────────────────────┘
                 │
                 ▼
┌────────────────────────────────────┐
│            JPA API                 │
│  - EntityManager                   │
│  - Query, TypedQuery               │
└────────────────────────────────────┘
                 │
                 ▼
┌────────────────────────────────────┐
│      JPA 구현체 (예: Hibernate)      │
│  - 실제 SQL 생성 및 실행               │
│  - 영속성 컨텍스트 관리                 │
└────────────────────────────────────┘
```

### QEntity ?
> QMember :	QueryDSL이 빌드 시 생성한 JPA 엔티티의 메타모델 클래스

## QueryDSL 사용해보기
---
> To create queries with Querydsl you need to instantiate variables and Query implementations. We will start with the variables.

```xml
<dependency>
  <groupId>com.querydsl</groupId>
  <artifactId>querydsl-apt</artifactId>
  <version>${querydsl.version}</version>
  <scope>provided</scope>
</dependency>

<dependency>
  <groupId>com.querydsl</groupId>
  <artifactId>querydsl-jpa</artifactId>
  <version>${querydsl.version}</version>
</dependency>
```

```xml
<project>
  <build>
  <plugins>
    ...
    <plugin>
      <groupId>com.mysema.maven</groupId>
      <artifactId>apt-maven-plugin</artifactId>
      <version>1.1.3</version>
      <executions>
        <execution>
          <goals>
            <goal>process</goal>
          </goals>
          <configuration>
            <outputDirectory>target/generated-sources/java</outputDirectory>
            <processor>com.querydsl.apt.jpa.JPAAnnotationProcessor</processor>
          </configuration>
        </execution>
      </executions>
    </plugin>
    ...
  </plugins>
  </build>
</project>
```

- The JPAAnnotationProcessor finds domain types annotated with the javax.persistence.Entity annotation and generates query types for them.
- If you use Hibernate annotations in your domain types you should use the APT processor com.querydsl.apt.hibernate.HibernateAnnotationProcessor instead.
- Run clean install and you will get your Query types generated into target/generated-sources/java.


```java
@Entity
public class Customer {
    private String firstName;
    private String lastName;

    public String getFirstName() {
        return firstName;
    }

    public String getLastName() {
        return lastName;
    }

    public void setFirstName(String fn) {
        firstName = fn;
    }

    public void setLastName(String ln) {
        lastName = ln;
    }
}
```


Querydsl will generate a query type with the simple name QCustomer into the same package as Customer. QCustomer can be used as a statically typed variable in Querydsl queries as a representative for the Customer type.

QCustomer has a default instance variable which can be accessed as a static field:

QCustomer customer = QCustomer.customer;
Alternatively you can define your own Customer variables like this:

QCustomer customer = new QCustomer("myCustomer");
2.1.6. Querying
The Querydsl JPA module supports both the JPA and the Hibernate API.

To use the JPA API you use JPAQuery instances for your queries like this:

// where entityManager is a JPA EntityManager
JPAQuery<?> query = new JPAQuery<Void>(entityManager);
If you are using the Hibernate API instead, you can instantiate a HibernateQuery like this:

// where session is a Hibernate session
HibernateQuery<?> query = new HibernateQuery<Void>(session);
Both JPAQuery and HibernateQuery implement the JPQLQuery interface.

For the examples of this chapter the queries are created via a JPAQueryFactory instance. JPAQueryFactory should be the preferred option to obtain JPAQuery instances.

For the Hibernate API HibernateQueryFactory can be used

To retrieve the customer with the first name Bob you would construct a query like this:

QCustomer customer = QCustomer.customer;
Customer bob = queryFactory.selectFrom(customer)
.where(customer.firstName.eq("Bob"))
.fetchOne();
The selectFrom call defines the query source and projection, the where part defines the filter and fetchOne tells Querydsl to return a single element. Easy, right?

To create a query with multiple sources you use the query like this:

QCustomer customer = QCustomer.customer;
QCompany company = QCompany.company;
query.from(customer, company);
And to use multiple filters use it like this

queryFactory.selectFrom(customer)
.where(customer.firstName.eq("Bob"), customer.lastName.eq("Wilson"));
Or like this

queryFactory.selectFrom(customer)
.where(customer.firstName.eq("Bob").and(customer.lastName.eq("Wilson")));
In native JPQL form the query would be written like this:

select customer from Customer as customer
where customer.firstName = "Bob" and customer.lastName = "Wilson"
If you want to combine the filters via "or" then use the following pattern

queryFactory.selectFrom(customer)
.where(customer.firstName.eq("Bob").or(customer.lastName.eq("Wilson")));
2.1.7. Using joins
Querydsl supports the following join variants in JPQL: inner join, join, left join and right join. Join usage is typesafe, and follows the following pattern:

QCat cat = QCat.cat;
QCat mate = new QCat("mate");
QCat kitten = new QCat("kitten");
queryFactory.selectFrom(cat)
.innerJoin(cat.mate, mate)
.leftJoin(cat.kittens, kitten)
.fetch();
The native JPQL version of the query would be

select cat from Cat as cat
inner join cat.mate as mate
left outer join cat.kittens as kitten
Another example

queryFactory.selectFrom(cat)
.leftJoin(cat.kittens, kitten)
.on(kitten.bodyWeight.gt(10.0))
.fetch();
With the following JPQL version

select cat from Cat as cat
left join cat.kittens as kitten
on kitten.bodyWeight > 10.0
2.1.8. General usage
Use the the cascading methods of the JPQLQuery interface like this

select: Set the projection of the query. (Not necessary if created via query factory)

from: Add the query sources here.

innerJoin, join, leftJoin, rightJoin, on: Add join elements using these constructs. For the join methods the first argument is the join source and the second the target (alias).

where: Add query filters, either in varargs form separated via commas or cascaded via the and-operator.

groupBy: Add group by arguments in varargs form.

having: Add having filters of the "group by" grouping as an varags array of Predicate expressions.

orderBy: Add ordering of the result as an varargs array of order expressions. Use asc() and desc() on numeric, string and other comparable expression to access the OrderSpecifier instances.

limit, offset, restrict: Set the paging of the result. Limit for max results, offset for skipping rows and restrict for defining both in one call.

2.1.9. Ordering
The syntax for declaring ordering is

QCustomer customer = QCustomer.customer;
queryFactory.selectFrom(customer)
.orderBy(customer.lastName.asc(), customer.firstName.desc())
.fetch();
which is equivalent to the following native JPQL

select customer from Customer as customer
order by customer.lastName asc, customer.firstName desc
2.1.10. Grouping
Grouping can be done in the following form

queryFactory.select(customer.lastName).from(customer)
.groupBy(customer.lastName)
.fetch();
which is equivalent to the following native JPQL

select customer.lastName
from Customer as customer
group by customer.lastName
2.1.11. Delete clauses
Delete clauses in Querydsl JPA follow a simple delete-where-execute form. Here are some examples:

QCustomer customer = QCustomer.customer;
// delete all customers
queryFactory.delete(customer).execute();
// delete all customers with a level less than 3
queryFactory.delete(customer).where(customer.level.lt(3)).execute();
The where call is optional and the execute call performs the deletion and returns the amount of deleted entities.

DML clauses in JPA don't take JPA level cascade rules into account and don't provide fine-grained second level cache interaction.

2.1.12. Update clauses
Update clauses in Querydsl JPA follow a simple update-set/where-execute form. Here are some examples:

QCustomer customer = QCustomer.customer;
// rename customers named Bob to Bobby
queryFactory.update(customer).where(customer.name.eq("Bob"))
.set(customer.name, "Bobby")
.execute();
The set invocations define the property updates in SQL-Update-style and the execute call performs the Update and returns the amount of updated entities.

DML clauses in JPA don't take JPA level cascade rules into account and don't provide fine-grained second level cache interaction.

2.1.13. Subqueries
To create a subquery you use the static factory methods of JPAExpressions and define the query parameters via from, where etc.

QDepartment department = QDepartment.department;
QDepartment d = new QDepartment("d");
queryFactory.selectFrom(department)
.where(department.size.eq(
JPAExpressions.select(d.size.max()).from(d)))
.fetch();
Another example

QEmployee employee = QEmployee.employee;
QEmployee e = new QEmployee("e");
queryFactory.selectFrom(employee)
.where(employee.weeklyhours.gt(
JPAExpressions.select(e.weeklyhours.avg())
.from(employee.department.employees, e)
.where(e.manager.eq(employee.manager))))
.fetch();
2.1.14. Exposing the original query
If you need to tune the original Query before the execution of the query you can expose it like this:

Query jpaQuery = queryFactory.selectFrom(employee).createQuery();
// ...
List results = jpaQuery.getResultList();




## 참고 자료
---
- [https://github.com/querydsl/querydsl](https://github.com/querydsl/querydsl)
- [http://querydsl.com/static/querydsl/latest/reference/html/ch02.html#jpa_integration](http://querydsl.com/static/querydsl/latest/reference/html/ch02.html#jpa_integration)
