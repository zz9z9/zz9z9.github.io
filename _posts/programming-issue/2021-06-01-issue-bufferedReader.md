---
title: BufferedReader의 readLine() 메서드에서 밑에 코드로 진행이 안된다.
date: 2021-06-01 00:29:00 +0900
categories: [개발 이슈]
tags: [JAVA I/O] # TAG names should always be lowercase
---

# 상황
---
- '자바 웹 프로그래밍 NextStep' 3장의 과제 중 하나인 웹 서버를 구현하기 위해 HTTP 요청이 서버에 어떤식으로 들어오는지를 보고싶었다.
- 따라서, 단순 확인을 위해 다음과 같은 코드를 작성하여 실행시키고 브라우저에서 localhost:8080 으로 요청을 보냈다.
```java
public class TestServer {
    public void start() throws IOException {
        ServerSocket serverSocket = new ServerSocket(8080);
        Socket connection;

        while((connection = serverSocket.accept()) !=null) {
            System.out.println(String.format("[connection info]%nIpAddr : %s, Port : %s%n", connection.getInetAddress(), connection.getPort()));
            BufferedReader br = new BufferedReader(new InputStreamReader(connection.getInputStream()));

            String line;
            while((line=br.readLine())!=null) {
                System.out.println(line); // 여기서 멈춘다
            }

            System.out.println("END!");
        }
    }

    public static void main(String[] args) throws IOException {
       TestServer server = new TestServer();
       server.start();
    }
}
```

- 아래와 같이 요청이 들어오는 것을 확인할 수 있었고, 'Http Method(GET, POST, ...)가 뭔지 확인하려면 요청의 첫 번째 라인을 확인하면 되겠구나' 등의 판단을 할 수 있었다.
![image](https://user-images.githubusercontent.com/64415489/123296071-49134900-d551-11eb-895a-2fc10875310f.png)

- 하지만, 문제는 코드의 15번째 라인 `System.out.println("END!");` 에 대한 출력이 콘솔에 찍히지 않았다는 것이었다.
디버거로 확인해보니 무한루프를 도는 것도 아니고 위 코드의 12번째 라인에서 대기 상태가 되는 것을 확인할 수 있었다.

# 해결 과정
---
- [스택오버플로우에 있는 글](https://stackoverflow.com/questions/7855822/bufferedreader-readline-method-hangs-and-block-program) 을 통해
BufferedReader의 readLine() 메서드는 라인이 종료되었다고 판단되지 않으면 값을 리턴하지 않는다는 것을 알게되었다.

- 그렇다면 라인이 종료되었다는 것을 판단하는 기준은 뭘까??
  - [자바 공식문서](https://docs.oracle.com/javase/8/docs/api/java/io/BufferedReader.html) 에 나와있는 readLine() 메서드에 대한 설명을 보면
끝에 개행 문자('\n', '\r', '\r\n') 중 하나가 있어야 하나의 라인으로 인식한다고 한다.
> <q> Reads a line of text. A line is considered to be terminated by any one of a line feed ('\n'), <br>
> a carriage return ('\r'), or a carriage return followed immediately by a linefeed. </q>

- 또한, BufferedReader의 readLine() 메서드를 직접 들여다보면 다음과 같은 로직이 있는 것을 확인할 수 있다. eol은 'end of line'이지 않을까 싶다.
```java
charLoop:
                for (i = nextChar; i < nChars; i++) {
                    c = cb[i];
                    if ((c == '\n') || (c == '\r')) {
                        eol = true;
                        break charLoop;
                    }
                }
```

> <q>Reads a line of text. A line is considered to be terminated by any one of a line feed ('\n'),
> a carriage return ('\r'), or a carriage return followed immediately by a linefeed.</q>

- 그렇다면, HTTP 요청의 마지막 라인이 어떻길래 아직 라인이 종료되었다고 판단하지 않는걸까 ?
  - [스택오버플로우에 있는 글](https://stackoverflow.com/questions/50447483/end-of-http-header)
  - [RFC 문서 34p](https://datatracker.ietf.org/doc/html/rfc2616#page-35)
  - HTTP 요청 형태 (HTTP 요청 헤더의 마지막 라인은 공백이었고 이로 인해 readLine() 메서드가 라인이 끝나지 않았다고 판단한 것)<br>
  - CRLF : Carriage Return(커서의 위치를 맨 앞으로 이동) + Line Feed(커서를 한 칸 아래로 이동)
<img src="https://user-images.githubusercontent.com/64415489/123300555-a9a48500-d555-11eb-885b-e25fd40b499a.png" width = "70%"/>

- 결과적으로 line이 공백이면 `"공백"`이라는 문자열을 출력해봄으로써 실제 HTTP 요청이 위와 같이 들어온다는 것을 알 수 있었고,<br>
공백인 경우 break를 통해 while문 내에서 계속 대기상태에 머물러있지 않게 할 수 있었다.
![image](https://user-images.githubusercontent.com/64415489/123302221-6fd47e00-d557-11eb-9a06-0e37d4e6b4f7.png)

# 배운 것
---
- HTTP 요청 형태
- BufferedReader의 readLine() 메서드가 라인을 인식하는 방법

# 더 공부해야할 부분
---
- JAVA I/O
- HTTP 응답 분할(HTTP Response Splitting, CRLF) 취약점

# 참고자료
---
- [https://stackoverflow.com/questions/7855822/bufferedreader-readline-method-hangs-and-block-program](https://stackoverflow.com/questions/7855822/bufferedreader-readline-method-hangs-and-block-program)
- [https://docs.oracle.com/javase/8/docs/api/java/io/BufferedReader.html](https://docs.oracle.com/javase/8/docs/api/java/io/BufferedReader.html)
- [https://stackoverflow.com/questions/50447483/end-of-http-header](https://stackoverflow.com/questions/50447483/end-of-http-header)
- [https://datatracker.ietf.org/doc/html/rfc2616](https://datatracker.ietf.org/doc/html/rfc2616)
