---
title: AWS 리전과 가용 영역
date: 2026-01-01 22:25:00 +0900
categories: [지식 더하기, AWS]
tags: [AWS]
---

- AWS 서비스는 전 세계 여러 위치에 분산되어 호스팅되며, 이러한 위치들은 AWS Region, Availability Zone, Local Zone, Wavelength Zone으로 구성된다.

## AWS Regions
---
> 물리적으로 분리된 **독립적인 지리적 영역**이다.

![img](/assets/img/aws-region-az-img1.png)
(출처 : [https://docs.aws.amazon.com/global-infrastructure/latest/regions/aws-regions-availability-zones.html](https://docs.aws.amazon.com/global-infrastructure/latest/regions/aws-regions-availability-zones.html))

- 각 Region은 다른 Region과 완전히 격리되도록 설계되었다.
  - 이를 통해 최대 수준의 장애 허용성과 안정성을 달성한다.
- 대부분의 AWS 서비스는 Region 단위 리소스를 지원한다.
- AWS 리소스를 조회할 때는 반드시 Region을 지정해야 하며, 해당 Region에 속한 리소스만 표시된다.
- 일부 리소스는 Region 간 복제가 가능하지만, AWS가 이를 자동으로 수행하지는 않는다.
  - 즉, DR 설계는 사용자 책임 영역

- 각 Region은 여러 개의 독립적인 위치, 즉 Availability Zone으로 구성된다.
  - Region 내의 Availability Zone들은 전용 메트로 광섬유망을 통해 저지연, 고대역폭, 고중복성 네트워크로 상호 연결된다.

- 워크로드를 배포하기 전에, 요구 사항을 가장 잘 충족하는 Region 또는 Regions를 고려해야 한다.
  - 예를 들어, 필요한 AWS 서비스와 기능을 제공하는 Region을 선택해야 하며, 대다수 사용자와 지리적으로 가까운 Region을 선택하면 네트워크 지연 시간을 줄일 수 있다.

### 계정 유형
> 사용자가 사용할 수 있는 Region은 계정 유형에 의해 결정된다.

**일반 AWS 계정**
- 여러 Region을 제공하며, 이를 통해 요구 사항에 맞는 위치에 AWS 리소스를 생성할 수 있다.
  - 예를 들어, 유럽 고객과의 거리 단축이나 **법적 요구 사항**을 충족하기 위해 유럽 Region에 리소스를 생성할 수 있다.

**GovCloud 계정**
- AWS GovCloud (US-West) 및 AWS GovCloud (US-East) Region에 대한 접근을 제공한다.
- 미국 정부·공공기관·규제 산업 전용 계정으로, 일반 AWS 계정과 완전히 분리된 Region 집합

**중국 계정**
- 베이징 및 닝샤(Ningxia) Region에만 접근할 수 있다.
- 즉, 중국 리전은 중국 법규에 따라 완전히 독립 운영

## AWS Availability Zones
---
> 하나의 Region 내부에 존재하는, 서로 격리된 위치이다.

![img](/assets/img/aws-region-az-img2.png)
(출처 : [https://docs.aws.amazon.com/global-infrastructure/latest/regions/aws-regions-availability-zones.html](https://docs.aws.amazon.com/global-infrastructure/latest/regions/aws-regions-availability-zones.html))

- 각 Region에는 **최소 세 개**의 Availability Zone이 존재한다.
- 이는 AWS 상에서 고가용성 애플리케이션을 설계할 수 있도록 하기 위함이다.
  - 즉, 장애 + 유지보수 + 확장 상황을 동시에 고려하기 위함이며
  - AWS에서 말하는 고가용성(HA) 설계는 기본적으로 Multi-AZ를 전제로 한다.

- 각 Availability Zone은 **하나 이상의 독립된 데이터 센터**로 구성되며, 각 데이터 센터는 전원·네트워크·연결의 중복 구성을 갖추고 서로 다른 시설에 위치한다.
  - Availability Zone들은 물리적으로 분리되어 있기 때문에, 화재·토네이도·홍수와 같은 재난이 발생하더라도 **하나의 AZ만 영향을 받도록** 설계되어 있다.

- Availability Zone의 코드는 Region 코드 뒤에 문자 식별자를 붙인 형태이다.
  - 예를 들어, `us-east-2a`, `us-east-2b`, `us-east-2c`는 us-east-2 Region에 속한 Availability Zone들이다.

- 2025년 11월 이전에 생성된 계정의 경우, 일부 오래된 Region에서는 Availability Zone과 AZ 코드 간의 매핑이 AWS 계정별로 독립적으로 이루어진다.
  - 이로 인해, 한 계정에서의 us-east-1a가 다른 계정에서의 us-east-1a와 동일한 물리적 위치가 아닐 수 있다.
  - 반면, 2025년 11월 이후에 생성된 계정은 Availability Zone과 코드가 동일하게 매핑된다.

- 각 Availability Zone에는 AZ ID가 있으며, 이는 모든 AWS 계정에서 동일한 물리적 위치를 의미한다.
  - AZ ID는 Region 코드의 앞 세 글자, Region 코드 끝의 숫자, `-az`, 그리고 숫자를 조합한 형식이다.
  - 예를 들어, `euw1-az1`, `euw1-az2`, `euw1-az3`은 eu-west-1 Region의 Availability Zone에 대한 AZ ID이다.
  - “같은 데이터센터에 두지 않겠다”는 요구 사항은 AZ 코드가 아니라 AZ ID 기준으로 검증해야 함

## 참고 자료
---
- [https://docs.aws.amazon.com/global-infrastructure/latest/regions/aws-regions-availability-zones.html](https://docs.aws.amazon.com/global-infrastructure/latest/regions/aws-regions-availability-zones.html)
- [https://docs.aws.amazon.com/global-infrastructure/latest/regions/aws-regions.html](https://docs.aws.amazon.com/global-infrastructure/latest/regions/aws-regions.html)
- [https://docs.aws.amazon.com/global-infrastructure/latest/regions/aws-availability-zones.html](https://docs.aws.amazon.com/global-infrastructure/latest/regions/aws-availability-zones.html)
- ChatGPT
