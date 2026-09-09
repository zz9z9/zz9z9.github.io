---
title: Vue 앱은 어떻게 화면에 그려지는가 - index.html, main.js, App.vue
date: 2026-09-09 23:00:00 +0900
categories: [지식 더하기, 이론]
tags: [Frontend, Vue]
---

SSR(JSP·Thymeleaf)만 다루다 Vue 프로젝트를 처음 열면 파일 세 개의 관계부터 막힌다. `index.html`은 거의 비어 있고, `main.js`는 다섯 줄이며, 화면에 보이는 내용은 `App.vue`에 있는데 브라우저는 `.vue` 확장자를 모른다.

검증 환경: Vue 3.5.42, Vite 8.2.2, vue-router 4.6.4, pinia 4.0.3. 프론트 개발 서버 `:5173`, API 서버(Spring Boot + H2) `:8081`.

> 큰 흐름:
> - Vite가 `.vue`를 JS로 번역해 브라우저에 주고
> - 브라우저가 그 JS를 실행하고
> - 그 안의 Vue 라이브러리 코드가 `document.createElement`를 호출해 화면을 만든다. 마법 없이 전부 JS다.

| | Java | Vue SFC |
| --- | --- | --- |
| 입력 | `.java` | `.vue` |
| 도구 | `javac` | Vite + `@vue/compiler-sfc` |
| 출력 | `.class` (바이트코드) | JS 텍스트 |
| 실행 주체 | JVM | 브라우저 JS 엔진 |
| 시점 | 배포 전 1회 | dev: 요청 시마다 / build: 1회 |

## 서버가 실제로 내려주는 HTML

---

> 개발 서버에 `/`를 요청하면 돌아오는 응답은 아래가 전부다.

```bash
$ curl -s localhost:5173/
```

```html
<!doctype html>
<html lang="ko">
  <head>
    <script type="module" src="/@vite/client"></script>
    <meta charset="UTF-8" />
    <title>Vue in Action - 사용자 관리</title>
  </head>
  <body>
    <div id="app"></div>
    <script type="module" src="/src/main.js"></script>
  </body>
</html>
```

사용자 목록 테이블도, 입력 폼도 없다. JSP였다면 서버가 반복문으로 `<tr>`을 찍어 내려줬을 자리가 `<div id="app"></div>` 하나로 비어 있다.

`/stats` 경로로 요청해도 응답은 바이트 단위로 동일하다.

```bash
$ diff <(curl -s localhost:5173/) <(curl -s localhost:5173/stats)
# 출력 없음 = 완전히 동일
```

서버는 경로를 보고 화면을 고르지 않는다. 경로 판단은 브라우저 안의 라우터가 한다.


## 세 파일의 역할 분담

---

> 렌더링 주체가 서버에서 브라우저로 넘어오면서 파일별 책임도 나뉜다.

| 파일 | 역할 |
| --- | --- |
| `index.html` | 앱이 들어갈 빈 자리(`#app`)와 진입 스크립트 태그 |
| `main.js` | 앱 인스턴스를 조립(플러그인 장착)하고 그 자리에 꽂는 행위 |
| `App.vue` | 실제로 그려질 내용, 최상위 컴포넌트 |

```js
// main.js
import { createApp } from 'vue'
import { createPinia } from 'pinia'
import App from './App.vue'
import router from './router'

createApp(App)
  .use(createPinia())
  .use(router)
  .mount('#app')
```

`createApp(App)`은 앱 인스턴스를 만들 뿐 DOM을 건드리지 않는다. `mount('#app')`이 "이 DOM 요소를 내 구역으로 삼겠다"는 선언이고, 그 안쪽은 이후 Vue가 전권을 갖고 관리한다.

## 화면이 생기는 시점

---

> 브라우저가 HTML을 받은 시점에는 화면이 비어 있고, JS가 실행된 뒤에야 DOM이 만들어진다.

```
1. 브라우저: GET /                 → index.html(빈 껍데기) 수신
2. 파싱 중 <script type="module" src="/src/main.js"> 발견
                                   → GET /src/main.js
3. main.js 의 import 문을 따라 연쇄 요청 (ES Module 네이티브 동작)
                                   → GET /src/App.vue, /src/router/index.js, ...
4. main.js 실행: createApp(App).mount('#app')
5. Vue 가 render 함수를 실행 → 실제 DOM 을 만들어 #app 안에 삽입
                                   ← 이 지점에서 처음으로 화면이 생김
6. onMounted 실행 → axios 로 GET /api/users (JSON 수신)
7. 응답으로 상태가 바뀌면 반응성이 감지 → 목록 부분만 다시 그림
```

