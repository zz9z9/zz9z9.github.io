# connectTimeout / readTimeout 은 언제, 어디서 적용되는가

> RestTemplate 호출 한 번을 Spring → JDK → 소켓 syscall 까지 따라가면서
> connectTimeout, readTimeout 이 각각 코드 어느 줄에서 실제로 소비되는지,
> 그 시점에 TCP 는 어떤 상태인지 정리.

**검증 환경 / 소스 버전**
- `spring-web 6.2.19` (Spring Boot 3.5.15, `spring-boot-starter-web` 만 의존)
- JDK 내부 소스: `temurin 21.0.7` / `GraalVM JDK 25` 의 `src.zip`
- 출발점 코드

```java
package inaction.http;

import org.springframework.web.client.RestTemplate;

public class Caller {
    private RestTemplate restTemplate = new RestTemplate();

    public void call(String url){
        restTemplate.getForEntity(url, String.class);
    }
}
```

**소스 까는 법 (직접 볼 때)**

```bash
# spring-web 소스
find ~/.gradle/caches -name "spring-web-*-sources.jar"
unzip -oq <위 경로> 'org/springframework/http/client/*' 'org/springframework/web/client/RestTemplate.java'

# JDK 내부 소스 (sun.* 은 IDE에서 기본으로 안 열림)
unzip -oq $(/usr/libexec/java_home -v 21)/lib/src.zip \
  'java.base/sun/net/**' 'java.base/java/net/*.java' 'java.base/sun/nio/ch/*.java' \
  'java.base/sun/security/ssl/*.java'
```

---

# 1. 어떤 구현체를 타는가

`new RestTemplate()` 은 request factory 를 지정하지 않는다. 상위 클래스 `HttpAccessor` 의 필드 기본값이 그대로 쓰인다.

```java
// org.springframework.http.client.support.HttpAccessor:56
private ClientHttpRequestFactory requestFactory = new SimpleClientHttpRequestFactory();
```

즉 **`java.net.HttpURLConnection` 기반**이다. (`spring-boot-starter-web` 만 있으면 httpclient5 는 클래스패스에 없음)

> 참고: `RestTemplateBuilder` / `RestClient` 를 쓰면 클래스패스에 있는 클라이언트(HttpClient5, Jetty, Reactor Netty …)를 자동으로 고른다. `new RestTemplate()` 직접 생성은 항상 `SimpleClientHttpRequestFactory`.

---

# 2. 전체 콜스택 (FQCN)

## 2-1. Spring 계층 — spring-web 6.2.19

```
inaction.http.Caller#call(String)
└ org.springframework.web.client.RestTemplate#getForEntity(String, Class, Object...)              RestTemplate.java:437
  └ org.springframework.web.client.RestTemplate#execute(String, HttpMethod, RequestCallback, ResponseExtractor, Object...)   :797
    │   callback  = org.springframework.web.client.RestTemplate$AcceptHeaderRequestCallback        :1009
    │   extractor = org.springframework.web.client.RestTemplate$ResponseEntityResponseExtractor    :1166
    └ org.springframework.web.client.RestTemplate#doExecute(URI, String, HttpMethod, RequestCallback, ResponseExtractor)     :877
      ├ org.springframework.http.client.support.HttpAccessor#createRequest(URI, HttpMethod)        HttpAccessor.java:123
      │ └ org.springframework.http.client.SimpleClientHttpRequestFactory#createRequest(URI, HttpMethod)
      │   ├ SimpleClientHttpRequestFactory#openConnection(URL, Proxy)
      │   │ └ java.net.URL#openConnection()
      │   │   └ sun.net.www.protocol.http.Handler#openConnection(URL, Proxy)   // 객체만 생성, I/O 없음
      │   ├ SimpleClientHttpRequestFactory#prepareConnection(HttpURLConnection, String)
      │   │     ★ connection.setConnectTimeout(int) / setReadTimeout(int)  — 필드 대입만
      │   └ new org.springframework.http.client.SimpleClientHttpRequest(HttpURLConnection, int)   // package-private
      ├ RestTemplate$AcceptHeaderRequestCallback#doWithRequest(ClientHttpRequest)   // Accept 헤더 채움
      ├ org.springframework.http.client.AbstractClientHttpRequest#execute()          AbstractClientHttpRequest.java:79
      │ └ org.springframework.http.client.AbstractStreamingClientHttpRequest#executeInternal(HttpHeaders)   :84
      │   └ org.springframework.http.client.SimpleClientHttpRequest#executeInternal(HttpHeaders, Body)
      │     ├ SimpleClientHttpRequest#addHeaders(HttpURLConnection, HttpHeaders)
      │     ├ java.net.HttpURLConnection#connect()          ──▶ 2-2 로 진입
      │     ├ java.net.HttpURLConnection#getResponseCode()  ──▶ 2-3 로 진입
      │     └ new org.springframework.http.client.SimpleClientHttpResponse(HttpURLConnection)
      ├ RestTemplate#handleResponse(URI, HttpMethod, ClientHttpResponse)
      │ └ org.springframework.web.client.DefaultResponseErrorHandler#hasError / handleError
      ├ RestTemplate$ResponseEntityResponseExtractor#extractData(ClientHttpResponse)
      │ └ org.springframework.web.client.HttpMessageConverterExtractor#extractData(ClientHttpResponse)
      │   └ org.springframework.http.converter.HttpMessageConverter#read(Class, HttpInputMessage)   ──▶ 2-4
      └ org.springframework.http.client.SimpleClientHttpResponse#close()                           ──▶ 2-5
```

