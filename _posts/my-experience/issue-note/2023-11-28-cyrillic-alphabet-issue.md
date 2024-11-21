---
title: 키릴문자를 아시나요 ?
date: 2023-11-28 10:25:00 +0900
categories: [경험하기, 이슈 노트]
tags: []
---

## 상황
- 담당하는 서비스에서 발행한 쿠폰 번호를 사용자가 앱에서 입력했는데 등록되지 않는다는 CS가 접수
- 로그에 남은 해당 쿠폰의 앞자리를 복사하여 DB에서 조회해봤는데 결과가 없음
- 하지만, 사용자가 보내준 스크린샷에 있는 쿠폰 번호를 직접 입력해서 조회하면 결과가 있음

## 원인 파악하기
- 아래 코드로 로그에서 복사한 경우와 직접 입력한 경우를 비교해보았다.

```java
import java.util.Scanner;

public class Main {

    public static void main(String[] args) {
       Scanner sc = new Scanner(System.in);
       String s = sc.nextLine();

       char[] chars = s.toCharArray();
       for (char c : chars) {
           System.out.println("char to int for "+ c + "=" +(int) c);
       }
    }
}
```

- 좌 : 로그에서 복사, 우 : 직접 입력

![image](/assets/img/cyrillic-issue-img1.png)

* 앞 네 글자(M3AE)의 decimal code가 다른 것을 알 수 있다.
* 로그에서 복사한 `M3AE`는 [키릴 문자](https://ko.wikipedia.org/wiki/%ED%82%A4%EB%A6%B4_%EB%AC%B8%EC%9E%90)라고 불리는 문자열이라고 한다.
* 왼쪽이 키릴 문자, 오른쪽이 라틴 문자 (일반 알파벳) - [참고 사이트](https://www.codetable.net/decimal/1052)

![image](/assets/img/cyrillic-issue-img2.png)

## 상황재현
1) (아이폰 기준) 키릴 문자 키보드 세팅 <br>
2) M3AE는 키릴 문자 키보드로, 나머지 문자는 일반 영어 키보드로 입력 <br>
3) 서버 로그에서도 M3AE 부분은 키릴문자로 찍힘

하지만 실제 사용자가 이렇게 입력했을리는 절대 없을 것 같다.

## 결론
- 사용자분께 확인한 결과 **키보드 어플**을 사용하셨고 기본 키보드로 입력했을 때 정상 등록됨을 확인했다.

