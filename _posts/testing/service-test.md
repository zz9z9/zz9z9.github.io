---
title: Service는 어떤 부분을 테스트 해야할까 ?
date: 2025-05-07 22:20:00 +0900
categories: [생각해보기, 코드 작성]
tags: []
---

## Service 레이어의 책임 ?
- 애플리케이션이 다루는 **도메인(비즈니스)에 특화된 요구사항**을 처리한다고 생각
  - 예를 들어, Controller는 HTTP 요청/응답 등 웹과 관련된 요구사항이라고 생각

## 그럼 Service 레이어의 어떤 부분을 검증해야 신뢰도 높은 애플리케이션이 될 수 있을까 ?
- 정상적인 상황에서
  - 비즈니스 요구사항을 제대로 처리하는지
    -> 비즈니스 요구사항을 처리하려면 반드시 정상 동작해야하는 부분들에 대한 테스트 ?
    -> 반드시 정상 동작해야하는 부분들 ?
      -> 음 ,, '상품권 사용 처리'를 생각해보면 '마일리지 적립 api 호출'은 반드시 필요함.
        -> 10번 넘게 시도했을때 제대로 블로킹되는지 이런 부분들은 반드시 정도까지는 아니라고 생각, 경우에 따라서는 운영에서 이런게 매우 중요한 상황이라고 한다면, 검증해야 한다고 생각. 즉 맥락에 따라 달라질 수 있다고 생각.
        -> '운영자에게 알림' 등도 마찬가지 -> 어떤 이벤트가 발생했을 때, 적절한 대응을 하는 자동화된 시스템이 있고, 운영자에게 이를 알리는건 참고용 정도인 느낌인 경우엔 '운영자에게 알림'까지 테스트를 작성할 필요가 없을 수 있지만, 아직 초기이고 이슈 발생시 운영에서 매우 중요한 대응들을 한다면 이 부분에 대한 테스트는 필수일 것으로 생각.

- 비정상적인 상황에서
  - 호출자에게 적절한 응답을 전달하는지
  - 비정상적인 요청이 시스템에 불필요한 이슈를 발생시키지 않도록, 방어가 잘 이루어지는지

## 테스트 작성시 생각해볼 것들

### Spring Context가 필요할까 ?
- `FooService`에서 의존하는 객체들을 생성하기 위해 해당 객체들에서 의존하는 것들을 또 알아야하는 식이면 Spring Context가 있어야 테스트가 가능하지 않을까 생각

### 테스트 더블을 사용해야할까 ? 사용한다면 어떤식으로 해야할까 ?
- 근데 서비스 레이어에서 '도메인 로직 처리를 제대로 하는지'에 대한 부분은 결국 api나 db 호출 정도밖에 없지 않나 ??

**DB에 접근하는 DAO(Data Access Object)**
**외부 API 호출**

**기타 ?**

### FooService를 생성하기 위한 의존성이 너무 많다 ?



```java
@PostMapping("/api/gift/use")
public ResponseEntity useGift(@RequestBody @Valid GiftProcessRequest giftProcessRequest, Errors errors) throws GiftcardApiCheckedException {
    if (errors.hasErrors()) {
        return ResponseEntity.badRequest().build();
    }

    GiftUseResponseDTO responseDTO = giftUserService.useGift(giftProcessRequest.getPinNo(), giftProcessRequest.getIdNo(), giftProcessRequest.getClientIp(), giftProcessRequest.getTransactionNo());
    return ResponseEntity.ok(ApiResponse.getSuccess(responseDTO));
}
```

