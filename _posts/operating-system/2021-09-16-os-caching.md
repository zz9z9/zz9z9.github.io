---
title: OS 캐시
date: 2021-09-16 22:25:00 +0900
categories: [Operating System]
tags: [caching]
---

# OS 캐시
---
- OS에는 디스크 내의 데이터에 빠르게 액세스할 수 있도록 하는 구조가 갖춰져 있다.
- OS는 ***메모리를 이용해서 디스크 액세스를 줄인다.***
  - 애플리케이션에서 이를 활용한다면 OS에 상당부분을 맡길 수 있다.
  - 이를 가능하게 하는 것이 **OS캐시**이다.
  - 리눅스의 경우에는 페이지 캐시(page cache), 버퍼 캐시(buffer cache)라고 하는 캐시 구조를 갖추고 있다.

## 가상 메모리
> 프로그램이 메모리를 사용할 때 물리적인 메모리를 직접 다루지 않고, ***추상화한 소프웨어적인 메모리***를 다루는 구조이다. <br>
> 하드웨어에서 제공하는 `페이징(paging)`이라고 하는 가상 메모리 구조를 사용해 실현한다.

- 즉, 가상 메모리란 OS가 커널 내에서 ***물리 메모리를 추상화 한 것***이다.
- 프로세스에서 메모리를 다루기 쉽게 하는 이점을 제공한다.
- 가상 메모리의 관리는 OS가 담당한다.

**※ 참고. 스왑(Swap)**
- 스왑은 가상 메모리를 응용한 기술 중 하나이다.
- 물리 메모리가 부족할 때 2차 기억창치(주로 디스크)를 메모리로 간주해서 외형상의 메모리 부족을 해소한다.
  - 물리 메모리가 부족한 경우 장시간 사용되지 않은 영역의 가상 메모리와 물리 메모리 영역 매핑을 해제한다.
  - 해제된 데이터는 디스크 등에 저장해두고 다시 필요해지면 원래로 되돌린다.

### 프로세스에서 메모리에 접근하려면 ?
1. 프로세스에서 OS로 메모리를 요청한다.
2. OS가 메모리에서 비어있는 (물리)메모리 주소 찾는다.
3. OS는 프로세스로 (가상)메모리 주소를 반환한다.
- OS는 메모리 4KB 정도를 블록으로 확보해서 관리한다.
  - 하나의 블록 단위를 '페이지'라고 한다.
  - 즉, 페이지란 OS가 물리 메모리를 확보/관리하는 단위이다.
- OS는 프로세스에서 메모리 요청을 받으면 필요한 만큼의 페이지를 확보해서 프로세스에 반환한다.
4. 프로세스는 가상 메모리에 접근한다. **(물리 메모리로 직접 접근할 수 없음)**
- 커널이 프로세스에 반환하는 가상 메모리 영역은 아직 실제로 물리 메모리와 연결되어 있지 않다.
- 즉, 실체가 없는 메모리 영역이다.
- 프로세스가 가상 영역에 대해 쓰기 작업을 수행하는 시점에 물리 메모리 영역과 연결관계를 맺는다.

### 가상 메모리를 사용해야 하는 이유
> 가상 메모리를 통해 얻을 수 있는 이점은 매우 크며, 이는 멀티 태스킹 OS를 지탱하는 중요한 역할을 담당한다.

- 물리 메모리로 탑재되어 있는 용량 이상의 메모리를 다룰 수 있을 것처럼 프로세스에게 보일 수 있다.
- 물리 메모리상에서는 흩어져 있는 영역을 연속된 하나의 메모리 영역으로 프로세스에게 보일 수 있다.
- Swap을 사용할 수 있다.
- 서로 다른 두 개의 프로세스가 참조하는 가상 메모리 영역을 동일한 물리 메모리 영역에 대응 시킬 수 있다.
  - 이를 통해 두 개의 프로세스가 메모리 내용을 공유할 수 있다.
  - `IPC(Inter Process Communication)` 공유 메모리 등은 이 방법으로 구현된다.

## 리눅스의 페이지 캐시 원리
> OS는 확보한 페이지를 메모리상에 계속 확보해두는 기능을 갖고 있다. 이를 '페이지 캐시'라고 한다. <br>
> 즉, 커널이 한 번 할당한 메모리를 해제하지 않고 계속 남겨두는 것이 페이지 캐시의 기본이다.

### 페이지 캐싱 과정
1. OS는 프로세스에게 요청받은 데이터를 디스크로부터 블록의 크기(ex : 4KB)만큼 읽는다.
2. 읽은 데이터를 (물리)메모리상에 위치시킨다.
3. 물리 메모리 주소를 가상 메모리 주소로 변환하여 프로세스에게 알려준다.
4. 프로세스는 (가상)메모리에 접근해서 데이터를 읽는다.
5. 프로세스가 데이터를 읽고 나서도 OS에서는 해당 데이터를 메모리에서 해제하지 않고 남겨둔다.
- 이를 통해 다른 프로세스에서 동일한 데이터가 필요한 경우 OS가 다시 디스크에 접근하지 않아도 된다.

**※ 캐시 이외의 메모리가 필요하게 되면 오래된 캐시가 파기된다.** <br>
즉, 메모리가 1GB 인데 그 중 900MB가 캐시로 사용되고 있다고 해서 메모리가 부족하다고 생각하지 않아도 된다.


## 4GB의 파일을 1.5GB의 여유가 있는 메모리에 캐싱할 수 있을까?
> 정답은 '가능하다'이다. 어떻게 가능한 것인지 원리를 살펴보자.

- 캐싱하고자 하는 파일에 대해 `i노드 번호`와 `오프셋` 두 가지 값을 키로 캐싱한다.
  - i노드 번호 - 리눅스가 파일을 식별하는 번호
  - 오프셋 - 파일의 어느 위치부터 시작할지를 나타내는 값
  - ***따라서, 파일 전체가 아닌 일부를 캐싱할 수 있다.***
    - '파일의 크기 > 메모리 공간' 이기 때문에, 파일의 일부를 캐싱하더라도 결국 메모리 공간이 꽉 차게 된다.
    - `LRU(Least Recently Used)` - 새로운 데이터를 캐싱하기 위한 메모리 공간을 확보하기 위해 가장 오래된 데이터를 파기
- 파일이 아무리 크더라도 캐싱된 키로부터 해당 페이지를 찾을 때의 데이터 구조는 최적화 되어있다.
  - OS(커널) 내부에서 사용되고 있는 자료 구조는 `Radix Tree`이다.
  - 캐싱된 파일이 커지더라도 캐시 탐색속도가 떨어지지 않도록 개발된 자료 구조이다.

# 참고 자료
---
- 이토 나오야 외 1명, 『웹 개발자를 위한 대규모 서비스를 지탱하는 기술』, 제이펍(2011), 8장
- 이토 나오야 외 5명, 『24시간 365일 서버/인프라를 지탱하는 기술』, 제이펍(2009), 4장