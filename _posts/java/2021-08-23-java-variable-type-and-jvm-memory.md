---
title: 자바의 메모리 구조와 변수 종류 살펴보기
date: 2021-08-23 23:00:00 +0900
categories: [Java]
tags: [Java, Memory, JVM]
---

# 들어가기전
---
스프링 빈은 기본적으로 싱글톤으로 생성되기 때문에, 빈으로 관리되는 객체의 인스턴스 변수로 선언된 데이터는 스레드 간에 공유된다.
이것을 고려하지 않고 무작정 인스턴스 변수로 선언하면, 멀티 스레딩 환경에서 데이터가 꼬여서 시스템 장애를 초래할 수도 있다.
그렇다면 왜 인스턴스 변수로 선언되는 데이터는 스레드 간에 공유되는 것일까? <br>
이를 이해하기 위해 JVM이 관리하는 메모리 구조에 대해 알아보자.

# Run-Time Data Areas
---
> Java Virtual Machine(JVM)은 프로그램 실행 중에 사용되는 다양한 런타임 데이터 영역을 정의한다. <br>
> 데이터 영역은 크게 ***JVM 단위***의 영역과 ***스레드 단위***의 영역으로 구분할 수 있다. <br>

- JVM 단위 : JVM을 시작할 때 생성되며 JVM이 종료될 때 삭제되는 데이터 영역.
  - Heap
  - Method Area
  - JVM 단위의 데이터 영역은 ***모든 스레드 간에 공유된다.***
- 스레드 단위 : 스레드가 생성될 때 만들어지고 스레드가 종료될 때 삭제되는 데이터 영역.
  - PC Register
  - JVM Stack
  - Native Method Stack

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/130481272-3f3e9c5b-ba39-44dd-ac6a-1cedd856df1b.png" width="80%"/>
  <figcaption align="center">출처 : <a href="https://homoefficio.github.io/2019/01/31/Back-to-the-Essence-Java-%EC%BB%B4%ED%8C%8C%EC%9D%BC%EC%97%90%EC%84%9C-%EC%8B%A4%ED%96%89%EA%B9%8C%EC%A7%80-2/">https://homoefficio.github.io/2019/01/31/Back-to-the-Essence-Java-%EC%BB%B4%ED%8C%8C%EC%9D%BC%EC%97%90%EC%84%9C-%EC%8B%A4%ED%96%89%EA%B9%8C%EC%A7%80-2/</a></figcaption>
</figure>

## Heap
- 힙은 모든 클래스 인스턴스 및 배열이 할당되는 영역이다.
- 힙에 저장된 객체에 할당된 메모리는 명시적인 방법으로는 절대 회수되지 못하며, 오직 가비지 컬렉터(garbage collector)에 의해서만 회수될 수 있다.
- 힙은 고정된 크기이거나 계산에 따라 확장/축소될 수 있다.
- 연산에 필요한 힙의 크기가 부족할 경우 JVM이 `OutOfMemoryError`를 발생시킨다.

## Method Area
- 런타임 상수 풀, 필드와 메서드 데이터, 생성자 및 메서드의 코드와 같은 ***클래스 단위***의 데이터를 저장한다.
- 메서드 영역은 논리적으로 힙의 일부이기 때문에 GC 대상이 되지만 단순 구현에서는 garbage collecting 또는 compacting(압축)하지 않도록 구현할 수 있다.
- 할당 요청을 위해 메서드 영역의 메모리를 사용할 수 없는 경우 JVM `OutOfMemoryError`를 발생시킨다.

## Run-Time Constant Pool
- 런타임 상수 풀에는 컴파일 타임에 이미 알 수 있는 숫자 리터럴 값부터 런타임에 해석되는 메서드와 필드의 참조까지를 포괄하는 여러 종류의 상수가 포함된다.
- 런타임 상수 풀은 다른 전통적인 언어에서 말하는 심볼 테이블과 비슷한 기능을 한다고 보면 된다.

## PC Register
- JVM은 한 번에 여러 스레드의 실행을 지원할 수 있다. 따라서 각 스레드에는 자체 PC(프로그램 카운터) 레지스터가 있다.
- 각 JVM 스레드는 단일 메서드의 코드, 즉 해당 스레드의 현재 메서드를 실행한다.
- 이 메서드가 native가 아닌 경우 pc 레지스터에는 현재 실행 중인 JVM 명령의 주소를 저장한다.
- 스레드에서 현재 실행 중인 메서드가 native이면 JVM의 pc 레지스터 값이 정의되지 않는다.

