---
title: Sync/Async, Blocking/Non-Blocking
date: 2021-08-07 00:29:00 +0900
---

# 들어가기 전
---
항상 동기적으로만 프로그래밍을 해왔었지만, 비동기적으로 프로그래밍 하는 것도 반드시 알고있어야 한다고 생각한다. (reactive app ?? -> Spring Webflux 등 ?)
비동기면 non-blocking, 동기면 blocking 이라고 생각했는데, 잘못 생각하고있었다.
제대로 알아보자.

# Synchronous vs Asynchronous
---
> Synchronous : 동시 발생[존재]하는, "synchronize(일치시키다, 동시에 일어나다)"는 [syn 같이] + [chron 시간] + [ze 동사]로 만들어지는 단어예요.
> Asynchronous : 동시에 존재[발생]하지 않는

--> 영어 뜻만보면 sync가 여러개를 동시에 실행시키는 느낌쓰 ??
--> 동시에 발생한다는게 (끝남과) 동시에 발생 ??

Synchronous, Asynchronous는 형용사. 그럼 컴퓨터 세계에선 뒤에 어떤 명사랑 자주 쓰일까 ?

Synchronous Programming, Asynchronous Programming ?
Synchronous Execution, Asynchronous Execution ?

task를 처리하는 방식 ??

clock을 알아야하는건가 ??

--> 스레드, 프로세스 입장에서 생각 ??

https://www.makeuseof.com/synchronous-asynchronous-programming-different/

# Blocking vs Non-Blocking
---

# Synchronous / Asynchronous 와  Blocking / Non-Blocking 관계
---
sync면 blocking, async면 non-blocking 아닌가 ??

https://www.cs.unc.edu/~dewan/242/s07/notes/ipc/node9.html



# 다양한 관점
---
1. 관심사의 차이
- Synchronous/Asynchronous는 호출되는 함수의 작업 완료 여부를 누가 신경쓰냐가 관심사다.
  - 호출되는 함수에게 callback을 전달해서, 호출되는 함수의 작업이 완료되면 호출되는 함수가 전달받은 callback을 실행하고, 호출하는 함수는 작업 완료 여부를 신경쓰지 않으면 Asynchronous다.
  - 호출하는 함수가 호출되는 함수의 작업 완료 후 리턴을 기다리거나, 또는 호출되는 함수로부터 바로 리턴 받더라도 작업 완료 여부를 호출하는 함수 스스로 계속 확인하며 신경쓰면 Synchronous다.

- Blocking/NonBlocking은 호출되는 함수가 바로 리턴하느냐 마느냐가 관심사다.
  - 호출된 함수가 바로 리턴해서 호출한 함수에게 '제어권'을 넘겨주고, 호출한 함수가 다른 일을 할 수 있는 기회를 줄 수 있으면 NonBlocking이다.
  - 그렇지 않고 호출된 함수가 자신의 작업을 모두 마칠 때까지 호출한 함수에게 제어권을 넘겨주지 않고 대기하게 만든다면 Blocking이다.

2. 입장의 차이
- Blocking/NonBlocking은 호출한 입장에서의 특징
- Sync/Async는 처리되는 방식의 특징

3. 동작관점의 차이
- Non-Blocking은 제어문 수준에서 지체없이 반환하는 것
- Asynchronous는 별도의 쓰레드로 빼서 실행하고, 완료되면 호출하는 측에 알려주는 것

4.
- Synchronous VS Asynchronous
두 가지 이상의 대상(메서드, 작업, 처리 등)과 이를 처리하는 시간으로 구분한다.
Synchronous: 호출된 함수의 리턴하는 시간과 결과를 반환하는 시간이 일치하는 경우
Asynchronous: 호출된 함수의 리턴하는 시간과 결과를 반환하는 시간이 일치하지 않는 경우

- Blocking VS Non-Blocking
호출되는 대상이 직접 제어할 수 없는 경우 이를 구분할 수 있다.
Blocking: 직접 제어할 수 없는 대상의 작업이 끝날 때까지 기다려야 하는 경우
Non-Blocking: 직접 제어할 수 없는 대상의 작업이 완료되기 전에 제어권을 넘겨주는 경우

