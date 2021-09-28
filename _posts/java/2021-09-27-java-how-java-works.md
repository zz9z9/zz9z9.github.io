---
title: 자바 애플리케이션이 실행되는 과정 살펴보기
date: 2021-09-27 00:29:00 +0900
categories: [Java]
tags: [Java, JVM]
---

# 들어가기 전
---
자바 애플리케이션이 실행되는 과정을 간단히 도식화 하면 아래처럼 표현할 수 있을 것이다. 이를 ***컴파일***과 ***실행***이라는 두 단계로 나눠서, 각 단계별로 어떤 과정이 일어나는지 살펴보자.

<img src="https://user-images.githubusercontent.com/64415489/135147400-5589a7fd-4a0d-4016-b4ed-d7e5e2589525.png" width="85%"/>

※ 컴파일 파트는 [HomoEfficio 님의 블로그](https://homoefficio.github.io/2019/01/31/Back-to-the-Essence-Java-%EC%BB%B4%ED%8C%8C%EC%9D%BC%EC%97%90%EC%84%9C-%EC%8B%A4%ED%96%89%EA%B9%8C%EC%A7%80-1/#about)를 바탕으로 정리하였음을 미리 밝힙니다.

# 1. 컴파일
---
> javac 컴파일러에 의해 `자바 소스 코드 파일(.java) → JVM 바이트코드(.class)`로 변환되는 과정

- C와 같은 대부분의 다른 언어는 Intel 또는 HP 프로세서 관련 명령어와 같은 컴퓨터 관련 명령어로 컴파일된다.
- 하지만, Java 코드는 컴파일되면 플랫폼에 독립적인 표준 바이트코드 세트로 변환되며, 이 바이트코드는 JVM(Java Virtual Machine)에 의해 실행된다.
  - Java에서는 각 명령어가 1바이트의 균일한 크기를 가지므로 이러한 명령어를 **바이트코드**라고 한다.
- JVM 스펙의 `.class` 파일 구조에 맞는 바이트코드를 만들어 낼 수 있다면 어떤 언어든 JVM에서 실행될 수 있다.
  - 클로저(Clojure)나 스칼라, 코틀린 등이 JVM에서 실행될 수 있는 이유가 바로 여기에 있다.

## 컴파일 과정
> 컴파일을 크게 두 파트로 나누면 다음과 같다.
> - 자바 언어 스펙에 따라 자바 코드 분석/검증
> - JVM 스펙의 class 파일 구조에 맞는 바이트코드를 생성

### 1. 자바 언어 스펙에 따라 분석/검증
- 어휘 분석 (Lexical Analysis)
  - Lexical Analyzer(Lexer 또는 Tokenizer라고도 한다)가 소스 코드에서 문자 단위로 읽어서 어휘소(lexeme)를 식별하고 어휘소를 설명하는 토큰 스트림(Token Stream)을 생성한다.

- 구문 분석 (Syntax Analysis)
  - Syntax Analyzer(구문 분석기, Parser 라고도 한다)가 어휘 분석 결과로 나온 토큰 스트림이 언어의 스펙으로 정해진 문법 형식에 맞는지 검사해서, 맞지 않으면 컴파일 에러를 내고, 맞으면 Parse Tree를 생성한다.

- 의미 분석 (Symantic Analysis)
  - 타입 검사, 자동 타입 변환 등이 수행된다.
  - 예를 들어 다음과 같은 코드(`int a = "Hello";`)는 구문 분석 단계에서는 에러가 나지 않지만, 의미 분석 단계에서는 타입 검사가 수행되면서 에러가 발생한다.
  - 의미 분석 단계를 거치면서 Parse Tree에 타입 관련 정보 등이 추가된다.

### 2. JVM 스펙의 class 파일 구조에 맞는 바이트코드를 생성
- 중간 코드 생성 (Intermediate Code Generation)
  - 의미 분석 단계를 통과한 파스 트리를 바탕으로 기계어로 변환하기 좋은 형태의 중간 언어로 된 중간 코드를 생성한다.
  - 중간 단계를 하나 둬서 간접화를 통해 경우의 수를 낮추고 효율을 높일 수 있다.
    - 자바의 바이트코드가 중간 코드에 해당한다고 볼 수 있다.
    - 다음 그림에서 4개의 언어를 나타내는 네모를 각각 자바, 클로저(Clojure), 스칼라, 코틀린이라면, 녹색 네모는 바이트코드라고 할 수 있다.
  <figure align = "center">
    <img src = "https://user-images.githubusercontent.com/64415489/135106178-b7b035e1-8dbd-4c74-ac4d-9ac7a5a7c772.png" width="80%"/>
    <figcaption align="center">출처 : <a href="https://www.slideshare.net/RamchandraRegmi/intermediate-code-generationramchandra-regmi">https://www.slideshare.net/RamchandraRegmi/intermediate-code-generationramchandra-regmi/</a></figcaption>
  </figure>

- 중간 코드 최적화 (Code Optimization)
  - 중간 코드가 더 효율적인 기계어로 변환되도록 최적화하는 과정이다.
  - 다음과 같이 매우 다양한 최적화 기법이 사용된다.
    - 핍홀(Peephole) 최적화
    - 지역 최적화
    - 루프 최적화
    - 전역 최적화

# 2. 실행
---
> `java [options] mainclass [args...] `로 자바 애플리케이션을 실행할 수 있다. `java` 명령어를 실행하게 되면
> 1. JRE(Java Runtime Environment)를 시작 (바이트코드 실행)
> 2. 지정된 클래스를 로드
> 3. 해당 클래스의 main() 메서드를 호출하여 애플리케이션 실행 <br>

**위에서 살펴본 과정은 JVM이 담당하게 된다. JVM이 무엇이고 어떻게 해당 과정을 수행하는지 살펴보자.** <br>

## JVM(Java Virtual Machine)이란 ?
> [공식 문서](https://docs.oracle.com/cd/E11882_01/java.112/e10588/chone.htm#JJDEV13017)에서는 JVM을 다음과 같이 표현한다. <br>
> <q>A JVM is a separate program that is optimized for the specific platform on which you run your Java code.</q> <br>
> → "JVM은 Java 코드를 실행하는 **특정 플랫폼에 최적화된** 별도의 프로그램이다."

- 자바 애플리케이션을 개발할 때 자바 언어로 작성된 사전 정의된 core class library를 사용한다.
- core class library는 일반적으로 사용되는 기능을 제공하는 패키지이다.
  - 예를 들어, 기본 언어 지원은 `java.lang`, I/O 지원은 `java.io`, 네트워크 접근은 `java.net` 패키지를 통해 제공된다.
- JVM과 core class library는 자바를 지원하는 모든 운영 체제에서 **자바 애플리케이션을 개발할 수 있는 플랫폼**을 제공한다.
  - 이를 통해 자바의 핵심 사상인 **"write once, run anywhere"(WORA)**가 가능해진다.
  ![image](https://user-images.githubusercontent.com/64415489/135127896-365f33d9-8022-4070-ad49-93e45a6b5112.png)
- 자바를 다운받을 때, 운영체제 별로 나뉘어져 있는 것을 생각해보면 쉽게 와닿을 것 같다.
![image](https://user-images.githubusercontent.com/64415489/135125540-a9fc02df-3d78-43b4-9a39-e07b0a4382fa.png)


## JVM이 바이트코드를 실행하기까지
> JVM의 구성요소를 살펴보면서 어떻게 실행되는지 알아보자.

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/135129315-6f93493a-71c5-4d3a-a1d5-325a64d68208.png" width="80%"/>
  <figcaption align="center">출처 : <a href="https://www.geeksforgeeks.org/jvm-works-jvm-architecture/">https://www.geeksforgeeks.org/jvm-works-jvm-architecture/</a></figcaption>
</figure>

### 1. Class Loader : Loading, Linking, Initializing
> JVM은 클래스와 인터페이스를 동적으로 로드, 연결 및 초기화한다.

#### Loading
> 특정 이름을 가진 클래스, 인터페이스 타입의 이진 표현을 바탕으로 클래스, 인터페이스를 만드는 과정이다.

- 클래스 로더는 `.class` 파일을 읽고 해당 파일에 대한 이진 데이터를 Method Area에 저장한다.
- JVM은 각 `.class` 파일에 대해 다음 정보를 Method Area에 저장한다.
  - 로드된 클래스 및 해당 직계 부모 클래스의 정규화된(fully qualified) 이름
  ```java
  public class Demo {
     public static void main(String[] argv) throws Exception {
        Class c = java.util.ArrayList.class;
        String className = c.getName();
        System.out.println("The fully-qualified name of the class is: " + className);
        // The fully-qualified name of the class is: java.util.ArrayList
     }
  }
  ```
  - `.class` 파일이 `Class`, `Interface` 또는 `Enum`과 관련이 있는지 여부
  - 수정자(`public`, `final`, `static`, ...), 변수, 메서드 정보 등

- `.class` 파일을 로드한 후 JVM은 이 파일을 힙 메모리에 나타내기 위해 `Class` 타입의 객체를 생성한다.
- 이 객체는 `java.lang` 패키지에 미리 정의된 `java.lang.Class<T>`이다.
- `Class` 객체는 클래스 이름, 부모 이름, 메서드 및 변수 정보 등과 같은 클래스 레벨의 정보를 얻는 데 사용할 수 있다.
- 이 객체 참조를 얻으려면 `Object.getClass()` 메서드를 사용한다.
- 로드된 모든 `.class` 파일에 대해 하나의 클래스 객체만 생성된다.

#### Linking
> 클래스, 인터페이스를 결합하여 JVM이 실행할 수 있는 상태로 만드는 과정이다. <br>
> verification, preparation, (선택적으로) resolution을 수행한다.

- Verification
  - `.class` 파일의 정확성을 보장한다.
    - 즉, 올바른 형식으로 올바른 컴파일러에 의해 생성되었는지 여부를 확인한다.
  - 검증에 실패하면 런타임 예외 `java.lang.VerifyError`가 발생한다.
    - 이 과정은 'ByteCodeVerifier' 컴포넌트에 의해 수행된다.
  - 검증이 완료되면 `class.`파일을 (기계어로) 컴파일할 준비가 된 것이다.

- Preparation
  - JVM은 클래스 변수에 메모리를 할당하고 메모리를 기본값으로 초기화한다.

- Resolution
  - 타입의 심볼릭 레퍼런스를 direct 레퍼런스로 바꾸는 과정이다.
  - 참조된 엔터티를 찾기 위해 메서드 영역을 탐색한다.


#### Initialization
> 클래스 또는 인터페이스의 초기화 메서드를 실행하는 것이다.

- 이 단계에서 모든 `static` 변수는 코드 및 `static block`(있는 경우)에 정의된 값으로 할당됩니다.
- 클래스에서는 위에서 아래로, 클래스 계층에서는 부모에서 자식 순서로 실행된다.

### 참고. 클래스 로더 구성
> 일반적으로, 세 가지 클래스 로더로 구성된다.

- Bootstrap class loader
  - `JAVA_HOME/jre/lib` 디렉토리에 있는 핵심 Java API 클래스를 로드한다.
    - 이 경로는 일반적으로 부트스트랩 경로로 알려져있다.
    - C, C++ 등의 native 언어로 구현되어 있다.
  - 모든 JVM 구현에는 신뢰할 수 있는 클래스를 로드할 수 있는 부트스트랩 클래스 로더가 있어야한다.

- Extension class loader
  - 부트스트랩 클래스 로더의 자식이다.
  - `JAVA_HOME/jre/lib/ext`(확장 경로) 또는 `java.ext.dirs` 시스템 속성에 의해 지정된 다른 디렉토리에 있는 클래스를 로드한다.
  - 자바에서는 `sun.misc.Launcher$ExtClassLoader` 클래스에 의해 구현된다.

- System/Application class loader
  - 확장 클래스 로더의 자식입니다.
  - 애플리케이션 `classpath`에서 클래스를 로드하는 역할을 수행한다.
  - 내부적으로 `java.class.path`에 매핑된 환경 변수를 사용한다.
  - 자바에서는 `sun.misc.Launcher$AppClassLoader` 클래스에 의해 구현된다.

```java
public class Test {
    public static void main(String[] args)
    {
        // String class is loaded by bootstrap loader, and
        // bootstrap loader is not Java object, hence null
        System.out.println(String.class.getClassLoader()); // null

        // Test class is loaded by Application loader
        System.out.println(Test.class.getClassLoader()); // jdk.internal.loader.ClassLoaders$AppClassLoader@8bcc55f
    }
}
```

- JVM은 Delegation-Hierarchy 원칙에 따라 클래스를 로드한다.
- 시스템 클래스 로더는 확장 클래스 로더에 로드 요청을 위임하고, 확장 클래스 로더는 부트스트랩 클래스 로더에 요청을 위임한다.
- 부트스트랩 경로에 클래스가 있는 경우 해당 클래스가 로드되지 않으면 다시 요청을 확장 클래스 로더로 전송한 다음 시스템 클래스 로더로 전송한다.
- 마지막으로 시스템 클래스 로더가 클래스 로드에 실패하면 런타임 예외 `java.lang.ClassNotFoundException`이 발생한다.

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/135138502-e98e346b-9bfe-4fef-858a-aaddf838e213.png" width="80%"/>
  <figcaption align="center">출처 : <a href="https://www.geeksforgeeks.org/jvm-works-jvm-architecture/">https://www.geeksforgeeks.org/jvm-works-jvm-architecture/</a></figcaption>
</figure>

### 2. Runtime Data Arae(JVM Memory)
[해당 내용과 관련하여 정리했던 포스팅](https://zz9z9.github.io/posts/java-variable-type-and-jvm-memory/)을 참조하면 될 것 같다.

### 3. Execution Engine
> 바이트 코드를 한 줄씩 읽어들여 다양한 메모리 영역에 있는 데이터와 정보를 바탕으로 명령을 실행한다. <br>
> 크게 Interpreter, JIT Compiler, Garbage Collector 세 부분으로 구성된다.

#### Interpreter
- 바이트코드를 한 줄씩 해석하여 실행한다.
- 같은 메서드를 여러 번 호출하는 경우, 매번 해석이 필요하기 때문에 비효율적이다.

#### JIT Compiler
- 인터프리터의 효율성을 높이기 위해 사용합니다.
- 전체 바이트 코드를 컴파일하여 네이티브 코드로 변경한다.
  - 인터프리터가 반복되는 메서드를 호출할 때마다 해당 부분에 대해 JIT가 네이티브 코드를 제공한다.
  - 결과적으로, 재해석이 필요하지 않으므로 효율성이 향상된다.

#### Garbage Collector
- 더 이상 참조되지 않는 객체를 제거한다.

### 4. Java Native Interface (JNI)
- Native Method Libraries와 연동하여 실행에 필요한 Native Library(C, C++)를 제공하는 인터페이스이다.
- JVM이 C/C++ 라이브러리를 호출할 수 있고, 하드웨어 전용 C/C++ 라이브러리에 의해 호출될 수도 있다.


### 5. Native Method Libraries
- Execution Engine에서 필요로 하는 Native Libraries(C, C++)의 모음이다.

# 더 공부할 부분
---
- JIT Compiler
- Garbage Collector
- 바이트코드

# 참고 자료
---
- [https://docs.oracle.com/cd/E11882_01/java.112/e10588/chone.htm#JJDEV13018](https://docs.oracle.com/cd/E11882_01/java.112/e10588/chone.htm#JJDEV13018)
- [https://homoefficio.github.io/2019/01/31/Back-to-the-Essence-Java-%EC%BB%B4%ED%8C%8C%EC%9D%BC%EC%97%90%EC%84%9C-%EC%8B%A4%ED%96%89%EA%B9%8C%EC%A7%80-1/](https://homoefficio.github.io/2019/01/31/Back-to-the-Essence-Java-%EC%BB%B4%ED%8C%8C%EC%9D%BC%EC%97%90%EC%84%9C-%EC%8B%A4%ED%96%89%EA%B9%8C%EC%A7%80-1/)
- [https://homoefficio.github.io/2019/01/31/Back-to-the-Essence-Java-%EC%BB%B4%ED%8C%8C%EC%9D%BC%EC%97%90%EC%84%9C-%EC%8B%A4%ED%96%89%EA%B9%8C%EC%A7%80-2/](https://homoefficio.github.io/2019/01/31/Back-to-the-Essence-Java-%EC%BB%B4%ED%8C%8C%EC%9D%BC%EC%97%90%EC%84%9C-%EC%8B%A4%ED%96%89%EA%B9%8C%EC%A7%80-2/)
- [https://docs.oracle.com/en/java/javase/11/tools/java.html#GUID-3B1CE181-CD30-4178-9602-230B800D4FAE](https://docs.oracle.com/en/java/javase/11/tools/java.html#GUID-3B1CE181-CD30-4178-9602-230B800D4FAE)
- [https://docs.oracle.com/javase/specs/jvms/se11/html/jvms-5.html#jvms-5.2](https://docs.oracle.com/javase/specs/jvms/se11/html/jvms-5.html#jvms-5.2)
- [https://www.geeksforgeeks.org/jvm-works-jvm-architecture/](https://www.geeksforgeeks.org/jvm-works-jvm-architecture/)
