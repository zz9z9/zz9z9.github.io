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

> 0~13번은 "무엇을 바꿔서 무엇이 갈라지는가" 를 하나씩 보고, 마지막 14~16번은 풀이 어떻게 동작하는지를 본다.

기준 조건은 `delayMs=50`, RTT 20ms, `sizeBytes=0`, 풀 50, VU 50 고정, 30초다. 각 실험은 여기서 **한 가지만** 바꾼다. 워밍업 15초는 버린다. 0번과 9~13번, 14~16번은 부하 생성기를 안 쓰므로 조건이 다르고, 각 절에 적는다.

| # | 확인할 것 | 구간 | 결과 |
| --- | --- | --- | --- |
| 0 | 응답을 닫지도, 본문을 읽지도 않으면 커넥션이 반환되지 않는다 | 전제 | 확인 |
| 1 | 정상 구간에서 풀의 이득은 재사용 축에서만 나온다 | 정상 | 확인 |
| 2 | 설정 안 하면 `maxPerRoute` 5 에 막힌다 | 정상 | 확인 |
| 3 | 필요 커넥션 수는 TPS × 응답시간으로 예측된다 | 정상 | 확인 |
| 4 | 재사용 이득 = RTT × 왕복수 (+ slow start 회피) | 정상 | 확인. https 가 3.4배 |
| 5 | keep-alive off 면 풀은 동시성 상한으로만 남는다 | 정상 | 확인 |
| 6 | 풀이 스레드풀보다 작으면 초과분은 큐에서 잔다 | 정상 | 확인 |
| 7 | 풀 상한만으로는 느린 업스트림이 무관한 API 까지 잡아먹는 걸 못 막는다 | 장애 | 확인 |
| 8 | 풀이 없으면 소켓이 무한히 는다 | 장애 | 확인 |
| 9 | 중간 장비가 말없이 끊으면 stale 커넥션에 요청이 실린다 | idle | 확인 |
| 10 | 자동 재시도가 stale 실패를 감춘다 | idle | 확인 |
| 11 | 풀은 자기가 들고 있는 커넥션이 죽은 걸 모른다 | idle | 확인. 알려주고 닫으면 안다. 원인은 넷 |
| 12 | 요청 수 상한은 알려주고 닫으므로 stale 을 만들지 않는다 | idle | 확인 |
| 13 | 커넥션을 풀에 두는 시간은 서버가 알려준 값을 따른다 | idle | 확인. 덮어쓰면 9번이 재현된다 |
| 14 | 풀은 미리 채워지지 않고 동시 요청 수만큼만 늘어난다 | 동작 | 확인 |
| 15 | 반납은 본문을 다 읽거나 응답을 닫는 순간 일어난다 | 동작 | 확인. 닫기만 해도 된다 |
| 16 | 재사용 못 하는 커넥션은 반납이 곧 폐기다 | 동작 | 확인 |

9번은 원래 "서버 keepAliveTimeout < 클라 `validateAfterInactivity` 면 그 사이가 사각지대"로 적어뒀는데, 톰캣 상대로는 그 사각지대가 안 생겼다. 왜 안 생기는지는 아래에 따로 적는다.

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
  # 음수 = 설정하지 않음 -> 서버의 Keep-Alive: timeout=N 을 따른다
  keep-alive-ms: ${POOL_KEEP_ALIVE_MS:-1}
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
            // 풀에서 커넥션을 빌리려고 기다리는 한도. 상한이 실제로 다른 요청을 지키게 만드는 값 (7번)
            .setConnectionRequestTimeout(props.connectionRequestTimeoutMs(), TimeUnit.MILLISECONDS)
            // 요청을 보낸 뒤 응답을 기다리는 한도
            .setResponseTimeout(props.responseTimeoutMs(), TimeUnit.MILLISECONDS)
            .build();

    return HttpClients.custom()
            .setConnectionManager(manager)
            // 이걸 빼면 클라이언트를 닫을 때 매니저까지 닫힌다
            .setConnectionManagerShared(true)
            .setDefaultRequestConfig(requestConfig)
            // 커넥션을 풀에 둘 시간을 응답마다 정한다. 이렇게 고정하면 서버가 뭐라 하든 이 값이다 (13번)
            .setKeepAliveStrategy((response, context) -> TimeValue.ofMilliseconds(props.keepAliveMs()))
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

**`setKeepAliveStrategy` 가 이 중에서 성격이 다르다.** 커넥션을 풀에 얼마나 두고 재사용할지는 위의 어떤 값도 아니고 이 전략이 응답마다 정한다. 9번이 예측대로 재현되지 않은 원인이 이것이었고, 반대로 이 값을 고정하면 9번이 재현된다(13번).

```java
// org.apache.hc.client5.http.impl.DefaultConnectionKeepAliveStrategy.java
public TimeValue getKeepAliveDuration(final HttpResponse response, final HttpContext context) {
    // 1. 응답의 Keep-Alive: timeout=N 을 그대로 따른다
    final Iterator<HeaderElement> it = MessageSupport.iterate(response, HeaderElements.KEEP_ALIVE);
    while (it.hasNext()) {
        final HeaderElement he = it.next();
        final String param = he.getName();
        final String value = he.getValue();
        if (value != null && param.equalsIgnoreCase("timeout")) {
            try {
                return TimeValue.ofSeconds(Long.parseLong(value));
            } catch (final NumberFormatException ignore) {
            }
        }
    }
    // 2. 헤더가 없으면 RequestConfig.connectionKeepAlive -> 기본 3분
    final HttpClientContext clientContext = HttpClientContext.cast(context);
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

#### 커널·cgroup 에서 직접 읽는 값

풀 게이지로는 안 보이는 것들이 있다. 커넥션이 **어떻게 끝났는지**, CPU 를 얼마나 썼는지는 컨테이너 안에서 직접 읽는다. `eclipse-temurin` 이미지에 `ss`·`netstat`·`top` 이 없어서 전부 파일로 읽는다.

| 값 | 어디서 | 어떻게 읽나 |
| --- | --- | --- |
| ESTABLISHED / TIME_WAIT / CLOSE_WAIT | `/proc/net/tcp` | `$4` 가 상태(`01` ESTABLISHED, `06` TIME_WAIT, `08` CLOSE_WAIT), `$2` local, `$3` remote. 포트는 16진수(8080 = `1F90`) |
| TIME_WAIT 총계, 소켓 메모리 | `/proc/net/sockstat` | `TCP: inuse … tw … mem …`. `mem` 은 소켓이 잡은 **페이지 수**(4KB/페이지) |
| 새로 맺은 커넥션 수 | `/proc/net/snmp` | `Tcp: ActiveOpens`(내가 건 것) / `PassiveOpens`(받은 것) |
| **RST 로 끝난 커넥션 수** | 〃 | `Tcp: EstabResets`. ESTABLISHED·CLOSE_WAIT 에서 곧바로 CLOSED 로 간 횟수 |
| CPU 사용량 | `/sys/fs/cgroup/cpuacct/cpuacct.usage` | 컨테이너 누적 CPU **나노초** |

**앞의 둘은 순간값이고 뒤의 셋은 누적값이다.** `/proc/net/tcp` 를 세면 "지금 몇 개"는 알아도 "그동안 몇 개가 생겼다 사라졌는지"는 모른다. 누적 카운터는 부하 전후로 두 번 읽어 **증분**을 쓴다. 1번에서 TIME_WAIT 이 0 인 이유를 찾을 때 이 차이가 갈랐다 — 순간값으로는 아무 일도 안 일어난 것처럼 보였는데, 증분을 보니 커넥션 14,077개가 전부 RST 로 끝나 있었다.

요청당 CPU 도 같은 식이다. `cpuacct.usage` 증분을 요청 수로 나눈다. `docker stats` 의 CPU% 는 순간 샘플이라 회차마다 흔들려서 안 쓴다.

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

그 `PoolEntry` 는 소켓이 아니라 **소켓을 담는 칸**이다. `connRef` 가 nullable 이라 칸과 소켓의 생애가 분리된다 — 빈 칸으로 태어나고(`new PoolEntry`), 소켓이 꽂히고(`assignConnection`), 소켓만 떼이기도 한다(`discardConnection`). 칸이 어느 자료구조에 있는지가 그대로 게이지다.

```
 createEntry()  ──►  leased          태어나는 자리는 항상 여기
                       │  free(entry, reusable=true)
                       ▼
                   available         들어오는 유일한 경로가 반납이다
                       │  getFree() 때 만료됐으면 discardConnection
                       ▼
                    버려진다          reusable=false 면 available 을 안 거친다
```

`free(entry, reusable)` 가 `false` 를 받으면 `leased` 에서만 빼고 `available` 에 넣지 않는다. 16번의 "반납과 폐기가 같은 동작"이 이 한 줄이다.

재사용 기한도 엔트리가 들고 있다.

| 필드 | 언제 정해지나 |
| --- | --- |
| `validityDeadline` | 소켓을 꽂을 때 `created + timeToLive` 로 한 번 |
| `expiryDeadline` | 반납할 때마다 `min(now + keepAlive, validityDeadline)` |
| `updated` | 반납 시각. `validateAfterInactivity` 가 이 값을 기준으로 stale 체크를 돌린다 |

`min` 이라서 **`timeToLive` 는 서버가 알려준 keep-alive 가 넘을 수 없는 천장**이다(13번).

여기서 두 가지가 따라온다.

**이 숫자는 실제 TCP 상태와 얼마든지 어긋난다.** 0번에서 `leased=50` 이 남은 게 그 예다. `PoolEntry` 50개가 `leased` Set 에 들어간 채 아무도 release 를 안 불렀다는 뜻이고, 그 소켓이 살았는지 죽었는지는 풀이 모른다. `/proc/net/tcp` 를 따로 세는 건 풀이 센 값을 커널 쪽과 맞춰보기 위해서다. 0번에서는 50/50 으로 일치했지만 **9~11번에서는 갈라진다** — 서버가 FIN 을 보내도 풀이 센 `available` 은 그대로다.

**pull 방식이라 스크레이프 시점의 순간값이다.** `Gauge.builder(name, obj, fn)` 로 등록된 `ToDoubleFunction` 은 수집 시점에 호출된다. 스크레이프 사이에 일어난 스파이크는 존재하지 않았던 게 된다. 1s 로 내려도 그보다 짧은 `pending` 스파이크는 여전히 놓치므로, 3번·8번처럼 대기 큐를 봐야 하는 실험은 부하를 충분히 오래 유지해 **스파이크가 아니라 정상 상태로** 만들어야 한다.

덧붙여 `getTotalStats()` 가 풀 전역 락을 잡으므로, 고동시성에서 스크레이프 주기를 더 낮추면 lease/release 와 경합한다. 1초면 무시할 수준이다.


## 결과
---

### 부하를 어떻게 줬나

1번부터 8번까지는 k6 컨테이너를 **같은 브리지 네트워크에 띄워** caller 를 때린다. 호스트에서 쏘면 Docker VM 경계의 지연이 재려는 값과 섞인다.

```js
// k6/scenario.js — VU 50 이 쉬지 않고 caller 를 호출한다 (constant-vus)
export const options = { vus: 50, duration: '30s', discardResponseBodies: true };

export default function () {
  http.get(`http://caller:8080/call?delayMs=50&sizeBytes=0&close=false&mode=safe`);
}
```

**VU(Virtual User)** 는 k6 의 가상 사용자다. 각 VU 가 위의 `default` 함수를 쉬는 시간 없이 반복하는데, **한 VU 는 한 번에 요청 하나**만 띄우고 응답을 받은 뒤 다음 회차로 넘어간다. 그래서 `vus: 50` 은 "초당 50 요청"이 아니라 **동시 요청 수 50**이라는 뜻이고, TPS 는 설정이 아니라 결과로 나온다 — 1번의 응답시간 73.9ms 면 50/0.0739 ≈ 677 이고, 실측 TPS 가 675 였다. 6번에서 `leased + pending` 이 정확히 50 으로 맞는 이유가 이것이다.

| 익스큐터 | 고정하는 것 | 따라 움직이는 것 |
| --- | --- | --- |
| `constant-vus` | **동시성**(VU 수) | TPS, 오퍼 부하 |
| `constant-arrival-rate` | **도착률**(TPS) | VU 수 (`preAllocatedVUs`~`maxVUs` 범위에서) |

1~8번은 동시성을 고정해야 "풀 50 에 동시성 50" 같은 조건이 성립하므로 `constant-vus` 를 쓴다. 7·8번만 도착률 고정인데, 이유는 그 절에 적는다. 스크립트의 `VUS` 는 그 개수를 넘기는 환경변수 이름일 뿐이다.

한 회차는 이렇게 돈다.

```bash
./scripts/run-case.sh "<설명>" <maxTotal> <maxPerRoute> <close> [delayMs] [VUs]

# 1) caller 재기동 (풀 설정은 env var) + health 대기
# 2) netem 재적용 후 connect 시간으로 RTT 검증   ← 결과 줄에 같이 찍는다
# 3) k6 15초    — JIT·풀 예열. 버린다
# 4) k6 30초    — 이 구간의 http_req_duration·http_reqs 만 쓴다
#    시작 15초 시점에 leased / pending / tomcat_threads_busy 를 1회 샘플링
```

<details markdown="1">
<summary>회차 전체 — <code>scripts/run-case.sh</code></summary>

```bash
#!/usr/bin/env bash
# 사용법: run-case.sh "<설명>" <MAX_TOTAL> <MAX_PER_ROUTE> <CLOSE> [DELAY_MS] [VUS]
#   MAX_TOTAL / MAX_PER_ROUTE 에 0 = "설정하지 않음" -> httpclient5 기본값
#   env: NETEM_MS(기본 20), SIZE_BYTES(기본 0), UPSTREAM_BASE_URL
set -e
cd "$(dirname "$0")/.."
DESC="$1"; TOTAL="$2"; PER_ROUTE="$3"; CLOSE="$4"; DELAY="${5:-50}"; VUS="${6:-50}"
NET=docker_default
D="${NETEM_MS:-20}"

export POOL_MAX_TOTAL="$TOTAL" POOL_MAX_PER_ROUTE="$PER_ROUTE"
(cd docker && docker-compose up -d --force-recreate caller >/dev/null 2>&1)
for i in $(seq 1 60); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:9080/actuator/health)" = "200" ] && break
  sleep 1
done

