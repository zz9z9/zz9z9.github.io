---
title: npm 알아보기
date: 2025-12-20 00:25:00 +0900
categories: [지식 더하기, 이론]
tags: [Frontend]
---

## npm (Node Package Manager)
---

> Node : Node.js에서 실행되는
> Package : JS 라이브러리 묶음
> Manager : 설치 / 관리 / 실행
> 즉, Node 환경에서 쓰는 JS 패키지를 관리하는 도구

> Node.js용 패키지 관리자
> npm is the world's largest software registry. Open source developers from every continent use npm to share and borrow packages, and many organizations use npm to manage private development as well.

| 단어      | 의미             |
| ------- | -------------- |
| Node    | Node.js에서 실행되는 |
| Package | JS 라이브러리 묶음    |
| Manager | 설치 / 관리 / 실행   |


npm consists of three distinct components:

the website
the Command Line Interface (CLI)
the registry
Use the website to discover packages, set up profiles, and manage other aspects of your npm experience. For example, you can set up organizations to manage access to public or private packages.

The CLI runs from a terminal, and is how most developers interact with npm.

The registry is a large public database of JavaScript software and the meta-information surrounding it.

- 프론트엔드 세계의 Maven Central + Gradle/Maven 일부 역할
- Java의 mvn install, gradle build 처럼
  - 라이브러리 다운로드
  - 의존성 버전 관리

| 역할      | 설명                             |
| ------- | ------------------------------ |
| 패키지 설치  | `vue`, `vite`, `axios` 등       |
| 의존성 관리  | `package.json`, `node_modules` |
| 스크립트 실행 | `npm run dev`, `npm run build` |

| Spring        | Vue          |
| ------------- | ------------ |
| Maven Central | npm registry |
| pom.xml       | package.json |
| .m2           | node_modules |


## Node
---
> Node.js = JavaScript를 “브라우저 밖”에서 실행하게 해주는 런타임 (Java의 JVM 같은 실행 환경)

- 원래 JavaScript는:
  - 오직 브라우저 안에서만 실행 가능
  - 서버, 빌드, 스크립트 실행 불가

- “JS로 서버도 만들고, 빌드도 하고 싶다” → Node.js 등장

| 역할        | 설명               |
| --------- | ---------------- |
| JS 실행     | `node app.js`    |
| 파일 시스템 접근 | read/write       |
| 네트워크      | HTTP 서버          |
| 빌드 실행     | Vite, Webpack 실행 |


```
Node.js is an open-source and cross-platform JavaScript runtime environment. It is a popular tool for almost any kind of project!

Node.js runs the V8 JavaScript engine, the core of Google Chrome, outside of the browser. This allows Node.js to be very performant.

A Node.js app runs in a single process, without creating a new thread for every request. Node.js provides a set of asynchronous I/O primitives in its standard library that prevent JavaScript code from blocking. In addition, libraries in Node.js are generally written using non-blocking paradigms. Accordingly, blocking behavior is the exception rather than the norm in Node.js.

When Node.js performs an I/O operation, like reading from the network, accessing a database or the filesystem, instead of blocking the thread and wasting CPU cycles waiting, Node.js will resume the operations when the response comes back.

This allows Node.js to handle thousands of concurrent connections with a single server without introducing the burden of managing thread concurrency, which could be a significant source of bugs.

Node.js has a unique advantage because millions of frontend developers that write JavaScript for the browser are now able to write the server-side code in addition to the client-side code without the need to learn a completely different language.

In Node.js the new ECMAScript standards can be used without problems, as you don't have to wait for all your users to update their browsers - you are in charge of deciding which ECMAScript version to use by changing the Node.js version, and you can also enable specific experimental features by running Node.js with flags.
```

### Node와 npm 관계 ?
> jvm 환경에서 gradle이 실행되는것 == node.js 환경에서 npm이 실행되는것 ? 으로 이해하면 되나 ?

```
OS
 └─ JVM
     └─ Gradle
         └─ build / dependency 관리

OS
 └─ Node.js
     └─ npm
         └─ install / script 실행
```

