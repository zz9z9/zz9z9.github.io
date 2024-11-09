---
title: javax.net.ssl.SSLHandshakeException - No appropriate protocol (protocol is disabled or cipher suites are inappropriate)의 원인을 찾아서
date: 2023-09-05 10:25:00 +0900
categories: [경험하기, 이슈 노트]
tags: [MySQL, SSL/TLS]
---

## 상황
> 신규 이전한 서버에서 애플리케이션을 띄우는데 다음과 같은 에러를 마주하게됐다. 이전 서버에서와 달라진 점은 CentOS 7.4에서 7.9로 바뀐 것밖에 없는데 뭐가 문제일까 이해가 잘되지 않았다.
> 또한 로컬 환경에서는 문제없이 실행되는 상황이라 추적이 더 어려웠다.

```
Caused by: javax.net.ssl.SSLHandshakeException: No appropriate protocol (protocol is disabled or cipher suites are inappropriate)
	at sun.security.ssl.HandshakeContext.<init>(HandshakeContext.java:171)
	at sun.security.ssl.ClientHandshakeContext.<init>(ClientHandshakeContext.java:103)
	at sun.security.ssl.TransportContext.kickstart(TransportContext.java:220)
	at sun.security.ssl.SSLSocketImpl.startHandshake(SSLSocketImpl.java:433)
	at com.mysql.jdbc.ExportControlled.transformSocketToSSLSocket(ExportControlled.java:186)
```

- 에러 로그를 봤을때 SSL 핸드셰이크하는 과정에서 적합한 프로토콜 또는 Cipher Suite가 없어서 발생한 에러로 보인다. 에러가 발생한 부분의 코드를 살펴보자
- `sun.security.ssl.HandshakeContext#HandshakeContext`
<img width="619" alt="image" src="https://github.com/zz9z9/zz9z9.github.io/assets/64415489/de3bffd0-ef51-49c6-b5df-65b5bfc0af0b">


- 결과적으로 `activeProtocols`가 빈 리스트라 발생한 에러임을 알 수 있다.
- 로컬 환경에서 디버거로 추적해보았을 때, `getActiveProtocols` 메서드의 첫 번째 파라미터인 `enabledProtocols`에 세팅된 프로토콜은 `TLS1.0`, `TLS1.1`이었다.
- 원인 파악을 위해서는 다음 두 가지 살펴봐야 할 것 같다.
1. `enabledProtocols`엔 어떻게 `TLS1.0`, `TLS1.1`이 세팅된 것일까
2. 왜 기존 서버와 로컬에서는 되고 신규 서버에서는 안될까 ?


>  그럼, 먼저 전반적인 호출 흐름을 살펴보자


## 호출 흐름 살펴보기
- 에러 로그 콜 스택에서도 볼 수 있듯이, 객체 호출 흐름은 다음과 같다.
```
com.mysql.jdbc.ExportControlled.transformSocketToSSLSocket
-> sun.security.ssl.SSLSocketImpl.startHandshake
-> sun.security.ssl.TransportContext.kickstart
-> sun.security.ssl.ClientHandshakeContext.<init>
-> sun.security.ssl.HandshakeContext.<init>
```