# qdisc 는 컨테이너 netns 에 붙어 있어 재생성 때마다 사라진다. 매 실험 전에 다시 걸고 검증한다.
TARGET=docker_upstream_1 ./scripts/netem.sh "$D" >/dev/null
if [ -n "${UPSTREAM_BASE_URL##*upstream:8080}" ] && [ -n "$UPSTREAM_BASE_URL" ]; then
  RTT=$(TARGET=docker_upstream-tls_1 VERIFY_URL=https://upstream-tls:8443/echo ./scripts/netem.sh "$D" | grep -o 'connect=[0-9.]*ms')
else
  RTT=$(TARGET=docker_upstream_1 ./scripts/netem.sh "$D" | grep -o 'connect=[0-9.]*ms')
fi
EFF=$(docker logs docker_caller_1 2>&1 | grep -o 'pool: maxTotal=[0-9]*, maxPerRoute=[0-9]*' | tail -1)

k6run() {
  docker run --rm --network "$NET" --cpus 2 -v "$PWD/k6:/scripts:ro" \
    -e VUS="$VUS" -e DURATION="$1" -e DELAY_MS="$DELAY" -e CLOSE="$CLOSE" -e MODE=safe \
    -e SIZE_BYTES="${SIZE_BYTES:-0}" \
    grafana/k6:0.53.0 run --quiet /scripts/scenario.js 2>&1
}
gauge() { curl -s http://localhost:9080/actuator/prometheus | awk -v s="$1" '$0 ~ s && $0 !~ /^#/ {printf "%d", $2}'; }

k6run 15s >/dev/null 2>&1                      # JIT warmup — 버린다
( k6run 30s > /tmp/_k6out 2>&1 ) &
sleep 15
MID="leased=$(gauge 'state="leased"') pending=$(gauge 'pool_total_pending') callerThreads=$(gauge '^tomcat_threads_busy')"
wait
OUT=$(cat /tmp/_k6out)
AVG=$(echo "$OUT" | grep -E "^ *http_req_duration" | sed -E 's/.*avg=([^ ]+).*/\1/')
TPS=$(echo "$OUT" | grep -E "^ *http_reqs" | sed -E 's#.* ([0-9.]+)/s.*#\1#')
printf '%-28s | %-34s | %-15s | %-9s | %-7s | %s\n' "$DESC" "$EFF" "$RTT" "$AVG" "${TPS%.*}" "$MID"
```

</details>

표의 **평균·p95·TPS 는 4)의 k6 요약**이고, `leased`·`pending`·`callerThreads` 는 그 한가운데서 뜬 **순간값**이다. `available`·`ESTABLISHED`·`CLOSE_WAIT` 처럼 부하가 끝난 뒤를 보는 값은 종료 후에 `pool-stat.sh` 로 잰다.

14~16번과 0번, 9~13번은 부하 생성기를 안 쓴다. 각 절에 적는다.

### 0번 — 응답을 닫지 않으면 반납되지 않는다

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

**동시성 1 로 순차 60회**를 쏜다. 부하 생성기 없이 curl 을 한 번에 하나씩 돌리므로, 커넥션이 1개를 넘길 이유가 원래는 없다.

```bash
./scripts/run-leak.sh leaky 404     # <mode> <업스트림이 줄 상태코드>

#   for i in $(seq 1 60); do
#     curl "localhost:9080/call?delayMs=0&status=404&mode=leaky"
#   done
```

<details markdown="1">
<summary>순차 60회 + 풀·소켓 상태 — <code>scripts/run-leak.sh</code></summary>

```bash
#!/usr/bin/env bash
# 사용법: run-leak.sh <MODE: leaky|safe> <STATUS>
#
# 동시성 1 로 60번 순차 호출한다(부하 생성기 없이 curl 루프).
# 반납이 안 되면 동시성이 1인데도 요청 수만큼 커넥션이 늘어난다.
set -e
cd "$(dirname "$0")/.."
MODE="$1"; STATUS="$2"
export POOL_MAX_TOTAL=50 POOL_MAX_PER_ROUTE=50 POOL_CONNECTION_REQUEST_TIMEOUT_MS=3000 \
       POOL_VALIDATE_AFTER_INACTIVITY_MS=-1 POOL_EVICT_IDLE_MS=-1 POOL_TIME_TO_LIVE_MS=-1 \
       POOL_KEEP_ALIVE_MS=-1 POOL_RETRY_ENABLED=false \
       UPSTREAM_BASE_URL=http://upstream:8080 KEEP_ALIVE_TIMEOUT=60000 NETEM_DELAY_MS=0
(cd docker && docker-compose up -d --force-recreate caller upstream >/dev/null 2>&1)
for i in $(seq 1 60); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:9080/actuator/health)" = "200" ] && break
  sleep 1
done

OK=0; FIRST_FAIL=""
for i in $(seq 1 60); do
  code=$(curl -s -o /dev/null -m 10 -w '%{http_code}' \
    "http://localhost:9080/call?delayMs=0&status=${STATUS}&mode=${MODE}")
  # 502 는 업스트림 에러를 caller 가 정상적으로 옮긴 것 -> 호출 자체는 성공
  if [ "$code" = "200" ] || [ "$code" = "502" ]; then OK=$((OK+1))
  elif [ -z "$FIRST_FAIL" ]; then FIRST_FAIL="$i"; fi
done

gauge() { curl -s http://localhost:9080/actuator/prometheus | awk -v s="$1" '$0 ~ s && $0 !~ /^#/ {printf "%d", $2}'; }
sock()  { docker exec docker_caller_1 sh -c "awk 'NR>1 && \$4==\"$1\" && \$3 ~ /:1F90\$/ {n++} END {print n+0}' /proc/net/tcp"; }
printf '%-6s + %-3s | 성공 %2d/60 | 첫 실패 %-6s | available=%-3s leased=%-3s | ESTABLISHED=%-3s CLOSE_WAIT=%s\n' \
  "$MODE" "$STATUS" "$OK" "${FIRST_FAIL:-없음}" \
  "$(gauge 'state="available"')" "$(gauge 'state="leased"')" "$(sock 01)" "$(sock 08)"
```

</details>

`mode` 는 위 두 코드 중 어느 경로를 탈지고, `status` 는 업스트림이 돌려줄 코드다. 풀은 `maxTotal=maxPerRoute=50`, `connectionRequestTimeout=3000`.

**성공은 caller 가 응답을 돌려준 것**까지 친다. 업스트림이 404·500 을 줘도 caller 는 502 로 옮기고 정상 종료하므로 성공이다. 실패는 커넥션을 못 빌려 `ConnectionRequestTimeoutException` 으로 떨어진 것뿐이다.

60회가 끝난 뒤 풀 게이지와 caller 의 `/proc/net/tcp` 를 같이 읽는다.

| # | 조건 | 성공 | 첫 실패 | available | leased | ESTABLISHED | CLOSE_WAIT |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | leaky + 정상(200) | 60/60 | 없음 | 1 | 0 | 1 | 0 |
| 2 | leaky + 404 | 50/60 | **51번째** | 0 | **50** | **50** | 0 |
| 3 | leaky + 500 | 50/60 | **51번째** | 0 | **50** | 0 | **50** |
| 4 | safe + 500 | 60/60 | 없음 | 0 | 0 | 0 | 0 |

**평소에는 아무 일도 없다.** 같은 leaky 코드인데 업스트림이 200 을 주는 동안은 커넥션 1개로 60회를 처리한다. 누수 경로는 에러 응답에서만 열린다. 배포하고 한참 뒤 업스트림 에러율이 오르는 순간 풀이 마르는 형태다.

**에러가 나기 시작하면 요청 수만큼 커넥션이 는다.** 순차 요청이라 동시성이 1인데 커넥션이 50개까지 늘고, `maxTotal` 을 채운 51번째부터 `ConnectionRequestTimeoutException` 으로 떨어진다.

**404 와 500 을 가른 건 톰캣이다.** 톰캣은 `400` 과 `5xx` 응답에 `Connection: close` 를 자동으로 붙인다(`404` 는 안 붙는다).

- **404** — 서버는 커넥션을 살려둔다. 살아 있는 커넥션 50개를 풀이 붙잡고 못 돌려준다. 순수한 누수다.
- **500** — 서버가 FIN 을 보내 닫았다. caller 소켓은 전부 `CLOSE_WAIT` 이고 살아 있는 커넥션은 **0개**다. 그런데 풀은 여전히 `leased=50` 으로 센다.

**3 에서는 풀이 "빌려준 상태"로 세고 있는 50개가 전부 이미 끊긴 커넥션이다.** 풀은 `PoolEntry` 가 `leased` Set 에 있다는 것만 알지, 그 소켓이 살았는지는 반납을 받아봐야 안다. 반납이 없으므로 영원히 모른다.

### 1번 — 정상 구간에서 갈리는 건 재사용 축뿐

'풀 없음'이라고 할 때 실제로 없어지는 건 **커넥션 재사용**과 **동시성 상한** 두 가지다. 붙여놓고 비교하면 어느 쪽 기여분인지 갈리지 않으므로 2×2 로 돌린다.

재사용 축은 업스트림이 `Connection: close` 를 붙이게 해서 끄고(네 번째 인자), 상한 축은 풀 크기로 준다.

```bash
./scripts/run-case.sh "A 재사용O 상한50"    50    50    false
./scripts/run-case.sh "B 재사용O 상한10000" 10000 10000 false
./scripts/run-case.sh "C 재사용X 상한50"    50    50    true
./scripts/run-case.sh "D 재사용X 상한10000" 10000 10000 true
```

| # | 조건 | 평균 | p95 | TPS |
| --- | --- | --- | --- | --- |
| 1 | 재사용 O, 상한 50 | 73.9ms | 78.7ms | 675 |
| 2 | 재사용 O, 상한 10000 | 73.5ms | 78.1ms | 679 |
| 3 | 재사용 X, 상한 50 | 95.2ms | 101.7ms | 524 |
| 4 | 재사용 X, 상한 10000 | 94.9ms | 101.1ms | 526 |

**1 ≈ 2, 3 ≈ 4.** 상한을 200배 늘려도 차이가 0.5% 안쪽이다. 부하가 상한 밑이면 lease 대기가 안 생기니 상한은 존재만 하고 아무 일도 하지 않는다. 상한 축은 장애 구간(7·8번)에서만 갈린다.

**갈린 폭이 RTT 와 맞는다.** 73.9 → 95.2ms, 차이 **21.3ms** 로 주입한 RTT 20ms 와 일치한다. TPS 는 675 → 524 로 22% 감소인데, 동시성이 고정이면 TPS 가 응답시간에 반비례하므로 73.9/95.2 = 0.776 과 맞아떨어진다.

#### 재사용을 끄면 TIME_WAIT 이 쌓이나

재사용이 없으면 요청 수만큼 커넥션이 생기고, 그만큼 TIME_WAIT 이 쌓여 포트·메모리를 먹을 것 같았다. 재보면 **재사용을 어떻게 끄느냐에 따라 갈린다.** 끄는 방법이 두 가지인데 먼저 닫는 쪽이 다르다.

```bash
./scripts/run-timewait.sh none      # 재사용 O
./scripts/run-timewait.sh server    # 업스트림이 Connection: close  (1번에서 쓴 방법)
./scripts/run-timewait.sh client    # 풀의 timeToLive=0 -> 빌려줄 때마다 버린다
```

<details markdown="1">
<summary>커넥션 수·RST·TIME_WAIT — <code>scripts/run-timewait.sh</code></summary>

```bash
#!/usr/bin/env bash
# 사용법: run-timewait.sh <CLOSER: none|server|client>
#
# 재사용을 끄는 방법이 두 가지인데, 먼저 닫는 쪽이 달라서 TIME_WAIT 이 쌓이는 자리가 다르다.
#   server — 업스트림이 Connection: close 를 붙인다 (1번에서 쓴 방법)
#   client — 풀이 빌려줄 때마다 TTL 만료로 버린다 (timeToLive=0) -> caller 가 먼저 닫는다
# 부하 중에 caller/upstream 양쪽의 TIME_WAIT 과 소켓 메모리를 같이 센다.
set -e
cd "$(dirname "$0")/.."
CLOSER="$1"
case "$CLOSER" in
  none)   CLOSE=false; TTL=-1 ;;
  server) CLOSE=true;  TTL=-1 ;;
  client) CLOSE=false; TTL=0  ;;
esac
export POOL_MAX_TOTAL=50 POOL_MAX_PER_ROUTE=50 POOL_KEEP_ALIVE_MS=-1 \
       POOL_CONNECTION_REQUEST_TIMEOUT_MS=3000 POOL_VALIDATE_AFTER_INACTIVITY_MS=-1 \
       POOL_EVICT_IDLE_MS=-1 POOL_TIME_TO_LIVE_MS="$TTL" POOL_RETRY_ENABLED=false \
       UPSTREAM_BASE_URL=http://upstream:8080 KEEP_ALIVE_TIMEOUT=60000 MAX_KEEP_ALIVE_REQUESTS=100
(cd docker && docker-compose up -d --force-recreate caller upstream >/dev/null 2>&1)
for i in $(seq 1 60); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:9080/actuator/health)" = "200" ] && break
  sleep 1
done
TARGET=docker_upstream_1 ./scripts/netem.sh 20 >/dev/null 2>&1

# $4=상태(06=TIME_WAIT), 포트 1F90=8080. caller 는 remote(=$3), upstream 은 local(=$2) 이 8080 이다
tw() { docker exec "$1" sh -c \
  "awk 'NR>1 && \$4==\"06\" && \$$2 ~ /:1F90\$/ {n++} END {print n+0}' /proc/net/tcp"; }
# sockstat 의 tw = TIME_WAIT 총계, mem = 소켓 버퍼로 잡은 페이지 수(4KB/페이지)
sockstat() { docker exec "$1" sh -c "grep '^TCP:' /proc/net/sockstat"; }

opens() { docker exec "$1" sh -c "awk '/^Tcp:/{if(h){split(h,a,\" \");split(\$0,b,\" \");for(i=1;i<=length(a);i++) if(a[i]==\"$2\") print b[i]} else h=\$0}' /proc/net/snmp"; }
A0=$(opens docker_caller_1 ActiveOpens); R0=$(opens docker_caller_1 EstabResets)

( docker run --rm --network docker_default --cpus 2 -v "$PWD/k6:/scripts:ro" \
    -e VUS=50 -e DURATION=30s -e DELAY_MS=50 -e CLOSE="$CLOSE" -e MODE=safe \
    grafana/k6:0.53.0 run --quiet /scripts/scenario.js > /tmp/_tw 2>&1 ) &
sleep 25
C_TW=$(tw docker_caller_1 3); U_TW=$(tw docker_upstream_1 2)
C_SS=$(sockstat docker_caller_1); U_SS=$(sockstat docker_upstream_1)
wait
TPS=$(grep -E "^ *http_reqs" /tmp/_tw | sed -E 's#.* ([0-9.]+)/s.*#\1#')
REQ=$(grep -E "^ *http_reqs" /tmp/_tw | sed -E 's/.*: ([0-9]+) .*/\1/')
A1=$(opens docker_caller_1 ActiveOpens); R1=$(opens docker_caller_1 EstabResets)

printf '%-7s | 요청 %-6s TPS %-5s | 새 커넥션 %-6s RST 로 끝 %-6s | TIME_WAIT caller=%-5s upstream=%s\n' \
  "$CLOSER" "$REQ" "${TPS%.*}" "$((A1-A0))" "$((R1-R0))" "$C_TW" "$U_TW"
printf '          caller   %s\n' "$C_SS"
printf '          upstream %s\n' "$U_SS"
```

</details>

커넥션 수와 종료 방식은 `/proc/net/snmp` 의 카운터 증분으로, TIME_WAIT 은 부하 25초 시점의 `/proc/net/tcp` 로 센다.

| # | 재사용 끈 방법 | 요청 | TPS | 새 커넥션 | RST 로 끝난 수 | caller TIME_WAIT |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | (안 끔) | 17,648 | 587 | **200** | 150 | 0 |
| 2 | 서버가 닫음 | 14,077 | 467 | 14,077 | **14,077** | **0** |
| 3 | 클라가 버림 | 13,401 | 445 | 13,401 | 0 | **8,179** |

**재사용이 없으면 요청 1건에 커넥션 1개**가 맞다. 17,648 요청을 커넥션 200개로 처리하던 것이 13,401 요청에 13,401개가 된다.

부하 중 상태를 히스토그램으로 뜨면 caller 에 `SYN_SENT`, upstream 에 `SYN_RECV` 가 늘 잡힌다. VU 가 그 시점에 **핸드셰이크 중**이라는 뜻이고, 3·4 에서 늘어난 21.3ms 가 여기 그대로 보인다.

**그런데 1번에서 쓴 방법으로는 TIME_WAIT 이 하나도 안 생긴다.** 커넥션 14,077개가 전부 **RST 로 끝났기 때문**이다. 서버가 `Connection: close` 를 붙이면 HttpClient5 는 그 커넥션을 재사용 불가로 표시하고, 반납 대신 `discardEndpoint()` 로 보낸다.

```java
// org.apache.hc.client5.http.impl.classic.InternalExecRuntime.java — 재사용 못 하는 커넥션은 이 경로로 간다
private void discardEndpoint(final ConnectionEndpoint endpoint) {
    endpoint.close(CloseMode.IMMEDIATE);
    ...
}

// org.apache.hc.core5.http.impl.io.BHttpConnectionBase.java — close(CloseMode), IMMEDIATE 면
socket.setSoLinger(true, 0);   // linger 0 -> close() 가 FIN 이 아니라 RST 를 보낸다
socket.close();
```

`SO_LINGER 0` 은 커널에 "정상 종료 절차 밟지 말고 끊어라"는 뜻이고, **RST 로 끝난 커넥션은 TIME_WAIT 을 남기지 않는다.** 그래서 caller 도 upstream 도 0 이다.

3 이 진짜 TIME_WAIT 이 쌓이는 경우다. 풀이 `timeToLive` 만료로 버리는 경로는 `CloseMode.GRACEFUL` 이라 정상적으로 FIN 을 보내고, 먼저 닫은 caller 에 TIME_WAIT 이 붙는다.

**8,179 에서 멈춘다.** 445 TPS × TIME_WAIT 60초면 26,700 개가 쌓여야 하는데 8,192 근처에서 더 안 는다. 컨테이너의 `tcp_max_tw_buckets` 가 **8192** 다. 이 상한을 넘으면 커널이 TIME_WAIT 을 유예 없이 없애버린다. 자원을 아끼려고 있는 값이 아니라, **TIME_WAIT 이 하는 일(지연 도착한 옛 패킷이 새 커넥션에 섞이는 걸 막는 것)을 포기**하는 안전장치다.

자원 영향은 예상과 달랐다. `/proc/net/sockstat` 의 `mem`(소켓 버퍼 페이지 수)은 200 → 205 로 20KB 쯤 움직였을 뿐이다. TIME_WAIT 소켓은 온전한 소켓이 아니라 경량 구조체라 **메모리로는 티가 안 난다.** 걸리는 건 메모리가 아니라 **포트**다. 이 컨테이너의 `ip_local_port_range` 는 32768~60999, 28,232 개다. 445 TPS × 60초 = 26,700 이므로 tw_buckets 상한이 없었다면 포트 고갈 직전까지 갔을 숫자다.

정리하면 "재사용을 끄면 TIME_WAIT 이 쌓인다"는 **맞기도 하고 틀리기도 하다.** 누가 먼저 닫는지, 그리고 그 닫기가 FIN 인지 RST 인지에 달렸다. 상대가 `Connection: close` 로 끊는 구성이면 클라이언트 쪽에는 TIME_WAIT 이 안 쌓이고, 풀의 TTL·eviction 으로 클라이언트가 버리는 구성이면 쌓인다.

> caller 의 TIME_WAIT 을 필터 없이 세면 재사용을 켜도 30~40개가 잡히는데 전부 **k6 ↔ caller** 커넥션이다. caller 톰캣이 `maxKeepAliveRequests` 기본값 100 에 걸려 닫고 있던 것이다 — 12번과 같은 동작이 부하 생성기 ↔ caller 구간에서 나타난 것이다.

#### 상한이 없으면 뭐가 먼저 바닥나나

그럼 풀 상한을 사실상 없애고(10000) 재사용도 없으면 어디까지 가나. 먼저 바닥나는 건 커넥션 수 자체가 아니라 **그걸 담는 커널 자원**이다. 기본값(포트 28,232개 / fd 1,048,576개)으로는 닿는 데 오래 걸리므로 caller 컨테이너의 한계를 좁혀서 같은 상황을 빨리 만든다.

```bash
./scripts/run-exhaust.sh port     # ephemeral port 를 500개로 줄인다
./scripts/run-exhaust.sh fd       # 열 수 있는 파일 수를 256개로 줄인다
```

<details markdown="1">
<summary>포트·fd 한계를 좁혀 고갈 — <code>scripts/run-exhaust.sh</code></summary>

```bash
#!/usr/bin/env bash
# 사용법: run-exhaust.sh <port|fd>
#
# 풀 상한이 없을 때 뭐가 먼저 바닥나는지 본다. 실제 한계까지 가려면 오래 걸리므로
# caller 컨테이너의 한계를 좁혀서 같은 상황을 빨리 만든다.
#   port — ephemeral port 를 500개로 줄이고, 클라이언트가 커넥션을 버리게 해서 TIME_WAIT 을 쌓는다
#   fd   — 열 수 있는 파일 수를 256개로 줄이고, 느린 업스트림에 상한 없는 풀로 붙는다
set -e
cd "$(dirname "$0")/.."
KIND="$1"
case "$KIND" in
  port) export PORT_RANGE="32768 33267" NOFILE=1048576 \
               POOL_MAX_TOTAL=10000 POOL_MAX_PER_ROUTE=10000 POOL_TIME_TO_LIVE_MS=0 \
               DELAY=50 VUS=50 ;;
  fd)   export PORT_RANGE="32768 60999" NOFILE=256 \
               POOL_MAX_TOTAL=10000 POOL_MAX_PER_ROUTE=10000 POOL_TIME_TO_LIVE_MS=-1 \
               DELAY=3000 VUS=200 ;;
