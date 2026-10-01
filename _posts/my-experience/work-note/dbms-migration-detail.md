---
title: Cubrid에서 MySQL로의 여정
date: 2025-10-18 23:00:00 +0900
categories: [경험하기, 작업 노트]
tags: [MySQL]
---



## 작업 절차

```
1. MYSQL 쿼리 검증
2. (서비스 점검을 걸고) cubrid에서 mysql로 데이터 마이그레이션
3. MySQL로 운영 (혹시모를 Cubrid로의 롤백 상황을 대비해서 Cubrid에도 데이터는 쌓음)
4. 운영 이슈 없으면 CUBRID FADEOUT
```

**1. MYSQL 쿼리 검증**
- `mybatis`를 사용중이었기 때문에, mysql용 쿼리 작성이 필요
- 따라서, MYSQL 전환되기 전에 해당 쿼리들이 에러는 없는지, 쿼리 에러가 없더라도 데이터가 cubrid와 동일한 값으로 변경되고 조회되는지를 어떻게 검증할지
  - 이 부분은 dao cubrid로 CRUD할 때, Spring AOP를 활용하여 intercept
  - mysql 쪽에도 동일하게 CRUD 하면서 쿼리 에러가 발생하거나, cubird 쪽과 select 결과가 다르면 개발자에게 알림 (비동기로 처리)
- 데이터 변경은 되었지만 쿼리로 SELECT 되지 않는 데이터들이 있을 수도 있기 때문에, 이런 부분들까지 커버하기 위해 별도의 데이터 검증 배치 구현


**1-1. 부하테스트**
- 피크 시간대의 TPS(20~30) 파악하여 JMeter 사용해서 1초에 약 30개의 요청을 5분간 (csv 파일 세팅해서)
- 이중화 구조 적용 안한 버전 vs 이중화 구조시 cubrid read vs mysql read
- CPU, 메모리, 응답시간 위주로 확인 (MethodInvoker 사용으로 인한 성능 저하있을지 우려)


**2. (서비스 점검을 걸고) cubrid에서 mysql로 데이터 마이그레이션**
- 서비스를 멈추지 않고 mysql로의 전환이 가능할지에 대한 고민을 했었는데, 결과적으로는 서비스 점검을 걸고 진행을 하였습니다.
- CDC 방식을 사용하면, 아예 안멈추긴 어려워도 중단시간을 최소화하면서 전환이 가능할 수 있을 것으로 생각했음.
  - 하지만, cubrid를 지원하는 마땅한 cdc 플랫폼이 없음
- 따라서, 중단 시간을 최소화하는 방안을 생각. 즉, 마이그레이션할 데이터 수를 어떻게 하면 최소화할 수 있을지
  - 이력 테이블 미리 옮기기
  - 새벽에 배치 돌때만 변경되는 테이블들 mysql로 먼저 넘어갈 수 있는 테이블들은 넘어가기


**3. MySQL로 운영 (혹시모를 Cubrid로의 롤백 상황을 대비해서 Cubrid에도 데이터는 쌓음)**
- 데이터 검증때 이미 양쪽 쌓기를 하고있었기 때문에 AOP 그대로 활용
- 추가적으로 고려해야했던건, `분산 트랜잭션 처리` // 비동기처리 못함
  - 2PC의 경우, coordinator라고 불리는 하나의 컴포넌트가 양쪽 DB로부터 commit이 가능한지에 대한 응답을 받고 (prepare 단계), commit 또는 rollback을 수행하는 방식.
    - 이 때 coordinator가 죽게되면 영향도가 매우 크고, 2PC의 경우 XA 프로토콜을 지원하는 XADataSource를 사용해야하는데, Cubrid의 경우 XADataSource 사용시, 기존에 사용중이던 브로커간 롤체인지를 위한 `althost` 옵션을 사용할 수 없음
  - ChainedTransactionManager의 경우, 각각의 DB에 매핑된 TransactionManager에게 차례로 commit 요청함
    - 첫번째 DB에 commit 성공 후, 두번째 DB에 커밋시 DB 다운 등으로 인해 커밋에 실패하면 첫번째 DB에만 데이터가 있을수 있게됨 (첫번째 DB에 커밋 실패하면 두번째는 rollback함)
    - 이로인해 2.5버전(21년)부터는 deprecated됨
