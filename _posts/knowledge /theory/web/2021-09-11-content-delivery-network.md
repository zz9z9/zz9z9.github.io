---
title: WEB - CDN(Content Delivery Network)
date: 2021-09-11 00:25:00 +0900
categories: [지식 더하기, 이론]
tags: [WEB]
---

# 들어가기 전
---
얼마전 면접에서 '화면의 초기 로딩 속도가 느리다면 어떻게 해결할 수 있을까요?' 라는 질문에 제대로 대답하지 못했던 기억이 있다.
뒤늦게 생각났는데 CDN을 활용하면 어느정도 개선되지 않을까 하는 생각이 들었다. 하지만, CDN에 대해 어렴풋이 알고있어 얘기를 꺼내지 못했다.
이번 기회에 CDN에 대해 잘 정리해보자.

# CDN이란 ?
---
> Content Delivery Network : 컨텐츠 전송 네트워크

- 정적 컨텐츠를 전송하는데 쓰이는, 지리적으로 분산된 서버의 네트워크이다.
  - html, 이미지, js, 비디오 등과 같은 정적 컨텐츠를 캐싱한다.

- 어떤 사용자가 웹사이트를 방문하면, 그 사용자에게 가장 가까운 CDN 서버가 정적 컨텐츠를 전달한다.

> 다음은 CDN을 활용하는 예를 보여준다.

1. 사용자 A가 이미지 URL을 이용해 image.png에 접근한다.
- URL의 도메인은 CDN 서비스 사업자가 제공한 것이다.
  - 예를 들어 다음 두 URL은 Cloudfront와 Akamai CDN이 제공하는 URL의 예이다.
    - https://mysite.cloudfront.net/logo.png
    - https://mysite.akamai.com/image-manager/img/logo.png

2. CDN 서버의 캐시에 해당 이미지가 없는 경우, 서버는 원본(origin) 서버에 요청하여 파일을 가져온다.
- 원본 서버는 웹 서버일 수도 있고 Amazon S3와 같은 온라인 저장소일 수도 있다.

3. 원본 서버가 파일을 CDN 서버에 반환한다.
- 응답의 HTTP 헤더에는 해당 파일이 얼마나 오래 캐시될 수 있는지를 설명하는 TTL(Time-To-Live)값이 들어있다.

4. CDN 서버는 파일을 캐시하고 사용자 A에게 반환한다.
- 이미지는 TTL에 명시된 시간이 끝날 때까지 캐시된다.

5. 사용자가 B가 같은 이미지에 대한 요청을 CDN 서버에 전송한다.
6. 만료되지 않은 이미지에 대한 요청은 캐시를 통해 처리한다.

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/132958378-63e2447d-f68d-450f-9007-030b5cd3b0b3.png" width="70%"/>
  <figcaption align="center">출처 : <a href="https://mygumi.tistory.com/67" target="_blank"> https://mygumi.tistory.com/67</a> </figcaption>
</figure>


# CDN 사용 시 고려해야 할 사항
---
## 1. 비용
CDN은 보통 제 3 사업자(thrid-party providers)에 의해 운영되며, CDN으로 들어가고 나가는 데이터 전송 양에 따라 요금을 내게 된다.
따라서, 자주 사용되지 않는 컨텐츠를 캐싱하는 것은 득이 될 것이 없으므로 CDN에서 빼는 것을 고려한다.

## 2. 적절한 만료 시한 설정
시의성이 중요한(time-sensitive) 컨텐츠의 경우, 만료 시점을 잘 정해야 한다.
너무 길지도 않고 짧지도 않아야 하는데, 너무 길면 컨텐츠의 신선도는 떨어질 것이고, 너무 짧으면 원본 서버에 빈번히 접속하게 되어 좋지 않다.

## 3. CDN 장애에 대한 대처 방안
CDN 자체가 죽었을 경우 웹사이트/애플리케이션이 어떻게 동작해야 하는지 고려해야 한다.
일시적으로 CDN이 응답하지 않을 경우, 해당 문제를 감지하여 원본 서버로부터 직접 컨텐츠를 가져오도록 클라이언트를 구성하는 것이 필요할 수도 있다.

## 4. 컨텐츠 무효화(invalidation) 방법
아직 만료되지 않은 컨텐츠라 하더라도 아래 방법 가운데 하나를 쓰면 CDN에서 제거할 수 있다.
- CDN 서비스 사업자가 제공하는 API를 이용하여 컨텐츠 무효화
- 컨텐츠의 다른 버전을 서비스하도록 오브젝트 버저닝(object versioning)을 이용
  - 컨텐츠의 새로운 버전을 지정하기 위해서는 URL 마지막에 버전 번호를 인자로 주면 된다.
  - 예를 들어, image.png?v=2와 같은 식이다.



# CDN의 필요기술
---
▶ 1. Load Balancing
 - 사용자에게 콘텐츠 전송 요청(Delivery Request)을 받았을 때, 최적의 네트워크 환경을 찾아 연결하는 기술, GSLB(Global Server Load Balancing)이라고도 한다.
 - 물리적으로 가장 가깝거나 여유 트래픽이 남아 있는 곳으로 접속을 유도하는 기술이다.