```java
@Slf4j
@Service
@RequiredArgsConstructor
public class GiftUserService {

    private final MileageApiService mileageApiService;
    private final BlockService blockService;

    private final MileageApiRequestGenerateService mileageApiRequestGenerateService;
    private final GiftUserValidationService giftUserValidationService;

    private final GiftUseValidator giftUseValidator;
    private final GiftUseStore giftUseStore;
    private final GiftUseManager giftUseManager;
    private final MileageAccumulator mileageAccumulator;
    private final MileageManager mileageManager;

    private final GiftUserRepository giftUserRepository;
    private final GiftInitializeRepository giftInitializeRepository;

    // 다른 도메인 로직들 ...

    @Transactional
    public GiftUseResponseDTO useGift(String pinNo, String idNo, String clientIp, String transactionNo) throws GiftcardApiCheckedException {

        // [유효성 검사]
        GiftUseInfo giftUseInfo = giftUserRepository.selectGiftUseInfoByPinNo(pinNo);
        giftUseValidator.validate(giftUseInfo, idNo, pinNo, clientIp, transactionNo);

        // [상품권 사용]
        giftUseManager.use(pinNo, idNo);

        // [마일리지(실제 페이코 포인트) 적립]
        MileageAccumulateResult accumulateResult = mileageAccumulator.accumulate(giftUseInfo, idNo);

        // 적립 실패 (예외 발생시킴)
        if (!accumulateResult.isSuccess()) {
            handleFailure(accumulateResult, giftUseInfo, pinNo, idNo);
        }

        // 적립 성공
        giftUseStore.saveGiftUseInfo(pinNo, giftUseInfo.getGiftPublicationNo(), idNo, accumulateResult.getMileageTradeNo());
        giftUseManager.informGiftUseInfo(giftUseInfo.getOrderTypeCode(), giftUseInfo.getOrderNo(), idNo, pinNo);

        return GiftUseResponseDTO.from(accumulateResult.getAccumulateInfo());
    }

    private void handleFailure(MileageAccumulateResult accumulateResult, GiftUseInfo giftUseInfo, String pinNo, String idNo) throws GiftcardApiCheckedException {
        // 이미 적립되었는데 상품권 쪽에는 정보 업데이트 안되어 있는 경우
        if (accumulateResult.alreadyAccumulated()) {
            MileageTrade trade = mileageManager.getMileageTrade(pinNo);
            giftUseStore.syncMileageTradeInfo(trade);
            giftUseManager.informGiftUseInfo(giftUseInfo.getOrderTypeCode(), giftUseInfo.getOrderNo(), trade.getMemberKey(), pinNo);

            // 롤백 되지 않게 Checked Exception 발생시킴
            throw new GiftcardApiCheckedException(ErrorLogLevel.WARN, String.format("gift pin already used : %s", MaskingUtil.getMaskedPinNo(giftUseInfo.getPinNo())), GiftcardApiResultCode.GIFT_PIN_USED);
        }

        if (!accumulateResult.hasUnknownError()) {
            blockService.saveFailureHistory(idNo);
        }

        // 한도 초과 관련 실패인 경우엔 마일리지 쪽에서 내려온 응답 메세지 전달
        // 그 이외의 실패인 경우엔 범용적인 메세지 전달
        String clientMessage = accumulateResult.isLimitExceed() ? accumulateResult.getMessage() : GiftcardApiResultCode.GIFT_MILEAGE_ACCUMULATE_FAIL.getClientMessage();
        throw new GiftcardApiException(ErrorLogLevel.ERROR, String.format("mileageApiCall - mileageAccumulate fail : %s", giftUseInfo), GiftcardApiResultCode.GIFT_MILEAGE_ACCUMULATE_FAIL, clientMessage);
    }

}
```

- FooService는 어떤 부분을 테스트 해야할까 ?
  - 가져야할 책임에 대해 => 예를 들어, GiftcardUseService는 '상품권 사용'에 대한 책임을 갖는다.
  - 그럼 '상품권 사용'에 대한 어떤 부분을 검증해야 신뢰도 높은 서비스가 될 수 있을까 ?
    - 정상 케이스 => 이 부분만큼은 반드시 보장돼야한다. (도메인 로직)
      - 마일리지 적립 API를 호출한다. => 상세한 구현을 아는건가 ? => 그럼 적립 API는 너무 저수준이면, 마일리지 API를 호출하는 컴포넌트의 특정 메서드가 호출됐는지 ? => 이것도 상세 구현을 아는거지만, 어떤 API를 호출하는지 아는 것보단 조금 더 높은 추상화 단계라고 생각이들긴함
        - 응답 코드에 따른 액션
      - 사용처리가 된다. => 이걸 반드시 DB를 조회해서 확인해야한다면, 테스트는 더 느리고 복잡해진다. => 따라서, 가능하다면 도메인 모델을 적극적으로 사용하는 것도 좋을듯 ?
    - 비정상 케이스 => 이 부분만큼은 절대 허용되면 안된다.
      - 이미 사용된 상품권은 다시 사용할 수 없다.


> **현재 스펙을 기준으로 이 코드에서 이것들은 정상적으로 동작해야한다**라는 것을 검증

// com.payco.giftcard.api.business.pin.service.GiftUserService#useGift

