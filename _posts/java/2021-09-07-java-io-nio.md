---
title: 자바 IO, NIO
date: 2021-09-07 00:29:00 +0900
categories: [Java]
tags: [Java, IO, NIO]
---

# Java I/O
---
> Input, Output을 나타낸다. In, Out의 기준은 JVM이다. 즉, JVM으로 들어오는 데이터를 다루는 경우엔 Input 데이터를 내보내는 경우엔 Output이다.

- Stream 기반이다.
  - 한 번에 1byte 또는 그 이상의 byte를 읽는다.
  - 데이터가 캐시되지 않는다. 따라서 데이터의 앞뒤로 이동할 수 없다.
  - 만약, 데이터에서 앞뒤로 이동해야 하는 경우 먼저 버퍼에 캐시해야 한다.
- blocking 방식이다.
  - 즉, 스레드가 `read()` 또는 `write()`를 호출하면 읽을 데이터가 있거나 데이터가 완전히 쓰여질 때까지 해당 스레드는 다른 작업을 수행할 수 없다.
- 크게 `InputStream/OutputStream`, `Reader/Writer`로 구분된다.


## java.io.InputStream
> 바이트 기반 입력 스트림의 최상위 클래스이며 추상클래스이다.

- 추상 클래스이다.
- `Closeable` 인터페이스를 구현한다.
  - 즉, java.io 패키지에 있는 클래스를 사용할 때에는 하던 작업이 종료되면 해당 리소스를 `close()` 메서드로 항상 닫아주어야 한다.
  - 여기서 리소스는 파일, 네트워크 연결 등이 될 수 있다.
- 주요 하위 클래스로는 `FileInputStream`, `DataInputStream`, `ObjectInputStream`, `BufferedInputStream` 등이 있다.

## java.io.OutputStream
> 바이트 기반 출력 스트림의 최상위 클래스이며 추상클래스이다.

- Closeable, Flushable 인터페이스를 구현한다.
- Flushable에는 `flush()` 메서드만 정의되어 있다.
  - 일반적으로 어떤 리소스에 데이터를 쓸 때, 쓰기 작업을 요청할 때마다 저장하는 방식으로 하게되면 효율이 떨어진다.
  - 따라서, 버퍼(buffer)를 갖고 데이터를 쌓아두었다가 어느정도 차게 되면 한번에 쓰는 것이 좋다.
  - `flush()` 메서드는 버퍼에 있는 데이터를 기다리지 말고 무조건 저장하게 만드는 기능을 수행한다.
- 주요 하위 클래스로는 `FileOutputStream`, `DataOutputStream`, `ObjectOutputStream`, `BufferedOutputStream` 등이 있다.

## java.io.Reader
> 문자 기반 입력 스트림의 최상위 클래스이며 추상클래스이다.

- `public abstract class Reader implements Readable, Closeable`
- 주요 하위 클래스로는 `FileReader`, `InputStreamReader`, `BufferedReader` 등이 있다.

## java.io.Writer
> 문자 기반 출력 스트림의 최상위 클래스이며 추상클래스이다.

- `public abstract class Writer implements Appendable, Closeable, Flushable`
- 주요 하위 클래스로는 `FileWriter`, `OutputStreamWriter`, `PrinterWriter`,  `BufferedWriter` 등이 있다.

## Blocking 방식 살펴보기
```
Name: Anna
Age: 25
Email: anna@mailserver.com
Phone: 1234567890
```

- 위 텍스트 파일을 읽는 프로그램을 작성해보자.

```java
InputStream input = ... ; // get the InputStream from the client socket

BufferedReader reader = new BufferedReader(new InputStreamReader(input));

String nameLine   = reader.readLine();
String ageLine    = reader.readLine();
String emailLine  = reader.readLine();
String phoneLine  = reader.readLine();
```

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/132817635-8b2368ea-877d-4c47-b2b4-d116cfe7c29c.png" width="70%"/>
  <figcaption align="center">출처 : <a href="http://tutorials.jenkov.com/java-nio/nio-vs-io.html#main-differences-between-java-nio-and-io" target="_blank"> http://tutorials.jenkov.com/java-nio/nio-vs-io.html#main-differences-between-java-nio-and-io</a> </figcaption>
</figure>


# New IO
> java.nio 패키지는 Java 1.4에서 처음 도입되었으며 향상된 파일 작업 및 `ASynchronousSocketChannel`는 Java 1.7(NIO.2)에서 업데이트되었다.

