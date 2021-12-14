---
title: IE11에서 window.open()시 빈팝업과 새로운 탭 생기는 이슈
date: 2021-12-14 23:00:00 +0900
categories: [개발 일기]
tags: [IE11]
---

# 상황
---
사내에서 사용하는 화면 중, 버튼을 누르면 `window.open(url, target, options)`으로 팝업을 띄우는 코드가 있었다. 하지만, 요구사항으로 인해 기존 로직을 `POST` 요청으로 변경해야했고 이를 위해 아래와 같은 방식으로 코드를 변경했다.
```javascript
const form = document.createElement("form");
form1.target="child1";
form1.param1="param1";
form1.param2="param2";

window.open("", "child1", "some options");
form1.submit();
```

개발 환경에서 테스트를 잘 마치고 운영 환경 전단계에 배포해서 확인해보는데, 기존에 팝업으로 뜨던 화면이 새로운 탭에서 열리고 팝업창은 빈 상태로 떠있는 현상이 발생했다. <br>

※ 테스트 브라우저는 `IE11`이고 개발 PC와 이상 현상을 발견한 PC는 다른 PC이다.

# 원인
---
> IE11의 특정 버전들에서 이러한 현상이 발생하는 것 같다.

- 처음엔 브라우저 설정도 바꿔보고 브랜치에 머지된 다른 자원들의 영향인지도 살펴보고 `window.open()` 자체에 대해서도 좀 더 찾아봤지만, 답이 나오질 않았다.
- 그러다 다음 두 개의 글을 통해 IE 문제인 것을 알 수 있었다.
  - [같은 현상1](https://answers.microsoft.com/en-us/ie/forum/all/open-new-popup-window-getting-a-blank-page-and-it/bab61949-2327-474d-b001-8f9f33562988)
  - [같은 현상2](https://support.citrix.com/article/CTX206419)

- 테스트시 정상적으로 작동한 IE11 버전과 아닌 버전 몇 가지를 파악해봤다.
  - 정상 작동
    - `20H2(OS 빌드 19042.1348)`
    - `버전 1909(OS 빌드 18363.1916)`
  - 오작동
    - `20H2(OS 빌드 19042.1288)`

# 시도해본 것들
---
> 다른 브라우저로 바꿀 수 있으면 좋겠지만, 해당 시스템의 운영 환경은 IE에 최적화 되어있다..

## 1. IE 탭 설정 바꾸기
- `인터넷 옵션 > 일반 > 탭 > 팝업 표시 방법 : 항상 새 창에서 팝업 열기`
- 이렇게 하면 새로운 탭에서 팝업창이 열리지는 않지만, `window.open()` 3번째 파라미터로 넘겨준 `width, height`에 세팅된 크기와는 다른 팝업창이 생기고, 빈팝업창 또한 그대로 남아있다.

## 2. UAC (사용자 계정 컨트롤) 설정
- [위에서 언급한 글](https://support.citrix.com/article/CTX206419)에서 제시하는 방법 중 하나로, **"Enable UAC"**가 있는데 나의 경우는 이 방법으론 해결되지 않았다.
- 내가 잘못한 것일 수도 있으니 좀 더 시도해봐야될 것 같다.

## 3. `window.open()` 3번째 파라미터에 `popup` 추가
- 시도 예정

# 참고 자료
---
- [https://answers.microsoft.com/en-us/ie/forum/all/open-new-popup-window-getting-a-blank-page-and-it/bab61949-2327-474d-b001-8f9f33562988](https://answers.microsoft.com/en-us/ie/forum/all/open-new-popup-window-getting-a-blank-page-and-it/bab61949-2327-474d-b001-8f9f33562988)
- [https://support.citrix.com/article/CTX206419](https://support.citrix.com/article/CTX206419)
