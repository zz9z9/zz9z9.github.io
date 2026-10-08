---
title: WEB - HTTP 커넥션 풀 직접 재보기 (1) 풀은 커넥션을 언제 만들고, 돌려받고, 버리나
date: 2026-10-09 01:00:00 +0900
categories: [지식 더하기, 이론]
tags: [WEB]
---

> HttpClient5 커넥션 풀이 커넥션을 언제 만들고, 언제 돌려받고, 언제 버리는지, 그리고 풀 설정이 그 과정의 어디에 걸리는지를 소스로 따라간다. <br>
> 기준 버전은 httpclient5 5.4.2 / httpcore5 5.3.3 이다.

## HTTP 커넥션 풀이란
---

> HTTP 커넥션 풀은 한 번 맺은 TCP 커넥션을 응답 뒤에도 닫지 않고 들고 있다가, 같은 목적지로 가는 다음 요청에 다시 빌려주는 객체다.

- 커넥션을 새로 맺으려면 TCP 3-way handshake 를, https 면 TLS 핸드셰이크까지 거쳐야 한다.
- HTTP/1.1 의 keep-alive 는 응답 뒤에도 커넥션을 열어 두자는 서버와 클라이언트 사이의 약속이고, 풀은 그렇게 열려 있는 커넥션을 모아 두었다가 요청마다 나눠 준다.
- 동시에 커넥션을 몇 개까지 만들지 상한도 정한다.

> Apache HttpClient 5 에서는 `PoolingHttpClientConnectionManager` 가 이 일을 한다. <br>
> 만드는 코드는 이렇다.

```java
// 전부 httpclient5 (org.apache.httpcomponents.client5:httpclient5) 안에 있다
import org.apache.hc.client5.http.impl.classic.CloseableHttpClient;                    // 요청을 보내는 클라이언트
import org.apache.hc.client5.http.impl.classic.HttpClients;                            // 클라이언트 빌더 진입점
import org.apache.hc.client5.http.impl.io.PoolingHttpClientConnectionManager;          // 커넥션 풀 (blocking I/O 용)
import org.apache.hc.client5.http.impl.io.PoolingHttpClientConnectionManagerBuilder;

PoolingHttpClientConnectionManager manager = PoolingHttpClientConnectionManagerBuilder.create()
        .setMaxConnTotal(50)        // 풀 전체 상한
        .setMaxConnPerRoute(50)     // 목적지(route)별 상한
        .build();

CloseableHttpClient httpClient = HttpClients.custom()
        .setConnectionManager(manager)
        .build();
```

매니저를 지정하지 않아도 풀은 생긴다. 위 코드에서 매니저를 빼면 이렇게 된다.

```java
CloseableHttpClient httpClient = HttpClients.createDefault();
// 또는
CloseableHttpClient httpClient = HttpClients.custom().build();
```

둘 다 `HttpClientBuilder` 를 만들어 `build()` 를 부른다.

```java
// org.apache.hc.client5.http.impl.classic.HttpClients.java (httpclient5 5.4.2)
public static HttpClientBuilder custom() {
    return HttpClientBuilder.create();
}

public static CloseableHttpClient createDefault() {
    return HttpClientBuilder.create().build();
}
```

- `build()` 는 지정된 매니저가 없으면 같은 `PoolingHttpClientConnectionManager` 를 기본값으로 만들어 끼운다.
- 그래서 **HttpClient5 클라이언트는 설정이 없어도 풀을 쓰고**, 이때 상한은 기본값 perRoute 5 / total 25 다.

```java
// org.apache.hc.client5.http.impl.classic.HttpClientBuilder.java — build() (httpclient5 5.4.2)
HttpClientConnectionManager connManagerCopy = this.connManager;
if (connManagerCopy == null) {
    final PoolingHttpClientConnectionManagerBuilder connectionManagerBuilder = PoolingHttpClientConnectionManagerBuilder.create();
    if (systemProperties) {
        connectionManagerBuilder.useSystemProperties();
    }
    connManagerCopy = connectionManagerBuilder.build();
}
```

매니저 안에서 커넥션을 실제로 들고 있는 건 httpcore5 의 `StrictConnPool` 이다. 필드를 보면 풀이 무엇으로 이뤄져 있는지 그대로 나온다.

