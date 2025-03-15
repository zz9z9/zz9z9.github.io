---
title: iframe이 열리지 않는 이슈 (ancestor violates the following Content Security Policy directive)
date: 2025-03-15 22:25:00 +0900
categories: [경험하기, 이슈 노트]
tags: [HTTP]
---

## 상황
- 기존에는 `http://alpha.domain.com` 부모창에서 `http://alpha-foo.domain.com` iframe을 사용하는 시스템에서,
- 특정 작업으로 인해 `http://alpha.domain.com` 부모창에서 `https://test.alpha-foo.domain.com` iframe을 사용하게 되었는데, 콘솔에 다음과 같은 에러 메세지가 찍히면서 화면이 뜨지 않았다.
- `http://alpha.domain.com`은 타시스템이고 iframe으로 제공하는 화면이 내가 관리하는 시스템이다.

```
Refused to frame 'https://test.alpha-foo.domain.com' because an ancestor violates the following Content Security Policy directive: "frame-ancestors 'self' *.domain.com".
```

## 내가 관리하는 시스템 Nginx 설정
- `add_header Content-Security-Policy "frame-ancestors 'self' *.domain.com";`

## 원인 파악
- [CSP 관련해서 정리](https://zz9z9.github.io/posts/content-security-policy/)하면서 알게되었고, 원인은 굉장히 간단했다.
- 앞서 세팅된 설정에 보면 `*.domain.com`으로 되어있는데, **스키마가 생략되면 CSP가 적용된 출처(origin)의 스키마를 따라가게된다.**
  - 즉, `https://test.alpha-foo.domain.com` iframe(origin)을 띄우려면 부모창(frame-ancestors)도 반드시 `https://*.domain.com`의 형식이어야 했던것이다.

## 해결 방안
**1. 설정 변경**
- `add_header Content-Security-Policy "frame-ancestors 'self' http://*.domain.com";`
  - http로 명시했더라도, "보안 단계가 더 높은 스키마로 업그레이드된 요청은 자동으로 허용"되기 때문에 https도 허용됨

**2. 부모창에서 https 사용**
