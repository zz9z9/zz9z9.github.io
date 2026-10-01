
## Reactive ?
- "리액티브(reactive)"라는 용어는 **변화에 반응하는 것**을 중심으로 구성된 프로그래밍 모델을 의미합니다.
- 예를 들어, 네트워크 구성 요소가 I/O 이벤트에 반응하거나, UI 컨트롤러가 마우스 이벤트에 반응하는 것 등이 이에 해당합니다.
- 그런 의미에서, 논블로킹(non-blocking)은 리액티브하다고 볼 수 있습니다.
  - 왜냐하면 블로킹 상태에 머무는 대신, **작업이 완료되거나 데이터가 사용 가능해질 때 알림에 반응하는 방식으로 전환**되기 때문입니다.

- 리액티브 프로세싱은 개발자가 비동기적이고 논블로킹(non-blocking) 애플리케이션을 구축할 수 있게 해주는 ***패러다임***으로, 플로우 제어(백프레셔)를 처리할 수 있습니다.

- 개발자들이 블로킹 코드를 논블로킹 코드로 전환하는 주요 이유 중 하나는 효율성입니다.

- 리액티브 코드는 더 적은 리소스로 더 많은 작업을 수행합니다.
- 리액티브 시스템은 현대 프로세서를 더 잘 활용합니다.
- 또한, 리액티브 프로그래밍에서 백프레셔를 포함하면 분리된 컴포넌트 간의 복원력을 강화할 수 있습니다.

## Reactive Streams
> https://www.reactive-streams.org/

- Reactive Streams는 **논블로킹 백프레셔(non-blocking back pressure)** 를 지원하는 비동기 스트림 처리를 위한 표준을 제공하려는 이니셔티브입니다.
- 이는 런타임 환경(JVM 및 JavaScript)과 네트워크 프로토콜을 포함한 다양한 영역에서의 노력을 포괄합니다.

* 이니셔티브 : (특정한 문제의 해결・목적 달성을 위한 새로운) 계획

- Reactive Streams는 상호운용성(interoperability)에서 중요한 역할을 합니다. Reactive Streams는 라이브러리나 인프라 구성 요소에는 유용하지만, 애플리케이션 API로는 적합하지 않은 경우가 많습니다. 그 이유는 Reactive Streams가 너무 저수준(low-level)이기 때문입니다.

- 애플리케이션에서는 비동기 로직을 구성하기 위해 더 높은 수준의 풍부하고 함수형인 API가 필요합니다. 이는 Java 8의 Stream API와 유사하지만, 컬렉션에만 국한되지 않는 기능을 제공합니다. 이러한 역할은 리액티브 라이브러리가 수행합니다.

## Project Reactor
> 공식 사이트 : https://projectreactor.io/
> https://github.com/reactor/reactor

- **Reactor는 Reactive Streams 사양에 기반을 둔 4세대 리액티브 라이브러리**로, JVM에서 논블로킹 애플리케이션을 구축하기 위해 설계되었습니다.
  - 4세대 리액티브 라이브러리: 이전 세대의 리액티브 라이브러리(RxJava와 같은 것들)에서 얻은 교훈과 기술 발전을 바탕으로 개발된 최신 리액티브 라이브러리

- Project Reactor is a fully non-blocking foundation with back-pressure support included.
- It’s the foundation of the reactive stack in the Spring ecosystem and is featured in projects such as Spring WebFlux, Spring Data, and Spring Cloud Gateway.

- Reactor는 Spring WebFlux에서 선택된 리액티브 라이브러리로, Mono와 Flux API 타입을 제공합니다.
- Mono는 01개의 데이터 시퀀스, Flux는 0N개의 데이터 시퀀스를 처리하며, ReactiveX 연산자 어휘에 맞춘 풍부한 연산자 세트를 갖추고 있습니다. Reactor는 Reactive Streams 라이브러리이므로, 모든 연산자는 논블로킹 백프레셔를 지원합니다. Reactor는 서버사이드 Java에 중점을 두고 개발되었으며, Spring과 긴밀히 협력하여 만들어졌습니다.

WebFlux는 Reactor를 핵심 의존성으로 사용하지만, Reactive Streams를 통해 다른 리액티브 라이브러리와도 상호 운용이 가능합니다. 일반적으로 WebFlux API는 단순한 Publisher를 입력으로 받고, 이를 내부적으로 Reactor 타입으로 변환하여 사용한 뒤, Flux 또는 Mono로 결과를 반환합니다. 따라서, 입력으로는 어떤 Publisher도 전달할 수 있고, 출력으로 반환된 Flux나 Mono에 대해 다양한 연산을 적용할 수 있습니다. 그러나 다른 리액티브 라이브러리에서 출력을 사용하려면 적절히 변환해야 합니다.

가능한 경우(예: 어노테이션 기반 컨트롤러), WebFlux는 RxJava나 다른 리액티브 라이브러리를 투명하게 적응하여 사용할 수 있도록 합니다. 더 자세한 내용은 Reactive Libraries 섹션을 참조하세요.

### Reactive Streams vs Reactor ?
**Reactive Streams**
- 표준 사양(Specification)입니다.
- Java 생태계에서 리액티브 프로그래밍의 기본 원칙을 정의합니다.
- 데이터 스트림과 비동기 처리를 위해 Publisher, Subscriber, Subscription, Processor의 4가지 주요 인터페이스를 정의합니다.
- **논블로킹 백프레셔(Non-blocking Back Pressure)**를 필수적으로 지원합니다.
- 자체 구현체는 없으며, 다양한 라이브러리가 이 표준을 기반으로 구현을 제공합니다.

**Reactor**
- Reactive Streams 표준을 구현한 라이브러리입니다.
- Spring WebFlux의 기본 리액티브 라이브러리로 사용됩니다.
- Mono와 Flux라는 고수준 API를 통해 Reactive Streams의 Publisher 개념을 확장하고, 풍부한 연산자(operator)와 비동기 데이터 흐름 제어 기능을 제공합니다.
- ReactiveX 연산자 스타일을 채택해 함수형 프로그래밍에 적합한 API를 제공합니다.



## Back-Pressure
- Spring 팀이 "리액티브"와 관련하여 연관 짓는 또 다른 중요한 메커니즘이 있는데, 그것은 **논블로킹 백프레셔(non-blocking back pressure)** 입니다.
- 동기적(synchronous) 명령형(imperative) 코드에서는 블로킹 호출이 호출자가 기다리도록 강제하는 자연스러운 백프레셔 역할을 합니다.
- 그러나 논블로킹 코드에서는 빠른 생산자가 목적지(호출하는 타겟)를 압도하지 않도록 **이벤트의 속도를 제어**하는 것이 중요해집니다.

## non-blocking, asynchronous

## Spring WebFlux
> 예시로 살펴보기

### Publisher
- Publisher는 데이터를 제공하는 역할을 하며, Mono와 Flux가 그 대표적인 구현체입니다.
  - Mono : 0~1개의 데이터를 제공하는 Publisher.
  - Flux : 0~N개의 데이터를 제공하는 Publisher.

```java
@GetMapping("/members/{id}")
public Mono<Member> getMemberById(@PathVariable Long id) {
    return memberService.findById(id); // Mono는 Publisher 역할
}

@GetMapping("/members")
public Flux<Member> getAllMembers() {
    return memberService.findAll(); // Flux는 Publisher 역할
}
```

## 참고 자료

---
- https://spring.io/reactive
- https://docs.spring.io/spring-framework/reference/web/webflux/new-framework.html#webflux-why-reactive
- https://tech.io/playgrounds/929/reactive-programming-with-reactor-3/Intro
