---
title: IE에서 작동하지 않는 자바스크립트 코드
date: 2021-12-06 23:00:00 +0900
categories: [개발 일기]
tags: [Internet Explorer, ES6]
---

# 상황
---
회사에서 맡은 작업을 로컬 환경에서 개발/테스트하고 개발 환경에 배포하여 잘 동작하는지 테스트해봤다. 로컬에서 여러 번의 테스트 결과 별이상 없었기 때문에 당연히 되겠지하고 '조회' 버튼을 누르는데 아무런 반응이 없었다... <br>
IE 개발자 도구를 통해 콘솔을 확인해보니, 서버에서 응답받은 js 파일 중 하나에서 `SCRIPT1004: ';'가 필요합니다.`라는 에러 메시지를 유발했다. 이 문제를 해결하고나니 콘솔 창에서 또 다른 에러 메세지인 `개체가 'replaceAll' 속성이나 메서드를 지원하지 않습니다.`를 맞닥들였다.

# 원인
---
> 두 에러 메시지 모두 IE에서 지원하지 않는 자바스크립트 기능을 사용했기 때문에 발생했다. <br>
> (로컬 환경에서는 크롬으로만 테스트를 해서 이상이 없었던 것이었다...)

- 다음은 `for ... of`에 대한 브라우저 호환성을 나타낸 표이다.
<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/144874879-26047ab2-f896-45bd-ac3c-8312ed63cb26.png" width="80%"/>
  <figcaption align="center">출처 : <a href="https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Statements/for...of#browser_compatibility" target="_blank"> https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Statements/for...of#browser_compatibility</a> </figcaption>
</figure>

- 다음은 `replaceAll`에 대한 브라우저 호환성을 나타낸 표이다.
<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/144875049-724747b0-850f-406e-a6ea-3222e3b54d7d.png" width="80%"/>
  <figcaption>출처 : <a href="https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/String/replaceAll" target="_blank"> https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/String/replaceAll</a> </figcaption>
</figure>

- [해당 사이트](https://caniuse.com/es6)에 가보면 ES6부터는 IE11에서만 부분 지원이라고 하는데 이마저도 `const, let` 등의 키워드 `Map, Set` 정도인 것 같다.
- [w3cschool](https://www.w3schools.com/js/js_versions.asp)에는 `Internet Explorer does not support ECMAScript 2015.`라고 되어있다.

# 해결 방법
---
> Babel과 같은 트랜스컴파일러를 사용하는 방법도 있겠지만, 학습이 부족하므로 일단 문법적으로 해결할 수 있는 방법에 대해 살펴보자. ~~(그냥 IE를 버리자. )~~

## for ... of 대신 for ... in 사용
- **Before**
```javascript
for(const order of orders) {
    ...
}
```

- **After**
```javascript
for(const idx in orders) {
    const order = orders[idx];
    ...
}
```

## replaceAll 대신 replace 함수와 정규 표현식 사용
- **Before**
```javascript
const price = value.replaceAll(',', ''); // "10,000,000" -> 10000000
```

- **After**
```javascript
const price = value.replace(/,/gi, ''); // "10,000,000" -> 10000000
```

<br>

**※ [해당 사이트](https://caniuse.com/)에서 아래와 같이 특정 기능에 대한 브라우저 호환성에 대해 확인해 볼 수 있다.**

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/144874381-7c466b52-dcf0-416e-bf35-da6299426518.png" width="80%"/>
  <figcaption align="center">출처 : <a href="https://caniuse.com/" target="_blank"> https://caniuse.com/</a> </figcaption>
</figure>


# 참고 자료
---
- [https://caniuse.com/](https://caniuse.com/)
- [https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/String/replaceAll](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/String/replaceAll)
- [https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Statements/for...of#browser_compatibility](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Statements/for...of#browser_compatibility)
