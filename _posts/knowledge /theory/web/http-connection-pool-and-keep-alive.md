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


## 실측해볼 것
---

> 각 항목은 "무엇을 바꿔서 무엇이 갈라지는가" 하나씩만 본다.

기준 조건은 `delayMs=50`, RTT 20ms, `sizeBytes=0`, 풀 50, VU 50 고정, 30초다. 각 실험은 여기서 **한 가지만** 바꾼다. 워밍업 15초는 버린다.

| # | 가설 | 구간 | 결과 |
| --- | --- | --- | --- |
| 0 | 응답 본문을 끝까지 소비해야 커넥션이 풀로 반환된다 | 전제 | 확인 |
| 1 | 정상 구간에서 풀의 이득은 재사용 축에서만 나온다 | 정상 | 확인 |
| 2 | 설정 안 하면 `maxPerRoute` 5 에 막힌다 | 정상 | 확인 |
| 3 | 필요 커넥션 수는 TPS × 응답시간으로 예측된다 | 정상 | 확인 |
| 4 | 재사용 이득 = RTT × 왕복수 (+ slow start 회피) | 정상 | 확인. https 가 3.4배 |
| 5 | keep-alive off 면 풀은 동시성 상한으로만 남는다 | 정상 | 확인 |
| 6 | 풀이 스레드풀보다 작으면 초과분은 큐에서 잔다 | 정상 | 확인 |
| 7 | 풀 상한만으로는 bulkhead 가 안 된다 | 장애 | 확인 |
| 8 | 풀이 없으면 소켓이 무한히 는다 | 장애 | 확인 |
| 9 | 중간 장비가 말없이 끊으면 stale 커넥션에 요청이 실린다 | idle | 확인 |
| 10 | 자동 재시도가 stale 실패를 감춘다 | idle | 확인 |
| 11 | 풀은 자기가 들고 있는 커넥션이 죽은 걸 모른다 | idle | 확인 |
| 12 | 요청 수 상한은 알려주고 닫으므로 stale 을 만들지 않는다 | idle | 확인 |

9번은 원래 "서버 keepAliveTimeout < 클라 `validateAfterInactivity` 면 그 사이가 사각지대"로 적어뒀는데, 톰캣 상대로는 그 사각지대가 안 생겼다. 왜 안 생기는지가 이 글에서 가장 뜻밖이었던 부분이라 아래에 따로 적는다.

## 실측 환경
---

> 재려는 값이 수 ms 단위라, 측정 환경이 그 크기의 오차를 만들면 아무것도 갈라지지 않는다. 환경 구성의 목표는 성능이 아니라 **재려는 값보다 작은 오차**다.

### 왜 이렇게 구성하는가

**로컬 루프백만으로는 결론이 안 난다.** 루프백 RTT는 0.05ms 수준이라 핸드셰이크 생략 이득이 측정 노이즈에 묻힌다. 그렇다고 upstream에서 `Thread.sleep`을 거는 건 **핸드셰이크가 끝난 뒤 구간**이라 RTT를 흉내내지 못한다. 네트워크 레벨 지연 주입이 따로 필요하다.

**지연은 두 축으로 나눠서 건다.**

| | 주입 위치 | 핸드셰이크에 영향 | 흉내내는 것 |
| --- | --- | --- | --- |
| RTT | upstream netns 의 `tc netem` | **있다** | 물리적 거리 |
| 처리시간 | upstream `Thread.sleep` | 없다 | 상대 서버가 자기 의존성 때문에 느림 |

**중간에 프록시가 끼면 핸드셰이크 비용이 사라진다.** 처음에는 RTT 를 toxiproxy 의 latency toxic 으로 주려고 했는데, 재보니 안 된다. toxiproxy 는 TCP 프록시라 클라이언트는 toxiproxy 와 핸드셰이크를 마치고, toxiproxy 가 그 뒤에 업스트림으로 연결한다. latency toxic 은 오가는 **데이터**를 늦출 뿐이라 커넥션 수립 비용은 그대로 빠진다.

upstream netns 에 `tc qdisc ... netem delay 5ms` 를 걸어두고 같은 네트워크 안에서 재보면 이렇게 갈린다.

| 경로 | `time_connect` | `time_starttransfer` |
| --- | --- | --- |
| upstream 직접 | **6.0ms** | 12.6ms |
| toxiproxy 경유 | **0.9ms** | 13.9ms |

데이터 경로 지연(ttfb)은 양쪽에 다 실리는데 커넥션 수립 비용만 사라진다. 그래서 RTT 는 `tc netem` 으로 걸고, **재사용을 재는 실험에서는 toxiproxy 를 경로에서 뺀다.**

같은 이유로 **호스트에서 재면 안 된다.** macOS 에서 published port 로 재면 Docker 의 포트 포워더가 먼저 연결을 받아버려서, netem 을 걸어둬도 `time_connect` 가 0.2ms 로 나온다. 포워더도 프록시라 똑같이 가린다.

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
k6 ──▶ caller:8080 ──▶ upstream:8080       (http)   전부 같은 브리지 네트워크
                   └─▶ upstream-tls:8443  (https, 4번 전용)
                         ▲   ▲
       (stale 실험        │   └─ netem: 각 upstream 의 netns 에 egress 지연
        에서만)            │
            toxiproxy ────┘
