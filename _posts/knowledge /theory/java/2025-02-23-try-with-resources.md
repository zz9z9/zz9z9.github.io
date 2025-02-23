---
title: Java - try-with-resources 알아보기
date: 2025-02-23 18:29:00 +0900
categories: [지식 더하기, 이론]
tags: [Java]
---

## try-with-resources란 ?
- 자바7부터 등장한 구문으로 try 블록이 종료될 때 `AutoClosable` 또는 `Closable` 인터페이스를 구현한 리소스에 대해 (JVM이) 자동으로 `close()`를 호출한다.

## 기존(try-finally) 방식
```java
static String readFirstLineFromFileWithFinallyBlock(String path) throws IOException {
    FileReader fr = new FileReader(path);
    BufferedReader br = new BufferedReader(fr);
    try {
        return br.readLine();
    } finally {
        br.close();
        fr.close();
    }
}
```

- 리소스 해제를 위해서는 직접 `close()`를 호출해야한다.
- 만약 `br.close()`에서 예외가 발생하면, `fr.close()`가 실행되지 않을 수 있음. (자원 누수 발생 가능)

## try-with-resources 방식
```java
static String readFirstLineFromFileWithFinallyBlock(String path) throws IOException {
  try (FileReader fr = new FileReader(path);
       BufferedReader br = new BufferedReader(fr)
  ) {
    return br.readLine();
  }
}
```
※ 자바 9부터는 이미 선언된 리소스도 try-with-resources에서 사용할 수 있다.
```java
static String readFirstLineFromFileWithFinallyBlock(String path) throws IOException {
  FileReader fr = new FileReader(path);
  BufferedReader br = new BufferedReader(fr);
  try (fr; br) {
    return br.readLine();
  }
}
```

## 예외 발생 시

```java
try (MyResource resource = new MyResource()) {
    throw new Exception("Exception in try block");
} catch (Exception e) {
    System.out.println("Main Exception: " + e.getMessage());
    for (Throwable suppressed : e.getSuppressed()) {
        System.out.println("Suppressed Exception: " + suppressed.getMessage());
    }
}
```

```
Main Exception: Exception in try block
Suppressed Exception: Exception in close()
```

- try 블록에서 예외 발생
  - 예외가 발생하더라도 close()는 자동으로 호출됨
- try 블록과 close()에서 모두 예외 발생
  - try 블록에서 발생한 예외가 주된 예외(primary exception)가 되고
  - close()에서 발생한 예외는 억제된 예외(suppressed exception)가 됨

**※ Suppressed Exception ?**
- 위에서 살펴보았듯이 `try-with-resources`에서는 두 개 이상의 예외가 발생할 수 있음
- 이런 경우 예외가 덮어씌워져 실제 원인(주 예외)이 사라질 수 있고, 이로 인해 디버깅이 어려워질 수 있음
- 따라서, try 블록에서 발생한 예외를 유지하고, close() 중 발생한 예외는 억제(Suppressed)함
- 자바 7에서 Throwable에 추가된 getSuppressed 메서드를 이용해서 억제된 예외를 가져올 수 있음

## 자원 해제 순서
- 닫히는 순서는 생성 순서의 반대 (LIFO, 후입선출)
  - 즉, writer.close() → zf.close() 순서로 실행됨

```java
try (
    java.util.zip.ZipFile zf = new java.util.zip.ZipFile(zipFileName);
    java.io.BufferedWriter writer = java.nio.file.Files.newBufferedWriter(outputFilePath, charset)
) {
    for (java.util.Enumeration entries = zf.entries(); entries.hasMoreElements();) {
        String zipEntryName = ((java.util.zip.ZipEntry) entries.nextElement()).getName();
        writer.write(zipEntryName);
    }
}
```
## Closable vs AutoClosable
> Java 7에서 try-with-resources를 추가하면서 기존 Closeable을 수정하면 하위 호환성이 깨질 수 있기 때문에 AutoCloseable을 새로 만들고, Closeable이 이를 확장하는 방식으로 해결.

```java
public interface AutoCloseable {
    void close() throws Exception;
}
```

```java
public interface Closeable extends AutoCloseable {
    public void close() throws IOException;
}
```

**예외 처리 관점**
- Closeable은 IO 스트림 전용으로 설계되었으며, IOException을 던진다.
- AutoCloseable은 일반 Exception을 던질 수 있음
  - 즉, AutoCloseable은 일반적인 자원 관리에 더 넓게 적용될 수 있음.
  - 하지만, 구체적인 예외(IOException, SQLException 등)를 던지는 것이 권장됨.
  - 만약 close()에서 예외가 발생할 가능성이 없다면, 예외를 던지지 않는 것이 더 바람직하다.

- AutoCloseable 구현시 close()에서 예외가 발생할 가능성이 있는 경우, 반드시 리소스를 먼저 해제해야 한다.
  - 만약 close()에서 예외가 발생할 수 있다면, 리소스를 먼저 해제하고 예외를 던지는 것이 중요하다.
  - 예외가 발생해도 리소스가 해제되지 않으면, 자원 누수(resource leak)가 발생할 수 있음.

**멱등성 관점**
- Closeable은 idempotent(멱등성) 을 보장
  - 예를 들어, FileInputStream.close()를 여러 번 호출해도 추가적인 예외 없이 안전하게 종료됨.

- AutoCloseable은 이러한 보장을 제공하지는 않지만, 리소스를 여러 번 닫더라도 문제가 발생하지 않도록 설계하는 것이 중요하다.
  - 즉, close()는 일반적으로 한 번만 호출되지만, 여러 번 호출될 가능성도 고려해야 한다.


# 참고 자료
---
- [https://stackoverflow.com/questions/13141302/implements-closeable-or-implements-autocloseable](https://stackoverflow.com/questions/13141302/implements-closeable-or-implements-autocloseable)
- [https://docs.oracle.com/javase/tutorial/essential/exceptions/tryResourceClose.html](https://docs.oracle.com/javase/tutorial/essential/exceptions/tryResourceClose.html)
- [https://docs.oracle.com/javase/8/docs/api/java/lang/AutoCloseable.html](https://docs.oracle.com/javase/8/docs/api/java/lang/AutoCloseable.html)