5번 이전까지 화면은 백지다. SSR은 1번 응답에 완성된 HTML이 들어 있고, CSR은 5번에서 JS가 DOM을 조립한다.

3번의 연쇄 요청은 DevTools Network 탭에서 그대로 보인다. `main.js` 하나를 요청했는데 `vue.js`, `pinia.js`, `App.vue`, `UsersView.vue`, `userStore.js`가 줄줄이 따라온다.

![DevTools Network 탭 - App.vue 요청의 응답 헤더에 Content-Type이 text/javascript로 찍혀 있다](/assets/img/vuejs-intro-img1.png)

## 브라우저는 .vue 를 모른다

---

> `.vue` 요청의 응답 Content-Type은 `text/javascript`다.

```bash
$ curl -s -D - -o /dev/null localhost:5173/src/App.vue | grep -i content-type
Content-Type: text/javascript
```

SFC(Single File Component, `.vue`)는 Vue의 파일 형식이지 웹 표준이 아니다. 원문을 JS로 해석시키면 `<script setup>`의 꺾쇠에서 바로 막힌다.

```js
new Function(fs.readFileSync('StatCard.vue', 'utf-8'))
// SyntaxError: Unexpected token '<'
```

브라우저가 `.vue`를 해석하는 게 아니라, Vite가 요청받는 순간 `@vue/compiler-sfc`로 컴파일해 JS로 바꿔 내려준다. 컴파일러를 직접 돌리면 변환 결과가 그대로 보인다.

```html
<!-- 입력 -->
<div class="app">
  <h1>{{ title }}</h1>
  <button @click="count++">{{ count }}</button>
</div>
```

```js
// 출력 - 브라우저에 도착하는 것
export function render(_ctx, _cache) {
  return (_openBlock(), _createElementBlock("div", { class: "app" }, [
    _createElementVNode("h1", null, _toDisplayString(_ctx.title), 1 /* TEXT */),
    _createElementVNode("button", {
      onClick: $event => (_ctx.count++)
    }, _toDisplayString(_ctx.count), 9 /* TEXT, PROPS */, ["onClick"])
  ]))
}
```

`{{ title }}`은 `_toDisplayString(_ctx.title)`로, `@click="count++"`는 `onClick: $event => (_ctx.count++)`로 바뀐다. HTML처럼 보이던 템플릿이 전부 JS 함수 호출이 된다. 이 함수의 반환값이 가상 DOM(vnode) — "화면이 이런 모양이어야 한다"를 기술한 JS 객체 트리이고, Vue가 이를 실제 DOM으로 만들어 붙인다. 상태가 바뀌면 render 함수를 다시 실행해 새 vnode 트리를 만들고, 이전 트리와 비교(diff)해 달라진 DOM만 갱신한다.

주석의 `1 /* TEXT */`, `9 /* TEXT, PROPS */`는 patch flag다. "이 노드는 텍스트만 바뀔 수 있다"를 컴파일 시점에 표시해 두면 diff 때 나머지 속성은 비교하지 않는다. 컴파일 단계가 있어서 얻는 최적화다.

여기서 컴파일은 `javac`처럼 바이트코드를 만드는 게 아니라 소스 → 소스 변환(트랜스파일)이다. 결과물은 위처럼 사람이 읽을 수 있는 JS 텍스트고, 그대로 브라우저가 실행한다.

`<style scoped>`도 별도 요청으로 분리된다. Network 탭의 `App.vue?vue&type=style&index=0&scoped=7a7a37b1&lang.css` 같은 항목이 그것이다.

## Vue 는 다운로드된 JS 라이브러리다

---

> `createApp(App).mount('#app')`은 새로운 문법이 아니라 `node_modules/vue`에 정의된 함수 호출이다.

빌드 결과 `index-*.js` 171KB의 대부분이 Vue 본체다. 브라우저는 그 JS를 평범하게 실행하고, 그 코드가 하는 일이 화면 그리기다.

`createApp`은 `@vue/runtime-dom`에 이렇게 적혀 있다.

