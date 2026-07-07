---
title: HTTPS 요청이 HTTP로 리다이렉트 되는 현상 2
date: 2026-07-07 22:25:00 +0900
categories: [경험하기, 이슈 노트]
tags: [HTTP]
---

## 상황
- 약 3년 전 [HTTPS 요청이 HTTP로 리다이렉트 되는 현상](https://zz9z9.github.io/posts/https-to-http-redirect/)을 겪었었다.
- 이때는 해결방법 2 (RequestHeader set X-Forwarded-Proto "https") ForwardedHeaderFilter
- 이전 서버 구성 `(브라우저) ---- https ---- (Load Balancer 1 : DSR 방식) ---- https ---- (웹서버) ---- http ---- (Load Balancer 2 : DSR 방식) ---- http ---- (WAS)`
  - 이전 포스팅에서 LB를 L4/L7 스위치라고 했었는데, 틀렸음. L7은 지원 안함
- 현재 서버 구성 `(브라우저) ---- https ---- (Load Balancer 1 : Proxy 모드) ---- http ---- (웹서버) ---- http ---- (Load Balancer 2 : Proxy 모드) ---- http ---- (WAS)`
  - L4/L7 스위치

- 현재 서버 구성에서는 웹 서버(Nginx)에서 X-Forwarded-Proto를 https로 세팅해도 http로 + 443이 아닌 애플리케이션 포트로 리다이렉트 돼서 페이지가 뜨지 않는 현상이 발생

## 원인 파악하기
> AS-IS LB (DSR) : https://docs.nhncloud.com/ko/Network/Load%20Balancer(DSR)/ko/overview
> TO-BE LB (Proxy) : https://docs.nhncloud.com/ko/Network/Load%20Balancer/ko/overview/

- 현재 LB는 SSL 통신이 필요한 구간에서는 인증서 관리 공수를 인프라팀에 맡기기 위해 `TERMINATED_HTTPS` 방식을 사용한다.
- 즉, 위에 언급한 현재 서버 구성에서 사용자와 맞닿아 있는(실제로 직접은 아니지만) LB1은 TERMINATED_HTTPS를, LB2는 WAS(애플리케이션) 포트로 직접 HTTP 통신을 한다.
- 이때 Proxy LB 문서에 있는 다음 문구
  - X-Forwarded-Proto:
    - 클라이언트가 사용한 프로토콜(http 또는 https)을 백엔드 서버에 전달합니다.
    - HTTP 리스너의 경우 http, TERMINATED_HTTPS 리스너의 경우 https 값이 설정됩니다.
  - X-Forwarded-Port: 클라이언트가 연결한 포트 번호를 백엔드 서버에 전달합니다.
- LB2 입장에서 클라이언트는 앞단의 웹서버(Nginx)가 되고, Nginx에서 LB2의 HTTP 리스너로 요청을 보내기 때문에
  - 클라이언트(Nginx)가 사용한 프로토콜 = HTTP, 백엔드 서버(WAS)에 전달되는 X-Forwarded-Proto = HTTP
  - 따라서, Nginx에서 X-Forwarded-Proto에 HTTPS를 세팅하더라도 LB에서 다시 세팅됨
- 또한, 클라이언트(Nginx)에서 LB2의 8080 포트 --> WAS의 8080 포트 이런식으로 맞춰놔서 X-Forwarded-Port를 Nginx에서 세팅한다고해도 LB2에서 8080으로 다시 세팅함

![NHN Cloud Proxy LB 문서의 X-Forwarded 헤더 설명 — 리스너 타입에 따라 X-Forwarded-Proto 값이 세팅되며, enable_x_forwarded_* 플래그로 on/off 할 수 있다](/assets/img/https-to-http-redirect-2-img1.png)

- 인프라팀에서 enable_x_forwarded_proto, enable_x_forwarded_port를 off로 세팅해서 테스트해보겠냐고 했지만 괜찮다고 말씀드렸다.
- 만약 off로 했을때, Nginx에서 넘어온 X-Forwarded-* 헤더의 값이 그대로 사용돼서 문제가 해결된다고 하더라도, 결국 HTTPS 리다이렉트가 의도한대로 동작하기 위해서는 다음과 같은 전제조건이 깔리는 것이라고 생각이 들었기 때문이다.
  - Nginx 설정
  - 로드밸런서 설정
- 이건 시간이 지날수록 코드에서는 보이지 않고, 문서나 구성원의 기억 속에서 남아있을 것이므로 유지보수하기 좋다고 생각하진 않았다.

## 조치

```java
@Slf4j
@Configuration
public class WebConfig implements WebMvcConfigurer {

  ...

    /**
     * 이 WAS(4430 커넥터)는 항상 HTTPS 종료 LB 뒤에 위치하므로, 외부 프로토콜/포트(https/443)를
     * 커넥터에 고정한다. getScheme()/isSecure()/getServerPort()/getRequestURL()이 모두 https·443으로
     * 동작하여, redirect 절대화 및 수동 URL 조립이 X-Forwarded 헤더·LB 설정에 의존하지 않고 올바르게 동작한다.
     */
    @Bean
    public WebServerFactoryCustomizer<TomcatServletWebServerFactory> httpsConnectorCustomizer() {
        return factory -> factory.addConnectorCustomizers(connector -> {
            connector.setScheme("https");
            connector.setSecure(true);
            connector.setProxyPort(443);
        });
    }
```

### relative redirect(useRelativeRedirects)로는 왜 안 되는가

Tomcat의 `useRelativeRedirects` 옵션도 있지만, 이걸로는 이 문제가 풀리지 않는다. 핵심은 리다이렉트 자체가 아니라 **URL을 앱이 직접 조립하는 부분**에 있기 때문이다.

`useRelativeRedirects`는 오직 `response.sendRedirect()`가 내보내는 `Location` 헤더를 상대경로로 쓸지만 결정한다. `request.getRequestURL()` / `getScheme()`이 반환하는 값은 전혀 건드리지 않는다.

그런데 실제 버그 지점은 로그인 인터셉터에서 로그인 페이지로 보낼 때, 로그인 후 돌아올 주소(`nextUrl`)를 절대 URL로 조립하는 부분이다.

```java
response.sendRedirect("/error/login?nextUrl=" +
    URLEncoder.encode(request.getRequestURL().toString() + ..., ...));
```

- 리다이렉트 대상(`/error/login`)은 이미 상대경로 → 이건 relative 옵션과 무관하게 문제없음
- 진짜 문제는 쿼리 파라미터 `nextUrl`을 `request.getRequestURL()`(scheme·host·port로 만든 절대 URL)로 조립한다는 것

`getScheme()`이 http를 반환하면 → `nextUrl=http://...`가 파라미터로 박힘 → 로그인 완료 후 이 `nextUrl`로 되돌려보낼 때 http로 다운그레이드된다. relative redirect를 켜도 `getRequestURL()`은 여전히 `http://...`를 뱉으므로 `nextUrl`은 그대로 http → 버그가 안 고쳐진다.

### 커넥터 레벨로 고친 이유

`connector.setScheme("https")`는 문제의 근원인 `getScheme()`/`getRequestURL()` 자체를 https로 고정한다. 그 결과 아래가 전부 해결된다.

| 케이스 | relative로 해결? | 커넥터 고정으로 해결? |
| --- | --- | --- |
| `sendRedirect("/error/…")` Location 헤더 | ⭕ | ⭕ |
| `nextUrl`에 박히는 `getRequestURL()` 절대 URL | ❌ | ⭕ |
| 로그인 후 외부 SSO 서버에서 복귀할 때 쓰는 절대 콜백 URL | ❌ (상대경로로 표현 불가) | ⭕ |

- relative redirect는 `sendRedirect`의 Location 헤더만 상대화 → 부분 처리
- 이 앱의 실제 원인은 `getRequestURL()` 기반 절대 URL 조립(`nextUrl`)이고, 외부 로그인 콜백은 절대 https URL이 필수라 상대경로로는 애초에 표현 불가
- 따라서 `getScheme()`/`getRequestURL()`의 소스를 https로 고정하는 커넥터 방식이 모든 경우를 커버

### 이 방식이 코드에 고정하는 전제

이 커넥터 설정은 **"이 커넥터로 들어오는 모든 요청의 원래 클라이언트 연결은 https·443이다"** 라는 전제를 코드에 고정한 것이다. 이 전제는 현재 토폴로지(모든 외부 트래픽이 TERMINATED_HTTPS LB의 443 리스너를 거쳐야만 이 커넥터에 도달)에 의해 보장된다.

즉, 인프라 설정(Nginx + LB)에 의존하는 방식을 거부한 대신 이쪽도 전제가 없는 건 아니다. 다만 그 전제가 문서나 기억이 아니라 **코드와 주석에 남는다**는 점이 다르다. 부수 효과로 LB를 거치지 않고 커넥터에 직접 닿는 요청(헬스체크, 내부 직접 호출 등)도 항상 https·443으로 인식된다는 점은 알고 있어야 한다.
