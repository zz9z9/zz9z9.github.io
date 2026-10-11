---
title: WEB - 풀이 죽은 커넥션을 집는 경우
date: 2026-10-11 23:00:00 +0900
categories: [지식 더하기, 이론]
tags: [WEB]
---

> [1편](/posts/http-connection-pool-1-lifecycle/)에서 HttpClient5 커넥션 풀이 커넥션을 빌려주고 돌려받는 흐름과, 쉬는 동안 끊긴 커넥션을 쓰지 않으려고 시각(keep-alive·`evictIdleConnections`·`timeToLive`)과 `isStale()` 로 거르는 설정을 봤다. <br>
> 이 글은, 그럼에도 죽은 커넥션에 요청이 실리는 경우(시각 계산이 어긋나거나 `isStale()` 이 못 막는 경우)를 정리한다. 이어서 죽은 커넥션에 요청하면 어떤 예외가 나는지, 클라이언트가 스스로 재시도하는지를 보고, 검증으로 못 거르는 경로 소실을 실측한다. <br>
> 기준 버전은 httpclient5 5.4.2 / httpcore5 5.3.3 이다.

## 죽은 커넥션을 거르는 설정

---

> 풀은 쉬고 있던 커넥션이 그사이 끊겼을 수 있다고 보고, 아래 설정으로 거른다.

| 설정 | 기준 시각 | 언제 거르나 |
| --- | --- | --- |
| keep-alive (`Keep-Alive: timeout=N`, 없으면 `RequestConfig.setConnectionKeepAlive` 기본 3분) | 반납 시각 + N → `expiryDeadline` | 대여 직전, evict 스레드 |
| `ConnectionConfig.setValidateAfterInactivity` (기본 2초) | 마지막 반납 시각(`updated`) + 값 | 대여 직전에 `isStale()` 을 부른다 |
| `HttpClientBuilder.evictIdleConnections(t)` | `updated` + t | evict 스레드 |
| `ConnectionConfig.setTimeToLive` | 커넥션을 만든 시각(`created`) + 값 | 대여 직전, evict 스레드 |

- 소켓을 직접 들여다보는 건 `isStale()` 하나다. 나머지는 모두 **시각만 보고** 버린다.
  - 즉, 서버가 알려준 timeout 이나 클라이언트가 정한 주기가 지났는지를 계산한다.
- `isStale()`은 상대가 보낸 `FIN` 이나 `RST`가 소켓에 와 있는지를 본다.

## isStale() 동작 방식

---

> `isStale()` 은 소켓 읽기 타임아웃을 1ms 로 바꿔 한 번 읽어 보고, 상대가 보낸 **FIN 이나 RST 가 와 있으면 끊긴 것으로 본다.**

### FIN 과 RST

> 둘 다 TCP 세그먼트 헤더의 플래그다. <br>
> FIN 은 "이쪽은 보낼 데이터를 다 보냈다"는 정상 종료이고, RST 는 "이 연결은 없다"는 즉시 중단이다.


| | FIN | RST |
| --- | --- | --- |
| 뜻 | 이 방향으로는 더 보내지 않는다. 반대 방향은 열려 있다 | 연결을 그 자리에서 끝낸다 |
| 보내는 때 | 애플리케이션이 소켓을 `close()` 하거나 `shutdownOutput()` 할 때 | 커널이 모르는 연결로 세그먼트를 받았을 때(소켓이 이미 완전히 사라진 연결, 아무도 듣지 않는 포트), 안 읽은 데이터가 수신 버퍼에 남은 채로 `close()` 할 때, `SO_LINGER` 0 으로 `close()` 할 때, 방화벽이 `REJECT --reject-with tcp-reset` 할 때 |
| 받은 쪽 소켓 | ACK 를 보내고 `CLOSE_WAIT` 이 된다 | 상태 없이 바로 사라진다. 응답하지 않는다 |
| 받은 쪽 자바 코드 | 읽으면 -1 (EOF). 쓰기는 여전히 된다 | 읽기·쓰기에서 `SocketException` (`Connection reset` 등) |
| 끝난 뒤 | 양쪽이 FIN 을 주고받고, 먼저 닫은 쪽에 `TIME_WAIT` 이 남는다 | `TIME_WAIT` 이 남지 않는다 |

- EOF(End Of File)는 스트림이 끝나 더 읽을 데이터가 없다는 뜻이다.
- 소켓에서는 FIN 을 받은 뒤 그 전에 온 데이터를 다 읽고 나면 `read()` 가 -1 을 돌려주는데, 이 -1 이 EOF 다.
- 패킷이나 특별한 바이트가 아니라 `read()` 가 알려 주는 상태다.

| 소켓 상황 | `read()` 결과 | 뜻 |
| --- | --- | --- |
| 아직 온 데이터가 없음 | 기다리다 `SocketTimeoutException` (`SO_TIMEOUT` 이 걸려 있을 때) | 지금은 없지만 앞으로 올 수 있다 |
| FIN 을 받음 | -1 (EOF) | 상대는 더 보내지 않는다 |
| RST 를 받음 | `SocketException` | 연결이 비정상으로 끊겼다 |

> 정상 종료는 양쪽이 FIN 을 하나씩 보내야 끝난다. 한쪽만 FIN 을 보낸 상태를 half-close 라 한다.

-  연결부터 종료까지 세그먼트와 소켓 상태는 이렇게 흘러간다.

![연결부터 종료까지의 TCP 세그먼트와 소켓 상태 — ① 3-way handshake 로 client 는 SYN_SENT 를 거쳐, server 는 LISTEN·SYN_RECV 를 거쳐 ESTABLISHED 가 된다. ② 요청·응답 뒤에도 keep-alive 라 소켓은 ESTABLISHED 로 풀에서 쉰다. ③ client 가 먼저 close() 하면 FIN·ACK·FIN·ACK 로 끝나고, client 는 FIN_WAIT_1·FIN_WAIT_2·TIME_WAIT, server 는 CLOSE_WAIT·LAST_ACK·CLOSED 를 거친다](/assets/img/http-connection-path-loss-img1.png)

- 풀이 `GRACEFUL` 로 닫을 때(`timeToLive` 만료 등)가 이 모양이다.
  - 실측에서는 server 가 ACK 와 FIN 을 한 세그먼트로 보내 세 세그먼트로 끝났고, client 소켓은 `TIME_WAIT` 으로 남았다.
- 풀이 `IMMEDIATE` 로 닫을 때(`isStale()` 에 걸림, 요청 중 예외 등)는 **FIN 대신 RST** 를 보낸다.
  - `SO_LINGER` 를 0 으로 두고 닫기 때문이다.

`SO_LINGER` 는 `close()` 를 부른 뒤 송신 버퍼에 남은 데이터와 FIN 을 어떻게 처리할지 정하는 소켓 옵션이다.

| `SO_LINGER` | `close()` 동작 | 상대가 받는 것 | `TIME_WAIT` |
| --- | --- | --- | --- |
| 꺼짐 (기본) | 바로 돌아오고, 커널이 남은 데이터를 보낸 뒤 FIN 을 보낸다 | 데이터 → FIN | 먼저 닫은 쪽에 남는다 |
| 켜짐, N초 | 남은 데이터가 전달될 때까지 최대 N초 기다린다 | 데이터 → FIN | 남는다 |
| 켜짐, 0초 | 송신 버퍼를 버리고 바로 연결을 없앤다 (abortive close) | RST | 남지 않는다 |

```java
// org.apache.hc.core5.http.impl.io.BHttpConnectionBase — close(CloseMode) (httpcore5 5.3.3, 일부)
if (closeMode == CloseMode.IMMEDIATE) {
    try {
        // force abortive close (RST)
        baseSocket.setSoLinger(true, 0);
    } catch (final IOException ignore) {
    } finally {
        Closer.closeQuietly(baseSocket);
    }
} else {
    ...                                              // GRACEFUL: SO_LINGER 를 건드리지 않고 닫는다 → FIN
}
```

- `IMMEDIATE` 로 닫히는 커넥션은 이미 못 쓰게 된 커넥션이라, FIN 을 주고받으며 정리할 이유가 없다.
- RST 를 받은 쪽은 응답하지 않고 소켓을 바로 없앤다. 보낸 쪽도 상대의 FIN 을 기다리지 않으므로 어느 쪽에도 `TIME_WAIT` 이 남지 않는다.

### 1ms 읽기

```java
// org.apache.hc.core5.http.impl.io.BHttpConnectionBase (httpcore5 5.3.3)
private static final Timeout STALE_CHECK_TIMEOUT = Timeout.ofMilliseconds(1);

public boolean isOpen() {
    return this.socketHolderRef.get() != null;      // 클라이언트가 닫았는지만 본다
}

public boolean isStale() throws IOException {
    if (!isOpen()) {
        return true;
    }
    try {
        final int bytesRead = fillInputBuffer(STALE_CHECK_TIMEOUT);
        return bytesRead < 0;                       // EOF = 상대가 FIN 을 보냈다
    } catch (final SocketTimeoutException ex) {
        return false;                               // 1ms 동안 읽을 게 없다 = 살아 있다고 본다
    } catch (final SocketException ex) {
        return true;                                // RST 등
    }
}

private int fillInputBuffer(final Timeout timeout) throws IOException {
    final SocketHolder socketHolder = ensureOpen();
    final Socket socket = socketHolder.getSocket();
    final int oldtimeout = socket.getSoTimeout();
    try {
        socket.setSoTimeout(timeout.toMillisecondsIntBound());
        return this.inBuffer.fillBuffer(socketHolder.getInputStream());
    } finally {
        socket.setSoTimeout(oldtimeout);
    }
}
```

- classic(blocking) 클라이언트는 풀에서 쉬는 소켓을 읽는 스레드가 없다.
- 상대가 보낸 FIN·RST 는 커널이 받아 소켓 상태만 바꿔 두고, 자바 쪽은 `isStale()` 이 읽어 볼 때 처음 안다.

| 쉬는 동안 소켓에 온 것 | 1ms 읽기 결과 | `isStale()` |
| --- | --- | --- |
| 아무것도 없음 | `SocketTimeoutException` | false — 살아 있다고 본다 |
| FIN (소켓은 `CLOSE_WAIT`) | -1 (EOF) | true |
| RST | `SocketException` | true |
| 클라이언트가 이미 닫음 | 읽지 않는다 (`isOpen()` false) | true |

