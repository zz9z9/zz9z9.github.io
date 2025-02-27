---
title: MySQL - 데이터 모델링
date: 2021-08-25 23:00:00 +0900
categories: [지식 더하기, 이론]
tags: [MySQL]
---

# 들어가기 전
---
애플리케이션을 설계할 때 'DB 테이블은 어떻게 구성해야하지?' 에 대한 막막함이 있다면 데이터 모델링이 문제 해결의 출발점이라고 생각한다. <br>

공부를 하기에 앞서 나의 언어로 정리해본다면 내가 생각하기에 모델링이라는 것은 먼저 문자 그대로 '모델화' 시킨다는 것인데, 모델이란 '어떤 대상을 필요한 특징만 추려서 나타낸 것' 이라는 생각이 든다. <br>

예를 들어, '아파트 단지 모형' 이라고 한다면 아파트, 부대시설 등을 나타낼 수 있을 것이며 이 때, 아파트 창문의 개수, 주차장의 주차 가능 대수, 내부 엘리베이터 등은 불필요한 정보일 것이다.

내가 생각하는 모델링의 장점으로는 현실의 복잡성을 추상화를 통해 단순화 할 수 있다는 것이다. 단순화하는게 어떤 장점이 있을지 데이터베이스 관점에서 생각해보면 최소한의 자원을 활용하여 대상을 저장할 수 있다는 점이 있을 것 같다.

# 데이터 모델링이란 ?
---
데이터 모델링(data modeling)이란 주어진 개념으로부터 논리적인 데이터 모델을 구성하는 작업을 말하며, 일반적으로 이를 물리적인 데이터베이스 모델로 환원하여 고객의 요구에 따라 특정 정보 시스템의 데이터베이스에 반영하는 작업을 포함한다. 후자의 의미로 흔히 '데이터베이스 모델링'으로 불리기도 한다.

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/130707886-b55f6408-a4a0-45d6-b4d1-b15a0dc6e10f.png" width="90%"/>
  <figcaption align="center">출처 : <a href="https://www.trifacta.com/blog/what-is-data-modeling/" target="_blank"> https://www.trifacta.com/blog/what-is-data-modeling/</a> </figcaption>
</figure>

