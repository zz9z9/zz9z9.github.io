---
title: WEB - nginx 처리율 제한 살펴보기
date: 2025-05-20 21:25:00 +0900
categories: [지식 더하기, 이론]
tags: [WEB]
---

- nginx는 처리율 제한을 위해 'leaky bucket algorithm' 사용
- leaky bucket algorithm
  - 물 : 사용자 요청
  - 버킷 : 요청이 대기하는 큐
  - 넘치는 물 : 큐가 다 차서 거절되는 요청
  - 새는 물 : 서버에 의해 처리되는 요청

```
limit_req_zone $binary_remote_addr zone=mylimit:10m rate=10r/s;

server {
    location /login/ {
        limit_req zone=mylimit;

        proxy_pass http://my_upstream;
    }
}
```

### limit_req_zone
- 문법 : `limit_req_zone key zone=name:size rate=rate [sync];`
- Context : `http`

**key**
- 어떤 기준으로 요청을 제한할지를 지정
- 예제에서는 `$binary_remote_addr`를 사용하고 있는데, 이 변수는 클라이언트의 IP 주소를 이진 형태로 나타낸다.
- 특정 api 호출 전체를 제한하려면 ?
  - `$server_name` 같은 공통키 사용

**zone**
- 제한 상태(예: 각 IP가 얼마나 자주 요청했는지 등)를 저장하는 공유 메모리 공간을 지정
- 공유 메모리를 사용하기 때문에, 이 정보는 여러 NGINX 워커 프로세스 간에 공유
- IP 주소 하나당 상태 정보 저장에 약 64바이트(32bit), 128바이트(64bit) 가 필요
  - 따라서 32bit 기준 1MB로 약 16,000개 64비트 기준 약 8,000개 저장 가능
- 새로운 항목을 만들 때마다 최근 60초 동안 사용되지 않은 항목 최대 2개를 제거해 메모리 고갈을 방지
- 만약 저장 공간이 가득 찼는데 새로운 IP 주소의 상태 정보를 저장하려고 하면:
  - 가장 오래된 항목을 제거하고, 그래도 공간이 부족하면 `503(Service Temporarily Unavailable)` 상태 코드를 반환

**rate**
- 최대 요청 속도를 지정
- 예를 들어 10r/s라고 하면, 초당 10건의 요청만 허용
  - nginx는 밀리초 단위로 요청을 추적하므로, 이 설정은 **100ms마다 1개의 요청을 허용**한다는 의미
- 지원 단위	: 초(`r/s`), 분(`r/m`)

**sync ?**
- 워커 프로세스가 여러 개일 때 공유 메모리(zone)를 이용해 rate limit 상태를 공유하지만, 워크로드이 많거나 고속 요청 환경에서는 다음 문제가 생길 수 있다:
  - 워커 프로세스들이 동시에 zone을 업데이트하면  동기화 지연이나 race condition처럼 보이는 현상이 발생할 수 있음
  - 즉, 잠깐 동안 초과 요청이 제한 없이 들어가는 것처럼 보일 수 있음

- sync 옵션은 이런 상황에서:
  - 정확도 향상 : 요청 제한 속도를 보다 정확하게 적용
  - 레이스 컨디션 방지 : 워커 간 동시 업데이트 시 충돌 완화
  - Burst 처리의 일관성 개선 : 여러 워커가 동시에 burst 큐를 채우는 상황을 제어

### limit_req
- 문법 : `limit_req zone=name [burst=number] [nodelay | delay=number];`
- Context : `http`, `server`, `location`

