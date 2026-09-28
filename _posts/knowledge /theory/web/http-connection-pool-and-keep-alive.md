---
title: WEB - HTTP 커넥션 풀과 keep-alive, 직접 재보기
categories: [지식 더하기, 이론]
tags: [WEB]
---

> Http 커넥션 풀을 사용하는 목적과 실측을 통해 체감해본다

## 커넥션 풀 사용 목적 ?
---

- 개인적으로 keep-alive가 적용(상대서버도 사용)돼야 커넥션 '재사용'의 효과를 제대로 누릴 수 있다고 생각
  - 즉, 3-way handshake 생략으로 인한 응답시간 이득(?) https일수록 ?

- keep-alive off 이더라도, 커넥션 풀을 사용하면 커넥션 풀 사이즈, maxPerRoute 등이 상대 서버에 이슈가 있거나 할 때 우리쪽 자원(소켓, 대역폭 ?, 메모리? 등등?)을 무한정 점유하지 않게하는 '상방' 역할이 가능하다고 생각
  - 반대로 설정을 제대로 신경쓰지 않거나 잘못하게되면, 자원이 여유로운데 제대로 활용하지 못하게 억제하는 '상방'으로의 역할이 될 수 있다고 생각


## 실측 환경
---

> 재려는 값이 수 ms 단위라, 측정 환경이 그 크기의 오차를 만들면 아무것도 갈라지지 않는다. 환경 구성의 목표는 성능이 아니라 **재려는 값보다 작은 오차**다.

### 왜 이렇게 구성하는가

**로컬 루프백만으로는 결론이 안 난다.** 루프백 RTT는 0.05ms 수준이라 핸드셰이크 생략 이득이 측정 노이즈에 묻힌다. 그렇다고 upstream에서 `Thread.sleep`을 거는 건 **핸드셰이크가 끝난 뒤 구간**이라 RTT를 흉내내지 못한다. 네트워크 레벨 지연 주입이 따로 필요하다.

**지연은 두 축으로 나눠서 건다.**

| | 주입 위치 | 핸드셰이크에 영향 | 흉내내는 것 |
| --- | --- | --- | --- |
| RTT | toxiproxy latency toxic | **있다** | 물리적 거리 |
| 처리시간 | upstream `Thread.sleep` | 없다 | 상대 서버가 자기 의존성 때문에 느림 |

**지연값은 구간마다 다르다.** 3초는 장애 상황을 흉내내는 값이고 기본값이 아니다.

| 구간 | `delayMs` | 쓰는 곳 |
| --- | --- | --- |
| 정상 | 50 | 기준선. 대부분의 실험이 여기서 돈다 |
| 장애 | 3000 | 상대 서버에 이슈가 있을 때만 |
| idle | — | 부하를 끊고 쉬게 한다 (stale 확인) |

**caller까지 전부 컨테이너에 넣는다.** macOS의 Docker는 리눅스 VM 안에서 도는데, 맥의 JVM이 published port로 컨테이너를 호출하면 VM 경계를 한 번 넘는다. 여기 붙는 지연과 지터가 재려는 값과 같은 크기다. 셋 다 같은 브리지 네트워크에 두면 이 홉이 사라진다. 부하 생성기도 마찬가지라 같은 네트워크에 넣는다.

컨테이너로 넣으면 따라오는 것:

- **소켓 관측** — macOS에는 `ss`가 없다. ephemeral port range를 좁혀 고갈을 빨리 재현하는 것도 컨테이너 netns 안에서는 `--sysctl net.ipv4.ip_local_port_range` 한 줄인데, 맥 호스트에서는 전역 설정을 건드려야 한다.
- **조건 고정** — JVM이 cgroup 제한을 읽으므로 `--cpus`를 주면 `availableProcessors`·GC 스레드 수·톰캣 기본 스레드 수가 거기 맞춰 결정된다. 맥북에서는 thermal throttling과 백그라운드 앱 때문에 1회차와 5회차 조건이 달라지므로, **분리보다 고정이 핵심**이다.

### 구성