```java
// org.apache.hc.core5.pool.StrictConnPool.java (httpcore5 5.3.3)
private final Map<T, PerRoutePool<T, C>> routeToPool;          // 목적지(route)별 하위 풀
private final LinkedList<LeaseRequest<T, C>> pendingRequests;  // 빌리려고 기다리는 요청
private final Set<PoolEntry<T, C>> leased;                     // 빌려준 엔트리
private final LinkedList<PoolEntry<T, C>> available;           // 놀고 있는 엔트리
private final Map<T, Integer> maxPerRoute;
private volatile int maxTotal;
```

- `T` 는 목적지를 나타내는 `HttpRoute`(scheme·host·port 등)이고, `C` 는 소켓을 감싼 `ManagedHttpClientConnection` 이다.
- 아래 그림은 업스트림 하나에 커넥션 5개를 들고, 그중 2개를 빌려준 상태다.
- `pendingRequests` 는 비어 있다. 빌려줄 엔트리가 `available` 에 남아 있으면 기다릴 일이 없다. 상한에 막혀 기다리는 모습은 아래 "설정별 영향도" 에 있다.

![커넥션 풀 구조 — 따로 묶인 leased 엔트리 2개는 스레드가 빌려 업스트림과 요청·응답을 주고받는 중이고, available 엔트리 3개는 연결만 유지한 채 쉬고 있으며, pendingRequests 는 비어 있다](/assets/img/http-connection-pool-img1.png)

- `leased`·`available` 에 들어 있는 `PoolEntry` 는 풀에 등록된 커넥션 한 건의 항목(엔트리)이다.
- `Map.Entry` 가 키와 값을 묶듯 **목적지와 커넥션**을 묶고, 생성·반납·만료 시각 같은 **메타데이터**를 붙인다.

## PoolEntry — 풀이 커넥션마다 두는 항목
---

> `PoolEntry` 는 풀에 등록된 커넥션 한 건의 항목(엔트리)이다. <br>
> 커넥션 자체가 아니라 **커넥션을 가리키는 참조와 메타데이터**를 들고 있어서, 커넥션 없이 먼저 만들어지고 커넥션만 버린 뒤에도 남을 수 있다.

- entry 는 사전의 표제어 한 줄, 장부의 한 건처럼 목록에 등록된 항목을 뜻한다.
- `Map.Entry` 와 모양이 같다.

```java
Map.Entry<K, V>     // 맵에 등록된 한 항목: 키 + 값
PoolEntry<T, C>     // 풀에 등록된 한 항목: 목적지(route) + 커넥션 + 메타데이터
```

### 엔트리 안에 든 것

```java
// org.apache.hc.core5.pool.PoolEntry.java (httpcore5 5.3.3, 필드만)
public final class PoolEntry<T, C extends ModalCloseable> {
    private final T route;                          // 목적지 (HttpRoute)
    private final TimeValue timeToLive;             // 커넥션 최대 수명 (기본 무제한)
    private final AtomicReference<C> connRef;       // 할당된 커넥션. 비어 있을 수 있다
    private volatile long created;                  // 커넥션을 할당한 시각
    private volatile long updated;                  // 마지막 반납 시각
    private volatile Deadline expiryDeadline;       // 이 시각이 지나면 재사용하지 않는다
    private volatile Deadline validityDeadline;     // created + timeToLive
    ...
    public boolean hasConnection() {
        return this.connRef.get() != null;
    }
}
```

엔트리 안은 세 겹이다.

```
PoolEntry                                   ← leased / available 에 들어가는 것
  └ connRef → ManagedHttpClientConnection   ← HTTP 요청·응답을 읽고 쓰는 객체
                └ socket → java.net.Socket   ← 커널의 TCP 소켓
```

- `connRef` 는 `null` 일 수 있다. 커넥션 객체는 있는데 소켓은 아직 없는 때도 있다.
- 풀이 세는 `leased`·`available` 은 엔트리의 개수다. 엔트리 안의 소켓이 살아 있는지는 세지 않는다.

재사용 기한도 엔트리에 기록된다.