```js
const createApp = ((...args) => {
  const app = ensureRenderer().createApp(...args);
  const { mount } = app;
  app.mount = (containerOrSelector) => {
    const container = normalizeContainer(containerOrSelector);
    if (container.nodeType === 1) {
      container.textContent = "";        // #app 안을 비우고
    }
    const proxy = mount(container, ...); // 렌더링
    container.setAttribute("data-v-app", "");
    return proxy;
  };
  return app;
});

function normalizeContainer(container) {
  if (isString(container)) {
    return document.querySelector(container);   // '#app' → DOM 요소
  }
  ...
}
```

DOM을 만드는 부분도 순수 DOM API다.

```js
const nodeOps = {
  insert: (child, parent, anchor) => { parent.insertBefore(child, anchor || null); },
  createElement: (tag, ...) => doc.createElement(tag),
  createText: (text) => doc.createTextNode(text),
  remove: (child) => { child.parentNode.removeChild(child); },
  ...
};
```

`mount('#app')`은 "이 요소를 비우고 내가 관리하겠다"는 선언이고, 이후 상태가 바뀔 때마다 Vue가 위 함수들을 대신 호출해 DOM을 갱신한다.

## node_modules 와 @vue 스코프

---

> `node_modules`는 `~/.m2`에 대응하지만, 캐시를 참조하는 게 아니라 프로젝트 안에 압축을 풀어 놓는다.

`package.json`에 적은 의존성은 4개인데 설치된 패키지는 56개, 57MB다. 전이 의존성까지 받은 결과다.

| | Maven | npm |
| --- | --- | --- |
| 선언 | `pom.xml` | `package.json` |
| 버전 고정 | pom에 직접 | `package-lock.json` |
| 저장소 | Maven Central | npm registry |
| 다운로드 캐시 | `~/.m2/repository` | `~/.npm/_cacache` |
| 사용 위치 | 캐시의 jar를 classpath에 참조 | 프로젝트마다 `node_modules`로 복사 |
| 배포 단위 | `.jar` | `.tgz` |

배포 단위가 압축 파일인 것은 같다(`npm view vue dist.tarball` → `vue-3.5.42.tgz`). 차이는 설치 후 압축이 풀린 채로 남는다는 점이고, 그래서 `node_modules/@vue/runtime-dom/dist/*.js`를 열어 위의 `createApp` 원문을 그대로 읽을 수 있다.

`@`로 시작하는 이름은 scoped package로, groupId와 같은 네임스페이스다.

```
@vue/runtime-dom     ≈   org.springframework:spring-web
└┬─┘ └────┬─────┘         └──────┬──────┘ └───┬────┘
scope   패키지명            groupId      artifactId
```

`vue` 패키지 자체에는 코드가 거의 없다. 진입 파일 전문이 이렇다.

```js
import { initCustomFormatter, warn } from '@vue/runtime-dom';
export * from '@vue/runtime-dom';     // 전부 그대로 재수출
```

`import { createApp } from 'vue'`는 실제로 `@vue/runtime-dom`의 함수를 쓴다. `spring-boot-starter-web` jar 안에 클래스가 0개이고 pom의 의존성 목록만 있는 것과 같은 구조다.

```bash
$ unzip -l spring-boot-starter-web-3.5.4.jar
  MANIFEST.MF / NOTICE.txt / LICENSE.txt      # 4 files, 클래스 0개
```

알맹이는 `@vue` 아래에 12개로 쪼개져 있다.

```
vue (껍데기)
└── @vue/runtime-dom        브라우저 DOM 조작 (nodeOps, createApp)
    ├── @vue/runtime-core   컴포넌트·렌더링 엔진 (플랫폼 무관)
    ├── @vue/reactivity     ref, computed, watch
    └── @vue/shared         공통 유틸
└── @vue/compiler-sfc       .vue → JS 변환 (Vite 가 사용)
└── @vue/compiler-dom       template → render 함수
└── @vue/server-renderer    SSR
```

쪼갠 이유는 필요한 것만 가져가게 하기 위해서다. `@vue/compiler-sfc`는 빌드할 때만 쓰므로 브라우저로 내려갈 필요가 없고, `@vue/reactivity`만 따로 설치해 `ref`·`computed`만 쓸 수도 있으며, `runtime-core`(엔진)와 `runtime-dom`(DOM 조작)이 분리돼 있어 DOM 대신 다른 플랫폼 구현을 끼울 수 있다. Vue도 Spring처럼 모노레포에서 개발하고 배포만 여러 패키지로 나눈다. `@vue/*` 버전이 전부 `3.5.42`로 같은 이유다.