상속 계층:
`SimpleClientHttpRequest` → `AbstractStreamingClientHttpRequest` → `AbstractClientHttpRequest` → `org.springframework.http.client.ClientHttpRequest`

## 2-2. `connect()` — connectTimeout 이 실제로 적용되는 경로

```
java.net.HttpURLConnection#connect()                                   (추상 — 실구현은 아래)
└ sun.net.www.protocol.http.HttpURLConnection#connect()                 HttpURLConnection.java:865
  └ sun.net.www.protocol.http.HttpURLConnection#plainConnect()                               :890
    └ sun.net.www.protocol.http.HttpURLConnection#plainConnect0()                            :902
      ├ sun.net.www.protocol.http.HttpURLConnection#getNewHttpClient(URL, Proxy, int)       :1028
      │ └ sun.net.www.http.HttpClient#New(URL, Proxy, int to, boolean useCache, HttpURLConnection)   HttpClient.java:328
      │   ├ sun.net.www.http.KeepAliveCache#get(URL, Object)      ← static 필드 kac, HttpClient.java:102
      │   │    ▶ HIT: 기존 ESTABLISHED 소켓 재사용 → 아래 전부 SKIP (connectTimeout 미사용)
      │   └ sun.net.www.http.HttpClient#<init>(URL, Proxy, int to)                           :265
      │     └ sun.net.www.http.HttpClient#openServer()                                       :585
      │       └ sun.net.www.http.HttpClient#openServer(String, int)                          :515
      │         └ sun.net.NetworkClient#openServer(String, int)                NetworkClient.java:120
      │           └ sun.net.NetworkClient#doConnect(String, int)                             :139   ★★ 핵심
      │             ├ sun.net.NetworkClient#createSocket()                                   :182
      │             │     (https 면 sun.net.www.protocol.https.HttpsClient#createSocket() 오버라이드  HttpsClient.java:417)
      │             ├ new java.net.InetSocketAddress(String, int)
      │             │ └ java.net.InetAddress#getByName → DNS 조회        ⚠ 타임아웃 미적용 구간
      │             ├ java.net.Socket#connect(SocketAddress, int timeout)             Socket.java:639
      │             │ └ sun.nio.ch.NioSocketImpl#connect(SocketAddress, int)     NioSocketImpl.java:561
      │             │   └ sun.nio.ch.NioSocketImpl#timedFinishConnect(FileDescriptor, long)  :540
      │             │       ★ SocketTimeoutException("Connect timed out")                    :546
      │             └ java.net.Socket#setSoTimeout(int)
      │               └ sun.nio.ch.NioSocketImpl#setOption(int, Object) → case SO_TIMEOUT    :1031
      ├ (https) sun.net.www.protocol.https.HttpsClient#afterConnect()            HttpsClient.java:453
      │   └ javax.net.ssl.SSLSocket#startHandshake()                                         :586
      │       ※ TLS 핸드셰이크는 connectTimeout 이 아니라 SO_TIMEOUT(readTimeout) 지배
      └ sun.net.www.http.HttpClient#setReadTimeout(int)   ← 호출부 HttpURLConnection.java:767
        └ sun.net.NetworkClient#setReadTimeout(int)                        NetworkClient.java:237
            → serverSocket.setSoTimeout(timeout)   ★ 소켓에 실제 기록. 재사용 소켓에도 매번 재적용
```

## 2-3. `getResponseCode()` — 요청 송신 + readTimeout 첫 발동

```
sun.net.www.protocol.http.HttpURLConnection#getResponseCode()
└ sun.net.www.protocol.http.HttpURLConnection#getInputStream()                               :1302
  └ sun.net.www.protocol.http.HttpURLConnection#getInputStream0()                            :1309
    ├ sun.net.www.protocol.http.HttpURLConnection#checkReuseConnection()                     :1160
    ├ sun.net.www.protocol.http.HttpURLConnection#writeRequests()        선언 :585 / 호출 :1390
    │     → request line + 헤더를 소켓 send buffer 로 write/flush  (첫 HTTP 바이트 송출)
    └ sun.net.www.http.HttpClient#parseHTTP(MessageHeader, HttpURLConnection)      HttpClient.java:710
      └ sun.net.www.http.HttpClient#parseHTTPHeader(MessageHeader, HttpURLConnection)        :774
        └ sun.net.www.MessageHeader#parseHeader(InputStream)
          └ java.net.Socket$SocketInputStream#read(byte[], int, int)
            └ sun.nio.ch.NioSocketImpl#read → #implRead(byte[], int, int)   NioSocketImpl.java:291
              └ sun.nio.ch.NioSocketImpl#timedRead(FileDescriptor, byte[], int, int, long)   :269
                  ★★ SO_TIMEOUT 을 실제로 소비하는 지점
                     SocketTimeoutException("Read timed out")                                :278
```

## 2-4. 바디 읽기 — readTimeout 재적용

