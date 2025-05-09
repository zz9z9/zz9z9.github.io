---
title: 마이크로서비스간 통신(1) - 개요
date: 2021-06-14 22:25:00 +0900
---
*※ 해당 내용은 '마이크로서비스 패턴(크리스 리처드슨)' 3장을 읽고 정리한 내용입니다.*

# Intro
---
- 프로세스 간 통신(Inter-Process Communication)
  - 프로세스들 사이에 서로 데이터를 주고받는 행위 또는 그에 대한 방법이나 경로
- 마이크로서비스 아키텍처는 애플리케이션을 여러 서비스로 구성하며, 서비스 인스턴스는 여러 머신에서 실행되는 프로세스 형태이므로
반드시 IPC를 통해 상호작용 해야한다.
- IPC는 애플리케이션 가용성(정상적으로 사용가능한 정도)에 영향을 미치며, 트랜잭션 관리와도 맞물려 있다.

# IPC 개요
---
## 1. 통신 방식

|   | 일대일 | 일대다 |
|---|--------|--------|
|동기|  요청 / 응답 | - |
|비동기|비동기 요청 / 응답 <br> 단방향 알림 | 발행 / 구독 <br> 발행 / 비동기 응답 |

- `요청/응답`
  - 클라이언트는 응답이 제때 도착할 것을 기다리며 대기하는 동안 블로킹된다.
  - 서비스와 <u>강하게 결합</u>된다.
- `비동기 요청/응답`
  - 클라이언트는 서비스에 요청하고 서비스는 비동기적으로 응답.
  - 클라이언트는 응답에 대한 대기 중에 블로킹하지 않는다.
- `단방향 알림`
  - 클라이언트는 서비스에 요청을 하고 서비스는 응답을 보내지 않는다. **(어떤 경우 ??)**
- `발행/구독`
  - 클라이언트는 <u>알림 메시지</u>를 발행하고 여기에 관심 있는 0개 이상의 서비스가 메시지를 소비
- `발행/비동기 응답`
  -  클라이언트는 <u>요청 메시지</u>를 발행하고 주어진 시간 동안 관련 서비스가 응답하길 기다린다.

## 2. 메시지 포맷
- IPC의 핵심은 메시지 교환이며, 대부분의 메시지는 데이터를 담고 있기 때문에 데이터 포맷은 중요한 설계 결정 항목이다.
- 메시지 포맷은 크게 **텍스트**와 **이진 포맷**으로 분류된다.

### 텍스트 메시지 포맷
- 대표적인 예로 JSON, XML이 있다.
- 장점
  - 자기 서술적(그 자체만으로도 의미가 분명한)이다.
  - 메시지 컨슈머는 자신이 관심 있는 값만 골라 쓰면 되므로 스키마가 자주 바뀌어도 하위 호환성이 쉽게 보장된다.
- 단점
  - 메시지가 다소 길다 (특히, XML)
  - 속성값 이외에 속성명이 추가되는 오버헤드가 있다.
  - 데이터가 많은 메시지는 텍스트를 파싱하는 오버헤드가 있다.

### 이진 메시지 포맷 (???)
- 대표적으로 프로토콜 버퍼와 아브로가 있다.
- 메시지 구조 정의에 필요한 타입 IDL(Interface Definition Language)를 제공
- 컴파일러는 메시지를 직렬화/역직렬화하는 코드 생성
- 따라서, 서비스를 API 우선 접근 방식으로 설계할 수밖에 없다.

# 더 공부해야할 부분
- 이진 메세지 포맷

# 참고 자료
- 크리스 리처드슨, 『마이크로서비스 패턴』, 길벗(2020), p104-152.