- 두 번째 단계인 `SSLSocketImpl`의 클래스를 보면 아래와 같이 `SSLContextImpl`, `TransportContext` 클래스를 인스턴스 변수로 선언하고 있고 `final`로 되어있는 것을 알 수 있다. 즉, `SSLSocketImpl`이 생성될 때, `SSLContextImpl`, `TransportContext` 객체도 반드시 함께 생성되는 것을 알 수 있다.
```java
public final class SSLSocketImpl
        extends BaseSSLSocketImpl implements SSLTransport {

    final SSLContextImpl sslContext;
    final TransportContext conContext;
 	...
}
```
- `TransportContext.kickstart` 이후의 흐름은 `ClientHandshakeContext` 객체를 생성하는 것인데, 맨 처음 `sun.security.ssl.HandshakeContext#HandshakeContext`을 다시 살펴보면 생성자 파라미터로 `SSLContextImpl`과 `TransportContext`가 필요한 것을 알 수 있다.
- 다시 거꾸로 정리하면, `ClientHandshakeContext`는 생성시 `HandshakeContext` 생성자를 호출하고,  `HandshakeContext`를 생성하기 위해서는 `SSLSocketImpl`의 `SSLContextImpl`과 `TransportContext`가 반드시 필요하다. 그리고, 이 두 객체는 `SSLSocketImpl`이 생성될 때 함께 세팅된다.
- **따라서, `ExportControlled.transformSocketToSSLSocket`에서 어떻게 `SSLSocketImpl`를 생성하는지, 그리고 여기에 세팅되는 `SSLContextImpl`과 `TransportContext`중 특히 (`getActiveProtocols`의 파라미터가 되는) `TransportContext`의 `SSLConfiguration`이 어떤지가 중요할 것 같다.**


> 이제 위 흐름을 생각하면서 원인 파악을 위한 두 가지 부분을 체크해보자.

## 1. `enabledProtocols`엔 어떻게 `TLS1.0`, `TLS1.1`이 세팅된 것일까 ?
- `ExportControlled.transformSocketToSSLSocket`에서는 `SocketFactory`를 통해 `SSLSocket`을 생성한다. (`mysqlIO.mysqlconnection = sslFact.connect`)
- 그리고 맨 아래 `((SSLSocket) mysqlIO.mysqlConnection).setEnabledProtocols(allowedProtocols.toArray(new String[0]))` 부분을 주목해서 보자.
- 에러가 발생한 애플리케이션의 DB 서버는 MySQL 5.7버전을 사용하고 있기 때문에, 따로 `enabledTLSProtocols` 옵션을 주지 않은 이상 `tryProtocols = new String[] { TLSv1_1, TLSv1 };` 이 부분을 탈 것이고, `configuredProtocols`에 이 두 개의 프로토콜이 세팅된다.
- 결과적으로, `if (jvmSupportedProtocols.contains(protocol) && configuredProtocols.contains(protocol))` 조건을 만족하는 프로토콜은 `TLS1.1`, `TLS1.0`밖에 없기때문에 `enabledTLSProtocols`에 두 개의 프로토콜이 세팅된다.

<img width="1631" alt="image" src="https://github.com/zz9z9/zz9z9.github.io/assets/64415489/8bcf4964-57a2-4396-841f-46921c9e0fdb">

## 2. 왜 로컬에서는 되고 서버에서는 안될까 ?

- `HandshakeContext`의 `getActiveProtocols` 메서드에서 `algorithmConstraints.permits` 부분을 자세히 살펴보았다.
<img width="864" alt="image" src="https://github.com/zz9z9/zz9z9.github.io/assets/64415489/a993748a-d75d-44f3-abb5-2c0f13efa7e9">

- `sun.security.ssl.SSLAlgorithmConstraints#permits`의 `tlsDisabledAlgConstraints.permits` 부분을 타는 것을 알 수 있었다.
<img width="800" alt="image" src="https://github.com/zz9z9/zz9z9.github.io/assets/64415489/8c0b8886-9fa2-45a2-ad9f-0742dd647510">

- `sun.security.util.DisabledAlgorithmConstraints#permits`
  - 요약하자면, `checkAlgorithm`에서 통과하지 못한 TLS 프로토콜은 available하지 않는 프로토콜이며, 이는 해당 프로토콜이 `disabledAlgorithms` 목록에 있는지로 판단한다.
```java
    @Override
    public final boolean permits(Set<CryptoPrimitive> primitives,
            String algorithm, AlgorithmParameters parameters) {
        if (!checkAlgorithm(disabledAlgorithms, algorithm, decomposer)) {
            return false;
        }

        if (parameters != null) {
            return algorithmConstraints.permits(algorithm, parameters);
        }

        return true;
    }
```