```
org.springframework.web.client.HttpMessageConverterExtractor#extractData
└ org.springframework.http.converter.AbstractHttpMessageConverter#read
  └ (예) org.springframework.http.converter.StringHttpMessageConverter#readInternal
    └ org.springframework.http.client.SimpleClientHttpResponse#getBody()
      └ sun.net.www.http.KeepAliveStream / sun.net.www.MeteredStream#read
        └ … → sun.nio.ch.NioSocketImpl#timedRead   ← read() 호출마다 SO_TIMEOUT 새로 카운트
```

## 2-5. close — 커넥션 반납

```
org.springframework.http.client.SimpleClientHttpResponse#close()
└ sun.net.www.http.KeepAliveStream#close()
  ├ 잔여 바이트 drain (queuedForCleanup)
  └ sun.net.www.http.KeepAliveCache#put(URL, Object, HttpClient)   → TCP 는 ESTABLISHED 유지
     (실패 시 sun.net.www.http.HttpClient#closeServer() → FIN)
```

---

# 3. 단계별 소켓 / TCP 상태와 타임아웃

| # | 코드 | 소켓 · TCP 상태 | 타임아웃 |
|---|------|----------------|---------|
| 1 | `java.net.URL#openConnection()` | **아무것도 없음.** `sun.net.www.protocol.http.HttpURLConnection` 객체만 new. FD 미할당, 패킷 0 | — |
| 2 | `SimpleClientHttpRequestFactory#prepareConnection` | 동일 | `setConnectTimeout` / `setReadTimeout` — **필드에 값만 저장.** 아직 효과 없음 |
| 3 | `SimpleClientHttpRequest#addHeaders` | 동일 | 헤더도 아직 메모리(`sun.net.www.MessageHeader`)에만 존재 |
| 4 | `connection.connect()` → `plainConnect0()` → `HttpClient.New(...)` | keep-alive 캐시(`kac.get`) 조회. **HIT 이면 기존 ESTABLISHED 소켓 재사용 → 4-a~4-c 전부 스킵** | 캐시 HIT 시 **connectTimeout 은 아예 쓰이지 않음** |
| 4-a | `NetworkClient#doConnect` → `createSocket()` | FD 할당, TCP **CLOSED** | — |
| 4-b | `new InetSocketAddress(server, port)` | **DNS 조회 (UDP/TCP 53)** | ⚠ **어떤 타임아웃도 안 걸림** |
| 4-c | `s.connect(addr, connectTimeout)` | SYN 송신 → **SYN_SENT** → SYN+ACK 수신 → ACK → **ESTABLISHED** | ✅ **connectTimeout 발동.** 초과 시 `SocketTimeoutException("Connect timed out")` |
| 4-d | `s.setSoTimeout(readTimeout)` (`NetworkClient#doConnect` 끝) + `http.setReadTimeout(readTimeout)` (`HttpURLConnection:767`) | ESTABLISHED. SO_TIMEOUT 값 세팅만 | readTimeout "장전" |
| — | `connect()` 리턴 시점 | **TCP 는 붙었지만 HTTP 바이트는 단 1개도 안 나갔음** | |
| 5 | `getResponseCode()` → `getInputStream0()` → `writeRequests()` | request line + 헤더를 send buffer 로 write/flush → 커널이 PSH/ACK 전송 | write 는 보통 논블로킹(버퍼 여유). 버퍼가 꽉 차면 여기서 블로킹 |
| 6 | `HttpClient#parseHTTP` | 소켓 **read() 블로킹** — 응답 첫 바이트 대기 | ✅ **readTimeout 최초 실효.** 초과 시 `SocketTimeoutException("Read timed out")` |
| 7 | `RestTemplate#handleResponse` → `getStatusCode()` | 이미 파싱 완료. **I/O 없음** | — |
| 8 | `extractData()` → 메시지 컨버터가 body `InputStream` read | 바디 청크 수신 | ✅ readTimeout **매 read 호출마다 새로 카운트** |
| 9 | `SimpleClientHttpResponse#close()` | 잔여 바이트 drain 후 `KeepAliveCache` 반납 → **ESTABLISHED 유지**. 실패 시 FIN → FIN_WAIT_1 | — |

> 핵심: **타임아웃이 "설정"되는 시점(2)과 "적용"되는 시점(4-c, 6)이 다르다.**
> `prepareConnection` 은 그냥 필드 대입이고, 실제 동작은 `sun.net.NetworkClient#doConnect` 안에서 일어난다.

---

# 4. connectTimeout 이 소비되는 실제 코드