| 필드 | 언제 정해지나 |
| --- | --- |
| `validityDeadline` | 커넥션을 할당할 때 `created + timeToLive` 로 한 번. 빌더로 만든 매니저에서는 무한이다 (아래) |
| `expiryDeadline` | 반납할 때마다 `min(now + keepAlive, validityDeadline)` |
| `updated` | 반납 시각. `validateAfterInactivity` 가 이 값을 기준으로 stale 체크를 돌린다 |

이 `timeToLive` 는 `ConnectionConfig.setTimeToLive` 로 준 값이 아니다. `PoolingHttpClientConnectionManagerBuilder` 는 풀을 만들 때 그 자리에 `null` 을 넘긴다.

```java
// org.apache.hc.client5.http.impl.io.PoolingHttpClientConnectionManagerBuilder.java — build() (httpclient5 5.4.2)
final PoolingHttpClientConnectionManager poolingmgr = new PoolingHttpClientConnectionManager(
        createConnectionOperator(schemePortResolver, dnsResolver, tlsSocketStrategyCopy),
        poolConcurrencyPolicy,
        poolReusePolicy,
        null,                 // 풀의 timeToLive
        connectionFactory);
```

- 그래서 빌더로 만든 매니저에서는 `validityDeadline` 이 무한이고, `expiryDeadline` 은 keep-alive 로만 정해진다.
- `ConnectionConfig` 의 `timeToLive` 는 `expiryDeadline` 에 반영되지 않는다. 매니저가 lease 때(⑥ 검사 2)와 evict 스레드의 `closeExpired()` 때 `created` 와 비교해 따로 본다("설정별 영향도").

### createEntry 에서 버려지기까지

![PoolEntry 의 생애 — caller 스레드의 lease 로 빈 엔트리가 생기고, 커넥션 객체가 할당되고, upstream 과 TCP 핸드셰이크를 하고, 요청·응답을 주고받은 뒤 반납되어 available 로 갔다가 다음 요청 때 핸드셰이크 없이 다시 쓰인다. 재사용 불가·만료·stale 이면 소켓을 닫아 upstream 에 FIN 이 간다](/assets/img/http-connection-pool-img2.png)

**① 엔트리를 만든다.** 빈 엔트리를 만들어 바로 `leased` 에 넣는다. `connRef` 는 비어 있다.

```java
// org.apache.hc.core5.pool.StrictConnPool.PerRoutePool — createEntry() (httpcore5 5.3.3)
public PoolEntry<T, C> createEntry(final TimeValue timeToLive) {
    final PoolEntry<T, C> entry = new PoolEntry<>(this.route, timeToLive, disposalCallback);
    this.leased.add(entry);
    return entry;
}
```

만드는 건 빌려줄 엔트리가 `available` 에 없고(⑥ 검사 1 을 통과한 게 없고), 상한에 여유가 있을 때뿐이다. 여유가 없으면 요청은 `pendingRequests` 에 들어가 다른 엔트리가 반납되기를 `connectionRequestTimeout` 까지 기다린다. 넘기면 예외로 실패한다.

```java
// org.apache.hc.core5.pool.StrictConnPool — processPendingRequest() (httpcore5 5.3.3, getFree 이후)
final int maxPerRoute = getMax(route);
if (pool.getAllocatedCount() < maxPerRoute) {             // route 상한에 여유가 있고
    final int freeCapacity = Math.max(this.maxTotal - this.leased.size(), 0);
    if (freeCapacity == 0) {                              // 전체 상한도 확인한다
        return false;
    }
    ...
    entry = pool.createEntry(this.timeToLive);            // ① 빈 엔트리를 만든다
    this.leased.add(entry);
    request.completed(entry);
    return true;
}
return false;                                             // 여유가 없으면 lease() 가 pendingRequests 에 넣는다
```

**② 커넥션 객체를 할당한다.** 매니저가 빌린 엔트리에 커넥션이 없으면 새 커넥션 객체를 만들어 `connRef` 에 할당한다. `createConnection(null)` 의 `null` 이 소켓이다. 아직 TCP 연결은 없다.

```java
// org.apache.hc.client5.http.impl.io.PoolingHttpClientConnectionManager — lease() (httpclient5 5.4.2, 일부)
final ManagedHttpClientConnection conn = poolEntry.getConnection();
if (conn != null) {
    conn.activate();                                                // 재사용
} else {
    poolEntry.assignConnection(connFactory.createConnection(null)); // 소켓 없는 커넥션 객체
}
```