- Gradle은 JVM 위에서 실행
- npm은 Node.js 위에서 실행

| 관점       | Gradle        | npm          |
| -------- | ------------- | ------------ |
| 실행 환경    | JVM           | Node.js      |
| 의존성 관리   | ⭕             | ⭕            |
| 빌드 트리거   | ⭕             | ⭕            |
| 스크립트 실행  | ⭕             | ⭕            |
| 실제 빌드 로직 | ⭕ (Gradle 내부) | ❌ (외부 도구 위임) |

**중요한 차이점**
- Gradle
  - 빌드 도구 자체
  - 컴파일, 테스트, 패키징 직접 수행
  - 플러그인 기반 DSL
  - `./gradlew build` : Gradle이 직접 컴파일하고 jar를 만듦

- npm
  - 패키지 관리자 + 실행기
  - 실제 빌드는 Vite / Webpack이 수행
  - npm은 “명령어 실행 버튼”에 가까움
  - `npm run build` : vite build 실행
  - npm은 빌드를 실행시킬 뿐, 빌드를 하지는 않음

- 따라서,

| Java         | JS             |
| ------------ | -------------- |
| JVM          | Node.js        |
| Gradle       | **npm + Vite** |
| gradle task  | npm script     |
| build.gradle | package.json   |


## Package
---

> 재사용 가능한 JavaScript 코드 묶음 (라이브러리)

- 하나의 패키지는 보통 다음과 같이 구성됨:

```
some-package/
 ├─ index.js
 ├─ other.js
 └─ package.json
```

- 기능 단위로 묶인 코드
- 버전이 있음
- 다른 프로젝트에서 재사용 가능

- 예시:

| 패키지     | 역할         |
| ------- | ---------- |
| `vue`   | Vue 런타임    |
| `vite`  | 빌드 도구      |
| `axios` | HTTP 클라이언트 |
| `pinia` | 상태 관리      |

- 자바 생태계와 비교

| Java               | JS           |
| ------------------ | ------------ |
| library            | package      |
| jar                | npm package  |
| groupId:artifactId | package name |
| version            | version      |

## 로컬에서 개발 서버 역할을 Vite가 한다는거야 Node가 한다는거야 ? 예를 들어, localhost:3000 으로 띄워서 vue로 만든 화면 보는건 누가, 어떤 흐름으로 가능하게 해주는거야 ?
---
> 로컬 개발 서버를 “직접” 띄우는 건 Vite
> 그 Vite를 실행시켜 주는 실행 환경이 Node.js

- Node.js: Vite가 돌아가는 “엔진(런타임)”
- Vite: 실제로 HTTP 서버를 띄우는 “프로그램”
  - localhost:3000(또는 5173)을 열어주는 주체는 Vite

- `npm run dev` 실행시
  - 1. `package.json`의 `scripts.dev` 확인

```
{
  "scripts": {
    "dev": "vite"
  }
}
```
  - 2. npm이 Node.js로 Vite를 실행 : `node node_modules/vite/bin/vite.js`

- Vite 서버가 하는 일

| 단계            | 설명               |
| ------------- | ---------------- |
| index.html 제공 | 기본 HTML          |
| JS 요청 처리      | ES Module 그대로 응답 |
| `.vue` 요청     | 즉석에서 변환          |
| HMR           | 변경 즉시 반영         |

| Java        | JS              |
| ----------- | --------------- |
| JVM         | Node.js         |
| Spring Boot | Vite            |
| Tomcat      | Vite 내부 HTTP 서버 |

- 왜 개발 서버가 필요한가?
  이유 : .vue 파일 때문
  - 브라우저는:
    - .vue ❌
    - <script setup> ❌
    import { ref } from 'vue' ❌

👉 누군가 중간에서 즉석 변환 필요
👉 그 역할을 Vite 개발 서버가 수행

```
코드 수정
  ↓
Vite 감지
  ↓
변경된 모듈만 교체
  ↓
브라우저 즉시 반영
```

