---
title: 프록시를 통해 API 호출할 때 지연되는 이슈
date: 2024-01-11 22:25:00 +0900
categories: [경험하기, 이슈 노트]
tags: []
---

## 상황
- 프록시 서버를 통해 API를 호출할 때 응답이 지연되는 케이스가 있었고, tcpdump를 통해 확인해본 결과 프록시 서버에 요청을 했다가 응답이 없으니 직접 요청 서버로 접근하는 것을 확인할 수 있었다.
- 프록시 서버에서 응답을 못 받은 이유는 네트워크 ACL 신청이 누락되어서였으며 ACL 등록 이후 해당 현상은 나타나지 않았다.

## 의문점
- 아래 코드로 로컬에서 재현해봤을때 자바 버전에 따라 결과가 다른 것을 알게되었다.
  - `java.net.ConnectException: Connection timed out: connect` 발생 (jdk 버전 : `jdk8u362-b09`)
  - 이슈 상황처럼 지연 응답옴 (jdk 버전 : `openjdk 1.8.0-242`)

```java
public class ProxyTest {

    public static void main(String[] args)  {
        Scanner sc = new Scanner(System.in);
        String url = sc.nextLine();
        String ipAddr = "접근되지 않는 서버 ip";
        String port = "임의의 포트";

        try {
            Properties systemSettings = System.getProperties();
            systemSettings.put("http.proxyHost",  ipAddr);
            systemSettings.put("http.proxyPort", port);
            systemSettings.put("https.proxyHost",  ipAddr);
            systemSettings.put("https.proxyPort", port);

            HttpURLConnection con = (HttpURLConnection) new URL(url).openConnection();

            System.out.println(con.getResponseCode() +  " : " + con.getResponseMessage());
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

}
```

## 원인 파악하기
- 실행 흐름을 확인해보기 위해 지연 응답이 오는 `openjdk 1.8.0-242` 버전에서 프록시 서버뿐 아니라, 요청 url 서버도 접근이 되지 않도록 해보았다.
- 좌 : `jdk8u362-b09`, 우 : `openjdk 1.8.0-242`

<img src = "/assets/img/proxy-issue-img1.png" alt="">

- 표시한 부분부터 실행흐름이 달라지는걸 볼 수 있었고 결과적으로 `sun.net.www.protocol.http.HttpURLConnection.plainConnect0`에서 프록시 서버로 연결 후 예외가 발생했을 때, 구현이 다르게 되어있는 것을 확인할 수 있었다.
  - 좌 : `jdk8u362-b09` (프록시 서버로 재요청), 우 : `openjdk 1.8.0-242` (프록시 서버 null로 세팅하고 재요청)

<img src = "/assets/img/proxy-issue-img2.png" alt="">

### RestTemplate 사용하면 ?
- 내부적으로 `HttpURLConnection` 사용하기 때문에 동일하다.
<img src = "/assets/img/proxy-issue-img3.png" alt="">

## 참고
> [https://bugs.openjdk.org/browse/JDK-8268881](https://bugs.openjdk.org/browse/JDK-8268881)

- 해당 이슈는 버그 리포팅 되었었고 `8u311` 버전에서 해결된 것으로 보인다.





