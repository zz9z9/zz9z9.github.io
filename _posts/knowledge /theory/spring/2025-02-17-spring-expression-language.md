---
title: Spring - SpEL(Spring Expression Language)
date: 2025-02-17 22:25:00 +0900
categories: [지식 더하기, 이론]
tags: [Spring]
---

## SpEL (Spring Expression Language) ?
>  런타임 시 객체 그래프를 조회하고 조작할 수 있도록 지원하는 표현 언어

- 목적
  - 자바에서 사용할 수 있는 표현 언어는 여러 가지가 있으며, 대표적으로 OGNL, MVEL, JBoss EL 등이 있다.
  - 하지만 Spring 커뮤니티에서는 Spring 포트폴리오 전반에서 사용할 수 있는 단일 표현 언어가 필요했음

- 특징
  - SpEL은 Spring 프레임워크의 여러 기능에서 표현식을 평가하는 기본 메커니즘으로 사용되지만, Spring과 직접적으로 결합된 것은 아닙니다.
  - 즉, 독립적인 표현 언어로도 활용할 수 있으며, 다른 표현 언어 구현과 통합될 수도 있습니다.

**※ 표현 언어란 ?**
> 특정 객체나 데이터를 쉽게 조회하고 조작할 수 있도록 도와주는 간단한 문법

- 목적
  - 표현 언어를 사용하면 자바 코드 없이도 간단한 연산, 메서드 호출, 프로퍼티 조회 등을 수행할 수 있습니다.
  - 예를 들어, Spring에서 SpEL을 사용하면 XML 설정이나 애노테이션에서 복잡한 Java 코드를 작성하지 않고도 표현식을 이용해 값을 설정할 수 있습니다.

- 예시
  // foo.jsp
  ${user.name}  <!-- user 객체의 name 프로퍼티 출력 -->
  ${order.totalPrice > 500}  <!-- 주문 금액이 500 이상인지 여부 반환 -->

@Value("#{user.name}") // user 객체의 name 프로퍼티 값 설정
private String userName;

@Value("#{order.totalPrice > 500 ? 'VIP' : 'Normal'}") // 조건식 사용
private String userType;

## SpEL 직접 사용 예시
> SpEL supports a wide range of features such as calling methods, accessing properties, and calling constructors.


**EX1**
ExpressionParser parser = new SpelExpressionParser();
Expression exp = parser.parseExpression("'Hello World'.concat('!')");
String message = (String) exp.getValue(); // "Hello World!"

**EX2**
ExpressionParser parser = new SpelExpressionParser();

// invokes 'getBytes().length'
Expression exp = parser.parseExpression("'Hello World'.bytes.length");
int length = (Integer) exp.getValue();

**EX3**
// #은 SpEL에서 변수, 메서드 매개변수, 컨텍스트 내의 특정 객체를 참조할 때 사용됩니다.
// 즉, 표현식 내부에서 "이름이 있는 값"을 참조할 때 #을 사용
@WithLock(type = LockType.DELETE, key = "#contactNums")
public List<Client> removeByIds(List<String> contactNums) {
...``
}

    @WithLock(type = LockType.UPDATE, key = "#toClient.contactNum")
    public Client update(Client toClient) {
		...
    }


import org.springframework.expression.ExpressionParser;
import org.springframework.expression.spel.standard.SpelExpressionParser;
import org.springframework.expression.spel.support.StandardEvaluationContext;
...

```java
@Aspect
@Component
@RequiredArgsConstructor
public class LockAspect {

    private final LockManager lockManager;
    private final ExpressionParser parser = new SpelExpressionParser();

    @Around("@annotation(withLock)")
    public Object around(ProceedingJoinPoint joinPoint, WithLock withLock) throws Throwable {
        List<String> keys = getLockKey(joinPoint, withLock.key());

        ...
    }

    private List<String> getLockKey(ProceedingJoinPoint joinPoint, String keyExpression) {
        MethodSignature signature = (MethodSignature) joinPoint.getSignature();
        Object[] args = joinPoint.getArgs();					// 파라미터 가져옴
        String[] paramNames = signature.getParameterNames();	// 파라미터 이름 가져옴
        StandardEvaluationContext context = new StandardEvaluationContext();

        for (int i = 0; i < paramNames.length; i++) {
            context.setVariable(paramNames[i], args[i]); // ex : toClient, Client
        }

		// keyExpression : #contactNums, #toClient.contactNum
        Object keyObject = parser.parseExpression(keyExpression).getValue(context); // Evaluate this expression in the provided context and return the result of evaluation.

        if (keyObject instanceof List) {
            return (List<String>) keyObject;
        } else if (keyObject instanceof String) {
            return List.of(keyObject.toString());
        }

        return Collections.emptyList();
    }

}
```


## 주요 컴포넌트
**ExpressionParser**
- 표현식 문자열을 해석(파싱)하는 역할을 담당
  - parser.parseExpression(…​)
  - ParseException이 발생할 수 있음

- ParseException 예시

parser.parseExpression("10 ++ 20"); //  SpEL에서 지원되지 않는 연산자
parser.parseExpression("'Hello ");  // 닫히지 않은 문자열 리터럴
parser.parseExpression("(10 + 20"); // 닫히지 않은 괄호
// 등등...

**Expression**
- 정의된 표현 문자열(expression string)을 평가(evaluation)
  - 평가(evaluation) : 표현식(Expression)을 실행하여 실제 값을 계산하는 과정
  - exp.getValue(…​)시 EvaluationException 발생 가능

- EvaluationException 예시
  parser.parseExpression("#unknownVar");  // 존재하지 않는 변수 참조
  parser.parseExpression("'hello' + 10"); // 잘못된 데이터 타입 변환

**EvaluationContext**
> 표현식을 평가할 때 속성(Property), 메서드(Method), 필드(Field)를 해석하고, 타입 변환을 수행하는 데 사용

| 구현체 | 설명 | 특징 | 사용 사례 |
| ---- | ----| ---- | ----|
| SimpleEvaluationContext | 제한된 SpEL 기능 제공 | - Java 타입 참조, 빈 참조, 생성자 호출 불가 <br> - 속성 읽기/쓰기 제어 가능 <br> - DataBindingPropertyAccessor 사용 가능 | 데이터 바인딩, 속성 기반 필터링 |
| StandardEvaluationContext | 전체 SpEL 기능 제공 | - Java 타입 참조, 빈 참조, 생성자 호출 가능 <br> - 메서드 호출 가능 <br> - 기본 루트 객체 설정 가능 | 복잡한 표현식 평가, 전체 SpEL 기능 활용 |

=> AOP 포인트컷도 ?
