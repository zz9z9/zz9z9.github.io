---
title: CompletableFuture, Parellel Stream을 통해 성능 개선해보기
date: 2021-08-18 14:00:00 +0900
categories: [개발 일기]
tags: [JAVA, 비동기, Completable Future, Parellel Stream]
---

# 들어가기 전
---
현재 운영하고 있는 시스템(자바 버전8)에서 조회 시간이 꽤 오래 소요되는 화면들이 있었다. 모든 화면이 그런것은 아니었지만 몇몇 화면의 백엔드 로직은 아래와 같이 되어있었다.
```java
public Map<String, Object> retrieve() {
  Object result1 = testProxy.findSomething(param1); // blocking
  Object result2 = testProxy.findSomething(param2); // blocking
  Object result3 = testProxy.findSomething(param3); // blocking

  Map<String, Object> toClient = new HashMap<>();
  toClient.put("result1", result1);
  toClient.put("result2", result2);
  toClient.put("result3", result3);

  return toClient;
}
```
즉, 모든 결과를 하나의 Map에 담아서 클라이언트에게 리턴하는 형식이었다. 하지만, 조회 결과들은 서로 독립적이었기 때문에 굳이 sequential하게 처리할 필요가 없을 것 같다는 생각이 들었다.
따라서 [자바에서의 비동기 처리를 공부](https://zz9z9.github.io/posts/java-asyncronous-programming/) 하고 해당 로직을 개선해보았다.

# Before
---
- 로직은 위에서 살펴본 것과 같고, insomnia를 활용해 응답 시간을 측정해보았다.

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/129858533-8a875433-e8b7-4ba8-b082-e525821d12f1.png" width="50%"/>
  <figcaption align="center">개선 전(약 5.7초 소요) <br> (핸드폰 카메라로 찍어 화질이 좋지 않은 점 양해부탁드립니다.)</figcaption>
</figure>

# After. CompletableFuture 적용
## Case1. 성능 개선됨
위에서 살펴본 로직을 다음과 같이 변경하여 약 2배 이상 빠르게 조회되는 것을 확인할 수 있었다.
```java
public Map<String, Object> retrieve() {
  CompletableFuture<Object> future1 =
                CompletableFuture.supplyAsync(() -> testProxy.findSomething(param1));

  CompletableFuture<Object> future2 =
                CompletableFuture.supplyAsync(() -> testProxy.findSomething(param2));

  CompletableFuture<Object> future3 =
                CompletableFuture.supplyAsync(() -> testProxy.findSomething(param3));


  Map<String, Object> toClient = new HashMap<>();
  toClient.put("result1", future1.join());
  toClient.put("result2", future2.join());
  toClient.put("result3", future3.join());

  return toClient;
}
```

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/129860019-c646c1b2-5d3b-4b99-a922-51220b76f178.png" width="50%"/>
  <figcaption align="center">CompletableFuture 적용 후(약 2.2초 소요) <br> (핸드폰 카메라로 찍어 화질이 좋지 않은 점 양해부탁드립니다.)</figcaption>
</figure>

### get() vs join()
- Future의 결과를 가져오기 위한 메서드로는 `get()`과 `join()`이 있는데 `get()`의 경우 checked exception/unchecked exception, `join()`의 경우 unchecked exception을 발생시킨다.
- 좀 더 공부해봐야겠지만, 현재 드는 생각으로는 `get()`에서 체크하는 `ExecutionException`, `InterruptedException`, `TimeoutException(timeout 속성 사용시)`이 발생하더라도 호출하는 입장에서는 명확한 복구 대책이 없을 것 같다.
- 따라서, `join()`을 활용하고 혹여나 런타임시 예외가 발생하면 ExceptionHandler(`@ControllerAdvice`, `@ExceptionHandler`)에서 처리하여 결과적으로 클라이언트(브라우저)에 문제가 생겼다는 것을 전달한다.
- 사용자는 몇 번의 조회 시도를 더 해보고 안되면 관리자에게 연락할 수 있도록 한다.

### CompletableFuture 사용시 while문을 통해 결과 확인 ?
CompletableFuture를 공부하면서 Future의 결과를 가져오기전에 작업이 완료됐는지 확인하는 아래와 같은 샘플코드를 접할 수 있었다.

```java
ExecutorService executorService = Executors.newSingleThreadExecutor();

CompletableFuture<String> future = new CompletableFuture<>(); // creating an incomplete future

executorService.submit(() -> {
   Thread.sleep(500);
   future.complete("value"); // completing the incomplete future
   return null;
});

while (!future.isDone()) { // checking the future for completion
   Thread.sleep(1000);
}

String result = future.get(); // reading value of the completed future
logger.info("result: {}", result);

executorService.shutdown();
```

내가 알기로 get, join은 작업이 완료될때까지 blocking 하는 메서드인데 왜 굳이 while이 필요할까? 라는 생각이 들어 [StackOverflow에 질문](https://stackoverflow.com/questions/68729877/refactoring-blocking-to-async-code-using-completablefuture)을 해봤고, 결과적으로 답변자들은 while문이 필요하지 않다는 답변을 남겼다. 이 사람들도 모르는 무언가가 있을지는 몰라도, 나 또한 굳이 while문이 필요하지 않은 것 같다는 생각이었기에 개선한 코드에서 알 수 있듯이 while문은 배제했다.

#### 참고. StackOverflow 답변
*"while문을 사용해야 한다면 제 코드의 경우 다음과 같이 작성해야하는게 좋을까요?"* 에 대한 답변이다.
```java
CompletableFuture<Void> allFutures = CompletableFuture.allOf(future1, future2, future3);

 while(!allFutures.isDone()){}

 Map<String, Object> toClient = new HashMap<>();
  toClient.put("result1", future1.get());
  toClient.put("result2", future2.get());
  toClient.put("result3", future3.get());
```

- 답변1.
> <q>The actively blocking loop while(!allFutures.isDone()){} is not okay and will melt your CPU (100% CPU usage). If you want to wait until all futures are done, just do allFutures.join() or allFutures.get(). That will be much better.</q> <br>
> **→ while문이 CPU에 과부하를 줄 것이고 get 이나 join이면 충분하다.**

- 답변2.
> <q>The first “Code after refactoring” is fine, the subsequent stuff is horrible. Why do you think you have to compare your code to something you “found somewhere”? Either, it’s a reputable source you can cite (which also usually explains why it does something in a certain way), or it’s not worth discussing.</q> <br>
> **→ 끔찍한 코드이며, 다른 사람의 코드에 근거가 부족하다면 굳이 비교하지 마라. ~~(혼났음..)~~**

## Case2. 성능 개선 되지 않음
비슷한 로직을 가진 다른 화면에도 동일하게 적용해봤지만 성능 개선이 되지 않는 경우도 있었다. 원인을 살펴보니, 여러 개의 조회 메서드 중, 특정 하나에서 시간이 오래걸리는 경우였다.
그렇게 되면, 비동기로 처리하더라도 결국 모든 결과를 가져오는데 걸리는 시간은 제일 오래 걸리는 메서드 기준이므로, 비동기로 처리하는 이점을 누릴 수 없다.
Case1의 경우 측정해보니 세 개의 메서드가 거의 동일한 시간이 걸렸다. 즉, 적용하고자 하는 로직이 어떤 특성을 갖는지 파악하고 적용해야 개선 효과를 얻을 수 있을 것 같다.


# After. Parellel Stream 적용
위에서 살펴본 로직을 다음과 같이 변경하였고, 개선 전에 비해 빨라졌지만 CompletableFuture와 비교했을 때는 좀 더 느린 것을 확인할 수 있었다.
둘 다 기본적으로 fork-join common pool을 사용하지만, Stream에서는 그룹화하는 부분(`toMap()`) 부분 때문에 CompletableFuture에 비해 시간이 좀 더 걸리는 것 같다.

```java
public Map<String, Object> retrieve() {
        Map<String, String> queries = new HashMap<>();
        queries.put("result1", "queryId");
        queries.put("result2", "queryId2");
        queries.put("result3", "queryId3");

        return queries.entrySet().parallelStream()
                .collect(Collectors.toMap(
                        e -> e.getKey(),
                        e -> testProxy.findSomething(e.getValue(), params))
                );
}
```

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/129866213-f98d0837-7654-471c-a8b1-35f0a5e4f4f8.png" width="50%"/>
  <figcaption align="center">CompletableFuture 적용 후(약 3.8초 소요) <br> (핸드폰 카메라로 찍어 화질이 좋지 않은 점 양해부탁드립니다.)</figcaption>
</figure>

# 결론
---
- 사실 5초에서 2초로 개선은 되었지만, 2초도 절대 빠른속도는 아니라고 생각한다. 애플리케이션 로직뿐 아니라, 근본적인 쿼리를 수정해서 성능을 개선해보고 싶다.
아직은 학습이 부족하기에 차근차근 공부해서 쿼리 튜닝도 할 수 있도록 해보자.

- 사실 `supplyThen()` 등 다양한 메서드를 활용하여 비동기적으로 파이프라인을 구축할 수 있다는게 CompletableFuture의 큰 장점인 것 같다. 아직은 맛보기에 불과하지만 앞으로 점차 다양한 메서드를 활용해서
CompletableFuture를 잘 활용해보자.

# 더 공부해야할 부분
---
- 쿼리 성능 개선