```
k6 ──▶ caller:8080 ──▶ toxiproxy:8666 ──▶ upstream:8080 (http)
                   ──▶ toxiproxy:8667 ──▶ upstream:8443 (https)
                                            전부 같은 브리지 네트워크
```

| 컨테이너 | cpus | 역할 |
| --- | --- | --- |
| caller | 2 | 측정 대상. RestClient + HttpClient5 풀 |
| upstream | 2 | 병목이 되면 안 된다 |
| k6 | 2 | 부하 생성기가 병목이면 TPS가 거짓말이 된다 |
| toxiproxy | 1 | 지연·장애 주입 |

풀 설정은 전부 env var로 뺀다(`@ConfigurationProperties`). 실험 조건 변경이 이미지 재빌드 없이 `docker compose up -d --force-recreate` 로 끝난다. jar는 bind-mount 하고 이미지는 `eclipse-temurin:21-jre` 로 고정한다.

### 역할 분담

| | 담당 | 예 |
| --- | --- | --- |
| upstream 앱 | **HTTP 레벨** — 응답 내용·시간·헤더 | 지연, 본문 크기, 상태 코드, `Connection: close` |
| toxiproxy | **TCP 레벨** — 커넥션·네트워크 장애 | RTT, 대역폭, `reset_peer`, `timeout` |

커넥션을 끊거나 RST를 쏘는 건 앱에서 흉내내기 번거로운데 toxic으로는 한 줄이다. 앱은 정상적인 HTTP 응답만 만든다.

### upstream 응답

엔드포인트 하나로 충분하다.

```java
@RestController
public class EchoController {

    // 요청마다 만들면 upstream 의 GC·CPU 를 재게 된다. 미리 만들어둔다
    private static final Map<Integer, byte[]> BODIES = Map.of(
            0, new byte[0],
            1024, filled(1024),
            102400, filled(102400));

    @GetMapping("/echo")
    ResponseEntity<byte[]> echo(@RequestParam(defaultValue = "0") long delayMs,
                                @RequestParam(defaultValue = "0") int sizeBytes,
                                @RequestParam(defaultValue = "200") int status,
                                @RequestParam(defaultValue = "false") boolean close)
            throws InterruptedException {
        Thread.sleep(delayMs);                          // 스레드는 점유, CPU 는 안 쓴다
        BodyBuilder b = ResponseEntity.status(status);
        if (close) {
            b.header(HttpHeaders.CONNECTION, "close");  // 재시작 없이 keep-alive 만 끈다
        }
        return b.body(BODIES.get(sizeBytes));
    }
}
```

| 파라미터 | 무엇을 가르는가 |
| --- | --- |
| `delayMs` | 상대 서버 지연. 처음엔 고정값 — Little's law 검증은 지연이 일정해야 예측값이 떨어진다 |
| `sizeBytes` | 본문이 작으면 한 세그먼트에 끝나 **TCP slow start 효과가 안 보인다.** 100KB 쯤 되면 재사용된 커넥션이 handshake RTT 와 **별개로** 빠르다 |
| `status` | 에러 경로. 커넥션 누수는 정상 경로가 아니라 예외 경로에서 난다 |
| `close` | upstream 재시작 없이 요청 단위로 keep-alive 토글 |

고정 `byte[]` 를 돌려주면 `Content-Length` 가 확정돼서 chunked 일 때보다 재사용 판단이 단순해진다.

**upstream 스레드는 기본값 200 에서 시작한다.** 올려놓고 시작하는 것보다, `busy` 가 200 에 닿는 동시성을 먼저 찾아두는 편이 낫다. 그 값이 해당 스레드 수에서 유효한 부하 상한이 되고, 그때 caller 쪽 지표가 어떤 모양인지도 같이 기록된다. 이후 500 으로 올려 천장이 따라 움직이는 걸 확인하면, **"주입한 지연"과 "upstream 큐잉"을 구분할 근거**가 생긴다.

### caller 풀 설정

측정 대상이다. 실험 조건이 전부 여기 걸리므로 설정값을 하나도 코드에 박지 않는다.

