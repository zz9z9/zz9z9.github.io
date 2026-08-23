---
title: WEB - RestTemplate·HttpClient5 설정과 타임아웃
date: 2026-08-22 21:25:00 +0900
categories: [지식 더하기, 이론]
tags: [WEB]
---

> `RestTemplate`으로 HTTP를 호출할 때 타임아웃 설정 입구는 네 곳에 흩어져 있다 — 커넥션 매니저, `HttpClient`, 요청 팩토리, 요청 컨텍스트. 같은 이름의 값이 여러 곳에 걸려 있을 때 실제로 무엇이 적용되는지를 Apache HttpClient 5.5.2 / Spring Framework 6.2.19 소스와 실행 결과로 확인했다.

## 실무에서 보는 설정

---

> 계층별 설정이 다 등장하는 형태의 `HttpClientConfig`. 이 글은 이 설정을 아래(커넥션 매니저)에서부터 따라 올라간다.

```java
@Configuration
public class HttpClientConfig {

    private static final RequestConfig BASE_REQUEST_CONFIG = RequestConfig.custom()
            .setResponseTimeout(5, TimeUnit.SECONDS)
            .setConnectionRequestTimeout(3, TimeUnit.SECONDS)
            .setConnectionKeepAlive(TimeValue.ofSeconds(30))
            .build();

    @Bean
    public PoolingHttpClientConnectionManager connectionManager() {
        return PoolingHttpClientConnectionManagerBuilder.create()
                .setMaxConnTotal(200)
                .setMaxConnPerRoute(50)
                .setDefaultSocketConfig(SocketConfig.custom()
                        .setSoTimeout(Timeout.ofSeconds(2))
                        .setTcpNoDelay(true)
                        .build())
                .setDefaultConnectionConfig(ConnectionConfig.custom()
                        .setConnectTimeout(Timeout.ofMilliseconds(1000))
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
    public RestTemplate restTemplate(CloseableHttpClient httpClient) {
        HttpComponentsClientHttpRequestFactory factory = new HttpComponentsClientHttpRequestFactory(httpClient);
        factory.setConnectTimeout(Duration.ofSeconds(3));   // 6.2.13 부터 deprecated — 아래에서 다룬다
        factory.setReadTimeout(Duration.ofSeconds(5));
        factory.setConnectionRequestTimeout(Duration.ofSeconds(5));

        // 팩토리 setter 는 전역값이라 경로별로 못 가른다. 요청별 상한은 컨텍스트로 준다
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

`responseTimeout`만 해도 세 곳에 걸려 있다 — `BASE_REQUEST_CONFIG`, `factory.setReadTimeout`, 경로별 컨텍스트. `/balance` 요청의 read 상한이 300ms인지 5s인지가 바로 답이 나오지 않는다.

## 흐름

---

> 요청 하나가 커널까지 내려가는 경로와, 그 경로를 실제로 실행하는 `HttpClient` 내부 체인.

```
RestTemplate
ㄴ HttpComponentsClientHttpRequestFactory
     요청 객체 + HttpContext 를 만든다. 타임아웃(RequestConfig)은 컨텍스트에 심는다
  ㄴ HttpClient (CloseableHttpClient)
       route 를 정하고 요청 처리를 시작한다
    ㄴ PoolingHttpClientConnectionManager
         풀에서 커넥션을 내어주고(lease), 없으면 새로 수립한다(connect)
      ㄴ ManagedHttpClientConnection
           HTTP 메시지 ↔ 바이트로 바꿔 소켓에 쓴다
        ㄴ Socket
          ㄴ Kernel
```

각 단계를 실제로 실행하는 건 `HttpClient` 안의 요청 처리 체인(exec chain)에 등록된 핸들러들이다. `HttpClientBuilder`가 `addFirst`로 쌓으므로 바깥에서 안쪽 순서는 이렇게 된다.

| 순서 (바깥 → 안쪽) | 핸들러 | 하는 일 |
|---|---|---|
| 1 | `RedirectExec` | 3xx면 새 route를 정해 안쪽 체인을 다시 돈다 |
| 2 | `HttpRequestRetryExec` | 재시도 대상이면 안쪽 체인을 다시 돈다 |
| 3 | `ProtocolExec` | Host 헤더·인증 등 프로토콜 처리 |
| 4 | `ConnectExec` | 커넥션 매니저에서 커넥션 확보 (lease → connect) |
| 5 | `MainClientExec` | 확보한 커넥션으로 요청 전달·응답 수신 |

재시도와 리다이렉트가 커넥션 확보보다 **바깥**에 있다. 다시 돌면 lease부터 전부 반복되고, 타임아웃도 처음부터 다시 센다.

```java
// org.apache.hc.client5.http.impl.classic.InternalHttpClient
@Contract(threading = ThreadingBehavior.SAFE_CONDITIONAL)
@Internal
class InternalHttpClient extends CloseableHttpClient implements Configurable {

  private static final Logger LOG = LoggerFactory.getLogger(InternalHttpClient.class);

  private final HttpClientConnectionManager connManager;
  private final HttpRequestExecutor requestExecutor;
  private final ExecChainElement execChain;
  private final HttpRoutePlanner routePlanner;

