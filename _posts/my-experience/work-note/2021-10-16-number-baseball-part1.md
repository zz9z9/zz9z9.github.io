---
title: 숫자 야구 게임 구현하기 (1)
date: 2021-10-16 23:00:00 +0900
categories: [경험하기, 작업 노트]
tags: []
---

# 들어가기 전
---
박재성님이 운영하시는 NextStep의 [자바 플레이그라운드 with TDD, 클린코드](https://edu.nextstep.camp/s/RFY359FE)를 몇 달 전에 끊어놨지만 ~~이직 준비하느라~~ 이제서야 실습해본다.
첫 번째 단계인 숫자 야구 게임을 먼저 요구사항만 보고 TDD 없이 구현해보려고 한다. 그리고 조영호님께서 쓴 『객체지향의 사실과 오해』에서 읽은 유스케이스와 도메인 모델 개념을 활용해서 애플리케이션을 설계해보고자 한다.
이 단계를 마치면 박재성님의 피드백 강의를 듣고 TDD 방식으로 다시 개발해보려고 한다.

# 기능 요구 사항
---
기본적으로 1부터 9까지 서로 다른 수로 이루어진 3자리의 수를 맞추는 게임이다.

- 같은 수가 같은 자리에 있으면 스트라이크, 다른 자리에 있으면 볼, 같은 수가 전혀 없으면 포볼 또는 낫싱이란 힌트를 얻고, 그 힌트를 이용해서 먼저 상대방(컴퓨터)의 수를 맞추면 승리한다.
  - e.g. 상대방(컴퓨터)의 수가 425일 때, 123을 제시한 경우 : 1스트라이크, 456을 제시한 경우 : 1볼 1스트라이크, 789를 제시한 경우 : 낫싱
- 위 숫자 야구 게임에서 상대방의 역할을 컴퓨터가 한다. 컴퓨터는 1에서 9까지 서로 다른 임의의 수 3개를 선택한다. 게 임 플레이어는 컴퓨터가 생각하고 있는 3개의 숫자를 입력하고, 컴퓨터는 입력한 숫자에 대한 결과를 출력한다.
- 이 같은 과정을 반복해 컴퓨터가 선택한 3개의 숫자를 모두 맞히면 게임이 종료된다.
- 게임을 종료한 후 게임을 다시 시작하거나 완전히 종료할 수 있다.


# 유스케이스
---
- 숫자야구 게임을 시작한다.
- 플레이어가 숫자를 제시했을 때, 상대방은 해당 숫자에 대한 결과를 리턴해준다.
  - 제시할 수 있는 숫자는 1~9로만 구성된 세 자리 수이다.

# 도메인 모델
---
## 의식의 흐름 1
- Player / Messenger / Opponent / GameManager

- Player가 입력한 숫자를 Opponent가 받기 위해서는 중간에 매개하는 역할이 있다고 생각. 만약 직접 전달하는거라고 하면 Player와 Opponent에서 수행하는 로직에 `System.out.print`와 같은 메서드가 들어가게 될 것이다.
  - 이는 비즈니스 로직의 흐름을 방해할 뿐더러, Player와 Opponent가 수행해야할 책임도 아니라고 생각했다.
  - 또한 입,출력 방식이 바뀌는 경우 Player와 Opponent 곳곳에 산재되어 있는 관련 코드들을 일일이 수정해야 할 것 이다.

- 따라서, Messenger라는 매개체를 통해 Player와 Opponent는 소통하는 것이 좀 더 자연스럽고 유지보수하기에도 좋다고 생각했다.
  - 서로의 메시지를 전달하는 수단이 현재는 console view 이지만, 추후에 수단이 바뀌더라도 Player와 Opponent의 코드는 변경될 필요가 없다.
  - Player와 Opponent에는 비즈니스 로직과 관련된 코드만 있게된다.

- 이렇게 하고 나니, 게임을 시작하고 종료하는 것에 대한 책임은 어떤 객체가 가져야할지에 대한 것이 남게되었다.
  - 게임을 중재하는 역할을 위한 객체를 별도로 만들어야하나? 라고 생각했지만 Messenger의 역할을 좀 더 넓은 범위로 추상화해서 GameManager라는 객체를 만드는게 어떨가 생각해봤다.

## 의식의 흐름 2
- 현실 세계에서는 게임을 조작하려면 사용자와 같은 누군가가 '실행'하고 '종료'하는 행위를 하기 때문에 위에서 `GameManager`를 생각하려 했던 것 같다.
  - 하지만, '객체지향의 사실과 오해'에서 봤듯이 현실 세계와 객체는 완전히 일치하기가 어렵고 그럴 필요도 없다고 했다. (표현적 차이)
  - 따라서, GameManager 대신 그냥 `BaseBallGame`이라는 게임 객체가 게임을 실행하고, 종료하는 역할을 하게 하면 될 것 같다.


# 책임 분배
---
- Player
  - 게임을 시작, 종료 의사를 밝힌다.
  - 숫자를 Messenger에게 전달한다.
  - 유효한 숫자인지 검증한다.

- BaseBallGame
  - 게임 시작, 또는 종료
    - Player에게 시작/종료 의사를 묻는다.
  - Player -> Opponent로 숫자 전달
  - Opponent -> View로 결과 전달

- Opponent
  - 전달받는 숫자에 대한 야구 결과를 리턴한다.

# 프로그래밍 요구사항
---
- 자바 코드 컨벤션을 지키면서 프로그래밍한다.
  - 기본적으로 Google Java Style Guide을 원칙으로 한다.
  - 단, 들여쓰기는 '2 spaces'가 아닌 '4 spaces'로 한다.

- indent(인덴트, 들여쓰기) depth를 2가 넘지 않도록 구현한다. 1까지만 허용한다.
  - 예를 들어 while문 안에 if문이 있으면 들여쓰기는 2이다.
  - 힌트: indent(인덴트, 들여쓰기) depth를 줄이는 좋은 방법은 함수(또는 메소드)를 분리하면 된다.

- else 예약어를 쓰지 않는다.
  - 힌트: if 조건절에서 값을 return하는 방식으로 구현하면 else를 사용하지 않아도 된다.
  - else를 쓰지 말라고 하니 switch/case로 구현하는 경우가 있는데 switch/case도 허용하지 않는다.

- 모든 로직에 단위 테스트를 구현한다. 단, UI(System.out, System.in) 로직은 제외
  - 핵심 로직을 구현하는 코드와 UI를 담당하는 로직을 구분한다.
  - UI 로직을 InputView, ResultView와 같은 클래스를 추가해 분리한다.

- 3항 연산자를 쓰지 않는다.
  - 함수(또는 메소드)가 한 가지 일만 하도록 최대한 작게 만들어라.


# 구현시 어려웠던 부분
---
- 숫자에 대해 1스트라이크, 2볼 등에 대한 결과를 반환하는 메서드를 구현할 때 `indent(인덴트, 들여쓰기) depth를 2가 넘지 않도록 구현한다. 1까지만 허용한다` 이 규칙을 지키기가 어렵다. (3항 연산자를 쓰지 않는다. 라는 규칙도 있기 떄문에..)
- `play()` 내부에 UI 관련 로직이 들어가버렸다 ... 분리할수는 없을까
- 구현해놓고 보니 테스트 하기가 어렵다 예를 들어 아래와 같은 메서드에 대해서는 어떻게 테스트해야할까 ?? 그리고 왜 현재는 테스트하기가 어려운 코드인걸까 ??
  - '테스트'라는 것은 결국 `특정 input 일 때 특정 output이 나오는지 확인하는 것`이라고 생각하는데 `keepContinue()` 메서드의 경우, input을 외부에서 입력할 수 없기 때문에 어떤 input에 대한 output이 무엇이다 라고 작성할 수가 없다.

```java
public class Player {
    private final Scanner sc = new Scanner(System.in);

    public boolean keepContinue() {
        int continueFlag = sc.nextInt();
        if(continueFlag==1) {
            return true;
        }

        return false;
    }

    public int getPredictNumber() {
        return sc.nextInt();
    }
}
```

- 근데 테스트를 `특정 input 일 때 특정 output이 나오는지 확인하는 것`라고 정의하면
  - 리턴값 void에 대한 테스트는 어떻게해야하지 ?? (setNumber이런거)
