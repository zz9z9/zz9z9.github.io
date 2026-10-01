## 상황

> 담당 서비스의 어드민(백오피스) 시스템 사용시 응답이 매우 느리거나 타임아웃 발생
> 모니터링 지표를 확인해보니 1번 서버(이하 A서버)에서 톰캣 스레드가 MAX까지 생성되어 있었음
> 발생일시 : 24/04/29 10시경 \~ 11시 30분(WAS 재기동)

### 모니터링 지표 확인

* CPU 사용률이 점점 오르더니 10시 6분 경 최고점을 찍고 내려옴
* CPU 사용률이 떨어진 이후엔 톰캣 Busy Thread Count (사용중인 스레드), Total Therad Count (전체 스레드 개수) 모두 지속적으로 증가함
* 힙 메모리 사용률 또한 점점 오르고, Major GC (Full GC)가 빈번하게 발생함
* 11:30분경 가맹점 1번 서버 어드민 WAS 내렸다 올리고나서 수치 정상화됨

![image](https://github.nhnent.com/storage/user/2746/files/82371c43-1434-4292-be1d-3db721038c70)

- Major GC (Full GC)가 빈번하게 발생
  ![image](https://github.nhnent.com/storage/user/2746/files/61ca0ae7-f4b1-49bb-8fbb-4e92497a596c)


## 원인 파악해보기

### CPU 사용률과 힙메모리 증가 ?

* 대상 기간이 매우 긴 엑셀 파일 생성 요청으로 인한 것으로 의심됨
  ![image](https://github.nhnent.com/storage/user/2746/files/cffaa631-b09c-4978-b8fb-e2d2e77eb8bd)

  * 09:01:34에 온 엑셀 다운로드 요청 (기간 : `2017.01.01 ~ 2024.04.29`)
  * 09:06:42에 온 엑셀 다운로드 요청 (기간 : `2016.01.01 ~ 2024.04.29`)
  * 09:51:42에 온 엑셀 다운로드 요청 (기간 : `2015.01.01 ~ 2022.12.31`)
* 즉, 힙 메모리 사용률이 계속 증가함에 따른 **Full GC로 인해 CPU 사용률이 올라갔고, Full GC 동안에는 사용자 요청을 처리하는 스레드가 동작하지 못하기 때문에**, 점점 응답 지연시간이 늘어났을 것으로 생각

### 스레드 개수 증가 ?
> 어떤 요청들이 스레드를 계속 점유하고 있었을까 ?

* 대부분 특정 화면에서 조회하는 API에 대한 대한 스레드임
  ![image](https://github.nhnent.com/storage/user/2746/files/8a5104a3-a329-4798-9376-858817f05f1e)

* 그렇다면, 해당 API를 처리할 때 어떤 부분에서 지연이 있었던걸까 ?
* 핀포인트로 확인결과 **특정 외부 api(이하 api/foo)를 호출하려는 과정에서 지연**이 있었음을 확인
* ![image](https://github.nhnent.com/storage/user/2746/files/e622397c-0395-4170-aa83-83d27fe49d31)
* ![image](https://github.nhnent.com/storage/user/2746/files/7a5fda2e-26f3-450d-83dc-f69774cf1ae0)

**그럼 외부 api 서버에 이슈가 있는걸까 ?**

* 외부 api 서버에서 A서버로부터 들어온 요청 로그 확인

> **10시 3분 43초 \~ WAS 재기동시(11시 30분경)까지 해당 어드민 서버로부터 지연 발생의 원인이된 요청이 들어오지 않음**

* 외부 api 1번 서버
  ![image](https://github.nhnent.com/storage/user/2746/files/8a9b03ef-8ad7-458d-8400-59f089b0af04)
* 외부 api 2번 서버
  ![image](https://github.nhnent.com/storage/user/2746/files/5ae9c209-af26-410b-8187-35debf45d353)

- 즉, 핀포인트에서 봤던 `api/foo` 호출시 지연은 요청 후 응답에 대한 지연이 아닌, 요청 자체를 보내지 못하고 있어서 발생한 지연임을 알 수 있음

### 10시 3분에 문제의 어드민 서버에 무슨 일이 일어난걸까 ?

* RestTemplate 통해 `api/foo` 호출하는 과정에서 OOME 발생.
* 즉, 대용량 엑셀 생성 요청으로 인해 힙 메모리가 많이 남지 않았기 때문에 api 요청을 처리하기 위해 메모리에 공간을 할당하는 과정(`509Factory.readFully`)에서 Full GC가 발생했는데도 힙 메모리를 충분히 확보하지 못함(`GC overhead limit exceeded`)

```
[2024/04/29 10:03:55.631][http-nio-9001-exec-16][ERROR][PaycoExceptionResolver]
Caused by: java.lang.OutOfMemoryError: GC overhead limit exceeded
at sun.security.provider.X509Factory.readFully(X509Factory.java:121) ~[na:1.8.0_242]
at sun.security.provider.X509Factory.readBERInternal(X509Factory.java:752) ~[na:1.8.0_242]
at sun.security.provider.X509Factory.readOneBlock(X509Factory.java:552) ~[na:1.8.0_242]
at sun.security.provider.X509Factory.engineGenerateCertificate(X509Factory.java:96) ~[na:1.8.0_242]

...

at org.apache.http.impl.execchain.ProtocolExec.execute(ProtocolExec.java:195) ~[httpclient-4.3.6.jar:4.3.6]
at org.apache.http.impl.execchain.RetryExec.execute(RetryExec.java:86) ~[httpclient-4.3.6.jar:4.3.6]
at org.apache.http.impl.execchain.RedirectExec.execute(RedirectExec.java:108) ~[httpclient-4.3.6.jar:4.3.6]
at org.apache.http.impl.client.InternalHttpClient.doExecute(InternalHttpClient.java:184) ~[httpclient-4.3.6.jar:4.3.6]
at org.apache.http.impl.client.CloseableHttpClient.execute(CloseableHttpClient.java:82) ~[httpclient-4.3.6.jar:4.3.6]
at org.apache.http.impl.client.CloseableHttpClient.execute(CloseableHttpClient.java:57) ~[httpclient-4.3.6.jar:4.3.6]
at org.springframework.http.client.HttpComponentsClientHttpRequest.executeInternal(HttpComponentsClientHttpRequest.java:89) ~[spring-web-4.3.30.RELEASE.jar:4.3.30.RELEASE]
at org.springframework.http.client.AbstractBufferingClientHttpRequest.executeInternal(AbstractBufferingClientHttpRequest.java:48) ~[spring-web-4.3.30.RELEASE.jar:4.3.30.RELEASE]
at org.springframework.http.client.AbstractClientHttpRequest.execute(AbstractClientHttpRequest.java:53) ~[spring-web-4.3.30.RELEASE.jar:4.3.30.RELEASE]
at org.springframework.web.client.RestTemplate.doExecute(RestTemplate.java:661) ~[spring-web-4.3.30.RELEASE.jar:4.3.30.RELEASE]
at org.springframework.web.client.RestTemplate.execute(RestTemplate.java:622) ~[spring-web-4.3.30.RELEASE.jar:4.3.30.RELEASE]
at org.springframework.web.client.RestTemplate.postForEntity(RestTemplate.java:416) ~[spring-web-4.3.30.RELEASE.jar:4.3.30.RELEASE]
at

...
```

* `api/foo` 호출시 사용하는 `RestTemplate`에 세팅되는 `PoolingHttpClientConnectionManager`의 maxConnection 수는 1
* **(직접 재현해보진 못해서 추측해보면) `api/foo` 호출 도중 OOME 발생으로 인해 `PoolingHttpClientConnectionManager`에서 관리하는 하나의 http 커넥션이 제대로 release되지 못했고, 이로 인해 다음 요청을 처리할 http connection이 없어서, 커넥션을 얻어오는 과정에서 무한히 대기가 발생**

## 결론

* 대상 기간이 매우 긴 엑셀 파일 생성 요청 n개로 인해 힙 메모리 사용량이 비정상적으로 증가했다.
* 이로 인해, Full GC가 빈번하게 발생했고 소요 시간도 오래걸렸다.
* 하필`api/foo`를 호출하는 과정에서 OOME를 만났다. `api/foo`를 호출하는 RestTemplate에 세팅된 `PoolingHttpClientConnectionManager`의 http connection은 한 개이다.
* (추측) OOME 발생으로 인해 `PoolingHttpClientConnectionManager`에 connection이 제대로 회수되지 못했다.
* (추측) 이로 인해 이후의 `api/foo`를 호출하는 코드가 포함된 로직에서는 사용할 HTTP connection이 없어서 요청이 처리되지 못하고 hang 상태에 걸려있었다.
* (추측) 이로 인해, 톰캣 스레드가 release되지 못해 사용할 스레드가 부족해져서 계속 스레드가 증가했다.

## 재발 방지 및 개선을 위해 생각해볼 부분

- PoolingHttpClientConnectionManager에 커넥션 얻어오는데 최대 제한 시간 세팅
  =>
```java
RequestConfig config = RequestConfig.custom()
				.setSocketTimeout(readTimeOut)
				.setStaleConnectionCheckEnabled(true)
				.setConnectionRequestTimeout(2000) // 이 부분
				.build();
```

=>
```
org.springframework.web.client.ResourceAccessException: I/O error on GET request for "http://local-partner-bo.payco.com:10003/temp/foo": Timeout waiting for connection from pool; nested exception is org.apache.http.conn.ConnectionPoolTimeoutException: Timeout waiting for connection from pool


Caused by: org.apache.http.conn.ConnectionPoolTimeoutException: Timeout waiting for connection from pool
```

- MaxTotal, MaxPerRoute
  => https://hc.apache.org/httpcomponents-client-4.5.x/current/httpclient/apidocs/org/apache/http/impl/conn/PoolingHttpClientConnectionManager.html

* 대용량 엑셀 다운로드 제한 ?
* 엑셀 다운로드시 메모리를 효율적으로 사용할 수 있도록 ?
* `PoolingHttpClientConnectionManager`의 커넥션 개수 한 개가 적절한 것일지 ?
* OOM이 발생했는데 힙덤프가 제대로 생성되지 않음 -> 힙덤프 파일 생성되도록
* Parallel GC를 G1 GC로 변경 ?
* tomcat에서의 응답 지연으로 인해 nginx - tomcat 간 커넥션 끊긴후 nginx에서 에러 페이지 못찾아서 404로 응답 내려주는 부분
* 기타 등등..


## 꼬리 질문
- GC와 CPU 사용률 관계 ?
- Full GC 동안에는 사용자 요청을 처리하는 스레드가 동작하지 못하기 때문에 ?
- RestTemplate 운영 전략 ?
- PoolingHttpClientConnectionManager