`NioSocketImpl#connect` 자체가 아니라, 그 안의 private 헬퍼가 던진다.

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
        park(fd, Net.POLLOUT, remainingNanos);            // :548  남은 예산만큼만 poll
        polled = Net.pollConnectNow(fd);
    }
    return polled && isOpen();
}
```

> 메시지는 **`"Connect timed out"`** (대문자 C). 옛날 `PlainSocketImpl` 시절의 `"connect timed out"` 과 다르므로 로그 grep 시 주의.

여기까지 오는 조건:

```java
// sun.nio.ch.NioSocketImpl#connect(SocketAddress, int)  :561
protected void connect(SocketAddress remote, int millis) throws IOException {
    ...
    ReentrantLock connectLock = readLock;                     // :575  readLock 재사용
    try {
        connectLock.lock();
        try {
            boolean connected = false;
            FileDescriptor fd = beginConnect(address, port);  // :485  state = ST_CONNECTING
            try {
                configureNonBlockingIfNeeded(fd, millis > 0); // :582  ★ timeout>0 이면 O_NONBLOCK
                int n = Net.connect(fd, address, port);       // :583  native connect(2)
                if (n > 0) {
                    connected = true;                         // 즉시 성립 (loopback 등)
                } else {
                    assert IOStatus.okayToRetry(n);           // EINPROGRESS
                    if (millis > 0) {
                        long nanos = MILLISECONDS.toNanos(millis);
                        connected = timedFinishConnect(fd, nanos);   // :592  ★ 여기
                    } else {
                        while (!polled && isOpen()) {         // timeout 0 → 무한 park
                            park(fd, Net.POLLOUT);
                            polled = Net.pollConnectNow(fd);
                        }
                    }
                }
            } finally {
                endConnect(fd, connected);                    // :521
            }
        } finally {
            connectLock.unlock();
        }
    } catch (IOException ioe) {
        close();                                              // :610  ★ FD 정리
        if (ioe instanceof InterruptedIOException) {
            throw ioe;                                        // :612  ★ 원본 그대로 재던짐
        } else {
            throw SocketExceptions.of(ioe, isa);              // :614
        }
    }
}
```

**포인트 3개**

1. **`millis > 0` 일 때만 이 경로를 탄다.** `configureNonBlockingIfNeeded(fd, millis > 0)` 로 FD 를 논블로킹으로 바꾼 뒤 `Net.connect` 가 `EINPROGRESS` 를 내면 `timedFinishConnect` 로 간다. `millis == 0`(무한) 이면 타임아웃 없는 `park(fd, POLLOUT)` 루프라 여기 안 온다.
   (예외: 가상 스레드에서는 `configureNonBlockingIfNeeded` 조건이 `timed || isVirtual()` 이라 항상 논블로킹 — `NioSocketImpl:207`)

2. **`SocketTimeoutException` 은 `InterruptedIOException` 의 서브클래스다.**
   ```java
   public class SocketTimeoutException extends java.io.InterruptedIOException   // SocketTimeoutException.java:34
   ```
   그래서 `catch (IOException ioe)` 안의 `instanceof InterruptedIOException` 분기에 걸려 **`SocketExceptions.of()` 로 감싸지지 않고 원본 인스턴스가 그대로 올라간다.** 단 그 직전 **`close()` 는 반드시 호출**되므로 타임아웃 난 소켓 FD 는 여기서 정리된다. (TCP 는 아직 SYN_SENT 였으므로 커널이 소켓 폐기 — RST 도 FIN 도 안 나감)

3. **실제 대기는 `park` 에서 `poll(2)` 로 일어난다.**
   ```java
   // sun.nio.ch.NioSocketImpl#park(FileDescriptor, int, long)  :171
   Thread t = Thread.currentThread();
   if (t.isVirtual()) {
       Poller.poll(fdVal(fd), event, nanos, this::isOpen);   // 가상 스레드: 캐리어 안 잡음
       if (t.isInterrupted()) throw new InterruptedIOException();
   } else {
       long millis = NANOSECONDS.toMillis(nanos);
       if (nanos > MILLISECONDS.toNanos(millis)) millis++;   // 올림 — 요청보다 짧게 깨지 않도록
       Net.poll(fd, event, millis);                          // 플랫폼 스레드: native poll
   }
   ```

## 같은 패턴의 형제들

| 예외 메시지 | 위치 | 소비하는 타임아웃 |
|---|---|---|
| `"Connect timed out"` | `NioSocketImpl#timedFinishConnect` **:546** | `Socket#connect(addr, timeout)` 인자 |
| `"Read timed out"` | `NioSocketImpl#timedRead` **:278** | `SO_TIMEOUT` (`setSoTimeout`) |
| `"Accept timed out"` | `NioSocketImpl#implAccept` **:701, :731** | `ServerSocket` 의 `SO_TIMEOUT` |

세 곳 다 구조가 같다 — `startNanos` 찍고 → 논블로킹 시도 → `remainingNanos <= 0` 이면 throw → 아니면 남은 만큼 `park`. 예산을 매 루프 재계산하므로 spurious wakeup 이 있어도 전체 상한은 지켜진다.

```java
// sun.nio.ch.NioSocketImpl#timedRead  :269
private int timedRead(FileDescriptor fd, byte[] b, int off, int len, long nanos) throws IOException {
    long startNanos = System.nanoTime();        // ★ :271  호출될 때마다 새로 찍힘
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

`startNanos` 가 **호출마다** 새로 찍히는 게 "SO_TIMEOUT 은 read 호출당 상한" 이라는 성질의 근원이다.

---

# 5. SO_TIMEOUT 의 정체 — RFC 도 커널 옵션도 아니다

## 5-1. Java 자체 상수일 뿐

```java
// java.base/java/net/SocketOptions.java:273
@Native public static final int SO_TIMEOUT = 0x1006;
```

`Socket#setSoTimeout(int)` → `SocketImpl#setOption(SO_TIMEOUT, millis)` 로 흘러가는 정수 태그.