@Transactional
public GiftUseResponseDTO useGift(String pinNo, String idNo, String clientIp, String transactionNo) throws GiftcardApiCheckedException {

    // [유효성 검사]
    GiftUseInfo giftUseInfo = giftUserRepository.selectGiftUseInfoByPinNo(pinNo);
    giftUseValidator.validate(giftUseInfo, idNo, pinNo, clientIp, transactionNo);

    // [상품권 사용]
    giftUseManager.use(pinNo, idNo);

    // [마일리지(실제 페이코 포인트) 적립]
    MileageAccumulateResult accumulateResult = mileageAccumulator.accumulate(giftUseInfo, idNo);

    // 적립 실패 (예외 발생시킴)
    if (!accumulateResult.isSuccess()) {
        handleFailure(accumulateResult, giftUseInfo, pinNo, idNo);
    }

    // 적립 성공
    giftUseStore.saveGiftUseInfo(pinNo, giftUseInfo.getGiftPublicationNo(), idNo, accumulateResult.getMileageTradeNo());
    giftUseManager.informGiftUseInfo(giftUseInfo.getOrderTypeCode(), giftUseInfo.getOrderNo(), idNo, pinNo);

    return GiftUseResponseDTO.from(accumulateResult.getAccumulateInfo());
}


**정상 케이스**
- 포인트 적립이 돼야한다.
- 사용 처리가 돼야한다.
- 특정 상품권 타입인 경우, 관련 시스템에 등록 여부를 알려야한다.

**예외 케이스**
- 비정상적인 핀번호인 경우
- 비정상적인 회원인 경우
  - 비정상이라는걸 판단하려면 외부 시스템에 의존해야한다
- 마일리지 적립에 이슈가 있는 경우
  - 이미 처리된 경우, 우리쪽에만 업데이트
  - 알 수 없는 에러인 경우
  - 그 외


※ 주의사항
- 이렇게 테스트 더블 (Stub/Mock) 혹은 Mock 라이브러리를 통해 처리하는 경우가 항상 옳은 것은 아닙니다.
- 그래서 테스트 더블을 사용하는 경우 다음의 주의사항을 꼭 염두해 두어야만 합니다.

- 무분별한 테스트 더블을 활용한 단위 테스트
  - 간혹 Stub, Mock에 빠져 모든 코드를 Stub, Mock으로 해결하려는 분들이 있습니다.

- 특히 대표적인 사례가 다음과 같습니다.
  - Service에서 하는 것이라곤 Repository의 메소드들을 호출하는게 전부인데, Repository를 전부 Stub/Mock 처리한 경우
  - 단위 테스트에만 빠지면 안됩니다.

- 통합/E2E 테스트와 달리 테스트 더블을 통한 단위 테스트는 각 Layer, Componenet 간 연동이 되어서도 잘 되는 것을 보장하지는 못한다

- stubbing을 통해서 연동되는 모듈들의 버그 유무는 전혀 고려하지 않은 상태로 테스트를 하다보니, 실제 연동 과정에서 많은 문제들이 발생할 수 있습니다.

사이드 이펙트가 적은 부분에 한해서 테스트 더블을 사용하는 것이 좋습니다.

- **가능하다면 실제 객체를 사용하는 것이 가장 좋고, 그게 어려울때만 테스트 더블을 사용하는 것이 좋습니다.**

점점 깨지기 쉬운 테스트
테스트 더블 객체들은 깨지기 쉬운 테스트 케이스가 되기 쉽습니다.
이는 Mock/Stub 처리를 위해 그만큼 테스트가 구현부를 상세하게 의존하기 때문입니다.

가능하다면 테스트 더블이 필요 없는 작은 구조로 구현부의 설계를 개선하는 것이 좋습니다.
그 편이 테스트 더블을 사용 하려고 노력하는 것보다 훨씬 낫습니다.

- 현재 짜고 있는 테스트 코드가 단위 테스트의 정의를 정확히 부합하고 있는지에 대해서는 집착할 필요가 전혀 없습니다. 가장 중요한 것은 프로젝트의 특징에 따라 코드를 잘 테스트할 수 있고 유지보수할 수 있는 코드를 구현하는 것입니다.



# 포인트 적립 관련 검증
---

## Version 1

