---
title: OS - Load Average 살펴보기 - 적용
date: 2025-04-03 20:25:00 +0900
categories: [지식 더하기, 이론]
tags: [OS]
---

> 실전에서 해당 지표를 어떻게 활용하면 좋을까 ?
> load average가 높아지는 상황들엔 어떤 것들이 있을까 ?

## 예시 : Load Average가 높아지는 몇 가지 상황

기존의 load average 계산은 이 I/O wait 상태는 포함하지 않아서, "부하가 낮은 것처럼" 보이는 문제가 있었어요.

비유로 이해하기
빠른 swap disk:
→ 프로세스가 swap을 빨리 끝내고 다시 CPU 실행 대기열에 들어감
→ runnable 상태가 많아짐 → load average가 높게 나옴

느린 swap disk:
→ 프로세스가 swap 중 I/O wait 상태로 오래 머무름
→ runnable 상태에서 빠짐 → load average에서 제외됨
→ 시스템은 느린데 load average는 낮게 나옴

- the problem is that processes which are swapping or
waiting on "fast", i.e. noninterruptible, I/O, also consume resources.


- When load averages first appeared in Linux, they reflected CPU demand, as with other operating systems.
- But later on Linux changed them to include not only runnable tasks, but also tasks in the uninterruptible state (TASK_UNINTERRUPTIBLE or nr_uninterruptible).

**그럼 Load Average가 높으면 CPU 사용률도 반드시 높은 상황일까 ?**
> 그렇지 않다.

### 예제
**1. uptime : Load Average 파악**

15:42:18 up 10 days,  2:14,  2 users,  load average: 10.23, 9.81, 5.12

**2. top : CPU 상태 확인**

%Cpu(s):  5.0 us,  2.0 sy,  0.0 ni, 10.0 id, 83.0 wa, 0.0 hi, 0.0 si, 0.0 st
- 83%가 wa (IO wait) = CPU는 놀고 있는데, 프로세스들이 디스크나 네트워크 응답을 기다리고 있음

**3. vmstat 1 : Runnable 상태 확인**
procs -----------memory---------- ---swap-- -----io---- -system-- ------cpu-----
r  b   swpd   free   buff  cache   si   so    bi    bo   in   cs us sy id wa st
12  0      0  50000  12000 400000    0    0   500  1000  300  150  5  2 10 83  0

- r 컬럼이 12 → runnable 상태의 프로세스가 12개
- 그런데 id는 10%, wa는 83% → 다들 IO 기다리느라 줄 서는 중

**4. iostat -x 1 : 디스크 IO 병목 체크**
Device:    %util     await     svctm
sda         99.9     900.0      2.5

- 디스크 사용률이 99.9%
- await가 900ms → 디스크 IO 하나 처리하는 데 거의 1초 걸림

**5. iotop : 누가 그렇게 디스크를 잡아먹나?**
Total DISK READ: 50.00 M/s | Total DISK WRITE: 0.00 B/s
PID  USER   DISK READ  COMMAND
12345 appuser 48.00 M/s  java -jar my-batch.jar
- 특정 배치 작업이 엄청난 양의 디스크 읽기 작업을 하고 있음
  → 이 프로세스 때문에 다른 프로세스들이 IO를 못 쓰고 대기 → load average 급등

즉, 리눅스 Load Average는 “CPU를 쓰려고 runnable 상태에 있는 프로세스” + “uninterruptible sleep 상태(D-state)인 프로세스”의 합이야.

즉, 단순히 "CPU를 기다리는 애들"만 포함되는 게 아니라,**디스크 IO 등을 기다리는 프로세스들(D 상태)**도 포함돼!
리눅스에서는 스레드도 커널 입장에서는 “스케줄링 단위”, 즉 task로 다뤄지기 때문에,
CPU를 점유하거나 기다리는 스레드는 Load Average 계산에 포함
=> Linux load averages are "system load averages" that show the running thread (task) demand on the system as an average number of running plus waiting threads.

## 의문점
**Q. 왜 D 상태가 Load Average에 포함될까 ?**
- 리눅스 커널은 D 상태를 시스템 리소스를 점유 중인데 강제로 깨울 수 없는 상태로 간주해.
  - 예를 들어 : 파일 읽기 / 네트워크 패킷 수신 / 데이터베이스 응답 대기 (로컬 디스크/소켓/파일 등)
  - 이런 작업들이 끝나야 다시 runnable 상태로 전환되거든.