**`java.net.StandardSocketOptions` 에는 `SO_TIMEOUT` 이 아예 없다.** 거기 있는 건 `SO_BROADCAST`, `SO_KEEPALIVE`, `SO_SNDBUF`, `SO_RCVBUF`, `SO_REUSEADDR`, `SO_REUSEPORT`, `SO_LINGER` — 전부 실제 커널 옵션이다. NIO 채널 API(`SocketChannel#setOption`)로는 SO_TIMEOUT 을 못 건다. 그런 개념이 없다.

## 5-2. 커널에 안 내려간다는 증거

`NioSocketImpl#setOption` 에서 다른 옵션과 처리가 확연히 다르다.

```java
// sun.nio.ch.NioSocketImpl#setOption(int, Object)  :1015
case SO_LINGER: {
    Net.setSocketOption(fd, StandardSocketOptions.SO_LINGER, i);   // → setsockopt(2)
    break;
}
case TCP_NODELAY: {
    Net.setSocketOption(fd, StandardSocketOptions.TCP_NODELAY, b); // → setsockopt(2)
    break;
}
case SO_TIMEOUT: {                                    // :1031
    int i = intValue(value, "SO_TIMEOUT");
    if (i < 0) throw new IllegalArgumentException("timeout < 0");
    timeout = i;              // ★ 그냥 자바 필드에 대입. syscall 없음.
    break;
}
```

```java
private volatile int timeout;   // NioSocketImpl.java:119
```

그리고 이 필드는 read 시점에 **유저 공간 poll 루프의 상한값**으로만 쓰인다.

```java
// sun.nio.ch.NioSocketImpl#implRead  :291
int timeout = this.timeout;
configureNonBlockingIfNeeded(fd, timeout > 0);   // O_NONBLOCK 전환
if (timeout > 0) {
    n = timedRead(fd, b, off, len, MILLISECONDS.toNanos(timeout));   // :304
} else {
    n = tryRead(fd, b, off, len);
    while (IOStatus.okayToRetry(n) && isOpen()) {
        park(fd, Net.POLLIN);        // 무한 대기
        n = tryRead(fd, b, off, len);
    }
}
```

즉 **JVM 은 소켓을 논블로킹으로 바꾸고 `poll(2)` 의 timeout 인자로 시간을 관리한다.** `setsockopt(SO_RCVTIMEO)` 는 호출조차 안 한다. `strace` / `dtruss` 로 떠도 안 나온다.

## 5-3. 진짜 커널 옵션은 SO_RCVTIMEO

```c
// macOS <sys/socket.h> — 실제로 확인
#define SO_SNDBUF       0x1001
#define SO_RCVBUF       0x1002
#define SO_SNDTIMEO     0x1005    /* send timeout */
#define SO_RCVTIMEO     0x1006    /* receive timeout */
```

Java 의 `SO_TIMEOUT = 0x1006` 이 BSD 의 `SO_RCVTIMEO` 와 값이 같은 건 90년대 BSD 헤더에서 번호를 그대로 가져온 흔적이다. 의미만 빌리고 구현은 안 쓴다. (Linux 는 `SO_RCVTIMEO` 가 20 이라 값도 안 맞음)

`SO_RCVTIMEO` / `SO_SNDTIMEO` 도 RFC 가 아니라 **POSIX.1-2001 / `setsockopt(2)`** 소켓 API 스펙이다. RFC 는 와이어 프로토콜(패킷 포맷, 상태 머신)을 정의하지 OS 의 소켓 API 를 정의하지 않는다.

## 5-4. RFC 에 있는 타임아웃과의 구분

| 이름 | 정의처 | 계층 | 와이어에 나타남? |
|---|---|---|---|
| `SO_TIMEOUT` | **Java 자체** (`SocketOptions:273`) | JVM 유저 공간 poll 루프 | ❌ |
| `SO_RCVTIMEO` / `SO_SNDTIMEO` | POSIX.1-2001, `setsockopt(2)` | 커널 소켓 API | ❌ |
| `TCP_USER_TIMEOUT` | **RFC 5482** (TCP User Timeout Option) + Linux 소켓 옵션 | TCP 스택 | ⭕ UTO 옵션 협상 시 |
| TCP Keepalive (`SO_KEEPALIVE`, `TCP_KEEPIDLE` …) | **RFC 1122 §4.2.3.6** | TCP 스택 | ⭕ keepalive probe |
| TCP 재전송 타이머 / RTO | **RFC 6298**, **RFC 9293** | TCP 스택 | ⭕ 재전송 |
| HTTP `Keep-Alive: timeout=n` | RFC 9112 (구 7230) | HTTP | ⭕ 헤더 |

**실무적 차이:** `SO_TIMEOUT` 은 애플리케이션 스레드가 read 를 기다리는 시간만 잰다. 타임아웃이 나도 **TCP 연결은 멀쩡히 ESTABLISHED 로 남아 있다** — 커널은 아무것도 모른다. 그래서 `NioSocketImpl#connect` 의 catch 블록이 명시적으로 `close()` 를 부르고, `HttpURLConnection` 도 타임아웃 후엔 keep-alive 캐시에 반납하지 않는다.