## 그럼 npm, Vite도 js로 만든 애플리케이션인거야 ?
---
> npm도, Vite도 전부 JavaScript로 만들어진 애플리케이션이다. 그리고 Node.js 위에서 실행된다.

```
OS
 └─ Node.js
     ├─ npm  (JS 프로그램)
     └─ Vite (JS 프로그램)
```

- npm = Node.js로 작성된 CLI 애플리케이션
  - 실제 파일 위치 (예시): `node_modules/npm/bin/npm-cli.js`
  - `npm run dev` -> `node npm-cli.js run dev` : JS 코드가 실행되는 것

- Vite = Node.js 환경에서 실행되는 JS 기반 개발 서버 + 빌드 도구
  - 주요 구성:
    - Node.js
    - esbuild (Go 기반, 일부 사용)
    - Rollup (JS)
  - `vite` -> `node node_modules/vite/bin/vite.js`

## Node.js는 런타임이라면서, Node.js로 작성했다는건 무슨 의미야 ?
---

왜 “JavaScript로 작성되었다” 대신 “Node.js로 작성되었다”라고 할까?

여기 중요한 뉘앙스 차이가 있음.

❌ “JavaScript로 작성되었다”만 말하면

브라우저용 JS인지?

Node용 JS인지?
→ 구분이 안 됨

✅ “Node.js로 작성되었다”라고 하면

브라우저 ❌

Node 런타임 전용 ⭕

fs, path, process 같은 Node API 사용 ⭕

👉 실행 환경까지 포함한 표현

5️⃣ npm이 실제로 Node.js 전용인 이유

npm 내부 코드에서는 이런 걸 씀:

const fs = require('fs')
const path = require('path')
process.exit(1)


이건:

브라우저 ❌

Node.js ⭕

👉 그래서 “Node.js로 작성된 애플리케이션” 이라고 부르는 게 정확함

## 그럼 브라우저용 JS랑 Node용 JS는 뭐가 달라?”
---
> 브라우저용 JS와 Node용 JS는 “언어 문법은 거의 같고”, “실행 환경과 사용할 수 있는 API가 다르다”

### 공통점
- 같은 언어다
  const sum = (a, b) => a + b

문법 (if, for, class, async/await)

타입 개념 (없음)

ES 표준

👉 완전히 같은 JavaScript

### 가장 큰 차이: 실행 환경(Runtime)

| 구분      | 브라우저 JS  | Node JS  |
| ------- | -------- | -------- |
| 실행 위치   | 브라우저     | OS 위     |
| 전역 객체   | `window` | `global` |
| DOM 접근  | ⭕        | ❌        |
| 파일 시스템  | ❌        | ⭕        |
| 네트워크 서버 | ❌        | ⭕        |

### 브라우저용 JS 특징
> 화면을 그리고 사용자와 상호작용

- 제공 API 예시:

```
document.querySelector('#app')
window.alert('hi')
fetch('/api/users')
```

- DOM API / BOM API  / Web API : 브라우저가 제공

- 할 수 없는 것
  fs.readFile('a.txt')   // ❌
  process.exit(1)       // ❌
  net.createServer()    // ❌
- 보안상 절대 허용 안 됨

### Node.js용 JS 특징
> 서버 / 빌드 / 자동화 / CLI

- 제공 API

```
const fs = require('fs')
const http = require('http')

http.createServer((req, res) => {
  res.end('hello')
}).listen(3000)
```

- 파일 시스템 / 네트워크 / 프로세스 제어 : Node.js가 제공

할 수 없는 것
document.getElementById('app') // ❌
window.location                // ❌
=> DOM이 없음

| 항목      | 브라우저 JS | Node JS |
| ------- | ------- | ------- |
| DOM     | ⭕       | ❌       |
| fs      | ❌       | ⭕       |
| http 서버 | ❌       | ⭕       |
| 보안 제약   | 강함      | 상대적 자유  |
| 주요 목적   | UI      | 서버/도구   |


Vue 프로젝트에서 둘은 어떻게 쓰일까?
개발 시
Node.js (Vite)
└─ 변환 / 개발 서버