esac
export POOL_CONNECTION_REQUEST_TIMEOUT_MS=3000 POOL_KEEP_ALIVE_MS=-1 \
       POOL_VALIDATE_AFTER_INACTIVITY_MS=-1 POOL_EVICT_IDLE_MS=-1 POOL_RETRY_ENABLED=false \
       POOL_RESPONSE_TIMEOUT_MS=20000 POOL_SOCKET_TIMEOUT_MS=20000 \
       UPSTREAM_BASE_URL=http://upstream:8080 KEEP_ALIVE_TIMEOUT=60000 CALLER_TOMCAT_THREADS_MAX=200
(cd docker && docker-compose up -d --force-recreate caller >/dev/null 2>&1)
for i in $(seq 1 60); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:9080/actuator/health)" = "200" ] && break
  sleep 1
done
echo "  한계: 포트=$(docker exec docker_caller_1 cat /proc/sys/net/ipv4/ip_local_port_range | tr '\t' '-') nofile=$(docker exec docker_caller_1 sh -c 'ulimit -n')"

N=$(docker logs docker_caller_1 2>&1 | wc -l)
docker run --rm --network docker_default --cpus 2 -v "$PWD/k6:/scripts:ro" \
  -e VUS="$VUS" -e DURATION=30s -e DELAY_MS="$DELAY" -e CLOSE=false -e MODE=safe \
  grafana/k6:0.53.0 run --quiet /scripts/scenario.js > /tmp/_ex 2>&1
LOG=$(docker logs docker_caller_1 2>&1 | tail -n +$((N+1)))

REQ=$(grep -E "^ *http_reqs" /tmp/_ex | sed -E 's/.*: ([0-9]+) .*/\1/')
FAIL=$(grep -E "^ *http_req_failed" /tmp/_ex | sed -E 's/.*: ([0-9.]+%).*✓ ([0-9]+).*/\1 (\2건)/')
echo "  요청 $REQ, 실패 $FAIL"
# 스택트레이스에 같은 문구가 여러 번 나오므로 로그 줄 수가 아니라 k6 실패 수가 기준이다
echo "$LOG" | grep -oiE "Cannot assign requested address|Too many open files|Address already in use|Connection refused|No buffer space" \
  | sort | uniq -c | sed 's/^/  /' || echo "  (해당 에러 없음)"
```

</details>

| 좁힌 것 | 값 | 요청 | 실패 | 에러 |
| --- | --- | --- | --- | --- |
| ephemeral port | 500개 (32768~33267) | 11,111 | **95.5%** (10,611건) | `Cannot assign requested address` |
| 열 수 있는 파일 수 | 256 | 1,712 | **30.3%** (518건) | `Too many open files` |

**포트 쪽은 성공한 게 정확히 500건이다.** 포트 번호 500개가 전부 TIME_WAIT 에 묶이는 순간 그 뒤로는 `connect` 자체가 안 된다. 상대 서버는 멀쩡한데 **커널이 빌려줄 번호가 없어서** 나가는 에러다. 앞의 tw_buckets 8192 가 없었다면 기본 포트 범위(28,232개)로도 445 TPS × 60초 = 26,700 이라 같은 벽에 닿는다.

fd 쪽은 소켓 하나가 fd 하나를 먹기 때문이다. 256개 안에는 JVM 이 이미 열어둔 jar·클래스·로그 파일도 들어가므로 소켓에 쓸 수 있는 건 그보다 적다.

**둘 다 풀 상한과 무관하게 걸린다.** 풀이 "10000개까지 허용"이어도 커널이 못 준다. 8번에서 ESTABLISHED 가 200 에서 멈춘 건 caller 톰캣 스레드가 200개라서였는데, 스레드를 더 줬다면 다음 벽이 이 둘이다.

### 2번 — `maxPerRoute` 5 에 막힌다

`0` 을 넘기면 빌더가 그 값을 덮어쓰지 않으므로 "설정하지 않음" 이 된다.

```bash
./scripts/run-case.sh "total200 perRoute미설정" 200 0  false
./scripts/run-case.sh "둘 다 미설정"              0   0  false
./scripts/run-case.sh "total200 perRoute50"     200 50 false
```

실제로 뭐가 적용됐는지는 기동 로그(`pool: maxTotal=…, maxPerRoute=…`)에서 읽어 결과에 같이 찍는다.

| # | 조건 | 실제 적용값 | 평균 | TPS | 부하 중 |
| --- | --- | --- | --- | --- | --- |
| 1 | total 200, perRoute 미설정 | maxTotal=200, **maxPerRoute=5** | 740.7ms | 66 | leased=5 pending=45 |
| 2 | 둘 다 미설정 | maxTotal=25, **maxPerRoute=5** | 741.8ms | 66 | leased=5 pending=45 |
| 3 | total 200, perRoute 50 | maxTotal=200, maxPerRoute=50 | 73.7ms | **676** | leased=50 pending=0 |

1·2 가 **완전히 같다.** `maxTotal` 을 25 에서 200 으로 8배 늘려도 TPS 가 66 에서 66 이다. 업스트림이 하나면 route 도 하나뿐이라 `maxPerRoute` 가 먼저 걸리고, `maxTotal` 은 도달할 일이 없는 숫자다. perRoute 까지 올리면 **TPS 가 10배**가 된다.

`leased=5 pending=45` 가 그림을 그대로 보여준다. 50개 요청 중 5개만 커넥션을 잡고 45개는 큐에서 기다린다.

라이브러리 기본값은 perRoute **5** / total **25** 다(httpclient5 5.4.2, 기동 로그로 확인). `PoolingHttpClientConnectionManagerBuilder` 는 값이 0보다 클 때만 덮어쓰므로, 안 건드리면 그대로다.

### 3번 — 풀 사이즈와 TPS

VU 50 고정이므로 동시성은 항상 50 이다. 필요한 커넥션도 50 이어야 한다. 풀 크기만 바꾸며 다섯 번 돌린다.

```bash
for n in 1 25 50 100 500; do ./scripts/run-case.sh "풀 $n" $n $n false; done
```

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

먼저 커넥션 수립 비용을 `curl` 로 분해한다. 매번 새 커넥션이어야 하므로 `Connection: close` 로 쏘고, 첫 요청은 ARP 에 1 RTT 를 더 쓰므로 3회 중앙값을 쓴다(아래). TLS 는 1.3 으로 협상됐다.

```bash
# 브리지 네트워크 안에서 (호스트에서 쏘면 publish 된 포트가 핸드셰이크 비용을 가린다)
docker run --rm --network docker_default pool-lab-net sh -c \
  "curl -sk -o /dev/null -H 'Connection: close' \
        -w '%{time_connect} %{time_appconnect}\n' https://upstream-tls:8443/echo"
```

`curl` 의 타이머는 구간 길이가 아니라 **요청 시작부터의 누적값**이다. 스톱워치 랩타임이라고 보면 된다.

```
요청 시작
  │
  ├─ time_namelookup     DNS 이름 해석 끝
  │
  ├─ time_connect        TCP 핸드셰이크 끝 (SYN → SYN-ACK → ACK)
  │
  ├─ time_appconnect     TLS 핸드셰이크 끝 — 암호화 통로 완성, 아직 요청 안 보냄
  │
  ├─ time_starttransfer  첫 바이트 도착 (= TTFB)
  │
  └─ time_total          응답 다 받음
```

표의 두 열이 가리키는 건 각각 이렇다.

- **`connect`** — TCP 핸드셰이크(SYN → SYN-ACK → ACK)가 끝난 시점이다. 여기까지면 바이트를 흘릴 수는 있지만 아직 평문이고, http 는 이 다음에 바로 요청을 보낸다. 앞단의 DNS 해석 시간(`time_namelookup`)도 누적값이라 이 안에 들어 있다.
- **`appconnect`** — TLS 핸드셰이크까지 끝난 시점이다. TCP 위에 얹히는 애플리케이션 레벨 커넥션이라 이 이름이 붙었고, https 일 때만 값이 찍힌다.

그래서 **TLS 핸드셰이크만의 비용은 `appconnect - connect`** 다 — 아래 세 줄이 순서대로 27.8 / 41.7 / 66.7ms 다.

| RTT | http `connect` | https `connect` | https `appconnect`(TLS 완료) |
| --- | --- | --- | --- |
| 0ms | 1.1ms | 0.9ms | **28.7ms** |
| 20ms | 21.5ms | 24.3ms | **66.0ms** |
| 50ms | 51.9ms | 53.7ms | **120.4ms** |

**RTT 가 0이어도 https 는 28.7ms 가 든다.** TLS 핸드셰이크는 왕복만 드는 게 아니라 비대칭키 연산이라는 CPU 비용이 따로 있다. "RTT × 왕복수" 로만 예측했던 게 여기서 틀렸다. RTT 가 붙으면 그 위에 왕복분이 더해져서, 수립 비용이 http 의 **2~3배**가 된다.

<details markdown="1">
<summary>첫 요청이 튀는 건 DNS 가 아니라 ARP 였다</summary>

같은 컨테이너에서 curl 프로세스를 여섯 번 돌리면 1회차만 `connect` 가 두 배다. 그런데 `namelookup` 은 거의 그대로다.

| 회차 | `namelookup` | `connect` |
| --- | --- | --- |
| 1 | 1.56ms | **44.7ms** |
| 2 | 1.08ms | 21.8ms |
| 3~6 | 0.8~1.2ms | 21.7~23.7ms |

DNS 몫은 0.5ms 뿐이다. 원인을 둘로 갈라봤다.

```bash
# A. DNS 만 미리 녹여놓고 쏜다
docker run --rm --network docker_default pool-lab-net sh -c \
  'getent hosts upstream-tls >/dev/null; curl -sk -o /dev/null -H "Connection: close" \
     -w "connect=%{time_connect}\n" https://upstream-tls:8443/echo'
# -> connect=0.042950   그대로 튄다

# B. ping 으로 ARP 까지 미리 하고 쏜다
docker run --rm --network docker_default pool-lab-net sh -c \
  'ping -c2 upstream-tls >/dev/null; curl -sk ... '
# -> connect=0.022295   안 튄다
```

같은 브리지 서브넷이라 SYN 을 내보내려면 커널이 상대의 MAC 을 먼저 알아야 한다. 컨테이너가 막 떴을 때는 이웃 테이블이 비어 있어서, SYN 이 큐에 붙들린 채 ARP request 가 나갔다 reply 가 돌아오기를 기다린다. 그 왕복에도 netem 지연이 똑같이 걸려서 1 RTT 가 더 붙는다. ping 출력 자체가 같은 얘기를 한다 — `min/avg/max = 20.578/31.452/42.327`, 첫 패킷만 두 배다.

```
--- 컨테이너 시작 직후
(이웃 테이블 비어 있음)
--- curl 1회 후
172.21.0.6 dev eth0 lladdr 02:42:ac:15:00:06 REACHABLE
```

한 번 `REACHABLE` 이 되면 수십 초 유지되니 이후 요청은 1 RTT 만 낸다. **"커넥션 수립 = SYN 왕복" 모델에 없는 L2 해석 단계가 첫 패킷에만 끼는 것이다.**

DNS 가 싼 건 이 환경 덕이다. 컨테이너의 리졸버가 Docker 내장 DNS(`127.0.0.11`)고, 컨테이너 이름은 데몬이 자기 테이블에서 바로 답한다. 그 경로는 업스트림에 걸어둔 netem 도 타지 않는다. 외부 도메인이면 리졸버까지 나가느라 수십 ms 가 붙고, 그때는 첫 요청이 DNS 때문에 튀는 게 맞다. `curl` 의 `time_connect` 은 프로세스 시작부터의 누적값이라 `time_namelookup` 을 포함하므로, 그랬다면 위 표의 `connect` 열에 그대로 드러난다.

</details>

부하를 걸어 TPS 로 보면 이렇다. 프로토콜은 업스트림 주소로, 본문 크기는 `SIZE_BYTES` 로 바꾼다. (RTT 20ms)

```bash
./scripts/run-case.sh "http"  50 50 false           # 재사용 O / X 는 마지막 인자
UPSTREAM_BASE_URL=https://upstream-tls:8443 ./scripts/run-case.sh "https" 50 50 false
SIZE_BYTES=102400 ./scripts/run-case.sh "100KB" 50 50 false
```

| # | | 재사용 O | 재사용 X | 차이 | TPS |
| --- | --- | --- | --- | --- | --- |
| 1 | http | 73.9ms | 95.2ms | **+21.3ms** | 675 → 524 (-22%) |
| 2 | https | 73.8ms | 147.1ms | **+73.3ms** | 674 → 338 (**-50%**) |
| 3 | http, 본문 100KB | 74.1ms | 154.8ms | **+80.7ms** | 672 → 321 (-52%) |

**재사용만 되면 프로토콜이 무의미해진다.** 첫 열이 전부 74ms 다. https 든 100KB 든 핸드셰이크를 이미 치러둔 커넥션을 쓰면 차이가 없다.

**재사용을 잃었을 때의 손해가 https 는 http 의 3.4배다**(73.3 / 21.3). 원래 질문이었던 "https 일수록 이득이 큰가"의 답이 이 숫자다. TPS 는 절반이 된다.

#### 그 CPU 비용은 얼마인가

`appconnect` 에 섞인 CPU 비용을 시간이 아니라 **CPU 사용량**으로 직접 잰다. 컨테이너 cgroup 의 `cpuacct.usage` 증분을 요청 수로 나눴다.

```bash
./scripts/run-cpu.sh https noreuse     # <http|https> <reuse|noreuse>
```

<details markdown="1">
<summary>cgroup CPU 증분 — <code>scripts/run-cpu.sh</code></summary>

```bash
#!/usr/bin/env bash
# 사용법: run-cpu.sh <http|https> <reuse|noreuse>
#
# 4번에서 TLS 핸드셰이크에 비대칭키 연산 CPU 비용이 있다는 걸 curl 로 봤다.
# 부하 중 caller/upstream 의 실제 CPU 사용량을 재서, 재사용이 그 비용을 얼마나 없애는지 본다.
# CPU 는 cgroup 의 cpuacct 누적값 증분으로 잰다(나노초). docker stats 의 순간값보다 안정적이다.
set -e
cd "$(dirname "$0")/.."
PROTO="$1"; REUSE="$2"
[ "$PROTO" = "https" ] && URL=https://upstream-tls:8443 && SRV=docker_upstream-tls_1 || { URL=http://upstream:8080; SRV=docker_upstream_1; }
[ "$REUSE" = "noreuse" ] && CLOSE=true || CLOSE=false
export POOL_MAX_TOTAL=50 POOL_MAX_PER_ROUTE=50 POOL_CONNECTION_REQUEST_TIMEOUT_MS=3000 \
       POOL_KEEP_ALIVE_MS=-1 POOL_VALIDATE_AFTER_INACTIVITY_MS=-1 POOL_EVICT_IDLE_MS=-1 \
       POOL_TIME_TO_LIVE_MS=-1 POOL_RETRY_ENABLED=false UPSTREAM_BASE_URL="$URL" \
       KEEP_ALIVE_TIMEOUT=60000 MAX_KEEP_ALIVE_REQUESTS=100
(cd docker && docker-compose up -d --force-recreate caller >/dev/null 2>&1)
for i in $(seq 1 60); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:9080/actuator/health)" = "200" ] && break
  sleep 1
done
# RTT 는 양쪽 업스트림에 똑같이 건다. https 쪽만 빼먹으면 TPS 비교가 어긋난다
TARGET="$SRV" VERIFY_URL="$URL/echo" ./scripts/netem.sh 20 >/dev/null 2>&1

cpu() { docker exec "$1" sh -c "cat /sys/fs/cgroup/cpuacct/cpuacct.usage"; }   # 나노초 누적

docker run --rm --network docker_default --cpus 2 -v "$PWD/k6:/scripts:ro" \
  -e VUS=50 -e DURATION=10s -e DELAY_MS=50 -e CLOSE="$CLOSE" -e MODE=safe \
  grafana/k6:0.53.0 run --quiet /scripts/scenario.js >/dev/null 2>&1   # 워밍업

C0=$(cpu docker_caller_1); U0=$(cpu "$SRV")
docker run --rm --network docker_default --cpus 2 -v "$PWD/k6:/scripts:ro" \
  -e VUS=50 -e DURATION=30s -e DELAY_MS=50 -e CLOSE="$CLOSE" -e MODE=safe \
  grafana/k6:0.53.0 run --quiet /scripts/scenario.js > /tmp/_cpu 2>&1
C1=$(cpu docker_caller_1); U1=$(cpu "$SRV")

REQ=$(grep -E "^ *http_reqs" /tmp/_cpu | sed -E 's/.*: ([0-9]+) .*/\1/')
TPS=$(grep -E "^ *http_reqs" /tmp/_cpu | sed -E 's#.* ([0-9.]+)/s.*#\1#')
CD=$((C1-C0)); UD=$((U1-U0))
# 요청 1건당 CPU(마이크로초) = 증분 / 요청 수
printf '%-5s %-8s | 요청 %-6s TPS %-5s | CPU 총 caller=%-7sms upstream=%-7sms | 요청당 caller=%-8sus upstream=%sus\n' \
  "$PROTO" "$REUSE" "$REQ" "${TPS%.*}" "$((CD/1000000))" "$((UD/1000000))" \
  "$(echo "scale=1; $CD/1000/$REQ" | bc)" "$(echo "scale=1; $UD/1000/$REQ" | bc)"