```

기본 경로에 toxiproxy 는 없다. RTT 를 netem 이 맡으면서 남은 역할이 "말없이 끊기" 뿐인데, 경로에 끼워두면 위에서 본 것처럼 핸드셰이크 비용이 가려진다. 9·10·11번에서만 `UPSTREAM_BASE_URL` 을 toxiproxy 로 돌린다.

| 컨테이너 | cpus | 역할 |
| --- | --- | --- |
| caller | 2 | 측정 대상. HttpClient5 풀 |
| upstream | 2 | 병목이 되면 안 된다 |
| upstream-tls | 2 | 같은 jar 를 TLS 로만 띄운 것. 4번에서 http 와 나란히 잰다 |
| k6 | 2 | 부하 생성기가 병목이면 TPS가 거짓말이 된다 |
| netem | — | upstream 의 netns 를 공유하는 사이드카. `NET_ADMIN` 으로 qdisc 만 걸고 끝난다 |
| toxiproxy | 1 | 통보 없이 끊는 중간 장비. 기본 경로 밖 |

풀 설정은 전부 env var로 뺀다(`@ConfigurationProperties`). 실험 조건 변경이 이미지 재빌드 없이 `docker compose up -d --force-recreate` 로 끝난다. jar는 bind-mount 하고 이미지는 `eclipse-temurin:21-jre` 로 고정한다.

`--force-recreate` 에는 함정이 하나 있다. compose 는 **매번 현재 셸 환경으로 서비스 정의를 다시 계산**해서, `caller` 만 다시 만들려고 해도 의존 서비스인 `upstream` 을 기본값으로 되돌려 만든다. 실험 조건을 셸에 export 해두고 여러 회차를 돌리면 중간부터 조용히 다른 조건이 된다. 조건은 실험 스크립트 안에서 고정해야 한다.

### 역할 분담

| | 담당 | 예 |
| --- | --- | --- |
| upstream 앱 | **HTTP 레벨** — 응답 내용·시간·헤더 | 지연, 본문 크기, 상태 코드, `Connection: close` |
| netem | **패킷 레벨** — 지연·손실 | RTT |
| toxiproxy | **TCP 레벨** — 통보 없는 커넥션 종료 | 프록시를 껐다 켜서 말없이 끊기 (9·10·11번) |

앱은 정상적인 HTTP 응답만 만든다. 톰캣으로는 "말없이 끊기"가 안 되기 때문에 toxiproxy 가 필요하다. 톰캣은 끊을 때 `Connection: close` 를 붙여 **알려주고** 끊는다(12번). 클라이언트가 모르는 채로 죽은 커넥션을 쥐고 있는 상황은 경로 중간에서 통보 없이 끊어줄 무언가가 있어야 만들어진다.

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

**"설정하지 않음"과 "0/무한으로 설정함"을 구분하는 게 이 실험의 전제다.** 2번은 *안 건드렸을 때* 기본값에 막히는 걸 봐야 하고, 7번은 *명시적으로 무한*으로 뒀을 때를 봐야 한다. 둘을 같은 값으로 표현하면 두 실험이 섞인다. 그래서 음수를 "안 건드림"으로 약속한다.

빈 설정은 이렇다. 어떤 값이 걸리는지 보이도록 그 분기는 걷어낸 것이고, **실제 코드는 각 `setXxx` 앞에 "음수면 이 줄을 호출하지 않는다" 가 붙는다**([원본](https://github.com/zz9z9/blog-code-practice/blob/master/traffic/http-connection-pool/caller/src/main/java/com/zz9z9/blogcode/traffic/httpconnectionpool/caller/HttpClientConfig.java)). 호출을 건너뛰어야 라이브러리 기본값이 그대로 남기 때문이다.

```java
@Bean
public PoolingHttpClientConnectionManager connectionManager(PoolProperties props) {
    ConnectionConfig connectionConfig = ConnectionConfig.custom()
            // TCP 연결 수립까지 기다리는 한도
            .setConnectTimeout(Timeout.ofMilliseconds(props.connectTimeoutMs()))
            // 소켓 read 한도
            .setSocketTimeout(Timeout.ofMilliseconds(props.socketTimeoutMs()))
            // 이 시간 이상 논 커넥션은 재사용 직전에 살아있는지 검증한다 (미설정 시 2초, 9번)
            .setValidateAfterInactivity(TimeValue.ofMilliseconds(props.validateAfterInactivityMs()))
            // 커넥션 최대 수명. 멀쩡해도 이 시간이 지나면 버린다
            .setTimeToLive(TimeValue.ofMilliseconds(props.timeToLiveMs()))
            .build();

    return PoolingHttpClientConnectionManagerBuilder.create()
            .setDefaultConnectionConfig(connectionConfig)
            .setDefaultSocketConfig(SocketConfig.custom().setTcpNoDelay(true).build())
            // 풀 전체 상한 (미설정 시 25)
            .setMaxConnTotal(props.maxTotal())
            // 라우트(scheme+host+port)별 상한. 실제 병목은 여기다 (미설정 시 5, 2번)
            .setMaxConnPerRoute(props.maxPerRoute())
            .build();
}

