---
title: WEB - read timeout과 keepalive timeout, LB에서부터 역산하기
date: 2026-09-16 22:00:00 +0900
categories: [지식 더하기, 이론]
tags: [WEB]
---

> read timeout과 keepalive timeout은 원래 다른 축이다. 하나는 "응답을 얼마나 기다릴까", 다른 하나는 "다 쓴 커넥션을 얼마나 들고 있을까"다.
> 그런데 LB가 두 축을 노브 하나로 묶어버리면 두 값을 따로 정할 수 없다.
> 이 글은 그 제약이 있는 구성에서 체인 전체의 타임아웃을 LB에서부터 역산하는 순서를 정리한다.

**확인한 것과 확인 못 한 것**

| 내용 | 출처 |
| --- | --- |
| NHN Cloud LB 리스너의 `keepalive_enable`(기본 `true`) · `keepalive_timeout`(기본 300초) · `connection_limit`(기본 2000) | [공개 API 문서](https://docs.nhncloud.com/ko/Network/Load%20Balancer/ko/public-api/) |
| `keepalive on` 일 때 한 값이 client/upstream keepalive timeout과 upstream read timeout에 함께 적용된다는 것 | NHN Cloud 담당자 확인 (2026-09 기준) |
| `keepalive off` 일 때 upstream read timeout 30초 | NHN Cloud 담당자 확인 (2026-09 기준) |
| nginx · Tomcat 기본값 | 각 공식 문서 (본문 링크) |

LB 쪽 두 줄은 공개 문서에 항목이 없다. 상품 스펙이 바뀔 수 있으니 본인 환경에서 다시 확인하는 편이 낫다.

## 구성 — 홉마다 커넥션이 끊긴다

---

> Proxy 모드 LB와 nginx는 HTTP 연결을 종단한다. 요청 하나가 클라이언트에서 WAS까지 가는 동안 TCP 커넥션은 네 번 끊긴다.

```
client ──① LB1(Proxy) ──② nginx ──③ LB2(Proxy) ──④ WAS(tomcat)
```

홉마다 커넥션을 거는 쪽(connector)과 받는 쪽(acceptor)이 갈린다. LB1은 클라이언트에 대해 acceptor이면서 nginx에 대해 connector다. 한 노드가 두 역할을 겸하고, 역할에 따라 걸리는 규칙이 달라진다.

커넥션이 네 개라는 건 요청 하나를 따라갔을 때의 얘기다. keepalive가 켜져 있으면 홉마다 커넥션을 재사용하므로 홉별 커넥션 수는 1:1로 대응하지 않는다. 클라이언트 커넥션 N개가 업스트림 커넥션 M개(M ≪ N)에 실린다. 이 압축이 keepalive를 켜는 실질 이득이고, LB의 `connection_limit` 같은 상한을 덜 건드리게 해준다.

## 두 타임아웃은 원래 다른 축이다

---

> read timeout은 체인 전체에 걸리는 대소 관계이고, keepalive timeout은 홉 하나 안에서만 성립하는 대소 관계다. 적용 단위가 다르다.

| | 적용 단위 | 방향 | 어기면 |
| --- | --- | --- | --- |
| read timeout | 체인 전체 | 안 → 밖으로 커진다 | 바깥이 먼저 끊겨 원인 구간을 오인한다 |
| keepalive timeout | 홉 하나 | 홉마다 connector < acceptor | acceptor가 닫은 커넥션에 요청을 실어 race가 난다 |

### read timeout — 안에서 밖으로 커진다

read timeout은 호출하는 쪽 설정이다. 이 구성에서 가장 안쪽 호출자는 `LB2 → WAS` 고, 밖으로 나가며 `nginx → LB2`, `LB1 → nginx`, `client → LB1` 순이다. 이 순서대로 값이 커져야 한다.

바깥이 먼저 끊기면 WAS는 계속 일하는데 응답을 받을 쪽이 없다. 자원은 자원대로 쓰고, 에러는 타임아웃을 낸 바깥 구간에서 나므로 실제로 느린 구간을 찾기 어려워진다. 안쪽이 먼저 끊겨야 그 홉이 범인이라는 게 드러난다.

read timeout이 재는 건 총 소요시간이 아니라 **바이트와 바이트 사이의 침묵 구간**이다. 응답이 조금씩이라도 계속 흘러나오는 동안은 타임아웃이 계속 리셋된다. 실제로 확인한 내용은 [connectTimeout / readTimeout 은 어디서 세팅되고, 어디서 적용되는가](/posts/connect-readtimeout/)에 정리해뒀다.

### keepalive timeout — 홉마다 connector < acceptor

acceptor가 idle 커넥션을 먼저 닫으면, 그 FIN이 도착하기 전에 connector가 같은 커넥션에 요청을 실을 수 있다. 요청은 이미 닫히는 중인 커넥션으로 나가고 RST로 돌아온다. connector 쪽에서는 `NoHttpResponseException`이나 connection reset으로 보인다.

HTTP 스펙은 서버가 커넥션을 닫기 직전 `408 Request Timeout`을 보내도록 권하지만 실제로 보내는 구현은 많지 않고, 클라이언트도 멱등 메서드에만 재시도하는 경우가 많다. 자세한 내용은 [HTTP의 연결모델](/posts/http-connection-model/)에 정리해뒀다.

그래서 **먼저 닫는 쪽을 connector로 만든다.** connector가 자기 판단으로 커넥션을 버리면 race가 날 커넥션 자체가 없다.

### 시간만 축인 게 아니다

커넥션은 시간이 아니라 요청 수로도 끊긴다. Tomcat `maxKeepAliveRequests` 기본값은 100, nginx `keepalive_requests` 기본값은 1000(1.19.10 이전 100)이다. keepalive를 시간으로만 보면 "왜 멀쩡하던 커넥션이 주기적으로 끊기지"를 설명하지 못한다.

## LB가 두 축을 노브 하나로 묶는다

---

> NHN Cloud LB 리스너에 노출된 타임아웃 노브는 `keepalive_timeout` 하나뿐이다.

| `keepalive_enable` | 적용되는 값 |
| --- | --- |
| `true` (기본) | `keepalive_timeout` 한 값이 클라이언트 쪽 keepalive timeout, 업스트림 keepalive timeout, 업스트림 read timeout 세 곳에 모두 적용된다 |
| `false` | keepalive를 쓰지 않고, 업스트림 read timeout은 30초로 고정된다 |

`keepalive_timeout` 기본값은 300초다. 켜 두면 서로 다른 축인 두 값이 300초로 같이 묶이고, 끄면 read timeout이 30초에 고정된다. **둘 다 원하는 값으로 두는 선택지가 없다.**

## 그래서 LB에서부터 역산한다

---

> LB 값은 나중에 계산해 맞추는 대상이 아니라 먼저 주어지는 제약이다. LB 값을 `K`로 고정하고 나머지를 `K`에서 끌어낸다.

1. `keepalive_enable` on/off를 정한다. off면 그 홉의 read timeout이 30초로 못박히고 keepalive는 논외가 된다.
2. on이면 `keepalive_timeout = K` 를 정한다.
3. 그 LB가 바라보는 **업스트림의 keepalive timeout > `K`** (LB가 connector)
4. 그 LB를 호출하는 **앞단의 keepalive timeout < `K`** (LB가 acceptor)
5. 그 LB가 업스트림 응답을 기다려주는 상한도 `K` 다. WAS 처리시간이 `K` 를 넘으면 끊긴다.

3번과 5번이 같은 `K` 를 반대 방향으로 잡아당긴다. 오래 걸리는 요청을 살리려고 `K` 를 키우면 업스트림 keepalive를 그보다 더 키워야 하고, 커넥션을 짧게 돌리려고 `K` 를 줄이면 read 예산이 같이 줄어든다.

### 기본값 그대로면 이미 깨져 있다

`LB2 → WAS` 홉에 기본값만 넣어보면 이렇다.

| 지점 | 값 | 근거 |
| --- | --- | --- |
| nginx 업스트림 keepalive timeout | 60초 | nginx `upstream` 블록 `keepalive_timeout` 기본값 |
| LB2 `keepalive_timeout` (`K`) | 300초 | NHN LB 리스너 기본값 |
| Tomcat `keepAliveTimeout` | 20초 또는 60초 | `connectionTimeout` 값을 그대로 쓴다. Tomcat 프로그램 기본값은 60초, 배포되는 `server.xml`은 20초 |

4번 규칙(nginx 60초 < `K` 300초)은 우연히 지켜진다. 그런데 3번 규칙은 Tomcat이 `K` 보다 커야 하므로 **300초를 넘겨야** 하는데, 실제 값은 20~60초다. 규칙이 깨진 상태가 기본값이다.

이 상태에서는 LB2가 300초까지 들고 있으려는 커넥션을 Tomcat이 20초 만에 닫는다. LB2가 그 커넥션을 재사용하는 순간 race가 난다.

### 어느 쪽으로 가도 대가가 있다

깨진 걸 맞추는 방법은 세 가지고, 전부 어딘가를 내준다.

- **`K` 를 유지(300초)하고 Tomcat을 올린다** — `keepAliveTimeout` 을 300초 위로 올려야 한다. WAS가 idle 커넥션을 5분씩 물고 있게 되고, 배포 때 커넥션을 비우는 데 그만큼 걸린다.
- **`K` 를 줄인다** — 예를 들어 30초로 줄이면 Tomcat은 30초 위, nginx 업스트림 keepalive는 30초 아래(기본 60초라 낮춰야 한다)로 맞춰야 한다. 대신 LB2가 WAS 응답을 기다려주는 상한도 30초가 되므로, 그보다 오래 걸리는 요청은 포기해야 한다.
- **`keepalive_enable` 을 끈다** — keepalive 제약에서 빠지는 대신 read timeout이 30초로 고정되고, 홉마다 매 요청 새 커넥션을 맺는다.

어느 쪽을 고르든 출발점은 `K` 다. WAS 설정에서 시작해 LB를 끼워 맞추려 하면 3번과 5번이 충돌하는 지점에서 막힌다.

### nginx 홉은 켜져 있는지부터 확인한다

nginx는 `upstream` 블록에 `keepalive` 지시자가 없으면 **업스트림 keepalive 자체를 쓰지 않는다.** 1.29.7 이전 버전은 `proxy_http_version 1.1` 과 `proxy_set_header Connection ""` 도 같이 필요하다.

```nginx
upstream backend {
    server 10.0.0.10:8080;
    keepalive 16;
    # keepalive_timeout 60s;   기본값
    # keepalive_requests 1000; 기본값
}

server {
    location / {
        proxy_pass http://backend;
        # 1.29.7 이전 버전에서만 필요
        # proxy_http_version 1.1;
        # proxy_set_header Connection "";
    }
}
```

이 설정이 없으면 `nginx → LB2` 홉은 매 요청 새 커넥션이고, 네 홉 전부 keepalive라는 전제 자체가 틀린다. 역산을 시작하기 전에 확인할 부분이다.

## 서비스별로 무엇을 고정하고 무엇을 양보하는가

---

> `K` 하나에 두 축이 묶이면 둘 다 만족시킬 수 없는 구간이 생긴다. 어느 쪽을 기준으로 잡을지는 서비스 성격에 따라 갈린다.

두 타임아웃은 영향을 받는 대상이 다르다.

| | 사용자 체감 | 인프라 자원 |
| --- | --- | --- |
| read timeout | 무한정 대기하지 않게 한다 | 응답 못 받을 요청에 자원을 오래 묶지 않는다 |
| keepalive timeout | 핸드셰이크가 빠진 만큼 빨라진다 | 커넥션·포트 점유를 줄인다 |

read timeout은 호출하는 쪽 설정이다. 클라이언트가 브라우저면 값이 곧 사용자 대기 시간이 되고, 클라이언트가 서버면 호출하는 서버가 알아서 정할 몫이다. keepalive의 자원 절약은 주로 커넥션을 먼저 닫는 쪽에 붙는다. 먼저 닫는 쪽에 TIME_WAIT이 쌓이므로 [소켓 상태](/posts/socket-status/) 관점에서는 connector 쪽 부담이다.

| 서비스 | 고정하는 쪽 | 이유 |
| --- | --- | --- |
| B2C | read timeout | 값이 그대로 사용자 대기 시간이 된다 |
| 백오피스 | read timeout | 응답 첫 바이트까지의 침묵이 길다 |
| API | keepalive timeout | 사용자 대기 시간이라는 제약이 없다 |

**B2C** 는 커넥션 수가 가장 많아 keepalive 이득도 가장 큰 쪽이다. read를 고정한다는 건 keepalive가 덜 중요하다는 뜻이 아니라, 충돌할 때 양보하는 쪽이 keepalive라는 뜻이다.

**백오피스** 의 근거는 "엑셀 다운로드가 오래 걸려서"가 아니다. read timeout은 침묵 구간을 재므로, 파일이 흘러나오기 시작하면 몇 분이 걸려도 끊기지 않는다. 위험한 건 요청을 받고 파일을 다 만들 때까지 한 바이트도 나가지 않는 구간이다. 응답을 스트리밍으로 바꿔 첫 바이트를 일찍 내보내면 같은 작업도 짧은 read timeout에서 살아남는다.

**API** 는 사용자 대기라는 상한이 없으니, 정상 요청이 끊기지 않을 만큼만 read를 확보하고 나머지는 keepalive 쪽에 맞춘다.

## 효과를 어떻게 재는가

---

> keepalive 이득은 조건에 따라 크게 갈리므로, 바꾸기 전에 지금 재사용이 되고 있는지부터 확인한다.

**재사용되고 있는지** — nginx는 `$upstream_connect_time` 을 로그에 남기면 된다. 커넥션을 재사용했으면 `0.000` 이 찍힌다. 이 값이 계속 0이 아니면 업스트림 keepalive가 안 걸린 것이다.

```nginx
log_format keepalive '$upstream_addr $upstream_connect_time $upstream_response_time';
```

**커넥션이 몇 개나 떠 있는지** — 홉 양쪽에서 같이 본다.

```bash
ss -tn state established '( dport = :8080 or sport = :8080 )' | wc -l
```

**핸드셰이크 비용이 얼마인지** — `curl` 로 연결·TLS·첫 바이트를 나눠 재면 keepalive로 빠지는 구간이 바로 보인다.

```bash
curl -o /dev/null -s -w 'connect=%{time_connect} tls=%{time_appconnect} ttfb=%{time_starttransfer}\n' https://...
```

평문 HTTP에 같은 DC 안이면 빠지는 건 TCP 핸드셰이크 1 RTT뿐이라 이득이 작다. TLS가 붙으면 핸드셰이크 왕복이 통째로 빠지므로 차이가 커진다. `maxKeepAliveRequests` 를 1로 두고 같은 부하를 태워 비교하면 keepalive만의 효과가 분리된다.

## 주의할 부분

---

> keepalive는 커넥션을 살려두는 설정이라, 한쪽이 먼저 죽는 순간이 전부 문제 지점이 된다.

**stale connection** — 위에서 본 connector < acceptor를 어겼을 때 나는 증상이다. 부하가 낮아 커넥션이 오래 놀 때 더 잘 난다. 재현하려면 트래픽을 끊고 acceptor의 keepalive timeout이 지난 뒤 요청 하나를 보내면 된다.

**배포 시 graceful shutdown** — WAS가 종료를 시작하면 살아 있는 keepalive 커넥션에 `Connection: close` 를 붙여 비워야 한다. LB 헬스체크가 down으로 바뀐 뒤에도 이미 맺힌 커넥션으로는 요청이 계속 들어오므로, 처리 중인 요청 시간과 keepalive timeout 중 긴 쪽만큼 기다려야 한다. `K` 를 300초로 두면 이 대기가 현실적인 배포 시간을 넘어선다. 앞의 "어느 쪽으로 가도 대가가 있다"에서 `K` 유지가 비싼 이유가 여기다.

**요청 수 상한** — `maxKeepAliveRequests` · `keepalive_requests` 에 걸려 끊기는 커넥션은 timeout 설정을 아무리 맞춰도 생긴다. 끊기는 것 자체를 없앨 수는 없고, 끊길 때 요청이 실려 있지 않게 하는 게 전부다.

**클라이언트 커넥션 풀** — 호출하는 쪽이 서버라면 풀에 물린 커넥션도 같은 규칙을 받는다. `validateAfterInactivity` · `evictIdleConnections` · `timeToLive` 를 상대의 idle timeout보다 짧게 두는 얘기는 [RestClient 설정](/posts/restclient-config/)에 정리해뒀다.

이 글은 HTTP/1.1 기준이다. HTTP/2나 TLS 종단 위치가 바뀌면 커넥션 단위 자체가 달라지므로 같은 규칙을 그대로 적용할 수 없다.

## 참고 자료

---

- [Load Balancer API 가이드 (docs.nhncloud.com)](https://docs.nhncloud.com/ko/Network/Load%20Balancer/ko/public-api/)
- [Load Balancer 개요 (docs.nhncloud.com)](https://docs.nhncloud.com/ko/Network/Load%20Balancer/ko/overview/)
- [ngx_http_upstream_module — keepalive (nginx.org)](https://nginx.org/en/docs/http/ngx_http_upstream_module.html#keepalive)
- [Apache Tomcat 10.1 — HTTP Connector (tomcat.apache.org)](https://tomcat.apache.org/tomcat-10.1-doc/config/http.html)
- [Connection management in HTTP/1.x (developer.mozilla.org)](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Connection_management_in_HTTP_1.x)