```java
@ConfigurationProperties(prefix = "pool")
public record PoolProperties(
        String upstreamBaseUrl,
        int maxTotal,
        int maxPerRoute,
        long connectionRequestTimeoutMs,
        long connectTimeoutMs,
        long responseTimeoutMs,
        long socketTimeoutMs,
        long validateAfterInactivityMs,
        long evictIdleMs,
        long timeToLiveMs,
        boolean retryEnabled
) {
}
```

```yaml
pool:
  # 0 이하 = 설정하지 않음 -> httpclient5 기본값 perRoute 5 / total 25
  max-total: ${POOL_MAX_TOTAL:50}
  max-per-route: ${POOL_MAX_PER_ROUTE:50}
  # 음수 = 무한 대기
  connection-request-timeout-ms: ${POOL_CONNECTION_REQUEST_TIMEOUT_MS:3000}
  # 음수 = 설정하지 않음 -> 매니저가 2초로 채운다
  validate-after-inactivity-ms: ${POOL_VALIDATE_AFTER_INACTIVITY_MS:-1}
  evict-idle-ms: ${POOL_EVICT_IDLE_MS:-1}
  retry-enabled: ${POOL_RETRY_ENABLED:false}
```

**"설정하지 않음"과 "0/무한으로 설정함"을 구분하는 게 이 실험의 전제다.** 2번은 *안 건드렸을 때* 기본값에 막히는 걸 봐야 하고, 7번은 *명시적으로 무한*으로 뒀을 때를 봐야 한다. 둘을 같은 값으로 표현하면 두 실험이 섞인다. 그래서 음수를 "안 건드림"으로 약속하고 분기한다.

```java
@Bean
public PoolingHttpClientConnectionManager connectionManager(PoolProperties props) {
    ConnectionConfig.Builder connectionConfig = ConnectionConfig.custom()
            .setConnectTimeout(Timeout.ofMilliseconds(props.connectTimeoutMs()))
            .setSocketTimeout(Timeout.ofMilliseconds(props.socketTimeoutMs()));

    // 음수면 아예 안 건드린다 -> 매니저가 null 을 보고 2초로 채운다 (resolveValidateAfterInactivity)
    if (props.validateAfterInactivityMs() >= 0) {
        connectionConfig.setValidateAfterInactivity(TimeValue.ofMilliseconds(props.validateAfterInactivityMs()));
    }
    if (props.timeToLiveMs() >= 0) {
        connectionConfig.setTimeToLive(TimeValue.ofMilliseconds(props.timeToLiveMs()));
    }

    PoolingHttpClientConnectionManagerBuilder builder = PoolingHttpClientConnectionManagerBuilder.create()
            .setDefaultConnectionConfig(connectionConfig.build())
            .setDefaultSocketConfig(SocketConfig.custom().setTcpNoDelay(true).build());

    // 0 이하로 두면 builder 가 덮어쓰지 않는다 -> 라이브러리 기본값 perRoute 5 / total 25 (가설 2)
    if (props.maxTotal() > 0) {
        builder.setMaxConnTotal(props.maxTotal());
    }
    if (props.maxPerRoute() > 0) {
        builder.setMaxConnPerRoute(props.maxPerRoute());
    }
    return builder.build();
}

@Bean
public CloseableHttpClient httpClient(PoolingHttpClientConnectionManager manager, PoolProperties props) {
    RequestConfig.Builder requestConfig = RequestConfig.custom()
            .setResponseTimeout(props.responseTimeoutMs(), TimeUnit.MILLISECONDS);

    // 음수면 무한 대기 (가설 7 의 "포기가 없는" 쪽)
    if (props.connectionRequestTimeoutMs() >= 0) {
        requestConfig.setConnectionRequestTimeout(props.connectionRequestTimeoutMs(), TimeUnit.MILLISECONDS);
    } else {
        requestConfig.setConnectionRequestTimeout(Timeout.DISABLED);
    }

    var clientBuilder = HttpClients.custom()
            .setConnectionManager(manager)
            .setConnectionManagerShared(true)
            .setDefaultRequestConfig(requestConfig.build());

    if (!props.retryEnabled()) {
        clientBuilder.disableAutomaticRetries();   // 가설 10 — 기본값은 멱등 요청을 1회 재시도한다
    }
    if (props.evictIdleMs() >= 0) {
        clientBuilder.evictIdleConnections(TimeValue.ofMilliseconds(props.evictIdleMs()));
    }
    return clientBuilder.build();
}

@Bean
public PoolingHttpClientConnectionManagerMetricsBinder poolMetrics(PoolingHttpClientConnectionManager manager,
                                                                  MeterRegistry registry) {
    PoolingHttpClientConnectionManagerMetricsBinder binder =
            new PoolingHttpClientConnectionManagerMetricsBinder(manager, "caller-pool");
    binder.bindTo(registry);
    return binder;
}
```