반대로 `TCP_USER_TIMEOUT`(Linux `setsockopt(IPPROTO_TCP, TCP_USER_TIMEOUT, ms)`)은 커널 레벨이라 미확인 데이터가 그 시간을 넘기면 **커널이 연결 자체를 끊는다.** 상대 서버가 조용히 죽어서 FIN/RST 도 못 보낸 경우(전원 차단, 방화벽 drop) `SO_TIMEOUT` 만으로는 커넥션 풀에 좀비 커넥션이 남는데, `TCP_USER_TIMEOUT` 이나 keepalive 가 그걸 잡아준다. Java 표준 API 로는 못 걸고 `jdk.net.ExtendedSocketOptions` 또는 Netty 의 `EpollChannelOption.TCP_USER_TIMEOUT` 이 필요하다.

> 요약: `SO_TIMEOUT` 은 "소켓 옵션" 이라는 이름을 달고 있지만 실제로는 **JVM 이 `poll(2)` 대기 상한으로 흉내 내는 애플리케이션 레벨 타임아웃**이다. 커널도 모르고, 네트워크 상대방도 모르고, RFC 에도 없다.

---

# 6. SocketImpl 구현체 지도

## 6-1. 계층 구조

```
java.net.SocketImpl (abstract, implements java.net.SocketOptions)          SocketImpl.java:45
│
├─ sun.nio.ch.NioSocketImpl                                             NioSocketImpl.java:78
│     implements sun.net.PlatformSocketImpl (마커 인터페이스)
│     ★ 실제 syscall 을 하는 유일한 구현체 (JDK 13 JEP 353 / 15 JEP 373 로 통합)
│
├─ java.net.DelegatingSocketImpl (package-private, abstract)      DelegatingSocketImpl.java:40
│  │    protected final SocketImpl delegate;
│  │    assert delegate instanceof PlatformSocketImpl;   ← 델리게이트는 반드시 플랫폼 impl
│  ├─ java.net.SocksSocketImpl                                    SocksSocketImpl.java:53,57
│  └─ java.net.HttpConnectSocketImpl                          HttpConnectSocketImpl.java:44
│
└─ sun.nio.ch.DummySocketImpl (package-private)                  DummySocketImpl.java:41
      모든 메서드가 InternalError. sun.nio.ch.SocketAdaptor:62 /
      sun.nio.ch.ServerSocketAdaptor:75 전용 (SocketChannel#socket() 의 껍데기)
```

**`SocksSocketImpl` / `HttpConnectSocketImpl` 은 I/O 를 안 한다.** 프록시 네고시에이션만 담당하고 실제 connect/read/write 는 안에 든 `NioSocketImpl` 에 위임한다. JDK 17 이전의 `java.net.PlainSocketImpl` / `AbstractPlainSocketImpl` / `TwoStacksPlainSocketImpl` 은 전부 삭제됐다.

## 6-2. 어느 생성자가 뭘 만드나

| 생성 코드 | 결과 impl | 소스 |
|---|---|---|
| `new Socket()` / `new Socket(host, port)` | `SocksSocketImpl(NioSocketImpl)` | `java.net.Socket#createImpl()` **Socket.java:570** |
| `new Socket(Proxy.NO_PROXY)` | **`NioSocketImpl` 직접** (래퍼 없음) | `java.net.Socket#Socket(Proxy)` **:242~250** |
| `new Socket(new Proxy(SOCKS, addr))` | `SocksSocketImpl(proxy, NioSocketImpl)` | **Socket.java:240** |
| `new Socket(new Proxy(HTTP, addr))` | `HttpConnectSocketImpl(proxy, NioSocketImpl, socket)` | **Socket.java:241** |
| `SocketChannel.open().socket()` | `DummySocketImpl` (플레이스홀더) | `sun.nio.ch.SocketAdaptor:62` — 실 I/O 는 `SocketChannelImpl` |
| `Socket.setSocketImplFactory(f)` (deprecated) | `f.createSocketImpl()` | Socket.java:1918 |

```java
// java.net.SocketImpl:51 — 갈림길의 끝
static <S extends SocketImpl & PlatformSocketImpl> S createPlatformSocketImpl(boolean server) {
    return (S) new NioSocketImpl(server);      // 항상 이것 하나
}
```

`Socket#createImpl()` 은 프록시를 안 줘도 **무조건 `SocksSocketImpl` 로 감싼다.** `SocksSocketImpl#connect` 가 런타임에 `ProxySelector.getDefault()` 를 상담해야 하기 때문이다(`SocksSocketImpl.java:279~294`). 프록시가 없으면 바로 `delegate.connect(epoint, ...)` 로 통과한다.

## 6-3. 두 래퍼의 동작 차이

**`SocksSocketImpl`** — SOCKS4/5 네고시에이션을 직접 수행. 타임아웃 관점에서는 **deadline 방식**이 핵심이다.

```java
// java.net.SocksSocketImpl#connect(SocketAddress, int)  :257
protected void connect(SocketAddress endpoint, int timeout) throws IOException {
    long finish = System.currentTimeMillis() + timeout;
    deadlineMillis = ...;
    ...
    delegate.connect(epoint, remainingMillis(deadlineMillis));   // :294, :321, :327
```

즉 `connectTimeout` 이 **프록시 TCP 연결 + SOCKS 핸드셰이크 전체**를 덮는다. 남은 예산을 계속 깎아서 넘긴다.