- `disabledAlgorithms`은 `DisabledAlgorithmConstraints`가 생성될때 세팅된다. `PROPERTY_TLS_DISABLED_ALGS`은 `"jdk.tls.disabledAlgorithms"`로 선언되어있다.
```java
final class SSLAlgorithmConstraints implements AlgorithmConstraints {

    private static final AlgorithmConstraints tlsDisabledAlgConstraints =
            new DisabledAlgorithmConstraints(PROPERTY_TLS_DISABLED_ALGS,
                    new SSLAlgorithmDecomposer());
```
```java
    public DisabledAlgorithmConstraints(String propertyName,
            AlgorithmDecomposer decomposer) {
        super(decomposer);
        disabledAlgorithms = getAlgorithms(propertyName); // propertyName = "jdk.tls.disabledAlgorithms"
```
- `getAlgorithms`은 `$JAVA_HOME/jre/lib/security/java.security` 파일에서 `propertyName`인 `jdk.tls.disabledAlgorithms`에 정의된 알고리즘(프토토콜) 목록을 가져온다.
- 로컬에서 확인해보니 해당 프로퍼티는 다음과 같이 선언되어 있었다. (`openjdk-1.8.0.242` 버전)
```
jdk.tls.disabledAlgorithms=SSLv3, RC4, DES, MD5withRSA, DH keySize < 1024, \
    EC keySize < 224, 3DES_EDE_CBC, anon, NULL
```

- **여기서 문득, 신규 서버의 자바 릴리즈 버전은 뭐지? 라는 생각이 들었고, 확인해보니 기존에 사용하던 `openjdk-1.8.0.242`이 아닌 `openjdk8u362-b09` 버전이 사용되고 있었다.**
- 해당 버전을 로컬에 설치해서 살펴본 결과, `jdk.tls.disabledAlgorithms` 프로퍼티는 다음과 같이 선언되어 있었다. (**`TLSv1, TLSv1.1`이 추가되어있다**)
```
jdk.tls.disabledAlgorithms=SSLv3, TLSv1, TLSv1.1, RC4, DES, MD5withRSA, \
    DH keySize < 1024, EC keySize < 224, 3DES_EDE_CBC, anon, NULL, \
    include jdk.disabled.namedCurves
```

- 이로써 기나긴 삽질의 시간을 끝낼 수 있게 되었다..!

## 정리
- MySQL 드라이버(mysql-connector-java 5.1.46 버전 기준)에서 `enabledTLSProtocols`과 같은 세팅이 별도로 정의되어있지 않으면, MySQL 5.7 서버와 SSL 핸드셰이크를 위한 프로토콜로 `TLS1.0`, `TLS.1.1`이 사용된다.
- 같은 자바 버전이더라도 릴리즈 버전에 따라 SSL 통신시 disable된 프로토콜이 다를 수 있다. 이로 인해, SSL 핸드셰이크가 제대로 이루어지지 않을 수 있다. <br>(이전과 달라진게 없는데 왜 문제가 생기지..? 라고 섣불리 생각하지 말자)


## 생각해본 조치 방안
- MySQL 버전 업그레이드
- `enabledTLSProtocols` 정의
  - `jdbc:mysql://{ip}:{port}/{dbName}?&enabledTLSProtocols={TLS_VERSION}`
  - 해당 MySQL 서버에서 지원하는 TLS 프로토콜이어야한다.
     - 지원하는 프로토콜 확인 방법 : `show variables like 'tls_%';`

- `useSSL=false` (해당 옵션을 주면 SSL 통신 자체를 하지 않는다.)
  - `jdbc:mysql://{ip}:{port}/{dbName}?&useSSL=false`
  - `com.mysql.jdbc.MysqlIO#doHandshake`
```java
        if (!this.connection.getUseSSL()) {
            ...
        } else {
            negotiateSSLConnection(user, password, database, packLength);
````
