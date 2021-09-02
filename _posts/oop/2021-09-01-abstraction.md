---
title: 객체 지향 언어의 특징 - 다형성과 추상화
date: 2021-09-01 00:29:00 +0900
categories: [OOP]
tags: [OOP, Java]
---

해당 글은 최범균 님의 [객체 지향 프로그래밍 입문 강의](https://www.inflearn.com/course/%EA%B0%9D%EC%B2%B4-%EC%A7%80%ED%96%A5-%ED%94%84%EB%A1%9C%EA%B7%B8%EB%9E%98%EB%B0%8D-%EC%9E%85%EB%AC%B8)를 듣고 정리한 내용입니다.

# 다형성과 추상화

## 다형성 (polymorphism)

> 여러(poly) 모습(morph)을 갖는 것. 즉, 한 객체가 여러 타입을 갖는 것을 의미한다.

- 즉, 한 객체가 여러 타입의 기능을 제공
- 타입 상속으로 다형성 구현
    - 하위 타입은 상위 타입도 됨
- 아래와 같은 관계가 있다고 가정했을 때, IotTimer는 Timer, Rechargeable 타입 모두로 선언될 수 있다.
  - 즉, 다양한 타입을 갖는다.

```java
public class IotTimer extends Timer implements Rechargeable {
    ...
}
```

```java
// 다형성
IotTimer it = new IotTimer();
Timer t = it;
Rechargeable r = it;
```

## 추상화(Abstraction)
- 데이터나 프로세스 등을 의미가 비슷한 개념이나 의미 있는 표현으로 정의하는 과정
- 두 가지 방식의 추상화
  - 특정한 성질
  - 공통 성질(일반화)

- 추상화의 간단한 예
  - 아이디, 이름, 메일 → DB의 USER 테이블
  - 통화, 금액 → Money
  - HP MXX, 삼성 SL-M2XX → 프린터
  - 지포스 GX - XX, 라데온 RD- XX → GPU
  - SCP로 파일 업로드, HTTP로 데이터 전송, DB 테이블에 삽입 → 푸시 발송 요청

***공통 성질을 뽑아내는 추상화를 통해 다형성이 실현된다.***

### 타입 추상화
- 여러 구현 클래스를 대표하는 상위 타입 도출
  - 흔히 인터페이스 타입으로 추상화
  - 추상화 타입과 구현은 타입 상속으로 연결

- 상위타입(인터페이스)인 `Notifier`는 기능에 대한 의미를 제공한다.
  - 즉, 구현은 제공하지 않고 하위 클래스(concrete 클래스)에게 맡긴다.

<img src = "https://user-images.githubusercontent.com/64415489/131896343-a12fc022-af55-46b1-a511-d40093294bb1.png" width="80%"/>

### 추상 타입
- 추상 타입은 구현을 감춘다.
  - 즉, 기능의 구현이 아닌 의도를 더 잘 드러낸다.
- 추상 타입을 사용하지 않는 경우 요구사항의 변경으로 인해 그와 관련없는 코드가 변경될 수 있다.
  - 예를 들어, 아래와 같은 경우 주문 취소 자체와는 크게 상관 없는 요구 사항 변경(취소시 이메일 전송, sms전송 등)으로 인해 ***본질적인 취소 메서드의 코드가 변경된다.***

- 최초 요구사항 (주문 취소시 sms 발송)

```java
private SmsSender smsSender;

public void cancel(String orderNo) {
    ... 주문 취소 처리

    smsSender.sendSms(...);
}
```

- 요구사항 변경 (카카오 알림, 메일 알림 추가)

```java
private SmsSender smsSender;
private KakaoPush kakaoPush;
private MailService mailSvc;

public void cancel(String orderNo) {
    ... 주문 취소 처리

    if(pushEnabled) {
        kakaoPush.push(...);
    } else {
        smsSender.sendSms(...);
    }
    mailSvc.sendMail(...);
}
```

- 이런 경우 추상 타입을 활용해 유연함을 제공할 수 있다.
  - 아래 예시는 `Notifier`의 콘크리트 클래스를 생성하는 부분까지 `NotifierFactory`라는 인터페이스를 사용해 추상화 시켰다.

```java
public void cancel(String orderNo) {
    ... 주문 취소 처리

    Notifier notifier = NotifierFactory.instance().getNotifier(...);
    notifier.notify(...);
}

public interface NotifierFactory {
    Notifier getNotifier(...);

    static NotifierFactory instance() {
        return new DefaultNotifierFactory();
    }
}

public class DefaultNotifierFactory implements NotifierFactory {
    public Notifier getNotifier(...) {
        if(pushEnabled) return new KakaoNotifier();
        else return new SmsNotifier();
    }
}
```

## 추상화의 시점
- 아직 존재하지 않는 기능에 대한 이른 추상화는 주의해야 한다.
  - 추상화 → 추상 타입 증가 → 복잡도 증가
- 따라서, 실제 변경 및 확장이 발생할 떄 추상화를 시도하는게 좋다.

※ 추상화 팁 : 구현을 한 이유가 무엇 때문인지 잘 생각해보고 상위 타입을 도출한다.

# 느낀점
---
- 캡슐화나 추상화의 본질은 결국 ***'구체적인 구현을 클라이언트(호출하는 부분)에게 숨긴다'***인 것 같다.
- 캡슐화 : 객체가 제공하는 기능의 내부 구현을 숨긴다.
  - 클라이언트는 자신이 사용하는 특정 객체의 기능에 대한 내부 구현은 알지못하고 해당 기능을 사용하기만 한다.
  - 따라서, 해당 객체의 기능의 내부 구현이 변경되더라도 클라이언트 코드는 변경되지 않는다.
- 추상화 : 클라이언트가 사용하게될 구체 클래스(콘크리트 클래스)를 숨긴다.
  - 클라이언트가 인터페이스에 의존하며 구체 클래스는 외부에서 가져옴으로써 런타임시 사용하게될 객체에 대해 알 수 없다.
  - 따라서, 구체 클래스가 변경되더라도 클라이언트 코드는 변경되지 않는다.

# 연관 포스팅
---
-[객체 지향 언어의 특징 - 캡슐화](https://zz9z9.github.io/posts/encapsulation/)