  ...

}
```

## 구성 요소

---

> 계층마다 이름이 비슷한 타임아웃 설정이 또 나오는 게 이 스택의 혼란 지점이다. 아래 계층부터 올라가면서 각 컴포넌트가 무엇을 책임지는지 본다.

### Apache HttpClient 5

HTTP 표준의 **클라이언트 쪽**을 구현한 자바 라이브러리다. 공식 문서가 잡는 대상은 "웹 브라우저, 웹 서비스 클라이언트처럼 HTTP 프로토콜을 활용하거나 확장하는 애플리케이션"이고, 스스로 브라우저는 아니라고 못박는다 — 콘텐츠를 렌더링하거나 자바스크립트를 실행하지 않는다.

- HTTP/1.0 · 1.1 · 2.0 구현. HTTPS 지원
- Basic · Digest · Bearer · SCRAM-SHA-256 인증, 쿠키를 포함한 상태 관리
- gzip · deflate 투명 압축 해제 (zstd · brotli는 선택)
- 커넥션 풀링과 리다이렉트·재시도 처리
- 동기(classic) API와 별개로 async · reactive API 제공

API가 두 갈래인 게 이 글과 관계가 있다. `RestTemplate`이 쓰는 건 **classic(동기)** 쪽이고, 패키지부터 갈린다.

| | 진입점 | 패키지 |
| --- | --- | --- |
| classic (동기) | `HttpClients` → `CloseableHttpClient` | `...http.impl.classic` |
| async | `HttpAsyncClients` → `CloseableHttpAsyncClient` | `...http.impl.async` · `...impl.nio` |

이 글의 내용은 classic 기준이다. async 쪽은 커넥션 오퍼레이터부터 별도 클래스라서 타임아웃이 걸리는 지점도 다르다.

```gradle
implementation 'org.apache.httpcomponents.client5:httpclient5'
```

### PoolingHttpClientConnectionManager

`org.apache.hc.client5.http.io.HttpClientConnectionManager`의 구현체다. 인터페이스가 규정하는 역할은 세 가지다.

- 새 HTTP 커넥션을 만드는 팩토리
- keep-alive로 살아 있는 커넥션을 관리
- 한 커넥션에 한 번에 한 스레드만 접근하도록 동기화

요청을 실행하는 일은 여기 없다. 커넥션을 만들고 '관리'만 한다.

`Pooling` 구현체는 여기에 풀을 얹고, **route 단위로** 풀링한다.

- route = (스키마, 호스트, 포트). 프록시를 거치면 프록시 정보까지 포함된다
- 같은 route로 가는 요청은 풀에 놀고 있는 커넥션이 있으면 새로 만들지 않고 빌려 쓴다(lease)
- 커넥션 수 상한은 route별(`maxConnPerRoute`)과 전체(`maxConnTotal`) 두 축이다
- TTL이 지난 커넥션은 아직 연결돼 있어도 재사용하지 않는다

route 단위라는 점이 뒤에서 반복해 걸린다. `ConnectionConfig`와 `SocketConfig`도 요청이 아니라 route를 키로 해석되고(`resolveConnectionConfig(route)`), `RequestConfig.connectTimeout`이 deprecated된 이유도 여기에 있다.

### 커넥션 매니저 설정

```java
@Bean
public PoolingHttpClientConnectionManager connectionManager() {
    return PoolingHttpClientConnectionManagerBuilder.create()
            .setMaxConnTotal(200)
            .setMaxConnPerRoute(50)
            .setDefaultSocketConfig(SocketConfig.custom()
                    .setSoTimeout(Timeout.ofSeconds(2))
                    .setTcpNoDelay(true)
                    .build())
            .setDefaultConnectionConfig(ConnectionConfig.custom()
                    .setConnectTimeout(Timeout.ofMilliseconds(1000))
                    .setSocketTimeout(Timeout.ofSeconds(3))
                    .setTimeToLive(TimeValue.ofMinutes(5))
                    .setValidateAfterInactivity(TimeValue.ofSeconds(2))
                    .build())
            .build();
}
```

| 설정 | 기본값 | 무엇을 정하나 |
| --- | --- | --- |
| `maxConnTotal` | 25 | 풀 전체 커넥션 수 상한 |
| `maxConnPerRoute` | 5 | route 하나당 커넥션 수 상한 |
| `SocketConfig.soTimeout` | 3분 | 소켓 생성 직후 깔리는 `SO_TIMEOUT` 바닥값 |
| `SocketConfig.tcpNoDelay` | true | Nagle 알고리즘 비활성화 |
| `ConnectionConfig.connectTimeout` | 3분 | TCP connect 상한. `RequestConfig.connectTimeout`이 null일 때 쓰인다 |
| `ConnectionConfig.socketTimeout` | null (안 덮음) | 커넥션의 기준 read 상한. 수립 직후와 lease마다 `SO_TIMEOUT`에 다시 걸린다 |
| `ConnectionConfig.timeToLive` | null (무제한) | 커넥션 최대 수명. 넘으면 재사용하지 않고 버린다 |
| `ConnectionConfig.validateAfterInactivity` | null (검사 안 함) | 이 시간 이상 놀았던 커넥션은 빌려주기 전에 stale 여부를 확인한다 |

`SocketConfig.soTimeout`과 `ConnectionConfig.socketTimeout`은 이름도 비슷하고 둘 다 read 상한(`SO_TIMEOUT`)을 건드리는데, 거는 시점이 다르다. [3. readTimeout은 fallback이 아니라 덮어쓰기](#3-readtimeout은-fallback이-아니라-덮어쓰기)에서 정리한다.

### HttpClient / CloseableHttpClient

`HttpClient`는 요청 실행 계약만 정의하는 인터페이스다. 상태 관리·인증·리다이렉트를 어떻게 처리할지는 구현체에 맡긴다. 커넥션 매니저가 '관리'라면 여기는 '실행'이다 — 매니저에서 커넥션을 빌려와 그 위로 요청을 흘려보낸다.

`HttpClients.custom()` → `HttpClientBuilder#build()`가 돌려주는 게 `CloseableHttpClient`(실제 타입은 `InternalHttpClient`)다. 소켓과 풀을 쥐고 있으므로 닫아야 하고, 그래서 `Closeable`이다.

```java
@Bean
public CloseableHttpClient httpClient(PoolingHttpClientConnectionManager cm) {
    return HttpClients.custom()
            .setConnectionManager(cm)
            .setDefaultRequestConfig(
                    RequestConfig.custom()
                            .setResponseTimeout(5, TimeUnit.SECONDS)
                            .setConnectionRequestTimeout(3, TimeUnit.SECONDS)
                            .setConnectionKeepAlive(TimeValue.ofSeconds(30))
                            .build()
            )
            .evictIdleConnections(TimeValue.ofSeconds(30))
            .build();
}
```

여기에도 타임아웃이 있지만 매니저 쪽과 성격이 다르다. 매니저 설정은 커넥션에 딸린 속성이고, `setDefaultRequestConfig`은 **요청에 실려 다니는** 기본값이다. 요청마다 다른 값을 줄 수 있는 건 이쪽뿐이다.

### HttpComponentsClientHttpRequestFactory (Spring 컴포넌트)

Spring의 `ClientHttpRequestFactory` 구현체로, `RestTemplate`이 쓰는 추상화와 Apache `HttpClient` 사이를 잇는다. `RestTemplate`은 JDK `HttpURLConnection`이나 Jetty 클라이언트로도 갈아끼울 수 있어야 해서 Apache HttpClient를 직접 알지 못하고, 그래서 이 층이 하나 더 필요하다.

요청 하나당 이 팩토리가 두 가지를 만든다.