Browser
└─ Vue 앱 실행

배포 시
Browser
└─ 빌드된 JS 실행


👉 Node는 개발/빌드 단계에서만

1️⃣ 문법은 같다
2️⃣ 실행 환경이 다르다
3️⃣ API 제공자가 다르다
4️⃣ 보안 모델이 다르다
5️⃣ 목적이 다르다

## Vue와 Node
---

✔ 우리가 만드는 것
Vue 소스 코드 (*.vue, *.js)
↓
빌드
↓
브라우저에서 실행 가능한 결과물


즉:

HTML

JS (ESM / bundle)

CSS

👉 이 결과물이 실제 “애플리케이션”

3️⃣ Node.js의 정확한 역할
Node.js는 여기까지만 관여함
[개발자]
.vue 작성
↓
[Node.js 환경]
Vite 실행
↓
변환 / 번들링
↓
dist/ 생성


Node.js ❌ Vue 실행

Node.js ⭕ Vite 실행

Vite ⭕ 빌드 결과물 생성

👉 Node는 도구 실행용 런타임

4️⃣ 그래서 더 정확한 문장은 이거야

❌ (부정확)

Node.js는 Vue를 만들기 위한 환경이다

⭕ (정확)

Node.js는 Vue 애플리케이션의 빌드 도구를 실행하기 위한 환경이다

또는 아주 정확하게:

Node.js는 Vue 소스 코드를
브라우저에서 실행 가능한 정적 자산으로
변환·번들링하는 도구(Vite 등)를 실행하는 런타임이다

## 내 이해 정리
---

- node.js : javascript(node 전용 js, 브라우저용 js와 다름)를 실행하는 런타임
- npm : node.js로 작성된(node 전용 js로 작성된) cli 애플리케이션 (패키지를 관리하는 역할)
  - 패키지 : js 기반의 라이브러리 같은 개념
- vite : node.js로 작성된 빌드 도구 + 개발 서버
- vue : javascript framework
  - vue, typescript 등을 브라우저가 이해할 수 있는 js로 변환 및 번들링하는 작업을 위해 Vite와 같은 빌드 도구 필요
  - 이러한 빌드 도구가 실행되는 환경을 제공하는게 Node.js
  - 따라서, vue 빌드 결과물을 만들기 위해서는 Node.js가 필요

=> 보완

node.js : JavaScript를 실행하는 런타임이며,
브라우저가 아닌 환경에서 실행되고
Node 전용 API(fs, http, process 등)를 제공함
👉 JS 문법은 동일,
👉 사용 가능한 API가 다름이 핵심

npm : Node.js 환경에서 실행되는
JavaScript로 작성된 CLI 애플리케이션이며,
패키지 설치/의존성 관리/스크립트 실행을 담당

vite : Node.js 환경에서 실행되는
JavaScript 기반의 프론트엔드 빌드 도구이며,
개발 서버와 번들링 기능을 제공


vue : 브라우저에서 실행되는 JavaScript UI 프레임워크

- Vue(SFC), TypeScript 등으로 작성한 애플리케이션 소스를
  브라우저가 실행 가능한 JavaScript/CSS/HTML로
  변환·번들링하기 위해 Vite 같은 빌드 도구가 필요함
- 이러한 빌드 도구를 실행하는 런타임이 Node.js임
- 따라서 Vue 애플리케이션의 빌드 결과물을 만들기 위해
  Node.js 환경이 필요함

## 그럼 vue는 어떤 언어 기반으로 만들어진거야 ?
---
Vue는 “JavaScript(정확히는 TypeScript)”로 만들어진 프레임워크다.

조금 더 정확히 말하면 👇

Vue의 코어는 TypeScript로 작성되어 있고,
최종적으로는 JavaScript로 컴파일되어 배포된다.

- Vue 3 기준
> Vue 3부터는 사실상 TS-first 프로젝트

| 항목       | 사용 언어                   |
| -------- | ----------------------- |
| Vue Core | **TypeScript**          |
| 런타임 코드   | JavaScript (빌드 결과)      |
| SFC 컴파일러 | TypeScript              |
| 개발 도구    | TypeScript + JavaScript |

