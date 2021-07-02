---
title: HTTP의 비연결성과 keep-alive
date: 2021-06-30 00:25:00 +0900
categories: [Web 지식]
tags: [HTTP, keep-alive]
---

# 비연결성이란 ?
---
> ***HTTP 통신을 한 번 할 때마다 TCP에 의해 연결/종료 되는 HTTP의 특징.***

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

# 지속 연결(Persistent Connection)
---
> ***HTTP/1.1과 일부 HTTP/1.0에서는 TCP 연결 문제를 해결하기 위해 '지속연결' 이라는 방법을 고안했다.***

- 어느 한쪽이 명시적으로 연결을 종료하지 않는 이상 TCP 연결을 계속 유지한다.
- HTTP/1.1에서는 표준 동작이지만 HTTP/1.0에서는 정식 사양이 아니었다.
- 클라이언트, 서버 모두 지속 연결을 지원해야 지속 연결이 가능하다.

## 장/단점
---
### 장점
- TCP 연결/종료에 대한 오버헤드가 줄어들기 때문에 서버에 대한 부하가 경감된다.
- 오버헤드를 줄인 만큼 HTTP 요청/응답이 더 빠르게 이루어진다.
- 여러 요청을 병행해서 보낼 수 있다. 즉, 요청에 대한 응답이 오기전에 다른 요청을 또 보낼 수 있다(파이프라인화)
- Reduced CPU usage and round-trips because of fewer new connections and TLS handshakes.

### 단점
- 필요한 모든 데이터가 수신되었을 때 클라이언트가 연결을 닫지 않으면 서버에서 연결을 유지하는 데 필요한 리소스를 다른 클라이언트에서 사용할 수 없게 된다.
- 서버가 TCP 연결을 닫는 동시에 클라이언트가 서버에 요청을 전송하는 경우, 경합 조건(race condition)이 발생할 수 있다.
- 따라서, 서버는 연결을 닫기 직전에 클라이언트에 408 Request Timeout 상태 코드를 전송해야 하며,
요청을 전송한 후 클라이언트가 408 상태 코드를 수신하면 서버에 대한 새 연결을 열고 요청을 다시 보낼 수 있다.
- 일부 클라이언트는 요청을 재전송하지 않으며, 요청을 재전송하는 많은 클라이언트는 요청에 역 HTTP 메서드가 있는 경우에만 재전송한다.

keep-alive ?

왜 알아야하지 ?

알면 어디에 써먹을 수 있을까 ?

# HTTP2에서는 keep-alive 사용하지 않는다 ??
https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Keep-Alive

# 참고 자료
---
- 우에노 센, 『그림으로 배우는 Http & Network Basic』, 영진닷컴(2015)
- [https://www.tutorialspoint.com/Connectionless-Services](https://www.tutorialspoint.com/Connectionless-Services)
- [https://en.wikipedia.org/wiki/HTTP_persistent_connection](https://en.wikipedia.org/wiki/HTTP_persistent_connection)
