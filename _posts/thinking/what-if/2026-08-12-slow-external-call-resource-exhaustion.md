---
title: 외부 API가 느려지면 무엇이 마르는가 — 스레드부터 커널 자원까지
date: 2026-08-12 22:20:00 +0900
categories: [생각해보기, what-if]
tags: [Resilience4j, Tomcat, TCP, Spring]
---

# 느린 외부 호출이 만드는 장애 — 질문으로 따라가는 정리

---

> **전제 구조**: `Client — WAS — DB`
> WAS에서 요청 처리 시 외부 호출이 필수인데, 그 응답이 오래 걸리는 상황

각 절은 실제로 던졌던 질문에서 출발한다.
`Q` = 내 질문 / `A(나)` = 내가 낸 답 / 그 아래가 확장된 내용.

## Q1. 요청 처리 중 외부 호출이 느리면 어떤 문제가 생기나?

---

> **A(나)** — 요청이 많은 경우 톰캣 커넥션풀을 모두 점유해서 다른 요청 처리에 영향을 끼칠 수 있음

**방향은 정확. 용어만 정정한다.**

| | 정확한 이름 | 기본값 |
|---|---|---|
| 톰캣 | 스레드**풀** (`maxThreads`) | 200 |
| DB | 커넥션**풀** (HikariCP) | 10 |

**이 둘을 분리해서 봐야 문제가 제대로 보인다.** 아래 모든 논의가 여기서 갈라진다.

### 전체 그림 — 한 줄 요약

> 느린 외부 호출은 그 자체로 장애가 아니다.
> **자원을 오래 붙잡게 만들고, 공유 자원을 통해 무관한 기능까지 끌고 내려가는 것**이 장애다.

핵심 질문 두 개로 압축된다.

1. 이 요청이 **어떤 자원을**, **얼마나 오래** 붙잡는가
2. 그 자원을 **누구와 공유**하는가

## Q2. 트랜잭션 안에서 외부 호출을 하면?

---

> **A(나)** — DB 커넥션도 점유 + 락

**정확하다.** 여기서 두 걸음 더.

### (a) DB 풀이 먼저 마른다

```
톰캣 스레드 200  ←→  Hikari 커넥션 10
```

이 숫자 차이가 핵심이다. **외부 호출 대기 중인 요청 10개만 있어도 커넥션 풀이 전부 물린다.** 그러면 외부 호출과 아무 상관 없는 API, 심지어 헬스체크 쿼리까지 `Connection is not available`로 죽는다.

→ **장애가 한 엔드포인트에서 전체 서비스로 번지는 첫 번째 경로.**

### (b) 락 보유 시간이 네트워크에 종속된다

```java
@Transactional
  ├─ SELECT ... FOR UPDATE   ← 락 획득
  ├─ 외부 API 호출 (60초)     ← 락을 쥔 채 대기
  └─ UPDATE
```

락 보유 시간이 **"쿼리 실행 시간"이 아니라 "외부 API 응답 시간"** 이 된다. 네트워크 상황이 우리 DB의 락 경합을 결정하는 구조. 여기서 lock wait timeout, 데드락 확률 증가가 파생된다.

### 원칙

> **외부 호출은 트랜잭션 밖으로.**

트랜잭션을 쪼개고, 상태 컬럼을 두고 → 커밋 → 외부 호출 → 별도 트랜잭션으로 결과 반영.

→ 그러면 새 질문이 생긴다: *"외부 호출은 성공했는데 결과 반영 전에 서버가 죽으면?"* → **Transactional Outbox Pattern** (아래 키워드 참고)

## Q3. 클라이언트가 먼저 끊으면 서버는 어떻게 되나?

---

> **A(나)** —
> ① 기존 요청은 끝까지 처리되고, 응답하려는데 커넥션이 닫혔으니 `ClientAbortException` 발생할 듯
> ② 새로고침 3번이면 3개
> ③ 멱등성 설계가 안 되어 있으면 중복 처리로 데이터 정합성 깨짐

**세 개 다 정확하다.** 각각 한 겹씩 더.

### ① ClientAbortException — 취소가 전파되지 않는다

이 예외는 **응답 write 시점에야** 터진다. 즉 서버는 클라이언트가 이미 떠난 걸 모른 채 외부 호출 60초를 끝까지 기다리고, DB 커넥션도 끝까지 물고 있다.

> **아무도 받지 않을 응답을 위해 자원을 전부 소모한다.**
> 서블릿 모델에는 취소 전파가 없기 때문.

### ② 3배 — 서버 안에서만 3배가 아니다

**외부 시스템 입장에서도 트래픽이 3배가 된다.** 이미 느려서 허덕이는 상대에게 3배를 꽂는 것.

```
외부 느려짐 → 유저 새로고침 → 부하 증가 → 더 느려짐 → 더 새로고침 → ...
```

이것이 **Retry Storm**이고, "재시도를 넣으면 도움이 되나?"의 답이기도 하다.

> **재시도는 느려진 상황에서 거의 항상 상황을 악화시킨다.**
> 넣으려면 세트로: Exponential Backoff + **Jitter** + 최대 횟수 + Circuit Breaker

### ③ 멱등성 — 여기에 더 고약한 게 있다

**read timeout이 났을 때, 그 요청은 실패한 걸까 성공한 걸까? 알 수 없다.**
외부에서는 이미 결제가 됐는데 우리만 모를 수 있다.

그래서 멱등키만으로는 정합성이 닫히지 않는다. 세 개가 필요하다.

1. **멱등키 (Idempotency Key)** — 중복 요청 차단
2. **결과 조회 API** — 미확정 건의 실제 상태 확인
3. **보정 배치** — 미확정 건을 주기적으로 확인·정리

→ 결제/정산 도메인에 **"미결" 상태**가 존재하는 이유.

## Q4. "무관한 조회 API까지 죽는다"는 게, 로직 안의 다른 호출인가 진입점부터 다른 API인가?

---

> **아예 다른 진입점.**

`GET /users/me` 같은, 외부 호출은커녕 DB 조회 한 번이면 끝나는 API. **코드상으로는 아무 관계가 없다.** 그런데 같은 톰캣 스레드풀, 같은 Hikari 풀을 쓴다.

```
GET /pay      → 외부 호출 (느림) → 스레드 200개 점유
GET /users/me → DB 조회 한 번    → 스레드를 못 받아 대기 → 같이 죽음
```

### 핵심 명제

> **공유 자원이 곧 장애 전파 경로다.**
> 코드 의존성은 없는데 **자원 의존성**이 있다. → **Noisy Neighbor**

## Q5. 그럼 어떻게 격리하나?

---

> **A(나)** —
> - 풀 안에서: 외부 호출이 긴 게 불필요하게 DB 자원 등을 점유하지 않게
> - 풀 밖에서: LB로 이 API는 특정 인스턴스로만 보내기 (안 바쁠 때 자원이 남아서 좋은 해결책은 아닌 듯)

**두 방향 다 정확하고, 두 번째의 트레이드오프도 맞다.** 정리하면 격리는 5계층.

### 계층 1. 자원 보유 시간 단축 ← 내가 말한 첫 번째

트랜잭션 밖으로 빼고, 커넥션은 필요한 순간에만 잡고 즉시 반납.