```java
// org.apache.hc.core5.pool.PoolEntry — assignConnection() (httpcore5 5.3.3)
public void assignConnection(final C conn) {
    if (this.connRef.compareAndSet(null, conn)) {
        this.created = getCurrentTime();
        this.updated = this.created;
        this.validityDeadline = Deadline.calculate(this.created, this.timeToLive);
        this.expiryDeadline = this.validityDeadline;
        this.state = null;
    } else {
        throw new IllegalStateException("Connection already assigned");
    }
}
```

**③ 소켓을 연결한다.** exec chain 이 `connect` 를 부르면 소켓을 만들어 TCP 핸드셰이크를 하고, 커넥션 객체에 묶는다. 커널에 소켓이 생기는 건 이 단계다.

```java
// org.apache.hc.client5.http.impl.io.DefaultHttpClientConnectionOperator — connect() (httpclient5 5.4.2, 일부)
final Socket socket = detachedSocketFactory.create(socksProxy);
...
socket.connect(remoteAddress, connectTimeout);   // TCP 3-way handshake
conn.bind(socket);
```

**④ 요청을 보내고 응답을 받는다.** 스레드가 엔트리의 소켓으로 요청을 쓰고 응답을 읽는다. 응답 헤더를 보고 이 커넥션을 다시 쓸지, 쓴다면 얼마 동안 쓸지 정해 둔다. 이 값은 반납 때 엔트리에 기록된다.

```java
// org.apache.hc.client5.http.impl.classic.MainClientExec — execute() (httpclient5 5.4.2, 일부)
final ClassicHttpResponse response = execRuntime.execute(exchangeId, request, ..., context);
...
if (reuseStrategy.keepAlive(request, response, context)) {          // Connection: close 가 없으면
    final TimeValue duration = keepAliveStrategy.getKeepAliveDuration(response, context); // Keep-Alive: timeout=N
    execRuntime.markConnectionReusable(userToken, duration);
} else {
    execRuntime.markConnectionNonReusable();
}
```

**⑤ 반납한다.** ④ 에서 재사용할 수 있다고 정했으면 기한을 갱신하고 `available` 맨 앞에 넣는다. 재사용할 수 없으면 소켓을 닫고 엔트리를 어디에도 넣지 않는다.

```java
// org.apache.hc.client5.http.impl.io.PoolingHttpClientConnectionManager — release() (httpclient5 5.4.2, 일부)
boolean reusable = conn != null && conn.isOpen() && conn.isConsistent();
if (reusable) {
    entry.updateState(state);
    entry.updateExpiry(keepAlive);        // expiryDeadline, updated 갱신
}
this.pool.release(entry, reusable);
```

```java
// org.apache.hc.core5.pool.StrictConnPool — release() (httpcore5 5.3.3, 일부)
if (this.leased.remove(entry)) {
    final boolean keepAlive = entry.hasConnection() && reusable;
    pool.free(entry, keepAlive);
    if (keepAlive) {
        this.available.addFirst(entry);   // LIFO
    } else {
        entry.discardConnection(CloseMode.GRACEFUL);
    }
}
```

`keepAlive` 가 `false` 면 `leased` 에서만 빠지고 `available` 에 들어가지 않는다. 풀이 엔트리를 더는 참조하지 않으니 엔트리는 GC 된다.

**⑥ 다시 빌린다.** `getFree` 가 `available` 맨 앞부터 엔트리를 꺼내 `leased` 로 옮긴다. 소켓은 그대로라 핸드셰이크가 없다. 꺼낸 엔트리는 두 번 검사받는다.

**검사 1 — 풀에서 `expiryDeadline` 을 본다.** 만료됐으면 엔트리째 버리고 다음 엔트리를 꺼낸다. 남은 게 없으면 `createEntry` 로 ① 부터 다시 간다.