- 스트림 기반 → 버퍼(Buffer)와 채널(Channel) 기반으로 데이터 처리
  - NIO에서 데이터를 주고 받을 때는 버퍼를 통해서 처리한다.

- 버퍼 기반 데이터 처리
  - 데이터는 버퍼로 읽혀지고 나중에 처리된다.
  - 필요에 따라 버퍼에서 앞뒤로 이동할 수 있습니다. 이를 통해 처리 중에 유연성을 높일 수 있다.
  - 버퍼를 완전히 처리하려면 필요한 모든 데이터가 버퍼에 포함되어 있는지 확인해야 한다.
  - 또한 버퍼로 더 많은 데이터를 읽을 때 아직 처리하지 않은 버퍼의 데이터를 덮어쓰지 않도록 해야한다.

- Non-Blocking
  - 스레드는 채널에 데이터 읽기를 요청할 수 있으며 현재 사용 가능한 데이터만 가져오거나 현재 사용 가능한 데이터가 없는 경우 아무 것도 가져오지 않는다.
  - 데이터를 읽을 수 있을 때까지 blocking 상태를 유지하는 대신 스레드는 다른 작업을 계속할 수 있다.
  - 스레드는 일부 데이터가 채널에 기록되도록 요청할 수 있지만, 데이터가 완전히 기록되기를 기다리지는 않는다.
  - 그런 다음 스레드는 계속해서 중간에 다른 작업을 수행할 수 있다.
  - IO 호출에서 차단되지 않을 때 스레드가 유휴 시간을 보내는 것은 일반적으로 그 동안 다른 채널에서 IO를 수행하는 것이다.
  - 즉, 단일 스레드가 여러 입력 및 출력 채널을 관리할 수 있다.

- `bufferFull()` 메서드는 버퍼에 읽어들인 데이터의 양을 추적하고 버퍼가 가득 찼는지 여부에 따라 true 또는 false를 반환해야한다. 즉, 버퍼가 처리할 준비가 되면 가득 찬 것으로 간주된다.
- `bufferFull()` 메서드는 버퍼를 스캔하지만 메서드가 호출되기 전과 동일한 상태로 버퍼를 유지해야 한다. 그렇지 않으면 버퍼로 읽은 다음 데이터가 올바른 위치에서 읽히지 않을 수 있다.

```java
ByteBuffer buffer = ByteBuffer.allocate(48);

int bytesRead = inChannel.read(buffer);

while(! bufferFull(bytesRead) ) {
    bytesRead = inChannel.read(buffer);
}
```

- 위 코드를 다음과 같은 다이어그램으로 나타낼 수 있다.

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/132822109-db59cd0d-40c3-4b85-b4cb-2e3eb1d0fcb3.png" width="70%"/>
  <figcaption align="center">출처 : <a href="http://tutorials.jenkov.com/java-nio/nio-vs-io.html#main-differences-between-java-nio-and-io" target="_blank"> http://tutorials.jenkov.com/java-nio/nio-vs-io.html#main-differences-between-java-nio-and-io</a> </figcaption>
</figure>


## Java NIO 주요 컴포넌트
> Java NIO는 Buffer, Channel, Selector를 기반으로 새로운 I/O 모델을 제공한다.

### 1. Buffer
- NIO에서 제공하는 Buffer는 `java.nio.Buffer` 클래스를 확장하여 사용한다.
- 기본 데이터 유형에 대해 버퍼를 사용할 수 있습니다. Java NIO는 버퍼 지향 패키지이다.
  - 즉, 채널을 사용하여 추가 처리된 버퍼에 데이터를 쓰거나 읽을 수 있다.
  - ByteBuffer, CharBuffer, DoubleBuffer 등 다양한 타입의 버퍼가 존재한다.
- 버퍼는 기본 데이터 유형을 보유하고 다른 NIO 패키지에 대한 개요를 제공하므로 데이터의 컨테이너 역할을 한다.
  - 버퍼는 채우기, 비우기, 뒤집기, 되감기 등을 할 수 있다.

- 위치와 관련된 메서드
  - `position()` : 현재의 위치를 나타냄
  - `limit()` : 읽거나 쓸 수 없는 위치를 나타냄
  - `capacity()` : 버퍼의 크기를 나타냄
  - `0 <= position <= limit <= capacity`

- 예제 코드