`setConnectionManagerShared(true)` 를 주지 않으면 `CloseableHttpClient` 를 닫을 때 매니저까지 닫혀서, 매니저를 빈으로 들고 지표를 붙이는 구성과 충돌한다.

**설정값을 조회해도 실제 적용값은 안 보인다.** 기동 로그에 매니저 상태를 찍어보면 이렇게 나온다.

```
pool: maxTotal=50, maxPerRoute=50, validateAfterInactivity=null
```

`null` 은 "검증을 안 한다"가 아니다. `getValidateAfterInactivity()` 는 `ConnectionConfig.DEFAULT` 를 읽어서 미설정 그대로인 null 을 돌려주는데, 실제 적용값은 lease 시점에 `resolveValidateAfterInactivity` 가 **2초**로 채운다. 설정 조회만 보고 "검증이 꺼져 있네"로 읽으면 9번이 왜 재현되는지 설명이 안 된다.

### 지표

| 지표 | 소스 | 보는 이유 |
| --- | --- | --- |
| `httpcomponents.httpclient.pool.total.pending` | Micrometer `PoolingHttpClientConnectionManagerMetricsBinder` | **대기 큐 길이.** 풀 상한이 무엇을 미루고 있는지가 여기 보인다 |
| `...pool.total.leased` / `available` / `max` | 〃 | 실제로 몇 개를 쓰고 있는지 |
| `tomcat.threads.busy` (caller) | actuator | 소켓 점유가 스레드 점유로 옮겨갔는지 |
| `tomcat.threads.busy` (upstream) | actuator | **매 회차 유효성 검사.** `threads.max` 에 닿으면 그 회차는 버린다 |
| `http.client.requests` | Micrometer | TPS·응답시간 분포 |
| ESTABLISHED / TIME_WAIT 수 | `ss -tn state established dst ... \| wc -l` | 커넥션이 실제로 재사용되는지 |

- **scrape 주기는 1s.** 기본 15s 면 `pending` 같은 순간 지표가 전부 뭉개진다.
- **첫 30~60초는 버린다.** JIT warmup 구간이다.
- **ESTABLISHED 는 `/proc/net/tcp` 에서 읽는다.** `eclipse-temurin` 이미지에는 `ss` 도 `netstat` 도 없다. `$2` 가 local(8080 = `1F90`), `$3` 이 remote, `$4` 가 상태(`01` = ESTABLISHED)다. prometheus 도 같은 포트를 긁으므로 toxiproxy 에서 온 것만 세야 한다.

#### 풀 게이지는 커널이 아니라 풀의 장부다

`available` · `leased` 가 어디서 나오는 값인지는 짚고 가야 한다. 소켓 상태를 조회하는 게 아니라 **풀 내부 자료구조의 `size()`** 다.

```
Gauge(httpcomponents.httpclient.pool.total.connections{state="available"})
  → ConnPoolControl.getTotalStats()      // PoolingHttpClientConnectionManager → StrictConnPool
  → PoolStats.getAvailable()
```

`StrictConnPool.getTotalStats()` 는 풀의 `ReentrantLock` 을 잡고 아래를 세서 `PoolStats` 를 새로 만들어 돌려준다.