```

</details>

| # | 조건 | TPS | 요청당 caller CPU | 재사용 상실 비용 |
| --- | --- | --- | --- | --- |
| 1 | http 재사용 O | 664 | 1,835us | |
| 2 | http 재사용 X | 519 | 2,331us | **+496us** |
| 3 | https 재사용 O | 627 | 2,588us | |
| 4 | https 재사용 X | 262 | 7,719us | **+5,131us** |

**재사용을 잃었을 때 드는 CPU 가 https 는 http 의 10.3배다**(5,131 / 496). 업스트림 쪽도 +331us 대 +3,344us 로 10.1배다.

앞에서 응답시간으로 본 배수는 3.4배였는데 CPU 로는 10배다. **지연은 기다리는 시간(RTT)이 섞여서 희석되지만 CPU 는 순수한 연산**이라 그렇다. 커넥션당 비용이니 TPS 가 높을수록 그대로 곱해진다 — 초당 500 커넥션이면 캘러 코어 2.5개어치다.

1 과 3 의 차이(1,835 → 2,588us)는 핸드셰이크와 별개다. **재사용이 잘 되고 있어도 https 는 요청당 CPU 가 41% 더 든다.** 이건 핸드셰이크가 아니라 레코드 암복호화(대칭키) 비용이라 재사용으로 없앨 수 없는 몫이다.

> 업스트림 CPU 를 http 와 https 사이에 직접 비교하면 안 된다. `upstream` 에만 톰캣 MBean 레지스트리가 켜져 있어서 조건이 다르다. 같은 컨테이너에서 재사용만 켰다 껐다 한 **증분**은 유효하다.

3 이 slow start 다. 본문 0바이트일 때 재사용 상실 비용은 21.3ms(= 1 RTT, 핸드셰이크)인데, 100KB 면 80.7ms 로 는다. 늘어난 **59.4ms 는 핸드셰이크가 아니라 congestion window 를 키우는 시간**이다. RTT 20ms 로 나누면 약 3 RTT — 초기 cwnd 로는 100KB 를 한 번에 못 밀어서 세 번 더 왕복한 것이다. 같은 100KB 도 cwnd 가 이미 커져 있는 커넥션에서는 0.2ms 밖에 안 든다.

<details markdown="1">
<summary>congestion window 와 slow start — 왜 100KB 가 세 번 왕복하나</summary>

애플리케이션이 `write` 로 100KB 를 넘겨도 그게 곧바로 선로로 나가는 건 아니다. 두 단계가 따로다.

```
애플리케이션:  write(socket, 데이터)   -> 커널 송신 버퍼에 복사하고 바로 리턴
커널(TCP):     버퍼에서 꺼내 세그먼트로 쪼개 내보낸다
               ^ 지금 당장 얼마나 내보낼지는 커널이 정한다
```

그 "얼마나"가 **congestion window(cwnd)** 다. ACK 를 아직 못 받은 채로 네트워크에 띄워둘 수 있는 최대 바이트 수이고, 송신 측 커널이 혼자 들고 있는 값이다. 중간 경로가 초당 몇 바이트를 버티는지는 아무도 알려주지 않는다. 처음부터 전속력으로 쏘면 라우터 큐가 넘쳐 패킷이 버려지고 그 재전송이 혼잡을 더 키우니, 작게 시작해서 올려본다.

수신 측이 헤더로 통보하는 receive window 와는 다른 값이다.

| | 누가 정하나 | 무엇을 막나 |
| --- | --- | --- |
| receive window (rwnd) | 수신 측이 TCP 헤더로 통보 | 받는 쪽 버퍼 넘침 |
| **congestion window (cwnd)** | 송신 측이 스스로 추정 | 중간 네트워크 혼잡 |

지금 나갈 수 있는 양은 `min(cwnd, rwnd)` 다.

**slow start** 는 커넥션이 새로 섰을 때 cwnd 를 ACK 가 돌아올 때마다 두 배로 키우는 구간이다. 이름은 slow 지만 증가는 지수적이다. 리눅스 초기값은 10 MSS 고, 임계치(`ssthresh`)에 닿거나 손실이 보이면 그 뒤로는 선형으로 천천히 올린다. 실제 소켓에서 둘 다 보인다.

```bash
# 컨테이너의 네트워크 네임스페이스를 공유해서 소켓을 본다 (caller 이미지에는 ss 가 없다)
docker run --rm --network container:docker_caller_1 pool-lab-net \
  ss -tin state established "( dport = :8080 )"
```

```
# caller 쪽 소켓 — 작은 요청만 보내니 초기값 그대로다
mss:1448 pmtu:1500 cwnd:10 bytes_sent:633 ... snd_wnd:64768

# upstream 쪽 소켓 — 본문을 2MB 쯤 보낸 뒤. 10 에서 올라가 ssthresh 에 닿았다
mss:1448 pmtu:1500 cwnd:16 ssthresh:16 bytes_sent:2038433 ...
```

MSS 1448 로 100KB 를 나눠 보내면 이렇게 된다.

| 왕복 | 그 번에 나갈 수 있는 양 | 누적 |
| --- | --- | --- |
| 1 | 10 × 1448 = 14.5KB | 14.5KB |
| 2 | 20 × 1448 = 29.0KB | 43.4KB |
| 3 | 40 × 1448 = 57.9KB | **101.3KB** |

세 번 나눠 보내고 사이사이 ACK 를 기다리니 위의 59.4ms 가 나온다. **그 시간은 데이터가 느려서가 아니라 커널이 "더 보내도 되나"를 세 번 확인한 시간이다.**

cwnd 는 소켓에 붙은 상태라서 같은 커넥션을 계속 쓰면 커진 값이 남아 있다. 그래서 같은 100KB 가 0.2ms 다. 다만 영원하지는 않다.

```
net.ipv4.tcp_slow_start_after_idle = 1
net.ipv4.tcp_congestion_control = cubic
rto:201     # 소켓의 재전송 타이머. ss -i 출력에 찍힌다
```

이 값이 1 이면 **유휴가 RTO(여기선 약 200ms)를 넘긴 커넥션은 cwnd 가 초기값으로 되돌려진다.** 소켓은 `ESTABLISHED` 로 멀쩡한데 cwnd 만 리셋된다. 풀 입장에서는, 재사용이 핸드셰이크는 확실히 아껴주지만 **띄엄띄엄 쓰이는 커넥션에서는 slow start 비용은 다시 낼 수 있다**는 뜻이다. (이 리셋 동작은 sysctl 과 커널 동작 기준이고 재보지는 않았다. 위 `ss` 출력도 netem 을 뗀 상태에서 본 것이라, 20ms 조건의 재현이 아니라 cwnd 가 어떤 값인지 보려고 붙였다.)

</details>

### 5·6번 — 재사용이 꺼져도 풀은 동시성 상한으로 남는다

3번과 같은 방식인데 재사용을 켠 것과 끈 것을 나란히 둔다.

```bash
for n in 5 25 50; do
  ./scripts/run-case.sh "풀 $n 재사용O" $n $n false
  ./scripts/run-case.sh "풀 $n 재사용X" $n $n true
done
```

앞 숫자는 k6 가 잰 평균 응답시간(`http_req_duration` 의 `avg`)이고 뒤가 TPS 다. 3번 표의 `평균` 열과 같은 값이다.

| 풀 | 재사용 O (평균/TPS) | 재사용 X (평균/TPS) | 부하 중 |
| --- | --- | --- | --- |
| 5 | 732.5ms / 67 TPS | 965.1ms / 51 TPS | leased=5 pending=45 **callerThreads=51** |
| 25 | 146.2ms / 340 TPS | 187.8ms / 265 TPS | leased=25 pending=25 **callerThreads=51** |
| 50 | 75.3ms / 662 TPS | 95.2ms / 524 TPS | leased=50 pending=0 **callerThreads=51** |

응답시간을 먼저 읽어야 표가 보인다. **732.5ms 중 일한 시간은 75ms 뿐이다.** 풀 50 일 때의 75.3ms 가 줄을 안 섰을 때의 순수 작업시간(업스트림 `delayMs=50` + RTT 20ms + 나머지)이고, 풀이 5 면 동시 요청 50개가 커넥션 5개를 돌려쓰니 열 배로 직렬화된다 — `75.3 × 10 ≈ 753ms`, 실측 732.5ms. 나머지 657ms 는 lease 를 기다린 시간이고, 그 대기자 수가 오른쪽의 `pending=45` 다. 재사용 X 열도 같은 식이다 — 4번에서 핸드셰이크를 매번 내면 요청당 95.2ms 였으니 `95.2 × 10 ≈ 952ms`, 실측 965.1ms.

**재사용이 꺼져도 TPS 는 풀 사이즈에 정비례한다.** 5:25:50 에 51:265:524 로 거의 정확히 1:5:10 이다. 재사용이라는 기능이 빠져도 **동시성 상한이라는 기능은 그대로 남는다** — 풀이 세마포어로 격하된다는 게 이 뜻이다.

6번은 맨 오른쪽 열이다. **`callerThreads` 가 풀 크기와 무관하게 항상 51 이다.** 풀이 5든 50이든 caller 톰캣 스레드 51개는 똑같이 점유된다. 풀 5 일 때 46개는 커넥션을 못 빌려 lease 대기에서 블록돼 있을 뿐이다. `leased + pending = 50` 으로 VU 수와 정확히 맞는다.

### 7·8번 — 상한만으로는 격리가 안 된다

caller 에 업스트림을 **전혀 부르지 않는** `/local` 엔드포인트를 두고, 느린 `/call` 과 **동시에** 때린다. 여기만 k6 시나리오가 다르다.

```js
// k6/bulkhead.js — 두 시나리오를 같이 돌린다
slow:  { executor: 'constant-arrival-rate', rate: 100, timeUnit: '1s', duration: '30s' }  // GET /call?delayMs=3000
local: { executor: 'constant-arrival-rate', rate: 20,  timeUnit: '1s', duration: '30s' }  // GET /local
```

```bash
./scripts/run-bulkhead.sh "CRT 60s" 50 60000     # <설명> <풀 크기> <connectionRequestTimeout ms>
```

<details markdown="1">
<summary>두 API 동시 부하 — <code>scripts/run-bulkhead.sh</code></summary>

```bash
#!/usr/bin/env bash
# 사용법: run-bulkhead.sh "<설명>" <POOL> <CRT_MS>   (CRT_MS 음수 = 무한 대기)
set -e
cd "$(dirname "$0")/.."
DESC="$1"; POOL="$2"; CRT="$3"
export POOL_MAX_TOTAL="$POOL" POOL_MAX_PER_ROUTE="$POOL" POOL_CONNECTION_REQUEST_TIMEOUT_MS="$CRT"
(cd docker && docker-compose up -d --force-recreate caller >/dev/null 2>&1)
for i in $(seq 1 60); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:9080/actuator/health)" = "200" ] && break
  sleep 1