```java
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.channels.FileChannel;


public class NioSample {
    public static void main(String[] args) {
        NioSample sample = new NioSample();
        sample.basicWriteAndRead();
    }

    public void basicWriteAndRead() {
        String fileName = "nio.txt";
        try {
            writeFile(fileName, "My first NIO sample");
            readFile(fileName);
        } catch (IOException e) {
            e.printStackTrace();
        }
    }

    private void writeFile(String fileName, String data) throws IOException {
        FileChannel channel = new FileOutputStream(fileName).getChannel(); // 파일을 쓰기 위한 채널 얻어오기
        byte[] byteData = data.getBytes();
        ByteBuffer buffer = ByteBuffer.wrap(byteData); // ByteBuffer 객체 생성
        channel.write(buffer); // 버퍼를 이용해서 파일 생성
        channel.close();
    }


    private void readFile(String fileName) throws IOException {
        FileChannel channel = new FileInputStream(fileName).getChannel(); // 파일을 읽기 위한 채널 얻어오기
        ByteBuffer buffer = ByteBuffer.allocate(1024);
        channel.read(buffer); // 버퍼를 넘겨줌으로써 데이터를 해당 버퍼에 담게된다.
        buffer.flip(); // 버퍼에 담겨있는 데이터의 가장 앞으로 이동

        while (buffer.hasRemaining()) {
            System.out.print((char) buffer.get());
        }

        channel.close();
    }
}
```

### 2. Channel
- 채널은 외부 세계와 통신하는 데 사용되는 스트림과 같다.
- 채널에서 버퍼로 데이터를 읽거나 버퍼에서 채널로 데이터를 쓸 수 있다.
- Java NIO는 non-blocking I/O 작업을 수행하며 이러한 I/O 작업에 채널을 사용할 수 있다.
- 서로 다른 엔티티에 대한 연결은 논블로킹 I/O 동작을 수행할 수 있는 다양한 채널로 표현된다.
- 채널은 중간 매체 또는 게이트웨이로 작동한다.

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/132728702-13122fc3-2e5b-49d7-a5f6-97472806b856.png" width="80%"/>
  <figcaption align="center">출처 : <a href="https://www.geeksforgeeks.org/introduction-to-java-nio-with-examples/" target="_blank"> https://www.geeksforgeeks.org/introduction-to-java-nio-with-examples/</a> </figcaption>
</figure>


### 3. Selector
- Selector를 통해 non-blocking I/O가 가능하다.
- Selector는 이벤트에 대해 여러 채널을 모니터링한다.
- 하나의 Selector를 사용해서 다수의 channels를 등록할 수 있다.
- 하나의 스레드를 사용해서 input을 처리할 수 있는 channel, writing을 위해 준비된 channel을 선택할 수 있다.
  - 즉, Selector는 I/O 작업을 위해 준비된 채널을 선택하는 데 사용된다.
- 결과적으로, 하나의 스레드 여러 개의 channel을 쉽게 관리할 수 있게된다.
  - 다수의 스레드로 IO를 관리하는 방식에 비해 스레드 간의 context switching을 줄여준다.

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/132728835-a48159c4-cddc-42ea-b72e-349ca9629183.png" width="80%"/>
  <figcaption align="center">출처 : <a href="https://www.geeksforgeeks.org/introduction-to-java-nio-with-examples/" target="_blank"> https://www.geeksforgeeks.org/introduction-to-java-nio-with-examples/</a> </figcaption>
</figure>


# Java I/O는 내부적으로 어떻게 동작할까 ?
---
## Buffer Handling and Kernel vs User Space
<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/132784262-d141cbf3-c7f1-4c35-bfb7-50d36ebbcc95.png" width="90%"/>
  <figcaption align="center">출처 : <a href="https://howtodoinjava.com/java/io/how-java-io-works-internally/" target="_blank"> https://howtodoinjava.com/java/io/how-java-io-works-internally/</a> </figcaption>
</figure>

- 위의 이미지는 블록 데이터가 하드 디스크와 같은 외부 소스에서 실행 중인 프로세스 내부의 메모리 영역(예: RAM)으로 이동하는 방식에 대한 단순화된 '논리적' 다이어그램을 나타낸다.

1. 프로세스는 `read()` 시스템 호출을 통해 버퍼를 채우도록 요청한다.
- 사용자 프로세스는 User Space에서 동작하기 때문에 하드웨어에 직접적으로 접근할 수 없다. 따라서, OS에서 제공하는 시스템콜을 통해 I/O를 수행해야 한다.
- read() 시스템콜을 통해 커널에게 I/O 수행을 요청한다.
  - 이 과정에서 유저 모드(User mode)에서 커널 모드(Kernal mode)로 스위칭이 발생한다.
