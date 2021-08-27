---
title: 간단한 DI 컨테이너 구현해보기
date: 2021-04-09 22:25:00 +0900
categories: [개발 일기]
tags: [Spring, DI Container] # TAG names should always be lowercase
---

*※ 순수 자바코드로 간단한 스프링 DI 컨테이너를 구현해보면서 DI의 필요성, 스프링 컨테이너 동작 원리 등을 이해해보기 위해 진행해본 토이 프로젝트* <br><br>
※ [구현코드 repository](https://github.com/zz9z9/my-di-container)

# DI(Dependency Injection) Container란 ?
---
- 애플리케이션에서 사용하는 객체들을 생성하고 *<u>객체들 간의 의존관계 주입</u>*, 객체의 생명주기 관리 등을 담당하는 주체
- 스프링 DI 컨테이너는 의존관계 주입 이외에도 매우 많은 역할을 수행한다.

# 의존성(의존관계) 주입이란 ?
---
> 호출할 객체를 직접 선언하는게 아니라 **<u>런타임시 외부에서 주입</u>**해주는 것

- DI가 가능한 이유는 구체적인 객체가 아닌 인터페이스에 의존하기 때문이다.
- *따라서, 객체 간의 의존관계를 정적인 클래스 관계에서는 알 수 없다.*

```java
public class CustomerServiceImpl implements CustomerService {
    // 인터페이스에 의존
    private final CustomerRepository customerRepository;

    // 런타임시 외부에서 주입
    public CustomerServiceImpl(CustomerRepository customerRepository) {
        this.customerRepository = customerRepository;
    }
```

# 의존성(의존관계) 주입이 필요한 이유
---
> *DIP, SRP, OCP를 지킨 좋은 설계를 가능하게 해준다. 이를 통해, 변화에 유연하게 대처할 수 있다.*

- DIP(Dependency Inversion Principle) : 추상화에 의존해야지, 구체화에 의존하면 안된다.
- SRP(Single Responsibility Principle) : 한 클래스는 하나의 책임만 가져야 한다.
- OCP(Open Closed Principle) : 소프트웨어 요소는 확장에는 열려 있으나 변경에는 닫혀 있어야 한다.
- 만약, 다음과 같은 코드에서 인메모리 DB를 사용하는 TemporaryCustomerRepository를 RDB를 사용하는 구현체로 바꿔야한다고 했을 때 어떤 문제가 있을지 살펴보자
  - `CustomerServiceImpl`이 `TemporaryCustomerRepository()` 라는 구체적인 객체에 의존하고 있다 <br> (DIP 위반)
  - 따라서 구현체를 변경하려면 `TemporaryCustomerRepository()` 를 새로운 구현체로 변경해줘야 한다 <br> (OCP 위반)
  - `CustomerServiceImpl`의 책임은 비즈니스 로직을 수행하는 것인데, 구체적인 구현체까지 결정하고 있다 <br> (SRP 위반)

```java
public class CustomerServiceImpl implements CustomerService {

    private final CustomerRepository customerRepository = new TemporaryCustomerRepository();

    @Override
    public void join(Customer customer) {
        customerRepository.save(customer.getId(), customer);
    }
```
- 반면, 맨 처음 살펴봤던 의존관계 주입 코드의 경우
  - `CustomerRepository`라는 인터페이스에만 의존한다 (DIP)
  - 따라서 다른 구현체로 변경해야 하는 경우 해당 코드에 변경사항은 없다 (OCP)
  - `CustomerRepository`의 구현체는 런타임시 외부에서 주입해주고 `CustomerServiceImpl`클래스는 비즈니스 로직만 수행한다 (SRP)
```java
public class CustomerServiceImpl implements CustomerService {
    // 인터페이스에 의존
    private final CustomerRepository customerRepository;

    // 런타임시 외부에서 주입
    public CustomerServiceImpl(CustomerRepository customerRepository) {
        this.customerRepository = customerRepository;
    }
```

# 구현해보기
---

*※ 구현하면서 스스로 했던 질문들을 적어봤습니다*

## 1. AppConfig 클래스 활용하여 컨테이너에 빈 등록하기
- 빈으로 등록하기 위해 AppConfig에 선언한 다양한 메서드의 이름, 리턴타입, 실제 구현체를 어떻게 가져오지 ?
   - reflection, 제네릭에 대해 공부
- 빈을 담아두는 자료 구조는 뭐가 좋을까 ?
  - 빈 이름/클래스 타입 or 클래스 타입 or 빈 이름으로 원하는 객체를 가져올 수 있어야 한다
  - 2개의 Map을 활용해서 (빈 이름 - 인스턴스) 쌍과 (타입 - 빈 이름 리스트) 쌍 만든다.
  - 두 번째 Map에서 value가 리스트인 이유는 타입이 같은 빈이 여러 개인 경우도 있기 때문에
  - 결과적으로 타입으로만 조회하는 경우 해당 타입의 빈 이름을 가져와서 그 이름으로 첫 번째 Map에서 인스턴스를 얻어올 수 있다.
- 컨테이너 클래스의 의존 관계는 어떤식으로 구성 하는게 좋을까 ?
  - 현재는 빈을 등록하고 조회하는 기능 위주의 컨테이너이지만 다른 기능의 확장성을 고려해서 Container 인터페이스에 기능별로 인터페이스를 상속하는게 좋을 것 같다

```java
  public interface BeanManagement {
      void registerBeans(Class<?>... clazz);

      Object getBean(String beanName) throws NoSuchBeanDefinitionException;

      <T> T getBean(String beanName, Class<T> beanType) throws NoSuchBeanDefinitionException;

      <T> T getBean(Class<T> beanType) throws NoUniqueBeanDefinitionException;

      String[] getBeanDefinitionNames();

      int getBeanDefinitionCount();
  }
```
```java
  public interface Container extends BeanManagement, 추가적인 기능들... {

  }
```
```java
  public class MyContainer implements Container {
       ...
  }
```

- 실제 스프링의 ApplicationContext도 아래와 같이 되어있었다.

```java
public interface ApplicationContext extends EnvironmentCapable, ListableBeanFactory, HierarchicalBeanFactory,
		MessageSource, ApplicationEventPublisher, ResourcePatternResolver {
```

## 2. 의존관계 주입 방식 결정하기
> 생성자를 통한 의존관계 주입방식으로 결정

### 수정자(setter)를 통한 의존관계 주입 방식
- public 으로 set메서드를 선언해야 하기 때문에 추후에 실수로라도 변경될 가능성이 있음
- 실수로 의존성 주입을 해주지 않으면 런타임시 NPE 발생할 수 있다.

### 생성자를 통한 의존관계 주입 방식
- 인스턴스 변수를 final로 선언할 수 있기 때문에 객체가 주입되고 나면 불변이다.
- 대부분의 의존관계는 애플리케이션 종료 전까지 불변해야하므로 불변이 보장되어야 한다.
- final로 선언한 변수에 대해 생성자에서 초기화를 하지 않으면 컴파일 오류가 나기 때문에 주입하지 않는 실수를 범할 일이 없다.
- [스프링 공식 문서](https://docs.spring.io/spring-framework/docs/5.0.3.RELEASE/spring-framework-reference/core.html#beans-setter-injection) 에서도 생성자를 통한 주입방식 권장<br>
> <q>The Spring team generally advocates constructor injection as it enables one to implement application components
> as immutable objects and to ensure that required dependencies are not null.
> Furthermore constructor-injected components are always returned to client (calling) code in a fully initialized state.
> As a side note, a large number of constructor arguments is a bad code smell,
> implying that the class likely has too many responsibilities and should be refactored to better address proper separation of concerns.</q>

## 3. 빈을 싱글톤 객체로 만들기
### 모든 구현체 클래스에 싱글톤 패턴 적용
 - boilerplate 코드가 만들어진다.
 - 싱글톤 패턴을 적용하면 유연성이 떨어진다(상속 불가 등)
 - 싱글톤으로 생성되는 객체는 구현체를 내부에 선언하므로 객체간에 결합도가 높아진다.

### Config 클래스들에 공통적으로 적용될 수 있는 부모 클래스 생성
  - Container가 여러번 생성되더라도 Config에 있는 빈은 한 번만 등록될 수 있도록 static으로 선언
  - 멀티스레딩 환경에서의 동시 접근 문제를 방지하기 위해 ConcurrentHashMap 사용
  - 문제점
    - AppConfig에서 boilerplate 코드가 생긴다 (빈 있는지 체크, 없으면 객체 생성)
    - 메서드 이름이 바뀌면 beanName 변수의 값도 변경해줘야 한다.
      - 즉, 실수할 여지를 제공한다.
    - 상속 구조로 인해 AppConfig는 CommonConfig에 의존하게된다.
      - CommonConfig의 변경이 AppConfig에 영향을 줄 수 있다.

```java
public class CommonConfig {

    private static Map<String, Object> beanStore = new ConcurrentHashMap<>();
    private static Set<String> beanNames = ConcurrentHashMap.newKeySet();

    public Object getBean(String beanName) {
        return beanStore.get(beanName);
    }

    public <T> void createBean(String beanName, T instance) {
        beanStore.put(beanName, instance);
        beanNames.add(beanName);
    }

    public boolean isExist(String beanName) {
        return beanNames.contains(beanName);
    }
}
```

```java
public class AppConfig extends CommonConfig {
    public CustomerService customerService() {

        String beanName = "customerService";
        if(!isExist(beanName)) {
            CustomerService customerService = new CustomerServiceImpl(customerRepository(), plannerService());
            createBean(beanName, customerService);
        }

        return (CustomerService) getBean(beanName);
    }

    public PlannerService plannerService() {

        String beanName = "plannerService";
        if(!isExist(beanName)) {
            PlannerService plannerService = new PlannerServiceImpl(customerRepository());
            createBean(beanName, plannerService);
        }

        return (PlannerService) getBean(beanName);
    }

    public CustomerRepository customerRepository() {

        String beanName = "customerRepository";
        if(!isExist(beanName)) {
            CustomerRepository customerRepository = new TemporaryCustomerRepository();
            createBean(beanName, customerRepository);
        }

        return (CustomerRepository) getBean(beanName);
    }
}
```

## 4. 만들어진 컨테이너를 기반으로 간단한 애플리케이션 작성
![image](https://user-images.githubusercontent.com/64415489/122795277-1de1ed00-d2f8-11eb-864e-d03017122b42.png)

---

# 더 공부해야할 부분
- 스프링에서 싱글톤 객체를 보장하는 방법

# 참고 자료
- [인프런 김영한님 강의(스프링 핵심 원리 - 기본편)](https://www.inflearn.com/course/%EC%8A%A4%ED%94%84%EB%A7%81-%ED%95%B5%EC%8B%AC-%EC%9B%90%EB%A6%AC-%EA%B8%B0%EB%B3%B8%ED%8E%B8/dashboard)
- [SOLID 원칙](https://ko.wikipedia.org/wiki/SOLID_(%EA%B0%9D%EC%B2%B4_%EC%A7%80%ED%96%A5_%EC%84%A4%EA%B3%84))