## 데이터 모델링의 필요성
> [이 글](https://www.linkedin.com/pulse/why-data-modelling-important-munish-goswami) 에 나와있는 내용 중 일부를 정리해보았다. '아 이래서 모델링을 해야하는구나' 정도의 느낌만 가져가면 될 것 같다.

1. 애플리케이션의 더 나은 품질
- 평균적으로 소프트웨어 개발 작업의 약 70%가 실패하며, 주요 실패 원인은 섣부르게 코딩을 시작하는 것 때문이다.
- 데이터 모델은 문제를 정의하는 데 도움이 되므로, 실제 코드를 작성하기 전에 이를 통해 여러 가지 문제 접근 방법을 고려해볼 수 있다.

2. 비용 절감(오류 조기 포착)
- 데이터 모델링은 오류와 감시를 수정하기 쉬운 시기에 조기에 포착한다.
- 이는 애플리케이션이 만들어진 후 오류를 수정하는 것 보다 비용이 적게 든다.

3. 소통의 도구
- 데이터 모델을 통해 개발자 뿐 아니라 기획자 등 다양한 이해관계자들 간에 원만한 소통이 가능해진다.
- 이를 통해, 애플리케이션에 포함된 것과 생략된 것이 무엇인지 대해 서로 간에 동의하는 데 도움을 준다.

4. 더 나은 성능
- 최적의 성능을 얻으려면 데이터 모델의 개념이 명확하고 일관성이 있어야 한다. 또한, 모델을 데이터베이스 설계로 변환하는 데 적절한 규칙을 사용해야 한다.
- 모델링은 빠른 성능을 위해 데이터베이스를 조정할 수 있도록 데이터베이스를 이해하는 수단을 제공한다.

5. 리스크 관리
- 데이터 모델의 크기와 테이블 간의 연결 강도 등을 바탕으로, 소프트웨어의 복잡성을 추정하고 개발 작업 및 프로젝트 위험 수준에 대한 통찰력을 얻을 수 있다.

# 데이터 모델링을 위한 용어
---
> 모델링을 학습하기에 앞서 필요한 용어에 대해 공부해보자

## Entity(엔터티)
- 일반적으로 '테이블'이라고 칭하는 개체이다.
- 하지만 항상 테이블과 1:1로 맵핑되는 것은 아니며, 2개 이상의 엔터티가 물리 모델링 단계에서 통합되기도 하고, 하나의 엔터티가 여러 개의 물리적 테이블로 구현되기도 한다.
- 엔터티를 도출할 때 가장 중요한 것은, 해당 용어가 의미하는 범위가 어디까지인지를 명확히 하고 그에 걸맞는 이름을 부여하는 것이다.
  - 이를 기반으로 속성, 식별자, 엔터티 간의 관계가 명확해진다.

### 엔터티의 작명
- 만약 엔터티 이름에 수식어가 있다면 검토해보고 필요하다면 통합하는 것이 좋다.
  - 예를 들어, '상품'을 '직원용상품', '고객용상품' 등으로 범위를 제한해서 여러 개의 엔터티를 정의하는 것은 좋지 않다.
- '리스트, '목록'과 같은 복수형 표현을 지양한다.
  - 이미 엔터티 자체가 레코드의 목록을 저장하는 개체이기 때문이다.
- '사원정보'와 같은 모호한 단어보다는 '사원'이라는 좀 더 명확하고 간결한 범위를 한정하는 것이 좋다.

## Attribute(속성)
- 더는 분리될 수 없는 최소의 데이터 보관 단위.(테이블의 컬럼과 맵핑된다.)
  - 즉, 하나의 엔터티 내에서 다른 어트리뷰트와 비교했을 때, 독자적인 성질을 가지는 것이어야 한다.
- 가공하지 않은 그대로의 값이라는 의미도 내포하고 있다.
  - 가공하지 않은 것의 반대 의미로 '추출 칼럼'이 있다.
  - 추출 칼럼은 하나의 엔터티나 다른 엔터티의 어트리뷰트로부터 계산된 값이다.
     - 예를 들어 게시물의 코멘트 개수, 게시판에 등록된 게시물의 개수 등이 있다.

### Attribute의 원자성
> 어트리뷰트는 반드시 독자적인 성질을 가지는 하나의 값만을 저장해야 한다.

- 예를 들어 회원의 취미 정보를 하나의 어트리뷰트에 구분자를 사용해서 한꺼번에 저장할 때도 있다.
- 하지만 이러한 방법은 어트리뷰트의 기본 조건에 위배되는 모델링 방법이며, 추후 물리 모델링 단계나 인덱스 설계에 나쁜 영향을 미칠 수 있다.
- 물리 모델 단계에서는 성능을 위해 어느정도 위배해서 설계할 수도 있지만, 논리 모델에서는 원자성을 위배하는 어트리뷰트는 고려하지 않는게 좋다.

## 식별자(Primary Key)
- 하나의 엔티티에서 개별 레코드를 식별할 수 있는 어트리뷰트의 조합
- 일반적으로 식별자로 어트리뷰트 하나를 가질 때가 많으며, 두 개 이상의 어트리뷰트가 조합되는 경우도 있다.

### 인조 식별자(Surrogate Key)
- 예를 들어 고객, 상품 엔터티를 기반으로 주문 엔터티를 만든다고 가정해보자.
  - 주문 엔터티의 식별자는 (고객ID, 상품코드, 주문일시)로 구성할 수 있을 것이다.
  - 하지만 주문 엔터티는 주문 이력, 상태 변화 등과 같은 수많은 자식 엔터티를 만들어낼 가능성이 높다.
  - 주문 엔터티의 식별자가 3개의 어트리뷰트로 구성되기 때문에 자식 엔터티는 그 이상의 어트리뷰트를 사용해야 할 수도 있다.
  - 따라서 '주문번호'와 같은 인위적인 숫자 값을 식별자로 대체해서 사용할 때가 많다.
- 인조 식별자를 도입한다면 본질 식별자(위의 경우 고객ID, 상품코드, 주문일시)는 대체키(유니크 인덱스)로 생성한다.

### 슈퍼 키(Super Key)
- 한 릴레이션 내에 있는 속성들의 집합으로 구성된 키. 릴레이션을 구성하는 모든 튜플 중 슈퍼키로 구성된 속성의 집합과 동일한 값은 나타내지 않는다.
- 릴레이션을 구성하는 모든 튜플에 대해 유일성(Unique)은 만족하지만, 최소성(Minimality)은 만족하지 못한다.

### 후보 키(Candidate Key)
- 엔터티를 구성하는 어트리뷰트들 중에서 레코드를 유일하게 식별하기 위해 사용되는 어트리뷰트들의 부분 집합.
- 유일성과 최소성을 모두 만족.
  - 유일성 : 하나의 키 값으로 하나의 튜플만을 유일하게 식별할 수 있어야한다.
  - 최소성 : 키를 구성하는 속성 하나를 제거하면 유일하게 식별할 수 없도록 꼭 필요한 최소의 속성으로 구성되어야 한다.
- 2개 이상의 어트리뷰트를 조합하여 만든 후보 키를 복합 키(Composite Key)라고 한다.

### 대체 키(Alternate Key)
- 후보 키 중에서 기본 키를 제외한 나머지를 의미한다.

### 외래 키(Foreign Key)
- 다른 엔터티의 기본 키를 참조하는 속성 또는 속성들의 집합을 의미한다.
- 엔터티 간의 관계를 표현할 때 사용한다. 즉, 외래키는 두 엔터티를 서로 연결하는 데 사용되는 키이다.
- 외래키가 포함된 테이블을 자식 테이블이라고 하고 외래키 값을 제공하는 테이블을 부모 테이블이라고 한다.
  - 부모 엔터티의 기본 키와 동일한 키 속성을 가진다.
- 부모 테이블의 기본키, 고유키가 여러개의 컬럼으로 이루어져 있다면 부모가 가진 기본키, 고유키 컬럼을 원하는 개수만큼 묶어서 외래키로 지정할 수 있다.

#### 참고. Primary Key vs Unique Key

| |Primary Key|Unique Key|
|-------|-------|-------|
|용도|테이블의 각 행에 대한 고유 식별자 역할|기본 키가 아닌 것 중 행을 유일하게 식별하는 역할|
|NULL 허용 여부|X|O|
|개수|오직 한 개|한 개 이상|
|인덱스|clustered index|non-clustered index|

<br>

## Relation(관계)
- 엔터티 간의 상호작용을 표현한 것
- 관계는 다른 엔터티의 어트리뷰트로 참여하기도 하지만 관계 자체가 별도의 엔터티로 구현돼야 할 때도 많다.

### 식별, 비식별 관계
- 식별 관계
  - 부모의 식별자가 자식 엔터티의 레코드를 식별하는데 꼭 필요한 관계
  - 게시판과 게시물의 관계를 보면, 게시물의 경우 부모 엔터티인 게시판의 식별자 게시판ID가 게시물의 식별자로 반드시 포함되어야 한다.
- 비식별 관계
  - 부모 엔터티의 식별자가 없어도 자식 엔터티의 레코드가 생성 가능한 관계
  - 회원과 게시물의 관계를 보면, 게시물의 경우 게시물ID만 있으면 레코드 생성이 가능하고 부모 엔터티의 식별자인 회원ID는 외래키로 구성할 수 있다.

### Cardinality(기수성)
> 부모 엔터티의 레코드 하나에 대해 자식 엔터티의 레코드가 얼마나 만들어질 수 있는지(발생 빈도)를 의미한다.

- 주로 0 또는 1, 1건 이상(N 또는 M)의 수준으로 구분해서 표시한다.

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/130806638-2a801437-8afe-4a4a-a3db-3f8251ecc05f.png" width="50%"/>
  <figcaption align="center">출처 : <a href="https://www.lucidchart.com/pages/ER-diagram-symbols-and-meaning" target="_blank"> https://www.lucidchart.com/pages/ER-diagram-symbols-and-meaning</a> </figcaption>
</figure>

### 다대다(M:M) 관계
- 어트리뷰트는 하나 이상의 값을 가지지 못하므로 M:M 관계를 1:M과 같이 어트리뷰트로 표현할 수는 없다.
- 논리 모델에서는 M:M 관계를 표기하기도 하지만, 물리 모델에서는 M:M 관계를 위한 표기법이 존재하지 않는다.

<img src="https://user-images.githubusercontent.com/64415489/130808029-b1f791c9-872e-4cdf-b548-d4902763fef1.png" width="50%"/>

- M:M 관계는 물리 모델로 넘어 오면서 다음과 같이 두 개의 1:M 관계로 풀어줘야한다.
  - 이를 'M:M 관계 해소'라고 한다.
- 꼭 물리 모델이 아니고 논리 모델에서 선행될 수도 있다.
- '수강'은 어떠한 엔터티가 아니라 학생과 과목 간의 '관계'를 나타내는 것이다.
  - 하지만 RDB의 구조적 한계로 이를 수강이라는 엔터티로 변환한 것이다.
  - 이처럼 관계를 저장하는 엔터티를 관계 엔터티(테이블)라고도 한다.

<img src="https://user-images.githubusercontent.com/64415489/130810940-6795887c-d4ef-4e22-9f74-8435d59f8f34.png" width="80%"/>

# 데이터 모델링 방법
> 일반적으로 업무 요건 정의 → 개념 모델링 → 논리 모델링 → 물리 모델링 순서로 진행된다.

## 개념 모델링
- 정의된 업무 요건을 기반으로 다음을 도출한다.
  - Entity
  - Attribute
  - 식별자(Identifier), 지정 후보키(candidate key), 기본키(primary key), 대체키(alternate key), 중복키(composite key)
  - 식별자가 될만한 어트리뷰트가 없다면 인조키 생성
  - Entity간의 관계 정의(PK와 FK 연결, Cardinality & Optionality)
    - 각 엔터티 간의 관계를 최대한 간결하게 표현해야 한다. ERD(E-R Diagram)의 생명은 가독성이다.

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/130814532-d375bb2d-b87d-4b00-8854-08fec58d2e50.png" width="80%"/>
  <figcaption align="center">출처 : <a href="https://bitnine.tistory.com/446" target="_blank"> https://bitnine.tistory.com/446</a> </figcaption>
</figure>


## 논리 모델링
- 개념적 모델링 된 것을 바탕으로 관계형 데이터베이스 패러다임에 어울리게 데이터를 정리하는 것
- ERD뿐만 아니라 시스템 구축을 위한 사항을 모두 정의한다.
- 또한, 정규화를 통해 논리 데이터 모델을 상세화하여 일관성을 확보하고 중복을 제거한다.

|개념 모델|논리 모델|
|----|----|
|Entity|Table|
|Attribute|Column|
|Relation|PK, FK|

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/130814760-deaa6c08-e74c-4f76-8ce7-7c8cb70b1041.png" width="90%"/>
  <figcaption align="center">출처 : <a href="https://bitnine.tistory.com/446" target="_blank"> https://bitnine.tistory.com/446</a> </figcaption>
</figure>

## 물리 모델링
- 논리적 모델링에서 도출된 이상적인 표를 실제 RDBMS에 맞게 변환하는 작업을 수행한다.
  - M:M 관계 같이 RDB에서 구현할 수 없는 구조를 해소하는 작업
  - 프라이머리 키의 컬럼 순서 선정
  - 컬럼의 이름 부여
  - 컬럼의 데이터 타입
- 이 단계에서 중요한 것은 '성능'이다.
  - 슬로우 쿼리 찾기, 인덱스, 반정규화 등

### 프라이머리 키 순서
- 물리 모델에서는 프라이머리 키를 구성하는 컬럼의 순서가 매우 중요하다.
- 프라이머리 키도 하나의 인덱스로써 사용되므로 반드시 SELECT의 조건 절에 자주 사용되는 컬럼 위주로 순서를 배치해야 한다.

### 데이터 타입 선정
- 문자, 숫자, 날짜, 이진 데이터 등
- 여러 형태를 가질 수 있는 데이터의 타입은 어떻게 결정해야 할까? 대표적인 예로 IP 주소를 생각해볼 수 있다.
   - IP 주소 정보는 컴퓨터 내부적으로는 숫자(부호 없는 4바이트 정수)로 처리하지만 일반적으로는 4개의 숫자 영역으로 구분된 문자열로 통용되고 있다.
   ```
   255.255.255.255 ⟷ 0xffffffff ⟷ 11111111 11111111 11111111 11111111
   ```
   - 따라서, IP 주소를 저장하기 위한 컬럼의 데이터 타입을 문자 타입으로 할지 숫자 타입으로 할지 고민하게 된다.
     - 편의성과 성능, 레코드 건수 등을 따져서 적절한 방법을 선택해야 한다.
     - 또한, 업무적인 용도를 분석하여 장단점을 조율한 후에 사용해야 한다.
- 만약 4바이트 정수로 IP 주소를 저장한다고 했을 때 다음과 같은 트레이드 오프를 고려해 볼 수 있다.
  - 장점
    - 컬럼의 길이가 15 글자에서 4바이트로 줄어듦
    - 컬럼의 길이 축소로 성능 향상이 기대됨
    - IP 주소를 A,B,C 등과 같은 대역별로 검색 가능
  - 단점
    - 값을 저장하거나 조회할 때 `INET_NTOA()` 또는 `INET_ATON()` 함수의 도움이 필요
    - 단순한 문자열 패턴 검색(`LIKE`)을 사용할 수 없음

#### 문자집합(캐릭터 셋)
> 문자집합에 따라 저장 공간의 길이가 2~3배씩 늘어날 수도 있고, 정렬이나 검색 규칙도 바뀔 수 있다.

- 하나의 DB에서 문자집합을 혼용하지 않는 것이 좋다는 의견과 명확한 기준만 있다면 2개 정도는 혼용해도 무방하다는 의견도 있다.
- 제대로 문자집합 관리가 되지 않는다면 쿼리의 성능만 떨어뜨리게 될 수도 있다.
- MySQL에서는 정렬이나 그룹핑과 같은 임시 테이블 또는 버퍼 작업을 위해 별도의 메모리 할당이 필요하다.
  - 이때 MySQL 서버는 데이터 타입에 명시된 길이를 기준으로 메모리 공간을 할당하고 사용한다.
  - 만약 해당 메모리 공간이 일정 크기 이상을 초과하면 메모리가 아닌 디스크에서 처리하게 된다.
  - 즉, 컬럼이 과도하게 크게 설정되면 메모리로 처리할 수 있는 작업이 디스크에서 처리될 가능성이 높아진다.

#### NULL과 NOT NULL
> NULL과 NOT NULL의 선택은 옵티마이저가 얼마나 쿼리를 더 최적화할 수 있게 환경을 만들어줄 것이냐의 관점에서 고려해야 한다.

- 예를 들어, NULL이 저장될 수 있는 컬럼에 대해 `IN` 형태의 조건을 사용하면 MySQL은 상상하지 못했던 이상한 비교 작업을 내부적으로 하게 된다.

# 정규화(Normalization)
> 정제되지 않은 데이터를 관계형 데이터베이스에 어울리는 데이터로 만드는 작업. 즉, 데이터의 중복을 최소화하여 효율적인 모델을 만든다.
> 논리 모델링에서의 정규화는 데이터 저장 비용을 최소화하고, 물리 모델링에서의 반정규화는 데이터를 읽어 오는 비용을 최소화한다.
> 일반적으로는 3NF(제 3정규화)까지 사용한다.

## 제 1정규화(No Repeating Group)
> 모든 속성은 반드시 하나의 값을 가져야 한다.

<img src="https://user-images.githubusercontent.com/64415489/130823964-ac5dadac-e8fe-4e52-8a97-7463894c7630.png" width="80%"/>

## 제 2정규화(Whole Key Dependent)
> 데이터의 중복 방지를 위해 부분적으로 종속되는 컬럼들을 모으고 전체적으로 종속되는 컬럼은 나눈다.

<img src="https://user-images.githubusercontent.com/64415489/130824539-bb2f5f00-1694-42fa-bd9c-9e4ccde78a4b.png" width="90%"/>

## 제 3정규화(Non-Key Independent)
> 식별자 이외의 속성간에 종속 관계가 존재하면 안된다.

![image](https://user-images.githubusercontent.com/64415489/130825542-3fa76565-9360-49dc-b582-5f515b19d3f4.png)

# 반정규화(Denormalization)
> 모델을 정규화할수록 SELECT 쿼리에서 필요한 테이블의 수 뿐만 아니라 GROUP BY나 쿼리 자체의 개수도 증가한다.
> 따라서, 필요한 경우 반정규화를 통해 데이터를 읽어 오는 비용을 최소화하는 것을 고려해봐야 한다.
> 반정규화는 정규화처럼 엄격하게 정해진 규칙들이 있는 것은 아니며,
> 반정규화 시 얻는 것(성능적 이점)과 잃는 것(데이터 중복 등)이 분명하므로 trade-off를 잘 따져야한다.

## 1. JOIN 줄이기
- 이 과정을 거치면 결국 정규화 되기 전 상태(데이터 중복)가 되는 것이다.
  - 즉, 성능적으로 개선할 수 있는 방법이 이것밖에 없을 때 사용하는 최후의 수단

![image](https://user-images.githubusercontent.com/64415489/130826886-77666168-d423-4694-bf7d-85a8e0c39e5f.png)

## 2. 계산 작업 줄이기
- 아래 예의 경우 GROUP BY를 사용하지 않아도 저자가 몇 개의 topic을 작성했는지 알 수 있다.

<img src="https://user-images.githubusercontent.com/64415489/130827400-91f57d49-cb21-4ae3-b35b-3584271ce459.png" width="80%"/>

## 3. 컬럼을 기준으로 테이블 분리하기
- 아래 예의 경우 description의 크기가 매우 크고 descripton을 따로 조회하는 경우도 많다면 테이블을 분리하는 것을 고려해 볼 수 있다.

<img src="https://user-images.githubusercontent.com/64415489/130827987-3d687f1a-34dd-4325-9171-ab79bb386dc1.png" width="80%"/>

## 4. 행을 기준으로 테이블 분리하기
- 각각의 행을 다른 DB 서버에 분산하여 저장할 수 있다.
- 전체적인 데이터의 관리가 매우 어려울 수 있다.

<img src="https://user-images.githubusercontent.com/64415489/130828484-8d33bab9-8c66-413e-9af2-f26921316094.png" width="90%"/>

# 참고 자료
---
- [https://www.linkedin.com/pulse/why-data-modelling-important-munish-goswami](https://www.linkedin.com/pulse/why-data-modelling-important-munish-goswami)
- [생활코딩 - 관계형 데이터 모델링](https://opentutorials.org/course/3883)
- [https://bitnine.tistory.com/446](https://bitnine.tistory.com/446)
- [https://moonibot.tistory.com/61](https://moonibot.tistory.com/61)
