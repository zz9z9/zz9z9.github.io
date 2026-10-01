---
title: Java - e.printStackTrace() 살펴보기
date: 2025-03-09 15:00:00 +0900
categories: [지식 더하기, 이론]
tags: [Java]
---


```java
// Throwable.java
public void printStackTrace() {
    printStackTrace(System.err);
}

public void printStackTrace(PrintStream s) {
    printStackTrace(new WrappedPrintStream(s));
}

private void printStackTrace(PrintStreamOrWriter s) {
    Set<Throwable> dejaVu = Collections.newSetFromMap(new IdentityHashMap<>());
    dejaVu.add(this);

    synchronized (s.lock()) {
        // Print our stack trace
        s.println(this);
        StackTraceElement[] trace = getOurStackTrace();
        for (StackTraceElement traceElement : trace)
            s.println("\tat " + traceElement);

        // Print suppressed exceptions, if any
        for (Throwable se : getSuppressed())
            se.printEnclosedStackTrace(s, trace, SUPPRESSED_CAPTION, "\t", dejaVu);

        // Print cause, if any
        Throwable ourCause = getCause();
        if (ourCause != null)
            ourCause.printEnclosedStackTrace(s, trace, CAUSE_CAPTION, "", dejaVu);
    }
}
```

## 1. 출력을 제어할 수 없음
- 이 메서드는 기본적으로 System.err에 직접 출력을 보내. 즉, 운영환경에서는 애플리케이션의 로그 시스템과 상관없이 콘솔로만 출력이 돼서 별도로 제어하기 어렵다는 거야.
- 이렇게 하면 운영 서버에서 예외 정보가 관리되지 않은 채 터미널이나 콘솔에만 남게 돼서, 나중에 문제가 생겼을 때 확인하기 어렵고, 로그의 통합 관리가 어려워져.

```java
public void printStackTrace() {
    printStackTrace(System.err); // 항상 System.err에 출력 (제어 어려움)
}
```

## 2. 성능 문제 및 동기화 이슈
- 이 코드에서 보면, 출력 스트림에 대한 동기화가 명시적으로 이뤄지고 있어.
- 즉, 예외가 많이 발생하면 여러 스레드가 같은 출력 스트림에 대해 경쟁하면서 성능이 저하될 수 있어. 특히 고부하 환경에서는 이 부분이 병목 현상을 일으킬 수 있어.

```java
synchronized (s.lock()) {
  ...
}
```

## 3. 많은 문자열

```java
for (StackTraceElement traceElement : trace)
    s.println("\tat " + traceElement);
```

왜 불필요한 문자열 객체가 생성될까?
자바에서 문자열 연결 연산자 +는 내부적으로 매번 StringBuilder를 만들어서 처리돼.
위 코드의 "\\tat " + traceElement은 루프마다 새로운 문자열 객체를 생성해.
StackTraceElement는 클래스 이름, 메서드 이름, 파일 이름, 라인 번호 등을 포함하는 상세한 정보가 담긴 객체라서, 매번 문자열로 변환될 때마다 새로운 객체가 힙(Heap)에 올라가.
예외가 자주 발생하거나 호출 스택이 깊으면 GC 대상이 되는 임시 객체들이 굉장히 많아지게 돼.
예를 들어, 호출 스택의 깊이가 50이라면 예외 한 번 발생할 때 최소한 50개의 새로운 문자열 객체가 힙에 생성돼. 예외가 빈번히 발생하는 상황이라면 금방 GC 부하를 초래할 수 있어.

