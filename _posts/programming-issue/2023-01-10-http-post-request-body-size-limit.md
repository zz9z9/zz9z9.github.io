---
title: POST 요청 사이즈 제한으로 인해 겪었던 이슈(http-max-post-size, max-http-form-post-size)
date: 2023-01-10 10:25:00 +0900
categories: [개발 일기]
tags: [Tomcat, HTTP]
---

## 상황
- 운영하고 있는 웹 서비스에서 상품 발송을 위해 수신자 정보를 저장하는 과정에서 수신자가 일정 수를 넘어가면 제대로 처리되지 않고 애플리케이션에서 예외 발생함

<br>

## 로그 추적
### 1. 아파치 로그
```
Connection reset by peer : ... AH01084: pass request body failed to ...
```

### 2. 애플리케이션 로그
- 컨트롤러에 파라미터가 null로 넘어옴. 이로 인해 유효성 검사에서 예외 처리됨


### 얻은 힌트
- Connection reset by peer (Remote Sever, 즉 톰캣 서버에서 RST 패킷 보내서 커넥션 끊김)
- pass request body failed
  - request body가 제대로 전달되지 못했다. (이로 인해 파라미터가 `null`로 넘어온 것 같다.)
- **추측 : 톰캣쪽에서 뭔가 문제가 발생하는 것 같다.**

<br>

## 원인 파악
> (Spring Boot 내장) 톰캣 관련 설정을 살펴보자

```yml
server:
  port: 포트번호
  tomcat:
    uri-encoding: UTF-8
    connection-timeout: ...
    min-spare-threads: ...
    max-threads: ...
    max-http-post-size: 3145728
    max-connections: ...
```

> 왠지 `max-http-post-size`가 연관있는 설정일 것 같다. 그런데, **post size라는게 정확히 어떤 것의 크기를 의미하는걸까 ? (request header를 포함한 전체 사이즈?)**

- [톰캣 공식문서](https://tomcat.apache.org/tomcat-9.0-doc/config/http.html)에서는 `maxPostSize` 속성을 다음과 같이 정의
```
The maximum size in bytes of the POST which will be handled by the container FORM URL parameter parsing.
The limit can be disabled by setting this attribute to a value less than zero.
If not specified, this attribute is set to 2097152 (2 megabytes).
Note that the FailedRequestFilter can be used to reject requests that exceed this limit.
```

- 소스를 찾아보면 `Content-Length`(Request Body의 크기)라는 것을 알 수 있다.
  - 내장 톰캣 라이브러리(`tomcat-embed-core-8.5.29.jar`)의 `org.apache.catalina.connector.Request#parseParameters`
![KakaoTalk_Photo_2023-08-15-00-23-57 001](https://github.com/zz9z9/zz9z9.github.io/assets/64415489/699f126f-5347-4386-8c8d-73317f0ea553)

- 또한, `Content-Type`이 `multipart/form-data`이거나 `application/x-www-form-urlencoded`인 경우에만 사이즈를 제한하는 로직을 타게된다.
  - 확인 결과, 수신자 정보 세팅 요청의 `Content-Type`은 `application/x-www-form-urlencoded`이었음
![KakaoTalk_Photo_2023-08-15-00-23-57 003](https://github.com/zz9z9/zz9z9.github.io/assets/64415489/faf54139-df7f-4d64-8df5-831cbedb9832)

- (이름에서 유추할 수 있듯이) `POST` 요청인 경우에만 제한된다.
  - `org.springframework.web.filter.HiddenHttpMethodFilter#doFilterInternal`
  ![KakaoTalk_Photo_2023-08-15-00-23-57 002](https://github.com/zz9z9/zz9z9.github.io/assets/64415489/43f1e6bd-850c-4d42-a6c4-d34d6a310123)


cf) 내장 톰캣 아닌 경우 (`server.xml`에 `maxPostSize`지정)
```xml
<Connector port="8080" protocol="HTTP/1.1" redirectPort="8443" maxPostSize="-1"/>
```

<br>

## 문제 해결
### 1. 수신자 정보 데이터 송신 구조 변경
> 불필요하게 중복되는 데이터 제거하여 RequestBody 크기 작게 만들기 (아래에서는 설명을 위해 json으로 표시. 실제로는 `x-www-form-urlencoded`, 즉 key-value 형태로 넘어감)

- before : 동일한 발신메세지 중복 (상품 발송시 발신메세지는 모두 동일)
```
{
    "상품코드" : ... ,
    "송신자이름" : ... ,
    "수신자목록" : [
    	    {"예약일시" : ... , "휴대폰번호" : ... , "발신메세지" : ...},
            {"예약일시" : ... , "휴대폰번호" : ... , "발신메세지" : ...},
        ]
}
```

- after : 발신메세지 항목 따로 분리
```
{
    "상품코드" : ... ,
    "송신자이름" : ... ,
    "발신메세지" : ... ,
    "수신자목록" : [
    		{"예약일시" : ... , "휴대폰번호" : ... },
            {"예약일시" : ... , "휴대폰번호" : ... },
        ]
}
```

### 2. max-http-post-size 변경
- 개선된 송신 구조 기준으로 10000건 송신시 약 3.8MB인 것을 감안하여 4194304(bytes, 4MB)로 변경


## 알게된 것
- `form` 태그에 `enctype` 따로 지정하지 않으면, form submit시 default content-type은 `x-www-form-urlencoded`
  - enctype 목록
    - application/x-www-form-urlencoded
    - multipart/form-data
    - text/plain

- POST 요청이면서 `Content-Type`이 `x-www-form-urlencoded` 또는 `multipart/form-data`인 경우에만 `http-max-post-size` 옵션이 적용됨 (json은 해당되지 않음)

- spring-boot의 `max-http-post-size` 속성은 2.1.x 버전에서부터 Deprecated 되었음 (`max-http-form-post-size`로 변경)
  - [제기됐던 이슈](https://github.com/spring-projects/spring-boot/issues/18521)
    - html form 요청과 관련해서 적용되는건데 `http-max-post-size`는 의미가 명확하지 않다.
  - [2.0.x 버전 Document](https://docs.spring.io/spring-boot/docs/2.0.x/api/org/springframework/boot/autoconfigure/web/ServerProperties.Tomcat.html#getMaxHttpPostSize--)
  - [2.1.x 버전 Document](https://docs.spring.io/spring-boot/docs/2.1.x/api/org/springframework/boot/autoconfigure/web/ServerProperties.Tomcat.html#getMaxHttpPostSize--)

cf) 운영하는 서비스는 spring-boot `v2.0.3` 사용중이었음