**`HttpConnectSocketImpl`** — 이름과 달리 자기가 CONNECT 를 말지 않는다. 리플렉션으로 `sun.net.www.protocol.http.HttpURLConnection#doTunneling()` 을 호출해서 터널링시킨 뒤(`HttpConnectSocketImpl.java:39~46` static 블록), 다 뚫리면 **소켓의 impl 자체를 갈아끼운다.**

```java
// java.net.HttpConnectSocketImpl#connect  :119~137
Socket httpSocket = privilegedDoTunnel(urlString, timeout);
close();                        // 원래 delegate FD 반납
SocketImpl si = httpSocket.impl();
socket.setImpl(si);             // ★ Socket 이 들고 있는 impl 을 통째로 교체
try {
    for (entry : optionsMap) si.setOption(entry.getKey(), entry.getValue());
} catch (IOException x) {  /* gulp! */  }     // ← 소스에 실제로 이렇게 적혀 있음
```

`connect()` 전에 걸어둔 `setSoTimeout` 등은 `optionsMap` 에 보관했다가(`setOption` :156~166) 나중에 best-effort 로 재적용되고, 실패하면 조용히 삼켜진다.

## 6-4. RestTemplate 경로에서는 뭐가 쓰이나

```java
// sun.net.NetworkClient:182
protected Socket createSocket() throws IOException {
    return new java.net.Socket(Proxy.NO_PROXY);  // direct connection
}
```

**HTTP 직결 → `NioSocketImpl` 직접.** 래퍼 0겹, `ProxySelector` 상담도 안 한다.

**HTTPS 는 다르다.** `sun.net.www.protocol.https.HttpsClient#createSocket()` (:417) 이 오버라이드해서 `sslSocketFactory.createSocket()` → `sun.security.ssl.SSLSocketImpl` 을 돌려준다. 이건 **`SocketImpl` 이 아니라 `java.net.Socket` 서브클래스**다.

```
sun.security.ssl.SSLSocketImpl
  → sun.security.ssl.BaseSSLSocketImpl        BaseSSLSocketImpl.java:54
    → javax.net.ssl.SSLSocket
      → java.net.Socket
```

생성자가 `super()` = `new Socket()` 을 타므로(`SSLSocketImpl.java:121~122` → `Socket.java:181` → `createImpl()`) 내부 impl 은 **`SocksSocketImpl(NioSocketImpl)`** 이 된다.

| 스킴 | Socket 객체 | impl 체인 | ProxySelector |
|---|---|---|---|
| `http://` | `java.net.Socket` | `NioSocketImpl` | 상담 안 함 |
| `https://` | `sun.security.ssl.SSLSocketImpl` | `SocksSocketImpl` → `NioSocketImpl` | **상담함** |

`socksProxyHost` 시스템 프로퍼티를 걸었을 때 HTTPS 만 프록시를 타는 현상이 여기서 나온다.

또한 `NetworkClient#doConnect` 는 HTTP 프록시 케이스에서도 `new Socket(Proxy.NO_PROXY)` 로 프록시 주소에 직접 붙고 터널링은 `HttpClient` 가 처리하므로, **`HttpConnectSocketImpl` 은 `HttpURLConnection` 경로에서 절대 안 쓰인다.** 사용자 코드가 `new Socket(new Proxy(Type.HTTP, addr))` 를 직접 할 때만 등장한다.

---

# 7. 함정 정리

## 7-1. `new RestTemplate()` 은 타임아웃이 무한대

```java
// org.springframework.http.client.SimpleClientHttpRequestFactory
private int connectTimeout = -1;
private int readTimeout = -1;

protected void prepareConnection(HttpURLConnection connection, String httpMethod) {
    if (this.connectTimeout >= 0) connection.setConnectTimeout(this.connectTimeout);
    if (this.readTimeout >= 0)    connection.setReadTimeout(this.readTimeout);
    ...
}
```

`-1` 이면 `setConnectTimeout` 을 **호출조차 안 하고**, `URLConnection` 기본값은 `0` = infinite 다. 상대 서버가 SYN 에 응답 안 하거나 응답을 안 내려주면 그 스레드는 영원히 잡혀 있다.

마지막 안전망은 시스템 프로퍼티뿐이고 기본값은 `0`(무한).

```java
// sun.net.NetworkClient  static 초기화 :56~72
protected static int defaultSoTimeout;
protected static int defaultConnectTimeout;
int soTimeout   = Integer.getInteger("sun.net.client.defaultReadTimeout", 0);
int connTimeout = Integer.getInteger("sun.net.client.defaultConnectTimeout", 0);
```

## 7-2. connectTimeout 은 DNS 를 커버하지 않는다

```java
// sun.net.NetworkClient#doConnect  :139
if (connectTimeout >= 0) {
    s.connect(new InetSocketAddress(server, port), connectTimeout);
    //        └─ 여기서 DNS resolve 가 먼저 끝난 다음에야 타이머 시작
}
```

DNS 가 5초 걸리면 connectTimeout 1초여도 총 6초.

## 7-3. readTimeout 은 "총 응답 시간" 이 아니다

SO_TIMEOUT 은 매 `read()` 마다 리셋된다(`timedRead:271`). 서버가 `readTimeout - 1ms` 마다 1바이트씩 흘려보내면 **영원히 안 끊긴다** (slow-drip / Slowloris 형태). 전체 시간 상한이 필요하면 별도 레이어가 있어야 한다.