- Vue 2는?
  - 대부분 JavaScript
  - 일부 Flow 타입
  - TS 지원이 제한적

- Vue의 2가지 얼굴
  ① Vue 프레임워크 본체

작성 언어: TypeScript

실행 환경: 브라우저

② Vue 빌드/컴파일 도구

작성 언어: TypeScript / JavaScript

실행 환경: Node.js

3️⃣ 왜 TypeScript로 만들었을까?
이유 1️⃣ 대규모 프레임워크 유지보수

타입 안정성

리팩토링 용이

이유 2️⃣ 사용자에게 TS 지원 제공

타입 추론

IDE 자동완성

이유 3️⃣ 컴파일 타임 최적화

SFC 분석

트리 쉐이킹


| Spring                  | Vue                   |
| ----------------------- | --------------------- |
| Spring Framework (Java) | Vue Core (TypeScript) |
| jar 배포                  | JS 번들 배포              |
| JVM 실행                  | 브라우저 실행               |

Vue를 만든 언어 = TypeScript
Vue가 실행되는 언어 = JavaScript

TypeScript는 컴파일 타임 언어
JavaScript는 런타임 언어

## Typescript를 js로 만드는것도 vite(빌드도구) 역할인건가 ?
---
> TypeScript를 JavaScript로 변환하는 과정은 빌드 단계에서 수행되며, Vite가 이를 책임지고 orchestrate(조율)한다. 실제 변환은 esbuild(기본) 또는 tsc(선택) 가 수행한다.

| 역할                | 담당                            |
| ----------------- | ----------------------------- |
| 빌드 파이프라인 총괄       | **Vite**                      |
| TS → JS 변환(트랜스파일) | **esbuild (기본)**              |
| 타입 체크             | **TypeScript(tsc)** *(선택/별도)* |
| 번들링               | **Rollup (Vite 내부)**          |


2️⃣ 개발 모드(npm run dev)에서는 어떻게 되나?
TS/SFC 작성
↓
Vite Dev Server
↓
esbuild로 TS → JS (빠르게, 타입체크 없이)
↓
브라우저로 ESM 전달


변환은 한다 ⭕

타입 체크는 안 한다 ❌ (속도 우선)

그래서 개발 중엔 타입 에러가 있어도 화면은 뜰 수 있음

3️⃣ 빌드 모드(npm run build)에서는?
TS/SFC 작성
↓
Vite build
↓
esbuild로 TS → JS
↓
Rollup 번들링
↓
dist/


기본 설정에서는 여전히 esbuild로 변환

타입 체크는 기본적으로 포함되지 않음

4️⃣ “그럼 tsc는 언제 쓰나?”
타입 체크가 필요할 때 (권장)

보통 이렇게 함:

{
"scripts": {
"dev": "vite",
"build": "vite build",
"typecheck": "tsc --noEmit"
}
}


또는

npm run build && npm run typecheck


👉 Vite는 빠른 빌드,
👉 tsc는 정확한 타입 검증

5️⃣ 왜 Vite는 tsc로 안 바꿀까?

tsc는 느림

Vite의 목표는 빠른 DX

변환(transpile)과 검증(type-check)을 의도적으로 분리

이건 요즘 프론트엔드의 표준 패턴이야.


## Vue 공식문서에 보면, Vue is a JavaScript framework for building user interfaces. 라고 되어있는데, 내 이해로 프레임워크는 정해진 틀에 맞춰서 개발하게되면, 자연스럽게 그 프레임워크에서 의도한 방향으로 개발되는 느낌인데, JavaScript 프레임워크라는게 무슨 의미야 ?
---
> “JavaScript 프레임워크”란
JavaScript로 작성된 애플리케이션을
‘정해진 구조와 흐름’에 따라 만들도록 도와주는 설계·실행 규칙의 집합이다.

Vue 문장의 의미를 풀면 👇