### FIN·RST 를 받은 커넥션을 다시 빌릴 때

> server 가 쉬는 커넥션을 먼저 끊고 2초 넘게 지나 다시 빌렸을 때, router 에서 tcpdump 로 잡은 순서다.

- (가) FIN: 톰캣의 `keepAliveTimeout` 을 0.3초로 두고, client 는 keep-alive 를 60초로 고정해 서버보다 길게 잡았다.
- (나) RST: 톰캣 자리에 0.5초 동안 요청이 없으면 `SO_LINGER` 0 으로 닫는 작은 파이썬 서버를 띄웠다.

![server 가 먼저 끊은 커넥션을 2초 넘게 쉰 뒤 다시 빌릴 때 — (가) server 가 FIN 으로 닫으면 client 는 CLOSE_WAIT, server 는 FIN_WAIT_2 로 남고, 대여 때 isStale() 이 EOF 를 읽어 stale 로 보고 RST 로 닫은 뒤 새 소켓으로 요청해 200. (나) server 가 RST 로 끊으면 양쪽 소켓이 바로 사라지고, 대여 때 isStale() 이 SocketException 으로 stale 로 보고 닫은 뒤 새 소켓으로 요청해 200](/assets/img/http-connection-path-loss-img2.png)

| | (가) server 가 FIN 으로 닫음 | (나) server 가 RST 로 끊음 |
| --- | --- | --- |
| 쉬는 동안 | server FIN → client ACK. client `CLOSE_WAIT`, server `FIN_WAIT_2` | server RST, 응답 세그먼트 없음. 양쪽 소켓이 사라진다 |
| 풀 엔트리 | available 그대로 | available 그대로 |
| 대여 | `isStale()` 이 stale 로 본다 | `isStale()` 이 stale 로 본다 |
| 옛 소켓으로 나간 것 | client RST | 없음 |
| 그다음 | 새 소켓 SYN… → 200 | 새 소켓 SYN… → 200 |

- (가) server 소켓은 FIN 을 보낸 뒤 client 의 FIN 을 기다리는 `FIN_WAIT_2` 로 남는다(server FIN 1.6초 뒤 확인).
  - client 의 RST 를 받자 바로 사라졌고, RST 에 대한 응답 세그먼트는 없었다.
  - client 가 FIN 으로 닫았다면 먼저 닫은 server 쪽에 `TIME_WAIT` 이 남았을 자리다.
- (나) client 소켓은 RST 를 받자 커널에서 바로 사라졌다(1초 뒤 `/proc/net/tcp` 에 없음).
  - 자바의 소켓 객체와 풀 엔트리는 남아 있다가 `isStale()` 이 읽어 볼 때 처음 끊긴 걸 안다.
  - 연결이 이미 없으므로 `IMMEDIATE` 로 닫아도 옛 소켓으로는 아무것도 나가지 않는다.
  - caller 로그를 DEBUG 로 켜면 `connection http-outgoing-0 is stale` 다음에 `close connection IMMEDIATE` 가 찍힌다. 1ms 읽기가 EOF 였는지 `SocketException` 이었는지는 로그에 나오지 않아, 표의 구분은 위 코드 기준이다.

## 그래도 죽은 커넥션을 쓰는 경우

---

> 서버가 클라이언트 계산보다 먼저 닫아도 FIN·RST 가 소켓에 와 있으면 `isStale()` 이 거른다. 죽은 커넥션에 요청이 실리는 건 `isStale()` 까지 놓칠 때다.

- 시각으로 거르는 설정은 서버가 클라이언트가 잡은 수명보다 먼저 닫으면 놓친다.
- 서버가 `Keep-Alive` 헤더를 안 줘서 클라이언트가 기본 3분을 잡거나, `setKeepAliveStrategy` 로 서버 값보다 길게 고정하거나, 배포·재기동, 중간 장비의 idle timeout 이 그런 경우다.
- 그래도 그것만으로 죽은 커넥션을 쓰지는 않는다. 앞의 (가)·(나) 가 바로 이 경우로, 시각 기준으로는 살아 있는 커넥션이었지만 `isStale()` 이 걸렀다.

> 뚫리는 건 아래 세 경우다.