> 엄밀히는 격리가 아니라 **점유 시간 단축**. 여전히 스레드 200개는 다 물릴 수 있다.
> **필요조건이지 충분조건이 아니다.**

### 계층 2. 벌크헤드 — 동시 실행량 제한

톰캣 스레드풀 자체는 API별로 못 쪼개지만, **동시 실행 허용량**은 쪼갤 수 있다. → Q6에서 상세

### 계층 3. 프로세스/인스턴스 분리 ← 내가 말한 두 번째

지적한 단점(자원 놀림)이 맞아서 보통 최후의 수단. 다만 **외부 연동이 아주 중요하거나 아주 불안정할 때는 정답이 되기도 한다.** (예: 정산에서 PG 연동만 별도 모듈로 분리) 오토스케일링을 붙이면 자원 놀림은 어느 정도 완화된다.

### 계층 4. 스레드를 아예 안 붙잡기 (비동기/논블로킹) → Q7에서 상세

### 계층 5. 동기 호출을 아예 하지 않기

응답을 즉시 줄 필요가 없다면 → 메시지 큐에 넣고 `202 Accepted`, 별도 컨슈머가 외부 호출. 위 문제 대부분이 사라진다. 대신 결과 조회/알림 경로가 필요.

## Q6-a. 벌크헤드 구현 코드는?

---

```yaml
resilience4j:
  bulkhead:
    instances:
      paymentApi:
        max-concurrent-calls: 30
        max-wait-duration: 0s   # 대기 없이 즉시 거절
```

```java
@Bulkhead(name = "paymentApi", type = Bulkhead.Type.SEMAPHORE, fallbackMethod = "busy")
public PayResult confirm(PayRequest req) {
    return restTemplate.postForObject("/confirm", req, PayResult.class);
}

// fallback은 원본 시그니처 + 예외 파라미터
private PayResult busy(PayRequest req, BulkheadFullException e) {
    throw new ExternalBusyException("요청이 몰렸습니다. 잠시 후 다시 시도해주세요.");
}
```

내부적으로는 그냥 세마포어다.

```java
private final Semaphore semaphore = new Semaphore(30);

public PayResult confirm(PayRequest req) {
    if (!semaphore.tryAcquire()) throw new ExternalBusyException("...");
    try {
        return restTemplate.postForObject(...);
    } finally {
        semaphore.release();
    }
}
```

31번째 요청은 **즉시 실패(fast fail)하고 스레드를 반납** → 나머지 170개 스레드가 산다. 배의 격벽(bulkhead)에서 온 이름.

> `Bulkhead.Type.THREAD_POOL`도 있지만 `CompletableFuture` 반환이 강제되므로, 동기 블로킹 코드에는 세마포어 방식이 맞다.

## Q6-b. RestTemplate의 HTTP 커넥션 풀 개수를 제한하고 대기시간을 짧게 하는 것과 결과적으로 같은 것 아닌가?

---

> **효과의 8할은 같다.** "동시성 상한 + fast fail"이라는 핵심 메커니즘이 동일하다. **좋은 지적.**

다만 네 가지가 다르다.

| | HTTP 커넥션 풀 제한 | 벌크헤드 |
|---|---|---|
| **격리 단위** | **호스트 단위** (`maxPerRoute`) | **메서드/오퍼레이션 단위** |
| **보호 범위** | HTTP 구간만 | 블록 전체 (DB 포함) |
| **조합** | 독립적 | Retry/CB/RateLimiter/TimeLimiter와 합성 |
| **메트릭** | 별도 수집 | 기본 제공 |

### ① 격리 단위

`maxPerRoute`는 호스트 단위다. 같은 외부 시스템이 **결제확정 API와 조회 API를 함께 제공하면 둘이 같은 풀을 나눠 쓴다.** 확정 API가 느려지면 조회도 같이 굶는다. 벌크헤드는 논리적 오퍼레이션 단위라 이걸 쪼갤 수 있다.

### ② 보호 범위

메서드가 `DB 조회 → 외부 호출 → DB 저장`이면, HTTP 커넥션을 30개로 제한해도 **그 30개 스레드는 각자 DB 커넥션도 물고 있다.** 벌크헤드는 블록 전체를 감싸므로 "이 로직이 잡을 수 있는 자원 총량"을 통으로 제한한다.

### ③ 합성

Resilience4j 데코레이터 순서: `Retry → CircuitBreaker → RateLimiter → TimeLimiter → Bulkhead` (벌크헤드가 최내곽). 커넥션 풀은 이 체인에 들어오지 않는다.

### 함정

~~`new RestTemplate()`의 기본 구현 `SimpleClientHttpRequestFactory`에는 **풀이 아예 없다.** 매 요청 새 커넥션이라 상한 자체가 없다.~~

**정정** — `SimpleClientHttpRequestFactory`가 쓰는 `HttpURLConnection`에는 JDK 내부에 `KeepAliveCache`가 있다. `http.keepAlive`는 기본 `true`, `http.maxConnections`는 기본 5(목적지당). 재사용이 아예 없는 건 아니다.

진짜 문제는 그 재사용이 **조건부**이고 **통제 불가능**하다는 것이다. 목적지당 5개로 고정이고, 값을 바꾸려면 JVM 시스템 프로퍼티뿐이며, 풀이 비었을 때 기다릴지 실패할지 고를 수단(`connectionRequestTimeout`)이 없다.

→ 결론은 그대로다. `HttpComponentsClientHttpRequestFactory`로 갈아끼워야 이 전략이 성립한다. → Q8 참고

### 결론

> **둘 다 한다.** 커넥션 풀 제한은 **자원 통제**(안 하면 무제한), 벌크헤드는 **정책 통제**. 층위가 다르다.

## Q6-c. 스레드 200개가 다 대기 중이면 새 요청은? acceptCount만큼 큐에 쌓이지 않나?

---

> **A(나)** — acceptCount만큼 큐에 쌓일 듯. 유저는 느리다고 생각할 것 같고, 메모리는 계속 점유되나?

**방향은 맞고, 중간에 한 층이 더 있다.**

```
maxThreads (200)      ← 실제 처리
maxConnections (8192) ← 수락은 하되 스레드를 기다리는 커넥션   ★ 여기가 빠졌던 층
acceptCount (100)     ← OS backlog, maxConnections 넘칠 때
그 이후                ← connection refused
```

> ~~`acceptCount`(100)가 그대로 OS backlog가 된다.~~
> **정정** — 실제 backlog는 `min(acceptCount, net.core.somaxconn)`이다. `somaxconn`이 낮으면 `acceptCount`를 아무리 올려도 커널에서 잘린다. (커널 5.4+ 기본 4096, 그 이전은 128)
> → Q11의 "분명 `ulimit` 올렸는데 계속 터진다"와 **같은 종류의 함정.** 애플리케이션 설정값이 곧 실효값이 아니다.

### 핵심은 8192다

스레드 200개가 다 막혀도 **톰캣은 8000개 넘는 요청을 계속 받아들인다. 거절하지 않고 다 삼킨다.**

→ 부하가 걸리면 **에러가 나는 게 아니라 레이턴시가 지수적으로 증가한다.**
유저 체감은 "느리다"가 맞는데, 대기 시간이 처리 시간에 계속 누적되어 뒤로 갈수록 30초, 60초로 폭주한다. **그 시점엔 유저가 이미 다 떠났고, 아무도 안 볼 응답을 만드느라 서버가 죽는다.**

