---
title: WEB - Content-Security-Policy(CSP) 살펴보기
date: 2025-03-15 22:25:00 +0900
categories: [지식 더하기, 이론]
tags: [WEB]
---

## Content-Security-Policy ?
> 콘텐츠 보안 정책(CSP)은 **특정 유형의 보안 위협의 위험을 방지하거나 최소화**하는 데 도움이 되는 기능으로 <br>
> 웹사이트에서 브라우저로 보내는 **일련의 지침으로 구성**되어 있으며, 브라우저에서 **코드가 수행할 수 있는 작업에 제한**을 두도록 지시

### CSP 전달 방식
- HTTP 응답 헤더
  - 메인 문서뿐만 아니라 모든 요청에 대한 응답에 적용되어야 한다.
- `<meta>` 태그의 `http-equiv` 속성으로 정의

### 정책
- 정책은 세미콜론으로 구분된 일련의 지시문(Fetch directives)으로 구성
- **각 지시문은 보안 정책의 다른 측면을 제어**

**예시**
> `Content-Security-Policy: default-src 'self'; img-src 'self' example.com`

- 지시문1 : `default-src 'self'`
  - 다른 리소스 유형에 대해 다른 정책을 설정하는 구체적인 지시어가 없는 한, 문서와 동일한 출처의 리소스만 로드하라고 브라우저에 지시
- 지시문2 : `img-src 'self' example.com`
  - 브라우저에 동일한 출처의 이미지나 `example.com`에서 제공된 이미지를 로드하라고 지시