| 경우 | 예 | `isStale()` 이 왜 못 거르나 | 요청을 실으면 |
| --- | --- | --- | --- |
| 반납 뒤 2초 안에 다시 빌린다 | 서버가 먼저 닫았는데 요청 간격이 2초보다 짧다 | 마지막 반납 뒤 `validateAfterInactivity` 가 지나지 않아 부르지 않는다 | FIN 이면 `NoHttpResponseException`, RST 면 `SocketException` (`Connection reset` 등). 바로 난다 |
| 검사 직후에 끊긴다 | 서버의 keep-alive timeout 과 거의 같은 순간에 요청을 싣는다 | 1ms 읽기를 통과한 뒤 FIN 이 온다. 검사와 요청 쓰기는 한 동작이 아니다 | 위와 같다 |
| 신호 없이 끊긴다 | 중간 장비가 연결 정보를 말없이 지움([경로 소실](#경로-소실)), 서버 호스트가 FIN 없이 사라짐 | 불러도 1ms 읽기가 `SocketTimeoutException` 으로 끝나 살아 있다고 본다 | 장비가 버리면 커널이 TCP 재전송만 반복하다 `responseTimeout` 뒤 `SocketTimeoutException: Read timed out`, RST 를 돌려주면 `Connection reset` |

요청 쓰기는 세 경우 모두 대개 성공한다. 예외는 응답을 읽을 때 소켓에 무엇이 와 있느냐로 갈린다.

- 첫째는 `validateAfterInactivity` 를 0 으로 두면 막을 수 있다. 0 이면 마지막 반납 시각과 상관없이 커넥션을 다시 쓸 때마다 `isStale()` 을 부른다.
- 둘째·셋째는 검증 설정으로 막을 수 없다.

```java
// org.apache.hc.client5.http.impl.io.PoolingHttpClientConnectionManager — lease() (httpclient5 5.4.2, 일부)
if (poolEntry.hasConnection()) {                        // 풀에 있던 커넥션을 다시 쓸 때만
    final TimeValue timeValue = resolveValidateAfterInactivity(connectionConfig);   // 없으면 2초
    if (TimeValue.isNonNegative(timeValue)) {          // 음수면 검사하지 않는다
        if (timeValue.getDuration() == 0               // 0 이면 매번
                || Deadline.calculate(poolEntry.getUpdated(), timeValue).isExpired()) {
            ...
            stale = conn.isStale();
```

대신 살아 있는 커넥션도 대여마다 1ms 읽기를 거친다. 읽을 게 없으니 1ms 를 기다려 `SocketTimeoutException` 으로 끝나고, 앞뒤로 타임아웃을 1ms 로 바꿨다가 되돌리는 `setSoTimeout` 호출이 붙는다. 실제로 얼마나 드는지는 [결과 — validateAfterInactivity 0 의 비용](#validateafterinactivity-0-의-비용)에서 쟀다.

### 반납 뒤 2초 안에 다시 빌릴 때

첫째 경우를 앞의 (가) 와 같은 조건(server 0.3초, client 60초)에서, 2초가 지나기 전에 다시 빌려 재현했다.

![server 가 FIN 으로 닫은 뒤 2초 안에 다시 빌릴 때 — 검증을 건너뛰고 CLOSE_WAIT 소켓에 요청을 쓰고, server 는 ACK 만 보내며, client 는 응답 대신 EOF 를 읽어 NoHttpResponseException 을 내고 RST 로 닫는다](/assets/img/http-connection-path-loss-img3.png)

| | 2초 안에 다시 빌림 |
| --- | --- |
| 쉬는 동안 | server FIN → client ACK. client `CLOSE_WAIT`, server `FIN_WAIT_2` |
| 대여 | `isStale()` 을 건너뛴다 |
| 그다음 세그먼트 | client 요청 → server ACK → client RST |
| 결과 | `NoHttpResponseException`, 500 |

- TCP 는 한쪽이 FIN 을 보내도 반대 방향 전송은 막지 않는다(half-close).
- `CLOSE_WAIT` 소켓에 쓴 요청도 커널 송신 버퍼에 들어가므로 `write` 는 성공한다. server 는 요청에 RST 를 보내지 않고 ACK 만 보냈다.
- 응답을 읽으면 이미 받아 둔 FIN 이 EOF 로 나온다.

![half-close 상태의 CLOSE_WAIT 소켓 — ① write(요청) 은 요청 바이트를 커널 송신 버퍼에 넣으면 성공으로 돌아오고, 커널이 열려 있는 client → server 방향으로 내보내면 server 커널은 ACK 만 돌려준다. ② read(응답) 은 커널 수신 버퍼에서 읽는데, server → client 방향은 FIN 으로 닫혀 FIN 만 있으므로 -1(EOF)이 나와 NoHttpResponseException 이 된다](/assets/img/http-connection-path-loss-img4.png)

`NoHttpResponseException` 은 응답 파서가 첫 줄을 읽다가 스트림 끝을 만나 `null` 을 돌려줄 때 던진다.

```java
// org.apache.hc.core5.http.impl.io.AbstractMessageParser — parse() (httpcore5 5.3.3, 일부)
final int i = buffer.readLine(this.headLine, inputStream);
if (i == -1) {
    return null;                                    // 한 줄도 읽기 전에 EOF
}

// org.apache.hc.core5.http.impl.io.DefaultBHttpClientConnection — receiveResponseHeader()
final ClassicHttpResponse response = this.responseParser.parse(this.inBuffer, socketHolder.getInputStream());
if (response == null) {
    throw new NoHttpResponseException("The target server failed to respond");
}
```

server 가 RST 를 돌려주고 client 가 EOF 보다 RST 를 먼저 처리하면 `Connection reset` 이 될 것으로 보이지만, 이 조합은 재현하지 않았다.

## 클라이언트가 스스로 재시도하나

---

>`HttpClientBuilder` 는 따로 설정하지 않으면 `DefaultHttpRequestRetryStrategy.INSTANCE` 로 재시도 단계를 넣고, 이 전략은 **멱등 요청을 1번 더** 보낸다.

```java
// org.apache.hc.client5.http.impl.classic.HttpClientBuilder — build() (httpclient5 5.4.2, 일부)
if (!automaticRetriesDisabled) {                      // disableAutomaticRetries() 를 부르면 true
    HttpRequestRetryStrategy retryStrategyCopy = this.retryStrategy;
    if (retryStrategyCopy == null) {
        retryStrategyCopy = DefaultHttpRequestRetryStrategy.INSTANCE;
    }
    execChainDefinition.addFirst(
            new HttpRequestRetryExec(retryStrategyCopy),
            ChainElement.RETRY.name());
}
```

```java
// org.apache.hc.client5.http.impl.DefaultHttpRequestRetryStrategy (httpclient5 5.4.2, 일부)
public DefaultHttpRequestRetryStrategy() {
    this(1, TimeValue.ofSeconds(1L));                 // 최대 1번, 1초는 429·503 응답 재시도 간격
}

public DefaultHttpRequestRetryStrategy(final int maxRetries, final TimeValue defaultRetryInterval) {
    this(maxRetries, defaultRetryInterval,
            Arrays.asList(                            // 재시도하지 않는 예외
                    InterruptedIOException.class,
                    UnknownHostException.class,
                    ConnectException.class,
                    ConnectionClosedException.class,
                    NoRouteToHostException.class,
                    SSLException.class),
            Arrays.asList(                            // 재시도하는 응답 코드
                    HttpStatus.SC_TOO_MANY_REQUESTS,
                    HttpStatus.SC_SERVICE_UNAVAILABLE));
}

public boolean retryRequest(final HttpRequest request, final IOException exception,
                            final int execCount, final HttpContext context) {
    if (execCount > this.maxRetries) {
        return false;                                 // 횟수 초과
    }
    if (this.nonRetriableIOExceptionClasses.contains(exception.getClass())) {
        return false;
    }
    for (final Class<? extends IOException> rejectException : this.nonRetriableIOExceptionClasses) {
        if (rejectException.isInstance(exception)) {
            return false;                             // 목록에 있는 예외의 하위 타입
        }
    }
    if (request instanceof CancellableDependency && ((CancellableDependency) request).isCancelled()) {
        return false;
    }
    return handleAsIdempotent(request);               // Method.isIdempotent(request.getMethod())
}
```

> 죽은 커넥션에서 나는 세 예외에 대입하면 이렇다.

| 예외 | 재시도 |
| --- | --- |
| `NoHttpResponseException` | 목록에 없다 → 멱등 메서드면 1번 더 보낸다 |
| `SocketException: Connection reset` | 목록에 없다 → 멱등 메서드면 1번 더 보낸다 |
| `SocketTimeoutException` | `InterruptedIOException` 의 하위라 하지 않는다 |

- 멱등 메서드는 `Method` enum 으로 정한다. `GET·HEAD·PUT·DELETE·OPTIONS·TRACE` 는 재시도하고 `POST·PATCH·CONNECT` 는 하지 않는다.
- 요청 본문을 다시 못 읽으면(`isRepeatable()` 이 false, `InputStreamEntity` 등) 전략에 묻지 않고 예외를 던진다.
- 재시도가 성공하면 호출한 쪽은 실패를 모른다. `Recoverable I/O exception ... caught` 가 INFO 로 남을 뿐이다.
- 재시도를 끄려면 빌더에서 `disableAutomaticRetries()` 를 부른다. 위 `build()` 의 분기대로 재시도 단계(`HttpRequestRetryExec`)가 체인에서 빠진다. 단계는 두고 횟수만 0 으로 하려면 `setRetryStrategy(new DefaultHttpRequestRetryStrategy(0, TimeValue.ZERO_MILLISECONDS))` 를 넘긴다. 둘 다 429·503 응답 재시도까지 함께 꺼진다.

재시도도 풀에서 커넥션을 빌린다. `HttpRequestRetryExec` 가 체인을 다시 타면 `ConnectExec` 가 쥔 커넥션이 없으므로 `acquireEndpoint()` 로 빌린다. 직전 커넥션을 어떻게 놓았느냐에 따라 받는 커넥션이 갈린다.

| 재시도 사유 | 직전 커넥션 | 간격 | 재시도가 받는 커넥션 |
| --- | --- | --- | --- |
| 예외 | `IMMEDIATE` 로 닫고 버린다 | 0 (`getRetryInterval` 의 default 구현) | 풀에 쉬는 다른 커넥션, 없으면 새 커넥션 |
| 429·503 응답 | 본문을 비우고 풀에 반납한다. 응답에 `Connection: close` 가 있으면 버린다 | 1초 | 반납했으면 같은 커넥션(풀이 LIFO), 버렸으면 다른 커넥션 |

> 같은 처지의 커넥션이 풀에 여럿 쉬고 있으면 예외 재시도도 죽은 커넥션을 집는다. 실측은 [C3](#재시도는-다음-커넥션이-살아-있어야-살린다-c1c3), 429·503 재시도가 집은 커넥션은 [R](#429503-재시도가-집는-커넥션-r) 에 있다.

## 경로 소실

---

> 경로 소실은 이 글에서 붙인 이름으로, 양 끝 소켓은 멀쩡한데 그 사이의 길이 이 연결을 잊어버린 상태를 말한다. <br>
> - **경로**: 클라이언트에서 서버까지 패킷이 지나가는 길이다. 그 사이에는 NAT·로드밸런서·방화벽 같은 장비가 끼어 있다. <br>
> - **소실**: 그 장비가 이 연결에 대해 들고 있던 상태를 잃는 것이다.

### 장비는 conntrack 항목으로 연결을 기억한다

- NAT·방화벽 같은 장비는 지나가는 연결마다 "이 연결이 누구와 누구 사이이고 지금 어떤 상태인지"를 한 줄씩 적어 둔다. 리눅스에서는 커널(netfilter)의 `conntrack` 테이블이 이것이고, 그 한 줄을 항목(entry)이라 부른다.
- 장비는 패킷이 올 때마다 주소·포트로 항목을 찾는다. 찾으면 이미 아는 연결의 패킷으로 보고 넘기고, NAT 라면 항목에 적힌 대로 주소를 바꾼다.

실측 중 router 에서 `conntrack -L` 로 읽은 항목 하나다.

```
tcp 6 9 ESTABLISHED src=10.81.0.10 dst=10.82.0.10 sport=33322 dport=8080   ← caller 가 보낸 모습
                    src=10.82.0.10 dst=10.82.0.2  sport=8080  dport=33322   ← upstream 이 답할 모습 (NAT 뒤)
```

| 칸 | 값 | 뜻 |
| --- | --- | --- |
| 프로토콜 | `tcp 6` | TCP (프로토콜 번호 6) |
| 남은 수명 | `9` | 초. 0 이 되면 항목이 지워진다 |
| 상태 | `ESTABLISHED` | 장비가 본 TCP 상태 |
| 원래 방향 | `src=10.81.0.10 … dport=8080` | caller 가 보낸 패킷의 주소·포트 |
| 응답 방향 | `src=10.82.0.10 dst=10.82.0.2 … dport=33322` | upstream 이 답할 때의 주소·포트. NAT 로 caller 대신 router(10.82.0.2)가 들어가 있다 |

응답이 오면 router 는 응답 방향 칸과 맞는 항목을 찾아 목적지를 원래 caller(10.81.0.10:33322)로 되돌린다. 항목이 없으면 되돌릴 근거가 없다.

![장비가 연결을 잊는 과정. client 10.81.0.10:33322, server 10.82.0.10:8080, 장비의 NAT 바깥 주소 10.82.0.2. ① 요청이 오가는 동안 장비의 conntrack 항목에는 tcp 6 9 ESTABLISHED, 원래 방향 src=10.81.0.10 dst=10.82.0.10 sport=33322 dport=8080, 응답 방향 src=10.82.0.10 dst=10.82.0.2 sport=8080 dport=33322 가 적혀 있고 수명은 패킷마다 다시 찬다. ② 패킷 없이 수명이 0 이 되면 장비가 이 항목을 말없이 지우고, client·server 에는 FIN·RST 가 가지 않아 둘 다 ESTABLISHED 로 남는다. ③ 그 뒤 10.81.0.10:33322 → 10.82.0.10:8080 요청이 오면 맞는 항목이 없어 장비는 버리거나(SocketTimeoutException), RST 를 돌려주거나(Connection reset), 새 항목을 만들어 통과시킨다](/assets/img/http-connection-path-loss-img5.png)

- 패킷이 지날 때마다 남은 수명이 그 상태의 수명 값으로 다시 채워지고, 패킷 없이 0 이 되면 항목이 지워진다. 이것이 장비의 idle timeout 이다.
  - `ESTABLISHED` 항목의 수명 값은 `nf_conntrack_tcp_timeout_established` 이고, 기본값은 432000초(5일)다. 실측에서는 10초로 줄였다.
  - 10초로 둔 router 에서 요청 직후 항목은 `9`, 4초 뒤 `5`, 다음 요청 직후 다시 `9` 였다. 요청 직후에 읽어도 10 이 아니라 9 로 찍혔다.
  - 지울 때 양 끝에 FIN 이나 RST 를 보내지 않는다. 클라이언트와 서버는 소켓을 여전히 `ESTABLISHED` 로 안다.
- 그 뒤 들어온 패킷을 어떻게 다루는지는 장비마다 다르다. 버릴 수도, RST 를 돌려줄 수도, 새 연결로 보고 통과시킬 수도 있다.

5일은 리눅스 박스를 NAT 로 쓸 때의 기본값이다. 클라우드의 NAT·LB 는 훨씬 짧게 지운다.

| 장비 | idle timeout | 지운 뒤 들어온 패킷 |
| --- | --- | --- |
| AWS NAT Gateway | 350초 (고정) | RST 를 돌려준다 |
| Azure NAT Gateway | 기본 4분 (4~120분) | — |
| Google Cloud NAT | TCP established 기본 1200초 (20분) | — |

- 클라이언트 커널의 TCP keepalive 기본값(2시간)은 이 셋보다 길다. 커넥션이 몇 분 쉬면 프로브가 나가기 전에 장비가 먼저 항목을 지운다.
- AWS 문서도 이 증상의 해결책으로 350초보다 짧은 TCP keepalive 를 켜라고 안내한다.

장비가 항목을 지운 뒤 같은 커넥션에 요청을 실어 실측했다. 환경은 [실측 환경](#실측-환경)에 있다.

| 확인한 것 | 실측 항목 |
| --- | --- |
| 장비가 패킷을 버리느냐, RST 를 돌려주느냐, 통과시키느냐에 따라 어떻게 되나 | [A1~A3](#장비가-지운-뒤의-패킷을-어떻게-다루는지가-결과를-가른다-a1a3) |
| `validateAfterInactivity` 를 0 으로 둬도 못 막는가 | [B1](#커넥션-검증으로는-못-막는다-b1) |
| 무엇으로 미리 막을 수 있나 (`evictIdleConnections`, TCP keepalive, 서버 keep-alive timeout) | [B2'·B4·B5](#미리-막는-방법은-셋이다-b2b4b5) |
| 기본 재시도가 살려 주나 | [C1~C3](#재시도는-다음-커넥션이-살아-있어야-살린다-c1c3) |

## 실측 환경

---

> caller·router·upstream 세 컨테이너로 돌렸다. router 가 경로 위의 장비 역할을 한다.

![실측 환경 구성. client 네트워크 10.81.0.0/24 의 caller(10.81.0.10)는 caller-route 로 10.82.0.0/24 를 router(10.81.0.2)로 보낸다. router 는 MASQUERADE 로 src 를 10.82.0.2 로 바꾸고 conntrack 수명을 10초로 줄였으며 loose·drop·reset 모드를 바꾼다. server 네트워크의 upstream(10.82.0.10:8080)은 caller 대역으로 가는 경로가 없어 router 에 답한다. 아래 표는 요청 한 건의 src·dst 가 구간마다 바뀌는 모습이다](/assets/img/http-connection-path-loss-img6.png)

- caller 와 upstream 을 같은 도커 네트워크에 두면 둘 사이에 손댈 장비가 없다. 도커 호스트에도 conntrack 이 있지만, 그 값을 바꾸면 다른 컨테이너도 모두 영향을 받는다.
- 그래서 둘을 다른 네트워크에 두고 그 사이 패킷이 router 컨테이너를 지나게 했다. router 는 네트워크 네임스페이스가 따로라서 그 안의 conntrack 수명과 iptables 규칙만 바꿀 수 있다.
- router 는 NAT(MASQUERADE)로 둘을 잇는다.
  - upstream 에는 caller 대역(10.81)으로 돌아가는 경로가 없다. NAT 를 거치면 upstream 이 보는 상대가 같은 대역의 router(10.82.0.2)라서 바로 답할 수 있다.
  - 경로 소실이 흔히 나는 NAT 게이트웨이와 같은 조건이 된다. 항목이 사라지면 돌아오는 패킷을 원래 연결로 되돌릴 대응이 남지 않는다.
  - drop·reset 모드는 NAT 없이 라우팅만 해도 `--ctstate INVALID` 규칙으로 재현된다. 결과가 NAT 동작에 달린 건 MASQUERADE 가 같은 포트를 다시 고른 A1 이다.

| 항목 | 값 |
| --- | --- |
| 클라이언트 | Spring Boot 3.4.4, HttpClient5 5.4.2 / httpcore5 5.3.3, JDK 21 |
| 서버 | 같은 Spring Boot 의 톰캣. `keepAliveTimeout` 60초 (`Keep-Alive: timeout=60` 을 응답에 싣는다) |
| router | alpine 3.20, iptables 1.8.10 (nf_tables), conntrack-tools 1.4.8 |
| 커널 | Docker Desktop 의 5.10.25-linuxkit |
| 공통 조건 | 장비 idle timeout 10초, 요청 사이 12초 쉼, `responseTimeout` 10초, 재시도 끔(C 제외) |

한 케이스는 이렇게 돈다.

1. caller 를 새로 띄우고 요청 1건으로 커넥션 하나를 풀에 넣는다(C3 는 동시에 2건으로 2개).
2. 12초 쉰다. 그사이 router 가 conntrack 항목을 지운다.
3. 같은 풀로 요청을 한 번 더 보내고, 결과·걸린 시간·예외를 본다.

router 가 항목을 지운 뒤 들어온 패킷을 다루는 방식은 셋으로 나눴다.

| 모드 | router 설정 | 흉내 내는 장비 |
| --- | --- | --- |
| loose | `nf_conntrack_tcp_loose=1` (리눅스 기본) | SYN 이 아닌 패킷(이미 진행 중인 연결의 ACK·데이터)으로도 항목을 새로 만든다 |
| drop | `tcp_loose=0` + `--ctstate INVALID -j DROP` | 모르는 연결의 패킷을 버린다 |
| reset | `tcp_loose=0` + `--ctstate INVALID -j REJECT --reject-with tcp-reset` | 모르는 연결에 RST 를 돌려준다 |

```bash
./scripts/run-pathloss.sh
```

<details markdown="1">
<summary>경로 소실 실측 — <code>scripts/run-pathloss.sh</code></summary>

```bash
#!/usr/bin/env bash
# 경로 소실: caller 와 upstream 사이의 router 가 conntrack 항목을 idle timeout(10초)으로 지운다.
# 지울 때 양 끝에 아무것도 보내지 않는다. 그 뒤 12초 쉬고 같은 커넥션에 요청을 싣는다.
set -e
cd "$(dirname "$0")/../docker"
DC="docker-compose -p pathloss -f docker-compose.pathloss.yml"
DEVICE_IDLE=10   # router 의 idle timeout
IDLE=12          # 요청 사이에 쉬는 시간. DEVICE_IDLE 보다 길다

router_mode() {   # <loose|drop|reset>
  docker exec pathloss_router_1 sh -c "
    iptables -F FORWARD
    sysctl -qw net.netfilter.nf_conntrack_tcp_timeout_established=$DEVICE_IDLE
    conntrack -F 2>/dev/null || true
    case $1 in
      loose) sysctl -qw net.netfilter.nf_conntrack_tcp_loose=1 ;;
      drop)  sysctl -qw net.netfilter.nf_conntrack_tcp_loose=0
             iptables -A FORWARD -m conntrack --ctstate INVALID -j DROP ;;
      reset) sysctl -qw net.netfilter.nf_conntrack_tcp_loose=0
             iptables -A FORWARD -p tcp -m conntrack --ctstate INVALID -j REJECT --reject-with tcp-reset ;;
    esac"
}

boot() {   # <env...>
  env "$@" $DC up -d --force-recreate upstream caller caller-route >/dev/null 2>&1
  # caller-route 가 server 대역 경로를 넣기 전에 요청이 나가면 router 를 안 거친다
  until docker exec pathloss_caller_1 cat /proc/net/route 2>/dev/null | grep -q 0000520A; do sleep 0.5; done
  until curl -sf -o /dev/null http://localhost:9180/actuator/health; do sleep 1; done
  until curl -sf -o /dev/null http://localhost:9181/echo; do sleep 1; done
}

sock() {   # caller 쪽 upstream:8080 소켓의 로컬 포트와 상태
  docker exec pathloss_caller_1 awk 'NR>1 && $3 ~ /:1F90$/ { split($2,a,":"); print a[2], $4 }' /proc/net/tcp \
    | while read -r port st; do
        case $st in 01) st=ESTABLISHED;; 08) st=CLOSE_WAIT;; 06) st=TIME_WAIT;; 04) st=FIN_WAIT1;; 05) st=FIN_WAIT2;; esac
        printf '%d:%s ' "0x$port" "$st"
      done
}

ct() {   # router 의 conntrack 항목 수
  docker exec pathloss_router_1 sh -c 'conntrack -L -p tcp --dport 8080 2>/dev/null | wc -l'
}

errs() {   # caller 로그에서 N 줄 이후의 예외 이름
  docker logs pathloss_caller_1 2>&1 | tail -n +"$1" \
    | grep -oE '[a-zA-Z.]+(Exception|Error): .{0,40}' | head -1 | sed 's/^.*\.\([A-Za-z]*Exception\)/\1/'
}

run() {   # <name> <mode> <env...>
  local name=$1 mode=$2; shift 2
  router_mode "$mode"
  boot "$@"
  # PAR 개를 동시에 보내 커넥션 PAR 개를 풀에 넣는다. 응답을 1초 늦춰 서로 겹치게 한다
  if [ "${PAR:-1}" -gt 1 ]; then
    for _ in $(seq "$PAR"); do curl -s -o /dev/null "http://localhost:9180/call?delayMs=1000" & done; wait
  else
    curl -s -o /dev/null http://localhost:9180/call
  fi
  local before; before=$(sock)
  sleep "$IDLE"
  local idle_sock idle_ct; idle_sock=$(sock); idle_ct=$(ct)
  local n; n=$(docker logs pathloss_caller_1 2>&1 | wc -l | tr -d ' ')
  local out; out=$(curl -s -o /dev/null -m 30 -w '%{http_code} %{time_total}' http://localhost:9180/call)
  sleep 0.5
  printf '%-34s | %-5s | 첫 요청 뒤: %-22s | %ss 쉰 뒤: %-22s conntrack=%s | 다음 요청 HTTP %s s | 뒤: %-22s | %s\n' \
    "$name" "$mode" "$before" "$IDLE" "$idle_sock" "$idle_ct" "$out" "$(sock)" "$(errs "$n")"
}

$DC up -d >/dev/null 2>&1
docker exec pathloss_router_1 sh -c 'until [ -f /ready ]; do sleep 0.5; done
  iptables -t nat -C POSTROUTING -o eth1 -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -o eth1 -j MASQUERADE'

BASE="POOL_RETRY_ENABLED=false"
run "A1. 방어 없음"                        loose $BASE
run "A2. 방어 없음"                        drop  $BASE
run "A3. 방어 없음"                        reset $BASE
run "B1. validateAfterInactivity=0"       drop  $BASE POOL_VALIDATE_AFTER_INACTIVITY_MS=0
run "B2. evictIdleConnections 5s (shared)" drop  $BASE POOL_EVICT_IDLE_MS=5000
run "B2'. evictIdleConnections 5s"         drop  $BASE POOL_EVICT_IDLE_MS=5000 POOL_MANAGER_SHARED=false
run "B3. setTcpKeepIdle(5)"                drop  $BASE POOL_TCP_KEEP_IDLE_SEC=5
run "B4. SO_KEEPALIVE + 커널 keepalive 5s"  drop  $BASE POOL_TCP_KEEP_IDLE_SEC=5 CALLER_KEEPALIVE_TIME=5 CALLER_KEEPALIVE_INTVL=5
run "B5. 서버 keepAliveTimeout 5s"          drop  $BASE KEEP_ALIVE_TIMEOUT=5000
run "C1. 재시도 켬 (기본 전략)"            drop  POOL_RETRY_ENABLED=true
run "C2. 재시도 켬 (기본 전략)"            reset POOL_RETRY_ENABLED=true
PAR=2 run "C3. 재시도 켬, 쉬는 커넥션 2개"  reset POOL_RETRY_ENABLED=true

# R. 429·503 응답 재시도가 어느 커넥션을 집는지. 경로 소실 없이, 커넥션 2개를 풀에 넣고 바로 상태 코드를 받는다
status_retry() {   # <status>
  router_mode loose
  boot POOL_RETRY_ENABLED=true LOGGING_LEVEL_ORG_APACHE_HC=DEBUG
  for _ in 1 2; do curl -s -o /dev/null "http://localhost:9180/call?delayMs=1000" & done; wait
  local n; n=$(docker logs pathloss_caller_1 2>&1 | wc -l | tr -d ' ')
  curl -s -o /dev/null "http://localhost:9180/call?status=$1"
  printf 'R. %s 재시도 | ' "$1"
  docker logs pathloss_caller_1 2>&1 | tail -n +"$((n + 1))" \
    | grep -oE 'http-outgoing-[0-9]+ << "HTTP/1.1 [0-9]+|releasing valid endpoint|discarding endpoint' \
    | sed 's/ << "HTTP\/1.1 / /' | paste -sd ' ' -
}
status_retry 429
status_retry 503
```

</details>

## 결과

---

> 장비가 버리는 경우(drop) 방어가 없으면 요청은 `responseTimeout` 10초를 다 채우고 실패했다. <br> 미리 막은 건 evict(스레드가 실제로 돌 때), 커널 TCP keepalive, 장비보다 짧은 서버 keepAliveTimeout 셋이었다.

| # | 장비 | 클라이언트 쪽 조건 | 12초 쉰 뒤 caller 소켓 / router conntrack 항목 수 | 다음 요청 |
| --- | --- | --- | --- | --- |
| A1 | loose | 방어 없음 | `ESTABLISHED` / 0 | **200**, 0.01초. 같은 소켓 그대로 |
| A2 | drop | 방어 없음 | `ESTABLISHED` / 0 | **500**, 10.05초. `SocketTimeoutException: Read timed out` |
| A3 | reset | 방어 없음 | `ESTABLISHED` / 0 | **500**, 0.07초. `SocketException: Connection reset` |
| B1 | drop | `validateAfterInactivity=0` | `ESTABLISHED` / 0 | 500, 10.06초. `SocketTimeoutException` |
| B2 | drop | `evictIdleConnections(5s)` + `setConnectionManagerShared(true)` | `ESTABLISHED` / 0 | 500, 10.05초. `SocketTimeoutException` |
| B2' | drop | `evictIdleConnections(5s)` | `TIME_WAIT` / 1 | **200**. 새 커넥션 |
| B3 | drop | `setSoKeepAlive(true)` + `setTcpKeepIdle(5)` | `ESTABLISHED` / 0 | 500, 10.06초. `SocketTimeoutException` |
| B4 | drop | B3 + 커널 `tcp_keepalive_time=5` | `ESTABLISHED` / **1** | **200**. 같은 소켓 그대로 |
| B5 | drop | 서버 `keepAliveTimeout` 5초, 검증은 기본 2초 | `CLOSE_WAIT` / 1 | **200**. 새 커넥션 |
| C1 | drop | 재시도 켬 (기본 전략) | `ESTABLISHED` / 0 | 500, 10.06초. `SocketTimeoutException` |
| C2 | reset | 재시도 켬 (기본 전략) | `ESTABLISHED` / 0 | **200**. 새 커넥션 |
| C3 | reset | C2 + 쉬는 커넥션 2개 | `ESTABLISHED` ×2 / 0 | 500, 0.07초. `Connection reset` 두 번 |

- router conntrack 항목 수는 다음 요청 직전에 router 에서 `conntrack -L -p tcp --dport 8080` 으로 센, upstream 8080 포트로 가는 TCP 항목의 수다.
  - 0 이면 장비가 이 연결을 잊은 것이다(경로 소실).
  - B4 는 keepalive 프로브가 수명을 계속 채워 항목이 남았다.
  - B2'·B5 는 쉬는 동안 커넥션이 FIN 으로 닫히기 시작했다. conntrack 은 닫히는 단계의 항목에 established 수명(10초) 대신 상태별 수명(`nf_conntrack_tcp_timeout_time_wait` 120초 등)을 쓰므로 항목이 남아 있었다.

- A2 에서 서버 쪽 소켓도 읽어 봤다. 12초 쉰 뒤 caller 와 upstream 의 소켓은 둘 다 `ESTABLISHED`(`/proc/net/tcp` 상태 `01`)였고, router 의 conntrack 에는 항목이 없었다.

### 장비가 지운 뒤의 패킷을 어떻게 다루는지가 결과를 가른다 (A1~A3)

- **loose (A1)** — 문제가 드러나지 않는다. 리눅스 conntrack 은 기본값(`nf_conntrack_tcp_loose=1`)에서 SYN 이 아닌 패킷으로도 항목을 새로 만든다. 항목이 지워진 뒤 들어온 요청 패킷(ACK·데이터)을 이미 진행 중인 연결의 것으로 보고 받아 준다(커널 문서: "picking up already established connections"). MASQUERADE 가 원래 포트를 그대로 다시 골라 서버가 보는 4-튜플이 같았고, 같은 소켓으로 응답이 왔다.
- **drop (A2)** — 요청을 보낸 뒤 ACK 가 오지 않아 caller 커널이 TCP 재전송을 반복한다. router 에서 tcpdump 로 보면 같은 208바이트 요청이 0.2·0.4·0.8·1.6초 간격으로 다시 나가고 모두 버려졌다(`DROP` 카운터 8). 실패는 `responseTimeout` 이 끝내 준다.
  - TCP 재전송: TCP 는 보낸 바이트마다 상대의 ACK 를 기다린다. 재전송 타이머(RTO) 안에 ACK 가 없으면 잃어버린 것으로 보고 같은 바이트를 다시 보내고, 보낼 때마다 RTO 를 두 배로 늘린다. 0.2·0.4·0.8·1.6초 간격이 이것이다.
  - 커널이 하는 일이라 HttpClient 의 재시도(멱등 요청 1번, A2 에서는 꺼 둠)와 다르다. 애플리케이션은 요청을 한 번 썼을 뿐이다.
  - 커널은 `tcp_retries2`(caller 기본 15) 번까지 재전송하고 연결을 끊는데, 이는 십수 분이 걸려 10초 `responseTimeout` 이 먼저 끝난다.
- **reset (A3)** — RST 가 바로 돌아와서 0.07초 만에 `Connection reset` 으로 끝난다.

> A1 은 포트를 그대로 다시 고를 수 있는 리눅스 router 하나의 결과다. 다른 포트를 고르는 NAT 라면 서버는 모르는 연결의 패킷을 받아 RST 를 돌려줄 것으로 보이지만, 직접 재현하지는 않았다.

### 커넥션 검증으로는 못 막는다 (B1)

`validateAfterInactivity=0` 이면 대여할 때마다 `isStale()` 을 부른다. 경로 소실에서는 FIN 도 RST 도 오지 않아 1ms 읽기가 타임아웃으로 끝나고, 검사를 통과한 커넥션에 요청이 실렸다.

### 미리 막는 방법은 셋이다 (B2'·B4·B5)

장비가 항목을 지우기 전에 셋 중 하나가 일어나면 된다.

| 방법 | 원리 | 실측 |
| --- | --- | --- |
| `evictIdleConnections(t)` | 풀이 쉬는 커넥션을 장비보다 먼저 닫는다 | B2' — 12초 시점에 소켓은 `TIME_WAIT`, 새 커넥션으로 200 |
| TCP keepalive | 쉬는 커넥션에도 프로브가 오가 장비의 항목을 살려 둔다 | B4 — 항목이 남아 같은 소켓으로 200 |
| 서버 `keepAliveTimeout` < 장비 idle timeout | 서버의 FIN 이 장비를 지나 클라이언트에 닿고, 검증이 걸러낸다 | B5 — 소켓은 `CLOSE_WAIT`, 새 커넥션으로 200 |

TCP keepalive 의 프로브는 커널이 쉬는 커넥션에 보내는 "살아 있나" 확인 패킷이다.

- 소켓에 `SO_KEEPALIVE` 가 켜져 있으면, 커넥션이 `tcp_keepalive_time` 동안 조용할 때 커널이 데이터 없는(length 0) ACK 를 보낸다. 상대 커널은 ACK 로 답한다.
- 답이 없으면 `tcp_keepalive_intvl` 간격으로 `tcp_keepalive_probes` 번 더 보내고, 끝내 답이 없으면 연결을 끊는다.
- 애플리케이션은 관여하지 않는다. HTTP 요청도 아니어서 서버 애플리케이션에는 보이지 않는다.
- 프로브와 그 답도 장비를 지나가므로 conntrack 항목의 수명이 다시 찬다. B4 가 막은 원리다.

![TCP keepalive 설정과 프로브 흐름. tcp_keepalive_time 은 조용한 시간이 이만큼 되면 첫 프로브를 보내는 값으로 리눅스 기본 7200초(2시간), B4 실측 5초. tcp_keepalive_intvl 은 답이 없을 때 다음 프로브까지의 간격으로 기본 75초, B4 5초. tcp_keepalive_probes 는 답 없이 보낼 프로브 수로 기본 9. (가) 상대가 답하면 조용해질 때마다 caller 커널이 데이터 없는 ACK 프로브를 보내고 upstream 이 ACK 로 답하며, 둘 다 router 를 지나가므로 router 의 conntrack 수명이 다시 찬다. (나) 답이 없으면 intvl 간격으로 다시 보내다가 9번째에도 답이 없으면 caller 커널이 연결을 끊는다. 기본값이면 첫 프로브까지 2시간, 끊기까지 7875초](/assets/img/http-connection-path-loss-img7.png)

B4 조건(`tcp_keepalive_time=5`, `tcp_keepalive_intvl=5`)에서 요청 한 건 뒤 router 에서 잡은 패킷이다.

```
0.000  caller → upstream  [P.] length 208   GET /echo ...       ← 요청
0.008  upstream → caller  [P.] length 199   HTTP/1.1 200        ← 응답
0.008  caller → upstream  [.]  ack 200, length 0
5.184  caller → upstream  [.]  ack 200, length 0                ← 프로브 (5초 조용한 뒤)
5.184  upstream → caller  [.]  ack 209, length 0                ← 답
10.305 caller → upstream  [.]  ack 200, length 0                ← 프로브
10.305 upstream → caller  [.]  ack 209, length 0                ← 답
```

각 방법에는 걸리는 조건이 있었다.

**evict 는 스레드가 떠야 돈다 (B2).** `HttpClientBuilder` 는 `setConnectionManagerShared(true)` 면 `IdleConnectionEvictor` 를 만들지 않는다. B2 는 `evictIdleConnections(5s)` 를 줬는데도 소켓이 12초 뒤까지 `ESTABLISHED` 로 남아 A2 와 같이 실패했다. 또 evict 스레드는 `t` 마다 깨어 `updated + t` 가 지난 엔트리를 닫으므로, 엔트리는 최대 `2t` 가까이 쉴 수 있다. 장비 idle timeout 보다 `2t` 를 짧게 잡아야 한다.

**HttpClient5 classic 은 `setTcpKeepIdle` 을 소켓에 넣지 않는다 (B3).** `SocketConfig` 에 `setTcpKeepIdle`·`setTcpKeepInterval`·`setTcpKeepCount` 가 있지만, B3 의 소켓은 keepalive 타이머가 켜진 채로 남은 시간이 약 7200초였다(`/proc/net/tcp` 의 timer 필드 `02:000AFB95`). 커널 기본값 `tcp_keepalive_time` 2시간이 그대로 걸린 것이다.

```java
// org.apache.hc.client5.http.impl.io.DefaultHttpClientConnectionOperator#connect (5.4.2) 에서 소켓에 넣는 값
sock.setReuseAddress(socketConfig.isSoReuseAddress());
sock.setTcpNoDelay(socketConfig.isTcpNoDelay());
sock.setKeepAlive(socketConfig.isSoKeepAlive());     // 켜고 끄기만 한다
// rcvBuf, sndBuf, linger ... getTcpKeepIdle / Interval / Count 는 읽지 않는다
```

httpclient5-5.4.2 jar 전체에서 `getTcpKeepIdle` 을 부르는 클래스는 없다. httpcore5-5.3.3 안에서는 `HttpRequester`·`HttpServer`(httpcore 자체의 클래식 부트스트랩)와 `SingleCoreIOReactor`(async)만 이 값을 쓴다. B4 는 caller 컨테이너의 네트워크 네임스페이스에 `net.ipv4.tcp_keepalive_time=5`, `tcp_keepalive_intvl=5` 를 넣어 막았다. 커널 값은 그 네임스페이스(또는 호스트)의 모든 소켓에 걸린다.

> 소켓 하나에만 걸려면 `ExtendedSocketOptions.TCP_KEEPIDLE` 을 직접 넣는 소켓 팩토리(`DetachedSocketFactory`)를 `DefaultHttpClientConnectionOperator` 에 넘기는 방법이 있어 보인다. 직접 재현하지는 않았다.

**서버 쪽 값은 클라이언트가 고를 수 없다 (B5).** 서버가 장비보다 먼저 FIN 을 보내면 장비의 항목이 살아 있는 동안 FIN 이 지나가고, 경로 소실이 아니라 보통의 stale 이 된다. 클라이언트는 기본 검증(2초)으로 걸러냈다.

### 재시도는 다음 커넥션이 살아 있어야 살린다 (C1~C3)

기본 재시도 전략은 `SocketTimeoutException` 을 재시도하지 않고 `Connection reset` 은 멱등 요청이면 1번 더 보낸다. 실측도 그대로 갈렸다.

- C1 (drop) — `SocketTimeoutException` 이라 재시도하지 않고 10초를 다 쓰고 실패했다.
- C2 (reset) — GET 을 새 커넥션으로 한 번 더 보냈고 200 이 났다.
- C3 (reset) — 첫 요청을 동시에 2건 보내 커넥션 2개를 풀에 넣고 12초 쉬었다. 첫 시도는 `http-outgoing-0` 에서 `Connection reset` 이 났고, 재시도는 풀에 남은 `http-outgoing-1` 을 집어 또 `Connection reset` 이 났다. 재시도는 1번뿐이라 500 으로 끝났다.

### 429·503 재시도가 집는 커넥션 (R)

경로 소실 없이 커넥션 2개를 풀에 넣고, 곧바로 429·503 을 돌려받게 했다. 어느 커넥션으로 나갔는지는 DEBUG 로그의 `http-outgoing-N` 으로 봤다.

| 응답 | 첫 시도 | 재시도 (1초 뒤) |
| --- | --- | --- |
| 429 | `http-outgoing-1`, 풀에 반납 (`releasing valid endpoint`) | `http-outgoing-1` — 같은 커넥션 |
| 503 | `http-outgoing-1`, 버림 (`discarding endpoint`) | `http-outgoing-0` — 풀에 쉬던 다른 커넥션 |

톰캣(10.1.39)은 503 응답에 `Connection: close` 를 붙여서, 클라이언트가 커넥션을 반납하지 않고 버렸다. 429 에는 붙이지 않았다.

### validateAfterInactivity 0 의 비용

`validateAfterInactivity` 를 0 으로 두면 커넥션을 다시 쓸 때마다 `isStale()` 이 돌고, 살아 있는 커넥션은 1ms 를 다 기다린다.

경로 소실 실측과 별개로, router 없이 같은 도커 네트워크에 둔 톰캣(위 upstream 과 같은 앱)에 커넥션 하나로 요청을 5,000번 순서대로 보냈다. JDK 21, Docker Desktop 5.10.25-linuxkit, JIT 워밍업 한 바퀴 뒤 값이다. 커넥션 팩토리를 감싸 `isStale()` 호출 수와 걸린 시간을 셌다.

| `validateAfterInactivity` | `isStale()` 호출 | 대여 한 번 (평균) | GET 한 번 (평균) |
| --- | --- | --- | --- |
| 음수 (검사 안 함) | 0번 | 0.05ms | 0.65ms |
| 2초 (기본) | 0번 | 0.06ms | 0.56ms |
| 0 | 4,950번 | 1.55ms | 2.34ms |

- `isStale()` 한 번에 평균 1.47ms 가 들었다. 1ms 타임아웃을 다 기다린 위에 0.47ms 가 더 붙었다. 나머지를 무엇이 차지하는지는 나눠 재지 않았다.
- 요청 간격이 2초보다 짧으니 기본값에서는 한 번도 부르지 않았다.
- 0 일 때 5,000번이 아니라 4,950번인 건 톰캣이 커넥션 하나로 100개 요청을 받으면 닫기 때문이다(`server.tomcat.max-keep-alive-requests` 100, 톰캣 기본값과 같다). 새로 만든 커넥션은 검사하지 않는다.
- 로컬처럼 응답이 1ms 안팎이면 요청마다 1.5ms 가 더해져 몇 배로 느려진다. 응답이 수십 ms 걸리는 호출이면 비중은 그만큼 작다.

<details markdown="1">
<summary>측정 코드 (Bench.java)</summary>

```java
import java.lang.reflect.*;
import java.util.*;
import java.util.concurrent.atomic.AtomicLong;
import org.apache.hc.client5.http.HttpRoute;
import org.apache.hc.client5.http.classic.methods.HttpGet;
import org.apache.hc.client5.http.config.ConnectionConfig;
import org.apache.hc.client5.http.impl.classic.*;
import org.apache.hc.client5.http.impl.io.*;
import org.apache.hc.client5.http.io.*;
import org.apache.hc.core5.http.HttpHost;
import org.apache.hc.core5.http.io.HttpConnectionFactory;
import org.apache.hc.core5.http.io.entity.EntityUtils;
import org.apache.hc.core5.http.protocol.HttpCoreContext;
import org.apache.hc.core5.util.*;

// validateAfterInactivity 값에 따라 대여 한 번에 드는 시간과 isStale() 호출 수
public class Bench {
    static final AtomicLong staleCalls = new AtomicLong(), staleNanos = new AtomicLong();

    static PoolingHttpClientConnectionManager manager(long validateMs) {
        var base = ManagedHttpClientConnectionFactory.INSTANCE;
        HttpConnectionFactory<ManagedHttpClientConnection> counting = socket -> {
            ManagedHttpClientConnection real = base.createConnection(socket);
            return (ManagedHttpClientConnection) Proxy.newProxyInstance(Bench.class.getClassLoader(),
                new Class<?>[]{ManagedHttpClientConnection.class}, (p, m, a) -> {
                    long t0 = m.getName().equals("isStale") ? System.nanoTime() : 0;
                    try { return m.invoke(real, a); }
                    catch (InvocationTargetException e) { throw e.getCause(); }
                    finally { if (t0 != 0) { staleNanos.addAndGet(System.nanoTime() - t0); staleCalls.incrementAndGet(); } }
                });
        };
        return PoolingHttpClientConnectionManagerBuilder.create()
            .setConnectionFactory(counting)
            .setDefaultConnectionConfig(ConnectionConfig.custom()
                .setValidateAfterInactivity(TimeValue.ofMilliseconds(validateMs)).build())
            .build();
    }

    static String pct(long[] ns) {
        Arrays.sort(ns);
        double avg = Arrays.stream(ns).average().orElse(0) / 1000;
        return String.format("평균 %7.1fµs  p50 %7.1fµs  p99 %7.1fµs", avg, ns[ns.length / 2] / 1000.0, ns[ns.length * 99 / 100] / 1000.0);
    }

    public static void main(String[] args) throws Exception {
        HttpHost host = HttpHost.create(args[0]);
        int n = Integer.parseInt(args[1]);
        long[] cases = {-1, 2000, 0};
        String[] names = {"꺼짐(-1)", "2초(기본)", "0"};
        for (int round = 0; round < 2; round++) {   // 첫 바퀴는 JIT 워밍업
            System.out.println(round == 0 ? "--- 워밍업" : "--- 측정");
            for (int c = 0; c < cases.length; c++) {
                // 1) 대여·반납만 반복
                try (var cm = manager(cases[c])) {
                    var route = new HttpRoute(host);
                    var ep = cm.lease("x", route, null).get(Timeout.ofSeconds(5));
                    cm.connect(ep, TimeValue.ofSeconds(5), HttpCoreContext.create());
                    cm.release(ep, null, TimeValue.ofMinutes(5));
                    staleCalls.set(0); staleNanos.set(0);
                    long[] ns = new long[n];
                    for (int i = 0; i < n; i++) {
                        long t0 = System.nanoTime();
                        ep = cm.lease("x", route, null).get(Timeout.ofSeconds(5));
                        ns[i] = System.nanoTime() - t0;
                        cm.release(ep, null, TimeValue.ofMinutes(5));
                    }
                    if (round == 1) System.out.printf("대여만  %-9s %s  isStale %d번, 한 번에 평균 %.1fµs%n", names[c], pct(ns),
                        staleCalls.get(), staleCalls.get() == 0 ? 0 : staleNanos.get() / 1000.0 / staleCalls.get());
                }
                // 2) 실제 GET 을 순서대로
                try (var cm = manager(cases[c]); var client = HttpClients.custom().setConnectionManager(cm).build()) {
                    var get = new HttpGet(args[0] + "/echo");
                    client.execute(get, r -> EntityUtils.toString(r.getEntity()));
                    staleCalls.set(0); staleNanos.set(0);
                    long[] ns = new long[n];
                    for (int i = 0; i < n; i++) {
                        long t0 = System.nanoTime();
                        client.execute(get, r -> EntityUtils.toString(r.getEntity()));
                        ns[i] = System.nanoTime() - t0;
                    }
                    if (round == 1) System.out.printf("GET    %-9s %s  isStale %d번%n", names[c], pct(ns), staleCalls.get());
                }
            }
        }
    }
}
```

</details>

## 롤링 배포: LB 와 WAS 사이 커넥션

---

> LB 뒤 WAS 두 대 중 한 대를 내릴 때, LB 가 그 WAS 와 들고 있던 keepalive 커넥션에 무엇이 오가고 요청이 어떻게 되는지 쟀다.

| 항목 | 값 |
| --- | --- |
| LB | nginx 1.27 (alpine). 라운드로빈, `keepalive 8`, `proxy_next_upstream` 기본값(`error timeout`) |
| WAS | was1·was2. 앞 절과 같은 Spring Boot 3.4.4 / Tomcat 10.1.39. Boot 3.4 부터 `server.shutdown` 기본값이 `graceful` 이다 |
| 네트워크 | 한 도커 네트워크. LB 10.83.0.2, was1 10.83.0.11, was2 10.83.0.12 |

```nginx
upstream was {
  server 10.83.0.11:8080;
  server 10.83.0.12:8080;
  keepalive 8;                       # WAS 쪽 쉬는 커넥션을 풀로 둔다
}
location / {
  proxy_pass http://was;
  proxy_http_version 1.1;
  proxy_set_header Connection "";    # 비워야 WAS 쪽 커넥션을 다시 쓴다
}
```

- 케이스마다 새로 띄우고, LB 가 WAS 마다 쉬는 커넥션을 하나씩 들게 한 뒤 was1 을 내렸다(t0).
- "처리 중" 케이스는 t0 0.5초 전에 3초 걸리는 요청 두 개를 동시에 보내 WAS 마다 하나씩 들어가 있게 했다.
- t0 부터 0.5초마다 LB 로 요청을 10번 보냈다(`curl -m 10`). 패킷은 LB 에서 tcpdump 로 잡았다.

| 케이스 | 내리는 방법 |
| --- | --- |
| G | `docker stop` (SIGTERM). graceful |
| I | `docker stop`. `SERVER_SHUTDOWN=immediate` |
| K | `docker kill` (SIGKILL) |
| P | 컨테이너는 두고 java 프로세스만 죽인다. 같은 서버에서 프로세스만 재시작하는 배포 |

G·I·K 는 컨테이너가 사라지면서 was1 의 IP 도 함께 사라진다. P 는 IP 가 남는다.

![롤링 배포 실측 요약. ① 쉬던 keepalive 커넥션: 다섯 종료 방법 모두 was1 이 +0.27초에 FIN 을 보내고 nginx 가 같은 시각 FIN 으로 닫아 풀에서 뺀다. 다음 요청은 새 SYN 으로 나간다. ② 새 연결: IP 가 남으면 RST(Connection refused)를 받아 was2 로 넘겨 0.005초에 200, IP 가 사라지면 SYN 이 1·2·4초 간격으로 재전송되며 답이 없어 클라이언트가 10초에 끊는다(499). ③ 처리 중 요청: graceful 은 응답 뒤 FIN, immediate·SIGKILL 은 응답 없이 FIN 이라 nginx 가 502 를 받고 was2 로 다시 보내 3.8초에 200](/assets/img/http-connection-path-loss-img8.png)

### 서버는 기존 커넥션에 FIN 을 보낸다

| 케이스 | 쉬는 keepalive 커넥션 | 처리 중이던 커넥션 | 처리 중이던 요청의 결과 |
| --- | --- | --- | --- |
| G | +0.27초 FIN | 응답(+2.50초)을 보낸 직후 FIN | was1 이 200 |
| I | +0.27초 FIN | 응답 없이 +0.27초 FIN | was1 502 → was2 로 넘겨 200 (3.78초) |
| K | +0.28초 FIN | 응답 없이 +0.30초 FIN | was1 502 → was2 로 넘겨 200 (3.79초) |
| P (SIGTERM) | +0.36초 FIN | 응답을 보낸 직후 FIN | was1 이 200 |
| P (SIGKILL) | | 응답 없이 +0.33초 FIN | was1 502 → was2 로 넘겨 200 (3.84초) |

- 다섯 방법 모두 기존 커넥션에는 FIN 만 갔다. RST 는 없었다.
- SIGKILL 로 죽여도 FIN 이 간다. 프로세스가 죽으면 커널이 남은 소켓을 닫는다. 결론의 "재시도에 맡겨도 되나" 에 적은 `docker kill` 실험과 같다.
- graceful 은 처리 중 요청을 끝까지 처리하고 닫았다. immediate·SIGKILL 은 응답 없이 닫았고, nginx 가 이를 502 로 보고 was2 로 다시 보냈다. GET 이라서 다시 보낸 것이다. nginx 는 POST 같은 비멱등 요청은 기본으로 다음 서버에 넘기지 않는다고 문서에 적혀 있다(돌려 보지 않았다).

### LB 는 FIN 받은 커넥션을 다시 쓰지 않았다

```text
+0.271  was1 > LB  [F.]    was1 이 쉬는 커넥션을 닫는다
+0.271  LB > was1  [F.]    같은 시각 nginx 도 닫는다
+0.271  was1 > LB  [.]
+0.582  LB > was1  [S]     다음 was1 몫 요청은 새 연결로 나간다
```

- nginx 는 FIN 을 받은 그 시각에 커넥션을 닫았고, 이후 was1 몫 요청은 모두 새 SYN 으로 나갔다.
- HttpClient 는 다르다. 쉬는 커넥션에 온 FIN 을 바로 보지 않고, 반납 뒤 2초 안이면 그대로 다시 쓴다([반납 뒤 2초 안에 다시 빌릴 때](#반납-뒤-2초-안에-다시-빌릴-때)).

### 실패는 새 연결에서 났다

| 상황 | was1 로 보낸 SYN | 클라이언트가 본 결과 |
| --- | --- | --- |
| P. IP 가 남음 | +0.57~0.60초에 RST (`Connection refused`) | nginx 가 was2 로 넘겨 200. 0.005초 |
| G·I·K. IP 가 사라짐 | 응답 없음. 1·2·4초 간격으로 SYN 재전송 | 요청 3~4건이 10초 타임아웃으로 실패 |

- IP 가 사라진 경우 SYN 에 아무 답이 없었다. nginx 는 `proxy_connect_timeout` 기본 60초까지 기다리는데, 그 전에 클라이언트가 10초에 끊었다. nginx 는 이를 499 로 남기고 was1 의 실패로 세지 않아 계속 was1 에도 요청을 나눴다.
- t0 에서 33~44초 뒤부터는 `connect() failed (113: Host is unreachable)` 가 3~4초 만에 났다. 그제서야 nginx 는 was1 을 잠시 빼고(`upstream server temporarily disabled`) was2 로 넘겼다. 그 전 30초 남짓 답이 없던 이유는 LB 에 남은 ARP 항목으로 추정한다(확인하지 않았다).
- graceful 종료 중(G 의 처리 중 케이스)에도 새 연결은 +0.57초에 RST 를 받았다. 처리 중 요청을 마치는 동안 새 연결은 받지 않는다.

> 롤링 배포에서 LB 가 끊긴 커넥션을 다시 쓰지는 않았다. 실패는 내린 서버로 새로 연결할 때와, graceful 이 아닌 종료로 처리 중 요청이 끊길 때 났다. LB 에서 먼저 빼고(drain) graceful 로 내리면 둘 다 피한다.

<details markdown="1">
<summary>실측 스크립트 (run-rolling.sh)</summary>

```bash
#!/usr/bin/env bash
# 사용법: run-rolling.sh
#
# LB(nginx) 뒤 WAS 두 대 중 was1 을 내린다. 롤링 배포의 한 단계.
# LB 가 was1 과 들고 있던 keepalive 커넥션에 무슨 패킷이 오가는지(FIN·RST), 내린 뒤 LB 가 그 커넥션에 요청을 싣는지 본다.
set -e
cd "$(dirname "$0")/../docker"
DC="docker-compose -p rolling -f docker-compose.rolling.yml"
LB=http://localhost:9190

now() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }

boot() {   # <env...>
  env "$@" $DC up -d --force-recreate >/dev/null 2>&1
  docker exec rolling_lb_1 sh -c 'apk add --no-cache tcpdump iproute2 >/dev/null'
  until curl -sf -o /dev/null http://localhost:9190/echo; do sleep 1; done
  until [ "$(docker exec rolling_lb_1 ss -tnH state established '( dport = :8080 )' | wc -l)" -ge 2 ]; do
    curl -s -o /dev/null $LB/echo
  done
}

down() {   # <stop|kill|proc-term|proc-kill>  stop·kill 은 컨테이너째, proc-* 는 java 프로세스만
  case $1 in
    stop|kill) docker "$1" rolling_was1_1 >/dev/null ;;
    proc-term) docker exec rolling_was1_1 sh -c 'kill -TERM $(pgrep java); while pgrep java >/dev/null; do sleep 0.05; done' ;;
    proc-kill) docker exec rolling_was1_1 sh -c 'kill -KILL $(pgrep java)' ;;
  esac
}

# <name> <stop|kill|proc-term|proc-kill> <inflight 0|1> <env...>
run() {
  local name=$1 how=$2 inflight=$3; shift 3
  [ -n "$ONLY" ] && [[ "$name" != $ONLY* ]] && return 0
  echo "=== $name"
  boot "$@"
  docker exec rolling_lb_1 ss -tnH '( dport = :8080 )' | sed 's/^/  내리기 전 LB 소켓: /'
  docker exec -d rolling_lb_1 sh -c 'tcpdump -i eth0 -nn -tt -l "tcp port 8080 and host 10.83.0.11" > /tmp/cap 2>/dev/null'
  sleep 1
  local n; n=$(docker logs rolling_lb_1 2>&1 | wc -l | tr -d ' ')
  # 처리 중인 요청: 3초 걸리는 요청 두 개를 동시에 보내 WAS 마다 하나씩 들어가게 한다
  if [ "$inflight" = 1 ]; then
    for _ in 1 2; do (curl -s -o /dev/null -w "  처리 중이던 요청: HTTP %{http_code} %{time_total}s\n" "$LB/echo?delayMs=3000") & done
    sleep 0.5
  fi
  local t0; t0=$(now)
  echo "  t0=$t0 was1 $how"
  ( s=$(now); down "$how"; echo "  $how 끝: +$(echo "$(now) - $s" | bc)s" ) &
  # 내리는 동안·내린 뒤 0.5초마다 LB 로 요청
  for i in $(seq 10); do
    curl -s -o /dev/null -m 10 -w "  +%{time_starttransfer} 요청 $i: HTTP %{http_code} %{time_total}s\n" $LB/echo | sed "s/+[0-9.]*/+$(echo "$(now) - $t0" | bc)/"
    sleep 0.5
  done
  wait
  sleep 1
  docker exec rolling_lb_1 sh -c 'pkill tcpdump; sleep 0.3; cat /tmp/cap' \
    | awk -v t0="$t0" '/ IP / { $1 = sprintf("+%.3f", $1 - t0); print "  pkt " $0 }' | cut -c1-110
  docker exec rolling_lb_1 ss -tnH '( dport = :8080 )' | sed 's/^/  내린 뒤 LB 소켓: /'
  docker logs rolling_lb_1 2>&1 | tail -n +"$((n + 1))" | grep -E '"GET|\[error\]|\[warn\]' | grep -v prematurely \
    | sed -E 's/^.*\[(error|warn)\] [0-9#*: ]+/[\1] /; s/, client.*upstream: "([^"]*)".*/ (\1)/' \
    | awk -v t0="$t0" '/^[0-9]+\.[0-9]+ / { $1 = sprintf("+%.3f", $1 - t0) } { print "  lb " $0 }' | cut -c1-160
  docker logs rolling_was1_1 2>&1 | grep -iE 'graceful|shutdown' | sed 's/^.*INFO [0-9]* --- \[[^]]*\] [^ ]* *: /  was1: /'
}

run "G1. graceful, 쉬는 커넥션만"      stop 0
run "G2. graceful, 처리 중 요청 있음"  stop 1
run "I1. immediate, 쉬는 커넥션만"     stop 0 SERVER_SHUTDOWN=immediate
run "I2. immediate, 처리 중 요청 있음" stop 1 SERVER_SHUTDOWN=immediate
run "K1. SIGKILL, 쉬는 커넥션만"       kill 0
run "K2. SIGKILL, 처리 중 요청 있음"   kill 1
PROC="WAS_CMD=java -jar /app/app.jar; sleep infinity"
run "P1. java 만 SIGTERM, 쉬는 커넥션만"  proc-term 0 "$PROC"
run "P2. java 만 SIGTERM, 처리 중"       proc-term 1 "$PROC"
run "P3. java 만 SIGKILL, 처리 중"       proc-kill 1 "$PROC"
```

</details>

## 결론

---

> 커넥션을 재사용하면(HTTP keep-alive) 새로 맺을 때는 없던 실패가 생긴다. 풀에서 쉬던 커넥션이 이미 죽어 있을 수 있기 때문이다.

### 재사용해서 생기는 예외

| 예외 | 원인 | 실패까지 | 기본 재시도 |
| --- | --- | --- | --- |
| `NoHttpResponseException` | 서버가 FIN 으로 닫은 커넥션을 반납 뒤 2초 안에 다시 씀 | 바로 | 멱등이면 1번 |
| `SocketException: Connection reset` | 서버나 장비가 RST 를 돌려줌 | 바로 | 멱등이면 1번 |
| `SocketTimeoutException: Read timed out` | 장비가 패킷을 버리는 경로 소실 | `responseTimeout` 전부 | 안 함 |

`SocketTimeoutException` 은 느린 서버와 겉모습이 같다. 요청이 서버에 닿지도 않았는데 `responseTimeout` 을 다 쓰고 실패한다.

### 재시도에 맡겨도 되나

- 기본 재시도는 멱등 메서드이고 본문을 다시 읽을 수 있을 때만 1번 더 보낸다. 풀의 다음 커넥션도 죽어 있으면 그것도 실패한다(C3).
- 이 글의 경우(half-close, 경로 소실의 RST)는 요청이 서버 애플리케이션에 닿지 않아 다시 보내도 안전하다.
- 다만 같은 예외가 요청이 처리된 뒤에도 난다.
  - 클라이언트가 보는 건 "요청을 다 쓰고 응답을 읽는데 EOF(또는 RST)가 왔다"뿐이다. 그 EOF 가 요청을 받기 전에 닫힌 탓인지, 처리하던 중 서버가 죽은 탓인지는 소켓에 드러나지 않는다.
  - 응답을 5초 늦추는 요청을 보내고 2초 뒤 upstream 컨테이너를 `docker kill` 로 죽였다. 요청은 이미 핸들러에서 처리 중이었는데도 클라이언트는 half-close 때와 같은 `NoHttpResponseException` 을 받았다. 프로세스가 죽으면 커널이 남은 소켓을 대신 닫아 FIN 이 가기 때문이다.
  - 처리 중에 DB 에 쓴 뒤 죽었다면, 이 예외를 보고 다시 보내는 순간 같은 쓰기가 두 번 된다.
- POST 같은 비멱등 요청까지 재시도하려면 서버 쪽 멱등 키 같은 장치가 먼저 있어야 한다. `SocketTimeoutException` 은 처리 여부를 알 수 없어 기본 전략도 재시도하지 않는다.

### 미리 막는 설정

| 설정 | 기준 | 막는 것 |
| --- | --- | --- |
| 클라이언트 keep-alive 시간 | 서버 `keepAliveTimeout` 보다 짧게. 서버가 `Keep-Alive` 헤더를 주면 기본 전략이 따른다 | 서버가 먼저 닫은 커넥션 |
| `evictIdleConnections(t)` | `2t` < 장비 idle timeout | 경로 소실 |
| 커널 TCP keepalive | `tcp_keepalive_time` < 장비 idle timeout | 경로 소실 |
| 서버 `keepAliveTimeout` | 장비 idle timeout 보다 짧게 | 경로 소실 |

- `validateAfterInactivity` 는 FIN·RST 가 온 커넥션만 거른다. 경로 소실은 못 거른다.
- `evictIdleConnections` 는 `setConnectionManagerShared(true)` 면 돌지 않는다.
- HttpClient5 5.4.2 classic 은 `SocketConfig.setTcpKeepIdle` 을 소켓에 넣지 않는다. `setSoKeepAlive(true)` 만으로는 커널 기본 2시간이 걸린다.

## 참고 자료

- [socket(7) SO_LINGER (man7.org/linux/man-pages/man7/socket.7)](https://man7.org/linux/man-pages/man7/socket.7.html)
- [RFC 9293 Transmission Control Protocol (rfc-editor.org/rfc/rfc9293)](https://www.rfc-editor.org/rfc/rfc9293)
- [Netfilter conntrack sysctl (docs.kernel.org/networking/nf_conntrack-sysctl)](https://docs.kernel.org/networking/nf_conntrack-sysctl.html)
- [TCP keepalive sysctl (docs.kernel.org/networking/ip-sysctl)](https://docs.kernel.org/networking/ip-sysctl.html)
- [Troubleshoot NAT gateways — Internet connection drops after 350 seconds (docs.aws.amazon.com/vpc/latest/userguide)](https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateway-troubleshooting.html#nat-gateway-troubleshooting-timeout)
- [Azure NAT Gateway resource — TCP idle timeout (learn.microsoft.com/azure/nat-gateway)](https://learn.microsoft.com/en-us/azure/nat-gateway/nat-gateway-resource)
- [Tune NAT configuration — TCP Established Connection Idle Timeout (docs.cloud.google.com/nat/docs)](https://docs.cloud.google.com/nat/docs/tune-nat-configuration)
- [Module ngx_http_upstream_module — keepalive (nginx.org/en/docs/http)](https://nginx.org/en/docs/http/ngx_http_upstream_module.html#keepalive)
- [Module ngx_http_proxy_module — proxy_next_upstream (nginx.org/en/docs/http)](https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_next_upstream)
- [Graceful Shutdown (docs.spring.io/spring-boot/reference/web)](https://docs.spring.io/spring-boot/reference/web/graceful-shutdown.html)
- [SocketConfig.Builder (hc.apache.org/httpcomponents-core-5.3.x/current/httpcore5/apidocs)](https://hc.apache.org/httpcomponents-core-5.3.x/current/httpcore5/apidocs/org/apache/hc/core5/http/io/SocketConfig.Builder.html)
- [Apache HttpComponents Client 5.4.2 소스 (github.com/apache/httpcomponents-client)](https://github.com/apache/httpcomponents-client/tree/rel/v5.4.2)
- [Apache HttpComponents Core 5.3.3 소스 (github.com/apache/httpcomponents-core)](https://github.com/apache/httpcomponents-core/tree/rel/v5.3.3)