Vue는 사용자 인터페이스(UI)를 만들기 위해
JavaScript 코드의 구조, 흐름, 책임을 미리 설계해 둔 프레임워크다.

네가 말한 “프레임워크 감각”은 정확하다

“정해진 틀에 맞춰서 개발하면
자연스럽게 그 프레임워크가 의도한 방향으로 개발된다”

👉 이게 프레임워크의 본질이야.

Spring이:

Controller

Service

Repository

Bean lifecycle

를 강제하는 것처럼,

Vue도 UI 개발의 흐름을 강제한다.

2️⃣ 그럼 “JavaScript 프레임워크”에서 JavaScript는 뭘 의미하나?
❌ 오해하기 쉬운 해석

“JavaScript로 만들어졌다는 뜻”

이건 절반만 맞음

✅ 정확한 해석

JavaScript 코드로 UI를 작성하게 만들고,
그 JS 코드의 구조와 실행 흐름을 프레임워크가 통제한다

3️⃣ Vue가 “프레임워크”인 이유 (핵심)

Vue는 단순한 라이브러리가 아님.

| 구분    | 라이브러리 | 프레임워크 |
| ----- | ----- | ----- |
| 흐름 제어 | 개발자   | 프레임워크 |
| 호출 주체 | 개발자   | 프레임워크 |
| 구조 강제 | 약함    | 강함    |
| 진입점   | 개발자   | 프레임워크 |

예시 비교
❌ 라이브러리 느낌
import lodash from 'lodash'

const result = lodash.sortBy(list)


👉 내가 필요할 때 호출

✅ Vue 프레임워크 느낌
<template>
<button @click="count++">{{ count }}</button>
</template>


👉

언제 렌더링할지

언제 다시 그릴지

DOM을 어떻게 바꿀지

전부 Vue가 결정

4️⃣ Vue가 UI 개발의 “틀”을 어떻게 강제하나?
① 컴포넌트 단위 개발
UI = Component들의 조합


화면을 컴포넌트로 나누도록 유도

상태와 UI를 묶음

② 선언적 렌더링
{{ count }}


“어떻게” DOM을 조작 ❌

“무엇이 보여야 하는지”만 선언 ⭕

👉 DOM 제어는 Vue 책임

③ 반응성(Reactivity)
const count = ref(0)


상태 변경 → UI 자동 갱신

갱신 타이밍/방식은 프레임워크가 관리

④ 생명주기
onMounted(() => {})


언제 실행될지 Vue가 결정

개발자는 “훅”만 제공

그래서 “JavaScript 프레임워크”의 정확한 의미

JavaScript를 사용해 UI를 작성하지만,
그 JavaScript의 실행 흐름과 구조는
프레임워크(Vue)가 제어한다

7️⃣ “UI를 만든다”는 말의 진짜 의미

Vue는 이렇게 생각하도록 강제함:

❌ “DOM을 어떻게 조작할까?”
⭕ “이 상태라면 UI는 어떻게 보여야 할까?”

👉 사고방식 자체를 바꿔줌

8️⃣ 한 문장으로 완성

Vue는 JavaScript로 UI를 작성하되,
UI의 구조·상태·렌더링 흐름을 프레임워크가 통제하는
‘JavaScript UI 프레임워크’다.

9️⃣ 네 질문에 대한 직접 답변

JavaScript 프레임워크라는게 무슨 의미야?

✔ JavaScript로 작성된 UI 코드에
✔ 프레임워크가 정한 구조와 흐름을 강제하고
✔ 렌더링·상태·라이프사이클을 대신 관리해 주는 것

## vue 프레임워크 사용할때와 안할때의 강제성 등의 차이를 예시 코드로 설명좀
---

아주 좋은 요청이야.
**“프레임워크의 강제성”**은 말로 설명하면 추상적인데,
코드로 보면 한 번에 이해된다.

아래를 같은 요구사항으로 비교해볼게.

요구사항
버튼을 누르면 숫자가 증가하고, 화면에 즉시 반영된다.

