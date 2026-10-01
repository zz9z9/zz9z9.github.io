> 내 애플리케이션에서 'api/foo'라는 요청을 처리하면 외부 API 서버 'api/bar' 호출이 반드시 필요
> 'api/foo' 요청이 급증해서 외부 서버에도 부하가 커진다면 ?


## 어떤 문제가 생길까 ?
- 외부 서버가 다른 요청들을 제대로 처리하지 못하거나, 심각한 경우 애플리케이션이 멈춘다.
- 이로 인해 'api/foo' 요청 또한 처리가 안된다.

## 우리쪽에선 어떤 조치를 할 수 있을까 ?
> 외부 서버 증설이 어려운 상황임을 가정
> api/foo 요청에 대한 응답이 반드시 실시간이어야 한다. (ex : 상품권 사용)
> api/foo 요청에 대한 응답은 반드시 실시간일 필요는 없지만 최대한 빠르게 처리될수록 좋다. (ex : 배민 주문)

## 실시간 응답 : 처리량 제어 ?

### 웹서버에서 제어
- 고정값이기 때문에, 유동적으로 제한값을 줄이거나 늘리는게 어렵지 않을까 ?
  - 물론 OpenResty의 경우, 관리자 UI → Redis → Lua가 반영, Lua 내에서 공유 메모리(shared_dict)로 제어가 가능은 하다고 한다.
- 제어해야할 api가 다양하다면, 설정 파일로만 관리하기에는 유지보수가 어려울 것 같다.
- 애플리케이션 코드에서 바로 확인이 어렵다. 웹 서버 관련 설정을 봐야지만 해당 사항을 알 수 있다.
- 초당 1000건 => 요청받는 입장에서 0.1초마다 100건씩 들어오는 경우와, 한번에 1000건이 들어오는 것과는 다를 수 있음, 하지만 후자도 허용됨
- 들어오는 요청에 대해서만 제어 가능

- 예시 : nginx에서 초당 1000건으로 제한

```
http {
    # 공통 키 사용 (모든 요청이 동일 키 "global"을 사용함)
    limit_req_zone $server_name zone=global_limit:10m rate=1000r/s;

    server {
        listen 80;
        server_name example.com;

        location /api/foo {
            limit_req zone=global_limit burst=1000 nodelay;
            proxy_pass http://backend;
        }
    }
}
```

- nginx는 워커 프로세스별로 limit zone을 공유하지 않음 → 여러 워커가 있을 경우 실제 제한이 정확하지 않을 수 있음
- 따라서, nginx만으로 제한하는건 한계가 있음
  - nginx는 기본적으로 각 워커(worker process)마다 메모리를 따로 씁니다.
  - limit_req_zone을 써도 요청 수는 IP 기준이고, 전체 요청 수를 정확히 제어하진 못해요.

- Lua는 nginx에 내장되면 ngx.shared.DICT라는 공유 메모리 영역을 사용할 수 있게 돼요.
- 여기에 요청 수를 직접 카운팅하면, 모든 요청을 정확히 제어할 수 있어요.
- 하지만 이 기능은 ngx_http_lua_module이 필요한데, 일반 nginx는 이 모듈이 없고, 이 모듈을 기본 포함하고 있는 게 OpenResty예요. -> https://github.com/openresty/openresty

- OpenResty 기준
```
lua_shared_dict global_limit 10m;

server {
    location /api/foo {
        access_by_lua_block {
            local limit = ngx.shared.global_limit
            local key = "global"
            local current, err = limit:incr(key, 1, 0)

            if current > 1000 then
                return ngx.exit(429)  -- Too Many Requests
            end

            -- 자동 감소를 위해 타이머 사용
            local delay = 1  -- 1초 후에 count 감소
            ngx.timer.at(delay, function(premature)
                limit:incr(key, -1)
            end)
        }

        proxy_pass http://backend;
    }
}

```

**※ Lua ?**
- Lua는 가볍고 빠른 스크립트 언어로, Nginx(OpenResty) 같은 시스템에서 동적 로직을 제어할 때 많이 사용돼요.


## 생각해볼것들
- `내 서버 처리량 >>> 외부 서버 처리량`이면 ?
=> 즉, 외부 서버 처리량 제한으로 인해 내 처리량의 1/n 만 사용하게되면 너무 아깝지 않나 ?