버전 충돌 처리 방식은 Maven과 다르다. npm은 기본적으로 `node_modules` 바로 아래에 평평하게 깔지만, 같은 패키지의 다른 버전이 필요하면 요구한 쪽 안에 중첩해 따로 깐다.

```
node_modules/@vue/devtools-api                       8.2.1   # pinia 가 요구
node_modules/vue-router/node_modules/@vue/devtools-api 6.6.4  # vue-router 가 요구
```

Maven은 nearest wins로 하나만 남겨 버전이 안 맞으면 `NoSuchMethodError`가 나지만, npm은 각자 자기 버전을 쓴다. 대신 같은 라이브러리가 여러 벌 번들에 들어갈 수 있다.

## SSR 과 다른 세 가지

---

> 렌더링 위치가 바뀌면서 데이터 형식, 화면 전환 방식, 서버 설정이 함께 달라진다.

**데이터는 HTML이 아니라 JSON으로 온다.** `/api/users`는 `[{"id":4,"name":"홍길동","age":41}]`만 반환한다. 화면 조립은 클라이언트 몫이라 백엔드에는 뷰 템플릿이 한 장도 없다.

**화면 전환에 서버 왕복이 없다.** `<RouterLink to="/stats">`를 누르면 `history.pushState()`로 주소창만 바꾸고 `<RouterView>` 자리의 컴포넌트를 교체한다. 문서 요청은 발생하지 않는다.

**서버에 SPA fallback 설정이 필요하다.** `/stats`에서 새로고침하면 브라우저는 서버로 `GET /stats`를 실제로 보낸다. 서버에 그 경로가 없으면 404다. 어떤 경로로 오든 `index.html`을 내려주고 경로 판단은 브라우저 라우터에 맡겨야 한다. 개발 중에는 Vite가 자동으로 처리하고(위 `diff` 결과), 배포 시에는 웹서버에 직접 설정한다.

```nginx
location / {
  try_files $uri $uri/ /index.html;
}
```

## 라우터는 어떻게 화면을 고르는가

---

> `router/index.js`는 URL과 컴포넌트의 매핑 테이블이고, 매칭은 서버가 아니라 브라우저에서 일어난다.

```js
const routes = [
  { path: '/',      component: UsersView },                              // 미리 import
  { path: '/stats', component: () => import('../views/StatsView.vue') }, // 함수
  { path: '/:pathMatch(.*)*', redirect: '/' },
]

export default createRouter({ history: createWebHistory(), routes })
```

| | Spring MVC | vue-router |
| --- | --- | --- |
| 매핑 선언 | `@GetMapping("/stats")` | `{ path: '/stats', component }` |
| 매칭 주체 | DispatcherServlet (서버) | 브라우저의 JS |
| 결과물 | HTML 응답 | 화면에 그릴 컴포넌트 |
| 매칭 시점 | 요청마다 | 링크 클릭 / 주소 변경 시 |

### app.use(router) 가 붙여주는 것

`use()`는 플러그인의 `install(app)`을 호출하는 규약이다. vue-router의 `install` 원문에 필요한 게 다 들어 있다.

```js
install(app) {
  app.component("RouterLink", RouterLink);        // ①
  app.component("RouterView", RouterView);        // ①
  Object.defineProperty(app.config.globalProperties, "$route", {
    get: () => unref(currentRoute)                // ②
  });
  push(routerHistory.location);                   // 최초 1회 현재 URL 로 이동
  app.provide(routerViewLocationKey, currentRoute);  // ②
}
```

**① 전역 등록.** `import` 한 컴포넌트는 그 파일 안에서만 유효하다(지역 등록). `App.vue`는 `RouterLink`를 import하지 않으므로 컴파일러가 이름표만 남기고, 실행 시점에 전역 등록 목록에서 찾는다. 컴파일 결과를 비교하면 처리가 갈린다.

```js
// UsersView.vue - import 한 경우: 변수를 직접 참조
import UserForm from "/src/components/UserForm.vue"
_createVNode($setup["UserForm"], { ... })

// App.vue - import 안 한 경우: 이름으로 찾아달라고 요청
const _component_RouterLink = _resolveComponent("RouterLink")
```

