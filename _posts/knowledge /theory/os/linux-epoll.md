---
title: Linux - epoll이란 ?
date: 2025-05-18 20:25:00 +0900
categories: [지식 더하기, 이론]
tags: [Linux]
---

## epoll ?
- epoll은 Linux 커널 2.6 이상에서 제공되는 **이벤트 감시 인터페이스**입니다.
  이전의 select()나 poll()에 비해 성능과 효율이 압도적으로 좋습니다.

- epoll은 크게 세 가지 시스템 호출을 중심으로 동작
  - `epoll_create()` : epoll 객체 생성 (파일 디스크립터 반환)
  - `epoll_ctl()`	: 감시할 FD를 epoll에 등록/수정/제거
  - `epoll_wait()` : 이벤트가 발생할 때까지 기다렸다가 알려줌

```
int epfd = epoll_create1(0);  // epoll 객체 생성

// 소켓 또는 파일 디스크립터를 등록
struct epoll_event ev;
ev.events = EPOLLIN | EPOLLET;
ev.data.ptr = custom_data;
epoll_ctl(epfd, EPOLL_CTL_ADD, sock_fd, &ev);

// 이벤트 대기 루프
while (1) {
struct epoll_event events[MAX_EVENTS];
int nfds = epoll_wait(epfd, events, MAX_EVENTS, timeout);

    for (int i = 0; i < nfds; i++) {
        // 이벤트 발생 시 해당 핸들러 실행
        handle_event(events[i].data.ptr);
    }
}
```

### 주요 특징
**1. 수십만 개 소켓 처리 가능**
- select()/poll()은 FD 수만큼 반복 확인 : (O(N))
- epoll은 이벤트가 발생한 FD만 알려줌 : (O(1))

**2. 이벤트 중심 모델**
- 관심 있는 이벤트만 등록 가능 (EPOLLIN, EPOLLOUT, EPOLLERR, ...)

**3. 레벨 트리거 vs 엣지 트리거**
- Level-triggered	: 읽을 게 있으면 계속 이벤트 발생
- Edge-triggered (EPOLLET) : 상태 변화가 생겼을 때만 이벤트 발생 → 더 빠르지만 직접 루프 돌면서 처리해야 함
  - nginx는 성능을 위해 EPOLLET (엣지 트리거) 방식 사용

## 참고 : 파일 디스크립터
> 파일 디스크립터(File Descriptor, FD)는 운영체제가 관리하는 열린 파일(또는 소켓, 파이프, 터미널 등)에 대한 정수형 식별자