1️⃣ Vue 없이 (순수 브라우저 JS)
❌ 프레임워크 없음 (라이브러리/로우 레벨)
<div id="app">
  <button id="btn">Count is: 0</button>
</div>

<script>
  let count = 0

  const btn = document.getElementById('btn')

  btn.addEventListener('click', () => {
    count++
    btn.textContent = `Count is: ${count}`
  })
</script>

특징

개발자가 직접 모든 흐름을 제어

상태(count)와 UI(DOM)가 분리

DOM 직접 조작

커질수록 복잡해짐

여기서 개발자가 책임지는 것

언제 DOM을 업데이트할지

어떤 DOM을 바꿀지

상태 변경 ↔ UI 동기화

👉 강제되는 구조가 없음
👉 개발자 스타일에 따라 코드가 제각각

2️⃣ Vue 사용 (프레임워크)
<script setup>
import { ref } from 'vue'

const count = ref(0)
</script>

<template>
  <button @click="count++">
    Count is: {{ count }}
  </button>
</template>

특징

DOM 직접 조작 없음

상태만 변경하면 UI는 자동 반영

UI 구조가 템플릿으로 고정됨

이벤트, 상태, 렌더링 방식이 정해져 있음

Vue가 대신 책임지는 것

언제 렌더링할지

어떤 DOM을 바꿀지

최소 변경(diff) 계산

성능 최적화

👉 개발자는 “무엇”만 선언
👉 “어떻게”는 Vue가 강제

3️⃣ “강제성”이 어디서 나타나는가
① DOM 접근 강제 차이
❌ Vue 없이
document.getElementById(...)
element.textContent = ...

⭕ Vue 사용
{{ count }}


👉 DOM 직접 접근 금지에 가까운 강제

② 상태 관리 방식 강제
❌ Vue 없이
let count = 0
count++
updateUI()

⭕ Vue 사용
const count = ref(0)
count.value++


👉 ref, reactive를 쓰도록 강제
👉 그냥 변수 쓰면 UI 안 바뀜

③ 이벤트 처리 방식 강제
❌ Vue 없이
btn.addEventListener('click', handler)

⭕ Vue 사용
<button @click="handler">


👉 이벤트 바인딩 문법 강제

④ 코드 구조 강제
❌ Vue 없이 (자유롭지만 혼란)
// 어디서든 DOM 접근
// 어디서든 상태 변경
// 파일 구조 자유

⭕ Vue 사용 (컴포넌트 중심)
Component
├─ state
├─ template
└─ behavior


👉 컴포넌트 단위 설계 강제

4️⃣ 조금만 복잡한 예제 (목록 렌더링)
❌ Vue 없이
<ul id="list"></ul>

<script>
  const items = []
  const ul = document.getElementById('list')

  function render() {
    ul.innerHTML = ''
    items.forEach(item => {
      const li = document.createElement('li')
      li.textContent = item
      ul.appendChild(li)
    })
  }

  items.push('A')
  items.push('B')
  render()
</script>


렌더 함수 직접 작성

전체 다시 그림

실수 여지 많음

⭕ Vue 사용
<script setup>
import { ref } from 'vue'

const items = ref(['A', 'B'])
</script>

<template>
  <ul>
    <li v-for="item in items" :key="item">
      {{ item }}
    </li>
  </ul>
</template>


반복 렌더링 규칙 강제

key 사용 강제

diff 알고리즘은 Vue 책임

5️⃣ “프레임워크의 강제성”을 한 문장으로

Vue를 쓰면
UI를 만드는 “자유”는 줄어들지만,
UI를 망칠 “자유”도 같이 사라진다.

## 스프링 프레임워크가 비즈니스 로직에 집중할 수 있게, 의존성 주입 / aop 등을 제공하는 것처럼, vue 프레임워크는 어떤 목표를 지향하며 이를 위해 어떤 핵심 개념(기능)들을 제공해 ?
---
> **Vue의 목표는
“UI 개발자가 화면 상태와 사용자 경험에만 집중하도록 만드는 것”**이다.
이를 위해 Vue는 DOM, 렌더링 타이밍, 상태 동기화, 성능 최적화 같은
UI 개발에서 가장 번거롭고 실수하기 쉬운 부분을 프레임워크가 대신 책임진다.