※ GSLB(Global server Load Balancing)
DNS(도메인 이름을 IP주소로 변환하는 서비스) 서비스의 발전된 형태라고 할 수 있다.

※ DNS와 GSLB 차이점
 - health check
DNS : 서버의 상태를 알 수 없어서 서비스를 실패하는 유저도 생길 수 있다.
GSLB : 서버의 상태를 모니터링(주기적으로 health check를 수행) 하고 실패한 서버의 IP는 응답에서 제외 하므로, DNS보다 훨씬 강력한 기능을 제공한다.

 - 로드밸런싱
DNS : Round Robin 방식을 사용, 정교한 로드 밸런싱이 힘들다.
GSLB : 서버의 로드를 모니터링 하기 때문에 로드가 적은 서버의 IP를 반환하는 식으로 정교한 로드밸런싱을 할 수 있다.

 - 레이턴시 기반 서비스
DNS : Round Robin 방식을 사용하여 유저는 네트워크상에서 멀리 떨어진 위치의 서버로 연결 할 수도 있다.
GSLB : 각 지역별로 서버에 대한 레이턴시(latency) 정보를 가지고 있기 때문에 유저가 접근을 하면, 유저의 지역으로 부터 가까운(더 작은 레이턴시를 가지는) 서버로 연결을 한다.

 - 위치기반 서비스
DNS : 유저는 Round Robin하게 서버로 연결된다.
GSLB : 유저의 지역정보를 기반으로, 해당 지역을 서비스하는 서버로 연결 할 수 있다.

▶ 2. 컨텐츠를 배포하는 기술
 - 컨텐츠의 삭제나 수정이 일어났을 때 이를 관리할 수 있는 기술이 필요하다.

▶ 3. CDN의 트래픽을 감지하는 기술
 - 통계자료를 고객에게 제공하기 위해 필요하다.
 - 트래픽을 분산하기 위해서 필요하다


# CDN의 캐싱 방식
---
1. Static Caching
– Origin Server에 있는 Content를 운영자가 미리 Cache Server에 복사
  미리 복사해 두기 때문에 사용자가 Cache Server에 Content를 요청시 무조건 Cache Server에 있다.
– 대부분의 국내 CDN에서 이 방식을 사용( ex. NCSOFT 게임파일 다운로드 등)

2. Dynamic Caching
– Origin Server에 있는 Content를 운영자가 미리 Cache Server에 복사하지 않음
– 사용자가 Content를 요청시 해당 Content가 없는 경우 Origin Server로 부터 다운로드 받아 전달한다.
  (Content가 있는 경우는 캐싱된 Content 사용자에게 전달.)
– 각각의 Content는 일정 시간이후 Cache Server에서 삭제될 수도 있다. (계속 가지고 있을 수도 있음)

# CDN 서비스 이용방법
---
1. CDN이용시 소스코드상에서 이미지 링크나 리다이렉트등 CDN을 서비스를 이용할 도메인을 호출 하는 경우 도메인의 주소를 CDN 업체장비의 주소로 이미지를 호출하는 경로로 변경 한다.
ex) 기존의 <img src= "http://www.goddaehee.com/~~~~">  => <img src= "CDN 업체 서버 도메인">

2. 서비스 신청 대상 도메인이 서버(Origin Server)를 바라보게끔 CDN장비주소로 연결 해주는 작업을 해야한다.
(CDN 서비스 신청시 CDN 서비스를 이용할 도메인의 네임서버레코드를 CDN서비스 업체에서 제공하는 도메인주소 또는 IP주소로 연결을 해야 한다.)

ex) http://www.goddaehee.com 이 CDN 서비스를 신청하고 싶은 도메인이라면 네임서버 A레코드를 CDN업체도메인.co.kr 으로 변경작업을 한다.
브라우저 주소창에 http://www.goddaehee.com를 입력했을때 발생되는 요청을 CDN업체 서버로 가게 해주는 작업이다.
기존 http://www.goddaehee.com 에 연결된 A레코드 IP값과 도메인 정보를 보내주면 CDN업체측에서 변경에 필요한 CNAME을 준다.
이에 따라 DNS상에서 CNAME을 각각의 도메인에 적용하여 수정해줘야 한다.

- https://goddaehee.tistory.com/173 [갓대희의 작은공간]

# CDN vs Squid-cache
---
http 프로토콜에 대해 문서 저장하는데 유용한 squid-cache 라는 것도 있는데, 용도는 비슷한것 같다.
둘을 비교해보자

https://www.g2.com/compare/cloudflare-inc-cloudflare-cdn-vs-squid-cache
https://blog.matthewskelton.net/2011/12/02/improving-page-speed-cdn-vs-squid-varnish-nginx/

# 참고 자료
---
- 알렉스 쉬, 『가상 면접 사례로 배우는 대규모 시스템 설계 기초』, 인사이트(2021), 1장

