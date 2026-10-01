---
title: DTO와 Domain Model, 그리고 Entity
date: 2022-09-05 00:29:00 +0900
---

## Data Transfer Object(DTO)
---
- DTO는 단순한 데이터 컨테이너인 객체이며, 이러한 객체는 서로 다른 프로세스와 애플리케이션 계층 간에 데이터를 전달하는 데 사용된다.

## Domain Model (Domain Object)
---
- Domain Model  "domain objects", "domain entities" and "model objects" 등 일반적으로 상호 교환적으로 사용된다.
- 일반적으로 도메인 모델은 세 가지 다른 개체로 구성된다.
  - Domain Service
    - 도메인 서비스는 도메인 개념과 관련되지만 엔터티 또는 값 개체의 "자연스러운" 부분이 아닌 작업을 제공하는 상태 비저장 클래스입니다.
  - Entity
    - 엔터티는 전체 수명 주기 동안 변경되지 않고 유지되는 ID로 정의되는 개체이다.
  - VO (Value Object)
    - VO는 속성이나 사물을 묘사하며, 이러한 객체에는 고유한 ID나 수명 주기가 없다.
    - 일반적으로 VO의 수명 주기는 엔터티의 수명 주기에 바인딩된다.

## Entity 조금 더 살펴보기
---
> "Entity"라는 용어는 다양한 맥락에서 다르게 해석될 수 있다.

- 대표적으로 사용되는 문맥은 다음과 같다.
  - 엔터프라이즈 자바 및 JPA
    - 데이터베이스에서 유지 관리되는 영구 데이터를 나타내는 개체
  - 도메인 주도 설계 (Domain Driven Design by Eric Evans)
    - 속성보다는 정체성에 의해 주로 정의되는 개체
  - 클린 아키텍처 (by Robert C. Martin)
    - 전사적인 중요한 비즈니스 규칙을 캡슐화하는 개체


물론 정확한 용어를 정의하는 것도 중요하지만, 결국 필요한 역할을 생각해본다면,

- client와 맞닿아 있는 역할
  - DTO

- 도메인 내의 일을 처리하기 위한 역할
  - Domain Model, Domain Object, Model Object

- DB (data storage)에 있는 데이터를 담는 역할
  - Entity, Domain Entity


그렇다면 왜 굳이 번거롭게 각각을 구분해서 생각하게 되었을까 ?

웹 애플리케이션의 역할과 그에 따른 아키텍처를 생각해보자

## Three Layers Should Be Enough for Everybody

- 웹 애플리케이션의 책임에 대해 생각해보면, 아래와 같은 책임이 있음에 공감할 수 있을 것이다.
  - 클라이언트의 입력을 처리하고, 클라이언트에게 올바른 응답을 반환
  - 클라이언트에게 합리적인 오류 메시지를 제공하는 예외 처리 메커니즘
  - 트랜잭션 관리
  - 인증과 인가
  - 애플리케이션의 비즈니스 로직 처리
  - 데이터 저장소 및 기타 외부 리소스와 통신

- 일반적으로, 세 개의 레이어를 통해 이러한 책임을 구현할 수 있다.

<img width="1212" alt="image" src="https://user-images.githubusercontent.com/64415489/188463943-a6aeaaaf-dc21-4790-8ce3-87c299cb8abc.png">

- 이 모델은 3개의 레이어를 포함하며, 레이어의 이름은 Spring Web Application에서 해당 요소로 변경된다.

- Web Layer
  - 사용자의 입력을 처리하고 사용자에게 올바른 응답을 반환
  - 예외 처리
  - 사용자 인증 처리 및 권한이 없는 사용자에 대한 첫 번째 방어선 역할

- Service Layer
  - 트랜잭션 경계 역할
  - public API 제공
  - 트랜잭션 경계 역할
  - 권한 부여
  - 파일 시스템, 데이터베이스 또는 이메일 서버와 같은 외부 리소스와 통신

- Repository Layer
  - 사용된 데이터 저장소와 통신

## DTO, Domain Model과 Layer 연관 지어 생각해보기 - Model Mapping
- 다음으로 해야 할 일은 각 계층의 인터페이스를 설계하는 것으로, DTO(Data Transfer Object) 및 도메인 모델과 같은 용어를 접하게 되는 단계입니다.

- 이제 이 용어가 의미하는 바를 알았으므로 각 레이어의 인터페이스를 설계하고 진행할 수 있습니다.

- 웹 계층은 DTO를 처리해야 한다.

- 서비스 계층은 데이터 전송 개체(및 기본 유형)를 메서드 매개변수로 사용합니다.
  - 도메인 모델 개체를 처리할 수 있지만 데이터 전송 개체만 웹 계층으로 다시 반환할 수 있습니다.

- 저장소 계층은 엔터티(및 기본 유형)를 메서드 매개변수로 사용하고 엔터티(및 기본 유형)를 반환합니다.

- 이것은 한 가지 매우 중요한 질문을 제기한다.
  - 데이터 전송 객체가 정말로 필요한가? 엔터티와 값 개체를 웹 계층으로 다시 반환할 수 없는 이유는 무엇입니까?

- There are two reasons why this is a bad idea:

- The domain model specifies the internal model of our application.
- If we expose this model to the outside world, the clients would have to know how to use it.
- In other words, the clients of our application would have to take care of things that don’t belong to them.
- If we use DTOs, we can hide this model from the clients of our application, and provide an easier and cleaner API.

- If we expose our domain model to the outside world, we cannot change it without breaking the other stuff that depends from it.
- If we use DTOs, we can change our domain model as long as we don’t make any changes to the DTOs.

