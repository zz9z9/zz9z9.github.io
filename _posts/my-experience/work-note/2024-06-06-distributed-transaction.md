Cubrid에서 MySQL로 (1) - 분산 트랜잭션 알아보기

# 상황
- 기존에 사용중인 Cubrid를 MySQL로 마이그레이션 필요
작업 단계
- Cubrid - MySQL에 데이터 쓰기 이중화
-

# 분산 트랜잭션
- n개의 DB에 걸친 작업을 하나의 트랜잭션으로 처리

# ChainedTransactionManager
- `spring-data-commons` 2.5버전부터 deprecated
=> 공식 이슈 : https://github.com/spring-projects/spring-data-commons/issues/2232
=> 답변보면 두 번째 TxManager에서 커밋에 실패했을 때, 첫번째에 이미 커밋된게 롤백되지 않는다는 점을 큰 이슈로 생각한 것 같음
=> 사람들 의견은, 그 한계점을 잘 인지하고 그런 상황에 대비해서 사용하고 있는데 뭐가 문제냐는식
=> 답변자도 쓸거면 쓰라는 식인 것 같음 (여기도 참고 : https://github.com/spring-projects/spring-data-commons/issues/2747)


# XAConnection (2Phase Commit)
- ATKIMOS ?
- Cubrid XAConnection에서는 altHost 지원 안함 ,,

# Kafka Connect
- CDC (Changed Data Capture)



# 참고 자료
---
-