5.
- Blocking VS Non-Blocking
블럭킹과 논블럭킹은 대기큐와 호출 결과 시점으로 구분할 수 있다. 설명하기 쉽게 프로그램 A와 B가 있다고 가정하겠다. 프로세스는 프로그램 A에서 B를 호출하는 순서로 진행한다.

Blocking
프로그램 A 에서는 프로그램 B 로직이 수행 완료될 때 까지 대기큐에 들어가 로직이 완료된 이후에나 대기큐에서 프로그램 A가 반환되어 이후 로직을 수행할 수 있다.
프로그램 B는 호출 결과를 로직 수행 완료 이후에 프로그램 A에게 돌려주게 된다.

Non Blocking
프로그램 A는 프로그램 B를 호출한 이후에도 제어권을 가지고 있어 대기큐에 들어가지 않고 다른 로직을 수행할 수 있다.
프로그램 B가 호출된 순간 호출되었다는 결과만 프로그램 A에게 돌려준다.

- Synchronous VS Asynchronous
동기와 비동기는 호출한 결과의 완료 여부를 확인 하는가에 따라 구분할 수 있다.

Sync
프로그램 B가 완료할 때까지 프로그램 A는 기다리게 되므로 아무런 로직도 수행하지 못한다.
ASync
프로그램 B를 호출한 이후에 프로그램 A는 프로그램 B의 완료 여부를 기다리지 않고 다음 로직을 수행한다.

# sync vs async
- Synchronous/Asynchronous는 호출되는 함수의 작업 완료 여부를 누가 신경쓰냐가 관심사다.
  - 호출되는 함수에게 callback을 전달해서, 호출되는 함수의 작업이 완료되면 호출되는 함수가 전달받은 callback을 실행하고, 호출하는 함수는 작업 완료 여부를 신경쓰지 않으면 Asynchronous다.
  - 호출하는 함수가 호출되는 함수의 작업 완료 후 리턴을 기다리거나, 또는 호출되는 함수로부터 바로 리턴 받더라도 작업 완료 여부를 호출하는 함수 스스로 계속 확인하며 신경쓰면 Synchronous다.


- 동기는 두 가지 이상의 대상(함수, 애플리케이션 등)이 서로 시간을 맞춰 행동하는 것이다. 예를들어 호출한 함수가 호출된 함수의 작업이 끝나서 결과값을 반화하기를 기다리거나, 지속적으로 호출된 함수에게 확인 요청을하는 경우가 있다.
  - A와 B가 시작 시간 또는 종료 시간이 일치하면 동기이다. 예를 들어 A, B 쓰레드가 동시에 작업을 시작하는 경우 (예를 들면 자바에서 CyclicBarrier) 메서드 리턴 시간(A)과 결과를 전달받는 시간(B)이 일치하는 경우
  - A가 끝나는 시간과 B가 시작하는 시간이 같으면 동기이다. 예를 들어 자바에서 synchronized와 BlockingQueue가 위와 같은 경우이다.

- 비동기는 동기와 반대로 대상이 서로 시간을 맞추지 않는 것을 말한다. 예를 들어 호출하는 함수가 호출되는 함수에게 작업을 맡겨놓고 신경을 쓰지 않는 것을 말한다. 비동기에 대한 자세한 예제는 아래에서 다룰 것이다.

# blocking vs non-blocking
- Blocking/NonBlocking은 호출되는 함수가 바로 리턴하느냐 마느냐가 관심사다.
  - 호출된 함수가 바로 리턴해서 호출한 함수에게 '제어권'을 넘겨주고, 호출한 함수가 다른 일을 할 수 있는 기회를 줄 수 있으면 NonBlocking이다.
  - 그렇지 않고 호출된 함수가 자신의 작업을 모두 마칠 때까지 호출한 함수에게 제어권을 넘겨주지 않고 대기하게 만든다면 Blocking이다.



- 블럭킹과 논블럭킹은 대기큐와 호출 결과 시점으로 구분할 수 있다.