done
gauge() { curl -s http://localhost:9080/actuator/prometheus | awk -v s="$1" '$0 ~ s && $0 !~ /^#/ {printf "%d", $2}'; }
sock() { docker exec docker_caller_1 sh -c "awk 'NR>1 && \$4==\"$1\" && \$3 ~ /:1F90\$/ {n++} END {print n+0}' /proc/net/tcp"; }

( docker run --rm --network docker_default --cpus 2 -v "$PWD/k6:/scripts:ro" \
    -e SLOW_VUS="${SLOW_VUS:-250}" -e DURATION=30s -e DELAY_MS="${DELAY_MS:-3000}" \
    grafana/k6:0.53.0 run --quiet /scripts/bulkhead.js > /tmp/_bh 2>&1 ) &
sleep 18
MID="threads=$(gauge '^tomcat_threads_busy') leased=$(gauge 'state="leased"') pending=$(gauge 'pool_total_pending') EST=$(sock 01)"
wait
OUT=$(cat /tmp/_bh)
m() { echo "$OUT" | grep -E "^ *$1\\.*" | sed -E "s/.*avg=([^ ]+).*p\\(95\\)=([^ ]+).*/\\1 \\2/"; }
read -r CALL_AVG CALL_P95 <<< "$(m call_duration)"
read -r LOC_AVG LOC_P95 <<< "$(m local_duration)"
FAIL=$(echo "$OUT" | grep -E "^ *call_failed" | sed -E "s/.*: ([0-9.]+%).*/\\1/")
RPS=$(echo "$OUT" | grep -E "^ *http_reqs" | sed -E "s#.* ([0-9.]+)/s.*#\\1#")
printf '%-20s | call avg=%-9s p95=%-9s | local avg=%-9s p95=%-9s | 실패=%-7s | %s\n' \
  "$DESC" "$CALL_AVG" "$CALL_P95" "$LOC_AVG" "$LOC_P95" "$FAIL" "$MID"
```

</details>

> **도착률 고정(`constant-arrival-rate`)이 핵심이다.** VU 고정으로 주면 빨리 실패하는 조건이 그만큼 더 쏘게 돼서 두 조건의 오퍼 부하가 달라진다. 처음에 `constant-vus` 로 돌렸다가 비교가 성립하지 않아 바꿨다.

`/call` 과 `/local` 은 별도 `Trend` 로 따로 집계하고, `callerThreads`·`leased`·`ESTABLISHED` 는 18초 시점에 한 번 뜬다.

| # | 조건 | `/call` p95 | **`/local` p95** | 실패율 | callerThreads | leased | ESTABLISHED |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | CRT 60초 (사실상 무한) | 30.0s | **20.36s** | 0% | **200** | 50 | 50 |
| 2 | CRT 200ms | 3.09s | **2.28ms** | 83% | 71 | 50 | 50 |
| 3 | CRT 0 (`Timeout.DISABLED`) | 3.0s | 2.55ms | 83% | 50 | 49 | 50 |
| 4 | **풀 10000**, CRT 0 | 7.89s | **4.89s** | 0% | **200** | 198 | **200** |

**풀 상한이 있어도 포기가 없으면 소용없다.** 1 에서 caller 톰캣 스레드 200개가 전부 먹히고, **업스트림을 전혀 안 부르는 `/local` 의 p95 가 20.36초**가 됐다. 풀이 막아준 건 소켓 50개뿐이고, 막지 못한 건 스레드 200개다. 소켓 점유가 스레드 점유로 자리를 옮겼을 뿐이다.

`connectionRequestTimeout` 을 200ms 로 주면 `/local` p95 가 **2.28ms** 다. 약 9,000배 차이다. `/call` 은 83% 가 실패하지만, 그게 격리가 하는 일이다 — 살릴 수 없는 요청을 빨리 포기해서 나머지를 살린다. 흔히 bulkhead 라 부르는 것이 이 동작이다.

4 가 8번이다. 상한을 사실상 없애면(10000) ESTABLISHED 가 **200개**까지 늘고 `/local` p95 도 4.89초로 무너진다. 200 에서 멈춘 건 caller 톰캣 스레드가 200개라서지 풀이 막은 게 아니다.

3 은 `connectionRequestTimeout` 을 0(`Timeout.DISABLED`)으로 둔 경우다. **무한 대기가 아니라 즉시 실패**다. 스레드가 50에 머물고 83% 가 곧바로 떨어졌다. "무한"을 표현하려면 0 이 아니라 충분히 큰 값을 줘야 한다.

### 9~12번 — stale connection

먼저 **예측이 틀렸다.** 서버 `keepAliveTimeout` 을 1초로 줄이고 클라이언트 검증 주기(2초)보다 짧게 만들어 사각지대를 내려 했는데, 몇 번을 돌려도 재현되지 않았다. 디버그 로그에 답이 있었다.

```
ex-0000000004 connection can be kept alive for 1 SECONDS
```

**톰캣이 `Keep-Alive: timeout=1` 로 자기 타임아웃을 알려주고, HttpClient5 가 그 말을 지킨다.** 위에서 본 `DefaultConnectionKeepAliveStrategy` 가 그 헤더를 읽어 풀 엔트리의 만료 시각을 1초로 잡으니, `validateAfterInactivity`(2초) 가 개입할 일도 없이 그 전에 버려진다. 서버가 알려주는 한 사각지대는 생기지 않는다.

이 헤더에는 조건이 있다. **클라이언트가 `Connection: keep-alive` 를 명시해야** 톰캣이 붙인다.

```
$ curl -D - -H 'Connection: keep-alive' http://upstream:8080/echo
Keep-Alive: timeout=1
Connection: keep-alive

$ curl -D - http://upstream:8080/echo
(둘 다 없음)
```

HttpClient5 는 명시해서 보내므로 힌트를 받는다.

**이 `timeout=N` 의 출처는 톰캣 커넥터의 `keepAliveTimeout` 이고, 스프링 부트에서는 `server.tomcat.keep-alive-timeout` 이다.** 여기서 upstream 쪽 서버 설정은 이것뿐이다.

```yaml
# upstream/src/main/resources/application.yml
server:
  tomcat:
    keep-alive-timeout: ${KEEP_ALIVE_TIMEOUT:60000}          # 9번은 1000, 13번은 5000 으로 띄운다
    max-keep-alive-requests: ${MAX_KEEP_ALIVE_REQUESTS:100}
```

부트가 하는 일은 이 값을 커넥터의 프로토콜 핸들러에 꽂는 것뿐이다.

```java
// org.springframework.boot.autoconfigure.web.embedded.TomcatWebServerFactoryCustomizer.java
map.from(properties::getKeepAliveTimeout).whenNonNull()
        .to(keepAliveTimeout -> customizeKeepAliveTimeout(factory, keepAliveTimeout));

private void customizeKeepAliveTimeout(ConfigurableTomcatWebServerFactory factory, Duration keepAliveTimeout) {
    factory.addConnectorCustomizers(connector -> {
        ProtocolHandler handler = connector.getProtocolHandler();
        // ... HTTP/2 업그레이드 프로토콜에도 같이 꽂는다
        if (handler instanceof AbstractProtocol<?> protocol) {
            protocol.setKeepAliveTimeout((int) keepAliveTimeout.toMillis());
        }
    });
}
```

헤더를 실제로 쓰는 자리는 톰캣에 한 군데다. 위 curl 결과가 여기서 나온다.

```java
// org.apache.coyote.http11.Http11Processor.java — prepareResponse()
if (protocol.getUseKeepAliveResponseHeader()) {
    boolean connectionKeepAlivePresent = isConnectionToken(
            request.getMimeHeaders(), Constants.KEEP_ALIVE_HEADER_VALUE_TOKEN);   // 요청에 keep-alive 가 있나
    if (connectionKeepAlivePresent) {
        int keepAliveTimeout = protocol.getKeepAliveTimeout();
        if (keepAliveTimeout > 0) {
            String value = "timeout=" + keepAliveTimeout / 1000L;                 // ms -> 초, 정수 나눗셈
            headers.setValue(Constants.KEEP_ALIVE_HEADER_NAME).setString(value);
            // ... Connection: keep-alive 도 같이 붙인다
```

**안 설정하면 `connectionTimeout` 이 쓰인다.** 필드가 `Integer` 라서 null 이면 커넥션 타임아웃으로 떨어지고, 부트는 `server.tomcat.connection-timeout` 에도 기본값을 주지 않으니 톰캣의 `soTimeout` 기본값 20초가 남는다. **아무것도 설정하지 않은 부트 서버는 `Keep-Alive: timeout=20` 을 알려준다**는 뜻이다. `-1` 로 주면 타임아웃이 없고, `max-keep-alive-requests` 를 0 이나 1 로 주면 keep-alive 자체가 꺼진다(응답에 `Connection: close` 가 붙는 12번의 모양이 된다).

```java
// org.apache.tomcat.util.net.AbstractEndpoint.java
public int getKeepAliveTimeout() {
    if (keepAliveTimeout == null) {
        return getConnectionTimeout();     // = soTimeout, 기본 20000
    }
    return keepAliveTimeout.intValue();
}
```

**1초 미만으로 주면 거꾸로 사각지대가 생긴다.** 헤더 단위가 초이고 정수 나눗셈이라 `keep-alive-timeout: 500ms` 는 `timeout=0` 으로 나간다. 클라이언트는 그 값을 `TimeValue.ofSeconds(0)` 으로 읽고, 양수가 아닌 값은 `Deadline.calculate` 가 `MAX_VALUE` 로 바꾼다 — **`timeToLive` 외에 만료가 없는 엔트리**가 된다. 톰캣은 0.5초에 끊는데 풀은 무기한 들고 있는 셈이고, 디버그 로그도 `can be kept alive for 1 SECONDS` 가 아니라 `indefinitely` 로 찍힌다. 소스를 따라간 결론이고 실측은 안 했다 — 9번은 `timeout=1` 이 나오는 1000ms 로 돌렸다.

그래서 진짜 stale 은 **말없이 끊는 무언가**로 만들어야 한다. 여기서는 중간 장비를 쓴다(클라이언트 쪽에서 그 말을 무시하게 만들어도 된다 — 13번). 톰캣은 `timeout=60` 을 알려주게 두고(위 `keep-alive-timeout: 60000`), 경로 중간의 toxiproxy 가 그보다 먼저 아무 통보 없이 커넥션을 끊는다. LB·프록시가 idle timeout 으로 끊는 상황과 같은 모양이다.

**여기서 "말없이" 는 끊긴다는 사실이 요청-응답 대화에 실려 오지 않는다는 뜻이다.** 마지막 응답은 `Keep-Alive: timeout=60` 으로 "계속 써도 된다"고 말한 상태였고, 그 뒤에 오는 건 HTTP 메시지가 아니라 TCP 세그먼트 하나(FIN)다. 어떤 요청에도 속하지 않으니 클라이언트의 HTTP 계층에는 들어올 자리가 없다. 통보가 어느 층에 오는지로 갈라보면 이렇다.

| 어떻게 끊나 | 신호 | HTTP 계층이 아나 | 커널이 아나 |
| --- | --- | --- | --- |
| 응답에 `Connection: close` | HTTP 헤더 | **안다** — 그 응답을 읽는 중이다 | 안다 |
| **FIN 만 보낸다** (여기, LB idle timeout) | TCP | 모른다 | **안다** — `CLOSE_WAIT` |
| RST | TCP | 모른다 | 안다 — 소켓이 에러로 바뀐다 |
| 패킷만 버린다 (방화벽 blackhole) | 없음 | 모른다 | **모른다** — `ESTABLISHED` 로 남는다 |

여기서 만든 건 둘째 줄이다. toxiproxy 를 껐다 켜면 FIN 이 오므로 `/proc/net/tcp` 에 `CLOSE_WAIT` 으로 찍힌다 — 아래 표의 `CLOSE_WAIT=1` 이 그 증거다. 넷째 줄이 제일 고약한데 커널조차 모르니 `isStale()` 로도 안 걸러진다. 그건 뒤의 D4 에서 따로 재현했다. RST 줄만 재현하지 않았다.

```
 caller (풀)              toxiproxy              upstream (톰캣)
     │                        │                        │
 1)  ├─── GET /call ─────────►├───────────────────────►│
     │◄─── 200 + Keep-Alive: timeout=60 ───────────────┤
     │   풀: available=1  "60초는 재사용해도 된다"
     │                        │                        │
 2)  │                 disable → enable                │  ← 톰캣은 아무 말도 안 했다
     │◄─── FIN ───────────────┤                        │
     │   풀: available=1 (그대로)  /  커널: CLOSE_WAIT=1
     │                        │                        │
 3)  ├─── GET /call ─────────►✗   쓰기는 성공 (half-close)
     │                            읽기에서 EOF
     │   → NoHttpResponseException
```

**2)에서 FIN 을 받았는데 왜 풀에서 안 닫히나.** 커널에서 소켓은 `CLOSE_WAIT` 으로 가지만 `PoolEntry` 는 `available` 에 그대로 남는다. blocking 클라이언트라 **유휴 소켓을 읽고 있는 스레드가 없어서** EOF 가 도착한 걸 아무도 못 본다. 비동기 클라이언트라면 I/O 리액터가 그 fd 를 selector 에 올려둔 채라 즉시 안다. `conn.isOpen()` 도 도움이 안 된다 — 하는 일이 `socketHolderRef.get() != null`, 즉 **"내가 닫았나"** 뿐이다.

그래서 죽은 걸 알아채는 지점은 세 군데고, 전부 누군가 건드려야 돌아간다.

| 언제 | 무엇이 | 하는 일 |
| --- | --- | --- |
| lease 직전 | `timeToLive` 만료 | `discardConnection(GRACEFUL)` |
| lease 직전 | `validateAfterInactivity`(기본 2초) 경과 | `conn.isStale()` → `discardConnection(IMMEDIATE)` |
| 백그라운드 | `evictIdleConnections` | 기본 꺼짐. 안 켜면 아무도 안 돈다 |

`isStale()` 이 FIN 을 실제로 확인하는 유일한 코드다. **1ms 타임아웃으로 소켓을 한 번 읽어보고** EOF(`bytesRead < 0`)면 죽은 것으로 본다.

끊은 건 2)의 중간 장비인데 풀이 들고 있는 유효기간은 1)에서 받은 60초다. 그 사이를 메우는 건 클라이언트 쪽 검증뿐이고, 그게 언제 도는지가 9번과 11번을 가른다.

부하가 아니라 **커넥션 1개로 딱 2번** 쏜다. 첫 요청으로 풀에 커넥션을 만들고, 그걸 죽인 뒤, 두 번째 요청이 그 커넥션을 집게 한다.

```bash
./scripts/run-stale.sh -1 false 0.3      # <validateAfterInactivity ms> <재시도> <idle 초>

# 1) curl localhost:9080/call                      → 풀에 커넥션 1개
# 2) toxiproxy 를 disable → enable                  → 중간 장비가 통보 없이 끊는다
# 3) sleep <idle>                                   → 검증 주기의 앞/뒤를 가른다
# 4) 풀 게이지 + /proc/net/tcp 를 찍고                → "요청 전 상태" 열
# 5) curl localhost:9080/call                      → 이 요청의 결과가 표의 HTTP 코드
```

<details markdown="1">
<summary>말없이 끊긴 커넥션 — <code>scripts/run-stale.sh</code></summary>

```bash
#!/usr/bin/env bash
# 사용법: run-stale.sh <VALIDATE_MS> <RETRY_ENABLED> <IDLE_SEC>
#
# upstream(톰캣)은 Keep-Alive: timeout=60 을 알려준다. 클라이언트는 그 말을 믿는다.
# 그런데 경로 중간의 toxiproxy 가 그보다 먼저, 아무 통보 없이 커넥션을 끊는다.
# 실제 LB·프록시가 idle timeout 으로 끊는 상황과 같은 모양이다.
set -e
cd "$(dirname "$0")/.."
VALIDATE="$1"; RETRY="$2"; IDLE="$3"
export POOL_VALIDATE_AFTER_INACTIVITY_MS="$VALIDATE" POOL_RETRY_ENABLED="$RETRY" \
       POOL_MAX_TOTAL=50 POOL_MAX_PER_ROUTE=50 POOL_CONNECTION_REQUEST_TIMEOUT_MS=3000 \
       UPSTREAM_BASE_URL=http://toxiproxy:8666 \
       KEEP_ALIVE_TIMEOUT=60000 MAX_KEEP_ALIVE_REQUESTS=100
(cd docker && docker-compose up -d --force-recreate caller upstream toxiproxy >/dev/null 2>&1)
for i in $(seq 1 60); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:9080/actuator/health)" = "200" ] && break
  sleep 1
