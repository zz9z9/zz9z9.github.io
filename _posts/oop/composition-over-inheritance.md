


# 상속(inheritance)

![image](https://user-images.githubusercontent.com/64415489/131668980-a74d92fe-601f-4ba9-b626-c5aeea056209.png)

# 상속을 통한 기능 재사용시 단점
- 상위 클래스 변경 어려움
- 클래스 증가
- 상속 오용


![image](https://user-images.githubusercontent.com/64415489/131669154-f9e06fb0-dcc4-4c06-b9eb-07194b603172.png)

![image](https://user-images.githubusercontent.com/64415489/131669688-5d741e30-a00e-45fc-8952-ccb867458f36.png)

![image](https://user-images.githubusercontent.com/64415489/131669825-5891a654-4db8-4bf1-b470-1a83aa686cdc.png)

# 조립(composition)
- 여러 객체를 묶어서 더 복잡한 기능을 제공
- 보통 필드로 다른 객체를 참조하는 방식으로 조립
- 또는 객체를 필요 시점에 생성,구함

![image](https://user-images.githubusercontent.com/64415489/131670053-29126e72-3e03-4f2a-88e1-f30a82962d31.png)

- 클래스 증식이 줄어들 수 있다.

![image](https://user-images.githubusercontent.com/64415489/131670134-be5b5b15-62b2-4c8a-8d3c-3919396d4a64.png)


- 불필요한 기능까지 상속하는 것을 방지할 수 있다.
![image](https://user-images.githubusercontent.com/64415489/131670234-c8dd4f24-7e7e-4b19-8468-8878c3c94fc4.png)

## 상속 vs 조립
- 상속하기에 앞서 조립으로 풀 수 없는지 검토한다.
- 진짜 하위 타입인 경우에만 상속을 사용한다.
