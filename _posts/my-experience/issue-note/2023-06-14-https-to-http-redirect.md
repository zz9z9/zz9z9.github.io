---
title: HTTPS 요청이 HTTP로 리다이렉트 되는 현상
date: 2023-06-14 22:25:00 +0900
categories: [경험하기, 이슈 노트]
tags: [HTTP]
---

## 상황
- 서버 이전 작업 후 담당 웹사이트에서 URL 리다이렉트시 페이지 응답이 없는 경우가 발생함
- 특정 사용자에게서는 이런 현상이 발생하지 않음
- 확인해보니 HTTPS 요청이 HTTP로 바껴서 리다이렉트됨

<img src = "/assets/img/https-to-http-img1.png" alt="">

## 원인 파악하기
- 요청이 WAS에 도달하기까지의 흐름
  - `(브라우저) ---- https ---- (L4/L7 스위치) ---- https ---- (웹서버) ---- http ---- (WAS)`
- 인터셉터에서 `HttpServletResponse.sendRedirect` 하는 부분을 타고 들어가다보면 헤더에 `Location`을 세팅하는 코드를 만날 수 있다.
  - `org.apache.catalina.connector.Response#sendRedirect`

<img src = "/assets/img/https-to-http-img2.png" alt="">

- else절에 `toAbsoulte` 메서드에서 요청 프로토콜은 `request.getScheme()` 을 통해 가져온다.
`org.apache.catalina.connector.Response#toAbsolute`
<img src = "/assets/img/https-to-http-img3.png" alt="">

**즉, WEB에서 WAS로 들어오는 요청은 `http`이므로 리다이렉트 url이 `http`로 만들어지게 되었던 것**

## 의문점
1. 이전 서버 구성에서는 이런 이슈 제보된 적이 없었음 <br>
**=> 이전 L4/L7 스위치에서 80 포트가 허용 되어있었음**

2. 특정 사용자는 접근이 됨<br>
**=> HSTS로 인해 HTTPS로 리다이렉트 되었음 (웹서버 설정 : `Strict-Transport-Security: max-age=31536000`)**
<img src = "/assets/img/https-to-http-img4.png" alt="">



**※ HSTS란 ?**
> [공식문서](https://developer.mozilla.org/ko/docs/Web/HTTP/Headers/Strict-Transport-Security) 참고

- HTTP Strict-Transport-Security 응답 헤더(종종 HSTS로 축약됨)는 사이트가 HTTPS를 통해서만 접근되어야 하며 향후 HTTP를 사용하여 사이트에 접근하려는 모든 시도는 자동으로 HTTPS로 변환되어야 함을 브라우저에 알립니다.
- HTTPS를 사용하여 사이트에 처음으로 접근하고 Strict-Transport-Security 헤더를 반환하면 브라우저가 이 정보를 기록하고, 이후에 HTTP를 사용하여 사이트를 로드하려고 시도할 때 자동으로 HTTPS를 대신 사용합니다.

## 조치
### 해결방법1 : 톰캣 `use-relative-redirects` 속성 사용

> [공식문서](https://docs.spring.io/spring-boot/appendix/application-properties/index.html#application-properties.server.server.tomcat.use-relative-redirects) 설명 <br>
> "sendRedirect 호출로 생성된 HTTP 1.1 이상의 Location 헤더가 상대 리디렉션을 사용할지 절대 리디렉션을 사용할지 여부 (기본값 : false)"

* `server.tomcat.use-relative-redirects=true`로 세팅하면 `response.sendRedirect("/상대경로")`로 호출시 리다이렉트 url이 상대경로로 지정됨 (요청 프로토콜 그대로 사용)
- 관련 코드 (위에서 살펴본 `org.apache.catalina.connector.Response#sendRedirect`의 if절)

<img src = "/assets/img/https-to-http-img5.png" alt="">

* 리다이렉트 url이 상대경로로 지정됐을때, https로 재요청하는 모습

<img src = "/assets/img/https-to-http-img6.png" alt="">
<img src = "/assets/img/https-to-http-img7.png" alt="">

### 해결방법2 : 톰캣에서 `X-Forwarded-Proto` 인식할 수 있도록 하기
* 웹 서버에서 톰캣으로 요청시 `X-Forwarded-Proto` 헤더에 `https`를 담아서 보낸다.
  * 관련 아파치 설정 :`RequestHeader set X-Forwarded-Proto "https"`

* 톰캣에서 리다이렉트 url 지정시 request에 담긴 `X-Forwarded-Proto` 활용하게 한다.
  * 이렇게 하려면 response.sendRedirect시 response 구현체가 org.springframework.web.filter 패키지의 `ForwardedHeaderFilter.ForwardedHeaderExtractingResponse`가 되도록 해야함
  * 이를 위해, 아래와 같이 필터를 빈으로 등록 (부트 2.1 버전부터는 직접등록하지 않고 톰캣에 관련 설정만 해주면 자동으로 세팅되는 것 같음 : [관련 글](https://stackoverflow.com/questions/59126518/how-to-cope-with-x-forwarded-headers-in-spring-boot-2-2-0-spring-web-mvc-behin) - 상품권몰은 2.0.3v 사용)


```java
@Configuration
public class XForwardedFilterConfig {

    @Bean
    public FilterRegistrationBean<ForwardedHeaderFilter> forwardedHeaderFilter() {
        FilterRegistrationBean<ForwardedHeaderFilter> registrationBean = new FilterRegistrationBean<>();
        registrationBean.setFilter(new ForwardedHeaderFilter());
        return registrationBean;
    }

}
```

* 리다이렉트 url이 `https`로 세팅됨
  <img src = "/assets/img/https-to-http-img8.png" alt="">


## 참고. HTTP 리다이렉트 관련 상태 코드

| | 301 | 302 | 303 | 307 | 308 |
|-| ----|-----|-----|-----|-----|
| Status | Moved Permanently | Found | See Other | Temporary Redirect | Permanent Redirect |
| 영구적 리다이렉션| O | X | X | X | O |
| 기존 요청 변경 | O (POST -> GET)| O (POST -> GET)| O (무조건 GET으로 변경)| X | X |

※ 영구적 리다이렉션에서는 기존 URL에 대한 모든 SEO 값과 링크 리소스가 새 URL로 이전.