| 지표 | 실제로 세는 것 |
| --- | --- |
| `leased` | `leased` **Set** 의 `size()` — 빌려주고 아직 반납 안 된 `PoolEntry` 개수 |
| `available` | `available` **LinkedList** 의 `size()` — 풀에 놀고 있는 `PoolEntry` 개수 |
| `pending` | `pendingRequests` 를 순회하며 `isDone()` 아니고 deadline 안 지난 것만 카운트 |
| `max` | `maxTotal` 필드 — 측정값이 아니라 설정값 그대로 |

여기서 두 가지가 따라온다.

**장부는 실제 TCP 상태와 얼마든지 어긋난다.** 0번에서 `leased=50` 이 남은 게 그 예다. `PoolEntry` 50개가 `leased` Set 에 들어간 채 아무도 release 를 안 불렀다는 뜻이고, 그 소켓이 살았는지 죽었는지는 풀이 모른다. `/proc/net/tcp` 를 따로 세는 건 이 장부를 교차검증하기 위해서다. 0번에서는 50/50 으로 일치했지만 **9~11번에서는 갈라진다** — 서버가 FIN 을 보내도 장부의 `available` 은 그대로다.

**pull 방식이라 스크레이프 시점의 순간값이다.** `Gauge.builder(name, obj, fn)` 로 등록된 `ToDoubleFunction` 은 수집 시점에 호출된다. 스크레이프 사이에 일어난 스파이크는 존재하지 않았던 게 된다. 1s 로 내려도 그보다 짧은 `pending` 스파이크는 여전히 놓치므로, 3번·8번처럼 대기 큐를 봐야 하는 실험은 부하를 충분히 오래 유지해 **스파이크가 아니라 정상 상태로** 만들어야 한다.

덧붙여 `getTotalStats()` 가 풀 전역 락을 잡으므로, 고동시성에서 스크레이프 주기를 더 낮추면 lease/release 와 경합한다. 1초면 무시할 수준이다.


## 실측해볼 것
---

> 각 항목은 "무엇을 바꿔서 무엇이 갈라지는가" 하나씩만 본다.

기준 조건은 `delayMs=50`, RTT 10ms, `sizeBytes=0`, 풀 50 이다. 각 실험은 여기서 **한 가지만** 바꾼다.

**0번이 나머지의 전제다.** 본문을 안 읽고 버리면 HttpClient5 는 재사용 대신 커넥션을 닫아버려서, 풀을 아무리 키워도 매번 새 커넥션이 된다. `ResponseEntity<Void>` 로 받거나 에러 경로에서 본문을 안 읽는 코드가 대표적이다. 이게 깨져 있으면 아래 전부가 같은 결과를 낸다.

| # | 가설 | 가르는 방법 |
| --- | --- | --- |
| 0 | 응답 본문을 끝까지 소비해야 커넥션이 풀로 반환된다 | 본문을 읽는 경우 vs 버리는 경우의 `leased` 반환 |

### 정상 구간 — `delayMs=50`

| # | 가설 | 가르는 방법 |
| --- | --- | --- |
| 1 | 정상 구간에서 풀의 이득은 **재사용 축에서만** 나온다 | 재사용 O/X × 상한 O/X 2×2 |
| 2 | 설정 안 하면 `maxPerRoute` 5 에 막힌다 (total 만 올려도 소용없다) | total 200 / perRoute 미설정 vs 둘 다 설정 |
| 3 | 필요 커넥션 수는 TPS × 응답시간으로 예측된다 | 풀 1 / 0.5배 / 1배 / 2배 / 10배 에서 TPS 비교 |
| 4 | 재사용 이득 = RTT × 왕복수 (+ slow start 회피) | RTT 0/10/50ms × http/https × `sizeBytes` 0/100KB |
| 5 | keep-alive off 면 풀은 동시성 상한으로만 남는다 | `close=true` 로 두고 TPS·`leased` 비교 |
| 6 | 풀이 스레드풀보다 작으면 초과분은 전부 큐에서 잔다 | 톰캣 200 / 풀 50, 부하를 풀 상한 위로 올리고 `pending` 관측 |

