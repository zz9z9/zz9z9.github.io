---
title: OS - 리눅스 Load Average 살펴보기
date: 2025-04-03 20:25:00 +0900
categories: [지식 더하기, 이론]
tags: [OS]
---

## Load Average ?
---

> 리눅스의 load average는 시스템 전체의 부하 평균을 나타내며, 실행 중이거나 대기 중인 스레드(태스크)의 수를 평균으로 나타낸 것. <br>
> 즉, 실행 가능한(runnable) 태스크뿐만 아니라, ***uninterruptible sleep 상태(중단 불가능한 대기 상태)에 있는 태스크들도 추적***

### 역사
- 처음엔 실행 가능한 태스크에 대해 CPU가 처리해야 할 작업량을 나타내는 지표였다.
- 하지만, 이렇게 했을때 생길수 있는 문제점은:
  - 시스템은 전체적으로 느려지지만 load average는 낮아지는 경우가 있음.
    - 예 : 빠른 swap 디스크에서 느린 swap 디스크로 바꾼 경우
      - 빠른 디스크 : 프로세스가 swap을 빨리 끝내고 다시 CPU 실행 대기열에 들어감. runnable 상태가 많아짐 → load average가 높게 나옴
      - 느린 디스크 : 프로세스가 swap 중 I/O wait 상태로 오래 머무름 → runnable 상태에서 빠짐 (uninterruptible sleep 상태로 바뀜) → load average에서 제외됨 → load average가 낮게 나옴
  - 따라서, 실행 가능한 태스크만 포함하게되면 부하로 인해 시스템 성능이 저하되는데 load average는 낮아질 수 있기 때문에 해당 지표가 직관적이지 않게됨

### 왜 uninterruptible sleep 상태의 작업이 많아지면 시스템이 느려질까 ?
>  예시 : swap-in/out, 파일 시스템 락, 디바이스 응답 대기, I/O wait 중인 프로세스 (보통 디스크 I/O 등)

**uninterruptible sleep (D 상태)의 특징**

1. 커널이 깰 수 없다.
- sleep 상태(S)는 인터럽트나 시그널로 깰 수 있는데, D 상태는 시스템 콜이 끝날 때까지 무조건 기다려야 한다.

2. 리소스를 점유한다.
- CPU를 직접 점유하진 않지만, 다음과 같은 시스템 자원을 계속 붙잡고 있게됨:
  - 메모리 페이지
  - I/O 버퍼
  - 락 (파일 시스템 락, inode 락 등)
  - 스레드/프로세스 slot 자체

3. 스케줄러 입장에서 "일이 밀리는 중"
- CPU가 직접 처리하진 않더라도, 해당 프로세스가 리소스를 기다리며 큐에 쌓이고 있는 상태

## 평균이란 ?
> 1분, 5분, 15분 동안의 평균은 어떻게 계산되는걸까 ?

