---
title: api를 호출해서 데이터를 가져오는 로직은 ItemReader에 ItemProcessor에 ?
date: 2023-12-19 10:25:00 +0900
categories: [생각해보기]
tags: [Spring Batch, ItemReader, ItemProcessor]
---

## 상황
- Job : 특정 조건을 만족하는 전체 가게 목록 파일을 일마다 생성
  - a. DB에서 특정 조건 만족하는 가게 목록 전체 가져온다 (페이징)
  - b. 가게 정보중 특정 데이터를 파라미터로 api 호출해서 부가적인 데이터 가져온다
  - c. a,b에서 가져온 데이터를 기반으로 가게 목록 파일 생성한다.

## 내 생각
[api 호출은 db 호출과 마찬가지로 reader에 있어야한다.]
- SRP 관점에서 생각해보자 ..
  - a, b 모두 파일을 생성하기 위해 필요한 데이터를 가져오는 행위이고, b를 수행하려면 a가 반드시 선행되어야 한다.
  - 따라서, a와 b는 하나의 책임으로 볼 수 있을 것 같다.

[api 호출은 processor에 있어야한다.]
- 결국 api를 호출하는 것은 파일을 만드는데 필요한 데이터가 외부에 있기 때문.
- 이를 파일 생성을 위해 필요한 모델을 만드는 행위로 보면 `transformation`의 일환이기 때문에 processor에 있어야한다.


## 공식문서 봐보기
- All batch processing can be described in its most simple form as reading in large amounts of data, performing some type of calculation or transformation, and writing the result out.
- Spring Batch provides three key interfaces to help perform bulk reading and writing: ItemReader, ItemProcessor, and ItemWriter.

## ItemReader
- Although a simple concept, an ItemReader is the means for providing data from many different types of input.
https://docs.spring.io/spring-batch/reference/readers-and-writers/item-reader.html

## ItemProcessor
- https://docs.spring.io/spring-batch/reference/readers-and-writers/item-reader.html

## 결론
- api 호출하는 부분도 데이터를 가져오는게 DB가 아닐뿐, 단순 데이터 세팅을 위한 것이다.
  - 이를 '비즈니스 로직'이라고 볼 수는 없을 것 같고 , 공식 문서 ItemReader 파트에서 얘기한 `many different types of input.` 중 하나라고 생각하는게 맞을 것 같다.
- 만약 파일 생성을 위해 필요한 데이터를 만들기 위해 어떠한 비즈니스 로직을 거치는 등의 과정이 필요하다면 이는 `데이터를 가공`하는 과정이라고 볼 수 있을 것 같고, ItemProcessor 쪽에서 처리하는게 더 적합할 것 같다.