### 장애 구간 — `delayMs=3000`

| # | 가설 | 가르는 방법 |
| --- | --- | --- |
| 7 | 풀 상한만으로는 bulkhead 가 안 된다 | `connectionRequestTimeout` 무한 vs 200ms 에서 caller `threads.busy` 비교 |
| 8 | 풀이 없으면 소켓이 무한히 는다 | ESTABLISHED / TIME_WAIT 추이 |

### idle 구간

| # | 가설 | 가르는 방법 |
| --- | --- | --- |
| 9 | 서버 keepAliveTimeout < 클라 `validateAfterInactivity` 면 그 사이가 사각지대다 | upstream `keep-alive-timeout=1000`, 클라 검증 2초(기본), 1.5초 쉬었다 요청 |
| 10 | 자동 재시도가 stale 실패를 감춘다 | 9번 조건에서 재시도 on/off |
| 11 | 풀은 자기가 들고 있는 커넥션이 죽은 걸 모른다 | `pool.total.available` vs CLOSE_WAIT 개수 |
| 12 | 요청 수 상한은 알려주고 닫으므로 stale 을 만들지 않는다 | `maxKeepAliveRequests=5`, 5번째 응답 헤더 확인 |

## 각 항목 보충
---

### 0번 — 확인됨

실습 코드는 [blog-code-practice/traffic/http-connection-pool](https://github.com/zz9z9/blog-code-practice/tree/master/traffic/http-connection-pool) 에 있다. 풀 설정은 `maxTotal=50` · `maxPerRoute=50` · `connectionRequestTimeout=3s`, 요청은 순차 60회.

caller 에 두 경로를 둔다. 하나는 본문을 끝까지 읽고 응답을 닫고, 하나는 응답 객체를 그냥 버린다.

```java
if (consume) {
    try (CloseableHttpResponse response = httpClient.execute(request)) {
        EntityUtils.consume(response.getEntity());   // 여기서 커넥션이 풀로 돌아간다
        return ResponseEntity.ok("upstream=" + response.getCode());
    }
}
// 본문을 소비하지도, 응답을 닫지도 않는다
CloseableHttpResponse leaked = httpClient.execute(request);
```

결과는 이렇게 갈렸다.

| | 성공/실패 | `available` | `leased` | upstream ESTABLISHED |
| --- | --- | --- | --- | --- |
| 본문 소비 | 60 / 0 | 1 | 0 | **1** |
| 응답 폐기 | 50 / 10 | 0 | **50** | **50** |

순차 요청인데도 소비하지 않은 쪽은 커넥션이 **60개 요청에 50개**까지 늘었다. 동시성이 1인데 커넥션이 50개 열린 것이다. 그리고 `maxTotal` 인 50 을 채운 **51번째 요청부터** `ConnectionRequestTimeoutException` 으로 떨어졌다 — 반납이 없으니 3초를 기다려도 빌릴 커넥션이 없다.

`leased=50` 이 그대로 남아 있는 게 핵심이다. 풀은 이 커넥션들이 이미 쓸모없다는 걸 모르고 "빌려준 상태"로 세고 있다. 풀 사이즈를 아무리 키워도 **고갈 시점이 뒤로 밀릴 뿐**이라, 이 경로가 열려 있으면 1~12번이 전부 같은 결과(요청 수만큼 커넥션 증가)를 낸다.

### 1번 — "풀 사용 vs 미사용"은 축이 두 개다

'풀 없음'이라고 할 때 실제로 없어지는 건 두 가지다. **커넥션 재사용**과 **동시성 상한**. 둘을 붙여놓고 비교하면 어느 쪽 기여분인지 갈리지 않으므로 2×2 로 돌린다.

| | 상한 있음 (풀 50) | 상한 없음 (풀 10000) |
| --- | --- | --- |
| 재사용 O | **기준선** | 상한만 없음 |
| 재사용 X (`close=true`) | 세마포어로 격하 (5번) | **'풀 없음'** |

정상 구간에서는 **상한 축이 아무 일도 하지 않는다.** 부하가 상한 밑이면 lease 대기가 안 생기기 때문이다. 즉 여기서 갈리는 건 재사용 축뿐이고, 상한 축은 장애 구간(7·8번)에서만 갈린다. 두 구간을 나눠 돌려야 결과 해석이 섞이지 않는다.

재사용 축에서 예측되는 값(RTT 10ms 기준):

| | 요청당 응답시간 | 기준선 대비 |
| --- | --- | --- |
| 재사용 O | 50ms | — |
| 재사용 X, HTTP | 50 + 10 = 60ms | +20% |
| 재사용 X, HTTPS (TLS 1.3) | 50 + 20 = 70ms | +40% |

동시성이 고정이면 TPS 는 응답시간에 반비례하므로, HTTPS 에서 재사용을 잃으면 **같은 커넥션 수로 TPS 가 30% 가까이 깎인다.**

응답시간보다 큰 비용이 따로 있다. 재사용이 없으면 요청마다 소켓을 새로 열고 닫으므로, 정상 상태 TIME_WAIT 이 **TPS × 60초** 로 쌓인다. 200 TPS 면 12,000 개다. 응답시간 차이는 20% 지만 이쪽은 포트 고갈로 이어지는 축이라, 정상 구간이라고 해서 풀 없이 굴러가는 게 아니라는 걸 이 지표가 보여준다.

### 2번 — 기본값은 확인해뒀다

httpclient5 5.3.1 바이트코드 기준 `PoolingHttpClientConnectionManager` 기본값은 perRoute **5** / total **25** 고, `PoolingHttpClientConnectionManagerBuilder` 는 값이 0보다 클 때만 덮어쓴다. 단일 업스트림이면 route 가 하나뿐이라 total 을 200으로 줘도 **5에 막힌다.**

### 3번과 7번 — "잘못 설정"의 두 방향

3번은 풀이 너무 작아서 자원이 여유로운데 못 쓰는 쪽(초안의 두 번째 '상방'), 7번은 상한은 있는데 **포기가 없는** 쪽이다.

커넥션을 못 빌리면 스레드가 lease 대기에서 블록된다. `connectionRequestTimeout` 이 없으면 **소켓 점유가 스레드 점유로 바뀔 뿐**이라, 업스트림 하나가 느려질 때 그 업스트림을 안 쓰는 API 까지 같이 죽는다. 상한이 bulkhead 가 되려면 "못 빌리면 포기한다"가 같이 있어야 한다.

### 4번 — 숫자가 먼저 예측된다

재사용으로 빠지는 건 커넥션 수립 왕복이다.

| | 왕복 수 | RTT 30ms 일 때 |
| --- | --- | --- |
| HTTP | TCP 1 RTT | 30ms |
| HTTPS (TLS 1.3) | TCP 1 + TLS 1 = 2 RTT | 60ms |
| HTTPS (TLS 1.2) | TCP 1 + TLS 2 = 3 RTT | 90ms |

"https 일수록 이득이 큰가"의 답은 **RTT × 왕복수**라 환경이 정한다. 같은 DC(RTT 0.5ms)면 HTTPS 라도 1.5ms 라 무시할 만하고, 인터넷 구간이면 요청당 90ms 다. `sizeBytes` 를 같이 돌리면 여기에 slow start 회피분이 얹히는 것까지 갈라진다.

### 9~12번 — stale connection 은 기본값 조합만으로 난다

**기본 설정 그대로 돌리면 아무것도 안 보인다.** HttpClient5 가 세 겹으로 막고 있다. httpclient5 5.3.1 바이트코드 기준:

| 방어 | 기본값 | 효과 |
| --- | --- | --- |
| `validateAfterInactivity` | **2초** — `ConnectionConfig` 에 미설정이면 `resolveValidateAfterInactivity` 가 null 일 때 2초로 채운다 | idle 2초 넘은 커넥션은 lease 직전에 stale 체크 |
| `evictIdleConnections` | 꺼짐 (빌더에서 호출해야 켜진다) | — |
| 자동 재시도 | `DefaultHttpRequestRetryStrategy` maxRetries **1**, interval 1s | 아래 참조 |

세 번째가 핵심이다. 비재시도 예외 목록에는 `InterruptedIOException` · `UnknownHostException` · `ConnectException` · `NoRouteToHostException` 만 있고 **`NoHttpResponseException` 과 connection reset 은 없다.** GET 은 멱등이라 죽은 커넥션에 걸려도 조용히 한 번 재시도해서 성공한다. "재현이 안 되네"의 정체가 이것이다 (10번).

**사각지대는 방어를 끄지 않아도 생긴다.** 서버 keepAliveTimeout 을 클라이언트 검증 주기보다 짧게 두면 그 사이 구간이 통째로 빈다.

```
upstream:  server.tomcat.keep-alive-timeout=1000    # 1초 뒤 서버가 FIN
caller:    validateAfterInactivity = 2초 (기본값, 안 건드린다)
           .disableAutomaticRetries()               # 이것만 끈다 — 증상을 보기 위해
```

요청 1회 → **1.5초 대기** → 요청 1회. 이 커넥션은 1초 시점에 이미 죽었지만 idle 이 2초를 안 넘었으므로 검증도 안 한다.

서버 FIN 을 받은 클라이언트 소켓은 CLOSE_WAIT 이고, **half-close 라 쓰기는 성공한다.** 요청은 그대로 나가고, 이미 완전히 닫힌 서버 소켓이 RST 로 답한다. 클라이언트는 쓰기 성공 후 읽기에서 터진다 — `NoHttpResponseException` 또는 `SocketException: Connection reset`. tcpdump 로 `FIN → PSH(요청) → RST` 순서를 그대로 찍을 수 있다.

**풀은 죽은 걸 모른다** (11번). 에러를 잡는 것보다 이 대비가 볼 만하다.

```bash
ss -tan state close-wait dst <upstream>:8080 | wc -l
```

이 값과 `httpcomponents.httpclient.pool.total.available` 을 같이 찍으면, 풀이 "빌려줄 수 있다"고 세는 커넥션 중 몇 개가 이미 시체인지 갈린다. 풀은 빌려주려고 시도하기 전까지 모른다.

**시간 상한과 요청 수 상한은 다르다** (12번). "keep-alive 를 잘못 설정한다"의 핵심이 여기다.

| | 닫는 방식 | 클라이언트가 아는가 |
| --- | --- | --- |
| `maxKeepAliveRequests` (톰캣 기본 100) | 마지막 응답에 `Connection: close` 를 붙이고 닫는다 | **안다.** 안전하다 |
| `keepAliveTimeout` | 예고 없이 FIN | **모른다.** 여기서만 stale 이 난다 |

요청 수 상한은 아무리 낮춰도 stale 을 만들지 않는다. 응답 헤더를 확인하면 실측으로 갈린다.

**해소 검증은 "0이 됐다"가 아니다.** 대소관계를 맞춰도(클라 검증·eviction 주기 < 서버 keepAliveTimeout) 에러율이 0 이 되진 않는다. stale 체크는 non-blocking peek 이라 **체크 시점엔 FIN 이 아직 안 왔고 직후에 도착하는 창**이 남는다. 그래서 검증 기준은 "사각지대의 결정적 실패가 사라지고 잔여 확률적 에러율만 남았다" 여야 한다. 이 잔여분이 멱등 요청 재시도가 필요한 이유이기도 하다.

## 나중 단계로 미뤄둘 것
---

- **upstream 플랫폼 스레드 vs 가상 스레드** — 7번에서 caller 쪽에 보이는 "소켓 점유 → 스레드 점유" 가 서버 쪽에서 반복되는 그림이라, 짝지어 보면 한 바퀴 돈다.
- **지연에 지터 주기** — 평균 지연으로 계산한 Little's law 는 응답시간에 꼬리가 있으면 필요 커넥션을 **과소평가**한다. 3번에서 고정 지연으로 예측이 맞는 걸 먼저 보인 다음에 깨야 의미가 산다.