- load average 관련 커널 소스 코드를 참고해보았다.
  - [loadavg.c](https://github.com/torvalds/linux/blob/402de7f/kernel/sched/loadavg.c)
  - [loadavg.h](https://github.com/torvalds/linux/blob/402de7fc880fef055bc984957454b532987e9ad0/include/linux/sched/loadavg.h)

- 평균 계산과 관련하여 참고한 주석과 코드는 아래와 같다.

```
* The global load average is an exponentially decaying average of nr_running +
* nr_uninterruptible.
*
* Once every LOAD_FREQ:
*
*   nr_active = 0;
*   for_each_possible_cpu(cpu)
*	nr_active += cpu_of(cpu)->nr_running + cpu_of(cpu)->nr_uninterruptible;
*
*   avenrun[n] = avenrun[0] * exp_n + nr_active * (1 - exp_n)

...

avenrun[0] = calc_load_n(avenrun[0], EXP_1, active, n);
avenrun[1] = calc_load_n(avenrun[1], EXP_5, active, n);
avenrun[2] = calc_load_n(avenrun[2], EXP_15, active, n);

...

calc_load_n(unsigned long load, unsigned long exp, unsigned long active, unsigned int n)
{
	return calc_load(load, fixed_power_int(exp, FSHIFT, n), active);
}

...

#define LOAD_FREQ	(5*HZ+1)	/* 5 sec intervals */
#define EXP_1		1884		/* 1/exp(5sec/1min) as fixed-point */
#define EXP_5		2014		/* 1/exp(5sec/5min) */
#define EXP_15		2037		/* 1/exp(5sec/15min) */

calc_load(unsigned long load, unsigned long exp, unsigned long active)
{
	unsigned long newload;

	newload = load * exp + active * (FIXED_1 - exp);
	if (active >= load)
		newload += FIXED_1-1;

	return newload / FIXED_1;
}
```

### 예시 : 1분 Load Average 계산
- 위 코드를 온전히 이해하기는 어려워서 주석에 있는 `avenrun[n] = avenrun[0] * exp_n + nr_active * (1 - exp_n)` 식을 기반으로 GPT에게 물어보았다.
  - (근데 `avenrun[0]` 이 아니라 `avenrun[n]`이 되어야하지 않나 ?)

```
- 가정: 매 샘플 주기(LOAD_FREQ)마다 nr_active = 10 (즉, 실행 또는 대기 중인 프로세스 수가 10으로 일정함)
- 초기 값: t=0일 때 load average 값=0
- exp_1: 0.9200 (1분에 해당하는 지수 상수, 5초 간격으로 1분 평균을 맞추기 위한 감쇠율)
```

| 샘플 주기 (Tick) | 이전 load (old_load) | 계산식                                                                 | 새로운 load (new_load) |
|------------------|----------------------|------------------------------------------------------------------------|------------------------|
| 1                | 0                    | 0 × 0.9200 + 10 × (1 - 0.9200) = 0 + 10 × 0.0800                       | 0.8                    |
| 2                | 0.8                  | 0.8 × 0.9200 + 10 × 0.0800 = 0.736 + 0.8                               | 1.536                  |
| 3                | 1.536                | 1.536 × 0.9200 + 10 × 0.0800 = 1.414 + 0.8                             | ≈ 2.214                |
| 4                | 2.214                | 2.214 × 0.9200 + 10 × 0.0800 = 2.0369 + 0.8                           | ≈ 2.837                |
| 5                | 2.837                | 2.837 × 0.9200 + 10 × 0.0800 = 2.613 + 0.8                             | ≈ 3.413                |
| ...              | ...                  | ...                                                                    | ...                    |

- 지수 평균의 의미
  - 1분 load average는 단순히 60번 반복해서 평균을 낸 값이 아니라, 지수적으로 과거를 감쇠하며 현재 값을 더해가는 방식
    - 단순 평균: "1분 동안 60번 재서 더한 뒤 나눈 값"
    - 지수 평균 : "1분 동안 부하가 계속 유지되었다면 어떤 값으로 수렴하겠는가?"

### 샘플 주기 : LOAD_FREQ
- `#define LOAD_FREQ	(5*HZ+1)	/* 5 sec intervals */`
  - 위 코드는 load average를 5초마다 갱신하려는 의도
- HZ : **"1초당 몇 번 시스템 타이머 인터럽트가 발생하는가"**를 나타내는 값 (커널의 시간 단위, 또는 **1초를 몇 개의 틱(jiffies)으로 나눌 것인가**를 결정하는 상수)
  - 100 :	1초에 100번 인터럽트 발생 → 1 tick = 10ms
  - 250	: 1초에 250번 인터럽트 → 1 tick = 4ms
  - 1000 : 1초에 1000번 인터럽트 → 1 tick = 1ms
- 즉, HZ가 높을수록 load average 갱신 주기가 더 세밀해지고 정확해짐
  - HZ가 100인 시스템 기준으로는 `LOAD_FREQ ≈ 501 jiffies ≈ 5.01초`

## 참고
- [https://www.brendangregg.com/blog/2017-08-08/linux-load-averages.html](https://www.brendangregg.com/blog/2017-08-08/linux-load-averages.html)
