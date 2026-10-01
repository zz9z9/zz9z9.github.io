---
title: java/spring 애플리케이션에서 외부 api 호출시 사용할 수 있는 객체 살펴보기
date: 2024-01-26 20:25:00 +0900
---

# 상황
// GET, POST 요청
// keep-alive
// connection-pooling
// Client -> Proxy -> Server
=> 프록시 관련 참고 :  https://11st-tech.github.io/2021/09/07/proxy-setting-guide/
// readTimeout, connectionTimeout
// 비동기 ??
// 에러 상황 400, 404, 500 등 ?
// 그 외 ?? --> 죽은 커넥션 처리등 ??

# java.net.HttpURLConnection
https://docs.oracle.com/javase/8/docs/api/java/net/HttpURLConnection.html
- Each HttpURLConnection instance is used to make a single request but the underlying network connection to the HTTP server may be transparently shared by other instances.
- Calling the close() methods on the InputStream or OutputStream of an HttpURLConnection after a request may free network resources associated with this instance but has no effect on any shared persistent connection.
- Calling the disconnect() method may close the underlying socket if a persistent connection is otherwise idle at that time.

- 각 HttpURLConnection 인스턴스는 단일 요청을 만드는 데 사용되지만 HTTP 서버에 대한 기본 네트워크 연결은 다른 인스턴스에서 투명하게 공유될 수 있습니다.
- 요청 후 HttpURLConnection의 InputStream 또는 OutputStream에서 close() 메서드를 호출하면 이 인스턴스와 연결된 네트워크 리소스를 해제할 수 있지만 공유 영구 연결에는 영향을 미치지 않습니다.
- 해당 시점에 영구 연결이 유휴 상태인 경우 Disconnect() 메서드를 호출하면 기본 소켓이 닫힐 수 있습니다.
- persistent connection ??

- Proxy