| Spring Framework | Vue Framework     |
| ---------------- | ----------------- |
| 비즈니스 로직 집중       | UI 상태/표현 집중       |
| 기술적 관심사 제거       | DOM/렌더링 제거        |
| IoC / DI         | Reactivity        |
| AOP              | Lifecycle / Watch |
| 트랜잭션, 보안         | 렌더링, 성능           |

=> 둘 다 **“관심사 분리”**가 핵심

Vue가 해결하려는 문제
UI 개발에서 개발자가 원래 해야 했던 일들

DOM 직접 조작

상태 변경 ↔ 화면 동기화

언제 다시 그릴지 판단

변경된 부분만 업데이트

이벤트 관리

👉 Vue의 목표 = 이걸 개발자에게서 뺏어오기

3️⃣ Vue가 제공하는 핵심 개념들 (Spring 대응 포함)
① Reactivity (반응성 시스템)
✔ Spring의 DI에 대응
const count = ref(0)


상태를 “관리 대상”으로 등록

변경 감지 자동

👉 상태 변경 = UI 자동 갱신

Spring 대응
Spring DI → 객체 생명주기 관리
Vue Reactivity → 상태 생명주기 관리

② 선언적 렌더링 (Declarative Rendering)
✔ AOP와 비슷한 역할
{{ count }}


“어떻게” 렌더링 ❌

“무엇이 보일지”만 선언 ⭕

👉 렌더링 로직은 프레임워크에 위임

③ Virtual DOM & Renderer
✔ Spring의 프록시 / AOP 느낌

변경 전/후 비교

최소 변경 적용

👉 성능 최적화를 프레임워크가 담당

④ 컴포넌트 모델
✔ Spring의 Bean / 모듈화
Component
├─ state
├─ template
└─ behavior


재사용 가능

독립적 상태

명확한 책임

⑤ Lifecycle Hooks
✔ Spring Lifecycle 대응
onMounted(() => {})


언제 실행될지 Vue가 결정

개발자는 “훅”만 제공

⑥ Template 문법 & Directives
✔ Spring MVC + View 템플릿 대응
v-if
v-for
v-model


조건/반복/바인딩 규칙 표준화

실수 방지

⑦ 단방향 데이터 흐름
✔ 트랜잭션 경계 같은 역할
Parent → Props → Child


상태 흐름 명확

사이드 이펙트 감소

4️⃣ Vue의 핵심 설계 철학 (정리)

Vue는 이렇게 생각하게 강제한다:

❌ “DOM을 어떻게 만질까?”
⭕ “이 상태에서 UI는 어떻게 보여야 할까?”

5️⃣ Spring과 Vue의 “제어권 역전(IoC)” 비교
Spring
@Service
class OrderService {
@Transactional
public void order() {}
}


트랜잭션 시작/종료 → Spring

Vue
<button @click="count++">
{{ count }}
</button>


렌더링 타이밍 → Vue

6️⃣ 한 문장으로 정리하면

Spring이 ‘비즈니스 로직의 실행 흐름’을 관리한다면,
Vue는 ‘UI 상태와 화면 렌더링의 흐름’을 관리한다.

7️⃣ 네 질문에 대한 직접 답

vue 프레임워크는 어떤 목표를 지향하며 이를 위해 어떤 핵심 개념(기능)들을 제공해 ?

✔ 목표

UI 개발자가 상태와 사용자 경험에만 집중하게 하는 것

✔ 핵심 개념

Reactivity

선언적 렌더링

Virtual DOM

컴포넌트 모델

Lifecycle hooks

Template & Directives

단방향 데이터 흐름

## 참고 자료
---
- [https://docs.npmjs.com/about-npm](https://docs.npmjs.com/about-npm)
- [https://nodejs.org/en/learn/getting-started/introduction-to-nodejs](https://nodejs.org/en/learn/getting-started/introduction-to-nodejs)