- 블록킹/논블록킹을 동기/비동기와 같이 생각하는 경우가 많은데, 이는 서로 관점이 다르다. 블록킹/논블록킹은 직접 제어할 수 없는 대상을 처리하는 방법에 따라 나눈다. 직접 제어할 수 없는 대상은 대표적으로 IO, 멀티쓰레드 동기화가 있다.


# asynchronous programming vs multithreading programming

1. Introduction
In this tutorial, we’ll show a simple explanation for asynchronous programming and multithreading programming. Then, we’ll discuss the differences between them.

2. What Is Asynchronous Programming?
An asynchronous model allows multiple things to happen at the same time. When your program calls a long-running function, it doesn’t block the execution flow, and your program continues to run. When the function finishes, the program knows and gets access to the result (if there’s a need for that).

Let’s take an example of a program that fetches two files over a network and combines them:


In an asynchronous system, the solution is to start an additional thread of control. The first thread fetches the first file, and the second thread fetches the second file without waiting for the first thread to finish, and then both threads wait for their results to come back, after which they resynchronize to combine their results.

Another example with a single-thread approach is a program that requests a file from the OS and needs to make a mathematical operation.

In an asynchronous system, the program asks the OS for the file and returns the control to the mathematical operation to be executed on the CPU, while waiting for the file.

One approach to asynchronous programming is to make functions that perform a slow action and take an extra argument, a callback function. The action is started, and when it finishes, the callback function is called with the result.

3. What Is Multithreading Programming?
Multithreading refers to the concurrent/parallel execution of more than one sequential set (thread) of instructions.

On a single processor, multithreading gives the illusion of running in parallel. In reality, the processor is switching by using a scheduling algorithm. Or, it’s switching based on a combination of external inputs (interrupts) and how the threads have been prioritized.

On multiple processor cores, threads are truly parallel. Individual microprocessors work together to achieve the result more efficiently. There are multiple parallel, concurrent tasks happening at once.

A basic example of multithreading is downloading two files from two different tabs in a web browser. Each tab uses a new thread to download the requested file. No tab waits for the other one to finish, they are downloading concurrently.

The following picture shows a simple explanation of concurrent execution of a multithreaded application:


4. Asynchronous vs Multithreading
From the definitions we just provided, we can see that multithreading programming is all about concurrent execution of different functions. Async programming is about non-blocking execution between functions, and we can apply async with single-threaded or multithreaded programming.

So, multithreading is one form of asynchronous programming.

Let’s take a simple analogy; you have a friend, and you decided to make dinner together.

Async is when you say to your friend, “You go to the store and buy pasta. Let me know when you get back, to make dinner together. Meanwhile, I’ll prepare sauce and drinks.”

Threading is, “You boil the water. I’ll heat the tomato sauce. While the water is boiling, ask me and I’ll put the pasta in. When the sauce is hot, you can add cheese. When both are done, I’ll sit down and you serve dinner. Then we eat.”. In the threading analogy, we can see the sequence of “When, Do” events, which represent the sequential set of instructions per each person (thread).

From that analogy, we can conclude that Multithreading is about workers, Asynchronous is about tasks.

5. Which One To Use?
Choosing between the two programming models depends mainly on performance.

Given all possible combinations between sync/async and single/multi-threading, which model should perform better?

In a nutshell, for large scale applications with a lot of I/O operations and different computations, using asynchronous multithreading programming flow, will utilize the computation resources, and take care of non-blocking functions. This is the programming model of any OS!

With more power, comes more responsibility! So if we decided to implement this model, we have to take care of different issues like race condition, deadlocks, shared resources, and callbacks events.


# 참고자료
---
- https://www.baeldung.com/cs/async-vs-multi-threading
- http://homoefficio.github.io/2017/02/19/Blocking-NonBlocking-Synchronous-Asynchronous/
- https://velog.io/@codemcd/Sync-VS-Async-Blocking-VS-Non-Blocking-sak6d01fhx
- https://incheol-jung.gitbook.io/docs/q-and-a/java/or-or-or
