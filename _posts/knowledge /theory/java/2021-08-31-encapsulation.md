---
title: OOP - 객체 지향 언어의 특징(캡슐화)
date: 2021-08-31 00:29:00 +0900
categories: [지식 더하기, 이론]
tags: [OOP]
---

해당 글은 최범균 님의 [객체 지향 프로그래밍 입문 강의](https://www.inflearn.com/course/%EA%B0%9D%EC%B2%B4-%EC%A7%80%ED%96%A5-%ED%94%84%EB%A1%9C%EA%B7%B8%EB%9E%98%EB%B0%8D-%EC%9E%85%EB%AC%B8)를 듣고 정리한 내용입니다.

# 캡슐화
> 데이터 + 관련된 기능을 묶는 것

- 객체가 기능을 어떻게 구현했는지 외부에 감추는 것
  - 구현에 사용된 데이터의 상세 내용을 외부에 감춤
  - 정보 은닉의미 포함

## 캡슐화를 하지 않는 경우
> 요구사항의 변경이 데이터 구조/사용에 변화를 발생시킴

- 예를 들어, 특정 회원이 정회원인지 체크해서 특정 기능을 제공하는 다음과 같은 코드가 있다고 가정해보자.

```java
if(account.getMembership() == REGULAR && account.getExpDate().isAfter(now())) {
    ... 정회원 기능
}
```

- 만약 해당 기능을 5년 이상 사용자에게도 제공해달라는 요구사항이 추가된다면 조건문에 또 다른 조건이 추가되어야한다.
```java
if(account.getMembership() == REGULAR && (
    account.getServiceDate.isAfter(fiveYearsAgo) && account.getExpDate().isAfter(now()))) {
    ... 정회원 기능
}
```

***결과적으로, account에 대한 요구사항의 변화로 인해 기존에 위와 같이 선언되어 있던 모든 부분에서 코드 수정이 발생한다.***

## 캡슐화를 하게되면 ?
> 내부 구현을 감춤으로써 외부의 영향(변경)을 최소화 하면서 객체 내부 구현 변경이 가능하다. <br>
> 즉, 이를 통해 OCP를 지킨 설계가 가능하다.

- 다시 위 예제로 예를 들면 아래와 같이 변경할 수 있다.
  - 즉, 기능을 제공하고 구현 상세를 감춘다.
  ```java
  if(account.hasRegularPermission()) {
      ... 정회원 기능
  }
  ```

- 만약 정회원 관련 요구사항이 변경되더라도 Account의 `hasRegularPermission()` 메서드 내부만 변경하면 된다.
  - `hasRegularPermission()` 메서드를 호출하는 부분에서는 변경될게 없다. (OCP)
  ```java
  public class Account {
      private Membership membership;
      private Date expDate;

      public boolean hasRegularPermission() {
          return account.getMembership() == REGULAR && expDate.isAfter(now());
      }
  }
  ```

- 또한 캡슐화를 통해 기능에 대한 의도를 명확하게 나타낼 수 있다.
  - 즉, `account.getMembership() == REGULAR && account.getExpDate().isAfter(now())` 이런식으로 단순히 조건만 나열하는 것 보다는
  - `hasRegularPermission()` 메서드를 통해 '정회원 권한이 있는지 확인한다'라는 의도를 훨씬 명확하게 드러낼 수 있다.

# 캡슐화를 위한 규칙
> ***"Tell, Don't Ask" : 데이터를 달라 하지 말고 해달라고 하기***

- 즉, 사용하는 입장에서 데이터를 가져와서 무언가 하려하지 말고, ***데이터를 갖고있는 객체에게*** 해당 데이터로 무언가 해달라고 요청해라.
- account의 membership 데이터를 가져와서 내가 검증한다. (X)

```
if (account.getMembership() == REGULAR) {
    ... 정회원 기능
}

```

- account 객체에게 맡긴다. (O)

```
if (account.hasRegularPermission()) {
    ... 정회원 기능
}
```

> ***Demeter's Law***

- 메서드에서 생성한 객체의 메서드만 호출
- 파라미터로 받은 객체의 메서드만 호출
- 필드로 참조하는 객체의 메서드만 호출

# 연관 포스팅
---
-[객체 지향 언어의 특징 - 다형성과 추상화](https://zz9z9.github.io/posts/abstraction/)
