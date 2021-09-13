---
title: 객체 지향 언어의 특징 - 기능과 책임 분리
date: 2021-09-04 00:29:00 +0900
categories: [OOP]
tags: [OOP, Java]
---

해당 글은 최범균 님의 [객체 지향 프로그래밍 입문 강의](https://www.inflearn.com/course/%EA%B0%9D%EC%B2%B4-%EC%A7%80%ED%96%A5-%ED%94%84%EB%A1%9C%EA%B7%B8%EB%9E%98%EB%B0%8D-%EC%9E%85%EB%AC%B8)를 듣고 정리한 내용입니다.


# 기능
---
- 기능은 하위 기능으로 분해 가능하다
  - ***각각의 기능을 누가 제공할 것인지 결정하는 것***이 객체 지향 설계의 기본이다.
- 기능은 곧 책임이다.
  - 따라서, 분리한 기능을 알맞게 분배해야한다.***(책임 분리)***

![image](https://user-images.githubusercontent.com/64415489/133125035-94f39f53-85ac-4d16-8a24-132d5de30552.png)

- 분리한 하위 기능을 활용해서 전체 기능을 완성한다.
```java
public class ChangePasswordService {
    public Result changePassword(...) {
        Member findMem = memberRepository.findById(id);
        if(findMem==null)

        ...
    }
}
```

## 기능을 분리하지 않으면 ?
- 클래스나 메서드가 커지면 절차 지향의 문제가 발생한다.
  - 큰 클래스의 경우 많은 필드를 많은 메서드가 공유하게 된다.
  - 큰 메서드의 경우 많은 변수를 많은 코드가 공유하게 된다.
  - 이런 경우, 여러 기능이 한 클래스/메서드에 섞여 있을 가능성이 높다.

- 따라서, 책임에 따라 코드를 적절하게 분리해야 한다.
<img src="https://user-images.githubusercontent.com/64415489/133126034-5ba69e62-0d47-466b-8bed-0a0accec8b01.png" width="70%"/>


# 책임 분배/분리 방법 살펴보기
---
> 크게 '패턴 적용', '계산 기능 분리', '외부 연동 분리', '조건별 분기 추상화' 관점에서 분리해 볼 수 있다.

## 1. 패턴 적용(전형적인 역할 분리)
- 간단한 웹 - 컨트롤러, 서비스, DAO
- 복잡한 도메인 - 엔티티, VO, 리파지토리, 도메인 서비스
- AOP - Aspect(공통 기능)
- 디자인 패턴 - 팩토리, 빌더, 전략, 템플릿 메서드 등

## 2. 계산 기능 분리

### Before
```java
Member mem = memberRepository.findOne(id);
Product prod = productRepository.findOne(prodId);

int payAmount = prod.getPrice() * orderReq.getAmount();
double pointRate = 0.01;

if(mem.getMembership() == GOLD) {
    계산 ...
} else if(mem.getMembership() == SILVER) {
    계산 ...
}
...

```

### After
> 포인트 계산에 대한 책임은 `PointCalculator`에게 맡긴다. 이를 통해, 포인트 계산에 대한 부분만 따로 테스트 할 수 있게된다.
> 즉, 역할 분리가 잘 되면 테스트가 용이해지는 장점도 얻을 수 있다.

```java
Member mem = memberRepository.findOne(id);
Product prod = productRepository.findOne(prodId);

int payAmount = prod.getPrice() * orderReq.getAmount();
PointCalculator cal = new PointCalculator(...);

int point = cal.calculate();
...

```

```java
public class PointCalculator {
    ...
    public int calculate() {
      if(membership == GOLD) {
        ...
      }
        ...
    }
}
```

## 3. 외부 연동 분리
> 네트워크, 메시징, 파일 등에 대한 연동 코드를 분리한다.

### Before
```java
Product prod = findOne(id);

RestTemplate rest = new RestTemplate();
List<RecommendItem> recoItems = rest.get("http:// ~~?prodId="+ prod.getId());
```

### After
> 의도가 잘 드러나는 이름을 사용하도록 신경쓰자. 위와 같은 상황에서는 <br>
> HttpDataService 보다 RecommendService가 더 직관적일 것이다.

```java
Product prod = findOne(id);

RecommendService recoService = new RecommendService();
List<RecommendItem> recoItems = recoService.getRecommendItems(prod);
```

## 4. 조건별 분기 추상화
> 조건별 분기가 산재해 있는 경우, 추상화 할 수 있는(공통적으로 묶을 수 있는) 부분이 있는지 살펴본다.

### Before
```java
String fileUrl = "";
if(fildId.startWith(...)) {
    fileUrl = ...;
} else if(fileId.startWith(...)) {
    fileUrl = ...;
} else if(...) {
    fileUrl = ...;
}
```

### After
> 공통적으로 계속 나타나는 url을 제공하는 부분을 묶는다.

```java
String fileUrl = FileInfo.getUrl(fileId);
```

```java
public class FileInfo {
    public static String getUrl(fileId) {
        if(fileId.startWith(...)) {
          ...
        }
        ...
    }
}
```