`<RouterLink>`는 Vue 문법이 아니라 전역 이름으로 등록된 컴포넌트다. `app.use(router)`를 빼면 `Failed to resolve component: RouterLink` 경고가 뜬다.

**② 현재 경로를 담은 ref.** 선언부는 평범한 `ref`다.

```js
const currentRoute = shallowRef(START_LOCATION_NORMALIZED);
```

`RouterView`는 이 값을 `computed`로 읽어 컴포넌트를 고른다.

```js
const matchedRouteRef = computed(() => routeToDisplay.value.matched[depth.value]);
const ViewComponent = matchedRoute && matchedRoute.components[currentName];
const component = h(ViewComponent, ...)
```

화면 전환은 `ref` 하나가 바뀌고 `computed`가 다시 계산되는 것이 전부다. 목록에 사용자를 추가할 때 화면이 갱신되는 것과 같은 메커니즘이며, 페이지 전환이라고 특별한 장치가 있는 게 아니다.

**③ popstate 리스너.** `window.addEventListener("popstate", popStateHandler)`가 브라우저의 뒤로/앞으로 가기를 감지한다.

| 동작 | `popstate` 발생 |
| --- | --- |
| `history.pushState()` 호출 (앱이 이동) | 안 남 |
| 사용자가 뒤로/앞으로 가기 클릭 | 남 |

앱이 스스로 이동할 때는 자기가 아니까 이벤트가 필요 없다. 뒤로가기는 브라우저가 혼자 URL을 되돌리므로 라우터가 알 방법이 이 이벤트뿐이고, 리스너가 없으면 주소창은 `/`인데 화면은 통계 페이지인 상태가 된다.

### 링크 클릭

```
1. <RouterLink to="/stats"> 클릭
   → <a> 기본 동작을 preventDefault 로 막고 router.push('/stats')
2. routes 배열에서 매칭 → component 가 함수다 → 호출해서 기다림
3. import('./StatsView-DHwxr6LF.js')  → GET /assets/StatsView-DHwxr6LF.js
4. history.pushState(null, '', '/stats')   ← 주소창만 변경, 문서 요청 없음
5. currentRoute 갱신 → RouterView 재렌더
```

문서 요청은 0건, JS 청크 요청 1건이고 그마저 최초 1회뿐이다.

### 주소창에 직접 입력하거나 새로고침

`dist`만 올린 정적 서버(SPA fallback + `/api` 중계)에 `/stats`로 접속했을 때 서버가 받은 요청이다.

```
/stats                          →  fallback: index.html
/assets/index-BI3Qq2BA.css      →  파일 그대로
/assets/index-BkhmfaHz.js       →  파일 그대로     # 메인 번들
/assets/StatsView-sbROwzsX.css  →  파일 그대로     # 여기부터 런타임 추가 요청
/assets/StatsView-DHwxr6LF.js   →  파일 그대로
/api/users                      →  백엔드(8081)로 중계
```

서버는 첫 줄에서 `index.html`을 주고 손을 뗀다. 이후 `/stats`를 해석하는 것은 브라우저 안의 라우터이며, 3번째 줄부터는 라우터가 `component` 함수를 호출한 결과로 발생한 요청이다.

`.vue` 경로가 해시 붙은 파일명이 되는 것은 빌드 시점의 치환이다.

```js
component: () => mh(() => import(`./StatsView-DHwxr6LF.js`), __vite__mapDeps([0,1]))

__vite__mapDeps = (i, m, d = ["assets/StatsView-DHwxr6LF.js", "assets/StatsView-sbROwzsX.css"]) => i.map(i => d[i])
```

`__vite__mapDeps`는 이 청크와 함께 받아야 할 파일 목록이고, preload 헬퍼가 CSS를 `<link>`로 먼저 건다. 위 로그에서 CSS가 JS보다 먼저 요청된 이유이며, 스타일 없는 화면이 잠깐 보이는 것을 막기 위해서다.

### history 모드 선택

```js
createWebHistory()       // /stats     - 서버 fallback 설정 필요
createWebHashHistory()   // /#/stats   - 설정 불필요
```

`#` 뒤는 서버로 전송되지 않으므로 해시 모드는 어떤 경로든 서버가 `/`만 받는다. 서버 설정을 건드릴 수 없는 환경의 회피책이고, URL이 지저분하고 SEO에 불리해 기본은 `createWebHistory`다.

## Vite proxy 는 개발 서버 전용

---

