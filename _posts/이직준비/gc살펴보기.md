## GC
- Java 8
- Java 9	G1GC 기본 사용, CDS 기본 활성화
- Java 11	ZGC 추가, Metaspace 최적화
- Java 17	ZGC & Shenandoah GC 개선


# Java 버전별 GC 정리

| Java 버전     | 기본 GC   | 추가된 GC                            | 특징                                      |
|--------------|---------|---------------------------------|-----------------------------------------|
| Java 8      | Parallel GC | G1 GC                           | Throughput 중심, Stop-the-world 발생 가능 |
| Java 9~11   | G1 GC   | ZGC (실험적)                     | G1 GC 기본 설정, 예측 가능한 GC 수행    |
| Java 12~16  | G1 GC   | Shenandoah GC (실험적), ZGC 개선 | Shenandoah/ZGC 도입, G1 GC 성능 개선    |
| Java 17 (LTS) | G1 GC   | ZGC, Shenandoah GC 정식 지원     | ZGC 대용량 지원 (16TB), Full GC 성능 향상 |
| Java 21 (LTS) | G1 GC   | ZGC, Shenandoah GC 성능 최적화   | ZGC Write Barrier 최적화, 저지연 개선    |

# GC별 동작 방식

| GC 유형        | Young Generation 처리                 | Old Generation 처리                     | Stop-the-world 시간          | 특징                                       |
|--------------|--------------------------------|----------------------------------|---------------------|----------------------------------------|
| Serial GC   | Copying GC (Single Thread)   | Mark-Sweep-Compact (Single Thread) | 길다 (Single Thread) | 단일 스레드, 작은 힙에 적합             |
| Parallel GC | Parallel Scavenge (Multi-Thread) | Parallel Mark-Sweep-Compact       | 중간 (Parallel 처리) | Throughput 중심, 병렬 처리            |
| G1 GC       | Region-based Evacuation     | Concurrent Marking + Mixed GC    | 예측 가능 (G1 설정 가능) | Balanced GC, Region 단위 처리         |
| ZGC         | Concurrent Region-based Evacuation | Fully Concurrent Marking + Compaction | 10ms 이하 (초저지연)  | 대용량 메모리 지원, 초저지연           |
| Shenandoah GC | Concurrent Region-based Evacuation | Fully Concurrent Marking + Compaction | 10ms 이하 (저지연)    | Stop-the-world 최소화, Full GC 거의 없음 |

## GC 동작 방식 상세
- 가비지 컬렉터는 두 가지 가설 하에 만들어졌다(사실 가설이라기보다는 가정 또는 전제 조건이라 표현하는 것이 맞다).
  - **대부분의 객체는 금방 접근 불가능 상태(unreachable)가 된다.**
  - **오래된 객체에서 젊은 객체로의 참조는 아주 적게 존재한다.**
- 이 가설의 장점을 최대한 살리기 위해서 HotSpot VM에서는 크게 Young 영역과 Old 영 2개로 물리적 공간을 나누었다.

### Young 영역(Young Generation 영역)
- 새롭게 생성한 객체의 대부분이 여기에 위치한다.
- 대부분의 객체가 금방 접근 불가능 상태가 되기 때문에 매우 많은 객체가 Young 영역에 생성되었다가 사라진다.
- 이 영역에서 객체가 사라질때 `Minor GC`가 발생한다고 말한다.
- Young 영역은 3개의 영역으로 나뉜다.
  - Eden 영역 / Survivor 영역(2개)
  - Minor GC는 Eden + 하나의 Survivor 영역을 대상으로 수행
    - 즉, Eden + 현재 활성화된 Survivor 영역(S0 또는 S1)에서 살아남은 객체를 정리하여 다른 Survivor 영역

- Minor GC 트리거 조건
  - Eden 영역이 꽉 차면 즉시 Minor GC 실행
  - Minor GC 도중 Survivor 영역(S0, S1)에 복사할 공간이 부족하면 일부 객체를 Old Generation으로 Promotion(승격).
  - 하지만 Survivor 영역이 꽉 찼다고 해서 바로 Minor GC가 발생하지는 않음.

- 각 영역별 처리 절차
  - 새로 생성한 대부분의 객체는 Eden 영역에 위치한다.
  - Eden 영역에서 GC가 한 번 발생한 후 살아남은 객체는 Survivor 영역 중 하나로 이동된다.
  - Eden 영역에서 GC가 발생하면 이미 살아남은 객체가 존재하는 Survivor 영역으로 객체가 계속 쌓인다.
  - 하나의 Survivor 영역이 가득 차게 되면 그 중에서 살아남은 객체를 다른 Survivor 영역으로 이동한다. 그리고 가득 찬 Survivor 영역은 아무 데이터도 없는 상태로 된다.
  - 이 과정을 반복하다가 계속해서 살아남아 있는 객체는 Old 영역으로 이동하게 된다.
    - 즉, 특정 횟수(n회) 이상 Minor GC를 거친 객체는 Old Generation(=Tenured 영역)으로 이동(Promotion).