```java
// org.apache.hc.core5.pool.StrictConnPool — processPendingRequest() (httpcore5 5.3.3, 일부)
for (;;) {
    entry = pool.getFree(state);                       // available 맨 앞부터 꺼낸다
    if (entry == null) {
        break;
    }
    if (entry.getExpiryDeadline().isExpired()) {       // 만료 → 엔트리째 버리고 다음
        entry.discardConnection(CloseMode.GRACEFUL);
        this.available.remove(entry);
        pool.free(entry, false);
    } else {
        break;
    }
}
if (entry != null) {                                   // 재사용
    this.available.remove(entry);
    this.leased.add(entry);
    request.completed(entry);
    return true;
}
// 여기까지 오면 빌려줄 엔트리가 없다 → createEntry (①)
```

```java
// org.apache.hc.core5.pool.StrictConnPool.PerRoutePool — getFree() (httpcore5 5.3.3, state 가 null 인 경로)
final Iterator<PoolEntry<T, C>> it = this.available.iterator();
while (it.hasNext()) {
    final PoolEntry<T, C> entry = it.next();
    if (entry.getState() == null) {
        it.remove();
        this.leased.add(entry);
        return entry;
    }
}
```

**검사 2 — 매니저에서 `timeToLive` 와 `isStale()` 을 본다.** 이미 `leased` 에 든 엔트리라 소켓만 버리고 엔트리는 그대로 둔다. 그다음 ② 의 `conn == null` 분기로 새 커넥션 객체를 할당하고 ③ 에서 다시 연결한다.

- `timeToLive` 는 `created`(커넥션을 할당한 시각)부터 잰다. 지났으면 `GRACEFUL` 로 닫는다.
- `isStale()` 은 마지막 반납(`updated`)부터 `validateAfterInactivity`(기본 2초) 넘게 쉰 엔트리에만 돈다. 걸리면 `IMMEDIATE` 로 닫는다.

```java
// org.apache.hc.client5.http.impl.io.PoolingHttpClientConnectionManager — lease() (httpclient5 5.4.2, 일부)
if (poolEntry.hasConnection()) {
    final TimeValue timeToLive = connectionConfig.getTimeToLive();
    if (TimeValue.isNonNegative(timeToLive)) {
        if (timeToLive.getDuration() == 0
                || Deadline.calculate(poolEntry.getCreated(), timeToLive).isExpired()) {
            poolEntry.discardConnection(CloseMode.GRACEFUL);     // 수명 초과
        }
    }
}
if (poolEntry.hasConnection()) {
    final TimeValue timeValue = resolveValidateAfterInactivity(connectionConfig);
    if (TimeValue.isNonNegative(timeValue)) {
        if (timeValue.getDuration() == 0
                || Deadline.calculate(poolEntry.getUpdated(), timeValue).isExpired()) {
            final ManagedHttpClientConnection conn = poolEntry.getConnection();
            boolean stale;
            try {
                stale = conn.isStale();
            } catch (final IOException ignore) {
                stale = true;
            }
            if (stale) {
                poolEntry.discardConnection(CloseMode.IMMEDIATE); // 끊긴 소켓
            }
        }
    }
}
final ManagedHttpClientConnection conn = poolEntry.getConnection();
if (conn != null) {
    conn.activate();                                                // 둘 다 통과 → 그대로 재사용
} else {
    poolEntry.assignConnection(connFactory.createConnection(null)); // 소켓을 버렸으면 ② 로
}
```

- 검사 1 에 걸리면 그 엔트리를 버리고 `available` 의 다음 엔트리를 꺼낸다. 남은 게 없을 때만 ① 부터 엔트리·커넥션 객체·소켓을 모두 새로 만든다. 검사 2 에 걸리면 엔트리는 그대로 두고 커넥션 객체와 소켓만 새로 만든다.

### 엔트리가 버려지는 때와 소켓만 버려지는 때

> 네 경우 모두 소켓은 `discardConnection` 이 닫는다. <br>
> 이 메서드는 소켓을 닫고 `connRef` 를 비울 뿐 엔트리를 지우지 않는다. 엔트리가 같이 사라지는지는 부른 쪽이 엔트리를 풀에서 빼느냐에 달렸다.

![엔트리가 버려지는 때와 소켓만 버려지는 때 — 반납 때 재사용 불가, lease 때 만료, evict 는 엔트리를 버리고, lease 때 timeToLive 초과나 isStale 이면 소켓만 버리고 엔트리는 leased 에 남는다](/assets/img/http-connection-pool-img3.png)