- 즉, 2PC는 강한 데이터 일관성을 보장하지만 단점도 치명적, ChainedTxManager는 구현이 단순하지만 2PC 만큼 강한 데이터 일관성을 보장하지는 못함.
- 2PC를 사용해서 coordinator가 다운되거나, ChainedTxManager를 사용해서 데이터 정합성이 깨지는 케이스 모두 발생할 가능성은 굉장히 낮을 것으로 생각했지만, 두 상황을 비교했을 때 coordinato 다운이 더 치명적일 것으로 생각했고, ChainedTxManager로 인해 정합성이 깨지더라도 운영에는 지장이 없음. (깨지면 수기 또는 배치로 맞추거나, 여차하면 mysql로 완전 전환 생각함)
  - (만약 정합성 깨지게된다면, 정합성 에러 발생한 시점과 관련 테이블을 기반으로 배치돌려서 맞추려고 했으나, 파트장님께서 해당 가능성은 매우 낮다고 생각하고 혹시나 발생하더라도 mysql에 대한 검증이 완료된 상황이므로 그냥 mysql로 넘어가자고 하심)
- `@Transactional` 어노테이션이 선언된 경우, ChainedTxManager가 알아서 적용이되지만, 그렇지 않은 경우에는 스프링에서 제공하는 transactionTemplate을 사용하여 Aspect 내부에 이중쓰기 하는 부분에 트랜잭션 매니저 적용

**4. 운영 이슈 없으면 CUBRID FADEOUT**


## 질문

### 구현은 어떤식으로 한건지 ?
- 예를 들어, Cubrid쪽에 질의하는 DAO 클래스가 TempDao.java 이고 해당 Dao에 매핑되는 쿼리 xml 파일이 있다고 가정
- mysql용으로는 TempDao 앞에 Mysql 접두사를 붙임, mysql용 쿼리도 생성.
- Cubrid DAO, Mysql DAO 모두 인터페이스이고 mybatis 매퍼 스캔 방식을 통해 구현체(`org.apache.ibatis.binding.MapperProxy`)가 스프링 빈으로 만들어짐 (빈 이름은 클래스명)
- cubrid에 질의하는 tempDao의 메서드, 이를테면 tempDao.select(); 같은게 호출되면 AOP로 Intercept
- intercept 하면, JoinPoint에 담겨있는 메서드 정보, 해당 메서드를 호출한 클래스 정보 등을 알 수 있음
- 이것을 통해, 호출한 클래스명 앞에 mysql을 붙이면, `ApplicationContext`를 통해 앞서 설명했던 mysql dao 빈을 가져올 수 있음
- 해당 빈을 가져와서, 동일한 파라미터로 동일한 메서드 실행
- 이런식으로 mysql에 select 하는 부분은 비동기로 처리 (cud는 auto_increment 때문에 못함)
- 실행 도중 쿼리 에러가 발생하거나, 쿼리 수행 결과가 다르면 사내 시스템을 통해 개발자에게 알림
- 쿼리 수행결과 비교 (비동기)
  - 조회한 데이터 검증은, 리턴 타입(Map, List, 특정 인터페이스 구현한 객체)에 따라, 어떤 단계에서의 마이그레이션인지에 따라 다르게 검증
  - 완전 마이그레이션 전에는 양쪽 db간에 데이터 다를 수 있으므로, mysql에 데이터 있는 경우만 비교, list 사이즈 비교 안함
  - 완전 마이그레이션 후에는 list 사이즈, 무조건 같은지 비교 등
- 검증 배치의 경우, 테이블별로 어떤 컬럼들을 비교할지, 어떤 필터링 조건을 사용할지, 어떤 값으로 정렬할지 등에 대한 정보를 별도의 테이블에 저장해놓고, 주기적으로 배치 돌면서 row별로 비교 (order by 키값)

### 다른 방식 생각해본거는 ?
- 현재 방식처럼 동기식 말고 TransactionEventListener로 이벤트 발행 ?
  - 기존에 메시지 브로커에 대한 운영 노하우 없이 도입하기에는 데이터 유실, 이벤트 발행 순서 보장, 단일 장애점 등 다양한 고려사항 생각했을 때 비용이 너무 클 것 같다고 판단.

