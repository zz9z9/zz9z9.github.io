---
title: try-with-resource 사용시 Socket closed 예외 발생
date: 2021-09-05 14:00:00 +0900
categories: [개발 일기]
tags: [Java, Socket]
---

# 상황
---
자바로 만든 간단한 웹 서버에서 404, 500과 같은 에러 페이지 처리를 위해 catch 절 내부에 에러 페이지를 응답하는 로직을 작성했다.
하지만 에러 발생시 에러 페이지가 응답되지 않고 `java.net.SocketException: Socket closed`가 발생했다.

```java
public class HttpServer {
    ...

    public void start() throws IOException {
        ExecutorService pool = Executors.newFixedThreadPool(NUM_THREADS);
        try (ServerSocket server = new ServerSocket(port)) {
            Socket connection;
            while ((connection = server.accept()) != null) {
                Runnable r = new HttpPageProcessor(connection);
                pool.submit(r);
            }
        }
    }
}
```

```java
public class HttpPageProcessor implements Runnable {

    @Override
    public void run() {
        try (InputStream inputStream = connection.getInputStream(); OutputStream outputStream = connection.getOutputStream()){
            httpReq = HttpUtils.getHttpRequest(inputStream);
            httpResp = HttpUtils.getHttpResponse(outputStream);

            ... 요청에 따라 알맞은 html 페이지 응답

        } catch (Exception e) {
            ... 에러 페이지 응답
        }
    }
    ...
}
```

# 원인
---
- 원인은 `try-with-resource` 사용으로 인해 `Socket`이 자동으로 닫히기 떄문이다.
  - 즉, catch절 내에서 에러 페이지 응답 로직을 수행하는데 필요한 소켓 커넥션이 이미 닫힌 상태이다.
- 근데 여기서 한가지 의문이 들었다.
  - **try() 내부에서 할당한 것은 `InputStream`과 `OutputStream`인데 왜 소켓도 닫히는거지 ?**
- 해답은 각각의 구현체인 `java.net.SocketInputStream`, `java.net.SocketOutputStream`에 있는 `close()` 메서드를 보면 알 수 있다.
  - `close()` 메서드 내부에서 소켓이 닫혔는지 여부를 확인하고 `socket.close()`를 호출하는 로직이 있다.
  - try 내부에서 `OutputStream`이 더 늦게 할당되므로 `SocketOutputStream.close()` 메서드가 먼저 호출된다.
  ```java
      private boolean closing = false;
      public void close() throws IOException {
          // Prevent recursion. See BugId 4484411
          if (closing)
              return;
          closing = true;
          if (socket != null) {
              if (!socket.isClosed())
                  socket.close();
          } else
              impl.close();
          closing = false;
      }
  ```

# 해결 과정
---
> try-catch-finally 사용

- 이렇게 해결하는게 맞는지는 모르겠으나, 일단 생각나는게 이것밖에 없어서 이렇게 해결해보았다.
- 추후에 더 나은 방법을 알게되면 업데이트 해야겠다.

```java
public class HttpPageProcessor implements Runnable {
    ...

    private void init() throws IOException {
        InputStream inputStream = connection.getInputStream();
        OutputStream outputStream = connection.getOutputStream());

        ... 객체 초기화
    }

    @Override
    public void run() {
        try {
            init();
             ... 요청에 따라 알맞은 html 페이지 응답
        } catch (Exception e) {
            ... 에러 페이지 응답
        } finally {
            try {
                connection.close();
            } catch (IOException e) {
                logger.error(e.getMessage(), e);
            }
         }
    }
    ...
}
```


# 참고 자료
---
- [https://stackoverflow.com/questions/1388602/do-i-need-to-close-both-filereader-and-bufferedreader](https://stackoverflow.com/questions/1388602/do-i-need-to-close-both-filereader-and-bufferedreader)