### Old 영역(Old Generation 영역)
- 접근 불가능 상태로 되지 않아 Young 영역에서 살아남은 객체가 여기로 복사된다.
- 대부분 Young 영역보다 크게 할당하며, 크기가 큰 만큼 Young 영역보다 GC는 적게 발생한다.
- 이 영역에서 객체가 사라질 때 `Major GC(혹은 Full GC)`가 발생한다고 말한다.
- Old 영역에 있는 객체가 Young 영역의 객체를 참조하는 경우가 있을 때를 처리하기 위해서 Old 영역에는 512바이트의 덩어리(chunk)로 되어 있는 카드 테이블(card table)이 존재한다.
  - 카드 테이블에는 Old 영역에 있는 객체가 Young 영역의 객체를 참조할 때마다 정보가 표시된다.
  - Young 영역의 GC를 실행할 때에는 Old 영역에 있는 모든 객체의 참조를 확인하지 않고, 이 카드 테이블만 뒤져서 GC 대상인지 식별한다.

- Old 영역은 기본적으로 데이터가 가득 차면 GC를 실행

### 왜 STW 때는 모든게 멈출까 ?

### 접근 불가능 판단 ?
1. Heap 영역에 존재하는 객체들에 대하여 접근 가능 여부를 확인
2. GC Root에서 시작하여 참조값을 따라가며 접근 가능한 객체들에 Mark 하는 과정을 진행
3. Mark되지 않은 객체들은 제거(Sweep) 대상이 되고 해당 객체들을 제거
**접근 가능 여부 확인 ?**
- ㅇㅇ

## Parallel GC
- Minor GC를 처리하는 스레드를 여러 개로 늘려 병렬로 처리 (`-XX:+UseParallelGC`)
- Parallel Old GC (`-XX:+UseParallelOldGC`, `-XX:+ParallelGCThreads=n` 옵션으로 멀티 스레드 개수를 지정할 수 있다.)
  - Parallel GC가 Young 영역에 대해서만 멀티스레드 방식을 사용했다면, Parallel Old GC는 Old 영역까지 멀티스레드 방식을 사용한다.

<img width="636" alt="Image" src="https://github.com/user-attachments/assets/706e3b2e-f39c-49fc-8137-7277cc097f0b" />

## G1 GC
- 전통적인 힙 구조는 Young, Old 영역을 명확하게 구분하였지만, G1 GC는 개념적으로 그들이 존재하나 일정 크기의 논리적 단위인 region으로 구분하고 있다.
  - 총 Region 개수는 최대 약 2048개 (JVM이 할당된 메모리에 따라 자동 결정됨).

