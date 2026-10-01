
## JVM 구성요소
- Class Loader
- JVM Memory
- Execution Engine
  - Interpreter
    - 바이트코드 한줄씩 해석
  - JIT Compiler
    - 전체 바이트 코드를 컴파일하여 네이티브 코드로 변경한다.
    - 인터프리터가 반복되는 메서드를 호출할 때마다 해당 부분에 대해 JIT가 네이티브 코드를 제공한다.
    - 결과적으로, 재해석이 필요하지 않으므로 효율성이 향상된다.
  - GC
- Java Native Interface (JNI)
- Native Method Libraries

## JVM 메모리(Runtime Data Areas)
- JVM 단위 : JVM을 시작할 때 생성되며 JVM이 종료될 때 삭제되는 데이터 영역.
  - Heap
  - Method Area
  - JVM 단위의 데이터 영역은 모든 스레드 간에 공유된다.

- 스레드 단위 : 스레드가 생성될 때 만들어지고 스레드가 종료될 때 삭제되는 데이터 영역.
  - PC Register
  - JVM Stack
  - Native Method Stack

- 메서드 영억
  - JVM의 특정 구현에 따라 GC 대상이 되기도 하고, 되지 않기도 합니다.
  - 런타임 상수 풀, 필드와 메서드 데이터, 생성자 및 메서드의 코드와 같은 클래스 단위의 데이터

- PC Register
  - JVM은 한 번에 여러 스레드의 실행을 지원할 수 있다. 따라서 각 스레드에는 자체 PC(프로그램 카운터) 레지스터가 있다.
  - 각 JVM 스레드는 단일 메서드의 코드, 즉 해당 스레드의 현재 메서드를 실행한다.
  - 이 메서드가 native가 아닌 경우 pc 레지스터에는 현재 실행 중인 JVM 명령의 주소를 저장한다.
  - 스레드에서 현재 실행 중인 메서드가 native이면 JVM의 pc 레지스터 값이 정의되지 않는다.

### Java 버전별 JVM 메모리 구조 변경 사항
**Java 7 (JDK 1.7) 이전**
- 메서드 영역 (Method Area): HotSpot JVM에서 Permanent Generation (PermGen) 영역을 사용하여 클래스 메타데이터를 저장.
- PermGen 특징:
  - 클래스 메타데이터, 런타임 상수 풀, 메서드 정보 등을 저장.
  - 크기 조정이 어려워 OutOfMemoryError 발생 가능 (java.lang.OutOfMemoryError: PermGen space).

**Java 8 (JDK 1.8)**
- PermGen 제거 → Metaspace 도입
  - 메서드 영역이 Metaspace로 변경됨.
  - Metaspace는 네이티브 메모리에서 할당되며, 기본적으로 제한 없음 (설정 가능).
  - XX:MaxMetaspaceSize 옵션으로 최대 크기 설정 가능.
  - PermGen을 제거하면서 java.lang.OutOfMemoryError: Metaspace가 발생할 수도 있음.
- String Pool 위치 변경
  - **기존에는 PermGen에 있던 String Pool이 Heap 영역으로 이동.**

### Constant Pool vs String Pool
- Constant Pool은 클래스 파일 내 상수 정보를 저장하는 공간.
  - 클래스 파일 내에 존재하며, 클래스 로딩 시 Method Area (Java 8 이후 Metaspace)로 올라감.
  - 숫자 리터럴, 메서드 참조, 필드 참조 등 JVM이 실행하는데 필요한 다양한 상수값을 저장함.
- String Pool은 Heap 영역에서 문자열 리터럴을 공유하는 공간.
  - 문자열 리터럴(String Literal)은 소스 코드에 직접 작성된 문자열 값을 의미해.  자바에서는 쌍따옴표(" ")로 감싸진 문자열이 문자열 리터럴이야.
- String 리터럴 ("Hello")은 Constant Pool에도 저장되지만, 문자열 값 자체는 String Pool에서 관리됨.

```java
public class Test {
    public static final int NUM = 100;  // Constant Pool에 저장됨
    public static final String TEXT = "Hello"; // String Pool에 저장됨
}
```

```java
public class StringPoolTest {
    public static void main(String[] args) {
        String s1 = "hello";  // String Pool에 저장
        String s2 = "hello";  // 기존 "hello" 재사용
        String s3 = new String("hello");  // Heap에 새로운 객체 생성

        System.out.println(s1 == s2);  // true (같은 객체)
        System.out.println(s1 == s3);  // false (다른 객체)
    }
}
```

**※ static 사용시 ?**

```java
public class Example {
    static String str1 = "hello";   // 문자열 리터럴
    static String str2 = new String("world");  // new String() 사용
}
```

- str1 (static 변수)	: Method Area (클래스 변수 저장 영역)	참조값 저장
- "hello" (리터럴)	: String Pool (Heap 내부 영역)	문자열 값 저장
- str2 (static 변수)	: Method Area	참조값 저장
- new String("world")	: Heap (일반 객체 영역)	새로운 객체 생성