- 따라서, 시스템 입장에선: “얘도 CPU가 필요한데 지금 잠깐 IO 때문에 못 받고 있는 거야. 부하라고 봐야지!” 하고 load average에 포함시켜 버리는 거야.


Q. **IO 대기와 CPU가 노는 것의 관계 ?**
- IO를 기다리는 프로세스는 CPU를 잠깐 놓고, 커널에게 “나 디스크 응답 올 때까지 대기할게~” 하고 빠져있음
- 이 상태가 바로 uninterruptible sleep (D 상태)
- 그래서 그 프로세스는 CPU를 사용하지 못해.

Q. **그럼 wa가 높으면 CPU가 놀고있으니 다른 프로세스가 사용하는게 아니라면 id(idle)도 높아야하지 않나 ?**
- wa와 id는 서로 배타적이 아니다. 즉, 한 코어의 시간은 us/sy/wa/id 중 하나로만 기록됨.
- 예시

CPU 0: [wa]
CPU 1: [wa]
CPU 2: [wa]
CPU 3: [wa]

→ 전체적으로 'CPU 사용률은 낮고', load average는 높음
→ id: 0%, wa: 100%

**Q.그럼 IO 대기로인해 프로세스가 uninterruptible sleep (D 상태)가 되고 다른 프로세스가 해당 코어를 사용해도 us가 올라가는게 아니라 wa가 올라가나 ?**

1. 어떤 프로세스가 IO를 기다리면서 D 상태가 됨
2. 그 프로세스가 쓰던 CPU 코어는 이제 다른 프로세스를 실행할 수 있음
3. 이후 코어에서 CPU 연산을 수행하는 다른 프로세스가 있다면 → us 증가
4. 근데 그 코어도 IO wait에 갇혀서 할 일이 없으면 → wa 증가

즉, D 상태인 프로세스가 있어도, 해당 CPU 코어가 뭘 하고 있는지에 따라 us 혹은 wa로 기록되는 거야.
D 상태는 그냥 "그 프로세스가 block 중"이라는 의미일 뿐
해당 코어가 실제로 IO를 기다리고 아무 일도 못하고 있는 시간이 있어야 wa가 올라감
반대로, 다른 일을 하고 있으면 그건 us나 sy로 잡히지

**Q. 그럼 IO 병목으로 인해 Load Average가 높아졌는데, top으로 확인했을때 wa가 아닌 us가 높은 상황일수도 있겠네 ?**
1. 프로세스1: IO 병목 → D 상태 (→ load average 증가 원인)
2. 프로세스2: CPU 점유 중 (→ us 증가)
3. wa는 낮음 (CPU는 일하고 있으니까)
4. 하지만 load average는 여전히 높음

- 타임라인으로 풀어볼게:
  시간 t1
  프로세스1: IO 요청 → block → D 상태

CPU는 할 일 없어서 wa 상승

Load Average 점점 증가

시간 t2
프로세스2가 들어와서 CPU 사용 (예: cron job, 로그 처리 등)

CPU는 일하니까 wa ↓, us ↑

근데 프로세스1은 여전히 IO wait 중 (D 상태)

➡️ Load Average는 여전히 높음 (왜? 아직도 runnable queue에 D 상태 프로세스가 남아 있기 때문)

- 실제 상황에서 이런 경우 흔히 볼 수 있음
  예를 들어:

IO 병목 때문에 시스템이 느려졌는데,

갑자기 누가 tar, gzip, curl, node 같은 CPU-heavy 프로세스 돌리면

→ wa는 줄고 us는 올라가지만

→ Load Average는 여전히 10 이상 유지됨

🔧 이럴 때 주의할 점
wa만 낮다고 해서 "IO 병목이 없어졌다"고 판단하면 안 됨

load average가 아직 높은데 top에서는 그 원인을 못 찾겠다?

→ D 상태 프로세스들을 ps -eo state,pid,cmd | grep '^D'로 확인해봐야 해!

※ 참고

| 항목  | 이름                | 의미                                                        |
|-------|---------------------|-------------------------------------------------------------|
| us    | User                | 유저 공간에서 실행된 코드의 CPU 사용률 (애플리케이션 등)    |
| sy    | System              | 커널(시스템) 공간에서 실행된 코드의 CPU 사용률 (시스템 콜 등) |
| ni    | Nice                | nice 값이 조정된 유저 프로세스의 CPU 사용률                  |
| id    | Idle                | CPU가 아무것도 하지 않고 빈 상태                           |
| wa    | IO Wait             | 디스크/네트워크 IO를 기다리느라 놀고 있는 CPU 시간          |
| hi    | Hardware Interrupt  | 하드웨어 인터럽트 처리에 사용된 CPU 시간                   |
| si    | Software Interrupt  | 소프트웨어 인터럽트(예: 커널 내부 소프트 인터럽트) 처리 시간|
| st    | Steal               | 가상화 환경에서 다른 VM이 CPU를 사용 중이라 뺏긴 시간      |


