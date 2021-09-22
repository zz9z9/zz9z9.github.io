---
title: 추상화를 통해 엑셀 생성 로직 리팩토링하기
date: 2021-09-13 22:25:00 +0900
categories: [개발 일기]
tags: [OOP, 추상화]
---


# 상황
---
현재 운영하고 있는 시스템에는, 사용자가 조회한 결과에 대해 엑셀 파일로 다운받을 수 있는 기능을 몇몇 화면에서 제공한다.
엑셀을 만드는 부분은 스프링부트 기반의 백엔드 서버에서 담당한다. 문제는 해당 로직에서 모든 셀에 대한 영역 지정을 하드코딩으로 해주고 있다는 것이다. <br>

예를 들어, 아래와 같은 경우 Title1의 병합 영역을 '2번 행 + B,C 열' 이런식으로 명시해주고 있다.
결과적으로 중간에 새로운 Title을 추가하게되면 (삭제가 되는 경우도 마찬가지로) 그 이후의 영역에 대한 하드코딩이 다 변경되어야 한다는 것이다. <br>

아래의 예시는 영역이 몇 개 없지만, 실제 코드에는 매우 많은 영역이 존재한다. 따라서, 사용자로부터 중간에 새로운 컬럼이 추가되어야 한다는 요구사항이 들어온다면
매우 비효율적인 노가다 작업을 해야한다.

![image](https://user-images.githubusercontent.com/64415489/134370866-34bc8ba7-9547-46b1-8343-5165f34f464a.png)

# 해결 과정
---
> 절차지향스럽게 산재되어 있는 코드 대신, 역할에 따라 각각의 클래스로 추상화해보자.

## 1. 셀 추상화
> 하나의 셀 뿐만 아니라, 병합된 셀, 하위 셀(위 예시에 subtitle 부분)을 포함하는 셀 등을 나타낼 수 있는 클래스가 필요하다고 생각했다.
> 또한 기존처럼 행과 열의 특정 위치가 아닌 '몇 개의 행을 병합할 것인지', '몇 개의 열을 병합할 것인지'에 대한 정보가 필요하다고 생각했다.

```java
public class CustomCell {
    private final String cellValue;  // 셀에 세팅될 값
    private final int rowSpan;       // 행 병합 수
    private final int colSpan;       // 열 병합 수
    private String dataKey;          // Map에 담긴 조회결과에서, 해당 컬럼에 세팅되어야할 데이터를 가져오기 위한 key값
    private List<CustomCell> childs; // 하위 셀

    ...
}
```

## 2. 테이블 추상화
> 테이블은 데이터가 무엇인지 나타내는 헤더와 데이터 영역인 body를 포함해야한다.
> 또한, 위 예시에는 없지만 테이블의 좌측에 붙어있는 수직 헤더가 포함되는 경우도 있다.

```java
public class CustomTable {
    private int horizontalHeaderStartRow;    // 수평 헤더 시작 행
    private String horizontalHeaderStartCol; // 수평 헤더 시작 열
    private int verticalHeaderStartRow;     // 수직 헤더 시작 행
    private String verticalHeaderStartCol;   // 수직 헤더 시작 열
    private List<CustomCell> horizontalHeaders; // 수평 헤더
    private List<CustomCell> verticalHeaders;   // 수직 헤더
    private List<Map<String,Object>> body;      // 세팅할 데이터
}

```

## 3. 엑셀 만드는 부분 추상화
> 세팅된 CustomTable을 활용하여 엑셀 파일을 만든다. 이 과정에서 셀에 스타일 등을 적용할 수 있다.

```java
public class CustomExcelCreator {
    private List<CustomTable> tables;

    ...

    public void createExcel() {
      ...
    }

    public void createCell(...) {
      ...
    }

    public void createTable(...) {
      ...
    }
}
```

# 결과
---
- 새로운 헤더가 추가되어야 하면 해당 영역을 `CustomCell`로 만든 뒤, 헤더 리스트에 추가한다.
- 기존에는 추가된 컬럼 이후의 모든 부분에 대해 코드를 재작성해야 했다면, 앞으로는 헤더 리스트에 추가하는 부분만 고치면 된다.


# 느낀점
---
- 쓸데없는 곳에 시간낭비 하지 않도록 항상 확장성을 생각해서 코드를 작성하자.
- 확장성이 좋다는 것은 기능, 요구사항 등이 추가/변경되는 경우 최소한의 코드 수정만 하게 만드는 것이라고 생각한다.
- 객체지향의 기본이 되는 캡슐화, 추상화, 다형성 등의 개념을 잘 이해하고 적용하는게 중요한 것 같다.