### 메모리 — 진짜 문제는 GC다

메모리 점유는 맞다. 커넥션마다 소켓 버퍼 + Request/Response 객체가 붙는다. 그런데 더 고약한 건 **객체 수명**이다.

```
정상:  요청 스코프 객체가 수십 ms 살다가 Young GC에서 소멸
지연:  60초 동안 살아있음 → Old 영역으로 승격(Promotion) → Full GC → STW
```

```
응답 느려짐 → 요청 더 쌓임 → 메모리 더 참 → GC 더 자주 → 더 느려짐
    → OOM → 인스턴스 사망 → 남은 인스턴스로 트래픽 집중 → 연쇄 붕괴
```

### 처방

> **`maxConnections`를 기본값보다 훨씬 낮게 잡는다.**
> 처리 못 할 요청은 삼키지 말고 빨리 거절하는 게 낫다. → **Graceful Degradation**

## Q7. "WebFlux를 쓰면 외부 호출 대기 중에 톰캣 스레드를 반납" — 더 설명 (reactive 개념 없음)

---

### 먼저: 왜 스레드가 묶이는가

`restTemplate.postForObject(...)` 한 줄이 실행될 때 스레드 내부:

```
1. 소켓에 요청 write
2. 커널의 read() 시스템콜 호출
3. 데이터가 아직 안 옴 → OS가 이 스레드를 WAITING 상태로 재움
4. ... 60초 ...
5. 응답 도착 → OS가 스레드를 깨움
```

**3~4번 구간에서 스레드는 CPU를 전혀 쓰지 않는다.** 그런데도 살아있고, 톰캣 200개 슬롯 중 하나를 차지하고, 스택 메모리(~1MB)도 잡고 있다.

이것이 블로킹 I/O — **"기다리는 일"에 스레드를 통째로 배정하는 모델.**
(정수기 앞에서 물 받는 동안 직원이 옆에 서서 지켜보는 셈)

### 핵심 통찰

> **기다리는 데는 스레드가 필요 없다.**

응답이 도착하는 건 커널이 알려주는 **이벤트**(epoll)다. 누가 지켜보고 있어야 아는 게 아니다. "이 소켓에 데이터 오면 알려줘"라고 등록만 해두면 스레드는 딴 일을 해도 된다.

```
[블로킹]
스레드1: ──요청──[···········60초 대기···········]──응답처리──
                  (스레드1 점유, 아무것도 못 함)

[논블로킹]
스레드1: ──요청──▶ (콜백 등록하고 즉시 반납)
스레드1: 그 사이 다른 요청 100개 처리
이벤트루프: [60초 후 응답 감지] ──▶ 스레드N에 "이제 처리해" 전달
```

### 정정 — 서블릿 비동기 ≠ WebFlux

"WebFlux를 쓰면 톰캣 스레드를 반납"이라고 썼는데 **부정확했다.** 둘은 다른 얘기다.

**서블릿 비동기** — 톰캣을 그대로 쓰면서 스레드만 반납

```java
@GetMapping("/pay")
public CompletableFuture<PayResult> pay(...) {
    return CompletableFuture.supplyAsync(() -> client.confirm(req));
}
```

컨트롤러가 `CompletableFuture`/`DeferredResult`/`Callable`을 리턴하면 톰캣이 그 스레드를 풀에 반납하고, 완료 시 다른 스레드로 응답을 쓴다. 기존 코드 구조를 거의 안 바꿔도 된다.

**WebFlux** — 톰캣을 아예 안 쓴다. Netty 기반이고 서블릿 스택 자체를 걷어낸다. 프로그래밍 모델도 `Mono`/`Flux`로 완전히 바뀐다.

### 큰 함정

위 `CompletableFuture.supplyAsync` 코드에서 톰캣 스레드는 반납했는데, **`client.confirm()`은 어디서 실행되나?**

→ `ForkJoinPool.commonPool`의 스레드. 거기서 여전히 블로킹으로 60초 기다린다.
**스레드를 옮겼을 뿐 없앤 게 아니다.**

> ~~톰캣 풀 대신 그 풀이 마른다.~~
> **정정 — 그냥 마르는 정도가 아니라 훨씬 나쁘다.** `commonPool`의 parallelism은 `availableProcessors() - 1`이다.

```
8코어 장비 → commonPool 워커 7개
톰캣 스레드 200개를 반납하고 7개짜리 풀로 옮긴 셈
```

동시에 처리 가능한 외부 호출이 200에서 7로 **줄어든다.** 게다가 `commonPool`은 JVM 전역 공유라 병렬 스트림 등 앱의 다른 코드까지 같이 굶는다. **개선이 아니라 대폭 악화.** 전용 `Executor`를 넘기지 않은 `supplyAsync`가 위험한 이유.

진짜 이득을 보려면 **호출 자체가 논블로킹**이어야 한다.

```java
@GetMapping("/pay")
public Mono<PayResult> pay(...) {
    return webClient.post().uri("/confirm").retrieve().bodyToMono(PayResult.class);
}
```

### 그리고 진짜 벽

**체인에 블로킹이 하나라도 있으면 전부 무의미해진다. 그런데 JPA/JDBC는 본질적으로 블로킹이다.**

`DB 조회 → 외부 호출 → DB 저장` 구조에서는 외부 호출만 논블로킹으로 바꿔봐야 앞뒤 DB 호출에서 스레드가 묶인다. R2DBC로 가야 하고, 그러면 JPA를 버려야 한다. → **WebFlux 도입이 무거운 진짜 이유.**

### 비동기가 해결하지 못하는 것

- **외부는 여전히 느리다.** 우리 스레드가 안 묶일 뿐, 유저 체감 응답 시간은 그대로
- **DB 커넥션과 락 문제는 그대로.** 트랜잭션 안에서 외부 호출하면 비동기든 아니든 락은 60초 잡혀 있다
- **자연 방어막이 사라진다.** 스레드 200 제한은 답답하지만 동시에 "외부에 200개 이상 안 보낸다"는 상한이기도 했다. 논블로킹은 죽어가는 외부에 1만 개를 꽂을 수 있게 만든다
  → **비동기로 갈수록 벌크헤드와 서킷브레이커가 더 필요해진다**

## Q8. RestTemplate 호출 시 점유하는 자원이 톰캣 스레드 말고 더 있나? (DB 커넥션처럼)

---

**대칭으로 보면 답이 나온다.**

```
DB 호출    : 톰캣 스레드 + DB 커넥션 (Hikari)
외부 호출  : 톰캣 스레드 + HTTP 커넥션 (HttpClient 풀)
```

구조가 똑같다. → Q6-b에서 "커넥션 풀 제한하면 되는 거 아니냐"고 한 것이 정확히 이 자원을 짚은 것.

### 큰 함정: 기본 구현의 재사용은 조건부다

`new RestTemplate()` → `SimpleClientHttpRequestFactory` → `HttpURLConnection`.

> ~~**풀이 없다 = 상한이 없다.** 요청 200개면 소켓 200개.~~
> **정정** — `HttpURLConnection`에는 `KeepAliveCache`가 있어서 목적지당 5개(`http.maxConnections`)까지는 재사용된다.

다만 캐시로 돌아가는 조건이 까다롭다.