## Fetch directives
> 리소스(JavaScript, CSS, 이미지 등)에 대한 허용된 범주(도메인, URL, 프로토콜, 또는 패턴 등)를 지정 <br>
> 예를 들어, `script-src`는 JavaScript 로드를 허용하는 범주를 설정 <br>
> 전체 지시어 목록은 [여기](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy#fetch_directives)에서 확인할 수 있다.

- default-src : 지시문이 명시적으로 나열되지 않은 모든 리소스에 대한 대체 정책을 설정

- 각 Fetch directives는 단일 키워드 `'none'` 또는 공백으로 구분된 하나 이상의 **출처 표현식(source expressions)**으로 지정
  - `none` : 해당 리소스 로드 자체를 차단
  - `self` : 문서 자체와 동일한 출처(origin)의 리소스만 허용
  - 두 개 이상의 출처 표현식이 나열된 경우 **하나라도 리소스를 허용하면 리소스가 허용됨**
    - 하지만, 예외적으로 `none`이 같이 있으면 다른 출처 표현식들은 무시됨

**예시**
> `Content-Security-Policy: default-src 'self'; img-src 'self' example.com`

- default-src는 단일 출처 표현식 self로 구성.
- img-src는 두 개의 출처 표현식 self와 example.com으로 구성

※ Fetch ?
- fetch는 일반적으로 영어에서 "가져오다" 또는 "불러오다"라는 의미
- fetch는 **브라우저가 외부 리소스를 요청하거나 가져오는 행위**
- 즉, Fetch directives란 웹 문서가 불러올 수 있는 리소스의 종류나 출처를 제한하는 지시어


## 출처 표현식 형식 살펴보기
> `<host-source>` 및 `<scheme-source>` 형식은 따옴표로 묶어서는 안되며, 다른 모든 형식은 작은 따옴표로 묶어야 한다.

### `<host-source>`
> 해당 리소스를 허용할 출처의 `URL` 또는 `호스트 IP 주소`

- 스키마(예: http, https), 포트 번호, 경로(path)는 생략할 수 있다.
  - origin = `<scheme> "://" <host> [ ":" <port> ]`
- **스키마를 생략하면, 문서의 출처(origin)에서 사용된 스키마가 자동으로 적용**된다.
  - 예를 들어, iframe에서 `Content-Security-Policy: frame-ancestors *.example.com`으로 설정했고 iframe의 url 스키마가 https라면 부모창도 반드시 https 여야한다.

- CSP(Content-Security-Policy)에서 스키마를 지정하면 원칙적으로는 정확한 일치가 요구되지만, 보안 단계가 더 높은 스키마로 업그레이드된 요청은 자동으로 허용된다.
  - `http://example.com`은 `https://example.com`의 리소스도 허용
  - `ws://example.com`은 `wss://example.org`의 리소스도 허용

- 와일드카드(*)는 서브도메인, 호스트 주소 및 포트 번호에서 사용할 수 있으며, 각 항목에서 가능한 모든 유효한 값이 허용됨을 의미한다.
  - `http://*.example.com`은 `example.com`의 모든 서브도메인으로부터 오는 리소스를 HTTP 또는 HTTPS로 허용

- 경로가 `/`로 끝나는 경우, 그 경로로 시작하는 모든 하위 경로를 매칭한다.
  - `example.com/api/`는 다음과 같은 경로 모두 허용:
    - `example.com/api/users`
    - `example.com/api/users/list`
    - `example.com/api/orders/123`

- 만약 경로가 `/`로 끝나지 않는다면, 정확히 그 경로 하나만 매칭한다.
  - `example.com/api` : `example.com/api`만 허용


### `<scheme-source>`
- `https:`와 같은 scheme을 사용할 수 있으며, 콜론(:)이 필수적이다
- 보안 업그레이드가 허용됨
  - http를 허용하면 https로 로드된 리소스도 허용
  - ws를 허용하면 wss로 로드된 리소스도 허용

## upgrade-insecure-requests 지시어
- 사이트는 때때로 주요 문서를 HTTPS를 통해 제공하지만 리소스는 HTTP를 통해 제공한다.
`<script src="http://example.org/my-cat.js"></script>`

- 이를 **mixed content**라고 하며, 안전하지 않은 리소스가 있으면 HTTPS에서 제공하는 보호가 크게 약화된다.
  - 브라우저가 구현하는 mixed content 알고리즘에 따라 문서가 HTTPS를 통해 제공되는 경우 안전하지 않은 리소스는 "업그레이드 가능한 콘텐츠"와 "차단 가능한 콘텐츠"로 분류된다.

- mixed content에 대한 궁극적인 해결책은 개발자가 모든 리소스를 HTTPS를 통해 로드하는 것입니다.
  - 그러나 사이트가 모든 콘텐츠를 HTTPS를 통해 제공할 수 있더라도 개발자가 리소스를 로드하는 데 사용하는 모든 URL을 다시 작성하는 것은 여전히 매우 어려움 (아카이브된 콘텐츠와 관련된 경우 사실상 불가능할 수도 있음).

- `upgrade-insecure-requests` 지시문은 이 문제를 해결하기 위해 사용된다.
  - `Content-Security-Policy: upgrade-insecure-requests`

- 이 지시문이 문서에 설정된 경우 브라우저는 다음과 같은 경우 모든 HTTP URL을 HTTPS로 자동 업그레이드한다.
  - 리소스(예: 이미지, 스크립트 등)를 로드하는 요청
  - 문서와 동일한 출처인 탐색 요청(예: 링크 대상)
  - 중첩된 브라우징 컨텍스트의 탐색 요청(예: iframe)
  - form 제출

- 하지만, 대상이 다른 출처인 최상위 탐색(top-level navigation) 요청은 업그레이드되지 않습니다.
  - Top-level navigation은 브라우저가 현재 페이지에서 다른 페이지로 직접 이동하는 요청을 의미
    - `<a href="...">` 링크를 클릭해서 다른 페이지로 이동하거나,
    - 주소창에 URL을 직접 입력해서 이동하거나,
    - 브라우저에서 페이지를 새로고침하거나 다른 웹사이트로 직접 이동하는 등

- 예를 들어, `https://example.org`의 문서가 `upgrade-insecure-requests` 지시어를 포함하는 CSP와 함께 제공되고 해당 문서에 다음과 같은 마크업이 포함되어 있다고 가정했을 때, 브라우저는 두 요청을 모두 자동으로 HTTPS로 업그레이드한다.
```html
<script src="http://example.org/my-cat.js"></script>
<script src="http://not-example.org/another-cat.js"></script>
```

- 하지만, 다음의 경우 브라우저는 첫 번째 링크는 HTTPS로 업그레이드하지만, 두 번째 링크는 다른 출처로 이동하기 때문에 업그레이드하지 않는다.
```html
<a href="http://example.org/more-cats">See some more cats!</a>
<a href="http://not-example.org/even-more-cats">More cats, on another site!</a>
```

## CSP로 악의적인 공격 막는 예시
**외부 스크립트 주입**
- 예시 : `<script src="https://evil.example.com/hacker.js"></script>`
- 방어 : `Content-Security-Policy: script-src 'self';`
  - 현재 도메인의 스크립트만 허용

**인라인 JavaScript 차단**
- 예시
```html
<script>
    console.log("You've been hacked!");
</script>
```
- 방어
  - `Content-Security-Policy: script-src 'self'`;
    - `<script>` 내부의 인라인 JavaScript 실행 차단 (`'unsafe-inline`' 키워드가 없으면 인라인 JavaScript 실행 차단됨)

**이벤트 핸들러 차단**
- 예시 :  `<img onmouseover="console.log(You've been hacked!)" />`
- 방어 : `Content-Security-Policy: script-src 'self';`
  - 위와 마찬가지로 `'unsafe-inline'`을 제거하면 `onmouseover`, `onclick` 같은 인라인 이벤트 핸들러 차단

## 참고 자료
- [https://developer.mozilla.org/en-US/docs/Web/HTTP/CSP](https://developer.mozilla.org/en-US/docs/Web/HTTP/CSP)
- [https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Security-Policy/frame-ancestors](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Security-Policy/frame-ancestors)