done
sock() { docker exec docker_caller_1 sh -c "awk 'NR>1 && \$4==\"$1\" && \$3 ~ /:21DA\$/ {n++} END {print n+0}' /proc/net/tcp"; }  # 8666 = 21DA
gauge() { curl -s http://localhost:9080/actuator/prometheus | awk -v s="$1" '$0 ~ s && $0 !~ /^#/ {printf "%d", $2}'; }

curl -s -o /dev/null http://localhost:9080/call                                   # 커넥션 하나를 풀에 만든다
curl -s -X POST -d '{"enabled":false}' http://localhost:8474/proxies/upstream_http >/dev/null  # 중간 장비가 말없이 끊는다
curl -s -X POST -d '{"enabled":true}'  http://localhost:8474/proxies/upstream_http >/dev/null
sleep "$IDLE"
BEFORE="available=$(gauge 'state="available"') ESTABLISHED=$(sock 01) CLOSE_WAIT=$(sock 08)"
N=$(docker logs docker_caller_1 2>&1 | wc -l)
code=$(curl -s -o /dev/null -m 20 -w '%{http_code}' http://localhost:9080/call)
err=$(docker logs docker_caller_1 2>&1 | tail -n +$((N+1)) | grep -oE "NoHttpResponseException|Connection reset|SocketException" | head -1)

V=$([ "$VALIDATE" -lt 0 ] && echo "2s(기본)" || echo "$((VALIDATE/1000))s")
printf '검증=%-8s 재시도=%-5s idle=%-5s | 요청 전: %-44s | HTTP %-3s | %s\n' \
  "$V" "$RETRY" "${IDLE}s" "$BEFORE" "$code" "${err:-예외없음}"
```

</details>

예외 이름은 4)와 5) 사이에 새로 찍힌 caller 로그에서 뽑는다.

| # | 클라 검증 | 재시도 | idle | 요청 전 상태 | 결과 | 예외 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 2초(기본) | off | 0.3초 | available=1, ESTABLISHED=0, **CLOSE_WAIT=1** | **HTTP 500** | `NoHttpResponseException` |
| 2 | 2초(기본) | on | 0.3초 | 〃 | HTTP 200 | (로그에만 남는다) |
| 3 | 2초(기본) | off | 3초 | 〃 | HTTP 200 | 없음 |

**9번** — idle 0.3초는 검증 주기 2초 안쪽이라 검증을 건너뛴다. 죽은 커넥션에 요청이 실리고, 쓰기는 half-close 라 성공한 뒤 읽기에서 터진다.

**10번** — 같은 조건에 재시도만 켜면 HTTP 200 이다. 예외는 로그에만 남고 호출자는 아무것도 모른다. `DefaultHttpRequestRetryStrategy` 의 비재시도 예외 목록에 `NoHttpResponseException` 이 없어서 멱등 요청이 조용히 한 번 더 나간다. **"우리는 이 문제 없는데요" 의 정체가 대개 이것이다.**

`DefaultHttpRequestRetryStrategy` 가 기본 생성자에서 넘기는 비재시도 예외는 여섯 개다.

```java
// org.apache.hc.client5.http.impl.DefaultHttpRequestRetryStrategy.java
public DefaultHttpRequestRetryStrategy(int maxRetries, TimeValue defaultRetryInterval) {
    this(maxRetries, defaultRetryInterval,
            Arrays.asList(                            // 재시도하지 않을 예외
                    InterruptedIOException.class,
                    UnknownHostException.class,
                    ConnectException.class,
                    ConnectionClosedException.class,
                    NoRouteToHostException.class,
                    SSLException.class),
            Arrays.asList(                            // 재시도할 상태 코드
                    HttpStatus.SC_TOO_MANY_REQUESTS,      // 429
                    HttpStatus.SC_SERVICE_UNAVAILABLE));  // 503
}

public DefaultHttpRequestRetryStrategy() {
    this(1, TimeValue.ofSeconds(1L));   // INSTANCE 가 쓰는 기본값
}
```

| 예외 | 왜 재시도하지 않나 |
| --- | --- |
| `InterruptedIOException` | 타임아웃·인터럽트 (`SocketTimeoutException` 이 여기 포함된다) |
| `UnknownHostException` | DNS 가 안 되면 다시 해도 안 된다 |
| `ConnectException` | 상대가 연결을 거부했다 |
| `ConnectionClosedException` | 응답 도중 끊김 — 서버가 요청을 받았을 수 있다 |
| `NoRouteToHostException` | 경로 자체가 없다 |
| `SSLException` | 핸드셰이크·인증서 문제 |

판정은 이 순서로 내려간다.

```java
// org.apache.hc.client5.http.impl.DefaultHttpRequestRetryStrategy.java — retryRequest()
@Override
public boolean retryRequest(HttpRequest request, IOException exception, int execCount, HttpContext context) {
    if (execCount > this.maxRetries) {
        return false;                       // 횟수 초과
    }
    if (this.nonRetriableIOExceptionClasses.contains(exception.getClass())) {
        return false;                       // 목록에 정확히 일치
    }
    for (Class<? extends IOException> rejectException : this.nonRetriableIOExceptionClasses) {
        if (rejectException.isInstance(exception)) {
            return false;                   // 목록의 하위 타입
        }
    }
    if (request instanceof CancellableDependency && ((CancellableDependency) request).isCancelled()) {
        return false;                       // 취소된 요청
    }
    // Retry if the request is considered idempotent
    return handleAsIdempotent(request);     // 여기까지 오면 메서드가 결정한다
}
```

`NoHttpResponseException` 은 이 목록에 없으므로 판정이 마지막 줄의 `Method.isIdempotent()` 로 내려간다. **비멱등은 POST·CONNECT 뿐**이고 GET·HEAD·PUT·DELETE·TRACE·OPTIONS 는 전부 재시도 대상이다. 멱등은 **HTTP 명세상 메서드의 성질**일 뿐이라, `GET /orders/pay?id=1` 처럼 GET 으로 상태를 바꾸는 API 도 라이브러리는 모르고 한 번 더 보낸다.

**기다리지도 않는다.** 생성자의 `defaultRetryInterval`(기본 1초)은 429·503 **응답** 경로에만 쓰인다. 예외 경로의 `getRetryInterval` 은 `DefaultHttpRequestRetryStrategy` 가 오버라이드하지 않아 인터페이스의 `default` 구현(`TimeValue.ZERO_MILLISECONDS`)이 그대로 남고, 실패한 그 자리에서 곧바로 다시 나간다.

전략과 무관하게 막히는 경우도 하나 있다. `HttpRequestRetryExec` 는 전략에 묻기 **전에** 요청 본문을 다시 읽을 수 있는지 보고, `InputStreamEntity` 처럼 `isRepeatable()` 이 false 면 어떤 전략을 줘도 재시도하지 않는다. 전략을 갈아끼우는 자리는 요청 단위인 `RequestConfig` 가 아니라 `HttpClientBuilder.setRetryStrategy(...)` 다.

**11번** — 앞 표의 1~3 은 모두 `available=1` 인데 `ESTABLISHED=0`, `CLOSE_WAIT=1` 이다. 풀이 "빌려줄 수 있다"고 세는 그 1개는 이미 끊긴 커넥션이다. 0번의 `leased` 와 같은 얘기가 `available` 쪽에서도 성립한다.

그런데 커넥션이 풀에서 **사라지는** 것 자체는 비정상이 아니다. 오히려 매일 일어난다. 문제는 **그걸 클라이언트가 아는 경우와 모르는 경우가 갈린다**는 것이고, 그 차이를 같은 조건에서 나란히 봤다. 커넥션 1개로 "만들고 → 끊고 → 다시 쏜다" 를 세 번 돌린다.

```bash
./scripts/run-vanish.sh
```

<details markdown="1">
<summary>알려주고 닫는 경우와 말없이 끊기는 경우 — <code>scripts/run-vanish.sh</code></summary>

```bash
#!/usr/bin/env bash
# 사용법: run-vanish.sh
#
# 풀에서 커넥션이 사라지는 경우를 "서버가 알려주고 닫는" 쪽과 "말없이 끊기는" 쪽으로 갈라 본다.
#   A. 응답에 Connection: close              -> 알려준다. 풀도 같이 버린다 (게이지와 소켓이 일치)
#   B. 서버가 keep-alive 를 안 씀            -> 알려준다. 매 응답에 Connection: close 가 붙는다
#   C. 중간 장비가 말없이 끊음               -> 안 알려준다. 게이지는 1 인데 소켓은 CLOSE_WAIT
# 셋 다 커넥션 1개로 "만들고 -> 끊고 -> 다시 쏜다" 를 돌린다. 부하 생성기는 안 쓴다.
# B 는 업스트림을 다시 띄워야 해서 마지막에 돌린다 (출력은 A, C, B 순).
set -e
cd "$(dirname "$0")/.."
export POOL_VALIDATE_AFTER_INACTIVITY_MS=-1 POOL_RETRY_ENABLED=false \
       POOL_MAX_TOTAL=50 POOL_MAX_PER_ROUTE=50 POOL_CONNECTION_REQUEST_TIMEOUT_MS=3000 \
       UPSTREAM_BASE_URL=http://toxiproxy:8666 \
       KEEP_ALIVE_TIMEOUT=60000 MAX_KEEP_ALIVE_REQUESTS=100
up() { (cd docker && docker-compose up -d --force-recreate "$@" >/dev/null 2>&1); }
health() { for i in $(seq 1 60); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:9080/actuator/health)" = "200" ] && break
  sleep 1
done; }
up caller upstream toxiproxy
health

sock() { docker exec docker_caller_1 sh -c "awk 'NR>1 && \$4==\"$1\" && \$3 ~ /:21DA\$/ {n++} END {print n+0}' /proc/net/tcp"; }  # 8666 = 21DA
gauge() { curl -s http://localhost:9080/actuator/prometheus | awk -v s="$1" '$0 ~ s && $0 !~ /^#/ {printf "%d", $2}'; }

probe() {   # <라벨> — 끊긴 직후 상태를 찍고, 그 커넥션을 쓸 차례의 요청 결과까지 찍는다
  STATE="available=$(gauge 'state="available"') ESTABLISHED=$(sock 01) CLOSE_WAIT=$(sock 08)"
  N=$(docker logs docker_caller_1 2>&1 | wc -l)
  CODE=$(curl -s -o /dev/null -m 20 -w '%{http_code}' http://localhost:9080/call)
  ERR=$(docker logs docker_caller_1 2>&1 | tail -n +$((N+1)) | grep -oE "NoHttpResponseException|Connection reset|SocketException" | head -1)
  printf '%-32s | 끊긴 뒤: %-44s | 다음 요청 HTTP %-3s | %s\n' "$1" "$STATE" "$CODE" "${ERR:-예외없음}"
}

# A. 서버가 이 응답만 close 로 닫는다 (EchoController 가 Connection: close 를 붙인다)
curl -s -o /dev/null 'http://localhost:9080/call?close=true'
sleep 0.3
probe "A. 응답에 Connection: close"

# C. 중간 장비가 말없이 끊는다
curl -s -o /dev/null http://localhost:9080/call                                                 # 풀에 커넥션 1개
curl -s -X POST -d '{"enabled":false}' http://localhost:8474/proxies/upstream_http >/dev/null   # 통보 없이 끊는다
curl -s -X POST -d '{"enabled":true}'  http://localhost:8474/proxies/upstream_http >/dev/null
sleep 0.3                                                                                       # 검증 주기 2초 안쪽
probe "C. 말없이 끊김 (idle 0.3s)"

# B. 서버가 keep-alive 자체를 안 쓴다 (max-keep-alive-requests=1 -> 매 응답에 Connection: close)
export MAX_KEEP_ALIVE_REQUESTS=1
up upstream
sleep 3
up caller        # 풀을 비우고 시작한다
health
echo "--- 응답 헤더 (max-keep-alive-requests=1)"
docker run --rm --network docker_default pool-lab-net sh -c \
  "curl -s -o /dev/null -D - -H 'Connection: keep-alive' http://upstream:8080/echo" | grep -iE '^(connection|keep-alive)'
curl -s -o /dev/null http://localhost:9080/call   # close 파라미터 없이 평범한 요청
sleep 0.3
probe "B. 서버가 keep-alive 를 안 씀"
```

</details>

| # | 어떻게 끊겼나 | 서버가 알렸나 | available | ESTABLISHED | CLOSE_WAIT | 다음 요청 |
| --- | --- | --- | --- | --- | --- | --- |
| A | 응답에 `Connection: close` (`close=true`) | 알림 | **0** | 0 | 0 | HTTP 200 |
| B | 서버가 keep-alive 를 안 씀 (`max-keep-alive-requests=1`) | 알림 | **0** | 0 | 0 | HTTP 200 |
| C | 중간 장비가 말없이 끊음 (idle 0.3초) | **안 알림** | **1** | 0 | **1** | **HTTP 500** `NoHttpResponseException` |

**A·B — 알려주고 닫으면 풀은 모를 수가 없다.** 닫겠다는 말이 **응답 헤더로** 오기 때문이다. 그 응답을 읽고 있는 스레드가 바로 그 자리에 있으니, `MainClientExec` 의 `reuseStrategy` 가 그 헤더를 보고 false 를 돌려주고 반납이 곧 폐기가 된다(16번). 그래서 `available` 도 0, 소켓도 0 이다 — **게이지와 커널이 일치한다.** 다음 요청은 새로 맺어서 성공한다.

B 가 "서버가 keep-alive 를 안 쓰는" 경우다. `max-keep-alive-requests` 를 0 이나 1 로 주면 응답이 이렇게 나간다.

```
$ curl -D - -H 'Connection: keep-alive' http://upstream:8080/echo
Connection: close
(Keep-Alive 헤더 없음)
```

클라이언트가 `Connection: keep-alive` 를 요청해도 서버가 거절한 것이고, 풀은 그 말을 그대로 따른다. **서버가 keep-alive 를 안 쓰면 풀은 재사용을 못 하지만 stale 도 안 생긴다.** 5·6번에서 본 "풀이 세마포어로 격하된다"가 이 상태다.

**C — 말없이 끊기면 아무도 못 본다.** 신호가 응답이 아니라 **유휴 소켓에 도착하는 FIN** 이다. blocking 클라이언트는 유휴 소켓을 읽는 스레드가 없어서 그 FIN 을 아무도 수거하지 않는다. 커널은 소켓을 `CLOSE_WAIT` 으로 바꿔두지만 `PoolEntry` 는 `available` 에 그대로 남아 있고, 다음 요청이 그 죽은 커넥션을 집는다. 쓰기는 half-close 라 성공하고 읽기에서 EOF 가 나면서 `NoHttpResponseException` 이 된다.

| | 알려주고 닫음 (A·B) | 말없이 끊김 (C) |
| --- | --- | --- |
| 신호가 오는 곳 | 응답 헤더 `Connection: close` | 유휴 소켓의 FIN |
| 누가 보나 | 그 응답을 읽는 스레드 | blocking 이면 아무도 (비동기는 I/O 리액터가 본다) |
| 풀 게이지 | 소켓 상태와 일치 | 어긋난다 (`available=1`, `CLOSE_WAIT=1`) |
| 다음 요청 | 새로 맺고 성공 | 죽은 커넥션을 집어 실패 |
| 필요한 방어 | 없음 | `validateAfterInactivity` / `evictIdleConnections` |

**그래서 풀 설정으로 막는 건 C 하나뿐이다.** A·B 는 프로토콜이 알려주니 공짜로 맞고, C 는 클라이언트가 스스로 의심해야 맞는다. 앞 표의 3 이 그 방어선을 보여준다 — idle 3초는 검증 주기 2초를 넘겨서 lease 직전에 stale 체크가 돌고, 죽은 커넥션을 버리고 새로 맺는다. **클라이언트 검증 주기 < 상대가 끊는 주기**가 지켜지면 막힌다.


#### 알려주지 않는 쪽이 중간 장비만은 아니다

C 는 toxiproxy 로 만들었지만, **중간 장비가 없어도 같은 모양이 나온다.** 서버가 "60초는 써도 된다"고 말한 뒤 그 60초 안에 사라지는 길이 여럿이다. 원인별로 하나씩 만들어봤다.

```bash
./scripts/run-dead.sh
```

<details markdown="1">
<summary>원인별로 죽은 커넥션 만들기 — <code>scripts/run-dead.sh</code></summary>

```bash
#!/usr/bin/env bash
# 사용법: run-dead.sh
#
# "서버는 끊었는데 클라이언트는 모르는" 상황을 원인별로 만든다. 중간 장비(toxiproxy)는 안 쓴다.
#   D1. 배포 중 — 업스트림을 재기동하는 동안 0.2초 간격으로 계속 때린다. 검증 2초(기본)
#   D2. 같은 부하에 검증만 매 lease 마다 (validateAfterInactivity=0)
#         두 실패를 예외로 구분한다:
#           ConnectException     = 서버가 없던 동안의 정직한 실패
#           NoHttpResponseException = 서버가 돌아온 뒤 죽은 커넥션을 집어서 난 실패 (stale)
#   D3. 설정 어긋남 — 서버가 Keep-Alive 헤더를 안 주면 클라는 기본 3분을 잡는데 서버는 1초에 끊는다
#   D4. 네트워크 단절(blackhole) — FIN 도 RST 도 없다. 검증을 매번 해도 못 걸러낸다
set -e
cd "$(dirname "$0")/.."
PORT_HEX=1F90   # upstream 8080

boot() {   # <validate_ms> <keep_alive_timeout_ms> <keep_alive_header>
  export POOL_VALIDATE_AFTER_INACTIVITY_MS="$1" KEEP_ALIVE_TIMEOUT="$2" KEEP_ALIVE_RESPONSE_HEADER="$3" \
         POOL_RETRY_ENABLED=false POOL_MAX_TOTAL=50 POOL_MAX_PER_ROUTE=50 \
         POOL_CONNECTION_REQUEST_TIMEOUT_MS=3000 POOL_RESPONSE_TIMEOUT_MS=10000 \
         UPSTREAM_BASE_URL=http://upstream:8080 MAX_KEEP_ALIVE_REQUESTS=100 \
         LOGGING_LEVEL_ORG_APACHE_HC=DEBUG
  (cd docker && docker-compose up -d --force-recreate upstream caller >/dev/null 2>&1)
  for i in $(seq 1 60); do
    [ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:9080/actuator/health)" = "200" ] && break
    sleep 1
  done
}
sock() { docker exec docker_caller_1 sh -c "awk 'NR>1 && \$4==\"$1\" && \$3 ~ /:$PORT_HEX\$/ {n++} END {print n+0}' /proc/net/tcp"; }
gauge() { curl -s http://localhost:9080/actuator/prometheus | awk -v s="$1" '$0 ~ s && $0 !~ /^#/ {printf "%d", $2}'; }
errs() { docker logs docker_caller_1 2>&1 | tail -n +$((1+$1)) | grep -oE "NoHttpResponseException|SocketTimeoutException|HttpHostConnectException|ConnectException|Connection reset" | sort | uniq -c | tr '\n' ' '; }

# ── D1/D2. 배포 중에 계속 때린다
deploy_case() {   # <라벨> <validate_ms>
  boot "$2" 60000 true
  curl -s -o /dev/null http://localhost:9080/call          # 풀에 커넥션 1개
  N=$(docker logs docker_caller_1 2>&1 | wc -l)
  ( sleep 2; cd docker && docker-compose restart upstream >/dev/null 2>&1 ) &
  OK=0; BAD=0
  for i in $(seq 1 120); do                                # 0.2초 * 120 = 약 24초
    code=$(curl -s -o /dev/null -m 5 -w '%{http_code}' http://localhost:9080/call)
    [ "$code" = "200" ] && OK=$((OK+1)) || BAD=$((BAD+1))
    sleep 0.2
  done
  wait
  printf '%-28s | 성공 %-4s 실패 %-4s | %s\n' "$1" "$OK" "$BAD" "$(errs "$N")"
}
deploy_case "D1. 배포, 검증 2초(기본)" -1
deploy_case "D2. 배포, 검증 매번(0)"    0

# ── D3/D4. 단발로 상태까지 본다
probe() {   # <라벨>
  STATE="available=$(gauge 'state="available"') ESTABLISHED=$(sock 01) CLOSE_WAIT=$(sock 08)"
  N=$(docker logs docker_caller_1 2>&1 | wc -l)
  T0=$(date +%s)
  CODE=$(curl -s -o /dev/null -m 30 -w '%{http_code}' http://localhost:9080/call)
  T=$(( $(date +%s) - T0 ))
  LIFE=$(docker logs docker_caller_1 2>&1 | grep -o "can be kept alive .*" | head -1)
  printf '%-28s | 클라가 잡은 수명: %-26s | 끊긴 뒤: %-42s | 다음 요청 HTTP %-3s (%ss) | %s\n' \
    "$1" "$LIFE" "$STATE" "$CODE" "$T" "$(errs "$N")"
}

# D3. 서버가 Keep-Alive 헤더를 안 준다 -> 클라는 기본 3분, 서버는 1초에 끊는다
# 상태를 읽는 데 1초 가까이 걸리므로 상태 보기와 요청 쏘기를 따로 돌린다.
# (상태를 읽는 동안에는 lease 가 없으니 검증도 안 돈다 — 유휴가 길어져도 상관없다)
boot -1 1000 false
curl -s -o /dev/null http://localhost:9080/call            # 커넥션 하나
sleep 1.5                                                  # 서버는 1초에 끊는다
STATE="available=$(gauge 'state="available"') ESTABLISHED=$(sock 01) CLOSE_WAIT=$(sock 08)"
LIFE=$(docker logs docker_caller_1 2>&1 | grep -o "can be kept alive .*" | head -1)

boot -1 1000 false                                         # 소켓을 깨끗이 비우고 요청만 쏜다
curl -s -o /dev/null http://localhost:9080/call
N=$(docker logs docker_caller_1 2>&1 | wc -l)
sleep 1.5                                                  # 서버는 끊었고 클라 검증 주기 2초는 아직 안 됐다
CODE=$(curl -s -o /dev/null -m 30 -w '%{http_code}' http://localhost:9080/call)
printf '%-28s | 클라가 잡은 수명: %-26s | 끊긴 뒤: %-42s | 다음 요청 HTTP %-3s | %s\n' \
  "D3. 헤더 없음, 검증 2초(기본)" "$LIFE" "$STATE" "$CODE" "$(errs "$N")"

# D4. 네트워크 단절 — FIN 도 RST 도 안 온다
boot 0 60000 true
curl -s -o /dev/null http://localhost:9080/call
docker network disconnect docker_default docker_upstream_1
sleep 0.3
probe "D4. 네트워크 단절, 검증 매번(0)"
docker network connect docker_default docker_upstream_1 >/dev/null 2>&1 || true
```

</details>

| # | 원인 | 클라가 잡은 수명 | 끊긴 뒤 | 결과 |
| --- | --- | --- | --- | --- |
| D1 | **배포** — 업스트림 재기동. 재기동 중에도 0.2초 간격으로 계속 호출 | `for 60 SECONDS` | `available=1`, `CLOSE_WAIT=1` | 120건 중 성공 88 / 실패 32. `ConnectException` 30 + **`NoHttpResponseException` 1** |
| D2 | 같은 배포인데 검증을 **매 lease 마다**(`validateAfterInactivity=0`) | `for 60 SECONDS` | 〃 | 성공 88 / 실패 32. `ConnectException` 31 + **`NoHttpResponseException` 0** |
| D3 | **서버가 `Keep-Alive` 헤더를 안 줌** — 서버는 1초에 끊는데 클라는 기본값을 잡는다 | **`for 3 MINUTES`** | `available=1`, `ESTABLISHED=0`, `CLOSE_WAIT=1` | **HTTP 500** `NoHttpResponseException` |
| D4 | **경로가 조용히 사라짐**(네트워크 단절). 검증은 매번(`0`) | `for 60 SECONDS` | `available=1`, **`ESTABLISHED=1`**, `CLOSE_WAIT=0` | **HTTP 500** `SocketTimeoutException`, **10초** 매달렸다 |

**D1 — 가장 흔한 원인은 배포다.** 서버가 알려준 60초가 끝나기 전에 서버가 먼저 사라진다. 톰캣은 정상 종료라 FIN 을 보내므로 C 와 같은 모양(`available=1`, `CLOSE_WAIT=1`)이 된다. 실패를 예외로 갈라보면 두 종류가 섞여 있다 — **서버가 실제로 없던 동안의 `ConnectException` 30건**과, **서버가 돌아온 뒤 죽은 커넥션을 집어서 난 `NoHttpResponseException` 1건**이다. 앞의 30건은 풀 설정으로 어쩔 수 있는 게 아니고, 뒤의 1건이 풀이 만든 몫이다.

**그럼 2초를 기다리지 말고 매번 검사하면 되지 않나.** 된다. `validateAfterInactivity` 는 **음수면 아예 안 하고, 0 이면 매 lease 마다** 한다.

```java
// org.apache.hc.client5.http.impl.io.PoolingHttpClientConnectionManager.java — lease 직후
final TimeValue timeValue = resolveValidateAfterInactivity(connectionConfig);
if (TimeValue.isNonNegative(timeValue)) {                        // 음수면 이 블록을 건너뛴다
    if (timeValue.getDuration() == 0                             // 0 이면 매번
            || Deadline.calculate(poolEntry.getUpdated(), timeValue).isExpired()) {
        final ManagedHttpClientConnection conn = poolEntry.getConnection();
        boolean stale;
        try {
            stale = conn.isStale();                              // 1ms 타임아웃으로 한 번 읽어본다
        } catch (final IOException ignore) {
            stale = true;
        }
        if (stale) {
            poolEntry.discardConnection(CloseMode.IMMEDIATE);
        }
    }
}
```

D2 에서 그 1건이 0 이 됐다. 다만 **보장은 아니다.** 검사와 쓰기가 원자적이지 않아서, `isStale()` 로 1ms 들여다본 직후에 FIN 이 와도 그 요청은 이미 나간다. 같은 실험을 세 번 돌렸을 때 `validateAfterInactivity=0` 으로도 1건이 난 회차가 있었다. 실패 건수가 한 자리라 비율로 읽을 수 없고, **"창이 줄어들지만 0 이 보장되지는 않는다"** 까지만 말할 수 있다. 공짜도 아니다 — 매 요청마다 1ms 타임아웃 읽기 syscall 이 하나 더 붙고, D4 처럼 커널도 모르는 경우에는 아무 도움이 안 된다. 이 틈을 메우는 자리가 재시도(10번)인데 그쪽은 멱등성 문제를 같이 들고 온다.

**D3 — 서버가 알려주지 않으면 클라이언트 기본값이 이긴다.** 톰캣의 `useKeepAliveResponseHeader` 를 끄면 `Keep-Alive` 헤더가 안 나간다. 그러면 `DefaultConnectionKeepAliveStrategy` 가 두 번째 분기로 떨어진다 — `RequestConfig.connectionKeepAlive`, **기본 3분**이다. 서버는 1초에 끊는데 풀은 3분을 들고 있으니, **9번에서 틀렸던 그 예측이 여기서는 그대로 맞는다.** 로그에 `can be kept alive for 3 MINUTES` 가 찍힌다. 9번이 재현되지 않은 건 "사각지대가 없어서"가 아니라 **톰캣이 알려주는 서버였기 때문**이었다.

```java
// upstream 쪽. 이 한 줄로 "자기 타임아웃을 안 알려주는 서버" 가 된다
if (handler instanceof AbstractHttp11Protocol<?> protocol) {
    protocol.setUseKeepAliveResponseHeader(enabled);
}
```

13번에서 클라이언트가 서버 말을 **무시하게** 만든 것과 원인은 같다. 한쪽은 서버가 말을 안 하고 한쪽은 클라이언트가 안 듣는데, 결과는 똑같이 **클라가 잡은 수명 > 서버가 닫는 시점** 이다. 그 부등호가 stale 의 조건이다.

**D4 — 커널조차 모르면 타임아웃까지 매달린다.** 경로만 사라지면 FIN 도 RST 도 안 온다. 소켓은 `ESTABLISHED` 로 남아 있고 `isStale()` 의 1ms 읽기도 "읽을 게 없다"로 통과한다. 그래서 검증을 매번 해도 못 걸러내고, 요청은 `responseTimeout`(여기선 10초)까지 매달렸다. 위 "말없이" 표의 넷째 줄이 이 경우다. **여기서 실패를 빨리 끝내는 건 풀 설정이 아니라 타임아웃 값이다.**

정리하면 stale 의 원인은 넷이고, 풀 설정이 닿는 범위가 서로 다르다.

| 원인 | 신호 | 검증(`validateAfterInactivity`)이 막나 |
| --- | --- | --- |
| 중간 장비 idle timeout (9·11번 C) | FIN | 주기가 상대보다 짧으면 막는다 |
| 배포·재기동 (D1) | FIN | 대체로 막지만 틈이 남는다 |
| 수명 설정 어긋남 (D3, 13번) | FIN | 막는다. 애초에 수명을 맞추는 게 먼저다 |
| 경로 소실 (D4) | **없음** | **못 막는다.** 타임아웃과 재시도의 영역이다 |

**12번** — 요청 수 상한은 성격이 다르다. 업스트림을 `maxKeepAliveRequests=5` 로 띄우고, **한 커넥션 위에서** 6번 연속으로 보내며 응답 헤더만 본다.

```bash
docker run --rm --network docker_default pool-lab-net sh -c \
  "curl -s -o /dev/null -D - -H 'Connection: keep-alive' \
        http://upstream:8080/echo?[1-6]"     # [1-6] 이 한 커넥션에서 6번 반복된다
```

| 요청 | 소스 포트 | 응답 헤더 |
| --- | --- | --- |
| 1~4번째 | 55610 | `Keep-Alive: timeout=60`, `Connection: keep-alive` |
| **5번째** | 55610 | **`Connection: close`** (Keep-Alive 헤더 사라짐) |
| 6번째 | **55612** | 새 커넥션에서 다시 `keep-alive` |

**알려주고 닫으므로 stale 을 만들지 않는다.** 시간 상한(`keepAliveTimeout`)은 예고 없이 FIN 을 보내지만, 요청 수 상한은 마지막 응답에 `Connection: close` 를 붙인다. 이 값을 아무리 낮춰도 stale 의 원인은 되지 않는다.

### 13번 — 커넥션 수명은 서버가 정한다

9번에서 톰캣이 알려준 `timeout=1` 을 클라이언트가 지키는 걸 봤는데, 그 판단을 하는 게 `ConnectionKeepAliveStrategy` 다. 이번엔 톰캣이 `timeout=5` 를 알려주게 두고(`keepAliveTimeout=5000`), 유휴 시간을 그 앞뒤로 두면서 잰다.

재사용 여부는 업스트림이 본 **caller 의 소스 포트**로 판별한다. 두 요청의 포트가 같으면 같은 TCP 커넥션이다.

```java
// caller — 한 번 호출하고 idleMs 쉬었다가 다시 호출한다
String first = peer();
Thread.sleep(idleMs);
String second = peer();
// peer() 는 업스트림이 돌려준 X-Peer(= servletRequest.getRemotePort()) 를 읽는다
```

```bash
./scripts/run-keepalive.sh 60000 -1 8   # <keepAliveStrategy 고정값 ms> <validateAfterInactivity ms> <idle 초>
#   음수를 주면 그 설정을 건드리지 않는다 = 기본 전략 / 기본 검증 주기
```

<details markdown="1">
<summary>커넥션 수명 — <code>scripts/run-keepalive.sh</code></summary>

```bash
#!/usr/bin/env bash
# 사용법: run-keepalive.sh <KEEP_ALIVE_MS> <VALIDATE_MS> <IDLE_SEC>
#
# 커넥션을 풀에 얼마나 둘지는 ConnectionKeepAliveStrategy 가 응답마다 정한다.
# 기본 전략(KEEP_ALIVE_MS < 0)은 서버의 Keep-Alive: timeout=N 을 그대로 따르고,
# 값을 주면 서버가 뭐라 하든 그 값으로 고정한다.
# 톰캣은 5초(=timeout=5)로 알려주게 두고, 유휴 시간을 그 앞뒤로 둬서 갈리는 지점을 본다.
set -e
cd "$(dirname "$0")/.."
KEEP_ALIVE="$1"; VALIDATE="$2"; IDLE="$3"
export POOL_KEEP_ALIVE_MS="$KEEP_ALIVE" POOL_VALIDATE_AFTER_INACTIVITY_MS="$VALIDATE" \
       POOL_MAX_TOTAL=50 POOL_MAX_PER_ROUTE=50 POOL_CONNECTION_REQUEST_TIMEOUT_MS=3000 \
       POOL_RETRY_ENABLED=false POOL_EVICT_IDLE_MS=-1 POOL_TIME_TO_LIVE_MS=-1 \
       UPSTREAM_BASE_URL=http://upstream:8080 LOGGING_LEVEL_ORG_APACHE_HC=DEBUG \
       KEEP_ALIVE_TIMEOUT=5000 MAX_KEEP_ALIVE_REQUESTS=100 NETEM_DELAY_MS=0
(cd docker && docker-compose up -d --force-recreate caller upstream >/dev/null 2>&1)
for i in $(seq 1 60); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:9080/actuator/health)" = "200" ] && break
  sleep 1
done

# 톰캣이 실제로 뭐라고 알려주는지 먼저 확인한다 (클라가 Connection: keep-alive 를 보내야 붙는다)
ADV=$(docker exec docker_caller_1 sh -c \
  "curl -s -D - -o /dev/null -H 'Connection: keep-alive' http://upstream:8080/echo" \
  | tr -d '\r' | grep -i '^Keep-Alive:' || echo "(알려주지 않음)")

N=$(docker logs docker_caller_1 2>&1 | wc -l)
BODY=$(curl -s -m 40 "http://localhost:9080/keepalive?idleMs=$((IDLE*1000))")
DUR=$(docker logs docker_caller_1 2>&1 | tail -n +$((N+1)) | grep -oE "can be kept alive (for [0-9]+ [A-Z]+|indefinitely)" | head -1)

K=$([ "$KEEP_ALIVE" -lt 0 ] && echo "기본(서버따름)" || echo "$((KEEP_ALIVE/1000))s고정")
V=$([ "$VALIDATE" -lt 0 ] && echo "2s(기본)" || echo "$((VALIDATE/1000))s")
printf '전략=%-14s 검증=%-8s idle=%-4s | %-42s | %s\n' "$K" "$V" "${IDLE}s" "${DUR:-로그없음}" "$BODY"
echo "  ($ADV)"
```

</details>

열 이름이 가리키는 건 각각 이렇다. 톰캣은 다섯 경우 모두 `timeout=5` 로 알려준다.

- **클라 전략** — `setKeepAliveStrategy`. `기본` 은 서버가 보낸 `timeout=5` 를 따르고, `60초 고정` 은 서버 헤더를 무시하고 응답마다 60초로 답하는 전략을 심은 것이다.
- **검증** — `validateAfterInactivity`. `끔` 은 빌려줄 때 확인 없이 그냥 주고, `2초(기본)` 은 2초 넘게 쉰 커넥션만 찔러보고 준다.
- **클라가 잡은 수명** — caller 의 HttpClient 로그에서 뽑은, 클라이언트가 그 커넥션에 실제로 매긴 유효기간이다. `for 5 SECONDS` 면 서버 말을 들었다는 증거고 `60000 MILLISECONDS` 면 무시했다는 증거다.

| # | 클라 전략 | 검증 | idle | 클라가 잡은 수명 | 결과 |
| --- | --- | --- | --- | --- | --- |
| 1 | 기본 | 끔 | 2초 | `for 5 SECONDS` | 재사용 (48938 → 48938) |
| 2 | 기본 | 끔 | 8초 | `for 5 SECONDS` | 새 커넥션 (49032 → 49034), 에러 없음 |
| 3 | 60초 고정 | 끔 | 3초 | `60000 MILLISECONDS` | 재사용 (49324 → 49324) |
| 4 | **60초 고정** | **끔** | **8초** | `60000 MILLISECONDS` | **`NoHttpResponseException`** |
| 5 | 60초 고정 | 2초(기본) | 8초 | `60000 MILLISECONDS` | 새 커넥션, 에러 없음 |

1·2 가 기본 동작이다. 클라이언트는 서버가 말한 5초를 그대로 풀 엔트리의 수명으로 잡고, 8초 뒤에 빌리려 하면 만료된 엔트리를 버리고 새로 맺는다. **검증을 꺼놨는데도 에러가 안 난다** — 여기서 stale 을 막은 건 `validateAfterInactivity` 가 아니라 서버가 보낸 헤더다.

4 가 9번에서 못 만들었던 그 사각지대다. 전략을 고정하면 서버 말이 무시된다. 톰캣은 5초에 끊었는데 풀은 60초까지 들고 있고, 검증도 없으니 죽은 커넥션에 요청이 실린다. **toxiproxy 없이, 톰캣만으로 재현된다.** 9번에서 중간 장비를 끌어와야 했던 건 톰캣이 정직해서였지 톰캣이라 안 되는 게 아니었다.

3 은 같은 60초 고정인데 멀쩡하다. 서버가 아직 안 끊은 3초 안쪽이기 때문이다. 문제는 전략을 고정하는 것 자체가 아니라 **서버가 끊는 시점보다 길게 잡는 것**이다. 5 는 그 상태에서 검증이 남은 방어선으로 작동하는 경우다.

정리하면 커넥션 수명을 정하는 순서가 이렇다.

```
서버의 Keep-Alive: timeout=N   →  있으면 그 값
       없으면                  →  RequestConfig.connectionKeepAlive (기본 3분)
       전략을 고정했으면        →  서버와 무관하게 그 값
```

기본값을 바꿀 이유는 거의 없다. 서버가 말해주면 그게 제일 정확하고, 안 말해주는 상대일 때만 3분이라는 값이 실제로 쓰인다.

**구현체는 하나뿐이다.** jar 에서 `keepalive` 로 걸리는 클래스가 인터페이스 하나와 구현 하나다(5.4.2·5.5.2 동일). 재시도 전략(10번)과 같은 모양으로, 고를 선택지가 있는 게 아니라 다르게 하려면 직접 구현해서 넣는 것이다. 위 표의 "60초 고정"도 람다 한 줄이다.

```java
.setKeepAliveStrategy((response, context) -> TimeValue.ofMilliseconds(60_000))
```

**이 람다가 `DefaultConnectionKeepAliveStrategy` 를 대신한다.** 인터페이스에 메서드가 `getKeepAliveDuration` 하나뿐이어서 람다가 곧 그 메서드의 구현이고, 빌더는 설정된 전략이 없을 때만 기본 전략을 끼운다.

```java
// org.apache.hc.client5.http.impl.classic.HttpClientBuilder.java — build()
ConnectionKeepAliveStrategy keepAliveStrategyCopy = this.keepAliveStrategy;
if (keepAliveStrategyCopy == null) {
    keepAliveStrategyCopy = DefaultConnectionKeepAliveStrategy.INSTANCE;   // 안 넣었을 때만
}
```

그래서 람다를 넣으면 기본 전략은 **아예 호출되지 않는다.** `Keep-Alive` 헤더를 읽는 코드가 그 클래스 안에만 있으니, 람다가 `response` 를 안 보는 순간 서버가 보낸 값은 아무도 읽지 않는 헤더가 된다. 전략을 "덮어쓴다"기보다 헤더 파싱을 하는 구현을 빼버리는 것이다.

**이름이 비슷한 이웃이 하나 있다.** 재사용을 할지 말지는 `ConnectionReuseStrategy`(httpcore5)가 정하고, 재사용한다고 치고 얼마나 둘지는 `ConnectionKeepAliveStrategy`(httpclient5)가 정한다. 두 전략이 불리는 자리가 한 군데라 거기서 보는 게 빠르다.

```java
// org.apache.hc.client5.http.impl.classic.MainClientExec.java
// The connection is in or can be brought to a re-usable state.
if (reuseStrategy.keepAlive(request, response, context)) {        // 1. 재사용할 커넥션인가
    // Set the idle duration of this connection
    final TimeValue duration = keepAliveStrategy.getKeepAliveDuration(response, context);   // 2. 얼마나 둘까
    LOG.debug("{} connection can be kept alive {}", exchangeId, s);   // 위 표의 "클라가 잡은 수명"
    execRuntime.markConnectionReusable(userToken, duration);
} else {
    execRuntime.markConnectionNonReusable();                      // 12번의 Connection: close 가 여기로 온다
}
```

1 이 false 면 2 는 아예 불리지 않는다. 12번에서 `close=true` 를 줬을 때 재사용이 끊긴 건 keep-alive 전략이 아니라 이 판단이고, 그 커넥션은 반납 대신 `discardEndpoint()` 로 간다(4번의 RST). 이쪽은 구현이 둘인데 상속 관계다. 클래식 빌더의 기본값은 `DefaultClientConnectionReuseStrategy`(httpclient5)이고, `CONNECT` 가 200 으로 끝난 경우만 따로 처리하고 나머지는 부모인 `DefaultConnectionReuseStrategy`(httpcore5)에 넘긴다. 재사용을 포기하는 조건은 그 부모 클래스 주석에 적혀 있다 — 요청이나 응답에 `Connection: close` 가 있을 때, 본문 길이가 모순될 때, HTTP/1.0 인데 `keep-alive` 가 없을 때.

### 14~16번 — 언제 만들고, 언제 돌려받고, 언제 버리나

앞의 실험들은 풀이 **이미 돌고 있는 상태**를 봤다. 마지막으로 그 앞 단계 — 풀이 커넥션을 어떻게 확보하고 어떻게 돌려받는지 — 를 확인한다. 숫자가 작아서 부하 생성기로는 안 보이고, 동시성을 한 단계씩 내가 정해야 하므로 curl 을 직접 띄운다.

```bash
./scripts/run-lifecycle.sh
```

<details markdown="1">
<summary>단계별 풀·소켓 상태 — <code>scripts/run-lifecycle.sh</code></summary>

```bash
#!/usr/bin/env bash
# 사용법: run-lifecycle.sh
#
# 풀이 커넥션을 "언제 만들고 / 언제 반납받고 / 반납 후 어떻게 하는지" 를 단계별로 찍는다.
# 동시성을 내가 정해야 하므로 부하 생성기 대신 curl 을 직접 띄운다.
#   available  = 풀에 놀고 있는 PoolEntry, leased = 빌려준 PoolEntry
#   ESTABLISHED= caller -> upstream 살아 있는 소켓 (/proc/net/tcp)
#   새 소켓    = /proc/net/snmp ActiveOpens 증분. 괄호는 그 단계에서 새로 만든 수
set -e
cd "$(dirname "$0")/.."
export POOL_MAX_TOTAL=50 POOL_MAX_PER_ROUTE=50 POOL_CONNECTION_REQUEST_TIMEOUT_MS=3000 \
       POOL_VALIDATE_AFTER_INACTIVITY_MS=-1 POOL_EVICT_IDLE_MS=-1 POOL_TIME_TO_LIVE_MS=-1 \
       POOL_KEEP_ALIVE_MS=-1 POOL_RETRY_ENABLED=false \
       UPSTREAM_BASE_URL=http://upstream:8080 KEEP_ALIVE_TIMEOUT=60000 \
       MAX_KEEP_ALIVE_REQUESTS=1000 NETEM_DELAY_MS=0
(cd docker && docker-compose up -d --force-recreate caller upstream >/dev/null 2>&1)
for i in $(seq 1 60); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:9080/actuator/health)" = "200" ] && break
  sleep 1
done

gauge() { curl -s http://localhost:9080/actuator/prometheus | awk -v s="$1" '$0 ~ s && $0 !~ /^#/ {printf "%d", $2}'; }
sock()  { docker exec docker_caller_1 sh -c "awk 'NR>1 && \$4==\"$1\" && \$3 ~ /:1F90\$/ {n++} END {print n+0}' /proc/net/tcp"; }
opens() { docker exec docker_caller_1 sh -c "awk '/^Tcp:/{if(h){split(h,a,\" \");split(\$0,b,\" \");for(i=1;i<=length(a);i++) if(a[i]==\"ActiveOpens\") print b[i]} else h=\$0}' /proc/net/snmp"; }

A0=$(opens); PREV=0
show() {
  local now=$(( $(opens) - A0 ))
  printf '%-30s | available=%-3s leased=%-3s | ESTABLISHED=%-3s CLOSE_WAIT=%-3s | 새 소켓 %-3s (+%s)\n' \
    "$1" "$(gauge 'state="available"')" "$(gauge 'state="leased"')" "$(sock 01)" "$(sock 08)" "$now" "$((now-PREV))"
  PREV=$now
}
# call <delayMs> <close> <mode> <sizeBytes>
call() { curl -s -o /dev/null -m 30 \
  "http://localhost:9080/call?delayMs=${1:-0}&close=${2:-false}&mode=${3:-safe}&sizeBytes=${4:-0}"; }
loop() { local n="$1"; shift; for i in $(seq 1 "$n"); do call "$@"; done; }

echo "# 1) 풀을 미리 채워두는가"
show "기동 직후 — 요청 0회"
call;        show "요청 1회"
loop 19;     show "순차 20회 (동시성 1)"

echo
echo "# 2) 동시성이 오르면 / 내려가면"
for i in $(seq 1 10); do call 1000 & done; sleep 0.6; show "동시 10 — 처리 중"
wait;                                                 show "동시 10 — 끝난 뒤"
for i in $(seq 1 3);  do call 1000 & done; sleep 0.6; show "동시 3 — 처리 중"
wait;                                                 show "동시 3 — 끝난 뒤"

echo
echo "# 3) 반납 시점"
call 3000 & sleep 1; show "응답 대기 중 (delayMs=3000)"
wait;                show "응답 다 읽은 뒤"

echo
echo "# 4) 서버가 Connection: close 를 붙이면"
call 0 true;      show "close 응답 1회"
loop 19 0 true;   show "close 순차 20회"
call;             show "다시 keep-alive 1회"

echo
echo "# 5) 응답을 닫기만 하고 본문을 안 읽으면 (100KB 본문)"
loop 20 0 false safe      102400; show "safe 순차 20회"
loop 20 0 false closeonly  102400; show "closeonly 순차 20회"
loop 20 0 false safe      102400; show "다시 safe 순차 20회"

echo
echo "# 6) 서버가 알려준 keep-alive 가 지나면 (upstream 재기동: timeout=5s)"
export KEEP_ALIVE_TIMEOUT=5000
(cd docker && docker-compose up -d --force-recreate caller upstream >/dev/null 2>&1)
for i in $(seq 1 60); do
  [ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:9080/actuator/health)" = "200" ] && break
  sleep 1
done
A0=$(opens); PREV=0
for i in $(seq 1 10); do call 1000 & done; wait;  show "동시 10 — 끝난 뒤"
sleep 8;                                          show "8초 유휴 (서버 timeout=5s)"
call;                                             show "그 뒤 요청 1회"
```

</details>

단계마다 **풀 게이지**(`available`·`leased`)와 **커널의 소켓 상태**를 같이 읽고, `/proc/net/snmp` 의 `ActiveOpens` 증분으로 **그 단계에서 새로 맺은 소켓 수**를 센다. 풀은 `maxTotal=maxPerRoute=50`, RTT 0, 업스트림은 `Keep-Alive: timeout=60`, eviction·TTL 은 끈 상태다.

#### 14번 — 풀은 미리 채워지지 않는다

| 단계 | available | leased | ESTABLISHED | 새 소켓 |
| --- | --- | --- | --- | --- |
| 기동 직후 — 요청 0회 | **0** | 0 | **0** | - |
| 요청 1회 | 1 | 0 | 1 | +1 |
| 순차 20회 (동시성 1) | 1 | 0 | 1 | **+0** |
| 동시 10 — 처리 중 | 0 | 10 | 10 | +9 |
| 동시 10 — 끝난 뒤 | **10** | 0 | 10 | +0 |
| 동시 3 — 처리 중 | 7 | 3 | **10** | +0 |
| 동시 3 — 끝난 뒤 | **10** | 0 | 10 | +0 |

**`maxTotal=50` 을 줬는데 기동 직후 커넥션은 0개다.** 풀 크기는 예약이 아니라 상한이다. 첫 요청이 와야 하나 만든다.

**풀 크기를 정하는 건 설정값이 아니라 동시 요청 수다.** 동시성 1 로 20회를 쏘면 소켓 하나로 다 처리하고(새 소켓 +0), 동시 10 이 되면 10개까지 늘어난다. 3번에서 "필요 커넥션 = TPS × 응답시간" 으로 풀 크기를 예측한 것과 같은 얘기다.

**한 번 커진 풀은 스스로 줄지 않는다.** 동시성이 3 으로 내려가도 소켓은 10개 그대로고, 그중 3개만 빌려주고 7개는 `available` 에 남는다. 줄어드는 경로는 `evictIdleConnections` 와 만료뿐이다(아래).

소스에서 보면 엔트리를 만드는 지점은 하나뿐이다. **빌려줄 free 엔트리가 없을 때만** 부른다.

```java
// org.apache.hc.core5.pool.StrictConnPool.java — PerRoutePool
public PoolEntry<T, C> createEntry(final TimeValue timeToLive) {
    final PoolEntry<T, C> entry = new PoolEntry<>(this.route, timeToLive, disposalCallback);
    this.leased.add(entry);     // 태어날 때부터 leased 다
    return entry;
}
```

두 가지가 여기서 따라온다. 엔트리는 **`leased` 로 태어난다** — `available` 로 들어가는 유일한 경로는 반납이다. 그리고 `new PoolEntry` 는 **소켓이 없는 빈 껍데기**다. TCP 연결은 exec chain 이 `connectionManager.connect(endpoint, ...)` 를 부를 때 맺어진다. 풀 엔트리 생성과 소켓 수립은 다른 단계다.

#### 15번 — 반납은 응답을 닫는 순간 일어난다

| 단계 | available | leased |
| --- | --- | --- |
| 응답 대기 중 (`delayMs=3000`) | 9 | **1** |
| 응답 다 읽은 뒤 | 10 | 0 |

빌리는 건 요청을 보내기 전이고, 돌려주는 건 응답을 다 처리한 뒤다. 업스트림이 3초를 끌고 있는 동안 그 커넥션은 `leased` 에 잡혀 있다.

그럼 "다 처리한 뒤"가 정확히 언제인가. `MainClientExec` 에서 두 갈래로 갈린다.

```java
// org.apache.hc.client5.http.impl.classic.MainClientExec.java
// 본문이 스트리밍이면 반납 책임을 응답 객체에 넘긴다
final HttpEntity entity = response.getEntity();
if (entity == null || !entity.isStreaming()) {
    execRuntime.releaseEndpoint();                            // 여기서 바로 반납
    return new CloseableHttpResponse(response);
}
return new CloseableHttpResponse(response, execRuntime);       // 반납은 나중에
```

본문이 있으면 반납 시점은 호출자 코드에 달린다. 트리거는 셋이다.

| # | 무엇을 하면 | 어떤 경로로 반납되나 |
| --- | --- | --- |
| 1 | 본문을 EOF 까지 읽는다 | `EofSensorInputStream` → `ResponseEntityProxy.eofDetected` → `releaseEndpoint()` |
| 2 | 본문 스트림을 닫는다 | 〃 `streamClosed` → 〃 |
| 3 | 응답 객체를 닫는다 | `ResponseEntityProxy.close` → 남은 본문 드레인 → `releaseEndpoint()` |

**3 이 예상과 달랐다.** 본문에 손을 안 대고 `try-with-resources` 로만 닫으면 재사용을 잃을 거라고 봤는데, 100KB 본문으로 20회씩 돌려보면 새 소켓이 하나도 안 늘어난다.

| 순차 20회 (100KB 본문) | available | ESTABLISHED | 새 소켓 |
| --- | --- | --- | --- |
| `safe` — `EntityUtils.consume` + close | 1 | 1 | +0 |
| `closeonly` — **본문 손 안 대고 close 만** | 1 | 1 | **+0** |
| 다시 `safe` | 1 | 1 | +0 |

이유가 소스에 주석으로 적혀 있다.

```java
// org.apache.hc.client5.http.impl.classic.ResponseEntityProxy.java — close()
public void close() throws IOException {
    // HttpEntity.close will close the underlying resource. Closing a reusable request stream results in
    // draining remaining data, allowing for connection reuse.
    super.close();        // ContentLengthInputStream.close() 가 남은 본문을 끝까지 읽어 버린다
    releaseConnection();
}
```

닫기만 해도 되는 대신 **남은 본문을 네트워크로 다 받아내는 값은 치른다.** 큰 응답을 중간에 버리는 코드라면 그게 공짜가 아니다.

거꾸로, 반납이 안 되는 코드는 **셋 다 안 타는** 코드다. 0번이 그 경우다 — 에러 경로에서 그냥 `return` 으로 빠져나가 close 도 consume 도 호출되지 않는다.

#### 16번 — 재사용 못 하는 커넥션은 반납이 곧 폐기다

앞 단계에서 풀에 10개가 쌓여 있는 상태에서, 업스트림이 `Connection: close` 를 붙이게 한다.

| # | 단계 | available | leased | ESTABLISHED | 새 소켓 |
| --- | --- | --- | --- | --- | --- |
| 1 | close 응답 1회 | **9** | 0 | 9 | +0 |
| 2 | close 순차 20회 | **0** | 0 | **0** | +10 |
| 3 | 다시 keep-alive 1회 | 1 | 0 | 1 | +1 |

1 이 이 실험의 답이다. 풀에 있던 10개 중 하나를 꺼내 썼는데 **되돌아온 게 없다.** `leased` 가 0 이니 반납은 됐고, 그런데 `available` 은 9 로 줄었다. 반납받자마자 버린 것이다. 2 에서 20회를 돌리면 풀에 있던 10개를 다 소진하고 나머지 10회는 새로 맺는다(+10) — **요청 1회당 소켓 1개**다. 3 처럼 keep-alive 응답 하나가 오면 다시 1개가 쌓인다.

경로는 두 군데로 나뉜다.

```java
// org.apache.hc.client5.http.impl.classic.InternalExecRuntime.java — releaseEndpoint(), 재사용 불가면 discard 로 빠진다
if (reusable) {
    manager.release(endpoint, state, validDuration);
} else {
    discardEndpoint(endpoint);   // endpoint.close(IMMEDIATE) 하고 나서 manager.release(endpoint, null, ZERO)
}

// org.apache.hc.core5.pool.StrictConnPool.java — release(entry, reusable)
final boolean keepAlive = entry.hasConnection() && reusable;
pool.free(entry, keepAlive);
if (keepAlive) {
    this.available.addFirst(entry);                 // 풀로 복귀
} else {
    entry.discardConnection(CloseMode.GRACEFUL);    // available 에 안 넣는다 = 사라진다
}
```

소켓을 먼저 죽이고(`CloseMode.IMMEDIATE` — 1번에서 TIME_WAIT 이 하나도 안 쌓이는 이유가 이것이다) 그 다음에 엔트리를 반납하므로, 매니저가 볼 때는 이미 `conn.isOpen()` 이 false 다. `reusable=false` 로 판정돼 `available` 에 들어가지 못한다. "반납된 뒤에 풀에서 사라진다"기보다 **반납과 폐기가 같은 동작**이다.

#### 만료된 엔트리는 다음 lease 때 치운다

16번은 서버가 `Connection: close` 로 **알려준** 경우였다. 아무 말 없이 keep-alive 시간만 지난 경우는 다르다. 업스트림을 `timeout=5` 로 띄워 커넥션 10개를 만들고 8초 쉬었다.

| # | 단계 | available | leased | ESTABLISHED | CLOSE_WAIT | 새 소켓 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 동시 10 — 끝난 뒤 | 10 | 0 | 10 | 0 | +10 |
| 2 | 8초 유휴 (서버 `timeout=5`) | **10** | 0 | **0** | **10** | +0 |
| 3 | 그 뒤 요청 1회 | **1** | 0 | 1 | 0 | +1 |

2 에서 풀은 여전히 10개를 들고 있다고 말하는데 **그 10개가 전부 이미 끊긴 커넥션이다.** 서버가 FIN 을 보내서 소켓은 전부 `CLOSE_WAIT` 이다. 풀 게이지가 커널이 본 소켓 상태와 어긋나는 경우고, 0번의 `leased=50` 과 11번의 `available=1` 이 같은 어긋남이었다.

치우는 시점은 **다음 lease** 다. 요청 한 번에 `available` 이 10 → 1 로 떨어졌다. 만료된 엔트리를 하나씩 버리며 쓸 만한 걸 찾고, 없으니 새로 맺고, 그게 반납되어 1개가 남았다.

```java
// org.apache.hc.core5.pool.StrictConnPool.java — processPendingRequest(), 빌려줄 엔트리를 찾는 루프
for (;;) {
    entry = pool.getFree(state);
    if (entry == null) {
        break;
    }
    if (entry.getExpiryDeadline().isExpired()) {
        entry.discardConnection(CloseMode.GRACEFUL);   // 만료된 건 여기서 버린다
        this.available.remove(entry);
        pool.free(entry, false);
    } else {
        break;
    }
}
```

그래서 `evictIdleConnections` 를 안 켜면 풀은 **유휴 커넥션을 스스로 줄이지 않는다.** 피크에 50개까지 커진 풀은 트래픽이 없는 새벽에도 50개로 남아 있고, 그 엔트리들이 이미 죽었는지는 다음 요청이 와야 알게 된다. 들고 있는 fd 자체가 큰 비용은 아니지만, **풀 게이지만 보고 "지금 쓸 수 있는 커넥션이 N개"라고 읽으면 안 된다.**

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

1. **응답은 어느 경로로 나가든 닫는다** (0·15번) — 반납 트리거는 본문 소비·스트림 닫기·응답 닫기 셋 중 하나고, 정상 경로에만 `close` 를 두면 에러 경로가 그 셋 다 안 탄다. `try-with-resources` 로 감싸면 세 번째가 보장된다.
2. **`maxPerRoute` 를 명시한다** (2번) — 기본값은 perRoute 5 / total 25 고, 업스트림이 하나면 `maxTotal` 은 도달할 일이 없는 숫자다. 8배 올려도 TPS 가 그대로였다.
3. **크기는 동시성 기준으로 잡는다** (3·14번) — 필요 커넥션 = TPS × 응답시간. 풀 크기는 예약이 아니라 상한이라 넉넉히 줘도 실제로 드는 건 동시 요청 수만큼이고, 모자라면 곧바로 큐가 된다. **크게 준 쪽의 손해가 작다.**
4. **상한에는 반드시 포기를 같이 준다** (7번) — `connectionRequestTimeout` 이 없으면 소켓 점유가 스레드 점유로 바뀔 뿐이라 업스트림을 안 쓰는 API 까지 죽는다. 0(`Timeout.DISABLED`)은 무한이 아니라 즉시 실패이므로, "무한"은 충분히 큰 값으로 표현한다.
5. **커넥션 수명은 서버 말을 따르게 두고, 검증 주기를 상대가 끊는 주기보다 짧게** (9·12·13번) — 톰캣은 `Keep-Alive: timeout=N` 으로 알려주고 HttpClient5 는 그 값을 지킨다. `setKeepAliveStrategy` 로 그걸 덮어쓰면 서버가 끊은 커넥션을 계속 들고 있게 된다(13번). 헤더를 안 주는 상대라면 풀은 **3분**을 들고 있으므로(`RequestConfig.connectionKeepAlive` 기본값), 그때는 `validateAfterInactivity`·`evictIdleConnections` 가 유일한 방어선이다.
6. **지표는 풀이 센 값과 커널 소켓 상태를 같이 본다** (0·11·16번) — `leased`·`available` 은 `PoolEntry` 개수일 뿐이라 이미 끊긴 것도 센다. 만료된 엔트리도 다음 lease 때까지 `available` 에 그대로 남으므로, 유휴가 길었다면 더 못 믿는다. `/proc/net/tcp` 의 `CLOSE_WAIT` 과 나란히 놓아야 갈린다.

## 재보고 나서 고친 것
---

> 실험 설계에서 틀렸던 것들.

**toxiproxy 로는 핸드셰이크 RTT 를 못 만든다.** TCP 프록시라 클라이언트는 toxiproxy 와 핸드셰이크를 마치고, toxiproxy 가 그 뒤에 업스트림으로 연결한다. latency toxic 은 오가는 데이터만 늦춘다. netem 5ms 를 걸고 재보면 직접 경로는 `connect` 6.0ms, toxiproxy 경유는 0.9ms 다. 그래서 RTT 는 `tc netem` 으로 걸고 toxiproxy 는 기본 경로에서 뺐다. 대신 9번의 "말없이 끊는 중간 장비" 역할로 제대로 쓰였다.

**호스트에서 재도 안 된다.** macOS 의 published port 로 재면 Docker 포트 포워더가 먼저 연결을 받아버려서, netem 을 걸어둬도 `connect` 가 0.2ms 로 나온다. 포워더도 프록시라 똑같이 가린다. 측정은 전부 네트워크 안에서 해야 한다.

**netem 은 조용히 사라진다.** qdisc 는 컨테이너 netns 에 붙어 있어서 컨테이너가 재생성되면 없어진다. 2번을 한 번 RTT 0 에서 돌리고 나서야 알았다. 더 고약한 건 compose 가 **매번 현재 셸 환경으로 서비스 정의를 다시 계산**한다는 것이다. `docker-compose up -d caller` 한 번에 의존 서비스인 upstream 까지 기본값으로 되돌려 만든다. 그래서 실험 스크립트가 매번 netem 을 다시 걸고 `connect` 시간으로 검증하게 했다. **실험 조건은 설정하는 게 아니라 매 회차 검증해야 하는 것**이다.

**`Timeout.DISABLED`(0) 은 무한이 아니다.** 즉시 실패다. "상한은 있는데 포기가 없는" 조건을 만들려면 충분히 큰 값(60초)을 줘야 한다.

**톰캣은 자기 타임아웃을 알려준다.** 9번에서 예측했던 사각지대가 안 생긴 이유다. 다만 예측 자체가 틀린 건 아니었다 — 헤더를 안 보내는 서버로 바꿔 보니(11번 D3) 클라이언트가 기본 3분을 잡고 그 사각지대가 그대로 재현됐다. 둘 다 위에 적었다.

**TIME_WAIT 을 가른 건 먼저 닫는 쪽이 아니었다.** 1번에서 caller 쪽이 0 으로 나온 걸 "서버가 능동 종료자라서"로 적어뒀는데, 재보니 양쪽 다 0 이었다. FIN 이 아니라 RST 로 끝나서다. 위에 따로 적었다.

**`try-with-resources` 로 닫기만 하면 재사용을 잃을 거라고 봤다.** 반납 트리거가 본문 소비뿐이라고 읽었기 때문인데, 재보면 새 소켓이 안 늘었다. `ResponseEntityProxy.close()` 가 남은 본문을 드레인하고 반납까지 한다 (15번).

## 나중 단계로 미뤄둘 것
---

- **upstream 플랫폼 스레드 vs 가상 스레드** — 7번에서 caller 쪽에 보이는 "소켓 점유 → 스레드 점유" 가 서버 쪽에서 반복되는 그림이라, 짝지어 보면 한 바퀴 돈다.
- **지연에 지터 주기** — 평균 지연으로 계산한 필요 커넥션 수는 응답시간에 꼬리가 있으면 **과소평가**한다. 3번에서 고정 지연으로 예측이 맞는 걸 확인했으니, 이제 깨볼 차례다.
- **TLS 세션 재개** — 4번에서 RTT 0 인데도 https 수립에 28.7ms 가 들었다. 세션 티켓이 이 비용을 얼마나 깎는지.