| 상황 | 커넥션의 운명 |
|---|---|
| 응답 본문을 끝까지 읽음 | 캐시에 반납 → 재사용 |
| 본문을 안 읽고 버림 | 그대로 `close()` → TIME_WAIT |
| 4xx/5xx에서 예외 던지고 탈출 | 마찬가지로 재사용 실패 |

**Q12 사례 2와 정확히 같은 함정이다.** 평소엔 5개를 돌려쓰다가, **외부가 에러를 뿜기 시작하면 그때부터 매 요청 새 소켓**이 된다. 가장 부하가 큰 순간에 재사용이 깨진다.

여기서 나오는 문제들이 Q9~Q11의 주제(ephemeral port, fd, TIME_WAIT)다.

**→ 위험한 건 "풀이 없다"가 아니라 "상한과 타임아웃을 우리가 정할 수 없다"는 쪽이다.**

```java
PoolingHttpClientConnectionManager cm = PoolingHttpClientConnectionManagerBuilder.create()
    .setMaxConnTotal(100)
    .setMaxConnPerRoute(30)              // 기본값 2. 반드시 조정
    .setDefaultConnectionConfig(ConnectionConfig.custom()
        .setConnectTimeout(Timeout.ofSeconds(1))            // TCP 핸드셰이크
        .build())
    .build();

CloseableHttpClient httpClient = HttpClients.custom()
    .setConnectionManager(cm)
    .setDefaultRequestConfig(RequestConfig.custom()
        .setConnectionRequestTimeout(Timeout.ofSeconds(1))  // 풀 대기
        .setResponseTimeout(Timeout.ofSeconds(3))           // read
        .build())
    .build();

RestTemplate restTemplate = new RestTemplate(
    new HttpComponentsClientHttpRequestFactory(httpClient));
```

> ~~타임아웃 3종을 모두 `RequestConfig`에 건다.~~
> **정정** — HttpClient 5.x에서 `RequestConfig.setConnectTimeout`은 deprecated다. connect 타임아웃은 **커넥션 매니저의 `ConnectionConfig`** 로 옮겨갔다. 4.x 예제를 그대로 옮겨오면 connect만 조용히 안 걸린 채로 남는다.

`connectionRequestTimeout`을 짧게 잡는 게 포인트. 풀이 비었을 때 여기서 무한정 기다리면 풀을 만든 의미가 없다.

### 타임아웃은 3개다

| 타임아웃 | 구간 | 원인 |
|---|---|---|
| connect | TCP 핸드셰이크 | 상대 서버 다운 |
| **read (response)** | 응답 대기 | **상대가 느림 — 이 문서의 주제** |
| connectionRequest | 우리 풀에서 커넥션 대기 | **우리 쪽 부하** (상대와 무관) |

**셋 다 걸지 않으면 각각 다른 방식으로 무한 대기한다.**

### 점유 자원 총정리

| 자원 | 상한 | 고갈 시 영향 범위 |
|---|---|---|
| 톰캣 스레드 | `maxThreads` (200) | 전체 API 마비 |
| HTTP 커넥션 | `maxPerRoute` (풀 사용 시만) | 해당 호출 대기 |
| ephemeral port | 목적지당 ~28,232 | **해당 목적지만** |
| file descriptor | `ulimit -n` | **프로세스 전역 — 전면 장애** |
| 힙 (응답 버퍼) | `-Xmx` | GC 폭주 → OOM |

\+ 트랜잭션 안이면 **DB 커넥션과 락**까지.

아래 두 개(port, fd)가 무서운 이유는 **프로세스 전역/커널 자원**이기 때문. Noisy Neighbor의 가장 밑바닥 층위다.

## Q9~Q10. `ip_local_port_range`가 무슨 의미고, "목적지당 28000"은 무슨 뜻인가? TIME_WAIT가 60초니까 몰리면 초과해서 요청이 불가능해지는 건가?

---

```bash
$ cat /proc/sys/net/ipv4/ip_local_port_range
32768	60999      # 28,232개
```

### 이 숫자의 의미

> **우리가 클라이언트로서 나갈 때, 커널이 출발지 포트로 쓸 수 있는 범위.**

왜 0부터가 아닌가 → 낮은 대역은 **서버가 listen하는 용도**로 예약되어 있다(80, 443, 3306, 8080...). 커널이 임의 배정하다가 3306을 골라버리면 그 서버에서 MySQL을 못 띄운다. 그래서 높은 대역을 자동 배정용으로 떼어둔 것.

**핵심: 인바운드와 무관하다.** 톰캣이 8080에서 1만 개를 받는 건 이 범위를 쓰지 않는다. **오직 우리가 밖으로 connect할 때만 소모된다.**

### "목적지당"인 이유 — 4-튜플

TCP 연결의 신원:

```
(출발지 IP, 출발지 포트, 목적지 IP, 목적지 포트)
```

이 4개 조합이 유일하기만 하면 커널은 구분할 수 있다. 특정 외부 API로 나갈 때:

```
(10.0.0.2, ?????, 10.0.0.5, 443)
    └고정    └변수    └고정      └고정
```

**변할 수 있는 건 출발지 포트 하나뿐** → 가짓수 = 28,232. 이것이 "목적지당 28,000개"의 의미.

목적지가 바뀌면 얘기가 다르다.

```
(10.0.0.2, 40000, 10.0.0.5, 443)   ← 결제API
(10.0.0.2, 40000, 10.0.0.9, 3306)  ← MySQL, 같은 40000 재사용 가능
```

4-튜플 전체가 다르므로 커널이 구분할 수 있고, **같은 포트 번호를 동시에 쓴다.**

> ### 정정
> 앞서 "포트가 마르면 DB 연결도 실패한다"고 했으나 **이는 과장이었다.**
> 결제 API로 28,232개를 다 써도 **MySQL 연결이나 다른 API 호출은 보통 멀쩡하다.**
> → **전면 장애가 아니라 "그 목적지로만" 막히는 부분 장애.** (fd 고갈이 전면 장애인 것과 대비)

곁가지: 서버에 IP가 여러 개면 출발지 IP도 변수가 되어 배수만큼 늘어난다. 상대가 DNS 라운드로빈으로 IP를 여러 개 주는 경우도 마찬가지 (LB 뒤면 보통 1개).

### TIME_WAIT — 이해한 게 맞다

**포인트: TIME_WAIT는 소켓이 닫혔는데도 그 4-튜플을 계속 점유한다.** 연결은 끝났지만 커널이 "이 조합은 60초간 재사용 금지" 딱지를 붙인다.

**왜 60초나 기다리나**
- (a) **마지막 ACK 유실 대비** — 즉시 소멸시키면 상대의 FIN 재전송에 RST를 쏘게 되고, 상대는 정상 종료 대신 에러로 처리
- (b) **유령 패킷 방지** (더 본질적) — 네트워크에서 지연된 이전 연결의 패킷이 같은 4-튜플의 새 연결에 섞여 들어오는 것을 2×MSL 동안 봉인

리눅스는 이 60초가 커널 하드코딩(`TCP_TIMEWAIT_LEN`)이라 sysctl로 못 바꾼다.