> `server.proxy`는 dev 서버가 요청을 대신 전달하는 설정이며, 빌드 결과물에는 포함되지 않는다.

```js
// vite.config.js
export default defineConfig({
  server: {
    proxy: {
      '/api': { target: 'http://localhost:8081', changeOrigin: true },
    },
  },
})
```

프론트는 `:5173`, API는 `:8081`이라 브라우저가 직접 호출하면 출처가 달라 CORS에 걸린다. 이 설정이 있으면 브라우저는 같은 출처인 `:5173/api/users`를 호출하고, Vite가 `:8081`로 중계한다. 브라우저 입장에서는 교차 출처 요청이 아니므로 CORS 검사 자체가 발생하지 않는다.

`npm run build` 산출물은 정적 파일이고 dev 서버가 없으므로 이 설정도 사라진다. 배포 환경에서는 프론트와 API를 같은 도메인 뒤에 두고 웹서버가 `/api`를 백엔드로 넘기거나, 도메인이 다르면 백엔드에서 CORS를 허용해야 한다. `vite preview`로 빌드 결과를 확인할 때는 `server.proxy`가 아니라 `preview.proxy`를 따로 설정한다.

## 개발 서버와 빌드 결과의 차이

---

> 개발 중에는 모듈을 파일 단위로 그때그때 변환하고, 빌드하면 하나로 번들링한다.

개발 서버는 `/src/App.vue`, `/src/router/index.js`처럼 파일을 하나씩 요청받아 변환해 내려준다. 응답 첫 줄의 `createHotContext`가 HMR(Hot Module Replacement) 장치로, 파일을 저장하면 페이지 전체가 아니라 해당 모듈만 교체된다.

`npm run build` 결과는 다음과 같다.

```html
<!doctype html>
<html lang="ko">
  <head>
    <title>Vue in Action - 사용자 관리</title>
    <script type="module" crossorigin src="/assets/index-B1EJTRP_.js"></script>
    <link rel="stylesheet" crossorigin href="/assets/index-Cipgu9OI.css">
  </head>
  <body>
    <div id="app"></div>
  </body>
</html>
```

수십 개 모듈이 JS 파일 하나로 번들링되고 파일명에 해시가 붙는다(캐시 무효화 목적). `<div id="app"></div>`가 비어 있는 것은 그대로다. 배포해도 렌더링 주체는 여전히 브라우저다.

## 번들링과 fat jar 의 차이

---

> 의존성을 한 덩어리로 묶는다는 발상은 같지만, 번들러는 실제로 쓰는 코드만 골라 넣는다.

같은 규모의 CRUD를 각각 빌드한 결과다.

| | 백엔드 (fat jar) | 프론트 (dist) |
| --- | --- | --- |
| 입력 | 의존성 jar 58개 | `node_modules` 57MB, 56패키지 |
| 산출물 | **47MB** | **208KB** |
| 내 코드 | 클래스 106개 | 컴포넌트 8개 + JS 6개 |
| 실행 | `java -jar` (톰캣 내장) | 정적 파일, 웹서버가 서빙 |

fat jar는 `BOOT-INF/lib/`에 의존성 jar를 통째로 넣는다. `spring-web.jar`에서 실제로 쓰는 클래스가 몇 개든 jar 전체가 들어간다. 런타임 리플렉션으로 클래스를 찾을 수 있어 안 쓰는 것처럼 보여도 함부로 뺄 수 없기 때문이다.

번들러는 반대로 도달하지 않는 코드를 잘라낸다(tree shaking). 같은 `vue` 패키지를 두 가지로 import해 각각 빌드하면 차이가 드러난다.

```
A) import { ref, computed } from 'vue'                      →  12.69 kB
B) import { createApp, h, Teleport, Transition, KeepAlive } →  73.50 kB
```

`ref`, `computed`만 쓰면 렌더러도 컴포넌트 시스템도 번들에 들어가지 않는다. ES Module의 `import`/`export`는 실행 전에 정적으로 분석되므로 무엇이 쓰이는지 알 수 있다.

실제 번들을 뒤져보면 안 쓰는 것과 빌드 전용 도구는 빠져 있다.

```
Teleport       : 있음      # ConfirmDialog 에서 사용
insertBefore   : 있음      # nodeOps
compileScript  : 없음      # @vue/compiler-sfc, 빌드할 때만 사용
createSSRApp   : 없음      # SSR 미사용
renderToString : 없음      # @vue/server-renderer
```