## 실전 사례
> https://pancho.dev/posts/linux-load-average/

### 높은 CPU 사용량
- top is the most common tool to watch processes and CPU usage, among other metrics.
- The impact that high cpu usage in a system will have, first thing it will impact is latency, if it’s a database server queries will take longer to be served, or if it’s a server running an HTTP application we will see latency going higher to serve request and in some cases requests will timeout, but it all depends on what the system is running.

### 메모리 부족으로 인한 Load Average 증가
- 메모리가 부족해서 Swap이 발생하면 → 디스크 IO가 증가 → 결국 Load Average도 상승

1. 메모리 부족 → 프로세스가 메모리 요청
- RAM이 다 찼다면 → 커널은 page cache나 프로세스 메모리를 swap 공간으로 밀어냄
2. Swap은 디스크 IO
- 디스크는 RAM보다 수십~수천 배 느림
- Swap in/out이 반복되면 → 엄청난 디스크 IO 발생
3. 디스크 IO 많아지면 → Load Average 상승
- D 상태(디스크 IO 대기) 프로세스가 증가
- Runnable Queue 길어짐 → load average 증가

- swap 확인
  - vmstat 1 : si (swap in), so (swap out) 확인
  - free -m : available 메모리가 0에 가까운지, swap이 사용중인지

## 상상해보기1 : Load Average가 높아졌다
1. 진짜 CPU 사용률이 높은 것인지 ? or I/O 대기로 인한 것인지 ?
   => top 명령어로 확인

2-1. wa가 높다.
=> 어떤 IO로 인한 것인지 (디스크 vs 네트워크 ?)
=> 어떻게 확인하지 ?
=> DISK IO인 경우 메모리 swap으로 인한 것인지 실제 디스크를 많이 사용하는 작업이 진행중인 것인지 ?
=> swap 확인 : vmstat의 si, so 또는 free -m

2-2. us가 높다.
=> 실제 이로 인한 load average 증가인지, IO 대기가 많아서 놀고있는 CPU를 사용하는 것인지 확인 필요
=> D 상태의 프로세스가 많은지 확인 : ps -eo state,pid,cmd | grep '^D'

- top으로 CPU 지표 확인
- us가 높다 --> 어떤 프로세스에서 많이 사용하고 있는 것인지 확인 (top 말고 딴것도 있나?)
  - D 상태인 프로세스들이 많은지도 확인 (IO 대기로 인해 Load Average가 높아진 것일 수 있으므로)
    - ps -eo state,pid,cmd | grep '^D'
- wa가 높다
  --> 어떤 프로세스에서 I/O 대기를 하고있는 것인지 : iostat
  --> swap 때문인지 : free -m, vmstat 1


## 상상해보기2 : 모니터링시 Alert 기준이 되는 Load Average 임계치는 어떤 기준으로 생각하면될까 ?
=> 어떤 지점부터가 시스템에 '이상'이 생긴 것으로 판단할 수 있을까 ?
=> '이상'이 생겼다는건 ?
=> 시스템이 의도대로 동작하지 않음, 사용자 경험이 급격하게 나빠짐 등등 ..
=> 시스템마다 다르다 .. 정답이 없다.

=> 하테나 예시

## 학습

- having high load average won’t tell exactly what is wrong with your system and gives a hint that there might be a bottleneck somewhere,
-  So there are situations that another complimentary metric from the system will be needed in order to find where the bottleneck is.

- One thing to have in mind when defining alerts or tuning an existing one, is to have enough metrics data to look at the history of load average in a system to see the baseline usage and maximum usages. It will always be better to have history of the load average to understand how it behaves and also how it correlated to other metrics in the system.

## CPU 코어 개수


## Load Avg가 높으면 ?
=> 어떤게 원인인지 어떻게 알지 ?
=> 어떤 프로세스들이 대기하는지 어떻게 알지 ? 대기하는 프로세스가 바로 처리돼야하는게 아니면 괜찮은거 아닌가 ?



## 참고
- https://pancho.dev/posts/linux-load-average/
- https://www.brendangregg.com/blog/2017-08-08/linux-load-averages.html