> ### 정정
> **TIME_WAIT 소켓은 fd를 소모하지 않는다.**
> `close()` 시점에 fd는 이미 반납되고, 커널 안에 `inet_timewait_sock` 경량 구조체만 남는다.
> 소모하는 것은 **4-튜플 슬롯(= 그 목적지로의 포트)과 약간의 커널 메모리**뿐.
> **TIME_WAIT 수만 개는 사실 정상이고 그 자체로 문제가 아니다.**

### 제약이 "동시 연결 수"에서 "연결 생성 속도"로 바뀐다

```
가용 슬롯 28,232개 ÷ 슬롯당 점유 60초 = 초당 약 470개
```

한 목적지로 **초당 470개 넘게 새 연결을 만들면** 반납보다 소모가 빨라 결국 바닥난다.
**동시에 470개가 살아있느냐와 무관하다.** 응답이 10ms에 와서 바로 닫아도 슬롯은 60초를 채워야 돌아온다.

**터지는 조건 (모두 충족 시)**
- 커넥션 재사용을 안 함 (매 요청 새 연결)
- 한 목적지에 집중
- 초당 수백 건 이상

### 증상

```
java.net.BindException: Cannot assign requested address    # EADDRNOTAVAIL
```

**이 메시지의 이질감이 중요하다.** 상대가 죽은 것도 타임아웃도 아닌데 "주소를 배정할 수 없다"고 나온다. 원인이 우리 쪽 커널 자원이라 로그만 보면 한참 헤맨다. **이 에러가 뜨면 바로 포트 고갈을 의심.**

```bash
ss -tan state time-wait | awk '{print $4}' | sort | uniq -c | sort -rn | head
ss -s
```

### 완화책과 진짜 해법

```bash
net.ipv4.tcp_tw_reuse = 1                      # 아웃바운드 한정 재사용 (타임스탬프 기반)
net.ipv4.ip_local_port_range = 10240 61000     # 범위 확대
```

> `tcp_tw_recycle`은 NAT 환경에서 연결이 끊기는 치명적 버그로 **커널 4.12에서 제거됨.** 오래된 블로그 보고 켜지 말 것.

**진짜 해법은 keep-alive / 커넥션 풀.**

```
재사용 실패: 요청 1,000개 → 연결 1,000개 생성·종료 → TIME_WAIT 1,000개
풀 사용    : 요청 1,000개 → 연결 30개 재사용        → TIME_WAIT 0개
```

포트 30개, fd 30개, TIME_WAIT 0. **세 문제가 한 번에 사라진다.**

> **470/sec라는 벽 자체가 "연결을 재사용하지 않는다"는 전제 위에서만 존재한다.**

### 왜 DB에서는 이 문제를 겪은 적이 없나

| | 연결 재사용 | 결과 |
|---|---|---|
| HikariCP (MySQL) | 커넥션을 계속 살려둠 | 포트 10~30개, TIME_WAIT 0 |
| Apache HttpClient 풀 | keep-alive 재사용 | 포트 30개 내외 |
| `new RestTemplate()` | ~~**매번 새 연결**~~ **목적지당 5개, 그나마 조건부** | 재사용 깨지면 요청 수만큼 |

**DB 커넥션은 재사용이 기본값이자 전부인데, HTTP는 재사용 폭이 좁고 조건부라 같은 트래픽에서도 여기만 터진다.**

## Q11. 목적지당 28,000개이고, 전역으로는 ulimit이 상한선인가?

---

**큰 그림은 맞다.** 다만 **두 개는 성격이 다른 별개의 축**이다.

| | 포트 | fd |
|---|---|---|
| 근거 | 커널의 TCP 식별 체계 (4-튜플 유일성) | 프로세스가 연 핸들 개수 제한 |
| 범위 | **목적지별** | **전역** (소켓 아닌 파일·파이프도 포함) |

**한 연결은 두 카운터를 동시에 하나씩 먹는다.** 둘 중 하나만 말라도 그 시점에 막힌다.

> 여기서 TIME_WAIT의 비대칭도 다시 설명된다 — **포트는 먹고 fd는 안 먹는다.** 두 축이 별개이기 때문.

### fd는 층이 여러 개다

```
fs.file-max                 # 시스템 전체 (커널). 보통 수백만
  └─ ulimit -n (soft/hard)  # 프로세스별 — 실제로 걸리는 지점
       └─ 프로세스가 실제 연 fd
```

**JVM에는 별도 fd 제한이 없다.** OS 값을 그대로 따른다.

```bash
cat /proc/<pid>/limits | grep files    # 실제 적용값 (셸의 ulimit -n과 다를 수 있음)
ls /proc/<pid>/fd | wc -l
```

> systemd는 `LimitNOFILE=`, 도커는 `--ulimit nofile`이 적용된다.
> **"분명 ulimit 올렸는데 계속 터진다"의 원인 대부분이 이것.**

### 실제로는 이 둘이 먼저 마르지 않는다

```
톰캣 스레드 200 ─── HTTP 커넥션 풀 30 ─── fd 65536 ─── 포트 28232
     ↑ 보통 여기서 먼저 막힘
```

블로킹 모델에서는 스레드 200이 상한이라 동시 아웃바운드가 200을 크게 넘기 어렵다. 커넥션 풀까지 걸면 30개. fd나 포트에 닿을 일이 없다.

### 그래서 진단 관점에서 이렇게 갈린다

> - **스레드풀 / 커넥션풀이 마름** → "**부하가 많다**" → 용량·정책 조정
> - **fd / 포트가 마름** → "**어딘가 새고 있다**" → 용량을 늘릴 게 아니라 **누수를 찾아야 한다**

누수의 전형:
- 커넥션을 안 닫음 (응답 스트림 미소비, `close()` 누락)
- 매 요청 `new RestTemplate()`
- TIME_WAIT 누적 (재사용 없이 초당 470건 이상)
- fd가 애초에 낮게 잡힘 (컨테이너 기본값 1024)

### 정리

| | 자원 범위 | 상한 | 실무에서 |
|---|---|---|---|
| 포트 | 목적지(IP:port)당 | ~28,232 | 재사용 없을 때만 |
| fd | **프로세스 전역** | `LimitNOFILE` | 누수 or 설정 미스 |

**단, fd는 아웃바운드만의 상한이 아니다.** 톰캣이 받은 인바운드 커넥션도 fd를 먹는다. `maxConnections` 8192면 인바운드만으로 8192개를 쓰므로, 아웃바운드를 아무리 잘 관리해도 `LimitNOFILE`은 넉넉히(65536) 잡아야 한다.

## Q12. fd 한계에 도달하는 예시는?

---

### 먼저 산수 — Spring Boot 앱은 idle에도 fd를 쓴다

```
JVM이 열어둔 jar 파일들     200~400   ← 클래스로딩 때문에 계속 열려있음
로그 파일                     2~5
Hikari 커넥션                10
Kafka 컨슈머/프로듀서 소켓    브로커 수 × N
epoll 인스턴스, 파이프        수십
톰캣 listen 소켓 등            수 개
────────────────────────────────────
합계                        300~500
```

> ~~Spring Boot 앱은 jar만으로 200~400개를 쓴다.~~
> **정정 — 실행 방식에 따라 크게 갈린다.** fat jar(`java -jar app.jar`)는 중첩 jar를 바깥 jar 하나로 읽어 수십 개 수준이고, `bootRun`이나 전개된 클래스패스는 의존성 jar 수만큼 열려 수백 개가 된다. 위 합계는 **전개 클래스패스 기준 추정치이며 직접 재보지 않았다.** 자기 환경 값은 아래로 확인하는 게 맞다.
>
> ```bash
> ls /proc/<pid>/fd | wc -l
> ls -l /proc/<pid>/fd | grep '\.jar' | wc -l
> ```