`@vue/*`가 12개로 쪼개져 있는 이유가 여기서 드러난다. 컴파일러는 `.vue`를 JS로 바꾸는 빌드 도구라 사용자 브라우저로 갈 이유가 없다.

산출물이 하나가 아니라는 점도 다르다.

```
dist/assets/index-BkhmfaHz.js       171.38 kB   # Vue + router + pinia + axios + 대부분 화면
dist/assets/StatsView-DHwxr6LF.js     1.78 kB   # 통계 페이지만
dist/assets/index-BI3Qq2BA.css        4.35 kB
dist/assets/StatsView-sbROwzsX.css    1.20 kB
```

라우터에서 `component: () => import('../views/StatsView.vue')`로 동적 import를 쓴 결과다(code splitting). `"연령대 분포"` 문자열은 메인 번들에 없고 `StatsView-*.js`에만 있으며, 사용자가 `/stats`에 들어가는 순간 1.78KB를 추가로 받는다. 코드를 네트워크로 내려보내야 해서 존재하는 최적화이고, 서버에 두면 그만인 jar에는 없는 고민이다.

실행 방식도 갈린다. fat jar는 톰캣을 품은 실행 가능한 완제품이라 `java -jar`로 뜨지만, `dist`는 실행 주체가 없는 정적 파일 묶음이다. 실행은 사용자 브라우저가 하고 서버는 파일을 전달만 한다. 앞의 SPA fallback 설정이 필요했던 이유도 여기에 있다.

## 정리

---

> 브라우저에서 **우클릭 → 페이지 소스 보기**와 **DevTools Elements 탭**을 비교하면 차이가 바로 드러난다.

전자는 서버가 내려준 빈 껍데기, 후자는 JS가 만들어낸 완성된 DOM이다. 둘이 다르다는 것이 CSR의 정의다.

| 구분 | SSR (JSP, Thymeleaf) | CSR (Vue SPA) |
| --- | --- | --- |
| 첫 응답 HTML | 데이터가 채워진 완성 문서 | 빈 `<div id="app">` |
| 렌더링 주체 | 서버 | 브라우저의 JS |
| 서버가 주는 데이터 | HTML | JSON |
| 화면 전환 | 문서 전체 재요청 | 컴포넌트 교체, 요청 없음 |
| 경로 처리 | 서버 라우팅 | 브라우저 라우터 + SPA fallback |

Vue도 SSR을 할 수 있다(Nuxt). 서버에서 컴포넌트를 HTML 문자열로 렌더링해 내려주고 브라우저에서 JS가 그 HTML에 이벤트를 다시 붙이는 하이드레이션 방식이며, SEO와 첫 화면 표시 속도가 중요할 때 사용한다.

## 참고 자료

---

- [Application Instance - createApp, mount (vuejs.org/guide/essentials/application)](https://vuejs.org/guide/essentials/application.html)
- [Rendering Mechanism - vnode, patch flag (vuejs.org/guide/extras/rendering-mechanism)](https://vuejs.org/guide/extras/rendering-mechanism.html)
- [Render Functions & JSX - h(), render 함수 직접 작성 (vuejs.org/guide/extras/render-function)](https://vuejs.org/guide/extras/render-function.html)
- [Single-File Components (vuejs.org/guide/scaling-up/sfc)](https://vuejs.org/guide/scaling-up/sfc.html)
- [Server Configurations - SPA fallback 설정 (vite.dev/guide/static-deploy)](https://vite.dev/guide/static-deploy.html)
- [Server Options - server.proxy (vite.dev/config/server-options)](https://vite.dev/config/server-options.html#server-proxy)
- [Building for Production - 번들 분리, 청크 (vite.dev/guide/build)](https://vite.dev/guide/build.html)
- [About packages and modules - scoped package (docs.npmjs.com)](https://docs.npmjs.com/about-packages-and-modules)
- [Different History Modes - 서버 설정 (router.vuejs.org/guide/essentials/history-mode)](https://router.vuejs.org/guide/essentials/history-mode.html)
- [Lazy Loading Routes - 동적 import 와 청크 분리 (router.vuejs.org/guide/advanced/lazy-loading)](https://router.vuejs.org/guide/advanced/lazy-loading.html)
- [Component Registration - 전역 등록과 지역 등록 (vuejs.org/guide/components/registration)](https://vuejs.org/guide/components/registration.html)
