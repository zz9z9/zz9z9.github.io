> 내 애플리케이션에서 'api/foo'라는 요청을 처리하면 외부 API 서버 'api/bar' 호출이 반드시 필요
> 'api/foo' 요청이 급증해서 외부 서버에도 부하가 커진다면 ?


## 어떤 문제가 생길까 ?
- 외부 서버가 다른 요청들을 제대로 처리하지 못하거나, 심각한 경우 애플리케이션이 멈춘다.
- 이로 인해 'api/foo' 요청 또한 처리가 안된다.

## 우리쪽에선 어떤 조치를 할 수 있을까 ?
> 외부 서버 증설이 어려운 상황임을 가정
> api/foo 요청에 대한 응답이 반드시 실시간이어야 한다. (ex : 상품권 사용)
> api/foo 요청에 대한 응답은 반드시 실시간일 필요는 없지만 최대한 빠르게 처리될수록 좋다. (ex : 배민 주문)

### 레디스 같은 외부 스토리지 ?
- `key : value = api url : 처리중인 요청 개수`
  - 요청 들어오면 +1, 처리 끝나면 -1
  - TTL ? 계속 ,, ? 0이면 없어짐 ?

**처리량 제한 상한값 고정 : 들어오는 요청**
> 들어오는 요청에 대해

```java
@Component
public class RateLimitFilter extends OncePerRequestFilter {

    private final RedisRateLimiter rateLimiter;

    public RateLimitFilter(RedisRateLimiter rateLimiter) {
        this.rateLimiter = rateLimiter;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
            throws ServletException, IOException {

        String path = request.getRequestURI();
        long limit = 10L;

        boolean allowed = rateLimiter.tryAcquire(path, limit);
        if (!allowed) {
            response.setStatus(HttpStatus.TOO_MANY_REQUESTS.value());
            response.getWriter().write("Too Many Requests");
            return;
        }

        try {
            filterChain.doFilter(request, response);
        } finally {
            rateLimiter.release(path);
        }
    }
}
```

**처리량 제한 상한값 고정 : 나가는 요청**

```java
@Slf4j
@Aspect
@Component
@RequiredArgsConstructor
public class LimitRequestAspect {

    private final RedisRateLimiter redisRateLimiter;

    @Around("@annotation(com.zz9z9.blogcode.traffic.ratelimiter.LimitRequest)")
    public Object around(ProceedingJoinPoint joinPoint) throws Throwable {
        MethodSignature signature = (MethodSignature) joinPoint.getSignature();
        Method method = signature.getMethod();
        LimitRequest limitRequest = method.getAnnotation(LimitRequest.class);

        String requestId = limitRequest.requestId();
        int count = limitRequest.count();

        boolean acquired = redisRateLimiter.tryAcquire(requestId, count);

        if (!acquired) {
            throw new RateLimitExceededException("Rate limit exceeded for " + requestId + ");
        }

        try {
            return joinPoint.proceed();
        } finally {
            redisRateLimiter.release(requestId);
        }
    }

}
```

```java
@Component
public class ApiCaller {

    @LimitRequest(requestId = "barRequest", count = 10)
    public String requestSomething() {
        try {
            Thread.sleep(5000L);
        } catch (InterruptedException e) {
            throw new RuntimeException(e);
        }

        return "result";
    }

}
```

```java
@Service
@RequiredArgsConstructor
public class RateService {

    private final ApiCaller caller;

    public String doSomething() {
        String result = caller.requestSomething();

        // ... 비즈니스 로직 처리

        return "something";
    }

}
```

**처리량 제한 상한값 유동적으로 변경**
- 외부 서버 헬스체크용 api의 응답시간을 주기적으로 확인해서 응답 속도에 따라 count 제어 ?
=> 매우 많은 곳에서 연동한다면 헬스체크 요청조차도 부하일수 있지않을까 ?
=> 헬스체크 API 응답이 실제 사용 API 상태와 다를 수 있음

- 요청 api 응답 시간을 기반으로 응답 시간이 느려질수록 count 감소, 빨라질수록 count 증가 (최대 상한값은 두고?)
=> 빠른 실패 응답일수도 있음
=> 실패율, timeout 비율 등도 고려할 수 있음
=> minCount, maxCount 설정해서 너무 낮거나 높아지지 않도록 제한
=> Redis 등에 requestId별로 dynamicCount를 저장하고 활용
=> 응답 시간이 긴 경우, 응답 기다리는 동안 아직 dynamicCount가 조정되지 않았을거기 때문에 많은 요청이 허용될 수 있음
=> Sliding Window (슬라이딩 윈도우)
  개념:
  최근 N개의 응답 시간만 저장해서, 그 평균을 계산하는 방식

=> EWMA (Exponential Weighted Moving Average, 지수 가중 이동 평균)
개념:
이전 평균에 새로운 값을 가중치로 반영해 부드럽게 변하는 평균을 만듭니다.

**처리량 제한 : 즉시 실패 응답**

**처리량 제한 : 특정 시간까지는 대기**

**응답 바로 안받아도 될 때**

### 서킷 브레이커

### WebFlux ?

## 생각해볼것들
- `내 서버 처리량 >>> 외부 서버 처리량`이면 ?
=> 즉, 외부 서버 처리량 제한으로 인해 내 처리량의 1/n 만 사용하게되면 너무 아깝지 않나 ?

## 참고
- 토스 슬래시 유량제어
- 가상 면접 사례 4장
