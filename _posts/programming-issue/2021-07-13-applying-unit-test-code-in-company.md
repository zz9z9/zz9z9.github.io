---
title: MSA 기반의 회사 프로젝트에 단위 테스트 코드 적용하기
date: 2021-07-13 22:25:00 +0900
---

# 들어가기 전
---
부끄러운 얘기지만 내가 회사에서 경험했던 프로젝트에는 테스트 코드가 없었다. 제작 당시 테스트 코드 작성에 대한 얘기가 아예 나오지 않았던 것은 아니지만, 당시 여론은
'제작 기간 맞추기도 쉽지 않은데 언제 그걸 하고 앉아있냐'라는 의견이 주를 이뤘다. 나 또한 테스트 코드의 중요성에 대해 잘 알지 못했고, 빡빡한 제작기간으로 인해 밥먹듯이 야근을 해댔기 때문에
개발기간 맞추기에만 급급했던 것 같다.
<br><br>

개발, 테스트 기간을 거쳐 시스템을 가동했고, 다양한 에러들이 터져나오며 정말 밤낮으로 디버깅을 했다. 어떤 문제에 대한 디버깅이 해당 문제는 해결했지만,
기존에 잘 동작하고 있던 부분에 영향을 미쳐서 또 다른 문제를 발생시키는 경우가 상당히 많았다. 여기서 나는 테스트 코드 작성을 하지 않은 것에 대한 댓가(?)를 치루는 것 같았다.
<br><br>

폭풍같은 시간들이 지나고 현재는 나름대로 안정화가 되어 운영을 하고 있지만, 여전히 테스트 코드의 부재는 코드를 리팩토링을 한다거나 새로운 요구사항에 대한 코드를 추가했을 때,
자동화된 테스트를 할 수 없으며 일일이 손으로 테스트를 해야한다는 불편함이 있다.
<br><br>

따라서 나는 지금이라도 테스트 코드를 작성해야겠다고 생각했고, 마이크로서비스 환경에서 [단위 테스트하는 방법을 공부](https://zz9z9.github.io/posts/msa-testing-part1/)한 뒤
회사 프로젝트에 적용해보았다.


# 단위 테스트 코드 작성하기
---
## 적용 범위
- 일단은 가장 핵심이 되는 비즈니스 로직(스프링 기준으로 ServiceImpl)들에 적용을 해보았다.
- 컨트롤러와 이벤트/메시지 핸들러 테스트는 추후에 적용해보고 내용을 추가할 예정이다.

## 무엇을 검증할 것인가 ?
- 일단 내가 속한 팀의 비즈니스 로직 특성은 일반적으로 다음과 같다.
  - 하나 이상의 마이크로서비스에서 데이터를 조회해온 뒤 데이터를 가공한다.
  - 가공한 데이터를 하나 이상의 서비스에 CUD(CREATE / UPDATE / DELETE) 처리를 한다.
  - 타서비스와 통신하는 방식에는 크게 두 가지가 있다.
    - R(조회) : Rest API
    - CUD :  메시지 (브로커 : Kafka)

- 위 특징을 기반으로, 비즈니스 로직에서 검증해야 할 것들은 다음과 같다고 생각했다.
  - 데이터 조회를 위해 특정 서비스를 호출했는지
  - 조회할 때 필요한 항목이 세팅이 됐는지
  - 타서비스에 CUD 처리를 위해 발행하는 이벤트에 데이터가 제대로 세팅이 되었는지
    - 검증 데이터 : 토픽명, 반드시 세팅되어야 할 항목의 값 등
  - 잘못된 데이터가 들어왔을 때, 적절한 예외를 발생시키는지

## 어떻게 검증할 것인가 ?
1. 데이터 조회를 위해 특정 서비스를 호출했는지
  - Mockito를 활용해서 타서비스를 호출하는 OtherServiceProxy 부분을 모킹하고, 조회 메서드 호출시 기대한 데이터를 반환하도록 스텁화한다.
  - verify를 통해 해당 메서드가 호출되었는지 확인한다.
  <img src = "https://user-images.githubusercontent.com/64415489/126074578-7f7c72a8-21b3-43c3-a531-4cdddcc2e832.png" width="90%"/>

2. 조회할 때 필요한 항목이 세팅이 됐는지
  - 단순 값인 경우 Mockito의 ArgumentMatchers eq() 활용

3. 타서비스에 CUD 처리를 위해 발행하는 이벤트에 데이터가 제대로 세팅이 되었는지
  - Mockito의 ArgumentCaptor 활용

## 적용 코드
> 실제 회사 코드를 첨부할 수는 없기 때문에, 대략적인 흐름을 파악할 수 있는 코드를 작성했다.
> 이렇게 하는게 맞는지는 모르겠으나, 최소한 없을 때 보다는 리팩토링 할 때 좀 더 안전하게 할 수 있을것 같다.
> 추후에 더 공부하고 새로운 것들을 알게되면 보완할 예정이다.

```java
public class CoreServiceImplTest {

    @Mock
    private AServiceProxy aServiceProxy;
    @Mock
    private BServiceProxy bServiceProxy;
    @InjectMocks
    private CoreServiceImpl logic;
    private Map<String, Object> inputMessage = new HashMap<>();

    private AServiceData getAServiceSampleData() {
        AServiceData data = new AServiceData();
        data 세팅 ...

        return data;
    }

    private BServiceData getBServiceSampleData() {
        BServiceData data = new BServiceData();
        data 세팅 ...

        return data;
    }

    private void initInputMsg() {
        inputMessage에 값 세팅...
    }

    private void initStub() {
        when(aServiceProxy.조회메서드(eq(value1), eq(value2), isNull()))
                .thenReturn(getAServiceSampleData);

        when(bServiceProxy.조회메서드(anyList())
                .thenReturn(getBServiceSampleData);
    }


    @Before
    public void initMock() {
        MockitoAnnotations.initMocks(this);
        initInputMsg();
        initStub();
    }

    @Test
    public void 타서비스_테이블에_저장() {
        logic.invoke(inputMessage);

        ArgumentCaptor<SaveData> captor = ArgumentCaptor.forClass(SaveData.class);

        verify(aServiceProxy).저장메서드(captor.capture());

        SaveData data = captor.getValue();
        assertThat(data).isNotNull();
        assertThat(저장한 데이터의 값).isEqualTo(기대하는 값);
        .
        .
        .
    }

    @Test
    public void 조회결과_없는경우_예외처리() {
        when(aServiceProxy.조회메서드(eq(value1), eq(value2), isNull()))
                .thenReturn(null);

        assertThrownBy(() -> logic.invoke(inputMessage).isInstanceOf(특정Exception.class);
    }

// 이하생략...

}
```

# 느낀점
---
- 개발하는 도메인을 제대로 파악하지 못한다면 어떤 값이 중요한지, 어떤 값을 검증해야 할지 잘 모르기 때문에 제대로된 테스트 코드 작성이 어려울 것 같다.
- 메서드는 최대한 나눠져 있는게 테스트하기에 수월한 것 같다.
- 꾸준히 연습하자.


# 더 공부할 부분
---
- @RunWith(MockitoJUnitRunner.class) vs initMock()
- JUnit5