- 제어권을 넘겨받은 커널은 우선 프로세스가 요청한 데이터가 이미 커널 영역 캐시 메모리에 존재하는지 확인한다.
  - 만일 데이터가 캐시에 존재한다면 해당 데이터를 read() 함수 호출 시 전달받은 메모리 영역에 복사한 뒤 제어권을 다시 사용자 프로세스에게 넘긴다.(커널 모드 -> 유저 모드로 스위칭)
  - 데이터가 캐시에 존재하지 않는다면 디스크로부터 데이터를 가져오는 과정을 수행한다.

2. 읽기 호출은 커널이 디스크 컨트롤러 하드웨어에 명령을 실행하여 디스크에서 데이터를 가져오도록 한다.
- 이는 CPU가 디스크보다 수백배는 빠르기 때문에, 디스크의 처리 시간을 기다리는 것이 낭비이기 때문이다.

3. 디스크 컨트롤러는 CPU의 추가 지원 없이 DMA를 통해 데이터를 커널 메모리 버퍼에 직접 쓴다.
4. 디스크 컨트롤러가 버퍼 채우기를 마치면 커널은 커널 공간의 임시 버퍼에서 프로세스가 지정한 버퍼로 데이터를 복사한다.
5. read() 과정이 종료되면서, 사용자 프로세스는 Block 되어 있던 메서드가 완료되며 요청한 데이터를 사용할 수 있게 된다.

## Arguments
- 위에서 살펴봤듯이, Java I/O의 경우 커널 메모리를 직접 접근하는 것이 아닌 JVM에 데이터를 copy하는 작업 로직이 포함되어 있기 때문에 비효율적이다는 의견이 있다.
  - CPU가 개입하여 커널 영역 메모리의 데이터를 사용자 영역으로 옮기며 오버헤드가 발생한다.
  - 이 과정에서 생성된 Java의 객체들은 GC 대상이 된다.
- 일반적으로 DMA를 하게되면 CPU 자원사용 없이 직접적인 메모리 접근을 하기 때문에 CPU 오버헤드가 없으며 CPU 자원 점유가 없는 non-blocking 수행이 가능하다는 이점이 있다.
  - java.nio 에서는 사용자 영역상에 Buffer를 만들어 사용하는것이 아닌 커널영역에 Buffer를 만들어 직접 DMA를 할 수 있도록 제공하고 있다.
  - 따라서, java.nio를 사용하는것이 java.io를 사용하는 것 보다 일반적으로 성능적으로 뛰어나다고 알려져있다.
  - 하지만, 항상 그런 것만은 아니다. [관련 글](https://taes-k.github.io/2021/01/06/java-nio/)

### cf) DMA(Direct memory access)
> DMA는 특정 하드웨어 하위 시스템이 CPU와 독립적으로 RAM에 액세스할 수 있도록 하는 기능이다.

- DMA가 없으면 CPU가 프로그래밍된 입출력을 사용할 때, 일반적으로 읽기 또는 쓰기 작업의 전체 시간 동안 완전히 사용되므로 다른 작업을 수행할 수 없다.
  - 따라서, CPU는 먼저 DMA 전송을 시작하고, 전송이 진행되는 동안 다른 작업을 수행한다.
  - 작업이 완료되면 DMA 컨트롤러로부터 인터럽트를 수신한다.
- 이 기능은 CPU가 데이터 전송 속도를 따라가지 못하거나 CPU가 상대적으로 느린 I/O 데이터 전송을 기다리는 동안 작업을 수행해야 할 때 유용하다.

# 참고 자료
---
- 이상민, 『자바의 신 2』, 로드북(2017), 26,27장
- [https://www.baeldung.com/java-io-vs-nio](https://www.baeldung.com/java-io-vs-nio)
- [http://tutorials.jenkov.com/java-nio/nio-vs-io.html#main-differences-between-java-nio-and-io](http://tutorials.jenkov.com/java-nio/nio-vs-io.html#main-differences-between-java-nio-and-io)
- [https://www.geeksforgeeks.org/introduction-to-java-nio-with-examples/](https://www.geeksforgeeks.org/introduction-to-java-nio-with-examples/)
- [https://howtodoinjava.com/java/io/how-java-io-works-internally/](https://howtodoinjava.com/java/io/how-java-io-works-internally/)
- [https://taes-k.github.io/2021/01/06/java-nio/](https://taes-k.github.io/2021/01/06/java-nio/)
- [https://leeyh0216.github.io/posts/java_nio_why_java_io_slow/](https://leeyh0216.github.io/posts/java_nio_why_java_io_slow/)
- [https://en.wikipedia.org/wiki/Direct_memory_access](https://en.wikipedia.org/wiki/Direct_memory_access)
