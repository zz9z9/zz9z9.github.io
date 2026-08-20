---
title: WEB - connectTimeout / readTimeout 은 어디서 세팅되고, 어디서 적용되는가
date: 2026-08-19 22:00:00 +0900
categories: [지식 더하기, 이론]
tags: [WEB, JAVA]
---

> `setConnectTimeout` / `setReadTimeout` 은 호출하는 순간엔 **필드에 값을 저장할 뿐**이다.
> 그 값이 실제로 소비되는 곳은 소켓 `connect()` 와 소켓 `read()` 두 곳이고,
> 커넥션 풀 클라이언트(HttpClient5)는 여기에 "풀에서 커넥션 빌리는 대기"가 하나 더 붙는다.
> 이 글은 그 "세팅 지점"과 "적용 지점"을 실제 코드와 발동 스택트레이스로 확인한다.

**검증 환경**
- 실행: `spring-web 6.2.5` (Spring Boot 3.4.4), `httpclient5 5.4.2`, Temurin JDK `21.0.10`
- 인용한 소스 라인은 JDK `21.0.7` 의 `src.zip`, `spring-web 6.2.5-sources`, `httpclient5 5.4.2-sources`, `httpcore5 5.3.3-sources` 기준
- 스택트레이스만 `21.0.10` 실행 결과다. 두 버전 사이에 `HttpURLConnection.java` 의 줄 번호가 몇 줄 어긋나므로 스택의 숫자와 본문 인용이 다를 수 있다 (다른 파일은 동일)
- 발동 스택트레이스는 아래 [검증 코드](#검증-코드)를 실제로 돌려 얻은 출력

**출발점 — 실제 클라이언트 코드**

```java
@Component
public class ExternalLimitClient {

    private final RestTemplate restTemplate;

    public ExternalLimitClient(
            @Value("${external.api.base-url}") String baseUrl,
            @Value("${external.api.read-timeout-ms}") int readTimeoutMs) {
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setReadTimeout(readTimeoutMs);     // ★ 여기서 뭐가 일어나는가?
        this.restTemplate = new RestTemplate(factory);
        this.baseUrl = baseUrl;
    }

    public LimitCheckResponse checkLimit(String orderNo, int amount) {
        return restTemplate.getForObject(
                baseUrl + "/limits/" + orderNo + "?amount=" + amount,
                LimitCheckResponse.class);
    }
}
```

`SimpleClientHttpRequestFactory` 는 **`java.net.HttpURLConnection` 기반**이다. `new RestTemplate()` 처럼 factory 를 안 주면 `HttpAccessor:56` 의 필드 기본값으로 이게 그대로 쓰인다. (`spring-boot-starter-web` 만 있으면 httpclient5 는 클래스패스에 없음. `RestTemplateBuilder` / `RestClient` 는 클래스패스의 클라이언트를 자동 선택하지만, 직접 생성은 항상 이 구현체다.)

## 1. 큰 그림 — 값의 여정

---

타임아웃 값은 여러 번 옮겨 적히지만 **전부 메모리 대입**이고, 시간이 실제로 소비되는 곳은 맨 끝 두 군데뿐이다.

```text
[세팅 — 필드 대입만, I/O 없음]

  factory.setConnectTimeout / setReadTimeout
    → SimpleClientHttpRequestFactory 의 int 필드              (앱 시작 시 1회)
    → prepareConnection() 에서 URLConnection 의 int 필드로     (요청마다)

[전달 — connect() 시점에 소켓까지 운반]

  connectTimeout → HttpClient.New(url, proxy, connectTimeout) 생성자 인자
  readTimeout    → http.setReadTimeout() → serverSocket.setSoTimeout()

[적용 — 시간이 실제로 소비되는 곳]

  connectTimeout → Socket.connect(addr, timeout)
                     → NioSocketImpl#timedFinishConnect   "Connect timed out"
  readTimeout    → 소켓 read() 호출마다
                     → NioSocketImpl#timedRead            "Read timed out"
```

> 핵심: **세팅 시점(요청 준비)과 적용 시점(소켓 connect / read)이 다르다.** 그래서 keep-alive 재사용이면 connectTimeout 은 아예 안 쓰이고, readTimeout 은 read 호출마다 다시 카운트된다.
> 실무에서 흔한 커넥션 풀 클라이언트(HttpClient5)는 6장에서 다룬다 — 세팅 위치와 "풀 대기" 축이 추가될 뿐, 최종 적용 지점은 동일하다.

전체 흐름을 애플리케이션 / JDK(유저 공간) / 커널 레벨로 나누면 다음과 같다. 각 단계의 코드 근거는 2~4장에서 확인한다.

![connectTimeout / readTimeout 흐름 — 애플리케이션(Spring) · JDK 유저 공간(java.net · sun.nio.ch) · 커널 3개 레인 스윔레인 다이어그램. ① 세팅은 factory → URLConnection 필드 대입뿐이라 소켓도 패킷도 없고, ② 커넥션 확보에서 keep-alive 캐시 HIT 면 connectTimeout 을 아예 안 쓰며 MISS 경로의 DNS 조회는 어떤 타임아웃도 덮지 못하고, ③ connect() 는 fcntl(O_NONBLOCK) → connect(2) EINPROGRESS → timedFinishConnect 의 park(POLLOUT, 남은 시간) 루프에서 connectTimeout 을 소비해 시간 초과 시 "Connect timed out", ④ 응답 read 는 read(2) EAGAIN → timedRead 의 park(POLLIN, 남은 시간) 루프에서 readTimeout 을 소비하되 read 호출마다 startNanos 가 리셋된다](/assets/img/connect-readtimeout-img1.svg)

## 2. 세팅 지점 — 전부 필드 대입

---

### 2-1. Spring: `prepareConnection`

> 요청마다 `SimpleClientHttpRequestFactory#createRequest` 가 `URL#openConnection()` 으로 `HttpURLConnection` **객체만** 만들고(이 시점 소켓 FD 없음, 패킷 0), 바로 타임아웃을 옮겨 적는다.

```java
// org.springframework.http.client.SimpleClientHttpRequestFactory
private int connectTimeout = -1;
private int readTimeout = -1;

protected void prepareConnection(HttpURLConnection connection, String httpMethod) throws IOException {
    if (this.connectTimeout >= 0) {
        connection.setConnectTimeout(this.connectTimeout);
    }
    if (this.readTimeout >= 0) {
        connection.setReadTimeout(this.readTimeout);
    }
    ...
}
```

`-1`(기본값)이면 `setConnectTimeout` 을 **호출조차 안 한다.** `URLConnection` 의 기본값은 `0` = 무한 — 즉 `new RestTemplate()` 은 connect 도 read 도 무한 대기다. 위 `ExternalLimitClient` 도 readTimeout 만 걸었으므로 **connect 는 무한**이다.

### 2-2. JDK: `URLConnection` 의 setter 도 대입뿐

```java
// java.base/java/net/URLConnection.java
public void setConnectTimeout(int timeout) {
    if (timeout < 0) {
        throw new IllegalArgumentException("timeout can not be negative");
    }
    connectTimeout = timeout;      // 끝. 검증 + 대입.
}
```

`setReadTimeout` 도 똑같다. 여기까지 소켓은 존재하지도 않는다.

## 3. connectTimeout 적용 지점 — `connect()` 안의 단 한 줄

---

### 3-1. 값이 소켓까지 가는 길

`HttpURLConnection#connect()` → `plainConnect0()` 에서 필드에 들어 있던 값이 드디어 움직인다.

```java
// sun.net.www.protocol.http.HttpURLConnection#plainConnect0  (21.0.7 :1252~1253)
// (프록시 유무에 따라 분기가 여럿이지만 모든 분기가 이 두 줄 패턴이다)
http = getNewHttpClient(url, p, connectTimeout);   // ① connectTimeout 은 생성자 인자로
http.setReadTimeout(readTimeout);                  // ② readTimeout 은 소켓 SO_TIMEOUT 에 기록 (→ 4장)
```

①은 `HttpClient.New(...)` 인데, **먼저 keep-alive 캐시를 조회한다** (`HttpClient.java:341` `kac.get(url, null)`). HIT 이면 기존 ESTABLISHED 소켓을 재사용하므로 아래 경로 전체가 스킵된다 — **connectTimeout 은 새 TCP 연결을 만들 때만 의미가 있다.**

MISS 면 `HttpClient` 생성자 → `openServer()` → `NetworkClient#doConnect` 로 내려간다. 여기가 값이 소켓 API 에 꽂히는 지점이다.

```java
// sun.net.NetworkClient#doConnect  (21.0.7 :152)
protected Socket doConnect (String server, int port)
        throws IOException, UnknownHostException {
    Socket s;
    ...
    s = createSocket();                    // FD 할당, TCP 는 아직 CLOSED

    if (connectTimeout >= 0) {
        s.connect(new InetSocketAddress(server, port), connectTimeout);   // :178 ★ 적용
    } else {
        if (defaultConnectTimeout > 0) {
            s.connect(new InetSocketAddress(server, port), defaultConnectTimeout);
        } else {
            s.connect(new InetSocketAddress(server, port));               // 무한 대기
        }
    }
    if (readTimeout >= 0)
        s.setSoTimeout(readTimeout);       // :187  SO_TIMEOUT 에 기록. 단 이 경로에선 readTimeout 이 -1 이다 (4-1)
    else if (defaultSoTimeout > 0) {
        s.setSoTimeout(defaultSoTimeout);
    }
    return s;
}
```

이 메서드에 함정이 두 개 있다.

1. **DNS 는 connectTimeout 밖이다.** `new InetSocketAddress(server, port)` 가 인자 평가 시점에 DNS 를 먼저 조회한다. resolve 가 5초 걸리면 connectTimeout 1초여도 총 6초.
2. `defaultConnectTimeout` / `defaultSoTimeout` 은 시스템 프로퍼티 `sun.net.client.defaultConnectTimeout` / `defaultReadTimeout` 이고 기본 `0`(무한). 마지막 안전망조차 기본은 없다.

### 3-2. 시간이 소비되는 곳: `timedFinishConnect`

`s.connect(addr, timeout)` → `NioSocketImpl#connect` 는 timeout 이 있으면 FD 를 논블로킹으로 바꾸고 native `connect(2)` 가 `EINPROGRESS` 를 내면 남은 시간만큼만 `poll(2)` 로 기다린다.

<details markdown="1">
<summary>배경: FD · 논블로킹 · connect(2) · EINPROGRESS · poll(2)</summary>

**FD (file descriptor)** — 커널이 프로세스에 열어준 자원(파일, 소켓, 파이프…)을 가리키는 정수 번호. 자바의 `Socket` 객체는 결국 이 번호 하나를 들고 커널에 시스템 콜을 요청하는 껍데기다.

**`connect(2)` / `poll(2)` 의 "(2)"** — 유닉스 매뉴얼 섹션 2 = 시스템 콜이라는 표기. 패킷을 보내고 연결을 수립하는 일은 JVM 이 직접 못 하고 전부 커널에 시스템 콜로 시킨다.

**블로킹 모드의 문제** — 소켓 기본 모드에서 `connect(2)` 를 부르면 커널이 3-way handshake 가 끝나거나 실패할 때까지 **스레드를 재워 버린다.** 이때 "몇 초만 기다려라"를 인자로 줄 방법이 없다 — 얼마나 기다릴지는 커널의 SYN 재전송 정책이 정한다(보통 수십 초~수 분). 즉 블로킹 connect 로는 애플리케이션이 원하는 타임아웃을 정확히 걸 수 없다.

**논블로킹(O_NONBLOCK)** — FD 에 이 플래그를 켜면 커널은 어떤 호출에서도 스레드를 재우지 않고 즉시 리턴한다. 논블로킹 상태에서 `connect(2)` 를 부르면 커널은 SYN 만 보내 놓고 `EINPROGRESS` 를 즉시 돌려준다. 이름은 에러 코드지만 실패가 아니라 **"연결은 백그라운드에서 진행 중이니 나중에 확인해라"** 는 신호다.

**`poll(2)`** — "이 FD 에 이벤트가 생길 때까지 **최대 N ms** 만 재워달라"는 시스템 콜. 연결 완료는 '쓰기 가능(POLLOUT)', 데이터 도착은 '읽기 가능(POLLIN)' 이벤트로 나타난다. **타임아웃을 인자로 받는다는 것**이 블로킹 connect/read 와의 결정적 차이다.

O_NONBLOCK 과 poll 은 서로 독립적인 기능이고, O_NONBLOCK 을 켠다고 poll 이 자동으로 걸리는 것도 아니다. poll 은 상주 감시자가 아니라 **호출할 때마다 한 번 "재워달라" 하고, 리턴하면 끝**이다. 그 사이 소켓 상태는 poll 을 부르든 안 부르든 커널 네트워크 스택이 알아서 갱신한다 — 패킷이 도착하면 커널이 수신 버퍼를 채우고 소켓을 '읽기 가능'으로 표시한 뒤, 그 소켓을 기다리며 잠들어 있는 스레드가 있으면 깨운다. 즉 논블로킹 전환의 의미는 **"기다리는 일"을 read/connect 안에서 poll 호출로 옮기는 것**이고, 옮기는 이유는 poll 만 타임아웃을 인자로 받기 때문이다.

조합하면 이렇게 된다:

```text
자바 스레드                                  커널
│  connect(2)          ── 논블로킹 ──▶     │  SYN 전송, 연결 진행 시작
│  ◀── EINPROGRESS 즉시 리턴 ──────────    │
│                                        │
│  poll(2, POLLOUT, 남은시간)   ────▶      │
│      …잠…                              │  SYN+ACK 도착 → FD가 '쓰기 가능'으로
│  ◀── 이벤트 발생 or 시간 만료로 깨어남 ──     │
│                                        │
│  연결 성립했나 확인 (pollConnectNow)       │
│  안 됐으면 남은 시간 재계산 → 다시 poll       │
│  시간 초과 → SocketTimeoutException      │
```

즉 커널에는 "타임아웃 있는 connect" 라는 시스템 콜이 없다. JVM 은 **논블로킹 connect + 타임아웃 있는 poll** 두 개를 조합해서 그걸 흉내 낸다. 4-2 의 `timedRead` 도 이벤트가 POLLIN 으로 바뀔 뿐 완전히 같은 구조다.

이걸 알고 `timedFinishConnect` 루프를 다시 보면 "**잔다 → 깨어나면 진짜 끝났는지 확인 → 안 끝났으면 남은 시간만큼만 다시 잔다**"의 반복이다. 부품별 역할:

| 코드 | 역할 |
|---|---|
| `Net.pollConnectNow(fd)` | **확인** — 기다리지 않고(타임아웃 0) "연결 결판났어?"를 커널에 물음. 성립 → `true`, 진행 중 → `false`, 실패(RST 등) → 예외 |
| `park(fd, POLLOUT, remainingNanos)` | **대기** — FD 가 쓰기 가능해지거나 남은 시간이 다 되면 깨어남. **깨워주기만 하지 결과는 안 알려줌** |
| `while (!polled && isOpen())` | 연결이 아직 안 됐고, 다른 스레드가 소켓을 `close()` 하지도 않았으면 반복 |
| `remainingNanos <= 0 → throw` | 깨어날 때마다 `startNanos` 기준으로 남은 시간 재계산 — 몇 번을 깨어나도 전체 대기가 상한을 못 넘음 |

루프가 필요한 이유는 park 가 깨어나는 이유가 "연결 성공" 하나가 아니기 때문이다 — 시간 만료일 수도, 연결 **실패**로 FD 가 ready 가 된 것일 수도, 시그널·spurious wakeup 으로 일찍 깨어난 것일 수도 있다. 그래서 깨어나면 반드시 `pollConnectNow` 로 재확인한다.

시나리오별 흐름:

- **즉시 성립**(루프백 등): 첫 `pollConnectNow` 가 `true` → 루프에 안 들어감
- **300ms 뒤 SYN+ACK 도착**(connectTimeout 1000ms): park 가 300ms 만에 깨어남 → 확인 `true` → 연결 완료
- **무응답**(blackhole): park 가 남은 시간을 다 쓰고 깨어남 → 확인 `false` → 다음 반복에서 시간 초과 → `"Connect timed out"`
- **거절(RST)**: park 가 즉시 깨어남 → `pollConnectNow` 가 `ConnectException("Connection refused")` — 타임아웃과 다른 예외

</details>

`NioSocketImpl#connect` 가 갈림길이다.

```java
// sun.nio.ch.NioSocketImpl#connect(SocketAddress, int)  :561 발췌
configureNonBlockingIfNeeded(fd, millis > 0);        // :582  timeout>0 이면 FD를 논블로킹으로 전환
int n = Net.connect(fd, address, port);              // :583  native connect(2)
if (n > 0) {
    connected = true;                                // 즉시 성립 (루프백 등)
} else {
    assert IOStatus.okayToRetry(n);                  // EINPROGRESS — 연결은 백그라운드 진행 중
    if (millis > 0) {
        long nanos = MILLISECONDS.toNanos(millis);
        connected = timedFinishConnect(fd, nanos);   // :592 ★ 타임아웃 있는 대기
    } else {
        boolean polled = false;
        while (!polled && isOpen()) {                // FD가 논블로킹인데 timeout 0 인 경우만 (아래 참고)
            park(fd, Net.POLLOUT);                   // nanos 0 → poll(-1) = 무한 poll
            polled = Net.pollConnectNow(fd);
        }
        connected = polled && isOpen();
    }
}
```

"FD 를 논블로킹으로 바꾼다"의 실제 코드는 이 체인이다:

```text
sun.nio.ch.NioSocketImpl#configureNonBlockingIfNeeded          :209
    if (!nonBlocking && (timed || Thread.currentThread().isVirtual())) {
        IOUtil.configureBlocking(fd, false);        // timeout 있을 때만. 가상 스레드는 항상.
        nonBlocking = true;                         // 한 번 바꾸면 기억해 두고 다시 안 바꿈
    }
 └ sun.nio.ch.IOUtil#configureBlocking (native)                 IOUtil.java:588
    └ C 구현 — src/java.base/unix/native/libnio/ch/IOUtil.c:71 (OpenJDK jdk21u)
        int flags = fcntl(fd, F_GETFL);
        int newflags = blocking ? (flags & ~O_NONBLOCK) : (flags | O_NONBLOCK);
        return (flags == newflags) ? 0 : fcntl(fd, F_SETFL, newflags);   // ★ 여기서 플래그 ON
```

즉 `fcntl(2)` 시스템 콜로 커널에 O_NONBLOCK 플래그를 켠다. read 경로(`implRead:301`)도 정확히 같은 함수를 호출한다 — SO_TIMEOUT 이 걸린 소켓의 read 가 논블로킹 + poll 조합으로 도는 이유다.

**timeout 을 안 걸면(0 = 무한) 어떻게 되나** — 논블로킹 + poll 조합은 "타임아웃을 지켜야 할 때만" 쓰는 우회로다. 플랫폼 스레드에서 timeout 이 0 이면 `configureNonBlockingIfNeeded(fd, false)` 는 아무것도 안 하고 FD 는 **블로킹 모드 그대로**다. 그러면 `Net.connect` / `tryRead` 의 `connect(2)` / `read(2)` 자체가 커널 안에서 스레드를 재우므로 **poll 은 아예 등장하지 않는다.** 이때 대기 상한은:

- connect: 커널의 SYN 재전송 정책 (Linux `tcp_syn_retries` 기준 2분대) → `ETIMEDOUT`. "무한"이라기보다 "커널 마음대로"
- read: **진짜 무한.** 데이터가 안 오면 read(2) 안에서 영원히 잔다

위 코드의 `else` 무한 park 루프는 "FD 가 논블로킹인데 timeout 은 0"인 경우용이다:
  - (1) **가상 스레드** — `configureNonBlockingIfNeeded` 의 `timed || isVirtual()` 조건 때문에 항상 논블로킹 (캐리어 스레드를 블로킹 syscall 에 묶을 수 없으므로),
  - (2) **한 번이라도 timed I/O 를 한 소켓** — `nonBlocking` 필드는 켜기만 하고 되돌리는 코드가 없어서, 이후 timeout 없는 호출도 논블로킹 + 무한 poll(`park` 에서 `nanos == 0 → millis = -1`, `Net.poll` javadoc: "-1 to wait indefinitely") 경로를 탄다.

timeout 이 있으면 `timedFinishConnect` 로 온다.

```java
// sun.nio.ch.NioSocketImpl:540
private boolean timedFinishConnect(FileDescriptor fd, long nanos) throws IOException {
    long startNanos = System.nanoTime();
    boolean polled = Net.pollConnectNow(fd);              // 논블로킹 즉시 확인
    while (!polled && isOpen()) {
        long remainingNanos = nanos - (System.nanoTime() - startNanos);
        if (remainingNanos <= 0) {
            throw new SocketTimeoutException("Connect timed out");   // ★ :546
        }
        park(fd, Net.POLLOUT, remainingNanos);            // 남은 시간만큼만 poll
        polled = Net.pollConnectNow(fd);
    }
    return polled && isOpen();
}
```

이때 TCP 는 SYN 을 보내고 **SYN_SENT** 에서 기다리는 중이다. 타임아웃이 나면 catch 블록에서 `close()` 로 FD 가 정리된다(아직 연결 전이라 FIN/RST 없이 폐기). 메시지는 `"Connect timed out"` — 대문자 C. 옛 `PlainSocketImpl` 시절의 `"connect timed out"` 과 다르므로 로그 grep 시 주의.

### 3-3. 실제 발동 — 스택트레이스로 확인

SYN 에 아무도 응답하지 않는 blackhole 주소(`10.255.255.1`)에 `connectTimeout=1000` 으로 호출한 결과다. **스택 자체가 3-1 → 3-2 의 경로 그대로다.**

```text
=== connectTimeout ===
spring: 6.2.5 / java: 21.0.10
elapsed: 1021ms
root cause: java.net.SocketTimeoutException: Connect timed out
  at java.base/sun.nio.ch.NioSocketImpl.timedFinishConnect(NioSocketImpl.java:546)  ← 소비
  at java.base/sun.nio.ch.NioSocketImpl.connect(NioSocketImpl.java:592)
  at java.base/java.net.Socket.connect(Socket.java:751)
  at java.base/sun.net.NetworkClient.doConnect(NetworkClient.java:178)              ← 적용 한 줄
  at java.base/sun.net.www.http.HttpClient.openServer(HttpClient.java:531)
  at java.base/sun.net.www.http.HttpClient.<init>(HttpClient.java:282)
  at java.base/sun.net.www.http.HttpClient.New(HttpClient.java:386)
  at java.base/sun.net.www.protocol.http.HttpURLConnection.getNewHttpClient(HttpURLConnection.java:1324)
  at java.base/sun.net.www.protocol.http.HttpURLConnection.plainConnect0(HttpURLConnection.java:1257)   ← 값 운반 시작
  at java.base/sun.net.www.protocol.http.HttpURLConnection.plainConnect(HttpURLConnection.java:1143)
```

## 4. readTimeout 적용 지점 — 소켓에 적어 두고 read 마다 소비

---

> read 에는 시간 인자가 없다. `s.connect(addr, timeout)` 과 달리 `in.read(buf)` 는 "얼마나 기다릴지" 를 받을 자리가 없어서, 그 값을 소켓 객체에 미리 적어 두고 read 가 꺼내 쓴다. 그 적어 두는 자리가 `SO_TIMEOUT` 이다. 값이 적히는 곳(4-1)과 소비되는 곳(4-2)이 갈리는 이유가 이것이다.

### 4-1. 값을 적는 곳: `setSoTimeout`

|  | connectTimeout | readTimeout |
|---|---|---|
| 전달 방식 | `s.connect(addr, timeout)` 호출 인자 | `s.setSoTimeout(t)` 로 소켓에 기록 |
| 유효 범위 | 그 `connect` 호출 하나 | 덮어쓸 때까지 그 소켓의 모든 read |
| 호출이 끝나면 | 남는 게 없다 | 값이 소켓에 그대로 남는다 |

"소켓에 남는다" 는 바뀌지 않는다는 뜻이 아니라 **아무도 안 바꾸면 그대로**라는 뜻이다. keep-alive 로 소켓을 재사용하면 지난 요청이 적어 둔 값이 그대로 붙어 있고, 그건 이번 요청의 readTimeout 이 아니다. 그래서 JDK 는 요청마다 다시 적는다 — 소켓이 하나여도 요청마다 다른 값이 걸리는 이유다.

#### 적히는 지점 세 곳

`getInputStream()` 한 번이 도는 동안 SO_TIMEOUT 을 건드리는 곳은 세 군데다.

```text
HttpURLConnection#getInputStream0                          :1622
 ├ checkReuseConnection()                                  :1689
 │   └ http.setReadTimeout(getReadTimeout())               :1076   ③ 같은 커넥션 재시도 시 되돌리기
 └ connect() → plainConnect() → plainConnect0()            :1184
     ├ http = getNewHttpClient(url, p, connectTimeout)     :1252
     │   └ HttpClient.New → kac.get(url, null)             :341    캐시 HIT 이면 여기서 끝
     │       └ (MISS) new HttpClient(url, p, to)           :386    ← connectTimeout 만 넘어간다
     │           └ openServer → NetworkClient#doConnect    :152
     │               ├ s.connect(addr, connectTimeout)     :178
     │               └ s.setSoTimeout(readTimeout)         :187    ① 소켓 생성 직후
     └ http.setReadTimeout(readTimeout)                    :1253   ② ★ 사용자 값은 여기서 적힌다
```

**① `NetworkClient#doConnect:187` — 이 경로에선 사용자 값이 아니다.**

`readTimeout` 은 `NetworkClient` 의 필드인데, 위 트리에서 보이듯 `HttpClient` 생성자에는 `to`(connectTimeout)만 넘어간다. `doConnect` 가 도는 시점의 필드는 아직 초기값 `-1` 이라 `if (readTimeout >= 0)` 가 거짓이고, `else` 분기의 `defaultSoTimeout` — 시스템 프로퍼티 `sun.net.client.defaultReadTimeout` — 만 반영된다 (3-1 코드의 마지막 블록).

```java
// sun.net.NetworkClient  (21.0.7 :63)
protected int readTimeout = DEFAULT_READ_TIMEOUT;   // = -1. HttpURLConnection 경로에선 여기 그대로다
```

FTP 처럼 이 필드를 connect 전에 채우는 다른 `NetworkClient` 하위 클래스에서는 :187 이 의미를 갖는다.

**② `plainConnect0:1253` — 사용자 값은 여기서 적힌다.**

3-1 에서 본 두 줄 패턴의 두 번째 줄이다. `getNewHttpClient` 바로 다음 줄이라 **커넥션이 새 것이든 캐시에서 꺼낸 것이든 무조건 이 줄을 지난다.**

```java
// sun.net.www.protocol.http.HttpURLConnection#plainConnect0  (21.0.7 :1252~1253)
http = getNewHttpClient(url, p, connectTimeout);   // 캐시 조회 또는 새 연결
http.setReadTimeout(readTimeout);                  // ★ 이번 요청 값으로 SO_TIMEOUT 덮어쓰기
```

종점은 `Socket#setSoTimeout` 이다.

```java
// sun.net.NetworkClient#setReadTimeout  :259
public void setReadTimeout(int timeout) {
    if (timeout == DEFAULT_READ_TIMEOUT)
        timeout = defaultSoTimeout;

    if (serverSocket != null && timeout >= 0) {
        try {
            serverSocket.setSoTimeout(timeout);      // :265  결국 여기
        } catch(IOException e) {
            // We tried...
        }
    }
    readTimeout = timeout;
}
```

**③ `checkReuseConnection:1070` — JDK 가 임시로 바꿔 둔 값 되돌리기.**

리다이렉트·인증 재시도처럼 같은 커넥션으로 다음 트랜잭션을 이어갈 때 탄다. JDK 내부가 SO_TIMEOUT 을 잠깐 자기 값으로 바꿔 쓰는 구간이 있어서 — `expect100Continue` 는 5초로 낮추고(`:1342`), 에러 스트림 버퍼링은 `timeout4ESBuffer/5` 를 쓴다(`:3908`) — 다음 트랜잭션 전에 사용자 값으로 되돌린다.

```java
// sun.net.www.protocol.http.HttpURLConnection#checkReuseConnection  :1070
private boolean checkReuseConnection () {
    if (connected) {
        return true;
    }
    if (reuseClient != null) {
        http = reuseClient;
        http.setReadTimeout(getReadTimeout());   // :1076  사용자 값으로 원복
        http.reuse = false;
        reuseClient = null;
        connected = true;
        return true;
    }
    return false;
}
```

#### 요청마다 갈리는지 실제로 확인

keep-alive 로 소켓 하나를 재사용하면서 요청마다 readTimeout 을 다르게 줘 봤다. 서버는 `/fast` 는 즉시, `/slow` 는 3초 뒤에 응답한다.

```text
[server] accepted from port 53991
[server] req#1 on port 53991 : GET /fast HTTP/1.1
[client] .../fast readTimeout=5000ms -> ok1 (18ms)
[server] req#2 on port 53991 : GET /slow HTTP/1.1
[client] .../slow readTimeout=300ms -> SocketTimeoutException: Read timed out (301ms)
```

서버가 본 클라이언트 포트가 두 요청 모두 `53991` — 소켓은 하나다. 그런데 2번 요청은 1번이 적어 둔 5초가 아니라 자기 값 300ms 에서 끊겼다.

2번 요청에서 `setReadTimeout` 을 아예 호출하지 않으면, 1번의 5초가 남아 있는 게 아니라 `URLConnection` 기본값 `0`(무한)이 적힌다.

```text
[server] req#2 on port 53994 : GET /slow HTTP/1.1
[client] .../slow readTimeout=-1ms -> ok2 (3002ms)
```

3초를 다 기다리고 정상 수신했다. 이전 값이 남는 게 아니라 **매 요청 덮어쓴다**는 쪽이 맞다.

<details markdown="1">
<summary>검증 코드 (Temurin 21.0.7, 단일 파일 실행)</summary>

```java
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;

public class KeepAliveTimeoutTest {
    public static void main(String[] args) throws Exception {
        ServerSocket ss = new ServerSocket(0, 1, InetAddress.getByName("127.0.0.1"));
        int port = ss.getLocalPort();

        Thread server = new Thread(() -> {
            try (Socket s = ss.accept()) {
                System.out.println("[server] accepted from port " + s.getPort());
                BufferedReader in = new BufferedReader(
                        new InputStreamReader(s.getInputStream(), StandardCharsets.ISO_8859_1));
                OutputStream out = s.getOutputStream();
                for (int i = 1; i <= 2; i++) {
                    String line = in.readLine();
                    if (line == null) return;
                    System.out.println("[server] req#" + i + " on port " + s.getPort() + " : " + line);
                    while (true) { String h = in.readLine(); if (h == null || h.isEmpty()) break; }
                    if (line.contains("/slow")) {
                        Thread.sleep(3000);                 // 응답을 3초 미룬다
                    }
                    byte[] body = ("ok" + i).getBytes(StandardCharsets.ISO_8859_1);
                    out.write(("HTTP/1.1 200 OK\r\nContent-Length: " + body.length + "\r\n\r\n")
                            .getBytes(StandardCharsets.ISO_8859_1));
                    out.write(body);
                    out.flush();
                }
            } catch (Exception e) {
                System.out.println("[server] " + e);
            }
        });
        server.setDaemon(true);
        server.start();

        get("http://127.0.0.1:" + port + "/fast", 5000);   // 새 커넥션
        get("http://127.0.0.1:" + port + "/slow", 300);    // keep-alive 재사용. -1 로 주면 미설정 케이스
    }

    static void get(String url, int readTimeout) throws Exception {
        HttpURLConnection c = (HttpURLConnection) URI.create(url).toURL().openConnection();
        c.setConnectTimeout(1000);
        if (readTimeout >= 0) c.setReadTimeout(readTimeout);
        long t0 = System.nanoTime();
        try (InputStream in = c.getInputStream()) {
            System.out.printf("[client] %s readTimeout=%dms -> %s (%dms)%n", url, readTimeout,
                    new String(in.readAllBytes(), StandardCharsets.ISO_8859_1),
                    (System.nanoTime() - t0) / 1_000_000);
        } catch (SocketTimeoutException e) {
            System.out.printf("[client] %s readTimeout=%dms -> %s: %s (%dms)%n", url, readTimeout,
                    e.getClass().getSimpleName(), e.getMessage(), (System.nanoTime() - t0) / 1_000_000);
        }
    }
}
```

</details>

`Socket#setSoTimeout` 자체는 검증 후 `SocketImpl` 로 넘기는 게 전부다.

```java
// java.net.Socket#setSoTimeout  :1383
public void setSoTimeout(int timeout) throws SocketException {
    if (isClosed())
        throw new SocketException("Socket is closed");
    if (timeout < 0)
        throw new IllegalArgumentException("timeout can't be negative");
    getImpl().setOption(SocketOptions.SO_TIMEOUT, timeout);
}
```

그 `setOption` 의 실체는 아래와 같다.

```java
// sun.nio.ch.NioSocketImpl  :119
private volatile int timeout;

// sun.nio.ch.NioSocketImpl#setOption  :1015
public void setOption(int opt, Object value) throws SocketException {
    synchronized (stateLock) {
        ensureOpen();
        try {
            switch (opt) {
            case SO_LINGER: {
                ...
                Net.setSocketOption(fd, StandardSocketOptions.SO_LINGER, i);   // ← 커널로 내려감
                break;
            }
            case SO_TIMEOUT: {                          // :1031
                int i = intValue(value, "SO_TIMEOUT");
                if (i < 0)
                    throw new IllegalArgumentException("timeout < 0");
                timeout = i;                            // ★ 자바 필드 대입이 전부. Net.setSocketOption 호출이 없다
                break;
            }
            case TCP_NODELAY: {
                boolean b = booleanValue(value, "TCP_NODELAY");
                Net.setSocketOption(fd, StandardSocketOptions.TCP_NODELAY, b); // ← 커널로 내려감
                break;
            }
            ...
```

옆에 있는 `SO_LINGER` / `TCP_NODELAY` 는 전부 `Net.setSocketOption(fd, ...)` 을 타고 `setsockopt(2)` 로 커널까지 내려간다. **`SO_TIMEOUT` 만 `timeout = i;` 한 줄로 끝난다.** 읽는 쪽도 똑같다.

```java
// sun.nio.ch.NioSocketImpl#getOption  :1100
public Object getOption(int opt) throws SocketException {
    synchronized (stateLock) {
        ensureOpen();
        try {
            switch (opt) {
            case SO_TIMEOUT:
                return timeout;              // :1105  커널에 안 물어본다. 방금 넣은 값을 그대로 돌려줄 뿐
            ...
```

#### SO_TIMEOUT 은 애초에 커널 소켓 옵션이 아니다

이름이 `SO_` 로 시작하고 `SO_LINGER`, `SO_RCVBUF`, `SO_KEEPALIVE` 와 같은 `SocketOptions` 인터페이스에 나란히 선언돼 있어서 **POSIX 소켓 옵션처럼 보이지만, SO_TIMEOUT 이라는 커널 옵션은 존재하지 않는다.** 자바가 자기 상수 테이블에만 정의해 둔 번호다.

```java
// java.net.SocketOptions  :273
@Native public static final int SO_TIMEOUT = 0x1006;
```

리눅스에 굳이 대응되는 진짜 옵션을 찾자면 `SO_RCVTIMEO` 인데, `NioSocketImpl` 은 그걸 쓰지 않는다. 대신 4-2 에서 볼 `timedRead` 가 **논블로킹 read + 타임아웃 있는 `poll(2)`** 를 조합해 같은 효과를 유저 공간에서 만들어 낸다. 3-2 의 connect 와 정확히 같은 패턴이다 — 커널에 "타임아웃 있는 read" 라는 syscall 이 없으니 JVM 이 흉내 내는 것이다.

#### 커널로 안 내려간다는 게 실무에서 뜻하는 것

| | 커널 옵션이었다면 | 실제 (자바 필드) |
|---|---|---|
| 설정 시 syscall | `setsockopt(2)` 발생 | **아무 syscall 도 안 일어남** |
| `strace` / `dtruss` | `setsockopt` 로 관측됨 | **안 보임** |
| 적용 범위 | 그 fd 를 쓰는 모든 recv 경로 | **`NioSocketImpl#timedRead` 를 타는 read 만** |
| 프로세스 밖에서 확인 | `getsockopt` 로 조회 가능 | **불가능. JVM 힙 안의 int 일 뿐** |

실제로 걸리는 함정들:

- **`ss`, `netstat`, `strace` 로 "이 소켓 readTimeout 이 얼마냐" 를 볼 수 없다.** 커널은 그런 게 걸려 있다는 사실 자체를 모른다. 장애 분석 때 소켓 상태 덤프를 아무리 떠도 타임아웃 설정은 안 나온다 — 확인하려면 힙덤프를 뜨거나 애플리케이션 설정을 봐야 한다.
- **`Socket#getSoTimeout()` 이 "잘 걸렸다" 를 증명하지 못한다.** 방금 대입한 필드를 그대로 되읽는 것이라, 값이 나온다고 해서 그게 실제로 동작한다는 보장이 아니다.
- **write 에는 안 걸린다.** SO_TIMEOUT 은 `timedRead` 안에만 구현돼 있다. 커널 옵션이 아니니 send 경로에 자동으로 적용될 길이 없고, 자바에는 write 타임아웃이라는 개념 자체가 없다. 요청 바디가 큰데 상대가 수신 윈도를 안 열어 주면 `write` 에서 무한 대기한다.
- **소켓을 NIO 로 넘기면 사라진다.** 이 값은 `SocketImpl` 인스턴스에 붙은 필드라, `SocketChannel` 이나 `Selector` 기반 코드로 같은 연결을 다루면 아무 의미가 없다. 네티 같은 프레임워크가 SO_TIMEOUT 대신 자체 타임아웃 핸들러를 두는 이유다.
- **이미 대기 중인 read 는 못 바꾼다.** `implRead` 가 진입할 때 `int timeout = this.timeout;` 으로 **한 번 스냅샷**을 뜬다. 다른 스레드가 중간에 `setSoTimeout` 을 다시 걸어도 이미 `park` 에 들어간 read 에는 반영되지 않고, 다음 read 호출부터 적용된다.

다만 **커널이 실제로 바뀌는 부작용**이 하나 있다. SO_TIMEOUT 이 0 보다 크면 read 직전에 fd 를 논블로킹으로 전환한다 (3-2 에서 본 `fcntl(2)`).

```java
// sun.nio.ch.NioSocketImpl#implRead  :292
int timeout = this.timeout;
configureNonBlockingIfNeeded(fd, timeout > 0);   // :301  ← timeout>0 이면 fd 를 O_NONBLOCK 으로
if (timeout > 0) {
    n = timedRead(fd, b, off, len, MILLISECONDS.toNanos(timeout));   // :304
} else {
    n = tryRead(fd, b, off, len);                // 타임아웃 없으면 그냥 블로킹 read
    while (IOStatus.okayToRetry(n) && isOpen()) {
        park(fd, Net.POLLIN);
        n = tryRead(fd, b, off, len);
    }
}

// sun.nio.ch.NioSocketImpl#configureNonBlockingIfNeeded  :209
private void configureNonBlockingIfNeeded(FileDescriptor fd, boolean timed) throws IOException {
    if (!nonBlocking
        && (timed || Thread.currentThread().isVirtual())) {
        IOUtil.configureBlocking(fd, false);     // ← 여기는 진짜 fcntl(2) syscall
        nonBlocking = true;                      // ★ 한 번 켜지면 되돌리는 코드가 없다
    }
}
```

정리하면 **readTimeout 을 거는 순간 커널 상태가 바뀌긴 한다. 다만 바뀌는 건 "타임아웃" 이 아니라 "블로킹 여부" 다.** 그리고 `nonBlocking` 은 한 번 true 가 되면 다시 내려가지 않는다 — 한 번이라도 타임아웃 있는 read 를 한 소켓은 이후 계속 논블로킹 + `poll` 루프로 돈다.

> SocketImpl 계층 지도(`SocksSocketImpl` 래핑, `SocketChannel` 과의 관계 등) 와 `SO_RCVTIMEO` 비교는 분량상 `so-timeout-internals.md` 로 분리한다.

### 4-2. 시간이 소비되는 곳: `timedRead`

#### 소켓까지 내려가는 read 경로

시작은 `HttpURLConnection#getInputStream0` 이다. 응답이 필요해지는 순간 `HttpClient#parseHTTP` 를 부른다.

```java
// sun.net.www.http.HttpClient#parseHTTP  :742~
try {
    serverInput = serverSocket.getInputStream();        // :754  소켓의 InputStream
    if (capture != null) {
        serverInput = new HttpCaptureInputStream(serverInput, capture);
    }
    serverInput = new BufferedInputStream(serverInput); // :758
    return (parseHTTPHeader(responses, httpuc));        // :759
} catch (SocketTimeoutException stex) {
    // We don't want to retry the request when the app. sets a timeout
    if (ignoreContinue) {
        closeServer();
    }
    throw stex;                                         // ★ 타임아웃은 재시도 없이 그대로 올린다
} catch (IOException e) {
    closeServer();
    cachedHttpClient = false;
    if (!failedOnce && requests != null) {              // 그 외 IOException 은 한 번 재시도 대상
        ...
```

`SocketTimeoutException` 은 따로 잡아 **재시도 없이 그대로 던진다.** 다른 `IOException` 은 `failedOnce` 를 세워 한 번 더 시도하지만, 타임아웃은 앱이 명시적으로 건 상한이라 존중한다.

그 다음 `parseHTTPHeader` 가 첫 8바이트를 읽어 `HTTP/1.` 로 시작하는지 확인한다. **여기가 응답 첫 바이트를 기다리는 자리**다.

```java
// sun.net.www.http.HttpClient#parseHTTPHeader  :806~
byte[] b = new byte[8];
try {
    int nread = 0;
    serverInput.mark(10);
    while (nread < 8) {
        int r = serverInput.read(b, nread, 8 - nread);   // :827  ★ 4-3 스택트레이스에 찍히는 프레임
        if (r < 0) {
            break;
        }
        nread += r;
    }
    ...
    ret = b[0] == 'H' && b[1] == 'T'
            && b[2] == 'T' && b[3] == 'P' && b[4] == '/' &&
        b[5] == '1' && b[6] == '.';
    serverInput.reset();
```

`serverInput` 은 `BufferedInputStream` 이고 그 아래가 소켓이다. 한 겹씩 벗기면 이렇게 내려간다.

```java
// java.net.Socket$SocketInputStream#read  :1097
public int read(byte[] b, int off, int len) throws IOException {
    try {
        return in.read(b, off, len);                     // :1099  in = SocketImpl 이 준 InputStream
    } catch (SocketTimeoutException e) {
        throw e;                                         // 그대로 통과
    } catch (InterruptedIOException e) {
        ...
    }
}

// sun.nio.ch.NioSocketImpl#getInputStream  :791
protected InputStream getInputStream() {
    return new InputStream() {
        ...
        @Override
        public int read(byte[] b, int off, int len) throws IOException {
            return NioSocketImpl.this.read(b, off, len); // :796
        }
        ...
    };
}

// sun.nio.ch.NioSocketImpl#read  :334
private int read(byte[] b, int off, int len) throws IOException {
    Objects.checkFromIndexSize(off, len, b.length);
    if (len == 0) {
        return 0;
    } else {
        readLock.lock();                                 // ★ 같은 소켓에 동시 read 는 직렬화된다
        try {
            if (readEOF)
                return -1;
            int size = Math.min(len, MAX_BUFFER_SIZE);
            int n = implRead(b, off, size);              // :346  → 4-1 의 implRead → timedRead
            if (n == -1)
                readEOF = true;
            return n;
        } finally {
            readLock.unlock();
        }
    }
}
```

`implRead` 가 4-1 에서 본 그 메서드다 — `this.timeout` 을 스냅샷 뜨고, 0 보다 크면 fd 를 논블로킹으로 바꾼 뒤 `timedRead` 로 넘긴다. 전체 경로를 한 줄로 세우면 이렇다.

```text
HttpURLConnection#getInputStream0
  → HttpClient#parseHTTP :759            소켓 InputStream 을 BufferedInputStream 으로 감쌈
  → HttpClient#parseHTTPHeader :827      "HTTP/1." 8바이트 읽기          ← 응답 첫 바이트 대기
  → BufferedInputStream#fill
  → Socket$SocketInputStream#read :1099
  → NioSocketImpl$1#read :796
  → NioSocketImpl#read :346              readLock + implRead 호출
  → NioSocketImpl#implRead :301,304      timeout 스냅샷 + O_NONBLOCK 전환
  → NioSocketImpl#timedRead :270         ★ 여기서 기다린다
```

**바디 read 도 결국 같은 스택으로 내려간다.** 헤더를 다 읽은 뒤 `parseHTTPHeader` 끝에서 `serverInput` 을 한 겹 더 감싸는데, 감싸기만 할 뿐 밑바닥은 그대로다.

```java
// sun.net.www.http.HttpClient#parseHTTPHeader  :1062~1080
/* wrap a KeepAliveStream/MeteredStream around it if appropriate */
if (cl > 0) {
    boolean useKeepAliveStream = isKeepingAlive() || disableKeepAlive;
    if (useKeepAliveStream) {
        serverInput = new KeepAliveStream(serverInput, cl, this);   // :1075
        failedOnce = false;
    } else {
        serverInput = new MeteredStream(serverInput, cl);           // :1079
    }
}
```

그래서 바디를 읽다 터지면 스택 위쪽에 `KeepAliveStream` / `MeteredStream` 프레임이 대신 올라올 뿐, 그 아래 `Socket$SocketInputStream` → `timedRead` 구간은 완전히 동일하다. **한 응답을 받는 동안 이 경로를 여러 번 지나간다** — 이게 바로 아래에서 볼 "read 호출당 상한" 성질의 원인이다.

#### 실제로 기다리는 한 곳

4-1 에서 소켓에 적어 둔 그 값이, read 가 일어날 때마다 `poll(2)` 대기 상한으로 쓰인다.

```java
// sun.nio.ch.NioSocketImpl#timedRead  :270
private int timedRead(FileDescriptor fd, byte[] b, int off, int len, long nanos) throws IOException {
    long startNanos = System.nanoTime();        // ★ 호출될 때마다 새로 찍힘
    int n = tryRead(fd, b, off, len);
    while (n == IOStatus.UNAVAILABLE && isOpen()) {
        long remainingNanos = nanos - (System.nanoTime() - startNanos);
        if (remainingNanos <= 0) {
            throw new SocketTimeoutException("Read timed out");    // :278
        }
        park(fd, Net.POLLIN, remainingNanos);
        n = tryRead(fd, b, off, len);
    }
    return n;
}
```

`startNanos` 가 **호출마다** 새로 찍힌다. 이 한 줄이 "SO_TIMEOUT 은 read 호출당 상한" 이라는 성질의 근원이다.

#### 한 응답에 read 가 여러 번인 이유

`connect` 와 `read` 는 커널에 요청하는 내용이 다르다.

|  | connect | read |
|---|---|---|
| 요청하는 것 | "연결을 맺어라" | "**지금 도착해 있는** 바이트를 달라" |
| 완료 조건 | ESTABLISHED 되면 끝 | 도착한 만큼 채우고 즉시 리턴 |
| 횟수 | 연결당 1번 | 필요한 만큼 모을 때까지 반복 |

TCP 는 응답을 한 덩어리로 배달하지 않는다. 세그먼트로 쪼개져 도착하고 `read(2)` 는 커널 수신 버퍼에 들어와 있는 만큼만 돌려주므로, HTTP 응답 하나를 완성하려면 호출자가 반복해야 한다. 그 반복문이 헤더 쪽과 바디 쪽에 하나씩 있다.

**헤더** — 위에서 인용한 `parseHTTPHeader:825` 의 `while (nread < 8)` 이다. 8바이트조차 한 번에 안 올 수 있다는 전제로 짜여 있다.

**바디** — `RestTemplate` 이면 메시지 컨버터 안에 있다. `getForObject(url, Report.class)` 가 응답 바이트를 `Report` 로 바꾸려면 응답 `InputStream` 을 직접 읽어야 하고, 그 스트림이 바로 위에서 `KeepAliveStream` 으로 감싼 그것이다.

```text
restTemplate.getForObject(url, Report.class)
 └ HttpMessageConverterExtractor#extractData          :90    Content-Type 으로 컨버터 선택
     └ converter.read(type, response)                 :105
         └ StringHttpMessageConverter#readInternal    :98    getBody().readNBytes(length)
             └ InputStream#readNBytes                 :412   while ((n = read(buf, ...)) > 0)  ← 바디 루프
                 └ KeepAliveStream(MeteredStream)#read :125  루프 없음. 다 읽었으면 -1
                     └ BufferedInputStream#fill              버퍼가 비었을 때만 소켓까지 내려간다
                         └ … → NioSocketImpl#timedRead :270
```

Content-Type 에 따라 컨버터가 갈린다 — `text/plain` 은 `StringHttpMessageConverter`, `application/json` 은 `MappingJackson2HttpMessageConverter` 가 `objectMapper` 로 스트림을 청크 단위로 읽는다(`readJavaType:368`). 어느 쪽이든 밑바닥은 같은 소켓 read 다.

```java
// org.springframework.http.converter.StringHttpMessageConverter#readInternal  (6.2.5 :94~99)
protected String readInternal(Class<? extends String> clazz, HttpInputMessage inputMessage) throws IOException {
    Charset charset = getContentTypeCharset(inputMessage.getHeaders().getContentType());
    long length = inputMessage.getHeaders().getContentLength();
    byte[] bytes = (length >= 0 && length <= Integer.MAX_VALUE ?
            inputMessage.getBody().readNBytes((int) length) : inputMessage.getBody().readAllBytes());
    return new String(bytes, charset);
}
```

`Content-Length` 만큼 채우는 루프는 `readNBytes` 안에 있고, 스트림 자신은 반복하지 않는다. `MeteredStream` 은 한 번만 위임하고 읽은 바이트를 세다가 `Content-Length` 를 채우면 스스로 닫혀 `-1` 을 돌려주고, 그걸로 위쪽 `while` 이 끝난다.

```java
// sun.net.www.MeteredStream#read  :125
public int read(byte b[], int off, int len) throws java.io.IOException {
    if (closed) return -1;
    int n = in.read(b, off, len);   // 루프 없음. 한 번만 위임한다
    justRead(n);                    // :68 count += n → :84 count >= expected 면 close()
    return n;
}
```

컨버터는 Spring 어휘일 뿐이다. `HttpURLConnection` 을 직접 쓰면 그 자리에 직접 짠 `while ((n = in.read(buf)) != -1)` 이 들어가고, 소켓 입장에서는 누가 반복하든 같다.

#### 루프가 두 층인데 성격이 반대다

```text
readNBytes:412 / parseHTTPHeader:825
  while (…)                                        ① 새 read 를 다시 호출
   └ … → NioSocketImpl#timedRead :270
            long startNanos = System.nanoTime();   ★ 여기서 시계가 0 으로
            while (n == UNAVAILABLE && isOpen())   ② 같은 read 안에서 재대기
             └ park(fd, POLLIN, remainingNanos)
```

|  | 반복하는 것 | 반복할 때 `startNanos` |
|---|---|---|
| ① 호출자 쪽 루프 | read 호출 자체 | **새로 찍힌다 → 예산 부활** |
| ② `timedRead` 내부 루프 | `poll` 재대기 | 그대로 → `remainingNanos` 감소 |

같은 `while` 인데 하나는 시계를 되감고 하나는 안 되감는다. readTimeout 이 "응답 전체 상한" 이 아니라 "한 번의 read 가 다음 바이트를 받기까지의 상한" 인 이유가 이것이다.

#### 실측 — slow-drip 은 안 끊긴다

서버가 바디를 **400ms 간격으로 1바이트씩** 흘리게 하고 readTimeout 만 바꿔 돌렸다.

```text
### readTimeout=500ms, 서버는 400ms 간격으로 1바이트씩 총 10바이트
  read#1  -> 1바이트 (누적 424ms)
  read#2  -> 1바이트 (누적 827ms)
  …
  read#10 -> 1바이트 (누적 4043ms)
완료: read 호출 10회, 10바이트, 총 4044ms

### readTimeout=300ms, 조건 동일
  SocketTimeoutException: Read timed out (321ms)
```

readTimeout 이 500ms 인데 **총 4초를 기다리고 정상 수신**했다. 매 read 가 400ms 만에 1바이트를 받아 500ms 예산 안에 들어왔기 때문이다. 300ms 쪽은 첫 400ms 공백에서 바로 터졌다.

> `readTimeout=300ms` 를 걸어도 상대가 299ms 마다 1바이트씩 보내면 응답은 끝나지 않는다. 총 응답 시간 상한은 이 축으로 못 걸고 별도 레이어가 필요하다 (8장).

<details markdown="1">
<summary>검증 코드 (Temurin 21.0.7, 단일 파일 실행)</summary>

```java
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;

public class DripTest {
    static final int GAP_MS = 400, BYTES = 10;

    public static void main(String[] args) throws Exception {
        int readTimeout = Integer.parseInt(args[0]);
        ServerSocket ss = new ServerSocket(0, 1, InetAddress.getByName("127.0.0.1"));
        Thread t = new Thread(() -> {
            try (Socket s = ss.accept()) {
                BufferedReader in = new BufferedReader(
                        new InputStreamReader(s.getInputStream(), StandardCharsets.ISO_8859_1));
                in.readLine();
                while (true) { String h = in.readLine(); if (h == null || h.isEmpty()) break; }
                OutputStream out = s.getOutputStream();
                out.write(("HTTP/1.1 200 OK\r\nContent-Length: " + BYTES + "\r\n\r\n")
                        .getBytes(StandardCharsets.ISO_8859_1));
                out.flush();
                for (int i = 0; i < BYTES; i++) {       // 바디를 400ms 간격으로 1바이트씩
                    Thread.sleep(GAP_MS);
                    out.write('x');
                    out.flush();
                }
            } catch (Exception e) { System.out.println("[server] " + e); }
        });
        t.setDaemon(true);
        t.start();

        HttpURLConnection c = (HttpURLConnection)
                URI.create("http://127.0.0.1:" + ss.getLocalPort() + "/drip").toURL().openConnection();
        c.setReadTimeout(readTimeout);
        long t0 = System.nanoTime();
        try (InputStream in = c.getInputStream()) {
            byte[] buf = new byte[64];
            int n, calls = 0, total = 0;
            while ((n = in.read(buf)) != -1) {          // ★ 이 read 하나하나가 SO_TIMEOUT 의 단위
                calls++;
                total += n;
                System.out.printf("  read#%d -> %d바이트 (누적 %dms)%n",
                        calls, n, (System.nanoTime() - t0) / 1_000_000);
            }
            System.out.printf("완료: read 호출 %d회, %d바이트, 총 %dms%n",
                    calls, total, (System.nanoTime() - t0) / 1_000_000);
        } catch (SocketTimeoutException e) {
            System.out.printf("  %s: %s (%dms)%n", e.getClass().getSimpleName(), e.getMessage(),
                    (System.nanoTime() - t0) / 1_000_000);
        }
    }
}
```

</details>

### 4-3. 실제 발동 — 스택트레이스로 확인

accept 만 하고 응답을 안 주는 로컬 서버에 `readTimeout=1000` 으로 호출한 결과다. 응답 첫 줄을 기다리는 read 에서 터진 것이 `parseHTTPHeader` 프레임으로 보인다.

```text
=== readTimeout ===
elapsed: 1007ms
root cause: java.net.SocketTimeoutException: Read timed out
  at java.base/sun.nio.ch.NioSocketImpl.timedRead(NioSocketImpl.java:278)           ← 소비
  at java.base/sun.nio.ch.NioSocketImpl.implRead(NioSocketImpl.java:304)
  at java.base/sun.nio.ch.NioSocketImpl.read(NioSocketImpl.java:346)
  at java.base/sun.nio.ch.NioSocketImpl$1.read(NioSocketImpl.java:796)
  at java.base/java.net.Socket$SocketInputStream.read(Socket.java:1099)
  at java.base/java.io.BufferedInputStream.fill(BufferedInputStream.java:291)
  ...
  at java.base/sun.net.www.http.HttpClient.parseHTTPHeader(HttpClient.java:827)     ← 응답 첫 줄 대기
  at java.base/sun.net.www.http.HttpClient.parseHTTP(HttpClient.java:759)
  at java.base/sun.net.www.protocol.http.HttpURLConnection.getInputStream0(HttpURLConnection.java:1720)
```

바디를 읽다 터지면 같은 `timedRead` 위에 `KeepAliveStream` / `MeteredStream` 프레임이 대신 올라온다.

## 5. 시점별 정리

---

| 시점 | 코드 | 타임아웃 관점에서 일어나는 일 |
|---|---|---|
| 앱 시작 | `factory.setReadTimeout(5000)` | 팩토리 int 필드 대입 |
| 요청 준비 | `prepareConnection` | `URLConnection` int 필드로 복사. **소켓 없음** |
| `connect()` | `HttpClient.New` → `kac.get` | keep-alive 캐시 HIT 면 재사용 — **connectTimeout 미사용** |
| └ 캐시 MISS | `new InetSocketAddress(...)` | **DNS 조회 — 어떤 타임아웃도 안 걸림** |
| └ | `s.connect(addr, connectTimeout)` | ✅ **connectTimeout 발동 지점** (SYN → SYN_SENT 대기) |
| └ | `s.setSoTimeout(readTimeout)` | 이 경로에선 `-1` 이라 시스템 프로퍼티만 반영 (4-1) |
| `plainConnect0` | `http.setReadTimeout(readTimeout)` | ✅ **이번 요청 readTimeout 이 SO_TIMEOUT 에 기록되는 곳** (캐시 HIT 여부와 무관) |
| `connect()` 리턴 | — | TCP ESTABLISHED, **HTTP 바이트는 아직 0** |
| 요청 송신 | `writeRequests()` | write 는 보통 논블로킹 (send buffer 가 차면 블로킹) |
| 응답 첫 줄 read | `parseHTTP` → `timedRead` | ✅ **readTimeout 첫 소비** |
| 바디 read | 컨버터 → `timedRead` | ✅ read **호출마다 새로 카운트** |
| `close()` | `KeepAliveCache#put` | ESTABLISHED 유지한 채 반납 (타임아웃 났던 소켓은 반납 안 함) |

## 6. 커넥션 풀 클라이언트(HttpClient5)는 어디가 다른가

---

실무에서는 `HttpURLConnection` 대신 보통 Apache HttpClient5 + `PoolingHttpClientConnectionManager` 를 쓴다. 흔한 세팅 형태부터.

```java
PoolingHttpClientConnectionManager cm = PoolingHttpClientConnectionManagerBuilder.create()
        .setDefaultConnectionConfig(ConnectionConfig.custom()
                .setConnectTimeout(Timeout.ofMilliseconds(1_000))   // 커넥션 수립 단계
                .setSocketTimeout(Timeout.ofMilliseconds(1_000))    // SO_TIMEOUT 초기값
                .build())
        .setMaxConnTotal(50)
        .setMaxConnPerRoute(20)
        .build();

RequestConfig requestConfig = RequestConfig.custom()
        .setConnectionRequestTimeout(Timeout.ofMilliseconds(500))   // 풀에서 커넥션 빌리는 대기
        .setResponseTimeout(Timeout.ofMilliseconds(1_000))          // 응답 대기
        .build();

CloseableHttpClient client = HttpClients.custom()
        .setConnectionManager(cm)
        .setDefaultRequestConfig(requestConfig)
        .build();

RestTemplate restTemplate = new RestTemplate(new HttpComponentsClientHttpRequestFactory(client));
```

결론부터: **최종 적용 지점은 3·4장과 완전히 동일하다.** connect 는 같은 `NioSocketImpl#timedFinishConnect`, read 는 같은 `NioSocketImpl#timedRead` 에서 터진다. 달라지는 건 (1) 세팅이 `ConnectionConfig` / `RequestConfig` 두 군데로 갈라지고, (2) **"풀에서 커넥션 빌리는 대기"라는 축이 하나 추가**된다는 것이다.

```text
[세팅 — 역시 전부 필드 대입]

  ConnectionConfig.connectTimeout / socketTimeout            (풀 매니저에 등록 — 커넥션 만들 때의 조건)
  RequestConfig.connectionRequestTimeout / responseTimeout   (클라이언트 기본값 or 요청 단위)
    ↑ Spring factory.setConnectTimeout           → RequestConfig.connectTimeout
      Spring factory.setReadTimeout              → RequestConfig.responseTimeout   ← 이름 주의
      Spring factory.setConnectionRequestTimeout → RequestConfig.connectionRequestTimeout

[적용 — 시간이 실제로 소비되는 곳]

  connectionRequestTimeout → 풀 lease 대기                     InternalExecRuntime#acquireEndpoint  ★ 새 축
  connectTimeout           → socket.connect(addr, timeout)    → 같은 timedFinishConnect
  socketTimeout            → SO_TIMEOUT 에 기록
  responseTimeout          → 요청 직전 SO_TIMEOUT 덮어쓰기      → 같은 timedRead
```

### 6-1. 세팅 지점이 두 군데로 갈라진다

**`ConnectionConfig`** 는 풀 매니저에 등록해 두는 "커넥션을 새로 만들 때의 조건"이고, **`RequestConfig`** 는 클라이언트 기본값 또는 요청 단위(`HttpClientContext`)로 실어 보내는 값이다. 여기까지는 역시 빌더가 불변 객체에 값을 담아 둘 뿐 아무 I/O 도 없다.

Spring 의 `HttpComponentsClientHttpRequestFactory` 에 setter 로 걸면 요청마다 `RequestConfig` 로 병합된다. **`setReadTimeout` 이 HC5 의 `responseTimeout` 으로 매핑**되는 게 포인트.

```java
// org.springframework.http.client.HttpComponentsClientHttpRequestFactory#mergeRequestConfig
RequestConfig.Builder builder = RequestConfig.copy(clientConfig);
if (this.connectTimeout >= 0) {
    builder.setConnectTimeout(this.connectTimeout, TimeUnit.MILLISECONDS);
}
if (this.connectionRequestTimeout >= 0) {
    builder.setConnectionRequestTimeout(this.connectionRequestTimeout, TimeUnit.MILLISECONDS);
}
if (this.readTimeout >= 0) {
    builder.setResponseTimeout(this.readTimeout, TimeUnit.MILLISECONDS);   // ★ readTimeout → responseTimeout
}
```

connectTimeout 은 두 곳(`RequestConfig` — deprecated 지만 동작, `ConnectionConfig`)에 다 있는데 우선순위는 **RequestConfig 가 먼저**다. 커넥션을 만들기 직전에 이렇게 고른다.

```java
// org.apache.hc.client5.http.impl.classic.InternalExecRuntime#connectEndpoint  (5.4.2 :160)
final Timeout connectTimeout = requestConfig.getConnectTimeout();
manager.connect(endpoint, connectTimeout, context);                     // :164

// org.apache.hc.client5.http.impl.io.PoolingHttpClientConnectionManager#connect  :485
final Timeout connectTimeout = timeout != null
        ? Timeout.of(timeout.getDuration(), timeout.getTimeUnit())
        : connectionConfig.getConnectTimeout();                         // RequestConfig 에 없을 때만 ConnectionConfig
```

기본값도 `HttpURLConnection`(전부 무한)과 다르다. `httpclient5 5.4.2` 소스 기준:

| 값 | 기본값 |
|---|---|
| `ConnectionConfig.connectTimeout` | **3분** (`DEFAULT_CONNECT_TIMEOUT = Timeout.ofMinutes(3)`) |
| `RequestConfig.connectionRequestTimeout` | **3분** |
| `ConnectionConfig.socketTimeout` | null = **무한** |
| `RequestConfig.responseTimeout` | null = **무한** |

즉 아무것도 안 걸어도 connect 와 풀 대기는 3분 상한이 있지만, **응답 대기는 기본 무한**이다.

### 6-2. 새 축: connectionRequestTimeout — 풀 lease 대기

소켓 이전 단계다. 풀의 커넥션이 전부 사용 중이면 요청은 소켓 근처에도 못 가고 lease 대기에서 죽는다.

```java
// org.apache.hc.client5.http.impl.classic.InternalExecRuntime#acquireEndpoint  (5.4.2 :105)
final LeaseRequest connRequest = manager.lease(id, route, connectionRequestTimeout, object);
try {
    final ConnectionEndpoint connectionEndpoint = connRequest.get(connectionRequestTimeout);  // :111 ★ 대기 지점
    ...
} catch (final TimeoutException ex) {
    connRequest.cancel();
    throw new ConnectionRequestTimeoutException(ex.getMessage());                             // :122
}
```

풀 크기 1 로 만들고 첫 요청이 커넥션을 물고 있는 동안 두 번째 요청을 보낸 실제 결과 (`connectionRequestTimeout=500ms`):

```text
=== HC5 connectionRequestTimeout ===
elapsed: 504ms
cause: org.springframework.web.client.ResourceAccessException: I/O error on GET request for
       "http://127.0.0.1:64328/": Timeout deadline: 500 MILLISECONDS, actual: 500 MILLISECONDS
cause: org.apache.hc.core5.http.ConnectionRequestTimeoutException: Timeout deadline: 500 MILLISECONDS, ...
  at o.a.hc.client5.http.impl.classic.InternalExecRuntime.acquireEndpoint(InternalExecRuntime.java:122)  ← 발동
  at o.a.hc.client5.http.impl.classic.ConnectExec.execute(ConnectExec.java:127)
  ...
```

**스택에 소켓 프레임이 하나도 없다** — I/O 문제가 아니라 우리 쪽 자원(풀) 고갈이라는 뜻이다. `SocketTimeoutException` 과 이 예외를 구분해서 봐야 원인 지목이 안 틀린다.

### 6-3. connectTimeout — 운반 경로만 다르고 도착지는 같다

풀에 재사용할 커넥션이 없어 새로 만들 때만 이 경로를 탄다 (keep-alive 재사용이면 스킵 — 3장과 같은 성질).

```java
// org.apache.hc.client5.http.impl.io.DefaultHttpClientConnectionOperator#connect  (5.4.2)
for (int i = 0; i < remoteAddresses.length; i++) {                        // ★ DNS 가 준 주소마다 반복
    final InetSocketAddress remoteAddress = new InetSocketAddress(address, port);
    final Socket socket = detachedSocketFactory.create(socksProxy);       // new Socket()
    try {
        if (soTimeout != null) {
            socket.setSoTimeout(soTimeout.toMillisecondsIntBound());      // :196  SocketConfig.soTimeout 기록
        }
        ...
        socket.connect(remoteAddress,
                TimeValue.isPositive(connectTimeout) ? connectTimeout.toMillisecondsIntBound() : 0);  // :216 ★ 적용
        ...
```

DNS 가 IP 를 N 개 주면 **주소마다 connectTimeout 을 full 로 다시 쓴다** (최악 `N × connectTimeout`, 함정 6 — 아래에서 자세히). blackhole 주소로 실제 발동시킨 결과:

```text
=== HC5 connectTimeout ===
elapsed: 1031ms
cause: org.apache.hc.client5.http.ConnectTimeoutException: Connect to http://10.255.255.1:80 failed: Connect timed out
  at java.base/sun.nio.ch.NioSocketImpl.timedFinishConnect(NioSocketImpl.java:546)   ← 3장과 동일한 소비 지점
  at java.base/sun.nio.ch.NioSocketImpl.connect(NioSocketImpl.java:592)
  at java.base/java.net.SocksSocketImpl.connect(SocksSocketImpl.java:327)
  at java.base/java.net.Socket.connect(Socket.java:751)
  at o.a.hc.client5.http.impl.io.DefaultHttpClientConnectionOperator.connect(...:216)  ← 적용 한 줄
  at o.a.hc.client5.http.impl.io.PoolingHttpClientConnectionManager.connect(...:490)
  at o.a.hc.client5.http.impl.classic.InternalExecRuntime.connectEndpoint(...:164)
  ...
```

맨 아래 소비 지점은 `HttpURLConnection` 때와 같은 `timedFinishConnect:546` 이다. 차이는 HC5 가 `new Socket()` 으로 만들기 때문에 `SocksSocketImpl` 래퍼가 한 겹 끼어 있다는 것 정도 (→ `so-timeout-internals.md` 2장). 예외 타입은 `SocketTimeoutException` 을 HC5 가 `ConnectTimeoutException` 으로 감싸서 올린다.

#### 주소가 여러 개인 이유 — `getAllByName` vs `getByName`

"DNS 가 준 주소" 라는 게 특수한 상황이 아니다. 로드밸런싱·멀티 리전 때문에 A 레코드를 여러 개 주는 게 오히려 일반적이고, IPv6 까지 켜져 있으면 AAAA 가 더해진다. 실제 조회 결과다.

```text
google.com          1  [142.250.199.238]
www.google.com      8  [142.251.150.119, 142.251.151.119, 142.251.152.119, ...]
naver.com           4  [223.130.192.247, 223.130.192.248, 223.130.200.219, 223.130.200.236]
amazon.com          3  [98.82.161.185, 98.87.170.71, 98.87.170.74]
s3.amazonaws.com    8  [16.15.199.196, 16.15.213.184, 16.182.72.56, ...]
```

HC5 는 이걸 전부 받아 온다. 기본 리졸버 `SystemDefaultDnsResolver` 의 알맹이가 `InetAddress.getAllByName` 이다.

```java
// DefaultHttpClientConnectionOperator#connect  (5.4.2 :161~177)
final InetAddress[] remoteAddresses;
if (endpointHost.getAddress() != null) {
    remoteAddresses = new InetAddress[] { endpointHost.getAddress() };   // IP 를 직접 준 경우만 1개
} else {
    remoteAddresses = this.dnsResolver.resolve(endpointHost.getHostName());   // → InetAddress.getAllByName(host)
    if (remoteAddresses == null || remoteAddresses.length == 0) {
        throw new UnknownHostException(endpointHost.getHostName());
    }
}
```

그리고 실패하면 다음 주소로 넘어간다. **`SocketTimeoutException` 이 `IOException` 하위라서 타임아웃도 이 catch 에 걸린다.**

```java
// :239~253
} catch (final IOException ex) {
    Closer.closeQuietly(socket);
    if (last) {
        throw ConnectExceptionSupport.enhance(ex, endpointHost, remoteAddresses);
    }
    // "retrying connection to the next address"  ← 남은 시간을 깎는 게 아니라 다음 주소에 full connectTimeout 을 새로 쓴다
}
```

그래서 `connectTimeout = 1000ms` 로 걸어 놨어도 `www.google.com` 처럼 주소가 8개 나오고 전부 응답이 없으면 **최대 8초**를 기다린다.

반면 `HttpURLConnection` 은 3-1 에서 본 그 한 줄이 전부다.

```java
// sun.net.NetworkClient#doConnect  :177~179
if (connectTimeout >= 0) {
    s.connect(new InetSocketAddress(server, port), connectTimeout);   // getByName — 첫 주소 하나
}
```

`new InetSocketAddress(String, int)` 는 내부적으로 `InetAddress.getByName` 이라 **첫 주소 하나만** 고르고, 루프도 없다. 트레이드오프가 정확히 반대 방향이다.

| | `HttpURLConnection` | HC5 |
|---|---|---|
| 시도하는 주소 | 첫 1개 | DNS 가 준 전부 |
| 최악 대기 | `connectTimeout` | `N × connectTimeout` |
| 일부 IP 만 장애 | 나머지를 시도조차 안 하고 **실패** | 다음 주소로 넘어가 **성공** |

가용성 면에선 HC5 쪽이 맞는 설계다. 다만 이걸 모르고 타임아웃을 잡으면 "1초로 걸었는데 왜 8초씩 걸리지" 가 된다. 목표 시간이 정해져 있으면 대상 호스트의 A/AAAA 개수를 확인해 `connectTimeout` 을 나눠 잡거나, 애초에 총 상한은 위 레이어(8장)에서 걸어야 한다.

### 6-4. responseTimeout / socketTimeout — 결국 둘 다 SO_TIMEOUT 이다

SO_TIMEOUT 쓰기가 세 번 일어난다. 전부 같은 자바 필드를 덮어쓰는 것뿐이다.

1. 소켓 생성 직후 — `SocketConfig.soTimeout` (`DefaultHttpClientConnectionOperator:196`)
2. 커넥션 수립 완료 후 — `ConnectionConfig.socketTimeout` (`PoolingHttpClientConnectionManager:504`)
3. **요청 직전 — `RequestConfig.responseTimeout` 으로 덮어쓰기:**

   ```java
   // org.apache.hc.client5.http.impl.classic.InternalExecRuntime#execute  (5.4.2 :226~)
   final Timeout responseTimeout = requestConfig.getResponseTimeout();
   if (responseTimeout != null) {
       endpoint.setSocketTimeout(responseTimeout);   // ★ SO_TIMEOUT 를 responseTimeout 값으로 교체
   }
   return endpoint.execute(...);
   ```

즉 **responseTimeout 은 별도 타이머가 아니라 요청 실행 동안 SO_TIMEOUT 을 갈아끼우는 것**이다. 따라서 성질도 SO_TIMEOUT 그대로다 — read 호출당 상한이고, 요청이 끝날 때까지 되돌리는 코드가 없어서 응답 헤더 이후 바디 read 에도 이 값이 유지된다. **총 응답 시간 상한이 아니다** (slow-drip 이면 역시 안 끊긴다). 게다가 이 덮어쓰기는 요청이 끝난 뒤에도 커넥션에 남는데, 그 이야기는 6-5 에서 한다. 무응답 서버로 발동시킨 결과:

```text
=== HC5 responseTimeout ===
elapsed: 1005ms
cause: java.net.SocketTimeoutException: Read timed out
  at java.base/sun.nio.ch.NioSocketImpl.timedRead(NioSocketImpl.java:278)             ← 4장과 동일한 소비 지점
  ...
  at o.a.hc.core5.http.impl.io.SessionInputBufferImpl.fillBuffer(SessionInputBufferImpl.java:149)
  at o.a.hc.core5.http.impl.io.SessionInputBufferImpl.readLine(...)
  at o.a.hc.core5.http.impl.io.DefaultBHttpClientConnection.receiveResponseHeader(...:331)  ← 응답 첫 줄 대기
  at o.a.hc.core5.http.impl.io.HttpRequestExecutor.execute(...:196)
  ...
```

### 6-5. 요청별로 타임아웃 다르게 주기

`socketTimeout` 과 `responseTimeout` 은 6-4 에서 봤듯 결국 같은 SO_TIMEOUT 필드를 건드린다. 그런데 설정은 두 개다.

#### 왜 둘로 나뉘어 있나 — 소유자와 적용 범위가 다르다

| | `socketTimeout` | `responseTimeout` |
|---|---|---|
| 담긴 곳 | `ConnectionConfig` | `RequestConfig` |
| 소유자 | 커넥션 매니저 (라우트별) | `HttpClientContext` (요청별) |
| 걸리는 시점 | 물리 커넥션 수립 직후 **1회** | **매 요청** 실행 직전 |
| 재사용 커넥션 | `connect()` 가 `isConnected()` 면 즉시 return → **다시 안 걸림** | 풀에서 꺼낸 커넥션에도 매번 |

**첫째, 커넥션은 공유되고 요청은 제각각이다.** 풀의 커넥션 하나를 여러 API 호출이 돌아가며 쓰는데, 잔액 조회는 300ms 안에 포기해야 하고 정산 리포트는 10초가 정상일 수 있다. 타임아웃이 커넥션에만 붙어 있으면 요청별로 다르게 줄 방법이 없다. 그래서 값이 `HttpClientContext` 에서 나온다.

```java
// InternalExecRuntime#execute  (5.4.2 :215~228)
final RequestConfig requestConfig = context.getRequestConfigOrDefault();   // ← 요청별 컨텍스트
final Timeout responseTimeout = requestConfig.getResponseTimeout();
if (responseTimeout != null) {
    endpoint.setSocketTimeout(responseTimeout);
}
```

**둘째, 커넥션을 여는 구간은 요청 실행 코드가 돌기 전이다.** 위 `InternalExecRuntime#execute` 는 exec 체인 맨 아래에서 도는데, 거기 닿기 전에 이미 소켓 read 가 일어난다. 호출 순서를 펼치면 이렇다.

```text
CloseableHttpClient#execute
 └ (exec 체인) … → ConnectExec#execute
     │
     ├ execRuntime.acquireEndpoint(...)                    :127   풀에서 커넥션 빌리기
     ├ execRuntime.connectEndpoint(context)                :144   ★ 여기서 소켓을 연다
     │   └ PoolingHttpClientConnectionManager#connect
     │       ├ DefaultHttpClientConnectionOperator#connect
     │       │    ├ socket.setSoTimeout(SocketConfig.soTimeout)    :196
     │       │    ├ socket.connect(remoteAddress, connectTimeout)  :216   ← connectTimeout 소비
     │       │    └ tlsSocketStrategy.upgrade(socket, ...)         :231   ← TLS handshake, read 발생
     │       └ conn.setSocketTimeout(ConnectionConfig.socketTimeout)      :504
     │
     └ chain.proceed(request, scope)                       :198   ← 여기부터가 "요청 실행"
         └ MainClientExec#execute
             └ InternalExecRuntime#execute                 :218
                 ├ endpoint.setSocketTimeout(responseTimeout)      :228   ★ responseTimeout 은 여기서 처음 걸린다
                 └ endpoint.execute(...)                           :233   요청 write + 응답 read
```

`ConnectExec` 은 커넥션을 다 세운 뒤에야 `chain.proceed` 로 내려간다.

```java
// org.apache.hc.client5.http.impl.classic.ConnectExec#execute  (5.4.2 :130~198)
if (!execRuntime.isEndpointConnected()) {
    ...
    case HttpRouteDirector.CONNECT_TARGET:
        execRuntime.connectEndpoint(context);   // :144  TCP connect + TLS handshake 가 전부 이 안
        ...
}
return chain.proceed(request, scope);           // :198  ← 이제야 요청 실행 단계로
```

TLS handshake 가 서버의 `ServerHello`·인증서를 기다리는 시점은 `:144` 안이다. `responseTimeout` 을 SO_TIMEOUT 에 쓰는 `:228` 은 `:198` 아래에 있으니, 그 시점엔 아직 어디에도 안 걸려 있다. 이게 "요청 실행 바깥의 read" 다.

이 구간을 지키는 건 `connect` 전에 깔아 둔 `SocketConfig.soTimeout` 이다.

```java
// DefaultHttpClientConnectionOperator#connect  (5.4.2 :180~231)
final Timeout soTimeout = socketConfig.getSoTimeout();      // :180  ConnectionConfig 아님, SocketConfig
...
if (soTimeout != null) {
    socket.setSoTimeout(soTimeout.toMillisecondsIntBound());               // :196  raw 소켓에 기록
}
...
socket.connect(remoteAddress, connectTimeout.toMillisecondsIntBound());    // :216
conn.setSocketTimeout(soTimeout);                                          // :223
final SSLSocket sslSocket = tlsSocketStrategy.upgrade(socket, ...);        // :231  ★ 이 read 를 :196 값이 지킨다
```

```java
// org.apache.hc.core5.http.io.SocketConfig  (5.3.3 :48)
private static final Timeout DEFAULT_SOCKET_TIMEOUT = Timeout.ofMinutes(3);
```

아무것도 설정 안 하면 handshake 가 멈췄을 때 **3분**을 기다린다. 무한은 아니지만, 응답을 300ms 안에 받겠다고 잡은 쪽에서는 사실상 무한이다.

정리하면 read 가 일어나는 지점마다 그 순간의 SO_TIMEOUT 주인이 다르다.

| read 지점 | 그 순간 SO_TIMEOUT | 비고 |
|---|---|---|
| TLS handshake (`upgrade` :231) | `SocketConfig.soTimeout` | 기본 3분. `responseTimeout` 미적용 |
| 풀에서 꺼낼 때 stale 체크 (`isStale`) | **1ms** 고정 | `BHttpConnectionBase:70`, 검사 후 원래 값으로 원복 |
| 프록시 `CONNECT` 응답 | `responseTimeout` | `createTunnelToTarget` 도 `execRuntime.execute` 를 거친다 (`ConnectExec:243`) |
| 응답 헤더·바디 | `responseTimeout`, 없으면 `ConnectionConfig.socketTimeout` | `:228` 이 null 이면 안 덮어쓴다 |

즉 둘은 "중복" 이 아니라 **적용 구간이 다르다.** `SocketConfig.soTimeout` / `ConnectionConfig.socketTimeout` 은 커넥션이 살아 있는 내내 깔려 있는 바닥값이고, `responseTimeout` 은 요청 실행 동안 그 위에 덮어쓰는 값이다.

#### 요청별로 주는 세 가지 방법

**(A) 요청 객체에 직접 `setConfig`** — `HttpGet` 같은 `HttpUriRequestBase` 가 `Configurable` 을 구현한다.

```java
RequestConfig base = RequestConfig.custom()
        .setConnectionRequestTimeout(Timeout.ofMilliseconds(200))   // 풀 lease 대기
        .setResponseTimeout(Timeout.ofSeconds(3))                   // 기본 응답
        .build();

CloseableHttpClient client = HttpClients.custom()
        .setConnectionManager(cm)
        .setDefaultRequestConfig(base)
        .build();

// 잔액 조회 — 빨리 포기해야 한다
HttpGet balance = new HttpGet("https://api.example.com/balance");
balance.setConfig(RequestConfig.copy(base)
        .setResponseTimeout(Timeout.ofMilliseconds(300))
        .build());

// 정산 리포트 — 오래 걸리는 게 정상이다
HttpGet report = new HttpGet("https://api.example.com/settlement/report");
report.setConfig(RequestConfig.copy(base)
        .setResponseTimeout(Timeout.ofSeconds(10))
        .build());
```

`RequestConfig.copy(base)` 로 시작한 게 핵심이다. 요청에 붙은 config 는 기본값과 **병합되지 않고 통째로 교체**된다.

```java
// InternalHttpClient#doExecute  (5.4.2 :153~160)
RequestConfig config = null;
if (request instanceof Configurable) {
    config = ((Configurable) request).getConfig();
}
if (config != null) {
    localcontext.setRequestConfig(config);   // ★ 교체. defaultConfig 와 merge 하지 않는다
}
setupContext(localcontext);                  // getRequestConfig() == null 일 때만 defaultConfig 를 넣는다
```

`RequestConfig.custom()` 으로 새로 만들면 `connectionRequestTimeout` 을 비롯한 나머지 설정이 전부 라이브러리 기본값으로 되돌아간다.

**(B) 컨텍스트로 넘기기** — 요청 객체를 재사용하거나, 호출 지점이 아닌 곳에서 타임아웃을 결정할 때.

```java
// 잔액 조회 — 빨리 포기해야 한다
HttpClientContext balanceCtx = HttpClientContext.create();
balanceCtx.setRequestConfig(RequestConfig.copy(base)
        .setResponseTimeout(Timeout.ofMilliseconds(300))
        .build());

String balance = client.execute(
        new HttpGet("https://api.example.com/balance"), balanceCtx,
        response -> EntityUtils.toString(response.getEntity()));

// 정산 리포트 — 오래 걸리는 게 정상이다
HttpClientContext reportCtx = HttpClientContext.create();
reportCtx.setRequestConfig(RequestConfig.copy(base)
        .setResponseTimeout(Timeout.ofSeconds(10))
        .build());

String report = client.execute(
        new HttpGet("https://api.example.com/settlement/report"), reportCtx,
        response -> EntityUtils.toString(response.getEntity()));
```

**(C) Spring 에서는 `setHttpContextFactory`** — Spring 은 `factory.setReadTimeout()` 을 **`responseTimeout` 으로 매핑**한다. 3장까지 본 그 readTimeout 이 HC5 로 오면 요청 단위 값이 되는 것이다.

```java
// HttpComponentsClientHttpRequestFactory#mergeRequestConfig
RequestConfig.Builder builder = RequestConfig.copy(clientConfig);
...
if (this.readTimeout >= 0) {
    builder.setResponseTimeout(this.readTimeout, TimeUnit.MILLISECONDS);   // ← readTimeout → responseTimeout
}
```

다만 이건 팩토리에 박히는 전역값이다. 요청별로 바꾸려면 Spring 이 뚫어 둔 훅을 쓴다. 이 글에서 본 설정을 전부 모으면 이렇게 된다.

```java
@Configuration
public class SettlementHttpClientConfig {

    // 요청별로 갈아끼울 때의 기준값. 요청 config 는 병합이 아니라 교체라 (A) 여기서 copy 해서 쓴다
    private static final RequestConfig BASE_REQUEST_CONFIG = RequestConfig.custom()
            .setConnectionRequestTimeout(Timeout.ofMilliseconds(200))    // 풀 lease 대기 (5장)
            .setResponseTimeout(Timeout.ofSeconds(5))                    // 기본 응답 상한
            .build();

    @Bean
    public PoolingHttpClientConnectionManager connectionManager() {
        return PoolingHttpClientConnectionManagerBuilder.create()
                .setMaxConnTotal(200)
                .setMaxConnPerRoute(50)
                // 소켓 생성 직후 깔리는 바닥값 — TLS handshake 를 지킨다 (안 잡으면 3분)
                .setDefaultSocketConfig(SocketConfig.custom()
                        .setSoTimeout(Timeout.ofSeconds(2))
                        .setTcpNoDelay(true)
                        .build())
                // 커넥션 수립 직후 1회 적용 — responseTimeout 이 없는 요청의 read 상한
                .setDefaultConnectionConfig(ConnectionConfig.custom()
                        .setConnectTimeout(Timeout.ofMilliseconds(1000))  // 주소마다 full (6-3)
                        .setSocketTimeout(Timeout.ofSeconds(3))
                        .setTimeToLive(TimeValue.ofMinutes(5))
                        .setValidateAfterInactivity(TimeValue.ofSeconds(2))
                        .build())
                .build();
    }

    @Bean
    public CloseableHttpClient httpClient(PoolingHttpClientConnectionManager cm) {
        return HttpClients.custom()
                .setConnectionManager(cm)
                .setDefaultRequestConfig(BASE_REQUEST_CONFIG)
                .evictIdleConnections(TimeValue.ofSeconds(30))
                .build();
    }

    // 경로별 응답 상한. 여기 없는 요청은 BASE_REQUEST_CONFIG 의 5s 를 그대로 쓴다
    private static final Map<String, Timeout> RESPONSE_TIMEOUTS = Map.of(
            "/balance",           Timeout.ofMilliseconds(300),   // 잔액 조회 — 빨리 포기해야 한다
            "/settlement/report", Timeout.ofSeconds(10)          // 정산 리포트 — 오래 걸리는 게 정상이다
    );

    @Bean
    public RestTemplate settlementRestTemplate(CloseableHttpClient httpClient) {
        var factory = new HttpComponentsClientHttpRequestFactory(httpClient);
        // factory.setReadTimeout(...) 은 팩토리 전역값이라 안 쓴다. 요청별로 갈라야 하므로 컨텍스트로 준다
        factory.setHttpContextFactory((method, uri) -> {
            HttpClientContext ctx = HttpClientContext.create();
            Timeout responseTimeout = RESPONSE_TIMEOUTS.get(uri.getPath());
            if (responseTimeout != null) {
                ctx.setRequestConfig(RequestConfig.copy(BASE_REQUEST_CONFIG)
                        .setResponseTimeout(responseTimeout)
                        .build());
            }
            return ctx;   // config 를 안 넣으면 createRequest 가 클라이언트 기본값(BASE)을 채운다
        });
        return new RestTemplate(factory);
    }
}
```

```java
// URI 를 보고 팩토리가 갈라 준다
restTemplate.getForObject("https://api.example.com/balance", Balance.class);            // → 300ms
restTemplate.getForObject("https://api.example.com/settlement/report", Report.class);   // → 10s
restTemplate.getForObject("https://api.example.com/merchants/1", Merchant.class);       // → 5s (BASE)
```

`/merchants/1` 처럼 맵에 없는 경로는 컨텍스트에 config 가 안 들어간 채로 나가고, 그 뒤를 `createRequest` 가 받는다.

```java
// HttpComponentsClientHttpRequestFactory  (spring-web 6.2.5 :252~291)
if (!(context instanceof HttpClientContext clientContext && clientContext.getRequestConfig() != null) && ...) {
    ...
    config = createRequestConfig(client);        // :260
}
...
protected RequestConfig createRequestConfig(Object client) {
    if (client instanceof Configurable configurableClient) {
        RequestConfig clientRequestConfig = configurableClient.getConfig();   // ★ setDefaultRequestConfig 로 넣은 BASE
        return mergeRequestConfig(clientRequestConfig);
    }
    ...
}
```

`mergeRequestConfig` 는 팩토리의 `connectTimeout`/`connectionRequestTimeout`/`readTimeout` 이 전부 미설정(-1)이면 받은 config 를 그대로 돌려준다(`:302~303`). 여기서는 아무것도 안 세팅했으니 `BASE_REQUEST_CONFIG` 가 손대지 않은 채 그대로 쓰인다.

**최종 정리 — 설정 다섯 개가 각각 어디에 걸리나**

| 설정 | 값 | 걸리는 시점 | 소비 지점 |
|---|---|---|---|
| `SocketConfig.soTimeout` | 2s | 소켓 생성 직후, `connect` 전 (`:196`) | TLS handshake read |
| `ConnectionConfig.connectTimeout` | 1s | `socket.connect()` 인자 (`:216`) | `timedFinishConnect` (3장). DNS 주소마다 full (6-3) |
| `ConnectionConfig.socketTimeout` | 3s | 커넥션 수립 직후 1회 (`:504`) | `timedRead` (4장). `responseTimeout` 이 없을 때만 살아남는다 |
| `RequestConfig.connectionRequestTimeout` | 200ms | 풀 lease 요청 시 | `connRequest.get(...)` (`:111`, 5장). 소켓과 무관 |
| `RequestConfig.responseTimeout` | 300ms / 10s / 5s | 매 요청 실행 직전 (`:228`) | `timedRead` (4장) |

요청 경로별로 `responseTimeout` 이 어디서 오는지:

| 요청 | `responseTimeout` | 출처 |
|---|---|---|
| `/balance` | 300ms | `RESPONSE_TIMEOUTS` → 컨텍스트 |
| `/settlement/report` | 10s | `RESPONSE_TIMEOUTS` → 컨텍스트 |
| 그 외 (`/merchants/1` …) | 5s | `BASE_REQUEST_CONFIG` — `createRequest` 가 채운다 |

그리고 `/settlement/report` 로 **새 커넥션**을 여는 요청 하나 동안, 그 소켓의 SO_TIMEOUT 은 이렇게 바뀐다.

| 순서 | 일어나는 일 | 그 순간 SO_TIMEOUT |
|---|---|---|
| 1 | 소켓 생성 → `setSoTimeout` (`:196`) | 2s |
| 2 | `socket.connect(addr, 1000)` (`:216`) | 2s (connect 상한은 별도 인자로 1s) |
| 3 | TLS handshake (`:231`) | **2s** ← 이 구간을 지키는 값 |
| 4 | 풀 매니저가 덮어씀 (`:504`) | 3s |
| 5 | 요청 실행 직전 (`:228`) | **10s** |
| 6 | 응답 헤더·바디 read | 10s (되돌리는 코드 없음) |

> `ConnectionConfig.socketTimeout` 3s 는 4번과 5번 사이에만 유효한데 그 사이엔 read 가 없다. `responseTimeout` 이 `null` 인 요청이 생길 때의 fallback 이다.
> 그리고 `/balance` 의 300ms 는 **응답 대기 상한이지 요청 전체 상한이 아니다.** 새 커넥션이면 앞에 `connectTimeout`(주소가 N 개면 최악 `N × 1s`)과 handshake 최대 2s 가 붙는다. 총 상한은 8장에서 다룬다.

동작하는 이유는 `createRequest` 가 컨텍스트를 먼저 검사하기 때문이다.

```java
// HttpComponentsClientHttpRequestFactory#createRequest  (spring-web 6.2.5)
HttpContext context = createHttpContext(httpMethod, uri);   // ← 등록한 httpContextFactory 가 호출된다
if (context == null) {
    context = HttpClientContext.create();
}

// Request configuration not set in the context
if (!(context instanceof HttpClientContext clientContext && clientContext.getRequestConfig() != null) &&
        context.getAttribute(HttpClientContext.REQUEST_CONFIG) == null) {    // ★ 이미 있으면 통째로 건너뛴다
    ...
    config = createRequestConfig(client);      // factory.setReadTimeout 이 반영되는 자리
    ...
}
```

> 6.2.5 이후 버전은 이 조건이 `hasCustomRequestConfig(context)` 메서드로 정리되면서, `RequestConfig.DEFAULT` **와 값이 같은 config 는 "커스텀 아님" 으로 보고 덮어쓴다**. 실무에서 걸릴 일은 드물지만, 기본값 그대로를 명시적으로 넣는 코드는 무시당한다.

#### 함정: `responseTimeout` 은 커넥션에 눌러붙는다

이 2층 구조는 실제로는 새어 나간다. `endpoint.setSocketTimeout()` 이 **실제 소켓뿐 아니라 커넥션이 기억하는 필드까지** 덮어쓰기 때문이다.

```java
// DefaultManagedHttpClientConnection  (5.4.2 :162~223)
@Override
public void setSocketTimeout(final Timeout timeout) {
    super.setSocketTimeout(timeout);
    socketTimeout = timeout;          // ★ 기억해 두는 값까지 갱신된다
}

@Override
public void passivate() {
    super.setSocketTimeout(Timeout.ZERO_MILLISECONDS);   // :218  풀 반납 시 0(무한)으로. 기억값은 안 건드린다
}

@Override
public void activate() {
    super.setSocketTimeout(socketTimeout);               // :223  풀에서 꺼낼 때 기억값으로 복원
}
```

`passivate()` 는 풀에 반납할 때(`PoolingHttpClientConnectionManager:440`), `activate()` 는 풀에서 빌릴 때(`:386`) 호출된다. `ConnectionConfig.socketTimeout = 5s` 인 풀에서 **요청 A 에만** `responseTimeout = 1s` 를 준 경우는 이렇게 흘러간다.

1. 새 커넥션 → `PoolingHttpClientConnectionManager:504` 가 5s 기록. 기억값 = **5s**
2. 요청 A 실행 → `setSocketTimeout(1s)` → 소켓 1s, **기억값도 1s 로 바뀜**
3. 풀 반납 → `passivate()` → 소켓 0. 기억값은 1s 그대로
4. 요청 B 가 같은 커넥션 lease → `activate()` → 5s 가 아니라 **1s 로 복원**
5. 요청 B 에 `responseTimeout` 이 없으면 덮어쓰기도 안 일어나므로 → **1s 로 실행**

`connect()` 는 `isConnected()` 면 즉시 return 하므로 `ConnectionConfig.socketTimeout` 은 두 번 다시 걸리지 않는다. 즉 **`socketTimeout` 은 "커넥션의 기본값" 이 아니라 "첫 초기값" 에 가깝다.** 한 요청이 바꿔 놓은 값이 풀 커넥션을 타고 다른 요청으로 흘러간다.

그래서 실무 결론은 이렇다.

- `socketTimeout` 은 handshake 구간까지 덮는 **바닥 안전망**으로 넉넉히 잡는다
- `responseTimeout` 은 **모든 요청에 빠짐없이 명시**한다. 일부 요청에만 주면 그 값이 새어 나간다
- 그런 점에서 (C) 의 `httpContextFactory` 가 가장 안전하다 — 요청마다 반드시 호출되므로 빠지는 요청이 생길 수 없다

> 정리: HC5 로 바꿔도 타임아웃의 물리 법칙은 안 바뀐다. 소비 지점은 `timedFinishConnect` / `timedRead` 그대로이고, 그 위에 **풀 lease 라는 새 대기 지점**과 **SO_TIMEOUT 을 요청 단위로 갈아끼우는 responseTimeout** 이 얹힌 것이다. 그리고 그 "갈아끼움" 은 요청이 끝나도 커넥션에 남는다.

## 7. 함정 정리

---

1. **`new RestTemplate()` / `SimpleClientHttpRequestFactory` 기본값은 무한 대기.** `-1` 이면 setter 호출조차 안 하고 `URLConnection` 기본 `0` = infinite (2-1). 시스템 프로퍼티 안전망(`sun.net.client.defaultConnectTimeout` 등)도 기본 `0`.
2. **connectTimeout 은 DNS 를 커버하지 않는다** (3-1). HC5 도 마찬가지 — 주소 배열을 다 뽑은 다음에야 connect 루프를 돈다 (6-3).
3. **readTimeout / socketTimeout / responseTimeout 은 총 응답 시간이 아니다.** 셋 다 결국 SO_TIMEOUT, 즉 read 호출당 상한이다 (4-2, 6-4). slow-drip 이면 영원히 안 끊긴다. 전체 상한이 필요하면 다른 레이어가 필요하다.
4. **keep-alive / 풀 재사용 시 connectTimeout 은 무의미.** 새 TCP 연결을 만들 때만 쓰인다 (3-1, 6-3).
5. **HC5 기본값은 connect·풀 대기 3분, 응답 대기 무한** (6-1). `HttpURLConnection` 의 "전부 무한"보다는 낫지만, 명시하지 않으면 스레드가 3분 + 무한으로 잡힐 수 있다.
6. **HC5 는 DNS 가 준 주소마다 connectTimeout 을 재시도**해서 최악 `N × connectTimeout` (6-3 의 주소 루프). `HttpURLConnection` 은 `new InetSocketAddress` 가 첫 주소만 고르므로 1회.

## 8. 클라이언트별 타임아웃 모델 비교

---

| 구현 | 타임아웃 축 |
|------|-----------|
| `SimpleClientHttpRequestFactory` (HttpURLConnection) | connect, read(SO_TIMEOUT) — **총 시간 상한 없음** |
| `HttpComponentsClientHttpRequestFactory` (HC5) | `connectionRequestTimeout`(풀 lease 대기, 6-2), `connectTimeout`, `socketTimeout`, `responseTimeout`(요청 단위 SO_TIMEOUT 덮어쓰기 — **총 상한 아님**, 6-4). **역시 총 시간 상한 없음** |
| `JdkClientHttpRequestFactory` (`java.net.http.HttpClient`) | `HttpClient.connectTimeout` + `HttpRequest.timeout`(응답 도착까지의 상한 — javadoc 기준. 바디 수신까지 덮는지는 미검증) |
| `ReactorClientHttpRequestFactory` | connect + `ReadTimeoutHandler` 등 Netty 핸들러 |

프로덕션에서 `HttpURLConnection` 은 함정 1 / 3 때문에 부적절하다. 단 HC5 로 바꿔도 "총 응답 시간 상한"은 생기지 않는다 — 그건 Resilience4j `TimeLimiter`, `@Transactional` 밖의 orchestration 타임아웃 등 별도 레이어의 일이다.

## 검증 코드

---

아래 두 테스트에서 본문의 발동 출력이 나왔다.

- `ConnectReadTimeoutTest` — 3-3 / 4-3 (`SimpleClientHttpRequestFactory`)
- `PooledConnectReadTimeoutTest` — 6-2 / 6-3 / 6-4 (HC5 + `PoolingHttpClientConnectionManager`, 클라이언트 구성은 6장 코드 그대로. 풀 고갈 재현은 풀 크기 1 + 무응답 서버에 첫 요청을 물려 놓고 두 번째 요청을 보내는 방식)

<details markdown="1">
<summary>테스트 전문</summary>

```java
class ConnectReadTimeoutTest {

    @Test
    void connectTimeout_blackhole_주소로_SYN_이_응답받지_못하면_발동한다() {
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(1_000);
        RestTemplate restTemplate = new RestTemplate(factory);

        long start = System.nanoTime();
        ResourceAccessException e = assertThrows(ResourceAccessException.class,
                () -> restTemplate.getForEntity("http://10.255.255.1/", String.class));
        long elapsedMs = (System.nanoTime() - start) / 1_000_000;

        System.out.println("elapsed: " + elapsedMs + "ms");
        printRootCause(e);   // 최심부 원인의 스택 상단 출력
        assertInstanceOf(SocketTimeoutException.class, e.getCause());
    }

    @Test
    void readTimeout_은_연결_후_응답을_기다리는_read_에서_발동한다() throws Exception {
        try (ServerSocket server = new ServerSocket(0)) {
            // accept 만 하고 응답은 영원히 안 내려주는 서버
            Thread silentServer = new Thread(() -> {
                try (Socket s = server.accept(); InputStream in = s.getInputStream()) {
                    byte[] buf = new byte[8192];
                    while (in.read(buf) != -1) { /* 요청은 읽되 응답은 안 씀 */ }
                } catch (Exception ignored) {
                }
            });
            silentServer.setDaemon(true);
            silentServer.start();

            SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
            factory.setConnectTimeout(1_000);
            factory.setReadTimeout(1_000);
            RestTemplate restTemplate = new RestTemplate(factory);

            ResourceAccessException e = assertThrows(ResourceAccessException.class,
                    () -> restTemplate.getForEntity("http://127.0.0.1:" + server.getLocalPort() + "/", String.class));
            printRootCause(e);
            assertInstanceOf(SocketTimeoutException.class, e.getCause());
        }
    }
}
```

</details>

## 참고 자료

---

- [Spring Framework - REST Clients (docs.spring.io)](https://docs.spring.io/spring-framework/reference/integration/rest-clients.html)
- [java.net.URLConnection#setConnectTimeout javadoc (docs.oracle.com)](https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/net/URLConnection.html#setConnectTimeout(int))
- [java.net.Socket#setSoTimeout javadoc (docs.oracle.com)](https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/net/Socket.html#setSoTimeout(int))
- [JEP 353: Reimplement the Legacy Socket API (openjdk.org)](https://openjdk.org/jeps/353)
