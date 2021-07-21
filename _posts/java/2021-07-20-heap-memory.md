---
title: 힙 사이즈와 OutOfMemoryError
date: 2021-07-20 23:00:00 +0900
categories: [Java]
tags: [Java, Heap Memory]
---

# OS 메모리 영역과 JVM 메모리 영역 ??

# 힙 사이즈
---
## 기본값
default
초기 메모리 = 32/64 = 0.5GB(InititialHeapSize)

최대 메모리 = 32/ 4= 8GB(MaxHeapSize)

`java -XX:+PrintFlagsFinal -version 2>&1 | grep -i -E 'heapsize|permsize|version'`

metaspacesize
permsize

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


## 힙의 최소/최대 사이즈

## 내 애플리케이션에 적절한 힙 사이즈 ?

## 힙의 크기는 유동적으로 증가시킬 수 있는건가 ?

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

# 참고 자료
---
- 자바 트러블슈팅
- https://docs.oracle.com/cd/E12839_01/web.1111/e13814/jvm_tuning.htm#PERFM164