![Image](https://github.com/user-attachments/assets/a3600fc3-83c3-4fe0-8e1c-405642af2d94)

- Region별 역할은 다음과 같이 동적으로 변함:
  - Eden (신규 객체 할당)
  - Survivor (Minor GC에서 살아남은 객체 저장)
  - Old Generation (오래 살아남은 객체 저장)
  - Humongous (매우 큰 객체 저장) → 일반 Region의 절반보다 큰 객체.

<img width="751" alt="Image" src="https://github.com/user-attachments/assets/5d51927b-84c1-4def-b009-16cfad4aa222" />

![Image](https://github.com/user-attachments/assets/94c1c31c-fbd1-4a8b-8530-3d551dc38863)

- "Garbage-First" 방식
  - 기존의 GC는 세대(Young/Old Generation) 중심으로 GC를 수행
  - G1GC는 **가비지가 많은 Region을 우선적으로 정리(Garbage-First)** 하여 성능을 최적화.
  - Fragmentation(메모리 단편화) 최소화 → 힙의 효율적인 활용 가능.

### 주요 동작 방식
**(1) Initial Mark (초기 마킹)**
- Old Generation에서 살아있는 객체를 식별하여 마킹.
- 애플리케이션 실행과 동시에 진행되므로 영향이 적음(STW 발생하지만 짧음).

**(2) Concurrent Marking (동시 마킹)**
- 모든 Region을 검사하면서 살아있는 객체를 확인.
- 앱 실행과 동시에 수행(Concurrent)
  -  Stop-the-world 없이 백그라운드에서 실행.
- 오래된 객체 중 가비지가 많은 Region을 우선적으로 GC 대상으로 선정.

**(3) Remark (리마크)**
- Concurrent Marking 동안 변경된 객체를 다시 마킹.
- 일시적인 Stop-the-world 발생 가능(하지만 매우 짧음).

**(4) Cleanup (정리)**
- 가비지가 많은 Region을 회수하고 메모리를 재사용 가능하도록 정리.
- 이 과정은 애플리케이션과 동시에 수행되며, Stop-the-world가 거의 없음.

**(5) Evacuation (객체 이동)**
- 가비지가 많은 Region에서 살아있는 객체를 다른 Region으로 복사하여 정리.
- Eden → Survivor → Old Generation으로 이동 (Young GC 수행).
- "Evacuation Pause" 시 애플리케이션 실행이 멈추지만, 예상 가능한 Pause Time으로 조절 가능.

**(6) Mixed GC (혼합 GC)**
- Old Generation과 Young Generation을 함께 정리하는 GC 수행.
- Old Generation에서 가비지가 많은 Region을 우선 처리
  - Full GC를 최대한 방지.


## 그래서 G1 GC의 어떤 부분이 Parallel GC 같은 기존 GC 보다 STW를 짧게 만드는거지 ?

**기존 GC(Parallel GC)의 문제점**
- Parallel GC는 Minor GC(Young Generation)에서는 멀티스레드로 빠르게 수행하지만, Old Generation GC(Full GC)가 발생하면 STW 시간이 길어지는 문제가 있음.
- Old Generation에서 Full GC가 발생하면 전체 힙을 `Mark-Sweep-Compact` 방식으로 처리해야 함.
- Full GC는 전체 애플리케이션이 멈춘 상태(STW)에서 수행되므로 매우 긴 지연 시간 발생 가능.
- 메모리 단편화(Fragmentation)가 발생하면 추가적인 Compaction이 필요하여 더 긴 STW를 유발.

### G1 GC는 어떻게 STW를 줄이는가?
**1. Region 기반 메모리 관리**
> 기존 GC는 전체 Old Generation을 대상으로 GC를 수행하지만, G1GC는 Region 단위로 처리하므로 STW를 줄일 수 있음.

- 기존 GC (Parallel GC)
  - Young / Old Generation이 고정 크기로 설정됨.
  - Old Generation에서 Full GC가 발생하면 전체 Old Generation을 한 번에 처리해야 하므로 STW 시간이 길어짐.

- G1GC
  - 힙을 작은 **Region 단위(1MB~32MB)**로 나누고, 필요에 따라 Young / Old 역할을 동적으로 변경.
  - Region 단위로 GC를 수행하여 한 번에 많은 영역을 처리하지 않으므로 STW 시간이 짧아짐.

**2. Concurrent Marking (Old Generation도 동시 마킹 수행)**
> G1GC는 Old Generation에서도 STW 없이 동작할 수 있는 "Concurrent Marking" 기법을 사용하여 기존 GC보다 STW 시간을 줄임.

- 기존 GC (Parallel GC)
  - Old Generation에서 GC를 수행할 때 Mark 단계에서 STW 발생 (모든 객체를 스캔해야 함).
  - 애플리케이션 실행이 멈춘 상태에서 오래 걸리는 경우가 많음.

- G1GC
  - Old Generation에 대해 "Concurrent Marking"을 수행하여 STW 없이 백그라운드에서 실행.
  - Initial Mark → Concurrent Marking → Remark 과정을 거쳐 **Old Generation에서 살아있는 객체를 미리 식별.**
  - STW를 최소화하면서도 Old Generation GC를 수행할 수 있음.

**3. Mixed GC (Full GC 없이 Old Generation 일부만 정리)**
> G1GC는 Mixed GC로 Full GC 발생을 최소화하여 STW 시간을 줄임.

- 기존 GC (Parallel GC)
  - Old Generation이 꽉 차면 Full GC 발생 → Mark-Sweep-Compact 방식으로 GC 수행 → 매우 긴 STW 발생.
  - Full GC가 발생하면 애플리케이션이 수 초~수십 초간 멈출 수 있음.

- G1GC
  - Mixed GC라는 방식을 사용하여 Young Generation GC(=Minor GC)와 Old Generation GC를 혼합 수행.
  - Old Generation의 가비지가 많은 Region만 선택하여 GC를 수행하므로 한 번에 많은 객체를 처리할 필요가 없음.
  - 따라서 Full GC를 최소화할 수 있고, STW 시간이 예측 가능해짐.

**4. Evacuation (객체 이동을 통한 메모리 정리)**
> 기존 GC는 Full GC에서 메모리를 압축하는 동안 긴 STW가 발생하지만, G1GC는 Region 단위로 객체를 이동하면서 STW를 줄임.

- 기존 GC (Parallel GC)
  - Old Generation에서 Compaction(압축) 작업이 필요함.
  - Compaction 과정은 모든 객체를 이동해야 하므로 긴 STW 발생 가능.

- G1GC
  - Evacuation(이전) 방식 사용:
  - 가비지가 많은 Region에서 살아남은 객체만 다른 Region으로 이동하고, 해당 Region을 비움.
  - Old Generation에서도 Compacting을 수행하므로 메모리 단편화를 줄이고 STW 시간을 짧게 유지.

<img width="792" alt="Image" src="https://github.com/user-attachments/assets/59bb8ed4-90f7-419c-bea1-20f868305428" />