## 7-4. keep-alive 재사용 시 connectTimeout 은 무의미

`HttpClient.New` 가 `KeepAliveCache` 에서 커넥션을 꺼내면 TCP 핸드셰이크 자체가 없다. connectTimeout 은 첫 연결에만 의미가 있고, 그 뒤로는 readTimeout 이 전부다.

## 7-5. HC5 는 주소마다 connectTimeout 을 재시도

Apache HttpClient5 는 DNS 가 여러 IP 를 주면 각 주소마다 connectTimeout 을 full 로 재시도해서 최악 `N × connectTimeout` 이 된다. (`HttpURLConnection` 은 `new InetSocketAddress` 가 첫 주소만 고르므로 1회)

---

# 8. 클라이언트별 타임아웃 모델 비교

| 구현 | 타임아웃 축 |
|------|-----------|
| `SimpleClientHttpRequestFactory` (HttpURLConnection) | connect, read(SO_TIMEOUT) — **총 시간 상한 없음** |
| `HttpComponentsClientHttpRequestFactory` (HC5) | `connectionRequestTimeout`(**풀에서 커넥션 빌리는 대기** — 풀 고갈 시 여기서 터짐), `connectTimeout`, `socketTimeout`, `responseTimeout`(총 응답 상한 ✅) |
| `JdkClientHttpRequestFactory` (`java.net.http.HttpClient`) | `HttpClient.connectTimeout` + `HttpRequest.timeout`(**전체 요청 상한** ✅) |
| `ReactorClientHttpRequestFactory` | connect + `ReadTimeoutHandler` 등 Netty 핸들러 |

프로덕션에서 `HttpURLConnection` 은 7-1 / 7-3 때문에 부적절하다.

---

# 9. 직접 확인하는 법

## 9-1. 브레이크포인트

| 목적 | 위치 |
|---|---|
| connectTimeout 실제 값 확인 | `sun.net.NetworkClient#doConnect` :139 |
| SO_TIMEOUT 이 언제/몇 번 세팅되는지 | `sun.net.NetworkClient#setReadTimeout` :237 (생각보다 여러 번 호출됨) |
| 남은 대기 예산 확인 | `sun.nio.ch.NioSocketImpl#timedRead` :269 의 `nanos` 인자 |
| 어느 impl 이 만들어졌는지 | `java.net.SocketImpl#createPlatformSocketImpl` :51 — 모든 경로가 여기로 수렴 |

## 9-2. 실제 impl 리플렉션으로 확인

```java
Field f = Socket.class.getDeclaredField("impl");
f.setAccessible(true);                 // --add-opens java.base/java.net=ALL-UNNAMED
System.out.println(f.get(socket).getClass());
```

## 9-3. 재현 실험 아이디어

- SYN 을 삼키는 blackhole 주소(`10.255.255.1`)로 → connectTimeout 발동 확인
- `ServerSocket` 으로 accept 만 하고 응답 안 주는 서버 → readTimeout 발동
- 1바이트씩 drip 내려주는 서버 → **readTimeout 이 안 걸리는 것** 재현 (7-3)
- 각 단계에서 `lsof -i` / `netstat -an | grep <port>` 로 SYN_SENT ↔ ESTABLISHED 관찰

---

# 참고 자료

- [JEP 353: Reimplement the Legacy Socket API (openjdk.org)](https://openjdk.org/jeps/353)
- [JEP 373: Reimplement the Legacy DatagramSocket API (openjdk.org)](https://openjdk.org/jeps/373)
- [RFC 5482 - TCP User Timeout Option (datatracker.ietf.org)](https://datatracker.ietf.org/doc/html/rfc5482)
- [RFC 1122 §4.2.3.6 - TCP Keep-Alives (datatracker.ietf.org)](https://datatracker.ietf.org/doc/html/rfc1122#section-4.2.3.6)
- [RFC 9293 - Transmission Control Protocol (datatracker.ietf.org)](https://datatracker.ietf.org/doc/html/rfc9293)
- [POSIX setsockopt (pubs.opengroup.org)](https://pubs.opengroup.org/onlinepubs/9699919799/functions/setsockopt.html)
- [java.net.Socket#setSoTimeout javadoc (docs.oracle.com)](https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/net/Socket.html#setSoTimeout(int))
- [Spring Framework - REST Clients (docs.spring.io)](https://docs.spring.io/spring-framework/reference/integration/rest-clients.html)

---

# TODO (최종 정리 시)

- [ ] 블로그 컨벤션 적용: front matter(`title` / `date` / `categories: [지식 더하기, 이론]` / `tags: [WEB]`), 파일명 `YYYY-MM-DD-connect-readtimeout.md` 로 rename
- [ ] `##` 헤딩 아래 `---` 구분선 + 첫 문장 blockquote 규칙 적용
- [ ] 9-3 재현 실험 실제로 돌려서 로그/출력 첨부 (blog CLAUDE.md 의 "내용 검증" 규칙)
- [ ] `2026-08-15-socket-status.md` (TIME_WAIT / CLOSE_WAIT) 와 상호 링크
- [ ] 글이 너무 길면 (1) RestTemplate 타임아웃 흐름 (2) SocketImpl / SO_TIMEOUT 내부 — 두 편으로 분리 검토
