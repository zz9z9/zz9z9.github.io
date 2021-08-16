---
title: Exception과 Error
date: 2021-08-10 00:29:00 +0900
categories: [JAVA]
tags: [JAVA, Exception, Error]
---

# 들어가기전
---
`CompletableFuture`를 사용하여 결과를 가져올 때, `get()`과 `join()`을 사용할 수 있는데, `get()`의 경우 checkedException `join()`의 경우 uncheckedException을 발생시킨다고 한다.
이 둘의 차이는 무엇이고 그럼 어떤 메서드를 사용해야할까에 대한 판단을 내리기 위해 공부해보자.

# Error vs Exception
---
Error와 Exception은 모두 `java.lang.Throwable`의 하위 클래스이다. 각각의 특징을 한 번 살펴보자.

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/129588147-11aa5bbe-8273-40b3-b2fd-9e8a1b40b5d5.png"/>
  <figcaption align="center">출처 : <a href="https://facingissuesonit.com/java-exception-handling/">https://facingissuesonit.com/java-exception-handling/</a></figcaption>
</figure>

## Error
- 에러는 Unchecked Exception이며 개발자는 이 것에 대한 어떠한 처리를 하지 않아도된다.(사실 할 수 있는게 없다.)
  - 예를 들어 `OutOfMemoryError`, `StackOverflowError` 등이 있다.
- 즉, 애플리케이션이 해당 에러를 복구할 방법이 없기 때문에, `try-catch` 절을 사용하지 않고 대부분의 경우 애플리케이션이 종료되도록 허용해야 한다.
  - 애플리케이션 수준에서 복구할 방법이 없는 이유는, 대부분의 오류가 JVM에 의해(시스템 레벨) 발생하기 때문이다.

## Exception
- 'Exception Event'의 줄임말로써, 프로그램의 정상적인 흐름을 중단(interrupt)하는 이벤트이다.
- 개발자가 작성한 코드에 의해 발생하며, `try-catch`를 통해 키워드를 `throw` 함으로써 복구할 수 있다.
- 두 가지 유형의 예외로 나눌 수 있다.
  - Checked Exception : 컴파일 시점에 컴파일러에 의해 체크되는 예외
  - Unchecked Exception : 컴파일 시점에 컴파일러에 의해 체크되지 않는 예외

## Exception과 Error 비교 요약

|     |Exception|Error|
|-----|---------|-----|
|복구 여부|try-catch 사용하여 호출자에게 다시 예외 throw|불가능|
|유형|Unchecked type|Checked type, Unchecked type|
|발생 원인|대부분 프로그램이 실행되는 환경에 의해 발생|프로그램에 의해 발생|
|발생 시점|런타임(Checked type의 경우 컴파일 시점에 컴파일러가 체크)|런타임|

# Checked Exception vs Unchecked Exception
---
자바에서 예외는 명시적으로 반드시 처리해야 하는 Checked Exception(`SQLException`, `IOException` 등)과
명시적으로 처리하지 않아도 되는 Unchecked Exception(`NullPointerException`, `NumberFormatException`)으로 나눠진다.
Unchecked Exception은 `RuntimeException`을 상속받는다.

## 예외 처리의 강제성에 대해
[자바 공식문서](https://docs.oracle.com/javase/tutorial/essential/exceptions/runtime.html) 에 보면 예외 처리와 관련하여 설명하고 있다.

- Checked Exception의 경우 예외 처리를 강제하는 이유
  - 해당 예외를 발생시킬 수 있는 여지를 포함하고 있는 메서드를 호출하는 호출자가 예외에 대해 인지하고 적절하게 처리하도록 할 수 있게 하기 위해.

```java
public FileInputStream(File file) throws FileNotFoundException {
    String name = (file != null ? file.getPath() : null);
    SecurityManager security = System.getSecurityManager();
    if (security != null) {
        security.checkRead(name);
    }
    if (name == null) {
        throw new NullPointerException();
    }
    if (file.isInvalid()) {
        throw new FileNotFoundException("Invalid file path");
    }
    fd = new FileDescriptor();
    fd.attach(this);
    path = name;
    open(name);
}

public FileInputStream(String name) throws FileNotFoundException {
    this(name != null ? new File(name) : null);
}
```

```java
private static void checkedExceptionWithTryCatch() {
    File file = new File("not_existing_file.txt");
    try {
        FileInputStream stream = new FileInputStream(file);
    } catch (FileNotFoundException e) {
        e.printStackTrace();
    }
}
```

- 왜 Unchecked Excpetion의 경우는 예외 처리를 강제하지 않았을까?
  - Runtime Exception은 프로그램의 어디에서나 발생할 수 있으며 매우 다양한 경우가 있다.
  - 만약, 모든 메서드 선언에 이러한 예외를 추가해야 하면 프로그램의 명확성이 떨어진다.
  - 예를 들어, 배열을 사용하는 메서드에서 `ArrayIndexOutOfBoundException`, 객체 참조하는 코드가 있는 곳에서 `NullPointerException` 일일이 처리해줘야한다면 코드가 매우 지저분해질 것이다.

- 결론적으로, 해당 글에서는 다음과 같이 마무리한다.
  - 클라이언트(호출자)가 예외로부터 복구할 것으로 합리적으로 기대할 수 있는 경우 checked exception을 사용할 것.
  - 클라이언트(호출자)가 예외에서 복구하기 위해 아무 것도 할 수 없으면 unchecked exception을 사용할 것.

# 실제로 적용해보기
---
- completableFuture 사용해서 성능 개선해보기

# 참고자료
---
- [https://stackoverflow.com/questions/5813614/what-is-difference-between-errors-and-exceptions](https://stackoverflow.com/questions/5813614/what-is-difference-between-errors-and-exceptions)
- [https://madplay.github.io/post/java-checked-unchecked-exceptions](https://madplay.github.io/post/java-checked-unchecked-exceptions)
- [https://cheese10yun.github.io/checked-exception/#unchecked-exception-1](https://cheese10yun.github.io/checked-exception/#unchecked-exception-1)
- [https://www.geeksforgeeks.org/errors-v-s-exceptions-in-java/](https://www.geeksforgeeks.org/errors-v-s-exceptions-in-java/)
- [https://docs.oracle.com/javase/tutorial/essential/exceptions/runtime.html](https://docs.oracle.com/javase/tutorial/essential/exceptions/runtime.html)
- [https://www.baeldung.com/java-checked-unchecked-exceptions](https://www.baeldung.com/java-checked-unchecked-exceptions)
