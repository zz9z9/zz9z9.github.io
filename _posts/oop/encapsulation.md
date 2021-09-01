
# 캡슐화

범균님 강의

- 데이터 + 관련된 기능을 묶는 것

- 객체가 기능을 어떻게 구현했는지 외부에 감추는 것
  - 구현에 사용된 데이터의 상세 내용을 외부에 감춤

- 정보 은닉의미 포함

# 왜 캡슐화 ?
- 외부에 영향 없이 객체 내부 구현 변경 가능

- 내부 구현 감춘다.
  - 내부 구현 변경에 따른 외부 영향을 최소화
  - 내부 구현 변경의 유연함

- 요구사항의 변경이 데이터 구조/사용에 변화를 발생시킴

![image](https://user-images.githubusercontent.com/64415489/131664735-09903619-9584-440e-ad08-727364b84ae5.png)


![image](https://user-images.githubusercontent.com/64415489/131664908-8f0e56b9-d8b4-41d6-8166-f61abdd9e1ff.png)


![image](https://user-images.githubusercontent.com/64415489/131665140-cfb9c869-3788-44ee-93db-0414b531f2a4.png)

![image](https://user-images.githubusercontent.com/64415489/131665265-6c5290f1-f0f7-4809-9d12-d9c6efa1680a.png)

![image](https://user-images.githubusercontent.com/64415489/131665317-f1c52cfa-53a1-44e5-a750-29e375922a0e.png)

![image](https://user-images.githubusercontent.com/64415489/131665390-45efeddf-8d4f-44b0-a9ee-4429ac39d045.png)


# 캡슐화를 위한 규칙

## "Tell, Don't Ask"
> 데이터를 달라 하지 말고 해달라고 하기

즉, 사용하는 입장에서 데이터를 가져와서 무언가 하려하지 말고
데이터를 갖고있는 객체에게 해당 데이터로 무언가 해달라고 해라

if (acc.getMembership() == REGULAR) {
    ... 정회원 기능
}

if (acc.hasRegularPermission()) {
    ... 정회원 기능
}

## Demeter's Law
- 메서드에서 생성한 객체의 메서드만 호출
- 파라미터로 받은 객체의 메서드만 호출
- 필드로 참조하는 객체의 메서드만 호출

![image](https://user-images.githubusercontent.com/64415489/131665883-8e1105e4-4f6b-477c-8979-c12fee23dfd0.png)