**컨테이너 기본값이 1024면 실질 여유가 500~700개뿐.** 인바운드 몇백 개만 들어와도 닿는다.
→ "누수가 있어야만 터진다"고 했지만, **설정이 낮으면 정상 동작만으로도 터진다.**

### 사례 1. 매번 새 HttpClient 생성 — 가장 흔함

```java
// 잘못된 예
public PayResult confirm(PayRequest req) {
    PoolingHttpClientConnectionManager cm = new PoolingHttpClientConnectionManager();
    CloseableHttpClient client = HttpClients.custom().setConnectionManager(cm).build();
    RestTemplate rt = new RestTemplate(new HttpComponentsClientHttpRequestFactory(client));
    return rt.postForObject("/confirm", req, PayResult.class);
    // client.close() 없음 → 소켓이 방치됨
}
```

풀을 만들어놨는데 **매 요청 새 풀**이라 재사용이 0. GC가 언젠가 정리하겠지만 **fd 증가 속도가 GC보다 빠르면 그냥 터진다.**
`WebClient`, `OkHttpClient`, `KafkaConsumer` 모두 동일. **→ 전부 싱글톤 빈으로.**

### 사례 2. 응답 본문 미소비 — 에러 상황에서만 샌다

```java
// 잘못된 예
CloseableHttpResponse res = client.execute(req);
if (res.getCode() != 200) {
    throw new ExternalApiException();   // 여기서 탈출 → 반납 안 됨
}
return parse(EntityUtils.toString(res.getEntity()));
```

Apache HttpClient는 **본문을 끝까지 읽어야 커넥션을 풀에 반납한다.**

> **고약한 점: 평소엔 멀쩡하다가 외부가 500을 뿜기 시작하면 그때부터 fd가 오른다.**
> **외부 장애가 우리 서버 사망으로 이어지는 경로.**

### 사례 3. Files 스트림 — 배치에서 잘 샌다

```java
// 잘못된 예
Files.list(Paths.get("/data/settlement"))
     .filter(p -> p.toString().endsWith(".csv"))
     .forEach(this::process);

// 올바른 예
try (Stream<Path> paths = Files.list(dir)) {
    paths.filter(...).forEach(...);
}
```

`Files.list/walk/lines`가 반환하는 Stream은 **디렉터리 핸들(fd)을 잡는다.** 정산 배치에서 파일을 다룬다면 눈여겨볼 자리.

### 사례 4. CLOSE_WAIT 누적 — 시그니처 증상

**TIME_WAIT는 fd를 안 먹지만, CLOSE_WAIT는 먹는다.** 이 대비가 진단의 핵심.

```
상대 ──FIN──▶ 우리        (외부 서버가 타임아웃으로 연결을 끊음)
우리 ──ACK──▶ 상대        (커널이 자동 응답)
     │
     └─ CLOSE_WAIT 진입. 여기서 멈춤.
        우리 애플리케이션이 close()를 호출해야만 다음 단계로 감.
```

**CLOSE_WAIT는 타임아웃이 없다.** 프로세스가 죽을 때까지 남는다.

| 상태 | fd 소모 | 자연 해소 | 의미 |
|---|---|---|---|
| TIME_WAIT | 안 함 | 60초 | 정상. 재사용을 안 할 뿐 |
| **CLOSE_WAIT** | **함** | **안 됨 (영구)** | **우리 코드 버그** |

> `ss`에 CLOSE-WAIT가 수백 개 쌓여 있으면 네트워크 문제가 아니라 **우리 코드가 소켓을 안 닫고 있는 것.** (사례 1·2가 대표 원인)

### 사례 5. 인바운드만으로도

```
maxConnections = 8192   (톰캣 기본)
LimitNOFILE   = 1024
```

스파이크로 커넥션 1000개가 들어오면 `IOException: Too many open files`.

**이 상태가 최악인 이유: 로그도 못 남기고 헬스체크도 못 받는다.** 프로세스는 살아있으니 LB는 정상으로 보고 트래픽을 계속 보낸다. **재시작 전엔 회복 불가한 좀비 상태.**

### 진단

```bash
# 1. 얼마나 썼나 / 한계는 얼마인가
ls /proc/<pid>/fd | wc -l
cat /proc/<pid>/limits | grep "open files"

# 2. 뭘로 썼나 — 소켓인지 파일인지가 바로 갈림
ls -l /proc/<pid>/fd | awk '{print $NF}' | sed 's/[0-9]*$//' | sort | uniq -c | sort -rn

# 3. 소켓이면 상태 분포
ss -tanp | grep <pid> | awk '{print $1}' | sort | uniq -c
#   CLOSE-WAIT 다수        → 우리 코드가 안 닫는 중
#   ESTAB 다수 + 목적지 하나 → 풀 없이 계속 여는 중

# 4. 어느 목적지인가
ss -tanp | grep CLOSE-WAIT | awk '{print $5}' | sort | uniq -c | sort -rn

# 5. 컨테이너 안에서 실제 적용값
cat /proc/1/limits | grep "open files"
```

### 예방이 더 중요

Micrometer 기본 제공 지표:

```
process.files.open / process.files.max > 0.8   → 알람
```

> **fd 그래프 읽는 법: 톱니 모양이면 정상, 계단식 우상향이면 누수.**
> 부하와 무관하게 계속 오르면 누수다.

로컬(맥/우분투)에서는 기본값이 높아 재현이 안 되고 **운영에서만 터지는** 전형적 케이스.

## Q13. 애플리케이션에서 소켓을 직접 닫아야 할 일이 있나?

---

**`Socket` 객체를 직접 다룰 일은 거의 없다. 그 감각은 맞다.**

다만 질문을 이렇게 바꾸면 답이 달라진다:
> **"소켓을 쥐고 있는 객체를 닫아야 할 일이 있는가?"** → 이건 자주 있다.

### 닫지 않아도 되는 것 (대부분)

```java
restTemplate.postForObject(...)      // 내부에서 response.close()까지 처리
jdbcTemplate.query(...)              // ResultSet/Statement/Connection 정리
@Transactional + JPA                 // 커밋/롤백 시 커넥션 반납
webClient.retrieve().bodyToMono()    // 시그널 완료 시 해제
```

**템플릿 메서드 패턴** — 자원 획득~해제를 프레임워크가 감싸고 우리는 가운데 로직만 넣는 구조라 샐 틈이 없다. Spring 추상화의 핵심 가치 중 하나.

> **그래서 Q12의 fd 누수 대부분은 "닫는 걸 잊어서"가 아니라 "추상화 밖으로 나갔을 때" 생긴다.**

### 닫아야 하는 것

**① 스트리밍으로 받을 때** — 정산에서 대용량 파일/리포트를 받아올 때. 통째로 메모리에 올리면 OOM이라 스트리밍으로 받는데, 여기가 추상화 밖이다.

```java
restTemplate.execute(url, HttpMethod.GET, null, response -> {
    try (InputStream is = response.getBody()) {   // ← 필요
        return parseCsv(is);
    }
});
```