- `ClassicHttpRequest` — 실제로 보낼 요청 객체
- `HttpContext` — 그 요청의 실행 컨텍스트. **타임아웃(`RequestConfig`)이 여기 실린다**

```java
HttpComponentsClientHttpRequestFactory factory = new HttpComponentsClientHttpRequestFactory(httpClient);
factory.setConnectionRequestTimeout(Duration.ofSeconds(5));
factory.setReadTimeout(Duration.ofSeconds(5));
factory.setHttpContextFactory((method, uri) -> {
    HttpClientContext ctx = HttpClientContext.create();
    Timeout responseTimeout = RESPONSE_TIMEOUTS.get(uri.getPath());
    if (responseTimeout != null) {
        ctx.setRequestConfig(RequestConfig.copy(BASE_REQUEST_CONFIG)
                .setResponseTimeout(responseTimeout)
                .build());
    }
    return ctx;
});
```

`setHttpContextFactory`는 요청마다 컨텍스트를 만드는 훅이다. `(HttpMethod, URI)`를 받으므로 경로별로 다른 `RequestConfig`를 실을 수 있다. 팩토리 setter가 전역값인 것과 달리, **요청별로 타임아웃을 갈라야 할 때 쓸 수 있는 유일한 입구**다.

### ConnectTimeout은 deprecated

`HttpComponentsClientHttpRequestFactory#setConnectTimeout`은 Spring 6.2.13부터 deprecated이고 `forRemoval`이 붙어 있다.

```java
@Deprecated(since = "6.2.13", forRemoval = true)
public void setConnectTimeout(int connectTimeout) {
    Assert.isTrue(connectTimeout >= 0, "Timeout must be a non-negative value");
    this.connectTimeout = connectTimeout;
}
```

javadoc이 지목하는 대안은 커넥션 매니저의 `ConnectionConfig`다. 같은 값이 httpclient5 쪽 `RequestConfig`에서도 deprecated인데, 이유는 `connectTimeout`이 요청이 아니라 **커넥션**의 속성이기 때문이다. keep-alive로 재사용되는 요청은 connect를 아예 하지 않고, 커넥션 매니저는 이 값을 route 단위로 해석한다.

