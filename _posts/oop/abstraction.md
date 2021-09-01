
# 다형성과 추상화

## 다형성 (polymorphism)

여러(poly) 모습(morph)을 갖는 것

객체 지향에서는 한 객체가 여러 타입을 갖는 것
  - 즉, 한 객체가 여러 타입의 기능을 제공
  - 타입 상속으로 다형성 구현
    - 하위 타입은 상위 타입도 됨

![image](https://user-images.githubusercontent.com/64415489/131666741-b7e22fdc-7e3b-431b-b037-64df58bbfd34.png)



## 추상화(Abstraction)
- 데이터나 프로세스 등을 의미가 비슷한 개념이나 의미 있는 표현으로 정의하는 과정
- 두 가지 방식의 추상화
  - 특정한 성질
  - 공통 성질(일반화)

- 간단한 예
  - DB의 USER 테이블 : 아이디, 이름, 메일
  - Money 클래스 : 통화, 금액
  - 프린터 : HP MXX, 삼성 SL-M2XX
  - GPU : 지포스 GX - XX, 라데온 RD- XX

***공통 성질을 뽑아내는 추상화를 통해 다형성을 실현할 수 있다.***

![image](https://user-images.githubusercontent.com/64415489/131667318-00780817-0984-4912-8bab-80d6865fcc6e.png)


### 타입 추상화
- 여러 구현 클래스를 대표하는 상위 타입 도출
  - 흔히 인터페이스 타입으로 추상화
  - 추상화 타입과 구현은 타입 상속으로 연결
- 추상 타입은 구현을 감춘다
- 추상 타입을 사용하면 유연함을 제공한다.

![image](https://user-images.githubusercontent.com/64415489/131667388-78b280b1-446c-4349-b5a1-87225d39d8b0.png)

![image](https://user-images.githubusercontent.com/64415489/131667654-9bd3a565-ee76-4480-99d9-812857563cdf.png)

- 본질(주문 취소)과는 크게 상관 없는 요구 사항 변경(취소시 이메일 전송, sms전송 등)으로 인해 본질적인 취소 메서드의 코드가 변경된다.
![image](https://user-images.githubusercontent.com/64415489/131667833-eaf6bb97-08b8-43ef-85fb-4fb45ac9ca2e.png)

![image](https://user-images.githubusercontent.com/64415489/131668010-86fb4f24-fafa-429b-ac07-1cff3a1d0bad.png)

- 사용할 대상 접근도 추상화
- getNotifier -> Notifier의 구현을 생성
  - 객체를 생성하는 기능 자체도 NotifierFactory로 추상화 해볼 수 있다.
![image](https://user-images.githubusercontent.com/64415489/131668171-6c50b709-6461-45cd-9b1d-8874a796470d.png)


![image](https://user-images.githubusercontent.com/64415489/131668481-12db3a4c-51bd-4adf-a40b-452ea9c86931.png)


![image](https://user-images.githubusercontent.com/64415489/131668604-c40ad67d-ffee-4bb9-ba12-8a5821c6c462.png)


![image](https://user-images.githubusercontent.com/64415489/131668807-4968907c-2b05-43c2-84b8-734e5c192b61.png)