`ResponseExtractor`를 직접 쓰는 순간 스트림 수명이 우리 책임이 된다. `getForObject`는 알아서 닫아주지만 이건 아니다.

**② 클라이언트를 직접 생성할 때** — 싱글톤 빈이면 앱 종료 시 정리되므로 OK. 문제는 메서드 안에서 `new` 하는 경우(= 애초에 하면 안 되는 것).

**③ Files 스트림** — `Files.list/walk/lines`

**④ 수동 생성한 `KafkaConsumer`** — `@KafkaListener`는 컨테이너가 관리하지만 직접 생성했다면 `close()` 필요

### 진짜 원인은 "안 썼다"보다 "예외 경로"

```java
InputStream is = response.getBody();
Data d = parse(is);        // ← 여기서 파싱 실패하면
is.close();                // ← 도달 못 함
```

**정상 흐름에선 완벽하게 닫히고, 외부가 이상한 응답을 주기 시작할 때만 샌다.** 평소엔 안 보이다가 외부 장애 때 같이 무너지는 이유.

> `try-with-resources`를 쓰는 이유는 "닫는 걸 잊지 않게"가 아니라 **"예외가 나도 닫히게"** 하는 것. finally의 문법 설탕.

### 판별 규칙

> **`AutoCloseable`을 반환하는 메서드를 직접 호출했다면, 닫는 것은 내 책임.**

타입에 이미 적혀 있다: `InputStream`, `Stream<Path>`, `CloseableHttpResponse`, `Connection`, `KafkaConsumer`

### 팀 차원

정적 분석이 사람 눈보다 낫다. CI에 붙이면 리뷰에서 놓쳐도 걸린다.
- SpotBugs `OBL_UNSATISFIED_OBLIGATION`
- SonarQube `S2095`

# 정정 사항 모음

---

대화 중 잘못 말했다가 바로잡은 것들. **틀리기 쉬운 지점이라 따로 모아둠.**

| # | 처음 설명 | 정정 |
|---|---|---|
| 1 | 톰캣 "커넥션풀" | 톰캣은 **스레드풀**(`maxThreads`), 커넥션풀은 DB(Hikari) 쪽 |
| 2 | WebFlux를 쓰면 톰캣 스레드를 반납 | **서블릿 비동기**가 톰캣 스레드를 반납. WebFlux는 톰캣을 아예 안 씀(Netty) — 별개 개념 |
| 3 | 포트가 마르면 DB 연결도 실패 | **4-튜플 식별**이라 목적지가 다르면 같은 로컬 포트 재사용 가능. **부분 장애**이지 전면 장애 아님 |
| 4 | TIME_WAIT가 fd를 소모 | **소모하지 않음.** `close()` 시 fd는 이미 반납. 4-튜플 슬롯 + 커널 메모리만 점유. **fd를 먹는 건 CLOSE_WAIT** |
| 5 | `SimpleClientHttpRequestFactory`는 풀이 없어 매 요청 새 커넥션 | `HttpURLConnection`에 **`KeepAliveCache`가 있다**(목적지당 5개). 문제는 재사용이 **조건부**(본문 미소비·에러 시 깨짐)이고 상한·타임아웃을 통제할 수 없다는 것 |
| 6 | `supplyAsync`로 옮기면 톰캣 풀 대신 그 풀이 마른다 | `commonPool` parallelism은 **코어 수 − 1**. 200 → 7로 **줄어드는** 것이라 악화. JVM 전역 공유라 다른 코드까지 굶음 |
| 7 | `acceptCount`가 곧 OS backlog | 실효값은 **`min(acceptCount, somaxconn)`**. 커널에서 잘린다 |
| 8 | 타임아웃 3종을 `RequestConfig`에 다 건다 | HttpClient 5.x에서 connect는 **`ConnectionConfig`** 로 이동. `RequestConfig` 쪽은 deprecated |
| 9 | Spring Boot는 jar만으로 fd 200~400 | 실행 방식에 따라 갈림(fat jar는 수십 개). **직접 재봐야 하는 값** |

# 우선순위 (정산 시스템 기준)

---

1. **타임아웃 3종 설정** — 안 하면 나머지가 다 무의미. 투자 대비 효과 최대
2. **커넥션 풀 + keep-alive** (`HttpComponentsClientHttpRequestFactory`) — 포트/fd/TIME_WAIT 동시 해결
3. **Circuit Breaker + Bulkhead** — 장애 전파 차단
4. **외부 호출을 트랜잭션 밖으로** — 락/커넥션 점유 시간 단축
5. **멱등키 + 결과 조회 API + 보정 배치** — 정합성 확보
6. **`LimitNOFILE` 상향(65536), `maxConnections` 하향**
7. **비동기가 필요하면 메시지 큐로** — 스레드 모델을 바꾸는 것보다 애초에 동기 요청-응답을 안 하는 편이 낫다

> WebFlux는 "외부 호출이 매우 많고 짧으며 로직은 단순한" 게이트웨이/프록시성 서비스에서 빛난다.
> **DB 트랜잭션이 핵심인 정산 도메인에는 다른 처방이 맞다.**

# 학습 키워드

---

## A. 회복 탄력성 (Resilience) — Resilience4j

---

**Circuit Breaker**
- 3-state: CLOSED / OPEN / HALF_OPEN
- `slidingWindowType` (COUNT_BASED vs TIME_BASED), `slidingWindowSize`
- `failureRateThreshold`, `slowCallRateThreshold`, `slowCallDurationThreshold`
- `minimumNumberOfCalls` — 표본이 적을 때의 임계값 함정
- `waitDurationInOpenState`, `permittedNumberOfCallsInHalfOpenState`
- `recordExceptions` / `ignoreExceptions` — 4xx를 실패로 셀 것인가
- Fallback 전략: 캐시된 값 / 기본값 / fail-fast

**나머지 모듈**
- Bulkhead (SEMAPHORE vs THREAD_POOL)
- Retry — Exponential Backoff, **Jitter**, Retry Budget
- RateLimiter, TimeLimiter
- **데코레이터 합성 순서**
- Hystrix → Resilience4j 전환 배경

**패턴 개념**
- Cascading Failure, **Retry Storm**, Thundering Herd
- **Graceful Degradation**, Fail Fast
- Load Shedding, Backpressure
- Timeout Budget / Deadline Propagation
- 📖 *Release It!* (Michael Nygard) — Circuit Breaker 패턴의 원전

## B. 커널 / 네트워크 자원

---

**TCP**
- **4-tuple**, ephemeral port, `ip_local_port_range`
- TCP 상태 전이도 — 특히 **TIME_WAIT vs CLOSE_WAIT vs FIN_WAIT**
- 2×MSL, `TCP_TIMEWAIT_LEN`
- `tcp_tw_reuse` / `tcp_tw_recycle`(제거됨, 이유 포함)
- TCP Keep-Alive vs HTTP Keep-Alive — **다른 개념**
- `somaxconn`, `tcp_max_syn_backlog`
- `EADDRNOTAVAIL` → `BindException: Cannot assign requested address`

**File Descriptor**
- `fs.file-max` / `ulimit -n`(soft·hard) / `LimitNOFILE` / `--ulimit nofile`
- `/proc/<pid>/limits`, `/proc/<pid>/fd`
- `EMFILE` vs `ENFILE`
- 컨테이너 환경의 fd 상속

