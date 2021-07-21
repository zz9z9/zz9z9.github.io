---
title: 자바 힙 메모리 사이즈와 OutOfMemoryError
date: 2021-07-20 23:00:00 +0900
categories: [Java]
tags: [Java, Heap Memory]
---

지금까지 OutOfMemoryError(OOM)을 만나게 되면, 정확한 진단없이 그냥 성능 팀에서 하라는 대로 Xms, Xmx 옵션을 활용해서 힙 크기를 조절했던 것 같다.
내가 스스로 판단할 수 있게끔 지식을 갖추고 연습해보자.

# 힙 메모리 사이즈
---
## 기본값
- [공식 문서](https://docs.oracle.com/javase/8/docs/technotes/guides/vm/gc-ergonomics.html) 에 보면 default로 세팅되는 초기 힙사이즈와 최대 힙사이즈에 대해 나와있다.
- 결론부터 얘기하면, 초기 힙사이즈는 물리 메모리의 1/64, 최대 힙사이즈는 물리 메모리의 1/4이다.
- 나의 경우 RAM이 32G 이므로, 초기 힙사이즈, 최대 힙사이즈는 각각 500MB, 8GB 정도가 나와야할 것이다.
- 아래의 `InitialHeapSize`와 `MaxHeapSize`를 확인해보면 예상대로 계산되는 것을 확인할 수 있다.

```
$ java -XX:+PrintFlagsFinal -version 2>&1 | grep -i -E 'heapsize|metaspacesize|version'
     size_t ErgoHeapSizeLimit                        = 0                                         {product} {default}
     size_t HeapSizePerGCThread                      = 43620760                                  {product} {default}
     size_t InitialBootClassLoaderMetaspaceSize      = 4194304                                   {product} {default}
     size_t InitialHeapSize                          = 536870912                                 {product} {ergonomic}
     size_t LargePageHeapSizeThreshold               = 134217728                                 {product} {default}
     size_t MaxHeapSize                              = 8589934592                                {product} {ergonomic}
     size_t MaxMetaspaceSize                         = 18446744073709535232                      {product} {default}
     size_t MetaspaceSize                            = 21807104                               {pd product} {default}
     size_t MinHeapSize                              = 8388608                                   {product} {ergonomic}
      uintx NonNMethodCodeHeapSize                   = 5839372                                {pd product} {ergonomic}
      uintx NonProfiledCodeHeapSize                  = 122909434                              {pd product} {ergonomic}
      uintx ProfiledCodeHeapSize                     = 122909434                              {pd product} {ergonomic}
     size_t SoftMaxHeapSize                          = 8589934592                             {manageable} {ergonomic}
  java version "15.0.1" 2020-10-20
```

<img src="https://user-images.githubusercontent.com/64415489/126507865-9dcb5218-9f74-4615-968d-dfe4061f09a8.png" width="80%"/>

## 내 애플리케이션에 적절한 힙 사이즈는 ?
> 딱 나눠 떨어지는 공식 같은 것은 없는 것 같다. 아래 사항을 참고하여 적절한 힙 사이즈를 찾기 위해 노력해보자.

아래 내용들은 [공식 문서](https://docs.oracle.com/cd/E13222_01/wls/docs81/perform/JVMTuning.html) 에서 발췌하였다.
해당 문서는 WebLogic Server를 기준으로 작성되었다.

### 힙 사이즈와 GC
- GC에 대한 허용 속도는 애플리케이션에 따라 다르며 GC의 실제 시간과 빈도를 분석한 후 조정해야 한다.
- 힙 크기가 클수록 Full GC 속도가 느려지고 빈도는 줄어든다. 힙 크기가 작을수록 Full GC는 빠르지만 자주 발생한다.
- 힙 크기를 조정하는 목적은 JVM이 GC 수행하는 데 드는 시간을 최소화하는 동시에, 한 번에 처리할 수 있는 클라이언트 수를 최대화하는 것이다.

### verbosegc 사용하기
- HotSpot VM의 GC 옵션(verbosec)을 사용하면 GC에 투입되는 시간과 리소스의 양을 정확하게 측정할 수 있다.
  - 로그 파일을 통해 진단 결과를 확인한다.
- 애플리케이션을 실행하는 동안 최대 부하에서 성능을 모니터링 한다.
- verbosec 옵션을 사용하여 JVM에 대한 자세한 가비지 수집 출력을 켜고 표준 오류 및 표준 출력을 모두 로그 파일을 통해 다음을 확인한.
  - 실행옵션 예시 : `-XX:+UseSerialGC -Xms1024m -Xmx1024m -verbose:gc`
  - GC 수행 빈도
  - GC 수행 시간(Full GC는 3~5초 이상 걸리지 않아야 한다.)
  - Full GC 후 사용 가능한 힙 메모리. 즉, 항상 힙의 85% 이상이 사용 가능한 상태라면 경우 힙 크기를 더 작게 설정할 수 있다.
- 힙 크기가 시스템에서 사용 가능한 RAM보다 크지 않아야 한다.
  - 시스템이 페이지를 디스크로 "swap" 하지 않도록 가능한 큰 힙 크기를 사용한다.
  - 시스템의 사용 가능한 RAM 크기는 하드웨어 구성과 시스템에서 프로세스를 실행하는 데 필요한 메모리 요구 사항에 따라 달라진다.
- 시스템이 가비지 수집에 너무 많은 시간을 소비하는 경우 힙 크기를 줄인다.
  - 일반적으로 사용 가능한 RAM의 80%(운영 체제나 다른 프로세스에서 사용하지 않음)를 JVM에 사용해야 한다.

### 주의사항
- JVM에서 사용하는 최대 메모리 양이 사용 가능한 물리적 RAM 양을 초과하지 않도록 설정해야 한다.
  - 이 값을 초과하면 OS가 페이징을 시작하고 성능이 크게 저하된다.
- 프로덕션 환경에서는 최소 힙 크기와 최대 힙 크기를 동일한 값으로 설정한다.
   - 힙을 지속적으로 늘리거나 줄이는 데 사용되는 JVM 리소스를 낭비하지 않도록 하기 위해

<br>

# OutOfMemoryError의 다양한 원인 살펴보기
---
> OutOfMemoryError가 발생하는 경우는 대표적으로 다음과 같다. <br>
> 1. 가비지 컬렉터가 새로운 객체를 생성할 공간을 더 이상 만들어주지 못하고, 힙 영역의 메모리 또한 증가될 수 없을 때
> 2. 네이티브 라이브러리 코드에서 스왑 영역이 부족하여, 더 이상 네이티브 할당을 할 수 없을 때

<br>
다양한 시스템 로그를 통해 OutOfMemoryError가 발생하는 여러가지 원인에 대해 살펴보자

## 1. Java heap space
> 자바의 힙 영역에서 더 이상 객체를 생성하기 어려울 때 발생한다.
> 이를 유발하는 다양한 케이스가 있을 수 있다.

- `Exception in thread "main".: java.lang.OutOfMemoryError: Java heap space`
- 메모리 크기를 너무 작게 잡거나, 메모리 크기를 지정하지 않은 경우
  - `-Xms`, `-Xmx` 실행옵션 확인하기
- 오래된 객체들이 계속 참조되고 있어 GC가 되지 않는 경우
  - static을 잘못 사용하고 있진 않은지, 애플리케이션이 의도치 않게 특정 객체를 계속 참조하고 있지는 않은지 확인하기
- finalize 메서드를 개발자가 개발한 클래스에 구현해 놓은 경우
  - JVM에는 GC 대상 객체들을 큐에 쌓고 처리하기 위한 데몬 스레드가 존재한다.
  - 이 스레드가 객체들을 처리하기도 전에 finalize로 인해 큐에 너무 많은 객체가 보관되어 있고, 처리가 불가능한 경우 문제가 발생할 수 있다.
- 스레드의 우선순위를 너무 높일 경우
  - 개발된 프로그램의 스레드 우선순위를 너무 높게 지정해 놓아서, 스레드를 메모리에 생성하는 속도가 GC를 처리하는 속도보다 빠르면 문제가 발생할 수 있다.
- 큰 덩어리의 객체가 여러 개 있을 경우
  - 예를 들어, 힙 메모리를 256MB로 지정하고 한번 호출되면 100MB의 메모리를 점유하는 화면을 세 번 호출하는 경우

## 2. Metaspace (Java 8 부터)
> Java 8 부터는 Permanent이 없어지고 Metaspace가 생겼다.

- `Exception in thread "main".: java.lang.OutOfMemoryError: Metaspace`
- Java 8 이전의 JVM에서는 Permgen Space라는 메시지가 나왔지만, Java 8 부터는 Metaspace 에러가 발생한다.
- 너무 많은 클래스가 자바 프로세스에 로딩될 경우 발생할 수 있다.
- `-XX:MaxMetaspaceSize` 옵션을 사용하여 크기를 조절할 수 있다.

## 3. Requested array size exceeds VM limit
- `Exception in thread "main".: java.lang.OutOfMemoryError: Requested array size exceeds VM limit`
- 배열의 크기가 힙 영역의 크기보다 더 크게 지정되었을 때 발생한다.
- 고정된 크기가 아닌 계산된 변수로 배열 크기를 지정할 경우 발생할 수 있다.

## 4. request \<size> bytes for \<reason>. Out of swap space?
- `Exception in thread "main".: java.lang.OutOfMemoryError: request <size> bytes for <reason>. Out of swap space?`
- 네이티브 힙 영역이 부족할 때, 즉 OS의 메모리(Swap 영역)가 부족한 상황이 되었을 때 발생한다.
  - 애플리케이션에서 호출하는 네이티브 메서드에서 메모리를 반환하지 않는 경우
  - 다른 애플리케이션에서 메모리를 반환하지 않는 경우

## 5. \<reason> \<stacktrace> (Native method)
- `Exception in thread "main".: java.lang.OutOfMemoryError: <reason> <stacktrace> (Native method)`
- 4번과 마찬가지로 네이티브 힙 영역에 메모리를 할당할 때 발생되는 에러이다.
- 4번의 경우는 JVM 코드에서 발생될 때, 이 경우는 JNI나 네이티브 코드에서 발생한다는 뜻이다.

# 메모리 문제와 GC 튜닝
---
> 너무 잦은 Full GC가 발생하면 성능에 많은 영향을 미친다.
> 이런 경우, 무작정 GC를 튜닝하기 보다는 GC가 많이 발생하지 않도록 하는 것이 먼저이다.
> 따라서, 다음과 같은 규칙을 잘 따랐는지 살펴봐야한다.

- 임시 메모리의 사용을 최소화
- 객체의 재사용
- XML 처리 시 메모리를 많이 점유하는 DOM 보다 SAX를 사용
- 너무 많은 데이터를 한 번에 보여주는 비즈니스 로직 제거

*※ 자바 프로세스 id(pid)만 알면 `jstat`을 사용하여(`java -gcutil <pid> <interval>`) 각 영역별로 메모리를 얼마나 사용하는지 확인할 수 있다.
jstat은 $JAVA_HOME/bin 디렉토리에 존재한다.*

# 더 공부할 부분
---
- finalize를 사용하면 안되는 이유
- 스레드 우선순위
- gc 로그 보는 법

# 참고 자료
---
- 이상민, 『자바 트러블슈팅』, 제이펍(2019), 12장.
- [https://docs.oracle.com/javase/8/docs/technotes/guides/vm/gc-ergonomics.html](https://docs.oracle.com/javase/8/docs/technotes/guides/vm/gc-ergonomics.html)
- [https://docs.oracle.com/cd/E12839_01/web.1111/e13814/jvm_tuning.htm#PERFM150](https://docs.oracle.com/cd/E12839_01/web.1111/e13814/jvm_tuning.htm#PERFM150)