```java
// org.apache.hc.core5.pool.PoolEntry — discardConnection() (httpcore5 5.3.3)
public void discardConnection(final CloseMode closeMode) {
    final C connection = this.connRef.getAndSet(null);
    if (connection != null) {
        this.state = null;
        this.created = 0;
        this.updated = 0;
        this.expiryDeadline = Deadline.MIN_VALUE;
        this.validityDeadline = Deadline.MIN_VALUE;
        if (this.disposalCallback != null) {
            this.disposalCallback.execute(connection, closeMode);
        } else {
            connection.close(closeMode);
        }
    }
}
```

- evict 를 켜면 `idle-connection-evictor` 스레드가 `maxIdleTime` 마다 깨어나 만료된 엔트리와 오래 논 엔트리를 치운다.

```java
// org.apache.hc.client5.http.impl.IdleConnectionEvictor (httpclient5 5.4.2, 일부)
while (!Thread.currentThread().isInterrupted()) {
    localSleepTime.sleep();                          // HttpClientBuilder 는 maxIdleTime 을 넘긴다
    connectionManager.closeExpired();                // expiryDeadline 이나 수명(timeToLive)이 지난 엔트리
    if (maxIdleTime != null) {
        connectionManager.closeIdle(maxIdleTime);    // maxIdleTime 넘게 논 엔트리
    }
}
```

- 소켓만 지울지 엔트리까지 지울지는 검사하는 시점에 엔트리를 누가 쥐고 있느냐로 정해지는 것으로 보인다(소스 구조로 본 해석이다).
  - **풀이 쥐고 있으면(반납·만료·evict) 엔트리를 버린다.** 상한이 세는 건 엔트리 개수라 빈 엔트리는 자리만 차지하고, 풀은 커넥션을 새로 만들 수 없다.
  - **스레드가 쥐고 있으면(TTL 초과·stale) 소켓만 바꾼다.** 이미 받은 자리를 놓으면 다시 lease 해야 하므로, `connFactory` 를 가진 매니저가 그 엔트리에 새 커넥션을 할당한다.

## 설정별 영향도
---

> HttpClient5 의 풀 관련 설정은 엔트리 생애의 한 지점에 걸려서, 그 지점에서 생길 수 있는 문제 하나를 막는다. <br>
> 기본값은 httpclient5 5.4.2 / httpcore5 5.3.3 소스 기준이다.

![설정별 영향도 — caller·풀·upstream 사이에서, lease 요청 때는 maxConnTotal·maxConnPerRoute 와 connectionRequestTimeout 이 상한과 대기를, 연결·요청 때는 connectTimeout 과 responseTimeout 이 매달림을, 반납 때는 upstream 의 Keep-Alive 로 keep-alive 전략이 만료 시각을, available 에서 쉬는 동안은 evict 스레드가 upstream 에 먼저 FIN 을 보내 정리를, 다음 lease 때는 validateAfterInactivity 와 timeToLive 가 소켓을 새로 연결하게 한다](/assets/img/http-connection-pool-img4.png)

- ### maxPerRoute — 목적지마다 몫이 나뉜다

`maxTotal` 은 풀 전체, `maxPerRoute` 는 목적지(route) 하나가 가질 수 있는 커넥션 수다. 목적지가 둘 이상일 때 차이가 드러난다.

![maxPerRoute — (가) maxTotal=8, maxPerRoute=4 면 느려진 upstream A 가 자기 몫 4개만 묶고, 5번째 A 요청은 전체에 자리가 남아도 pendingRequests 에서 기다리며, B 요청은 자기 몫으로 새 커넥션을 만든다. (나) maxPerRoute=8 이면 A 가 전체 8개를 다 차지해 B 는 커넥션이 하나도 없는데도 기다린다](/assets/img/http-connection-pool-img5.png)