- 이것이 나쁜 생각인 데는 몇 가지 이유가 있다.
  - 1. 도메인 모델은 애플리케이션의 내부 모델을 나타내는데, 만약 이 모델을 외부 세계에 노출시킨다면, 클라이언트는 그것을 사용하는 방법을 알아야 할 것이다. 즉, 클라이언트는 자신에게 속하지 않는 것을 처리해야 합니다.  DTO를 사용하면 이 모델을 애플리케이션의 클라이언트로부터 숨길 수 있고 더 쉽고 깨끗한 API를 제공할 수 있다.
  - 2. 우리가 우리의 도메인 모델을 외부 세계에 노출시키면 그것에 의존하는 다른 것들을 깨뜨리지 않고는 그것을 변경할 수 없다. DTO를 사용하는 경우 DTO를 변경하지 않는 한 도메인 모델을 변경할 수 있습니다.

# REALITY LIKE?
- When applied in practice, there are many multitudes of situations that occur. Not just follow the pattern.

Controller receives DTO> Service converts DTO into model or entity, then processes> Repository receives Entity into DB

Repository taken from DB to Entity> Service, then processed it into DTO> Controller and returned DTO

But there are other cases such as:

Controller does not accept DTO but accepts primitive parameters such as int, float, …
Get into a DTO List
Returns a List DTO
…
Therefore, in practice one can make changes to suit the project.

The standard example is the Service will do a mapping to DTO and vice versa, the controller only accepts DTO. But sometimes to reduce the load on the service, this mapping will be done by the controller (though the controller can get bloated, while it is true that the controller must be kept thin – as little code as possible).

But either way, the general rule is that mapping is always done at the edge of code (edge). That means if the mapping in the service, the transformation should always be at the top, or at the end of the method when they are processed.

Also, to reduce the boilerplate code, we often reduce the tightness a bit if not needed. Eg:

Sometimes without a domain model , the Service can convert DTO directly to an entity .
Services can also return Entity or Model , if they are too simple and contain no sensitive info. At this time, there is no need for DTO, but the controller returns Entity or Model to avoid confusion (although it is against the principle of publicizing these two guys, but should also consider).
There is a lot of controversy about the use of DTO, as an anti pattern. Personally, I do not see that, sometimes DTO is still quite useful, and can be customized to be more suitable and effective.

- 실무에 적용하다 보면 여러 가지 상황이 발생합니다. 패턴만 따라가는 것이 아닙니다.
  - Controller는 DTO 수신 > Service는 DTO를 모델 또는 엔터티로 변환한 후 처리> Repository는 Entity를 DB로 수신

- DB에서 Entity> Service로 Repository를 가져와 DTO> Controller로 처리하고 DTO를 반환

  그러나 다음과 같은 다른 경우가 있습니다.

  컨트롤러는 DTO를 허용하지 않지만 int, float, …
  DTO 목록에 들어가기
  목록 DTO를 반환합니다.
  …
  따라서 실제로 프로젝트에 맞게 변경할 수 있습니다.

  표준 예는 서비스가 DTO에 대한 매핑을 수행하고 그 반대의 경우 컨트롤러가 DTO만 수락한다는 것입니다. 그러나 때때로 서비스의 부하를 줄이기 위해 이 매핑은 컨트롤러에서 수행됩니다(컨트롤러가 부풀려질 수 있지만 컨트롤러는 가능한 한 적은 코드로 얇게 유지해야 하는 것이 사실입니다).

  그러나 어느 쪽이든 일반적인 규칙은 매핑이 항상 코드의 가장자리(가장자리)에서 수행된다는 것입니다. 즉, 서비스의 매핑이 처리되는 경우 변환이 항상 맨 위에 있거나 메서드의 끝에 있어야 합니다.

  또한 상용구 코드를 줄이기 위해 필요하지 않은 경우 기밀성을 약간 줄입니다. 예:

  때때로 도메인 모델 없이 서비스는 DTO를 엔터티로 직접 변환할 수 있습니다.
  서비스는 너무 단순하고 민감한 정보가 포함되어 있지 않은 경우 Entity 또는 Model 을 반환할 수도 있습니다.
  - 이때 DTO는 필요하지 않지만 컨트롤러는 혼동을 피하기 위해 Entity 또는 Model을 반환합니다(이 두 사람을 공개하는 원칙에 위배되지만 고려해야 함).
  - 안티 패턴으로 DTO를 사용하는 것에 대해 많은 논란이 있습니다. 개인적으로, 때때로 DTO가 여전히 매우 유용하고 더 적합하고 효과적이도록 사용자 정의할 수 있다고 생각하지 않습니다.

# 결론
---
- 정답은 없다. 상황에 맞게 고민하고 그 때 마다 최선이라고 생각하는 선택을 하는 수밖에 ...

# 참고자료
---
-  [https://www.petrikainulainen.net/software-development/design/understanding-spring-web-application-architecture-the-classic-way/](https://www.petrikainulainen.net/software-development/design/understanding-spring-web-application-architecture-the-classic-way/)
- [https://www.linkedin.com/pulse/difference-between-entity-dto-what-use-instead-omar-ismail?trk=pulse-article_more-articles_related-content-card](https://www.linkedin.com/pulse/difference-between-entity-dto-what-use-instead-omar-ismail?trk=pulse-article_more-articles_related-content-card)
- [https://itzone.com.vn/en/article/entity-domain-model-and-dto-why-so-many/](https://itzone.com.vn/en/article/entity-domain-model-and-dto-why-so-many/)
- [https://stackoverflow.com/questions/15540147/differentiating-between-domain-model-and-entity-with-respect-to-mvc](https://stackoverflow.com/questions/15540147/differentiating-between-domain-model-and-entity-with-respect-to-mvc)
