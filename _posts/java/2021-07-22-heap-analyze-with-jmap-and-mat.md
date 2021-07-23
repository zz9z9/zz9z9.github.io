---
title: 자바 메모리 단면 분석하기
date: 2021-07-20 23:00:00 +0900
categories: [Java]
tags: [Java, Heap Memory, Eclipse Memory Analyzer]
---

# 언제 메모리 단면을 분석해야할까 ?
---
메모리 단면인 '힙 덤프(Heap Dump)'는 생성하는데 비용이 비싸기 때문에, 메모리가 부족해지는 현상이 지속해서 발생하거나 OOM 에러가 발생했을 때 생성해야 한다.
여기서 말하는 비용이란 다음과 같다
- 덤프 파일을 생성하는 동안 서비스가 불가능한 상황이 된다.
- 덤프 생성시 많은 시간이 소요될 수 있다.
- 큰 파일(대부분 점유하고 있는 메모리 크기만큼의 파일)이 생성된다.
- 몇몇 JDK 버전은 jmap과 같은 도구를 사용할 경우, 한 번밖에 덤프 파일을 생성할 수 없다.

OOM은 에러가 발생하므로 인식할 수 있겠지만, 메모리가 점점 부족해지는 것은 어떻게 파악할 수 있을까?
- jstat 사용
- WAS의 모니터링 콘솔
- Java Visual VM, Jconsole과 같은 JMX 기반의 모니터링 도구
- APM(Application Performance Management) 활용
- verbosegc, Xlog 옵션 활용

## jstat 예시 (JDK 11 사용)
- 실행하는 자바 애플리케이션의 pid를 알기 위해 `jps` 명령어를 활용한다
```
$ jps
18387 Launcher
18388 HoldMemory
33396
18389 Jps
```

- `jstat -gcutil <pid> <interval>`을 활용하여 모니터링 할 수 있다.
- 아래 항목 중 4번째 컬럼인 O(Old 또는 Tenured 영역)의 메모리 사용량이 GC 이후에도 증가한다면 메모리 릭이 발생하고 있다고 판단할 수 있다.
  - 해당 영역의 메모리 사용량은 애플리케이션이 동작하는 동안에는 계속 증가하는 것이 기본이다.
  - 따라서, 일반적인 상황에서 Old 영역의 메모리가 계속 증가한다고 해서 메모리 릭이라고 판단해선 안된다.
```
$ jstat -gcutil 18388 2s
  S0     S1     E      O      M     CCS    YGC     YGCT    FGC    FGCT    CGC    CGCT     GCT
  0.00 100.00   9.09  10.13  95.47  88.35      2    0.032     0    0.000     0    0.000    0.032
  0.00 100.00   9.09  10.13  95.47  88.35      2    0.032     0    0.000     0    0.000    0.032
  0.00 100.00  18.18  21.23  95.47  88.35      4    0.062     0    0.000     0    0.000    0.062
  0.00 100.00  18.18  21.23  95.47  88.35      4    0.062     0    0.000     0    0.000    0.062
  0.00 100.00  45.45  30.12  95.47  88.35      6    0.093     0    0.000     0    0.000    0.093
  0.00 100.00  45.45  30.12  95.47  88.35      6    0.093     0    0.000     0    0.000    0.093
  0.00 100.00  16.67  46.96  95.47  88.35      8    0.129     0    0.000     0    0.000    0.129
  0.00 100.00  16.67  46.96  95.47  88.35      8    0.129     0    0.000     0    0.000    0.129
  0.00 100.00  17.24  58.04  95.47  88.35      9    0.162     0    0.000     0    0.000    0.162
  0.00 100.00  17.24  58.04  95.47  88.35      9    0.162     0    0.000     0    0.000    0.162
  0.00 100.00   8.70  63.48  95.51  88.35     10    0.199     0    0.000     2    0.001    0.200
  0.00 100.00   8.70  63.48  95.51  88.35     10    0.199     0    0.000     2    0.001    0.200
  0.00 100.00  43.24  64.98  95.51  88.35     11    0.215     0    0.000     4    0.002    0.216
```

# 메모리 단면 생성하기
---
- 메모리 단면은 일반적으로 다음과 같이 생성할 수 있다.
  - 자바 프로세스 실행 시 옵션에 포함하여 자동 파일 생성
    - `-XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=경로`
    - OOM 에러가 발생하지 않은 이상 애플리케이션 성능에 전혀 영향을 끼치지 않는다.
  - 실행 옵션과 상관없이 명령어를 사용하여 파일 생성
    - jmap 명령어
    - 리눅스의 gcore와 같은 OS에서 제공하는 코어 덤프 명령어 (파일 크기가 자바 힙 덤프에 비해 훨씬 크다)

## jmap 사용해서 힙 덤프 생성하기

|옵션|내용|
|-----|-----|
| -dump:[live],format=\<format>,file=\<filename> | 힙 덤프 파일을 생성 |
| -finalizerinfo | GC가 되려고 기다리고 있는 객체들의 정보 출력 |
| -clstats | 클래스 로더의 통계 정를 제공 |
| -histo[:live] | 힙 영역의 메모리 점유 상태를 가장 많이 점유한 객체부터 출력 |
| -F | -dump와 -histo 옵션과 같이 사용되며, 덤프를 강제로 발생시킬 때 사용 |