```java
@DisplayName("[정상] 포인트 적립이 돼야한다 1")
public void foo() {
    // Given (테스트 데이터 준비)
    String pinNo = "123456";
    String idNo = "user123";
    String clientIp = "127.0.0.1";
    String transactionNo = "txn-001";

    GiftUseInfo mockGiftUseInfo = new GiftUseInfo();
    MileageAccumulateResult mockAccumulateResult = new MileageAccumulateResult();
    mockAccumulateResult.setSuccess(true);

    // Mocking (유효한 상품권이 존재함)
    when(giftUserRepository.selectGiftUseInfoByPinNo(pinNo)).thenReturn(mockGiftUseInfo);
    doNothing().when(giftUseValidator).validate(mockGiftUseInfo, idNo, pinNo, clientIp, transactionNo);
    doNothing().when(giftUseManager).use(pinNo, idNo);
    when(mileageAccumulator.accumulate(mockGiftUseInfo, idNo)).thenReturn(mockAccumulateResult);

    // When (메서드 실행)
    giftUserService.useGift(pinNo, idNo, clientIp, transactionNo);

    // Then (검증)
    verify(mileageAccumulator, times(1)).accumulate(mockGiftUseInfo, idNo);
}
```
=> 내부 구현(mileageAccumulator.accumulate 호출하기 전에 giftUserRepository.selectGiftUseInfoByPinNo, giftUseValidator.validate, giftUseManager.use이 호출되는것)을 너무 상세히 알고 있기 때문에, 구현이 변경되면 영향을 받을 가능성이 높아진다.

```java
@DisplayName("[정상] 포인트 적립이 돼야한다 2")
void useGift_processesGiftUsageCorrectly() {
    // Given
    String pinNo = "123456";
    String idNo = "user123";
    String clientIp = "127.0.0.1";
    String transactionNo = "txn-001";

    GiftUseInfo giftUseInfo = new GiftUseInfo();
    MileageAccumulateResult accumulateResult = new MileageAccumulateResult();
    accumulateResult.setSuccess(true);

    when(giftUserRepository.selectGiftUseInfoByPinNo(pinNo)).thenReturn(giftUseInfo);
    when(mileageAccumulator.accumulate(giftUseInfo, idNo)).thenReturn(accumulateResult);

    // When
    giftUserService.useGift(pinNo, idNo, clientIp, transactionNo);

    // Then: 특정 호출들이 실행되었는지 검증
    InOrder inOrder = inOrder(giftUseValidator, giftUseManager, mileageAccumulator, giftUseStore);

    inOrder.verify(giftUseValidator).validate(giftUseInfo, idNo, pinNo, clientIp, transactionNo);
    inOrder.verify(giftUseManager).use(pinNo, idNo);
    inOrder.verify(mileageAccumulator).accumulate(giftUseInfo, idNo);
    inOrder.verify(giftUseStore).saveGiftUseInfo(pinNo, giftUseInfo.getGiftPublicationNo(), idNo, accumulateResult.getMileageTradeNo());
}
```
=> 이 또한 내부 구현을 상세히 알고 있다.

## Version2
> 통합 테스트

    // 핵심적인 로직만 Mocking하고, End-to-End 테스트 추가
    // 클래스에 @ExtendWith(SpringExtension.class)와 @SpringBootTest 추가해줘야됨
    @DisplayName("[정상] 포인트 적립이 돼야한다 3")
    void useGift_accumulatesMileage() {
      // Given
      String pinNo = "123456";
      String idNo = "user123";
      String clientIp = "127.0.0.1";
      String transactionNo = "txn-001";

      MileageAccumulateResult mockAccumulateResult = new MileageAccumulateResult();
      mockAccumulateResult.setSuccess(true);

      when(mileageAccumulator.accumulate(any(), eq(idNo))).thenReturn(mockAccumulateResult);

      // When
      GiftUseResponseDTO response = giftUserService.useGift(pinNo, idNo, clientIp, transactionNo);

      // Then
      assertNotNull(response);
      verify(mileageAccumulator, times(1)).accumulate(any(), eq(idNo));
}

=> 세부 구현을 알 필요가 없기 때문에, 코드 변경에 영향을 훨씬 덜 받게된다.
=> 하지만, pinNo, idNo이 실제로 유효한 값이어야한다. (DB에 세팅되어 있어야함)
=> 또한, 통합테스트이기 때문에 실제 DB연동 등에도 이상이 없어야하며 단위테스트보다 느리다.
=> 테스트 후 데이터 정리되는 부분 등도 신경써야한다.


## 참고
- https://jojoldu.tistory.com/320
- https://jojoldu.tistory.com/614
- https://aeliketodo.tistory.com/141
- https://github.com/woowacourse/jwp-refactoring/pull/12