- 새 엔트리를 만들 수 있는지는 두 번 따진다. route 의 엔트리 수(`leased` + `available`)가 `maxPerRoute` 보다 적고, 풀 전체의 `leased` 가 `maxTotal` 보다 적어야 한다. 위 ① 에 인용한 `processPendingRequest` 의 두 `if` 다.
- (가) 처럼 `maxPerRoute` 를 `maxTotal` 보다 작게 두면, 한 목적지가 느려져도 그 목적지 몫만 묶이고 나머지 목적지는 계속 커넥션을 얻는다.
- (나) 처럼 둘을 같게 두면, 느려진 목적지 하나가 전체 상한을 다 차지해 멀쩡한 목적지로 가는 요청까지 `connectionRequestTimeout` 까지 기다린다.
- 전체 상한이 찼어도 다른 route 의 엔트리가 `available` 에서 놀고 있으면 기다리지 않는다. 풀이 `available` 맨 뒤(가장 오래 논) 엔트리를 닫고 그 자리에 새 엔트리를 만든다. (나) 에서 B 가 기다리는 건 A 의 8개가 모두 `leased` 이기 때문이다.

```java
// org.apache.hc.core5.pool.StrictConnPool — processPendingRequest() (httpcore5 5.3.3, 일부)
if (pool.getAllocatedCount() < maxPerRoute) {
    final int freeCapacity = Math.max(this.maxTotal - this.leased.size(), 0);
    if (freeCapacity == 0) {
        return false;                                         // 전체가 다 빌려 나갔다 → 기다린다
    }
    final int totalAvailable = this.available.size();
    if (totalAvailable > freeCapacity - 1) {                  // 놀고 있는 엔트리가 자리를 차지하면
        final PoolEntry<T, C> lastUsed = this.available.removeLast();
        lastUsed.discardConnection(CloseMode.GRACEFUL);       // 가장 오래 논 것을 닫고
        final PerRoutePool<T, C> otherpool = getPool(lastUsed.getRoute());
        otherpool.remove(lastUsed);
    }
    entry = pool.createEntry(this.timeToLive);                // 새로 만든다
    ...
}
```

### evict — 쉬는 엔트리를 치우는 스레드

evict 두 설정은 같은 `IdleConnectionEvictor` 스레드 하나를 띄운다.
- 무엇을 켰느냐에 따라 스레드가 깨는 주기와 부르는 메서드가 다르다.
- `maxIdleTime` 은 따로 설정하는 값이 아니라 `evictIdleConnections(t)` 에 넘기는 인자 `t` 다.

| 켠 것 | 깨는 주기 | 부르는 메서드 |
| --- | --- | --- |
| `evictExpiredConnections()` 만 | 5초 | `closeExpired()` |
| `evictIdleConnections(t)` 만 | `t` | `closeExpired()` + `closeIdle(t)` |
| 둘 다 | `t` | `closeExpired()` + `closeIdle(t)` — `evictIdleConnections(t)` 만 켠 것과 같다 |

```java
// org.apache.hc.client5.http.impl.classic.HttpClientBuilder.java — build() (httpclient5 5.4.2)
if (!this.connManagerShared) {
    ...
    if (evictExpiredConnections || evictIdleConnections) {           // 둘 중 하나만 켜도 스레드 하나
        if (connManagerCopy instanceof ConnPoolControl) {
            final IdleConnectionEvictor connectionEvictor = new IdleConnectionEvictor((ConnPoolControl<?>) connManagerCopy,
                    maxIdleTime, maxIdleTime);                       // sleepTime 과 maxIdleTime 에 같은 값
            ...
            connectionEvictor.start();
        }
    }
}
```

```java
// org.apache.hc.client5.http.impl.IdleConnectionEvictor (httpclient5 5.4.2, 일부)
final TimeValue localSleepTime = sleepTime != null ? sleepTime : TimeValue.ofSeconds(5); // evictExpired 만 켜면 null -> 5초
...
while (!Thread.currentThread().isInterrupted()) {
    localSleepTime.sleep();
    connectionManager.closeExpired();                // 늘 부른다
    if (maxIdleTime != null) {                       // evictIdleConnections 를 켰을 때만
        connectionManager.closeIdle(maxIdleTime);
    }
}
```

두 메서드는 `available` 의 엔트리만 훑는다. 빌려준 엔트리는 건드리지 않는다.

- `closeExpired()` 는 만료 시각이나 수명이 지난 엔트리를 버린다. 매니저가 풀의 `closeExpired()` 를 덮어써서, `expiryDeadline` 과 함께 `ConnectionConfig` 의 `created + timeToLive` 도 본다.
- `closeIdle(t)` 는 마지막 반납(`updated`)부터 `t` 넘게 논 엔트리를 버린다. 만료 시각은 보지 않는다.

