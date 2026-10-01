---
title: 회사 프로젝트에 테스트 코드 적용하기
date: 2021-07-10 22:25:00 +0900
---

## 이슈1
Command is too long. Shorten command line for DomainLogicTest~
==> .idea /workspace.xml에 <property name="dynamic.classpath" value="true"/> 추가

## 이슈2
[Spring Boot ConflictingBeanDefinitionException]

I had the same problem on a Spring integration test when I ran it with InteliJ.

After a refactor, one of my controller class was actually duplicate in the /out/production/classes directory which is the default output directory for Intelij since version 2017.2. Since the gradle output directory is different (It's build/classes), the gradle clean goal had no effect.

For me the solution was to manually remove /out/production/classes and re run my integration test.

For a possible durable solution not having 2 output directories see here

==> target 디렉토리 삭제해주니깐 됐다
   예전 빌드 그게 남아있는건가 ??
   애플리케이션 띄울 때 거기서 보는건가 ??

## 이슈3
//테스트 코드 작성 시 아래와 같은 에러 발생.
```
Unable to find a @SpringBootConfiguration, you need to use @ContextConfiguration or @SpringBootTest(classes=...) with your test
```

@SpringBootApplication 애노테이션이 붙은 클래스가 존재하는 패키지의 하위 패키지에 테스트를 둬야 한다는 원칙을 어긴 것이다.
예: a.b.c.Application 이라면, 테스트 클래스는 a.b.c 아래의 패키지에 존재해야한다. 만약 a.b.x 처럼 돼있는 패키지에 테스트 클래스가 존재하면 자동으로 @SpringBootApplication을 탐색하지 못한다.

==> 패키지 경로는 같음, 위 문제 때문은 아닌듯
==> pcmApp 처럼 @EnableAutoConfiguration 붙여주니깐 됐따
   이게 머지 ???

----
### @EnableAutoConfiguration

메인 클래스에 붙어 있는 @SpringBootApplication은 크게 3가지가 합쳐진 것이라고 생각할 수 있다.
1. @SpringBootConfiguration
2. @ComponentScan
3. @EnableAutoConfiguration

@SpringBootApplication 내부에 있는 @ComponentScan은 subpakage만 스캔한다.
@SpringBootApplication does is a component scan. But, it only scans on sub-packages. i.e. if you put that class in com.mypackage, then it will scan for all classes in

- 스프링 부트 어플리케이션은 Bean을 2번 등록한다. 처음에 ComponentScan으로 등록하고,
그 후에 EnableAutoConfiguration으로 추가적인 Bean들을 읽어서 등록한다.

@EnableAutoConfiguration
AutoConfiguration은 결국 Configuration이다. 즉, Bean을 등록하는 자바 설정 파일이다.

spring.factories 내부에 여러 Configuration 들이 있고, 조건에 따라 Bean을 등록한다.

따라서 메인 클래스(@SpringBootApplication)를 실행하면, @EnableAutoConfiguration에 의해 spring.factories 안에 들어있는 수많은 자동 설정들이 조건에 따라 적용이 되어 수 많은 Bean들이 생성되고,
스프링 부트 어플리케이션이 실행되는 것이다.

중요한 것은 @EnableAutoConfiguration인데 @EnableAutoConfiguration은 spring.factories 라는 스프링부트의 meta 파일을 읽어서,
미리 정의되어 있는 자바 설정 파일(@Configuration)들을 빈으로 등록하는 역할을 수행한다.
spring.factories는 spring-boot-autoconfigure 프로젝트의 META-INF안에 들어있다.

==> 메이븐 디펜던시에 추가된 spring-boot-autoconfigure jar 파일 들어가보면 있음


그리고 intellij에서 빨간줄로 Attributes should be specified via @SpringBootApplication이라고 나온다

- https://velog.io/@max9106/Spring-Boot-EnableAutoConfiguration
- https://cornswrold.tistory.com/314

## 이슈4
@SpringBootTest 붙여서 하면 너무 느리다 ,, 모든 의존성 다 관리해야돼서 ??

SpringBootTest 너무 느려요??
개발하고 있는 프로젝트가 커져 빈이 많아지면, 당연히 IoC컨테이너에 빈을 등록하는데 오랜 시간이 걸린다. ( 뜨는데 2~5초인데 그것도 못참아? 라고 하시는 분들은 테스트 코드를 많이 돌리지 않거나 테스트 코드가 프로젝트에 많지 않아서 일것이다. 이 2~5초차이가 상당히 크다고 생각한다. )



그래서 내가 원하는 빈만을 등록하려면 어떻게 해야할까?

SpringBootTest 어노테이션에 원하는 class 등록하기
EnableConfigurationProperties 어노테이션에 원하는 Configuration 빈 적어주기

@SpringBootTest(classes = {StayGolfOrderServiceImpl.class, StayGolfApiServiceConfiguration.class})
@EnableConfigurationProperties(StayGolfConfiguration.class)

## 이슈5
- 단위 테스트의 어려움
  - 비즈니스 로직이 대부분 다른 서비스 테이블 변경하고 이벤트 발행하는 부분이 많아서, 실제 디펜던시들을 띄워야한다.
    - 띄우려면, application.yml도 필요 ??
  - 내 서비스 테이블의 데이터를 바꾸는거면, 관련 디펜던시를 목 객체로 처리해서 항상 기대한 값을 리턴하게 하면 될텐데...


## 이슈6
```
java.lang.IllegalStateException : Could not locate PropertySource and the fail fast property is set, failing
```

config 서버 ??
bootstrap.yml vs application.yml

I have just asked the Spring Cloud guys and thought I should share the info I have here.

bootstrap.yml is loaded before application.yml.

It is typically used for the following:

when using Spring Cloud Config Server, you should specify spring.application.name and spring.cloud.config.server.git.uri inside bootstrap.yml
some encryption/decryption information
Technically, bootstrap.yml is loaded by a parent Spring ApplicationContext. That parent ApplicationContext is loaded before the one that uses application.yml.



bootstrap.yml or bootstrap.properties
It's only used/needed if you're using Spring Cloud and your application's configuration is stored on a remote configuration server (e.g. Spring Cloud Config Server).

From the documentation:

A Spring Cloud application operates by creating a "bootstrap" context, which is a parent context for the main application. Out of the box it is responsible for loading configuration properties from the external sources, and also decrypting properties in the local external configuration files.

Note that the bootstrap.yml or bootstrap.properties can contain additional configuration (e.g. defaults) but generally you only need to put bootstrap config here.

Typically it contains two properties:

location of the configuration server (spring.cloud.config.uri)
name of the application (spring.application.name)
Upon startup, Spring Cloud makes an HTTP call to the config server with the name of the application and retrieves back that application's configuration.

application.yml or application.properties
Contains standard application configuration - typically default configuration since any configuration retrieved during the bootstrap process will override configuration defined here


Anatoly above sums it pretty clearly and nicely as to what you need to do. If you are looking for a quick and dirty test try changing the hostnames from http://config:8888 to http://localhost:8888 in the bootstrap.yml files, for the service you are trying to run.



Setting failsafe to false will just not throw the exception , this is something I would not recommend since this means even if you are not connected to your config server and unable to fetch the configuration your application will run which leads to an uncertain behavior (since you do not know where your properties are loaded), always better to fail fast. The original cause of the problem is an exception or failing during fetching the remote environment from your config server, probably a timeout issue.


If you build and run project modules manually (e.g. from IDE) you should rename all "config" hostnames in bootstrap.yml files to "localhost".


## 이슈7
```
The bean 'com.posco.mes3.m0ac21.client.GenealogyClient.FeignClientSpecification' could not be registered.
A bean with that name has already been defined and overriding is disabled
```
- 다른곳에서 이미 해당 bean을 생성해서 중복이 되는현상
  - GenealogyClient가 GenealogyDelegator에도 있고, CommonResultDelegator에도 있다

### 해결방법
- 둘 중에 한 곳에만 선언하거나, allow-bean-definition-overriding true로 세팅해준다
```yaml
spring:
    main:
      allow-bean-definition-overriding: true
```


## 이슈8
```
Failed to configure a DataSource: 'url' attribute is not specified and no embedded datasource could be configured.
Reason: Failed to determine a suitable driver class

Action:
Consider the following:
If you want an embedded database (H2, HSQL or Derby), please put it on the classpath.
If you have database settings to be loaded from a particular profile you may need to activate it (no profiles are currently active).
```

## 이슈9
Could not resolve placeholder 'activeProperties' in value "${activatedProperties}"



