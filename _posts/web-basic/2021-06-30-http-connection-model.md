---
title: HTTP의 연결모델
date: 2021-06-30 00:25:00 +0900
categories: [Web 지식]
tags: [HTTP, Connection Management]
---

> ***<q>connection management allows considerable boosting of performance in HTTP</q>***

# Short-lived connections
---
> ***HTTP 통신을 한 번 할 때마다 TCP에 의해 연결/종료 된다.***

- 따라서, 매 통신 마다 새로운 연결을 맺어야한다.
- 초기 통신에서는 작은 사이즈의 텍스트를 보내는 정도였기 때문에 별 문제가 되지 않았다.
- 하지만, HTTP가 널리 보급되어감에 따라 하나의 HTML 문서에 여러 이미지, js 파일 등이 포함되고 그것들을 획득하기 위해 여러번 요청을 보내야한다.
- 즉, 아래와 같은 프로세스를 매 요청마다 반복해야 하는 것이다.

<img src="https://user-images.githubusercontent.com/64415489/124314011-b015ab00-dbac-11eb-8a28-6d88be5817e8.png" width="60%" height="40%"/>

## 장/단점
---
### 장점
- CPU, 메모리와 같은 서버의 자원을 지속적으로 점유하지 않는다.

### 단점
- 매 요청마다 TCP 연결/종료가 발생하기 때문에 통신량이 늘어나게 된다.

# Persistent Connection
---
> ***HTTP/1.1과 일부 HTTP/1.0에서는 TCP 연결 문제를 해결하기 위해 '지속연결' 이라는 방법을 고안했다.***

- 어느 한쪽이 명시적으로 연결을 종료하지 않는 이상 TCP 연결을 계속 유지한다.
- HTTP/1.1에서는 표준 동작이지만 HTTP/1.0에서는 정식 사양이 아니었다.
- 클라이언트, 서버 모두 지속 연결을 지원해야 지속 연결이 가능하다.

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/124387961-757e5080-dd1b-11eb-99cb-b3b1cee79284.png" height=550/>
  <figcaption align="center">출처 : https://developer.mozilla.org/en-US/docs/Web/HTTP/Connection_management_in_HTTP_1.x</figcaption>
</figure>

## 장/단점
---
### 장점
- TCP 연결/종료에 대한 오버헤드가 줄어들기 때문에 서버에 대한 부하가 경감된다.
- 오버헤드를 줄인 만큼 HTTP 요청/응답이 더 빠르게 이루어진다.
- 여러 요청을 병행해서 보낼 수 있다. 즉, 요청에 대한 응답이 오기전에 다른 요청을 또 보낼 수 있다(파이프라인화)
- 새로운 연결 및 TLS 핸드셰이크 감소로 CPU 사용량 및 왕복이 감소한다.

### 단점
- 필요한 모든 데이터가 수신되었을 때 클라이언트가 연결을 닫지 않으면 서버에서 연결을 유지하는 데 필요한 리소스를 다른 클라이언트에서 사용할 수 없게 된다.
- 서버가 TCP 연결을 닫는 동시에 클라이언트가 서버에 요청을 전송하는 경우, 경합 조건(race condition)이 발생할 수 있다.
- 따라서, 서버는 연결을 닫기 직전에 클라이언트에 408 Request Timeout 상태 코드를 전송해야 하며,
요청을 전송한 후 클라이언트가 408 상태 코드를 수신하면 서버에 대한 새 연결을 열고 요청을 다시 보낼 수 있다.
- 일부 클라이언트는 요청을 재전송하지 않으며, 요청을 재전송하는 많은 클라이언트는 요청에 역 HTTP 메서드가 있는 경우에만 재전송한다.
- 과부하 상태에서는 DoS 공격을 당할 수 있습니다.

## keep-alive
---
> Connection : keep-alive

- HTTP 헤더 속성 중 하나이다.
- HTTP 1.0에서는 keep-alive 헤더가 포함되지 않는 한 연결이 지속되지 않는 것으로 간주되었다.
- HTTP 1.1에서는 기본 속성이 되었다. 원하지 않는 경우엔 `Connection : close`를 헤더에 추가하면 'Short-lived connections' 연결 모델을 사용한다.
- keep-alive Timeout
  - Socket에 I/O Access가 마지막으로 종료된 시점부터 정의된 시간까지 Access가 없더라도 세션을 유지하는 구조이다.
  - 서버 자원은 유한하기 때문에, 여러 개의 커넥션을 계속 유지하게 되면 서버의 가용성을 떨어뜨릴 수 있다.