@Bean
public CloseableHttpClient httpClient(PoolingHttpClientConnectionManager manager, PoolProperties props) {
    RequestConfig requestConfig = RequestConfig.custom()
            // 풀에서 커넥션을 빌리려고 기다리는 한도. 상한을 bulkhead 로 만드는 값 (7번)
            .setConnectionRequestTimeout(props.connectionRequestTimeoutMs(), TimeUnit.MILLISECONDS)
            // 요청을 보낸 뒤 응답을 기다리는 한도
            .setResponseTimeout(props.responseTimeoutMs(), TimeUnit.MILLISECONDS)
            .build();

    return HttpClients.custom()
            .setConnectionManager(manager)
            // 이걸 빼면 클라이언트를 닫을 때 매니저까지 닫힌다
            .setConnectionManagerShared(true)
            .setDefaultRequestConfig(requestConfig)
            // 유휴 커넥션을 백그라운드로 청소하는 주기
            .evictIdleConnections(TimeValue.ofMilliseconds(props.evictIdleMs()))
            // 기본값은 멱등 요청을 1회 재시도한다. 끄면 실패가 그대로 보인다 (10번)
            .disableAutomaticRetries()
            .build();
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

**여기서 안 건드린 설정이 하나 있다.** `setKeepAliveStrategy` 는 기본값으로 뒀는데, 9번이 예측대로 재현되지 않은 원인이 이것이었다. 커넥션을 풀에 얼마나 두고 재사용할지는 위의 어떤 값도 아니고 이 전략이 응답마다 정한다.

```java
// DefaultConnectionKeepAliveStrategy (기본값)
public TimeValue getKeepAliveDuration(HttpResponse response, HttpContext context) {
    // 1. 응답의 Keep-Alive: timeout=N 을 그대로 따른다
    for (HeaderElement he : iterate(response, "keep-alive")) {
        if ("timeout".equalsIgnoreCase(he.getName()) && he.getValue() != null) {
            return TimeValue.ofSeconds(Long.parseLong(he.getValue()));
        }
    }
    // 2. 헤더가 없으면 RequestConfig.connectionKeepAlive -> 기본 3분
    return clientContext.getRequestConfigOrDefault().getConnectionKeepAlive();
}
```

이 값이 `MainClientExec` 에서 `markConnectionReusable(userToken, duration)` 으로 넘어가 풀 엔트리의 만료 시각이 된다. 그래서 **커넥션의 수명은 서버가 정하고, 클라이언트는 서버가 말이 없을 때만 자기 값을 쓴다.**

| 상대 | 풀이 잡는 유효기간 |
| --- | --- |
| `Keep-Alive: timeout=N` 을 주는 서버 | N초 |
| 헤더를 안 주는 서버·프록시 | **3분** (`RequestConfig.connectionKeepAlive` 기본값) |

두 번째 줄이 위험한 쪽이다. 상대가 60초에 조용히 끊어도 풀은 3분을 들고 있으므로, 그 사이의 방어선은 `validateAfterInactivity` 하나뿐이다. 9번이 그 상황이다.

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
| ESTABLISHED / TIME_WAIT / CLOSE_WAIT 수 | `/proc/net/tcp` (아래 참조) | 풀이 센 값과 맞는지 |

- **scrape 주기는 1s.** 기본 15s 면 `pending` 같은 순간 지표가 전부 뭉개진다.
- **첫 30~60초는 버린다.** JIT warmup 구간이다.
- **ESTABLISHED 는 `/proc/net/tcp` 에서 읽는다.** `eclipse-temurin` 이미지에는 `ss` 도 `netstat` 도 없다. `$2` 가 local(8080 = `1F90`), `$3` 이 remote, `$4` 가 상태(`01` = ESTABLISHED)다. prometheus 도 같은 포트를 긁으므로 caller 에서 온 것만 골라야 한다.

#### 풀 게이지는 소켓이 아니라 자바 객체를 센다

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

**이 숫자는 실제 TCP 상태와 얼마든지 어긋난다.** 0번에서 `leased=50` 이 남은 게 그 예다. `PoolEntry` 50개가 `leased` Set 에 들어간 채 아무도 release 를 안 불렀다는 뜻이고, 그 소켓이 살았는지 죽었는지는 풀이 모른다. `/proc/net/tcp` 를 따로 세는 건 풀이 센 값을 커널 쪽과 맞춰보기 위해서다. 0번에서는 50/50 으로 일치했지만 **9~11번에서는 갈라진다** — 서버가 FIN 을 보내도 풀이 센 `available` 은 그대로다.

**pull 방식이라 스크레이프 시점의 순간값이다.** `Gauge.builder(name, obj, fn)` 로 등록된 `ToDoubleFunction` 은 수집 시점에 호출된다. 스크레이프 사이에 일어난 스파이크는 존재하지 않았던 게 된다. 1s 로 내려도 그보다 짧은 `pending` 스파이크는 여전히 놓치므로, 3번·8번처럼 대기 큐를 봐야 하는 실험은 부하를 충분히 오래 유지해 **스파이크가 아니라 정상 상태로** 만들어야 한다.

덧붙여 `getTotalStats()` 가 풀 전역 락을 잡으므로, 고동시성에서 스크레이프 주기를 더 낮추면 lease/release 와 경합한다. 1초면 무시할 수준이다.


## 결과
---

### 0번 — 본문을 소비해야 반납된다

일부러 이상하게 짠 코드가 아니라, **정상 경로에만 `close` 가 있고 에러 경로는 상태코드만 보고 빠져나가는** 흔한 형태다.

```java
// leaky — 에러면 본문을 안 읽고 그냥 나간다
CloseableHttpResponse response = httpClient.execute(request);

if (response.getCode() >= 400) {
    log.warn("업스트림 에러: {}", response.getCode());
    return ResponseEntity.status(502).body("upstream=" + response.getCode());
}

String body = EntityUtils.toString(response.getEntity());
response.close();
return ResponseEntity.ok(...);
```

```java
// safe — try-with-resources 로 감싸면 어느 경로로 나가든 소비하고 닫는다
try (CloseableHttpResponse response = httpClient.execute(request)) {
    EntityUtils.consume(response.getEntity());
    ...
}
```

순차 60회. `available`·`leased` 는 풀이 센 값이고, 그 오른쪽은 같은 시점 caller 의 `/proc/net/tcp` 다.

| 조건 | 성공 | 첫 실패 | available | leased | ESTABLISHED | CLOSE_WAIT |
| --- | --- | --- | --- | --- | --- | --- |
| leaky + 정상(200) | 60/60 | 없음 | 1 | 0 | 1 | 0 |
| leaky + 404 | 50/60 | **51번째** | 0 | **50** | **50** | 0 |
| leaky + 500 | 50/60 | **51번째** | 0 | **50** | 0 | **50** |
| safe + 500 | 60/60 | 없음 | 0 | 0 | 0 | 0 |

**평소에는 아무 일도 없다.** 같은 leaky 코드인데 업스트림이 200 을 주는 동안은 커넥션 1개로 60회를 처리한다. 누수 경로는 에러 응답에서만 열린다. 배포하고 한참 뒤 업스트림 에러율이 오르는 순간 풀이 마르는 형태다.

**에러가 나기 시작하면 요청 수만큼 커넥션이 는다.** 순차 요청이라 동시성이 1인데 커넥션이 50개까지 늘고, `maxTotal` 을 채운 51번째부터 `ConnectionRequestTimeoutException` 으로 떨어진다.

**404 와 500 을 가른 건 톰캣이다.** 톰캣은 `400` 과 `5xx` 응답에 `Connection: close` 를 자동으로 붙인다(`404` 는 안 붙는다).

- **404** — 서버는 커넥션을 살려둔다. 살아 있는 커넥션 50개를 풀이 붙잡고 못 돌려준다. 순수한 누수다.
- **500** — 서버가 FIN 을 보내 닫았다. caller 소켓은 전부 `CLOSE_WAIT` 이고 살아 있는 커넥션은 **0개**다. 그런데 풀은 여전히 `leased=50` 으로 센다.

세 번째 줄이 볼 만하다. **풀이 "빌려준 상태"로 세고 있는 50개가 전부 시체다.** 풀은 `PoolEntry` 가 `leased` Set 에 있다는 것만 알지, 그 소켓이 살았는지는 반납을 받아봐야 안다. 반납이 없으므로 영원히 모른다.

### 1번 — 정상 구간에서 갈리는 건 재사용 축뿐

'풀 없음'이라고 할 때 실제로 없어지는 건 **커넥션 재사용**과 **동시성 상한** 두 가지다. 붙여놓고 비교하면 어느 쪽 기여분인지 갈리지 않으므로 2×2 로 돌린다.

| 조건 | 평균 | p95 | TPS |
| --- | --- | --- | --- |
| A 재사용 O, 상한 50 | 73.9ms | 78.7ms | 675 |
| B 재사용 O, 상한 10000 | 73.5ms | 78.1ms | 679 |
| C 재사용 X, 상한 50 | 95.2ms | 101.7ms | 524 |
| D 재사용 X, 상한 10000 | 94.9ms | 101.1ms | 526 |

**A ≈ B, C ≈ D.** 상한을 200배 늘려도 차이가 0.5% 안쪽이다. 부하가 상한 밑이면 lease 대기가 안 생기니 상한은 존재만 하고 아무 일도 하지 않는다. 상한 축은 장애 구간(7·8번)에서만 갈린다.

**갈린 폭이 RTT 와 맞는다.** 73.9 → 95.2ms, 차이 **21.3ms** 로 주입한 RTT 20ms 와 일치한다. TPS 는 675 → 524 로 22% 감소인데, 동시성이 고정이면 TPS 가 응답시간에 반비례하므로 73.9/95.2 = 0.776 과 맞아떨어진다.

#### TIME_WAIT 은 caller 에 안 쌓였다

재사용이 없으면 caller 에 TIME_WAIT 이 쌓일 거라고 봤는데, caller → upstream 커넥션의 TIME_WAIT 은 **0** 이었다.

| | caller | upstream |
| --- | --- | --- |
| caller → upstream | `SYN_SENT` 50 | `SYN_RECV` 50 |
| TIME_WAIT | 0 | 0 |

**TIME_WAIT 은 먼저 닫는 쪽에 붙는다.** 이 실험에서 재사용을 끄는 방법은 upstream 이 `Connection: close` 를 붙이는 것이었고, 그러면 능동 종료자는 **서버**다. "재사용이 없으면 TPS × 60초만큼 TIME_WAIT" 이라는 계산 자체는 맞지만, **어느 쪽에 붙는지는 누가 먼저 닫느냐가 정한다.** 클라이언트가 커넥션을 버리는 구성(풀의 TTL·eviction)이어야 클라이언트 쪽 포트 고갈로 이어진다.

`SYN_SENT`·`SYN_RECV` 가 50개씩 잡힌 것도 같이 볼 만하다. VU 50 이 전부 **핸드셰이크 중**이라는 뜻이다. C·D 에서 늘어난 21ms 가 여기 그대로 보인다.

덤으로, caller 쪽 TIME_WAIT 을 필터 없이 세면 100개쯤 잡히는데 전부 **k6 ↔ caller** 커넥션이었다. caller 의 톰캣이 `maxKeepAliveRequests` 기본값 100 에 걸려 닫고 있던 것이다 — 12번을 부하 쪽에서 우연히 먼저 본 셈이다.

### 2번 — `maxPerRoute` 5 에 막힌다

| 조건 | 실제 적용값 | 평균 | TPS | 부하 중 |
| --- | --- | --- | --- | --- |
| total 200, perRoute 미설정 | maxTotal=200, **maxPerRoute=5** | 740.7ms | 66 | leased=5 pending=45 |
| 둘 다 미설정 | maxTotal=25, **maxPerRoute=5** | 741.8ms | 66 | leased=5 pending=45 |
| total 200, perRoute 50 | maxTotal=200, maxPerRoute=50 | 73.7ms | **676** | leased=50 pending=0 |

앞의 두 줄이 **완전히 같다.** `maxTotal` 을 25 에서 200 으로 8배 늘려도 TPS 가 66 에서 66 이다. 업스트림이 하나면 route 도 하나뿐이라 `maxPerRoute` 가 먼저 걸리고, `maxTotal` 은 도달할 일이 없는 숫자다. perRoute 까지 올리면 **TPS 가 10배**가 된다.

`leased=5 pending=45` 가 그림을 그대로 보여준다. 50개 요청 중 5개만 커넥션을 잡고 45개는 큐에서 기다린다.

라이브러리 기본값은 perRoute **5** / total **25** 다(httpclient5 5.4.2, 기동 로그로 확인). `PoolingHttpClientConnectionManagerBuilder` 는 값이 0보다 클 때만 덮어쓰므로, 안 건드리면 그대로다.

### 3번 — 풀 사이즈와 TPS

VU 50 고정이므로 동시성은 항상 50 이다. 필요한 커넥션도 50 이어야 한다.

| 풀 | 평균 | TPS | leased | pending |
| --- | --- | --- | --- | --- |
| 1 | 2.91s | 16 | 1 | 49 |
| 25 | 146.2ms | 340 | 25 | 25 |
| **50** | 75.3ms | **662** | 50 | 0 |
| 100 | 74.4ms | 670 | 50 | 0 |
| 500 | 73.1ms | 682 | 50 | 0 |

**50 에서 평탄해진다.** 그 위로는 아무리 늘려도 `leased` 가 50 을 안 넘는다. 남는 커넥션은 그냥 논다.

50 아래에서는 TPS 가 풀 사이즈에 정비례한다. 요청 하나가 커넥션을 쥐는 시간이 70ms 이므로 풀 N 개의 처리량은 N/0.07 이다 — 25개면 357 예측에 실측 340, 1개면 14 예측에 실측 16. **"필요 커넥션 = TPS × 응답시간" 이 그대로 맞는다.**

풀 1 의 평균이 2.91초인 건 `connectionRequestTimeout` 3초 바로 아래다. 조금만 더 좁았으면 대기가 아니라 실패로 나타났을 것이다.

### 4번 — 재사용 이득 = 핸드셰이크 + slow start

먼저 커넥션 수립 비용을 `curl` 로 분해한다. TLS 는 1.3 으로 협상됐다.

| RTT | http `connect` | https `connect` | https `appconnect`(TLS 완료) |
| --- | --- | --- | --- |
| 0ms | 1.1ms | 0.9ms | **28.7ms** |
| 20ms | 21.5ms | 24.3ms | **66.0ms** |
| 50ms | 51.9ms | 53.7ms | **120.4ms** |

**RTT 가 0이어도 https 는 28.7ms 가 든다.** TLS 핸드셰이크는 왕복만 드는 게 아니라 비대칭키 연산이라는 CPU 비용이 따로 있다. "RTT × 왕복수" 로만 예측했던 게 여기서 틀렸다. RTT 가 붙으면 그 위에 왕복분이 더해져서, 수립 비용이 http 의 **2~3배**가 된다.

부하를 걸어 TPS 로 보면 이렇다. (RTT 20ms)

| | 재사용 O | 재사용 X | 차이 | TPS |
| --- | --- | --- | --- | --- |
| http | 73.9ms | 95.2ms | **+21.3ms** | 675 → 524 (-22%) |
| https | 73.8ms | 147.1ms | **+73.3ms** | 674 → 338 (**-50%**) |
| http, 본문 100KB | 74.1ms | 154.8ms | **+80.7ms** | 672 → 321 (-52%) |

**재사용만 되면 프로토콜이 무의미해진다.** 첫 열이 전부 74ms 다. https 든 100KB 든 커넥션이 이미 서 있으면 차이가 없다.

**재사용을 잃었을 때의 손해가 https 는 http 의 3.4배다**(73.3 / 21.3). 원래 질문이었던 "https 일수록 이득이 큰가"의 답이 이 숫자다. TPS 는 절반이 된다.

세 번째 줄이 slow start 다. 본문 0바이트일 때 재사용 상실 비용은 21.3ms(= 1 RTT, 핸드셰이크)인데, 100KB 면 80.7ms 로 는다. 늘어난 **59.4ms 는 핸드셰이크가 아니라 congestion window 를 키우는 시간**이다. RTT 20ms 로 나누면 약 3 RTT — 초기 cwnd 로는 100KB 를 한 번에 못 밀어서 세 번 더 왕복한 것이다. 같은 100KB 도 따뜻한 커넥션에서는 0.2ms 밖에 안 든다.

### 5·6번 — 재사용이 꺼져도 풀은 동시성 상한으로 남는다

| 풀 | 재사용 O | 재사용 X | 부하 중 |
| --- | --- | --- | --- |
| 5 | 732.5ms / 67 TPS | 965.1ms / 51 TPS | leased=5 pending=45 **callerThreads=51** |
| 25 | 146.2ms / 340 TPS | 187.8ms / 265 TPS | leased=25 pending=25 **callerThreads=51** |
| 50 | 75.3ms / 662 TPS | 95.2ms / 524 TPS | leased=50 pending=0 **callerThreads=51** |

**재사용이 꺼져도 TPS 는 풀 사이즈에 정비례한다.** 5:25:50 에 51:265:524 로 거의 정확히 1:5:10 이다. 재사용이라는 기능이 빠져도 **동시성 상한이라는 기능은 그대로 남는다** — 풀이 세마포어로 격하된다는 게 이 뜻이다.

6번은 맨 오른쪽 열이다. **`callerThreads` 가 풀 크기와 무관하게 항상 51 이다.** 풀이 5든 50이든 caller 톰캣 스레드 51개는 똑같이 점유된다. 풀 5 일 때 46개는 커넥션을 못 빌려 lease 대기에서 블록돼 있을 뿐이다. `leased + pending = 50` 으로 VU 수와 정확히 맞는다.

### 7·8번 — 상한만으로는 bulkhead 가 안 된다

업스트림 지연 3초, 도착률 100/s 고정. caller 에 업스트림을 **전혀 부르지 않는** `/local` 엔드포인트를 두고 같이 때린다.

> 부하를 VU 고정으로 주면 fail-fast 쪽이 훨씬 많이 쏘게 돼서 두 조건의 오퍼 부하가 달라진다. 도착률을 고정해야 비교가 선다.

| 조건 | `/call` p95 | **`/local` p95** | 실패율 | callerThreads | leased | ESTABLISHED |
| --- | --- | --- | --- | --- | --- | --- |
| CRT 60초 (사실상 무한) | 30.0s | **20.36s** | 0% | **200** | 50 | 50 |
| CRT 200ms | 3.09s | **2.28ms** | 83% | 71 | 50 | 50 |
| CRT 0 (`Timeout.DISABLED`) | 3.0s | 2.55ms | 83% | 50 | 49 | 50 |
| **풀 10000**, CRT 0 | 7.89s | **4.89s** | 0% | **200** | 198 | **200** |

**풀 상한이 있어도 포기가 없으면 소용없다.** 첫 줄에서 caller 톰캣 스레드 200개가 전부 먹히고, **업스트림을 전혀 안 부르는 `/local` 의 p95 가 20.36초**가 됐다. 풀이 막아준 건 소켓 50개뿐이고, 막지 못한 건 스레드 200개다. 소켓 점유가 스레드 점유로 자리를 옮겼을 뿐이다.

`connectionRequestTimeout` 을 200ms 로 주면 `/local` p95 가 **2.28ms** 다. 약 9,000배 차이다. `/call` 은 83% 가 실패하지만, 그게 bulkhead 가 하는 일이다 — 살릴 수 없는 요청을 빨리 포기해서 나머지를 살린다.

마지막 줄이 8번이다. 상한을 사실상 없애면(10000) ESTABLISHED 가 **200개**까지 늘고 `/local` p95 도 4.89초로 무너진다. 200 에서 멈춘 건 caller 톰캣 스레드가 200개라서지 풀이 막은 게 아니다.

세 번째 줄은 덤으로 알게 된 것이다. `connectionRequestTimeout` 을 0(`Timeout.DISABLED`)으로 두면 **무한 대기가 아니라 즉시 실패**다. 스레드가 50에 머물고 83% 가 곧바로 떨어졌다. "무한"을 표현하려면 0 이 아니라 충분히 큰 값을 줘야 한다.

### 9~12번 — stale connection

먼저 **예측이 틀렸다.** 서버 `keepAliveTimeout` 을 1초로 줄이고 클라이언트 검증 주기(2초)보다 짧게 만들어 사각지대를 내려 했는데, 몇 번을 돌려도 재현되지 않았다. 디버그 로그에 답이 있었다.

```
ex-0000000004 connection can be kept alive for 1 SECONDS
```

**톰캣이 `Keep-Alive: timeout=1` 로 자기 타임아웃을 광고하고, HttpClient5 가 그 말을 지킨다.** 위에서 본 `DefaultConnectionKeepAliveStrategy` 가 그 헤더를 읽어 풀 엔트리의 만료 시각을 1초로 잡으니, `validateAfterInactivity`(2초) 가 개입할 일도 없이 그 전에 버려진다. 서버가 알려주는 한 사각지대는 생기지 않는다.

이 헤더에는 조건이 있다. **클라이언트가 `Connection: keep-alive` 를 명시해야** 톰캣이 붙인다.

```
$ curl -D - -H 'Connection: keep-alive' http://upstream:8080/echo
Keep-Alive: timeout=1
Connection: keep-alive

$ curl -D - http://upstream:8080/echo
(둘 다 없음)
```

HttpClient5 는 명시해서 보내므로 힌트를 받는다.

그래서 진짜 stale 은 **말없이 끊는 중간 장비**로 만들어야 한다. 톰캣은 `timeout=60` 을 광고하게 두고(기본값), 경로 중간의 toxiproxy 가 그보다 먼저 아무 통보 없이 커넥션을 끊는다. LB·프록시가 idle timeout 으로 끊는 상황과 같은 모양이다.

| 클라 검증 | 재시도 | idle | 요청 전 상태 | 결과 | 예외 |
| --- | --- | --- | --- | --- | --- |
| 2초(기본) | off | 0.3초 | available=1, ESTABLISHED=0, **CLOSE_WAIT=1** | **HTTP 500** | `NoHttpResponseException` |
| 2초(기본) | on | 0.3초 | 〃 | HTTP 200 | (로그에만 남는다) |
| 2초(기본) | off | 3초 | 〃 | HTTP 200 | 없음 |

**9번** — idle 0.3초는 검증 주기 2초 안쪽이라 검증을 건너뛴다. 죽은 커넥션에 요청이 실리고, 쓰기는 half-close 라 성공한 뒤 읽기에서 터진다.

**10번** — 같은 조건에 재시도만 켜면 HTTP 200 이다. 예외는 로그에만 남고 호출자는 아무것도 모른다. `DefaultHttpRequestRetryStrategy` 의 비재시도 예외 목록에 `NoHttpResponseException` 이 없어서 멱등 요청이 조용히 한 번 더 나간다. **"우리는 이 문제 없는데요" 의 정체가 대개 이것이다.**

**11번** — 세 줄 모두 `available=1` 인데 `ESTABLISHED=0`, `CLOSE_WAIT=1` 이다. 풀이 "빌려줄 수 있다"고 세는 그 1개가 시체다. 0번의 `leased` 와 같은 얘기가 `available` 쪽에서도 성립한다.

세 번째 줄은 방어선이 어디인지 보여준다. idle 3초는 검증 주기 2초를 넘겨서 lease 직전에 stale 체크가 돌고, 죽은 커넥션을 버리고 새로 맺는다. **클라이언트 검증 주기 < 상대가 끊는 주기**가 지켜지면 막힌다.

**12번** — 요청 수 상한은 성격이 다르다. `maxKeepAliveRequests=5` 로 두고 한 커넥션에 6번 보내면 이렇게 나온다.

| 요청 | 응답 헤더 |
| --- | --- |
| 1~4번째 | `Keep-Alive: timeout=60`, `Connection: keep-alive` |
| **5번째** | **`Connection: close`** (Keep-Alive 헤더 사라짐) |
| 6번째 | 새 커넥션에서 다시 `keep-alive` |

**알려주고 닫으므로 stale 을 만들지 않는다.** 시간 상한(`keepAliveTimeout`)은 예고 없이 FIN 을 보내지만, 요청 수 상한은 마지막 응답에 `Connection: close` 를 붙인다. 이 값을 아무리 낮춰도 stale 의 원인은 되지 않는다.

## 정리
---

> 위 결과를 세 가지로 추린다. 괄호 안 번호는 근거가 된 실험이다.

### 풀을 쓰면 뭐가 좋은가

**두 가지 기능이 서로 다른 구간에서 작동한다.** 하나로 묶어 생각하면 어느 쪽이 일하고 있는지 안 보인다.

| | 정상 구간 | 장애 구간 |
| --- | --- | --- |
| 일하는 기능 | 커넥션 재사용 | 동시성 상한 |
| 없으면 | 요청마다 수립 비용을 낸다 | 소켓·스레드가 부하만큼 늘어난다 |

**재사용으로 빠지는 비용** (RTT 20ms, 1·4번)

| | 재사용 O | 재사용 X | TPS |
| --- | --- | --- | --- |
| http | 73.9ms | 95.2ms | -22% |
| https | 73.8ms | 147.1ms | **-50%** |
| http, 본문 100KB | 74.1ms | 154.8ms | -52% |

빠지는 건 핸드셰이크 1 RTT, https 면 TLS 왕복과 비대칭키 연산, 본문이 크면 slow start 까지다. **재사용만 되면 프로토콜도 본문 크기도 무의미해진다** — 첫 열이 전부 74ms 다.

**상한으로 막는 것** (7·8번) — 업스트림이 3초로 느려졌을 때 풀 10000 이면 커넥션이 200개까지 늘고 무관한 API 의 p95 가 4.89초가 된다. 풀 50 이면 커넥션은 50개에서 멈춘다. 다만 **상한만으로는 절반만 막힌다**(주의사항 4).

### 만날 수 있는 에러

| 에러 | 무슨 뜻인가 | 가르는 법 |
| --- | --- | --- |
| `ConnectionRequestTimeoutException` | 제한 시간 안에 커넥션을 못 빌렸다 | 아래 두 갈래 |
| `NoHttpResponseException` · `Connection reset` | 죽은 커넥션에 요청을 실었다 (9번) | `available` 은 있는데 커널엔 `CLOSE_WAIT` |
| 에러 없이 느려지기만 함 | 풀이 작아 큐에서 기다린다 (2·6번) | `pending` 이 쌓이고 `leased` 가 상한에 붙어 있다 |
| **에러가 아예 안 보임** | 재시도가 감추고 있다 (10번) | 로그에는 예외가 있는데 호출자는 200 을 받는다 |

`ConnectionRequestTimeoutException` 은 원인이 두 갈래인데 증상이 같다.

- **풀이 작다** — `leased` 가 상한에 붙어 있고 `pending` 이 쌓인다. 부하를 멈추면 풀린다. `maxPerRoute` 기본값 5 에 막힌 경우가 대부분이다 (2번).
- **반납이 안 된다** — 부하가 없는데도 `leased` 가 안 줄어든다. 되돌아오지 않으므로 시간이 지나도 안 풀린다 (0번).

### 주의사항

1. **본문은 어느 경로로 나가든 소비한다** (0번) — 정상 경로에만 `close` 를 두면 업스트림 에러율이 오르는 순간 풀이 마른다. `try-with-resources` 로 감싼다.
2. **`maxPerRoute` 를 명시한다** (2번) — 기본값은 perRoute 5 / total 25 고, 업스트림이 하나면 `maxTotal` 은 도달할 일이 없는 숫자다. 8배 올려도 TPS 가 그대로였다.
3. **크기는 동시성 기준으로 잡는다** (3번) — 필요 커넥션 = TPS × 응답시간. 넉넉하면 남는 건 그냥 놀지만, 모자라면 곧바로 큐가 된다. **크게 준 쪽의 손해가 작다.**
4. **상한에는 반드시 포기를 같이 준다** (7번) — `connectionRequestTimeout` 이 없으면 소켓 점유가 스레드 점유로 바뀔 뿐이라 업스트림을 안 쓰는 API 까지 죽는다. 0(`Timeout.DISABLED`)은 무한이 아니라 즉시 실패이므로, "무한"은 충분히 큰 값으로 표현한다.
5. **클라이언트 검증 주기 < 상대가 끊는 주기** (9·12번) — 톰캣은 `Keep-Alive: timeout=N` 으로 알려주고 HttpClient5 는 그 값을 지키지만, 중간 LB·프록시는 말없이 끊는다. 헤더가 없으면 풀은 **3분**을 들고 있으므로(`RequestConfig.connectionKeepAlive` 기본값) `validateAfterInactivity`·`evictIdleConnections` 를 상대가 끊는 주기보다 짧게 둔다.
6. **지표는 풀이 센 값과 커널 소켓 상태를 같이 본다** (0·11번) — `leased`·`available` 은 `PoolEntry` 개수일 뿐이라 시체도 센다. `/proc/net/tcp` 의 `CLOSE_WAIT` 과 나란히 놓아야 갈린다.

## 재보고 나서 고친 것
---

> 실험 설계에서 틀렸던 것들. 재보기 전에는 전부 그럴듯해 보였다.

**toxiproxy 로는 핸드셰이크 RTT 를 못 만든다.** TCP 프록시라 클라이언트는 toxiproxy 와 핸드셰이크를 마치고, toxiproxy 가 그 뒤에 업스트림으로 연결한다. latency toxic 은 오가는 데이터만 늦춘다. netem 5ms 를 걸고 재보면 직접 경로는 `connect` 6.0ms, toxiproxy 경유는 0.9ms 다. 그래서 RTT 는 `tc netem` 으로 걸고 toxiproxy 는 기본 경로에서 뺐다. 대신 9번의 "말없이 끊는 중간 장비" 역할로 제대로 쓰였다.

**호스트에서 재도 안 된다.** macOS 의 published port 로 재면 Docker 포트 포워더가 먼저 연결을 받아버려서, netem 을 걸어둬도 `connect` 가 0.2ms 로 나온다. 포워더도 프록시라 똑같이 가린다. 측정은 전부 네트워크 안에서 해야 한다.

**netem 은 조용히 사라진다.** qdisc 는 컨테이너 netns 에 붙어 있어서 컨테이너가 재생성되면 없어진다. 2번을 한 번 RTT 0 에서 돌리고 나서야 알았다. 더 고약한 건 compose 가 **매번 현재 셸 환경으로 서비스 정의를 다시 계산**한다는 것이다. `docker-compose up -d caller` 한 번에 의존 서비스인 upstream 까지 기본값으로 되돌려 만든다. 그래서 실험 스크립트가 매번 netem 을 다시 걸고 `connect` 시간으로 검증하게 했다. **실험 조건은 설정하는 게 아니라 매 회차 검증하는 것**이라는 교훈이 남았다.

**`Timeout.DISABLED`(0) 은 무한이 아니다.** 즉시 실패다. "상한은 있는데 포기가 없는" 조건을 만들려면 충분히 큰 값(60초)을 줘야 한다.

**톰캣은 자기 타임아웃을 알려준다.** 9번에서 예측했던 사각지대가 안 생긴 이유다. 위에 따로 적었다.

**TIME_WAIT 은 먼저 닫는 쪽에 붙는다.** 1번에서 caller 쪽이 0 으로 나온 이유다.

## 나중 단계로 미뤄둘 것
---

- **upstream 플랫폼 스레드 vs 가상 스레드** — 7번에서 caller 쪽에 보이는 "소켓 점유 → 스레드 점유" 가 서버 쪽에서 반복되는 그림이라, 짝지어 보면 한 바퀴 돈다.
- **지연에 지터 주기** — 평균 지연으로 계산한 필요 커넥션 수는 응답시간에 꼬리가 있으면 **과소평가**한다. 3번에서 고정 지연으로 예측이 맞는 걸 확인했으니, 이제 깨볼 차례다.
- **클라이언트가 먼저 닫는 구성에서의 TIME_WAIT** — 1번에서 서버가 능동 종료자였다. 풀의 `timeToLive`·`evictIdleConnections` 로 클라이언트가 버리게 만들면 포트 고갈 쪽으로 이어지는지.
- **TLS 세션 재개** — 4번에서 RTT 0 인데도 https 수립에 28.7ms 가 들었다. 세션 티켓이 이 비용을 얼마나 깎는지.