### 2PC(2-phase commit)를 사용하지 않기로 결정하신 이유 중 하나로 "coordinator가 단일 장애점이 될 수 있다"고 하셨는데, 이에 대해 좀 더 상세하게 설명해 주실 수 있을까요?
- commit 가능 여부 질의 -> commit
- 직접 사용해본 것은 아니지만, 참여 노드들에게 commit 응답을 받지 못하거나 그럴때 계속 대기한다거나
- coordintor에 모든 요청이 갈것이므로 부하에 어느정도로 견딜 수 있는지도 확실치 않음
- Atomikos가 참여 노드와 연결을 관리하는 데 사용하는 리소스 풀 크기가 제한되어 있고, 이를 초과하면 트랜잭션이 실패할 수 있음.


### ChainedTxManager ?
- Spring Data의 ChainedTrasactionManager (spring-data-commons 2.5버전 -> 21년 4월 부터 deprecated, 현재 최신 3.4.0)를 활용하였습니다.
- spring-data-commons repo의 이슈를 찾아봤을때 deprecated된 이유는 완전한 정합성이 보장되지 않는데, 사람들의 착각을 불러일으킬 수 있다는게 골자였던 것으로 알고있습니다.
- 기존에 잘 사용하고 있던 사람들이 이에 대해 인지하고 사용하고 있다고했고, 메인테이너는 그렇다면 알아서 잘 사용하라는 식의 답변을 남긴걸보고 저 또한 이 부분을 인지하고 사용하면 될 것으로 생각했습니다.
- 커밋 순서 설정 가능, mysql -> cubrid 순서로 커밋
- 2PC 학습 비용, 담당하는 coordinator가 단일 장애점이 될 수 있는것을 생각했을때 그 정도의 비용을 들일정도로 강한 정합성을 요구하는 상황은 아니라고 생각되어서 선택하지 않음 (+ 분산 트랜잭션으로 묶는 기간이 길지 않을 것으로 생각)

-ChainedTxManager 생성시 n개의 TxManager 세팅 (생성자 파라미터)
- commit, rollback시 파라미터에 세팅된 역순으로 TxManager commit, rollback 호출
- 첫번째 TxManger에서 실패하면 모두 롤백되지만
- 이후의 TxManager에서 실패하면 그 앞에 커밋된거는 롤백 안됨
- 이렇게 커밋 제대로 안되었으면, HeuristicCompletionExeception 발생시키고 그 안에 전체 롤백되었는지, 부분 롤백 되었는지에 대한 상태 정보가 들어있음
- 괜찮다고 판단한 이유는, 분트로 묶는 시점은 MySQL에 대한 검증이 거의 완료돼서 MySQL을 기준으로 운영하는 상황. 정말 혹시라도 Cubrid로 다시 롤백해야할 상황을 대비해서 데이터 정합성을 맞춰놓는다.
- 다시 Cubrid 롤백해야할 가능성과 그리고 commit이 실패하는 경우는 가능성이 매우 낮은 상황이라고 판단
- 혹시라도 정합성 깨지더라도 MySQL에는 데이터가 있을 것이므로, 운영에는 지장 없을 것이고, 반드시 맞춰야한다면 어떻게든 맞추거나 그냥 cubrid fadeout 했을듯

### Spring AOP 동작 방식 ?
- 스프링 4버전부터 cglib proxy가 default
- 5.3 버전부터 ByteBuddy가 새롭게 도입되어 더 나은 성능과 유지 보수를 지원. (인터페이스 유무 상관없음, 상속 안해도됨)
  - ByteBuddy는 바이트코드 수준에서 클래스를 동적으로 생성하거나 수정하여 더 높은 유연성을 제공합니다.
- cglib는 enhancer로 target 클래스 상속받는 프록시 객체 만듦 (원본 클래스를 확장(extend)하여 서브 클래스를 생성)
  - CGLIB는 클래스 상속을 통해 프록시를 생성하며, 원본 클래스를 기반으로 바이트코드를 조작합니다.