**도구**: `ss`, `netstat`, `lsof`, `/proc`, `tcpdump` 기본

## C. I/O 모델 & 동시성

---

- Blocking / Non-blocking / Sync / Async **4분면**
- `select` → `poll` → **`epoll`** (edge vs level triggered)
- Event Loop, Reactor Pattern
- C10K Problem
- Servlet 3.0 Async (`DeferredResult`, `Callable`, `AsyncContext`)
- Servlet 3.1 Non-blocking I/O
- Reactive Streams 스펙 (`Publisher`/`Subscriber`/`Subscription`/`Processor`)
- Project Reactor: `Mono`, `Flux`, Backpressure, Scheduler
- **R2DBC** — 그리고 JPA를 못 쓰는 이유
- **Virtual Threads (Project Loom, JDK 21)** — 블로킹 코드를 그대로 두고 스레드 제약을 푸는 방향. WebFlux의 대안
- `CompletableFuture`, `ForkJoinPool.commonPool`의 함정

## D. 톰캣 / 서블릿 컨테이너

---

- `maxThreads`, `minSpareThreads`, `maxConnections`, `acceptCount`, `connectionTimeout`
- **BIO / NIO / NIO2 / APR 커넥터**의 차이
- `keepAliveTimeout`, `maxKeepAliveRequests`
- `ClientAbortException`과 **취소 전파가 없는 이유**
- Graceful Shutdown (`server.shutdown=graceful`)

## E. HTTP 클라이언트

---

- `RestTemplate` / `RestClient`(Spring 6.1+) / `WebClient` / `FeignClient` 비교
- `SimpleClientHttpRequestFactory` vs `HttpComponentsClientHttpRequestFactory`
- `PoolingHttpClientConnectionManager`: `maxTotal`, `defaultMaxPerRoute`
- **타임아웃 3종**: connect / response(read) / connectionRequest
- `validateAfterInactivity`, `evictIdleConnections` — **stale connection 문제**
- HTTP/1.1 keep-alive vs HTTP/2 multiplexing

## F. JVM / GC

---

- Generational GC, Young → Old **Promotion**
- Premature Promotion, Allocation Rate
- G1GC 튜닝 기본, Stop-The-World
- `-XX:+HeapDumpOnOutOfMemoryError`, MAT로 누수 추적

## G. 트랜잭션 & 정합성 (정산 도메인 직결)

---

- **트랜잭션 경계 설계** — 외부 호출을 제외하는 원칙
- `@Transactional` 전파 속성 (`REQUIRES_NEW` 활용)
- Lock wait timeout, Deadlock, InnoDB 락 종류
- **Idempotency Key** 설계
- **Transactional Outbox Pattern**
- Saga Pattern (Choreography vs Orchestration)
- Compensating Transaction / 보정 배치
- **Exactly-once의 환상** — at-least-once + 멱등성이 현실적 해법
- 2PC를 안 쓰는 이유
- 정산 도메인의 "미결/미확정" 상태 모델링

## H. 관측 가능성 (Observability)

---

```
process.files.open / process.files.max
hikaricp.connections.pending
tomcat.threads.busy
resilience4j.bulkhead.available.concurrent.calls
resilience4j.circuitbreaker.state
```

- USE Method (Utilization / Saturation / Errors)
- RED Method (Rate / Errors / Duration)
- p50 / p95 / **p99** — 평균이 거짓말하는 이유
- **Little's Law (L = λW)** — 동시성·처리량·응답시간의 관계. 위 숫자들(200, 10, 30)을 정량적으로 정하는 도구
- Distributed Tracing (OpenTelemetry, Jaeger)
- **Tail Latency Amplification**

## I. 아키텍처

---

- **Noisy Neighbor** 문제
- 동기 vs 비동기 통합 설계 판단 기준
- Async API 패턴: `202 Accepted` + 폴링 / 웹훅
- Kafka 기반 비동기 처리와 결과 통지
- API Gateway 레벨의 rate limit / circuit breaker
- Service Mesh (Istio, Envoy) — 회복성을 인프라 레이어로 내리는 방향

## 추천 학습 순서

---

| 순서 | 주제 | 이유 |
|---|---|---|
| 1 | **타임아웃 3종 + 커넥션 풀** | 당장 코드에 적용 가능, 효과 즉시 |
| 2 | **Circuit Breaker + Bulkhead** | Resilience4j 문서 + 로컬 실습 |
| 3 | **TCP 상태 전이도 + fd** | `ss`로 실제 서버를 관찰해보기 |
| 4 | **Little's Law** | 위 모든 숫자를 감이 아니라 계산으로 |
| 5 | **Transactional Outbox** | 정산 시스템 정합성 설계에 직결 |
| 6 | **Virtual Threads** | 향후 이 문제 지형 자체를 바꿀 기술 |

## 참고 자료

---

- [Java 네트워킹의 HTTP Keep-Alive 동작과 `http.maxConnections` (docs.oracle.com/javase/8/.../http-keepalive.html)](https://docs.oracle.com/javase/8/docs/technotes/guides/net/http-keepalive.html) — `HttpURLConnection`의 `KeepAliveCache` 기본 동작. Q6-b·Q8 정정 근거
- [Apache HttpClient 5.x Migration Guide (hc.apache.org/httpcomponents-client-5.2.x/migration-guide)](https://hc.apache.org/httpcomponents-client-5.2.x/migration-guide/index.html) — connect 타임아웃이 `RequestConfig`에서 `ConnectionConfig`로 이동한 배경. Q8 정정 근거
- [Apache Tomcat 9 HTTP Connector 설정 (tomcat.apache.org/tomcat-9.0-doc/config/http.html)](https://tomcat.apache.org/tomcat-9.0-doc/config/http.html) — `maxThreads`, `maxConnections`, `acceptCount`, `connectionTimeout` 기본값
- [`listen(2)` — 백로그 큐와 `somaxconn` (man7.org/linux/man-pages/man2/listen.2.html)](https://man7.org/linux/man-pages/man2/listen.2.html) — backlog가 `somaxconn`으로 잘리는 규칙. Q6-c 정정 근거
- [`tcp(7)` — TCP 소켓 옵션과 `tcp_tw_reuse` (man7.org/linux/man-pages/man7/tcp.7.html)](https://man7.org/linux/man-pages/man7/tcp.7.html) — TIME_WAIT 재사용, `ip_local_port_range` 관련
- [`ForkJoinPool.commonPool()` API 문서 (docs.oracle.com/en/java/javase/21/.../ForkJoinPool.html)](https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/util/concurrent/ForkJoinPool.html) — commonPool의 parallelism이 `availableProcessors() - 1`인 근거. Q7 정정 근거
- [Resilience4j Bulkhead 문서 (resilience4j.readme.io/docs/bulkhead)](https://resilience4j.readme.io/docs/bulkhead) — SEMAPHORE / THREAD_POOL 차이와 설정 프로퍼티
- [Spring Framework REST Clients (docs.spring.io/spring-framework/reference/integration/rest-clients.html)](https://docs.spring.io/spring-framework/reference/integration/rest-clients.html) — `RestTemplate` / `RestClient` / `WebClient`와 `ClientHttpRequestFactory` 구현체