```java
// org.apache.hc.client5.http.impl.io.PoolingHttpClientConnectionManager.java (httpclient5 5.4.2)
this.pool = new StrictConnPool<HttpRoute, ManagedHttpClientConnection>(...) {
    @Override
    public void closeExpired() {
        enumAvailable(e -> closeIfExpired(e));       // 풀 기본 구현을 덮어쓴다
    }
};

void closeIfExpired(final PoolEntry<HttpRoute, ManagedHttpClientConnection> entry) {
    final long now = System.currentTimeMillis();
    if (entry.getExpiryDeadline().isBefore(now)) {                       // keep-alive 로 정한 만료 시각
        entry.discardConnection(CloseMode.GRACEFUL);
    } else {
        final ConnectionConfig connectionConfig = resolveConnectionConfig(entry.getRoute());
        final TimeValue timeToLive = connectionConfig.getTimeToLive();
        if (timeToLive != null && Deadline.calculate(entry.getCreated(), timeToLive).isBefore(now)) { // 수명
            entry.discardConnection(CloseMode.GRACEFUL);
        }
    }
}
```

```java
// org.apache.hc.core5.pool.StrictConnPool.java (httpcore5 5.3.3)
public void closeIdle(final TimeValue idleTime) {
    final long deadline = System.currentTimeMillis() - (TimeValue.isPositive(idleTime) ? idleTime.toMilliseconds() : 0);
    enumAvailable(entry -> {
        if (entry.getUpdated() <= deadline) {        // 마지막 반납이 idleTime 보다 전
            entry.discardConnection(CloseMode.GRACEFUL);
        }
    });
}

public void enumAvailable(final Callback<PoolEntry<T, C>> callback) {
    ...
    final Iterator<PoolEntry<T, C>> it = this.available.iterator();
    while (it.hasNext()) {
        final PoolEntry<T, C> entry = it.next();
        callback.execute(entry);                     // 위의 검사. 걸리면 소켓을 닫는다
        if (!entry.hasConnection()) {                // 소켓을 닫은 엔트리는 풀에서 뺀다
            final PerRoutePool<T, C> pool = getPool(entry.getRoute());
            pool.remove(entry);
            it.remove();
        }
    }
    processPendingRequests();                        // 자리가 났으니 기다리던 요청을 깨운다
    ...
}
```

- **`setConnectionManagerShared(true)` 면 evict 설정은 아무 일도 하지 않는다.** 스레드를 띄우는 코드가 `!this.connManagerShared` 안에 있다.
- **엔트리는 `maxIdleTime` 의 두 배 가까이 남을 수 있다.** 스레드가 `maxIdleTime` 마다 깨므로, 직전 검사 바로 뒤에 반납된 엔트리는 다음 검사에서 아직 기준을 넘지 않아 그다음 검사에서야 치워진다(소스로 본 해석이다). 중간 장비의 idle timeout 보다 먼저 닫으려면 `maxIdleTime` 을 그 절반 아래로 둔다.
- **`ConnectionConfig.setTimeToLive` 는 lease 때와 `closeExpired()` 때 본다.** evict 를 끄면 lease 때만 보므로, 수명이 지난 커넥션도 다음 요청이 올 때까지 `available` 에 남는다.
- **경로 소실을 미리 막는 건 `evictIdleConnections` 뿐이다.** `validateAfterInactivity` 는 FIN 을 받은 소켓만 걸러낸다. 중간 장비가 말없이 지운 커넥션은 그 장비의 idle timeout 전에 풀이 먼저 닫아야 피할 수 있다. 이미 실린 요청은 `responseTimeout` 이 끊어 줄 뿐이다.

## 참고 자료
---

> 본문의 코드는 아래 태그의 소스에서 옮겼다.

- [Apache HttpComponents Client 5.4.2 소스 (github.com/apache/httpcomponents-client)](https://github.com/apache/httpcomponents-client/tree/rel/v5.4.2)
- [Apache HttpComponents Core 5.3.3 소스 (github.com/apache/httpcomponents-core)](https://github.com/apache/httpcomponents-core/tree/rel/v5.3.3)