- methodInterceptor 사용해서 실행 메서드 intercept하고 원하는 부가 기능 추가
  - jdk dynamic 프록시는 인터페이스 기반의 프록시 객체 생성.
  - invocationHandler 사용해서 인터페이스의 메서드 intercept

### 쿼리 어떤 식으로 바꿨는지 ?
- NVL => INFULL
- TO_DATTIME => STR_TO_DATE
- YYYYMMDD => %Y%m%d
- DECODE => IF

### 양쪽 SEQ가 틀어진다는게 어떤 상황 ?
- 가맹점 관리하는 테이블의 PK가 auto_increment로 증가하는 시퀀스인데요 이 값을 외부 시스템에 전달하는 등 유의미하게 사용하고 있습니다.
- 이런 상황에서 예를 들어 동시에 가맹점 A, B에 대한 등록 요청 두 개가 들어오면, Aspect에서 양쪽 DB에 질의를 요청할때 A 가맹점이 양쪽 DB에 B보다 반드시 먼저 들어간다는 보장이 없기 때문에 seq가 불일치하는 상황이 나오게됩니다.
- 따라서, auto_incremen를 사용하지 않고, 별도의 seq 테이블을 만들고 가맹점 저장 전에 해당 테이블에서 auto_increment한 후, MyBatis의 useGeneratedKeys라는 기능을 활용하면 auto_increment로 증가한 값을 바로 가져올 수 있어서, 해당 값을 가맹점 객체에 세팅 후 양쪽 db 모두에 저장되도록
  - `PreparedStatement preparedStatement = connection.prepareStatement(insertSql, Statement.RETURN_GENERATED_KEYS)`
- 데이터 완전 마이그레이션 전에는 Cubrid seq 테이블 기준으로 들어가도록 하였고, 완전 마이그레이션 이후에는 MySQL seq 테이블 기준으로 들어가도록 하였습니다.

### 다시 설계한다면 PK 어떻게 할 것 같은지 ?
- seq를 유의미하게 사용하면 분산 시스템에서 고유성을 보장하지 못할 수 있음.
- PK가 클수록 다른 인덱스 구조도 커지면서 페이지가 많이 쪼개져 디스크 I/O 횟수가 증가하는 문제가 있다.
- PK 값은 항상 유효해야 하며, 비즈니스 로직과 독립적이어야 함.
  - 비즈니스 키는 변경될 가능성이 있으므로 신중히 고려해야 함, 비즈니스 요구사항이 아니라도 법이 바뀔수도 있는거고,, ex : 주민등록번호
- PK가 변경되는 경우에 레코드가 저장된 물리적인 위치도 변경되어야 함
- PK 값에 따라 레코드가 있어야 하는 페이지가 달라질 수 있다.
  - 변경시 인덱스 구조 변경에도 매우 많은 비용 (보조 인덱스들까지 모두 영향 받기 때문에)
- 비즈니스 키가 변경되지 않고, 고유성을 영구히 유지할 수 있을 때. (국가 코드(ISO 코드))
- auto_increment seq는 순차적으로 증가하는 값이 그대로 노출됨.
- 외부 시스템과 연동하는 값으로 PK를 사용할 경우, PK 변경(예: 데이터 재구성)시 외부 시스템의 연동에도 영향을 미침.
- 시스템 요구사항 변경이나 데이터 이관 작업에서 PK를 변경해야 할 경우, 외부 시스템도 함께 수정해야 하므로 유지보수 비용이 증가

### 베타 부하테스트는 어떤식으로 ?
- 피크 시간대의 TPS(20~30) 파악하여 JMeter 사용해서 1초에 약 30개의 요청을 5분간 (csv 파일 세팅해서)
- 이중화 구조 적용 안한 버전 vs 이중화 구조시 cubrid read vs mysql read
- CPU, 메모리, 응답시간 위주로 확인 (MethodInvoker 사용으로 인한 성능 저하 우려)

### Aspect 적용된 클래스는 어떤 객체로 생성되는지
- AopProxy로 감싸지고 target은 mapper scan 방식으로 생성된 MapperProxy 객체


### 큐브리드 버전간의 저장 구조가 다르다 ?