deprecated지만 코드 경로는 살아 있어서 세팅하면 여전히 `ConnectionConfig.connectTimeout`을 이긴다 ([2. 설정값별 최종 적용 경로](#2-설정값별-최종-적용-경로)). 예전 코드에 남은 `factory.setConnectTimeout(30s)` 한 줄이 매니저에 새로 넣은 값을 조용히 덮는 형태가 되므로, 옮길 때 지우는 것까지 해야 한다.

이 setter의 javadoc에는 "SSL handshake나 CONNECT 요청의 타임아웃에는 영향을 주지 않는다, 그건 `SocketConfig`를 써야 한다"고 적혀 있다. httpclient5 5.5까지는 맞는 설명이고 5.5.1부터 달라졌다 ([TLS handshake는 어느 타임아웃에 걸리나](#tls-handshake는-어느-타임아웃에-걸리나)).

Spring 7.0에는 이 setter가 아예 없다. `mergeRequestConfig`도 `connectionRequestTimeout`과 `readTimeout` 두 필드만 병합한다.

### RestTemplate

`org.springframework.web.client.RestTemplate`. HTTP 메서드별 템플릿 메서드와 범용 `exchange`·`execute`를 노출하는 동기 클라이언트다. 실제 통신은 전부 `ClientHttpRequestFactory`에 위임하므로, 타임아웃 관점에서 `RestTemplate` 자체가 하는 일은 없다.

공유 컴포넌트로 쓰도록 만들어졌지만 설정 변경이 동시성에 안전하지 않아서, 설정은 기동 시점에 끝내야 한다. 설정이 다른 인스턴스가 여럿 필요하면 `ClientHttpRequestFactory`는 공유하면서 `RestTemplate`만 여러 개 만들면 된다.

### RestClient

`org.springframework.web.client.RestClient`. 6.1부터 들어온 동기 클라이언트로, 같은 `ClientHttpRequestFactory` 위에 fluent API를 얹은 것이다. `RestClient.create(restTemplate)` / `builder(restTemplate)`로 기존 `RestTemplate` 설정을 그대로 물려받을 수 있다.

**타임아웃 설정 계층은 `RestTemplate`과 완전히 같다.** 이 글의 내용은 둘 다에 그대로 적용된다.

## 타임아웃 정리

---

> `connectTimeout`, `readTimeout`, `connectionRequestTimeout`이 각각 어디서 정해지는지 정리한다. 설정 입구 네 곳(커넥션 매니저의 `SocketConfig`·`ConnectionConfig`, RequestFactory, RequestFactory의 `HttpContext`)이 하나의 fallback 체인을 이루는 게 아니라, 설정값마다 경로가 다르다.

Apache HttpClient 5.5.2 / httpcore5 5.3.6 / Spring Framework 6.2.19 소스와 실행 결과 기준이다.

### 1. RequestConfig 덩어리가 정해지는 순서

`connectionRequestTimeout`, `connectTimeout`, `responseTimeout`, `connectionKeepAlive`는 전부 `RequestConfig` 하나에 담겨 요청에 실려 다닌다. 그 `RequestConfig`가 어디서 오는지가 먼저다.

| 순위 | 출처 | 적용 방식 |
| --- | --- | --- |
| 1 | RequestFactory의 `HttpContext` — `httpContextFactory`가 만든 컨텍스트에 `RequestConfig`가 들어 있고, 그게 `RequestConfig.DEFAULT`와 `equals`가 아닐 때 | **통째로** 채택. Client·Factory 설정은 전부 무시된다 (all-or-nothing) |
| 2 | 요청 객체 자체 — `HttpGet.setConfig` 등 `Configurable` 구현 | `InternalHttpClient.doExecute`가 실행 직전 컨텍스트를 덮는다 |
| 3 | Client default ⊕ Factory setter | Client의 `setDefaultRequestConfig` 값을 복사본 베이스로 두고, Factory에 세팅된 필드만 그 위에 덮는다 — **필드 단위 병합, Factory 우선** |

1번이 all-or-nothing이라는 게 함정이다. 컨텍스트에 `RequestConfig`를 하나 꽂으면 거기 안 담긴 항목까지 그 객체의 값(대개 `RequestConfig.DEFAULT`)으로 떨어진다. `RestTemplate` 경로에서는 Spring이 요청 객체에 `RequestConfig`를 넣지 않으므로 2번은 쓰이지 않는다. 실질적으로 1번 아니면 3번이다.

### 3순위 병합은 구체적으로 어떤 값이 남나

`mergeRequestConfig`의 조건은 필드별 `>= 0`이다.

```java
// HttpComponentsClientHttpRequestFactory.java:325-341 (spring-web 6.2.19)
protected RequestConfig mergeRequestConfig(RequestConfig clientConfig) {
    if (this.connectTimeout == -1 && this.connectionRequestTimeout == -1 && this.readTimeout == -1) {  // nothing to merge
        return clientConfig;
    }

    RequestConfig.Builder builder = RequestConfig.copy(clientConfig);
    if (this.connectTimeout >= 0) {
        builder.setConnectTimeout(this.connectTimeout, TimeUnit.MILLISECONDS);
    }
    if (this.connectionRequestTimeout >= 0) {
        builder.setConnectionRequestTimeout(this.connectionRequestTimeout, TimeUnit.MILLISECONDS);
    }
    if (this.readTimeout >= 0) {
        builder.setResponseTimeout(this.readTimeout, TimeUnit.MILLISECONDS);
    }
    return builder.build();
}
```

세 필드의 초기값이 `-1`이므로, setter를 호출하지 않은 항목은 병합 대상에서 빠지고 Client 값이 그대로 살아남는다. Client에 세 값을 모두 1000ms로 걸어 두고 Factory 쪽을 바꿔 가며 `mergeRequestConfig`의 결과를 찍어 봤다.

```java
RequestConfig clientConfig = RequestConfig.custom()
        .setConnectionRequestTimeout(1000, TimeUnit.MILLISECONDS)
        .setConnectTimeout(1000, TimeUnit.MILLISECONDS)
        .setResponseTimeout(1000, TimeUnit.MILLISECONDS)
        .build();
HttpClient client = HttpClients.custom().setDefaultRequestConfig(clientConfig).build();

// mergeRequestConfig 가 protected 라 노출용 서브클래스로 감싸 호출
factory.setReadTimeout(2000);
factory.merge(clientConfig);
```

| 케이스 | Factory 설정 | connectionRequestTimeout | connectTimeout | responseTimeout |
| --- | --- | --- | --- | --- |
| A | 없음 | 1000ms | 1000ms | 1000ms |
| B | `setReadTimeout(2000)` | 1000ms | 1000ms | **2000ms** |
| C | 셋 다 3000 | **3000ms** | **3000ms** | **3000ms** |
| D | `setReadTimeout(2000)` (Client 설정 없음) | 3분 | null | 2000ms |
| E | `setReadTimeout(0)` | 1000ms | 1000ms | **0ms = 무한** |

B가 이 병합의 성격을 보여준다. Factory에서 `readTimeout` 하나만 건드렸는데 나머지 두 값은 Client 것이 그대로 남는다. "Factory에 설정하면 Client 설정이 통째로 무시된다"도, "Client가 우선이다"도 아니고 **필드 단위로 Factory가 이긴다.**

D는 Client 쪽 `RequestConfig`에 아무것도 안 넣은 경우다. 병합되지 않은 자리는 `RequestConfig` 자체의 기본값(`connectionRequestTimeout` 3분, `connectTimeout` null)으로 떨어진다.

E는 조건이 `> 0`이 아니라 `>= 0`이라서 생긴다. `0`은 "설정 안 함"이 아니라 **무한 대기**로 해석되므로, 계산 결과가 0이 될 수 있는 변수를 setter에 그대로 넘기면 타임아웃이 사라진다.

### 2. 설정값별 최종 적용 경로

| 설정 | 소비 지점 | 적용 순서 | 아무것도 설정 안 하면 |
| --- | --- | --- | --- |
| `connectionRequestTimeout` | 풀에서 커넥션 대여(lease) 대기 | `RequestConfig` 하나뿐 (위 1번 표) | 3분 |
| `connectTimeout` | TCP connect (+TLS handshake) | `RequestConfig.connectTimeout`(deprecated) → **null이면** `ConnectionConfig.connectTimeout` | 3분 |
| `readTimeout`(=`responseTimeout`) | 응답 read = 소켓 `SO_TIMEOUT` | 덮어쓰기 스택 (아래 3번) | 3분 |
| `connectionKeepAlive` | 재사용 커넥션 유지 상한 | `RequestConfig` 하나뿐 | 3분 |

`connectTimeout`만 진짜 fallback이다. `InternalExecRuntime`이 `requestConfig.getConnectTimeout()`을 매니저에 넘기고, 매니저가 그게 null일 때만 자기 `ConnectionConfig`를 쓴다.

```java
// PoolingHttpClientConnectionManager.java:492
final Timeout connectTimeout = timeout != null
        ? Timeout.of(timeout.getDuration(), timeout.getTimeUnit())
        : connectionConfig.getConnectTimeout();
```

`SocketConfig`·`ConnectionConfig` 어디에도 `connectionRequestTimeout`에 대응하는 값은 없다. `soTimeout`/`socketTimeout`은 read 전용이고 풀 대기와는 무관하다.

반대 방향도 마찬가지다. `validateAfterInactivity` · `timeToLive` · `soTimeout` 바닥값은 요청이 아니라 커넥션에 딸린 속성이라 `RequestConfig`로는 건드릴 수 없고, 어떤 요청이든 항상 매니저 설정만 쓰인다.

### 3. readTimeout은 fallback이 아니라 덮어쓰기

read 상한의 실체는 소켓 옵션 `SO_TIMEOUT` 하나다. **블로킹 read 한 번이 데이터를 기다릴 수 있는 최대 시간**으로, 스레드가 `socket.read()`를 호출하면 커널 버퍼에 데이터가 도착할 때까지 그 자리에서 멈춰 기다리다가(블로킹) 그 시간 안에 한 바이트도 안 오면 `SocketTimeoutException`이 난다. 성질이 두 가지다.

- **read 호출 1회당** 적용된다. 응답 전체 시간의 상한이 아니다. 서버가 바이트를 조금씩 흘려주면 read가 성공할 때마다 대기가 새로 시작되므로, 응답 전체는 `SO_TIMEOUT`보다 훨씬 오래 걸릴 수 있다.
- 소켓 위에서 일어나는 **모든 블로킹 read**에 적용된다 — TLS handshake 중의 read, 상태줄·헤더 read, 바디 read 전부. 어느 단계냐가 아니라, 그 read가 일어나는 순간 소켓에 어떤 값이 깔려 있느냐만 문제다.

read 계열 설정 3개는 우선순위 로직이 따로 있는 게 아니라, 이 한 자리를 서로 다른 시점에 덮어쓴다.

```
SO_TIMEOUT 한 자리 — 나중에 덮은 값이 이긴다

소켓 생성 시   SocketConfig.soTimeout          기본 3분   → 항상 깔린다 (바닥)
     ↓
connect 직후   ConnectionConfig.socketTimeout  기본 null  → null이면 안 덮음
lease 직후     ConnectionConfig.socketTimeout  풀에서 꺼낼 때마다 다시 걸림
     ↓
요청 직전      RequestConfig.responseTimeout   기본 null  → null이면 안 덮음
```

`soTimeout`을 "바닥값"이라 부르는 이유가 여기 있다. 시간 축에서는 세 값 모두 대기 시간의 상한(천장)이고, "바닥"은 이 덮어쓰기 스택에서의 위치를 말한다 — 제일 먼저 깔려서 위에 아무것도 안 덮인 구간에서만 드러나는 층이다.

`SocketConfig`와 `ConnectionConfig.connectTimeout`은 커넥션이 **새로 만들어질 때만** 적용된다. 풀에서 재사용되는 커넥션은 소켓 생성과 connect를 통째로 건너뛴다. `ConnectionConfig.socketTimeout`만 예외로, 수립 직후뿐 아니라 **풀에서 커넥션을 꺼낼 때(lease)마다** 다시 걸린다.

정리하면 "앞이 없으면 뒤를 쓴다"가 아니라 **"뒤가 있으면 앞을 덮는다"** 이고, 덮은 값은 요청이 끝나도 복원되지 않은 채 커넥션과 함께 풀로 돌아간다. `responseTimeout`을 일부 요청에만 주면 다음 요청이 그 값을 물려받는 이유다. 이걸 되돌리는 게 lease마다 다시 걸리는 `ConnectionConfig.socketTimeout`이고, 설정하지 않으면(기본 null) 리셋이 없어 read 상한이 그 커넥션을 직전에 쓴 요청에 따라 달라진다. (실측은 [재사용 커넥션에서 read 상한이 섞이는 걸 확인해보기](#재사용-커넥션에서-read-상한이-섞이는-걸-확인해보기))

그래도 무한 대기가 나지는 않는데, 특정 설정 덕이 아니라 스택 구조 자체 덕이다 — `SocketConfig.DEFAULT.soTimeout`이 null이 아니라 3분이라 `SO_TIMEOUT` 자리는 항상 유한한 값으로 채워져 있다.

### 그래서 설정할 곳

| 어디에 | 무엇을 |
| --- | --- |
| `HttpClient.setDefaultRequestConfig` | `connectionRequestTimeout`, `responseTimeout`, `connectionKeepAlive` |
| 커넥션 매니저의 `ConnectionConfig` | `connectTimeout`, `socketTimeout` |

RequestFactory setter는 위 1번 표의 3순위 경로에서 Client 설정 위에 필드 단위로 덮이므로, 둘 다 쓰면 어느 값이 이겼는지 코드만 봐서는 추적이 어려워진다. 한 곳으로 몰아두는 편이 낫다.


## 근거: 소스와 실측

---

> 위 정리를 확인한 코드와 실행 결과. 설정 입구는 4곳(팩토리, 컨텍스트, HttpClient, 커넥션 매니저)에 흩어져 있지만, 요청이 실행될 때 실제로 타임아웃을 소비하는 주체는 둘뿐이다 — 요청에 실려 다니는 `RequestConfig`와, 커넥션 매니저가 커넥션에 발라두는 `ConnectionConfig`/`SocketConfig`.

Apache HttpClient 5.5.2 / Spring Framework 6.2.19 소스 기준으로 확인한 내용이다. 버전에 따라 갈리는 항목(TLS handshake)은 5.0.4~5.6.4 릴리스 태그 소스를 비교했다.

### 설정 입구 라벨

| 라벨 | 설정 위치 | 타임아웃 항목 |
|---|---|---|
| **Context** | `httpContextFactory`에서 `HttpClientContext`에 실은 `RequestConfig` | `RequestConfig` 전체 |
| **Factory** | `HttpComponentsClientHttpRequestFactory` setter | `setReadTimeout`(→ `responseTimeout`으로 병합), `setConnectionRequestTimeout`, `setConnectTimeout`(6.2.13부터 deprecated) |
| **Client** | `HttpClient`의 `setDefaultRequestConfig(...)` | `RequestConfig` 전체 |
| **Manager** | `PoolingHttpClientConnectionManager`의 `ConnectionConfig` / `SocketConfig` | `connectTimeout` · `socketTimeout` · `timeToLive` · `validateAfterInactivity` / `soTimeout` |

Context, Factory, Client는 입구는 셋이지만 결국 전부 `RequestConfig`라는 같은 그릇으로 모인다. 어느 입구가 이기는지는 [위](#1-requestconfig-덩어리가-정해지는-순서)에서 정리했고, 그 판정과 병합을 실제로 하는 코드가 `HttpComponentsClientHttpRequestFactory#createRequest`다.

```java
// createRequest — context 에 RequestConfig 가 이미 있으면(Context) 이 블록 전체가 스킵된다
if (!hasCustomRequestConfig(context)) {
    RequestConfig config = null;
    // 요청 객체 자체에 config 가 실려 있으면 그대로 사용 (RestTemplate 경로에서는 사실상 항상 null)
    if (httpRequest instanceof Configurable configurable) {
        config = configurable.getConfig();
    }
    if (config == null) {
        config = createRequestConfig(client);   // Client ⊕ Factory
    }
    if (config != null) {
        if (context instanceof HttpClientContext clientContext) {
            clientContext.setRequestConfig(config);
        }
        context.setAttribute(HttpClientContext.REQUEST_CONFIG, config);
    }
}
```

```java
// Context 판정
private static boolean hasCustomRequestConfig(HttpContext context) {
    if (context instanceof HttpClientContext clientContext) {
        RequestConfig requestConfig = clientContext.getRequestConfig();
        return requestConfig != null && !requestConfig.equals(RequestConfig.DEFAULT);
    }
    return context.getAttribute(HttpClientContext.REQUEST_CONFIG) != null;
}
```

```java
// Client ⊕ Factory 의 실체 — mergeRequestConfig 본문과 실측 결과는 위 절 참고
private RequestConfig createRequestConfig(Object client) {
    if (client instanceof Configurable configurableClient) {
        return mergeRequestConfig(configurableClient.getConfig());
    }
    return mergeRequestConfig(RequestConfig.DEFAULT);
}
```

`hasCustomRequestConfig`는 context의 config가 `RequestConfig.DEFAULT`와 `equals`로 같으면 custom이 아닌 것으로 판정한다. 아무 값 없이 `RequestConfig.custom().build()`를 context에 실으면 Context로 인정되지 않는다.

### 요청 한 번의 타임라인

```
restTemplate.getForObject(...)
│
├─ ① 요청 생성 (HttpComponentsClientHttpRequestFactory.createRequest)
│     context 에 RequestConfig 있는가?
│       있으면(Context) → 이 요청의 RequestConfig = Context   (Factory, Client 는 완전 무시)
│       없으면          → 이 요청의 RequestConfig = Client ⊕ Factory
│     ▶ 이후 단계에서 "RequestConfig" 는 여기서 확정된 것 하나를 말한다
│
└─ ② httpClient.execute(request, context)
   │
   ├─ [풀 대기]  connectionRequestTimeout
   │      ◀ RequestConfig             = Context 또는 (Factory, 없으면 Client)
   │    놀던 커넥션 stale 체크 기준 (validateAfterInactivity)
   │      ◀ Manager (ConnectionConfig)                     ← 항상 Manager
   │    lease 직후: socketTimeout 설정돼 있으면 SO_TIMEOUT 리셋
   │      ◀ Manager (ConnectionConfig)                     ← 항상 Manager
   │
   ├─ [커넥션 수립]  ※ 새 커넥션일 때만. 재사용이면 통째로 스킵
   │    소켓 생성: SO_TIMEOUT 바닥값 (soTimeout)
   │      ◀ Manager (SocketConfig)                         ← 항상 Manager
   │    TCP connect (connectTimeout, DNS 결과 주소마다 반복)
   │      ◀ RequestConfig.connectTimeout 이 있으면 그것    = Context 또는 Factory
   │        null 이면 Manager (ConnectionConfig.connectTimeout)
   │    TLS handshake — 5.5.1+: connectTimeout, 5.5 이하: soTimeout (하단 절 참고)
   │    수립 직후: SO_TIMEOUT = socketTimeout, TTL 스탬프
   │      ◀ Manager (ConnectionConfig)                     ← 항상 Manager
   │
   ├─ [요청 실행 직전]  responseTimeout 있으면 SO_TIMEOUT 덮어씀
   │      ◀ RequestConfig             = Context 또는 (Factory, 없으면 Client)
   │
   ├─ [응답 대기·읽기]  현재 SO_TIMEOUT = read 상한
   │      = 위에서 마지막으로 덮은 값 (안 덮었으면 Manager 의 socketTimeout → soTimeout 순으로 남은 값)
   │
   └─ [반납] 풀로 release — SO_TIMEOUT 은 마지막 값 그대로 남는다
```

### 재사용 커넥션에서 read 상한이 섞이는 걸 확인해보기

[readTimeout은 fallback이 아니라 덮어쓰기](#3-readtimeout은-fallback이-아니라-덮어쓰기)의 두 가지 — `responseTimeout`이 커넥션에 남는다는 것, `ConnectionConfig.socketTimeout`이 그걸 되돌린다는 것 — 을 실제로 돌려서 확인했다. httpclient5 5.5.2 / httpcore5 5.3.6 / JDK 21 기준이다.

커넥션을 강제로 재사용시키기 위해 풀 크기를 1로 두고 두 요청을 순서대로 보낸다.

- **A**: `responseTimeout` 300ms, 즉시 응답하는 엔드포인트 → 성공하고 커넥션이 풀로 반납된다
- **B**: `responseTimeout` **미설정**, 800ms 걸리는 엔드포인트

```java
PoolingHttpClientConnectionManager cm = PoolingHttpClientConnectionManagerBuilder.create()
        .setDefaultConnectionConfig(cc.build())   // CASE 1: socketTimeout 미설정 / CASE 2: 5s
        .setMaxConnPerRoute(1).setMaxConnTotal(1)
        .build();

CloseableHttpClient client = HttpClients.custom()
        .setConnectionManager(cm)
        .setDefaultRequestConfig(RequestConfig.custom()
                .setConnectionRequestTimeout(Timeout.ofSeconds(5))
                .build())              // responseTimeout = null
        .disableAutomaticRetries()
        .build();

// A — 요청 객체에 config 를 실어 responseTimeout 300ms 적용
HttpGet a = new HttpGet("http://localhost:" + port + "/fast");
a.setConfig(RequestConfig.custom()
        .setConnectionRequestTimeout(Timeout.ofSeconds(5))
        .setResponseTimeout(Timeout.ofMilliseconds(300)).build());
exec(client, a);

// B — 아무 설정도 주지 않는다
HttpGet b = new HttpGet("http://localhost:" + port + "/slow");
exec(client, b);
```

결과.

```
===== CASE 1: ConnectionConfig.socketTimeout 미설정 (기본 null) =====
A (responseTimeout=300ms, /fast) -> OK 200  (90ms)
   pool: [leased: 0; pending: 0; available: 1; max: 1]
B (responseTimeout 미설정, /slow 800ms) -> SocketTimeoutException: Read timed out  (303ms)

===== CASE 2: ConnectionConfig.socketTimeout = 5s =====
A (responseTimeout=300ms, /fast) -> OK 200  (2ms)
   pool: [leased: 0; pending: 0; available: 1; max: 1]
B (responseTimeout 미설정, /slow 800ms) -> OK 200  (802ms)
```

CASE 1의 B는 자기 설정이 아니라 A가 남긴 300ms에 걸려 303ms에 죽는다. CASE 2는 lease 시점에 5s로 리셋되어 802ms에 정상 응답한다. 두 CASE 모두 A 직후 풀 상태가 `available: 1`이므로 B가 같은 커넥션을 재사용한 것이 맞다.

값이 남는 쪽은 커넥션이다. 마지막으로 세팅된 SO_TIMEOUT을 필드에 기억해 두고, 풀에 반납될 때 소켓만 0으로 내렸다가 꺼낼 때 그 필드를 복원한다.

```java
// DefaultManagedHttpClientConnection
public void setSocketTimeout(final Timeout timeout) {
    super.setSocketTimeout(timeout);
    socketTimeout = timeout;          // 마지막 값을 필드에 기억
}

public void passivate() { super.setSocketTimeout(Timeout.ZERO_MILLISECONDS); }  // 반납: 소켓만 0, 필드는 유지
public void activate()  { super.setSocketTimeout(socketTimeout); }              // lease: 기억한 값 복원
```

되돌리는 쪽은 매니저인데, `ConnectionConfig.socketTimeout`이 설정돼 있을 때만 동작한다.

```java
// PoolingHttpClientConnectionManager
conn.activate();
if (connectionConfig.getSocketTimeout() != null) {   // 기본 null → 리셋이 일어나지 않는다
    conn.setSocketTimeout(connectionConfig.getSocketTimeout());
}
```

> `responseTimeout`을 일부 요청에만 주는 구성이라면 `ConnectionConfig.socketTimeout`을 함께 설정한다. 없으면 read 상한이 그 커넥션을 직전에 쓴 요청에 따라 달라진다.

### TLS handshake는 어느 타임아웃에 걸리나

TLS handshake에는 별도 타이머가 없다. handshake 자체가 소켓 위 read/write의 연속이라, ServerHello 등을 기다리는 것도 결국 블로킹 read이고 그 순간 소켓에 깔린 SO_TIMEOUT이 handshake를 지배한다. 그래서 질문은 "handshake 시점에 SO_TIMEOUT에 뭐가 들어있냐"로 환원되는데, 이게 버전에 따라 다르다 (릴리스 태그별 소스로 확인).

| HttpClient 버전 | handshake를 지배하는 값 |
|---|---|
| ~5.1 | `SocketConfig.soTimeout` (기본 3분). `TlsConfig`가 아직 없다 |
| 5.2 ~ 5.5 | `TlsConfig.handshakeTimeout`을 명시했으면 그것, 아니면 `SocketConfig.soTimeout` |
| 5.5.1~ | handshake 직전에 SO_TIMEOUT을 `handshakeTimeout ?? connectTimeout`으로 교체했다가 handshake 후 복원 → 사실상 `connectTimeout` |

경계는 5.6이 아니라 **5.5.1**이다. 5.5까지는 handshake 직전 SO_TIMEOUT 조정이 TLS 전략 쪽(`AbstractClientTlsStrategy#executeHandshake`)에 있었고, `handshakeTimeout`을 명시하지 않으면 아무것도 하지 않았다.

```java
// 5.5 — AbstractClientTlsStrategy#executeHandshake
final Timeout handshakeTimeout = tlsConfig.getHandshakeTimeout();
if (handshakeTimeout != null) {
    upgradedSocket.setSoTimeout(handshakeTimeout.toMillisecondsIntBound());
}
initializeSocket(upgradedSocket);
upgradedSocket.startHandshake();
```

5.5.1에서 이 코드가 커넥션 오퍼레이터로 옮겨가면서 `?: connectTimeout` 폴백과 원복이 붙었다. 5.6.4까지 동일하다.

```java
// 5.5.1~ — DefaultHttpClientConnectionOperator#connect
final int soTimeout = socket.getSoTimeout();
final Timeout handshakeTimeout = tlsConfig.getHandshakeTimeout() != null
        ? tlsConfig.getHandshakeTimeout() : connectTimeout;
if (handshakeTimeout != null) {
    socket.setSoTimeout(handshakeTimeout.toMillisecondsIntBound());
}
final SSLSocket sslSocket = tlsSocketStrategy.upgrade(socket, tlsName.getHostName(), tlsName.getPort(), attachment, context);
conn.bind(sslSocket, socket);
socket.setSoTimeout(soTimeout);   // 복원
```

"TLS handshake는 connectTimeout이 아니라 read(so) 타임아웃에 걸린다"는 설명은 5.5까지 기준으로는 맞는 말이고, 5.5.1부터는 `connectTimeout`이 handshake까지 커버한다. 이 경계가 Spring Boot 3.5.x 패치 사이에 걸쳐 있어서 마이너 버전만 보고는 판단할 수 없다.

| Spring Boot | 관리하는 httpclient5 |
|---|---|
| 3.3.13 | 5.3.1 |
| 3.4.10 · 3.5.0 | 5.4.4 |
| 3.5.5 · 3.5.6 | 5.5 |
| 3.5.7 이상 | 5.5.1 |

프록시 CONNECT 터널 위에서 TLS로 올라가는 경로(`DefaultHttpClientConnectionOperator#upgrade`)에는 5.6.4까지도 이 처리가 없다. 그쪽은 여전히 소켓에 깔려 있는 값, 즉 `soTimeout`(또는 그 시점의 SO_TIMEOUT)이 handshake를 지배한다.

### 타임아웃별 예외

어느 타임아웃이 터졌는지는 예외 타입으로 역추적할 수 있다.

| 초과한 타임아웃 | 예외 |
|---|---|
| `connectionRequestTimeout` (풀 대기) | `ConnectionRequestTimeoutException` |
| `connectTimeout` (TCP connect) | `ConnectTimeoutException` |
| SO_TIMEOUT (`responseTimeout` / `socketTimeout` / `soTimeout`) | `SocketTimeoutException` |

## 실무에서 생각해볼 것

---

> `connectTimeout`/`readTimeout` 두 개만 잡고 끝내기 쉬운데, 실무 장애는 그 옆 — 풀 대기, 풀 사이즈, 커넥션 수명 — 에서 더 자주 난다.

요청별로 상한을 달리해야 하면 Context(`httpContextFactory`)를 한 층 더 쓴다. 그 외에 아래 항목들은 타임아웃 값 자체와는 별개로 봐야 한다.

### 풀 대기: connectionRequestTimeout

기본값이 3분이다. 다운스트림이 느려지면 커넥션이 점유되고 다음 요청들이 풀 lease 대기에 들어가는데, 이 값이 길면 호출 스레드가 줄줄이 묶여 장애가 호출자 쪽으로 전파된다. read 타임아웃보다 짧게 잡는다. `ConnectionRequestTimeoutException`은 "상대가 느리다"가 아니라 "내 풀이 모자라다"는 신호라서 모니터링을 분리할 가치가 있다.

### 풀 사이즈와 타임아웃은 세트

`maxConnPerRoute` 기본값은 5다. 필요한 커넥션 수는 대략 TPS × 평균 응답시간이고, 최악의 응답시간은 read 타임아웃이므로 read 타임아웃을 늘리면 같은 TPS에서도 풀이 더 커야 한다. 타임아웃만 조정하고 풀을 안 보면 위의 풀 대기 문제로 되돌아간다.

### "요청 전체 시간"의 상한은 어디에도 없다

`responseTimeout`은 블로킹 read 1회당 상한이라, 서버가 바이트를 조금씩 흘려주는 응답은 read가 성공할 때마다 대기가 새로 시작되어 전체 시간이 상한 없이 늘어진다. 요청 전체 데드라인이 필요하면 HttpClient 설정만으로는 안 되고 상위 수단(Resilience4j `TimeLimiter`, 비동기 호출 + `Future.get(timeout)` 등)이 필요하다.

### keep-alive 커넥션의 반대편 수명

풀에 물고 있던 커넥션을 서버나 LB가 먼저 끊으면 타임아웃이 아니라 `NoHttpResponseException`이나 connection reset으로 나타난다. `setConnectionKeepAlive` · `timeToLive` · `evictIdleConnections` · `validateAfterInactivity`를 상대(서버·LB)의 idle timeout보다 짧게 맞추는 게 핵심이다. 본문 설정의 keepalive 30s / evict 30s / TTL 5m / validate 2s가 이 층이다.

### 재시도가 붙는 조건

`HttpClientBuilder`는 `disableAutomaticRetries()`를 부르지 않는 한 `DefaultHttpRequestRetryStrategy`를 체인에 끼워 넣는다. 기본값은 **최대 1회 재시도, 간격 1초**다. 다만 무엇이 재시도되는지는 통념과 다르다.

| 실패 | 재시도되나 |
| --- | --- |
| `SocketTimeoutException` (read 상한 초과) | ✗ |
| `ConnectTimeoutException` (connect 상한 초과) | ✗ |
| `ConnectionRequestTimeoutException` (풀 대기 초과) | ✗ |
| `NoHttpResponseException`, connection reset 등 그 밖의 `IOException` | 멱등 메서드만 ○ (GET·HEAD·PUT·DELETE·OPTIONS·TRACE) |
| 429 · 503 응답 | ○ — **멱등성을 따지지 않는다** |

타임아웃 예외 셋이 전부 `InterruptedIOException`을 상속하고, 이 클래스가 non-retriable 목록에 들어 있어서 그렇다.

```java
// DefaultHttpRequestRetryStrategy — 재시도하지 않는 IOException 목록
InterruptedIOException.class,   // ← SocketTimeoutException, ConnectTimeoutException,
                                //    ConnectionRequestTimeoutException 이 모두 여기 해당
UnknownHostException.class,
ConnectException.class,
ConnectionClosedException.class,
NoRouteToHostException.class,
SSLException.class
```

그래서 "타임아웃 × (1 + 재시도 횟수)"로 시간이 곱해지는 일은 기본 전략에서 일어나지 않는다. 예산이 늘어나는 건 다른 경로다.

- 멱등 요청이 커넥션 끊김(`NoHttpResponseException` 등)으로 실패하면 재시도가 붙어 connect와 응답 대기가 한 번 더 돌아간다
- 429/503 응답에는 `Retry-After` 헤더값 또는 기본 간격 1초의 대기가 더해진다

429/503 경로에 멱등성 검사가 없다는 게 주의할 점이다. 결제 POST가 503을 받으면 기본 설정에서 그대로 한 번 더 나간다. 이 경로가 스스로 물러나는 조건은 하나뿐인데, 재시도 간격이 `responseTimeout`보다 길 때다.

```java
final Timeout responseTimeout = requestConfig.getResponseTimeout();
if (responseTimeout != null && defaultRetryInterval.compareTo(responseTimeout) > 0) {
    return false;
}
```

비멱등 요청에 재시도가 붙는 게 곤란하면 `disableAutomaticRetries()`로 끄거나, `retryRequest(HttpResponse, ...)`를 오버라이드해 멱등 메서드만 통과시키는 전략을 넣는다.

## 참고 자료

---

> 타임아웃 병합·소비 흐름은 아래 소스에서 직접 확인했다.

- [HttpComponentsClientHttpRequestFactory.java (github.com/spring-projects/spring-framework)](https://github.com/spring-projects/spring-framework/blob/6.2.x/spring-web/src/main/java/org/springframework/http/client/HttpComponentsClientHttpRequestFactory.java)
- [InternalExecRuntime.java (github.com/apache/httpcomponents-client)](https://github.com/apache/httpcomponents-client/blob/master/httpclient5/src/main/java/org/apache/hc/client5/http/impl/classic/InternalExecRuntime.java)
- [PoolingHttpClientConnectionManager.java (github.com/apache/httpcomponents-client)](https://github.com/apache/httpcomponents-client/blob/master/httpclient5/src/main/java/org/apache/hc/client5/http/impl/io/PoolingHttpClientConnectionManager.java)
- [DefaultHttpClientConnectionOperator.java (github.com/apache/httpcomponents-client, rel/v5.5.1 — handshake 처리가 여기로 옮겨온 버전)](https://github.com/apache/httpcomponents-client/blob/rel/v5.5.1/httpclient5/src/main/java/org/apache/hc/client5/http/impl/io/DefaultHttpClientConnectionOperator.java)
- [AbstractClientTlsStrategy.java (github.com/apache/httpcomponents-client, rel/v5.5 — 5.5 이하 handshake 동작)](https://github.com/apache/httpcomponents-client/blob/rel/v5.5/httpclient5/src/main/java/org/apache/hc/client5/http/ssl/AbstractClientTlsStrategy.java)
- [DefaultHttpRequestRetryStrategy.java (github.com/apache/httpcomponents-client)](https://github.com/apache/httpcomponents-client/blob/master/httpclient5/src/main/java/org/apache/hc/client5/http/impl/DefaultHttpRequestRetryStrategy.java)
- [HttpClient 5 공식 문서 (hc.apache.org)](https://hc.apache.org/httpcomponents-client-5.5.x/)
- [RestTemplate javadoc (docs.spring.io)](https://docs.spring.io/spring-framework/docs/current/javadoc-api/org/springframework/web/client/RestTemplate.html)
- [RestClient javadoc (docs.spring.io)](https://docs.spring.io/spring-framework/docs/current/javadoc-api/org/springframework/web/client/RestClient.html)