# HTTP pipelining
---
- 커넥션 지연을 회피하고자 같은 영속적인 커넥션을 통해서, 응답을 기다리지 않고 요청을 연속적으로 보내는 기능이다.
- GET, HEAD, PUT, DELETE 메서드같은 idempotent(멱등한) 메서드만 가능하다(POST는 불가능).
왜냐하면 실패가 발생한 경우에는 단순히 파이프라인 컨텐츠를 다시 반복하면 되기 때문이다.
- 대부분의 모던 브라우저는 이 기능을 기본적으로 활성화하지 않는다.
  - 모든 HTTP/1.1 호환 프록시와 서버들은 파이프라이닝을 지원해야 하지만, 실제로는 많은 프록시와 서버들은 제한을 가지고 있다.
  - 버그가 있는 프록시들이 많은데, 이들은 웹 개발자들이 쉽게 예상하거나 분석하기 힘든 이상하고 오류가 있는 동작을 야기한다.
  - 파이프라이닝은 정확히 구현해내기 복잡합니다: 전송 중인 리소스의 크기, 사용될 효과적인 RTT, 그리고 효과적인 대역폭은 파이프라인이 제공하는 성능 향상에 직접적으로 영향을 미친다.
  - 파이프라이닝은 HOL(Head-of-line blocking) 문제에 영향을 받습니다.
  - 이런 이유들로, 파이프라이닝은 더 나은 알고리즘인 멀티플렉싱으로 대체되었는데, 이는 HTTP/2에서 사용된다.

*※ HOL(Head-of-line blocking) : 단일 TCP 연결에서, 이전 요청이 완료될 때까지 이후의 요청이 기다려야 하는 것*

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/124387988-934bb580-dd1b-11eb-8af8-8de7ac3a4395.png" height=550/>
  <figcaption align="center">출처 : https://developer.mozilla.org/en-US/docs/Web/HTTP/Connection_management_in_HTTP_1.x</figcaption>
</figure>

# Multiplexing
---
> ***여러가지의 자원을 한 번의 요청을 통해 받을 수 있어 client마다 하나의 TCP connection이면 충분하다는 개념이다***

- HTTP2.0부터 지원
- 가능하게된 배경
  - HTTP2에서는 데이터를 전송할 때, 일반 문자열이 아닌 바이너리로 인코딩하여 전송한다.
    - 바이너리 포맷의 데이터를 사용하게 되어, 이전에는 하나로 모여있던 데이터를 프레임이라는 단위로 나눠서 관리 / 전송할 수 있게되었다.
  - HTTP2에서는 Frame과 Stream이라는 개념이 추가되었다.
    - Frame은 HTTP2 통신에서 데이터를 주고받을 수 있는 가장 작은 단위이다. 헤더 프레임, 데이터 프레임으로 구성되어 있다.
    - 스트림은 클라이언트와 서버 사이에 맺어진 연결을 통해 양방향으로 데이터를 주고받는 한개 이상의 메시지를 의미한다.
    - 메시지는 HTTP1.1처럼 요청과 응답의 단위이다. 메시지는 다수의 Frame으로 구성되어 있다.
    - 즉, 프레임 → 메시지 → 스트림이 되는 구조이다
    <figure align = "center">
      <img src = "https://user-images.githubusercontent.com/64415489/124389142-d5c3c100-dd20-11eb-8b01-89c8f4ae6176.png" height=550/>
      <figcaption align="center">출처 : https://developers.google.com/web/fundamentals/performance/http2</figcaption>
    </figure>

  - HTTP2에서는 스트림 하나가 다수개의 요청과 응답을 처리할 수 있는 구조로 바뀌었다.
    - HTTP1 시절에는, 요청과 응답이 메시지라는 단위로 완벽하게 구분되어 있었지만, HTTP2에서는 스트림이라는 단위로 요청과 응답이 묶일 수 있는 구조가 만들어졌다.
    - 따라서, 응답 프레임들은 요청 순서에 상관없이 만들어진 순서대로 클라이언트에 전달될 수 있다.
    - 결과적으로, HTTP1 때처럼 중간에 응답이 막히면 대기하고 있던 Response들이 모두 기다려야하는 HOL 이슈에서 벗어날 수 있게 되었다.
    <figure align = "center">
      <img src = "https://user-images.githubusercontent.com/64415489/124391014-58e91500-dd29-11eb-8343-aa7872d9c451.png" height=600/>
      <figcaption align="center">출처 : https://developers.google.com/web/fundamentals/performance/http2</figcaption>
    </figure>

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/124388878-bbd5ae80-dd1f-11eb-85b3-778344f8758c.png" height=550/>
  <figcaption align="center">출처 : https://www.programmersought.com/article/86161816904/</figcaption>
</figure>

# 더 공부해야할 부분
---
- TCP/IP
- HTTP2, HTTP3
- HTTP Connection Pooling

# 참고 자료
---
- 우에노 센, 『그림으로 배우는 Http & Network Basic』, 영진닷컴(2015)
- [https://www.tutorialspoint.com/Connectionless-Services](https://www.tutorialspoint.com/Connectionless-Services)
- [https://en.wikipedia.org/wiki/HTTP_persistent_connection](https://en.wikipedia.org/wiki/HTTP_persistent_connection)
- [https://developer.mozilla.org/en-US/docs/Web/HTTP/Connection_management_in_HTTP_1.x](https://developer.mozilla.org/en-US/docs/Web/HTTP/Connection_management_in_HTTP_1.x)
- [https://goodgid.github.io/HTTP-Keep-Alive/](https://goodgid.github.io/HTTP-Keep-Alive/)
- [https://nuli.navercorp.com/community/article/1132452?email=true](https://nuli.navercorp.com/community/article/1132452?email=true)
- [https://americanopeople.tistory.com/115](https://americanopeople.tistory.com/115)
- [https://developers.google.com/web/fundamentals/performance/http2](https://developers.google.com/web/fundamentals/performance/http2)