**burst**
- 만약 위 같은 예시에서 동일한 IP에서 100ms 이내에 2개의 요청이 들어오면, NGINX는 두 번째 요청에 대해 503 (Service Temporarily Unavailable) 응답을 보냄
  - 다른 응답 코드를 보내고 싶으면 [limit_req_status](https://nginx.org/en/docs/http/ngx_http_limit_req_module.html#limit_req_status) 활용
- 하지만 대부분의 애플리케이션은 **순간적으로 요청이 몰리는 현상(burst)**이 발생

```
location /login/ {
    limit_req zone=mylimit burst=20;

    proxy_pass http://my_upstream;
}
```

- `burst=20` : 지정된 속도(예: 초당 10회 요청)를 초과하는 최대 20개의 요청까지 큐에 저장 가능
  - 예를 들어, 동시에 21개의 요청이 들어오면:
    - 첫 번째 요청은 즉시 처리나머지 20개 요청은 큐에 저장
    - 이후 100ms마다 하나씩 처리됨 (설정된 속도: 10r/s에 맞춰)
    - 만약 큐가 꽉 찬 상태에서 또 요청이 들어오면, 그 요청은 503 에러로 거부됨

**nodelay**
- burst 설정은 요청을 일정 간격으로 처리하므로 트래픽이 부드럽게 흐르지만, 사용자 입장에서는 사이트가 느려진 것처럼 느껴질 수 있다.
- 예를 들어 큐의 마지막 요청(20번째)은 최대 2초까지 기다려야 하며, 이 응답은 이미 쓸모 없어졌을 수도 있다.

```
location /login/ {
    limit_req zone=mylimit burst=20 nodelay;

    proxy_pass http://my_upstream;
}
```

- nodelay는 큐 슬롯은 유지하지만, 큐에 넣은 요청을 즉시 처리
- 단, 속도 제한은 여전히 적용되며, 슬롯을 차지한 후 일정 시간(예: 100ms)이 지나야 슬롯이 다시 사용 가능
  - 즉, 매100ms마다 슬롯 한 개를 비움

**예시 상황**
1. 큐가 비어 있는 상태에서 IP 하나가 동시에 21개의 요청을 보냄
- 21개 모두 즉시 처리
- 이 중 20개는 큐 슬롯을 **‘점유 중’**으로 표시
- 슬롯은 이후 100ms마다 하나씩 해제됨

2. 501ms 후 20개 요청이 들어옴
- 슬롯 5개가 해제되어 있음
- 5개 요청 처리, 15개 요청 거부 (503)

**delay**

```
limit_req_zone $binary_remote_addr zone=ip:10m rate=5r/s;

server {
    listen 80;
    location / {
        limit_req zone=ip burst=12 delay=8;
        proxy_pass http://website;
    }
}
```

- delay를 지정하면 일정 개수까지는 바로 처리하고, 나머지는 초당 요청 제한(rate)을 지키며 처리


<figure align = "center">
  <img width="723" alt="Image" src="https://github.com/zz9z9/zz9z9.github.io/assets/a5045d45-ed0b-44ec-bda7-e07be101becb" />
  <figcaption align="center">출처 : <a href="https://blog.nginx.org/blog/rate-limiting-nginx" target="_blank"> https://blog.nginx.org/blog/rate-limiting-nginx</a> </figcaption>
</figure>


### 특정 IP 별도 처리

```
geo $limit {
    default 1;
    10.0.0.0/8 0;
    192.168.0.0/24 0;
}

map $limit $limit_key {
    0 "";
    1 $binary_remote_addr;
}

limit_req_zone $limit_key zone=req_zone:10m rate=5r/s;

server {
    location / {
        limit_req zone=req_zone burst=10 nodelay;

        # ...
    }
}
```

- `geo`
  - 클라이언트 IP를 기반으로 `$limit` 변수 값을 설정
  - 10.0.0.0/8 및 192.168.0.0/24 대역에 속한 IP는 `$limit` = 0
  - 그 외 IP는 `$limit` = 1 (기본값)

- `map`
  - `$limit` 값을 기준으로 `$limit_key`를 설정
    - `$limit == 0` → `$limit_key = ""` (빈 문자열)
    - `$limit == 1` → `$limit_key = $binary_remote_addr`

- `limit_req_zone`
  - `$limit_key`를 기준으로 요청 속도를 제한
  - 키가 빈 문자열("")이면 속도 제한이 적용되지 않음
    - 즉, 허용된 IP(allowlist)는 제한 없이 통과되고, 나머지는 초당 5건으로 제한됨

### 여러 개의 limit_req 디렉티브를 동시에 사용
- 각 제한이 서로 충돌하면: **가장 강한 제한(최소 속도 or 가장 긴 지연)**이 적용됨

```
http {
    limit_req_zone $limit_key zone=req_zone:10m rate=5r/s;
    limit_req_zone $binary_remote_addr zone=req_zone_wl:10m rate=15r/s;

    server {
        location / {
            limit_req zone=req_zone burst=10 nodelay;
            limit_req zone=req_zone_wl burst=20 nodelay;
            # ...
        }
    }
}
```

| 대상 IP      | req\_zone (5r/s) 적용 | req\_zone\_wl (15r/s) 적용 | 실제 제한                  |
| ---------- |---------------------| ---------------------- | ---------------------- |
| 허용된 IP     | X (key가 "")         | O (binary IP로 적용됨)      | 15r/s 제한               |
| 허용되지 않은 IP | O                   | O                       | 5r/s 제한 (더 엄격한 제한 적용됨) |

## 참고 자료
- [https://blog.nginx.org/blog/rate-limiting-nginx](https://blog.nginx.org/blog/rate-limiting-nginx)
- [https://nginx.org/en/docs/http/ngx_http_limit_req_module.html#limit_req_zone](https://nginx.org/en/docs/http/ngx_http_limit_req_module.html#limit_req_zone)
- [https://nginx.org/en/docs/http/ngx_http_limit_req_module.html#limit_req](https://nginx.org/en/docs/http/ngx_http_limit_req_module.html#limit_req)