- `jmap -dump:<dump-options> <pid>` 명령어 사용하여 아래와 같이 파일을 생성할 수 있다.
```
$ jmap -dump:format=b,file=dumptest.bin 20195
Heap dump file created
```
<img src="https://user-images.githubusercontent.com/64415489/126754570-b3f78a18-c58e-4923-936a-850f78291e51.png" width="20%" height="20%"/>

# MAT 활용하여 메모리 단면 분석하기
---
> MAT는 Eclipse Memory Analyzer로서 활발하게 개발 및 유지보수가 이루어지고 있다. <br>
> MAT 이외에도 다양한 메모리 분석 도구가 있다.

- 먼저 [MAT를 다운](https://www.eclipse.org/mat/downloads.php) 받는다.
- 생성한 힙 덤프 파일을 MAT에서 열게되면 아래와 같은 화면을 볼 수 있다.
<img src="https://user-images.githubusercontent.com/64415489/126758057-73618a51-7433-4c3d-af83-3a7a8bf28cf4.png" width="90%"/>

## Leak Suspect
> Details를 누르면 아래 항목들을 확인할 수 있다.

- Description
  - 해당 객체에 대한 설명
- Shortest Paths To the Accumulation Point
  - 메모리를 점유하고 있는 객체가 가장 상단에, 그 객체를 생성하고 호출한 객체가 하단에 트리 형태로 나타난다.
- Accumulated Objects
  - 메모리를 점유하고 있는 객체가 가장 하단에, 그 객체를 생성하고 호출한 객체가 가장 상단에 트리 형태로 나타난다.
- Accumulated Objects by Class
  - 클래스별로 객체를 점유하는 대상 목록
  ![image](https://user-images.githubusercontent.com/64415489/126806442-6ca8d9e6-6c81-40b2-9b44-91d4e2acbca3.png)

## Histogram
> 클래스별 객체의 개수와 그 크기를 가장 큰 값부터 확인할 수 있다.

- 어떤 클래스 타입이 가장 많은 메모리를 가지고 있는지 쉽게 파악할 수 있다.
- 하지만, 메모리를 가장 많이 사용하는 객체를 식별하기는 쉽지 않다.
  - 예를 들어 아래 화면에서 `byte[]`는 가장 많은 양의 메모리를 차지하고 있다. 그러나 어떤 객체가 실제로 해당 바이트 배열을 보유하고 있는지 식별할 수 없다.
![image](https://user-images.githubusercontent.com/64415489/126805194-87a3a914-1d79-437b-9f61-2010b55ee315.png)
- Shallow Heap/Retained Heap
  - Shallow Heap은 객체 자체의 크기이다.
  - Retained Heap은 객체 자체의 크기 + 해당 객체에서 갖고있는 객체들의 크기이다.
  - 예를 들어, 아래 HoldMemory 객체 자체는 16바이트의 크기를 가진다. 그러나 해당 객체가 갖고 있는 모든 객체의 크기가 700Mb를 초과한다.
  - 따라서, HoldMemory에 의해 유지되는 `HashMap`이 메모리 문제의 원인일 것으로 추론할 수 있다.
  ![image](https://user-images.githubusercontent.com/64415489/126811689-e2bdcd6a-f392-4de9-affd-db4d8146492c.png)

## Dominator Tree
> 각 클래스별(클래스 로더 단위)로 점유하고 있는 메모리의 양이 가장 많은 클래스부터 트리 형태로 나타낸다.

- 예를 들어, 아래 화면에서는 HoldMemory 객체가 가장 큰 메모리를 차지하고 있음을 알 수 있다.
- 또한, 해당 객체가 700Mb 이상의 메모리를 포함하는 해시 맵을 보유하고 있음을 알 수 있다.
  ![image](https://user-images.githubusercontent.com/64415489/126812225-4879c879-740a-471d-8941-0d3223837346.png)
- Dominator Tree 하나의 객체가 많은 양의 메모리를 차지할 때 분석하기에 유용하다.
- 만약 여러 개의 작은 객체로 인해 메모리 릭이 발생한다면, 히스토그램을 사용하여 메모리를 가장 많이 인스턴스를 확인하는 것이 좋다.

## Duplicated Classes
> 여러 클래스 로더에서 중첩되게 로딩한 클래스의 대한 정보를 확인할 수 있다.

- 클래스 로더에 문제가 있을 경우 확인하는 용도로 주로 사용한다.

# 실제로 사용해보기
---
- [XSSF vs SXSSF 클래스 메모리 사용량 비교해보기](https://zz9z9.github.io/posts/xssf-oom-analyze/)

# 참고 자료
---
- 이상민, 『자바 트러블슈팅』, 제이펍(2019), 13~14장.
- https://www.cleantutorials.com/jconsole/heap-dump-analysis-using-eclipse-memory-analyzer-tool-mat
- https://eclipsesource.com/blogs/2013/01/21/10-tips-for-using-the-eclipse-memory-analyzer/