# Apache HttpComponents (HttpClient)
[공식문서](https://hc.apache.org/httpcomponents-client-5.3.x/index.html)
- Although the java.net package provides basic functionality for accessing resources via HTTP, it doesn't provide the full flexibility or functionality needed by many applications. HttpClient seeks to fill this void by providing an efficient, up-to-date, and feature-rich package implementing the client side of the most recent HTTP standards and recommendations.

- Features
  Standards based, pure Java, implementation of HTTP versions 1.0, 1.1, 2.0 (only async APIs)
  Supports encryption with HTTPS (HTTP over SSL) protocol.
  Pluggable socket factories and TLS strategies.
  Transparent message exchanges through HTTP/1.1 and HTTP/1.0 proxies.
  Tunneled HTTPS connections through HTTP/1.1 and HTTP/1.0 proxies, via the CONNECT method.
  Basic, Digest, Bearer authentication schemes.
  HTTP state management and cookie support.
  Flexible connection management and pooling.
  Support for HTTP response caching.
  Source code is freely available under the Apache License.

## PoolingHttpClientConnectionManager
> https://hc.apache.org/httpcomponents-client-5.2.x/current/httpclient5/apidocs/org/apache/hc/client5/http/impl/io/PoolingHttpClientConnectionManager.html


- `HttpClientConnectionManager`와 `ConnPoolControl`을 구현하고있다.

- ClientConnectionPoolManager maintains a pool of ManagedHttpClientConnections and is able to service connection requests from multiple execution threads.
- Connections are pooled on a per route basis. A request for a route which already the manager has persistent connections for available in the pool will be serviced by leasing a connection from the pool rather than creating a new connection.
- ClientConnectionPoolManager maintains a maximum limit of connection on a per route basis and in total. Connection limits, however, can be adjusted using ConnPoolControl methods.
- Total time to live (TTL) set at construction time defines maximum life span of persistent connections regardless of their expiration setting. No persistent connection will be re-used past its TTL value.


- `http.conn-manager.timeout`를 양수로 설정하여 커넥션 매니저가 커넥션 요청 작업에서 무기한 block되지 않도록 할 수 있다. 만약에 http.conn-manager.timeout 시간동안 커넥션이 풀에 반환되지 않으면 ConnectionPoolTimeoutException이 발생한다.
HTTP 스펙은 지속 커넥션이 얼마나 유지되어야 하는지에 대한 기간을 지정하지 않는다. 일부 HTTP 서버는 비표준 헤더인 Keep-Alive를 사용해서 클라이언트에게 커넥션을 얼마나 유지할 것인지를 알려준다. HttpClient는 가능한 이 정보를 사용한다. 만약에 Keep-Alive 헤더가 응답에 있지 않으면, HttpClient은 커넥션을 무기한으로 유지한다고 가정한다.
=> https://gunju-ko.github.io/http/httpclient/2019/01/23/Apache-HttpClient.html


```
22:25:50.830 [main] DEBUG org.apache.hc.client5.http.impl.classic.InternalHttpClient - ex-0000000001 preparing request execution
22:25:50.849 [main] DEBUG org.apache.hc.client5.http.impl.classic.ProtocolExec - ex-0000000001 target auth state: UNCHALLENGED
22:25:50.850 [main] DEBUG org.apache.hc.client5.http.impl.classic.ProtocolExec - ex-0000000001 proxy auth state: UNCHALLENGED
22:25:50.850 [main] DEBUG org.apache.hc.client5.http.impl.classic.ConnectExec - ex-0000000001 acquiring connection with route {}->http://localhost:8080
22:25:50.851 [main] DEBUG org.apache.hc.client5.http.impl.classic.InternalHttpClient - ex-0000000001 acquiring endpoint (3 MINUTES)
22:25:50.853 [main] DEBUG org.apache.hc.client5.http.impl.io.PoolingHttpClientConnectionManager - ex-0000000001 endpoint lease request (3 MINUTES) [route: {}->http://localhost:8080][total available: 0; route allocated: 0 of 5; total allocated: 0 of 25]
22:25:50.866 [main] DEBUG org.apache.hc.client5.http.impl.io.PoolingHttpClientConnectionManager - ex-0000000001 endpoint leased [route: {}->http://localhost:8080][total available: 0; route allocated: 1 of 5; total allocated: 1 of 25]
22:25:50.877 [main] DEBUG org.apache.hc.client5.http.impl.io.PoolingHttpClientConnectionManager - ex-0000000001 acquired ep-0000000001
22:25:50.877 [main] DEBUG org.apache.hc.client5.http.impl.classic.InternalHttpClient - ex-0000000001 acquired endpoint ep-0000000001
22:25:50.877 [main] DEBUG org.apache.hc.client5.http.impl.classic.ConnectExec - ex-0000000001 opening connection {}->http://localhost:8080
22:25:50.878 [main] DEBUG org.apache.hc.client5.http.impl.classic.InternalHttpClient - ep-0000000001 connecting endpoint (null)
22:25:50.880 [main] DEBUG org.apache.hc.client5.http.impl.io.PoolingHttpClientConnectionManager - ep-0000000001 connecting endpoint to http://localhost:8080 (3 MINUTES)
22:25:50.880 [main] DEBUG org.apache.hc.client5.http.impl.io.DefaultHttpClientConnectionOperator - localhost resolving remote address
22:25:50.884 [main] DEBUG org.apache.hc.client5.http.impl.io.DefaultHttpClientConnectionOperator - localhost resolved to [localhost/127.0.0.1, localhost/0:0:0:0:0:0:0:1]
22:25:50.886 [main] DEBUG org.apache.hc.client5.http.impl.io.DefaultHttpClientConnectionOperator - localhost:8080 connecting null->localhost/127.0.0.1:8080 (3 MINUTES)
22:25:50.887 [main] DEBUG org.apache.hc.client5.http.impl.io.DefaultManagedHttpClientConnection - http-outgoing-0 set socket timeout to 3 MINUTES
22:25:50.887 [main] DEBUG org.apache.hc.client5.http.impl.io.DefaultHttpClientConnectionOperator - localhost:8080 connected null->localhost/127.0.0.1:8080 as http-outgoing-0
22:25:50.887 [main] DEBUG org.apache.hc.client5.http.impl.io.PoolingHttpClientConnectionManager - ep-0000000001 connected http-outgoing-0
22:25:50.887 [main] DEBUG org.apache.hc.client5.http.impl.classic.InternalHttpClient - ep-0000000001 endpoint connected
22:25:50.887 [main] DEBUG org.apache.hc.client5.http.impl.classic.MainClientExec - ex-0000000001 executing POST /mock/post HTTP/1.1
22:25:50.888 [main] DEBUG org.apache.hc.client5.http.protocol.RequestAddCookies - ex-0000000001 Cookie spec selected: strict
22:25:50.897 [main] DEBUG org.apache.hc.client5.http.impl.classic.InternalHttpClient - ep-0000000001 start execution ex-0000000001
22:25:50.898 [main] DEBUG org.apache.hc.client5.http.impl.io.PoolingHttpClientConnectionManager - ep-0000000001 executing exchange ex-0000000001 over http-outgoing-0
22:25:50.899 [main] DEBUG org.apache.hc.client5.http.headers - http-outgoing-0 >> POST /mock/post HTTP/1.1
22:25:50.899 [main] DEBUG org.apache.hc.client5.http.headers - http-outgoing-0 >> Content-Type: application/json
22:25:50.899 [main] DEBUG org.apache.hc.client5.http.headers - http-outgoing-0 >> Accept: application/json
22:25:50.899 [main] DEBUG org.apache.hc.client5.http.headers - http-outgoing-0 >> Accept-Encoding: gzip, x-gzip, deflate
22:25:50.899 [main] DEBUG org.apache.hc.client5.http.headers - http-outgoing-0 >> Content-Length: 32
22:25:50.899 [main] DEBUG org.apache.hc.client5.http.headers - http-outgoing-0 >> Host: localhost:8080
22:25:50.899 [main] DEBUG org.apache.hc.client5.http.headers - http-outgoing-0 >> Connection: keep-alive
22:25:50.899 [main] DEBUG org.apache.hc.client5.http.headers - http-outgoing-0 >> User-Agent: Apache-HttpClient/5.3.1 (Java/11.0.10)
22:25:50.900 [main] DEBUG org.apache.hc.client5.http.wire - http-outgoing-0 >> "POST /mock/post HTTP/1.1[\r][\n]"
22:25:50.900 [main] DEBUG org.apache.hc.client5.http.wire - http-outgoing-0 >> "Content-Type: application/json[\r][\n]"
22:25:50.900 [main] DEBUG org.apache.hc.client5.http.wire - http-outgoing-0 >> "Accept: application/json[\r][\n]"
22:25:50.900 [main] DEBUG org.apache.hc.client5.http.wire - http-outgoing-0 >> "Accept-Encoding: gzip, x-gzip, deflate[\r][\n]"
22:25:50.900 [main] DEBUG org.apache.hc.client5.http.wire - http-outgoing-0 >> "Content-Length: 32[\r][\n]"
22:25:50.900 [main] DEBUG org.apache.hc.client5.http.wire - http-outgoing-0 >> "Host: localhost:8080[\r][\n]"
22:25:50.900 [main] DEBUG org.apache.hc.client5.http.wire - http-outgoing-0 >> "Connection: keep-alive[\r][\n]"
22:25:50.900 [main] DEBUG org.apache.hc.client5.http.wire - http-outgoing-0 >> "User-Agent: Apache-HttpClient/5.3.1 (Java/11.0.10)[\r][\n]"
22:25:50.900 [main] DEBUG org.apache.hc.client5.http.wire - http-outgoing-0 >> "[\r][\n]"
22:25:50.900 [main] DEBUG org.apache.hc.client5.http.wire - http-outgoing-0 >> "{"name": "lee", "city": "seoul"}"
22:25:52.562 [main] DEBUG org.apache.hc.client5.http.wire - http-outgoing-0 << "HTTP/1.1 200 [\r][\n]"
22:25:52.563 [main] DEBUG org.apache.hc.client5.http.wire - http-outgoing-0 << "Content-Type: application/json[\r][\n]"
22:25:52.563 [main] DEBUG org.apache.hc.client5.http.wire - http-outgoing-0 << "Transfer-Encoding: chunked[\r][\n]"
22:25:52.563 [main] DEBUG org.apache.hc.client5.http.wire - http-outgoing-0 << "Date: Mon, 13 May 2024 13:25:52 GMT[\r][\n]"
22:25:52.563 [main] DEBUG org.apache.hc.client5.http.wire - http-outgoing-0 << "Keep-Alive: timeout=60[\r][\n]"
22:25:52.563 [main] DEBUG org.apache.hc.client5.http.wire - http-outgoing-0 << "Connection: keep-alive[\r][\n]"
22:25:52.563 [main] DEBUG org.apache.hc.client5.http.wire - http-outgoing-0 << "[\r][\n]"
22:25:52.563 [main] DEBUG org.apache.hc.client5.http.wire - http-outgoing-0 << "1c[\r][\n]"
22:25:52.563 [main] DEBUG org.apache.hc.client5.http.wire - http-outgoing-0 << "{"resultMessage":"success!"}[\r][\n]"
22:25:52.564 [main] DEBUG org.apache.hc.client5.http.headers - http-outgoing-0 << HTTP/1.1 200
22:25:52.565 [main] DEBUG org.apache.hc.client5.http.headers - http-outgoing-0 << Content-Type: application/json
22:25:52.565 [main] DEBUG org.apache.hc.client5.http.headers - http-outgoing-0 << Transfer-Encoding: chunked
22:25:52.565 [main] DEBUG org.apache.hc.client5.http.headers - http-outgoing-0 << Date: Mon, 13 May 2024 13:25:52 GMT
22:25:52.565 [main] DEBUG org.apache.hc.client5.http.headers - http-outgoing-0 << Keep-Alive: timeout=60
22:25:52.565 [main] DEBUG org.apache.hc.client5.http.headers - http-outgoing-0 << Connection: keep-alive
22:25:52.568 [main] DEBUG org.apache.hc.client5.http.impl.classic.MainClientExec - ex-0000000001 connection can be kept alive for 60 SECONDS
22:25:52.570 [main] DEBUG org.apache.hc.client5.http.wire - http-outgoing-0 << "0[\r][\n]"
22:25:52.570 [main] DEBUG org.apache.hc.client5.http.wire - http-outgoing-0 << "[\r][\n]"
22:25:52.571 [main] DEBUG org.apache.hc.client5.http.impl.classic.InternalHttpClient - ep-0000000001 releasing valid endpoint
22:25:52.571 [main] DEBUG org.apache.hc.client5.http.impl.io.PoolingHttpClientConnectionManager - ep-0000000001 releasing endpoint
22:25:52.571 [main] DEBUG org.apache.hc.client5.http.impl.io.PoolingHttpClientConnectionManager - ep-0000000001 connection http-outgoing-0 can be kept alive for 60 SECONDS
22:25:52.571 [main] DEBUG org.apache.hc.client5.http.impl.io.PoolingHttpClientConnectionManager - ep-0000000001 connection released [route: {}->http://localhost:8080][total available: 1; route allocated: 1 of 5; total allocated: 1 of 25]
response :: {"resultMessage":"success!"}
```

# RestTemplate

- ClientHttpRequestFactory
- HttpComponentsClientHttpRequestFactory
- SimpleClientHttpRequestFactory (default) => HttpURLConnection 사용

- [공식 문서](https://docs.spring.io/spring-framework/docs/current/javadoc-api/org/springframework/web/client/RestTemplate.html)

- Synchronous client to perform HTTP requests, exposing a simple, template method API over underlying HTTP client libraries such as the JDK `HttpURLConnection`, Apache `HttpComponents`, and others.
- RestTemplate offers templates for common scenarios by HTTP method, in addition to the generalized `exchange` and `execute` methods that support less frequent cases.

- `RestTemplate` is typically used as a shared component. However, its configuration does not support concurrent modification, and as such its configuration is typically prepared on startup.
- **If necessary, you can create multiple, differently configured RestTemplate instances on startup.**
- Such instances may use the same underlying `ClientHttpRequestFactory` if they need to share HTTP client resources.

```java
ResponseEntity<PaycoIdApiResponse<PaycoIdMemberProfile>> response = restTemplate.exchange(
                paycoIdNewApiProperties.paycoMemberInfoUrl(),
                HttpMethod.POST,
                new HttpEntity<>(getMemberProfileByIdNoRequest, getDefaultHeaders()),
                new ParameterizedTypeReference<PaycoIdApiResponse<PaycoIdMemberProfile>>() {}
        );
```

- 참고 : Deprecation of RestTemplate
  - Despite its usefulness, RestTemplate was deprecated in Spring 5 in favor of `WebClient`, a non-blocking, reactive web client introduced in Spring WebFlux.

## ParameterizedTypeReference
> https://docs.spring.io/spring-framework/docs/current/javadoc-api/org/springframework/core/ParameterizedTypeReference.html

- The purpose of this class is to enable capturing and passing a generic Type.
- In order to capture the generic type and retain it at runtime, you need to create a subclass (ideally as anonymous inline class) as follows:
```java
ParameterizedTypeReference<List<String>> typeRef = new ParameterizedTypeReference<List<String>>() {};
```

- 특정 팀, 외부 업체 등에서 제공하는 api의 형태가 아래와 같이 `header`, `result`로 구성되어 있다고하자.
```json
{
  "header" : {
    "code" : 1000,
    "message" : "success",
    "successful" : true
  },

  "content" : {
    // 응답 데이터
  }
}
```

- `HelloCompanyProductInfoApiResponse`, `HelloCompanyOrderInfoApiResponse` 이런식으로 api별 응답을 각각 정의해줘야한다.
```java
public class RestTemplateClient {

  public HelloCompanyProductInfoApiResponse productInfoApiResponse() {
    String fooResourceUrl = "http://localhost:8080/hello/company/products";
    return getResponse(fooResourceUrl, HelloCompanyProductInfoApiResponse.class);
  }

  public HelloCompanyOrderInfoApiResponse orderInfoApiResponse() {
    String fooResourceUrl = "http://localhost:8080/hello/company/orders";
    return getResponse(fooResourceUrl, HelloCompanyOrderInfoApiResponse.class);
  }

  private <T> T getResponse(String requestUrl, Class<T> clazz) {
    RestTemplate restTemplate = new RestTemplate();
    ResponseEntity<T> resp = restTemplate.getForEntity(requestUrl, clazz);
    return resp.getBody();
  }

}
```

```java
public class HelloCompanyOrderInfoApiResponse {

  private HelloCompanyApiHeader header;
  private HelloCompanyOrder content;

  // 생성자, Getter 등 ...
}


public class HelloCompanyProductInfoApiResponse {

  private HelloCompanyApiHeader header;
  private HelloCompanyProduct content;

  // 생성자, Getter 등 ...
}
```

# Java11 HttpClient

# WebClient

# RestClient
- As of 6.1 (Spring)
- https://docs.spring.io/spring-framework/docs/current/javadoc-api/org/springframework/web/client/RestClient.html


## 참고 자료
- https://springframework.guru/using-resttemplate-with-apaches-httpclient/