## Java Virtual Machine Stacks
- 각 스레드에는 스레드와 동시에 생성된 전용 JVM 스택이 있다. JVM 스택은 프레임(Frame)을 저장한다.
- JVM 스택은 로컬 변수와 부분 결과를 보유하고 있으며 메서드 호출 및 반환을 담당한다.
- 스레드의 계산에 허용된 크기보다 큰 JVM 스택이 필요한 경우 JVM이 `StackOverflowError`를 발생시킨다.
- JVM 스택을 동적으로 확장할 수 있지만 메모리가 부족하거나, 새 스레드에 대한 초기 JVM 스택을 만드는 데 메모리가 부족한 경우
JVM이 `OutOfMemoryError`를 발생시킨다.

### 참고. Stack Frame
- JVM 스택을 구성하는 프레임은 다음과 같은 용도로 사용된다.
  - 데이터 및 부분 결과를 저장
  - 동적 연결(dynamic linking) 수행
  - 메서드에 대한 값을 반환
  - 예외 전달

- 각 프레임의 구성 요소는 다음과 같다.
  - 로컬 변수 배열(array of local variables)
  - 피연산자 스택(operand stack)
  - 현재 메서드 클래스의 런타임 상수 풀에 대한 참조

- 메서드가 호출될 때마다 새 프레임이 생성된다.
- 프레임은 메서드 호출이 완료되면 해당 완료가 정상인지 여부에 관계없이 삭제된다.

## Native Method Stack
- JVM 구현시 native 메서드(Java 프로그래밍 언어가 아닌 언어로 작성된 메서드)를 지원하기 위해 일반적으로 "C 스택"이라고 불리는 기존 스택을 사용할 수 있다.
- native 메서드를 로드할 수 없고 기존 스택에 의존하지 않는 JVM 구현에서는 Native Method Stack을 제공할 필요가 없다.
  - 제공된 경우 Native Method Stack은 일반적으로 각 스레드가 생성될 때 스레드별로 할당된다.

- 이 스펙을 사용하면 Native Method Stack이 고정된 크기이거나 계산에 필요한 대로 동적으로 확장 및 축소될 수 있다.
  - Native Method Stack의 크기가 고정된 경우 해당 스택을 만들 때 각각의 크기를 개별적으로 선택할 수 있다.

- 스레드의 계산에 허용된 것보다 큰 Native Method Stack이 필요한 경우 JVM이 `StackOverflowError`를 발생시킨다.
- Native Method Stack을 동적으로 확장하려고 했으나 사용 가능한 메모리가 부족하거나, 새 스레드에 대한 초기 Native Method Stack을 만드는 데 사용할 수 없는 경우 JVM에서 `OutOfMemoryError`를 발생시킨다.


# 변수의 종류
> 자바의 변수에는 지역 변수 / 매개 변수 / 인스턴스 변수 / 클래스 변수가 있다.
> 위에서 공부한 메모리 구조를 기반으로 각각의 변수가 어디에 저장될지 생각해보자.

```java
public class VariableType {
    static int 클래스_변수;
    int 인스턴스_변수;

    public void test(int 매개_변수) {
        int 지역_변수;
    }
}
```
- 클래스 변수
  - 클래스가 처음 호출될 때 생명이 시작되고, 자바 프로그램이 끝날 때 소멸된다.
  - 저장되는 영역 : Method Area
    - **주의 : JVM 단위의 영역이므로 모든 스레드 간에 데이터가 공유된다.**
- 인스턴스 변수
  - 객체가 생성될 때 생명이 시작되고, 그 객체를 참조하고 있는 다른 객체가 없으면 소멸된다.
  - 저장되는 영역 : Heap
    - **주의 : JVM 단위의 영역이므로 모든 스레드 간에 데이터가 공유된다.**
- 매개 변수
  - 메서드가 호출될 때 생명이 시작되고, 메소드가 끝나면 소멸된다.
  - 저장되는 영역 : JVM Stack(Stack Frame)
- 지역 변수
  - 지역 변수를 선언한 중괄호 내에서만 유효
  - 저장되는 영역 : JVM Stack(Stack Frame)


# 참고자료
---
- [https://docs.oracle.com/javase/specs/jvms/se7/html/jvms-2.html](https://docs.oracle.com/javase/specs/jvms/se7/html/jvms-2.html)
- [https://homoefficio.github.io/2019/01/31/Back-to-the-Essence-Java-%EC%BB%B4%ED%8C%8C%EC%9D%BC%EC%97%90%EC%84%9C-%EC%8B%A4%ED%96%89%EA%B9%8C%EC%A7%80-2/](https://homoefficio.github.io/2019/01/31/Back-to-the-Essence-Java-%EC%BB%B4%ED%8C%8C%EC%9D%BC%EC%97%90%EC%84%9C-%EC%8B%A4%ED%96%89%EA%B9%8C%EC%A7%80-2/)
- 이상민, 『자바의 신 1』, 로드북(2017), 4장
