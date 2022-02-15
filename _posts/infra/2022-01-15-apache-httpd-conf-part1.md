---
title: Apache httpd.conf 파일 속성 공부하기(1)
date: 2022-01-15 13:25:00 +0900
categories: [Infra]
tags: [apache, httpd]
---

# 들어가기 전
---
회사에서 서버 이관을 준비하고 있다. 기존에 각각의 서버에 흩어져 있던 애플리케이션을 한 서버로 모으는 등의 작업을 해야하는데, 그럴려면 기존에 세팅된 아파치 설정 파일을 제대로 이해하고 더 나아가 수정하는 등의 작업이 필요할 것 같다.
따라서, `httpd.conf` 파일에 있는 속성들이 어떤 것을 의미하는지, 왜 필요한지 정리해보려고 한다.

# httpd란 ?
---
> **"Hypertext Transfer Protocol daemon"**

- 데몬은 사용자가 직접적으로 제어하지 않고, 백그라운드에서 돌면서 여러 작업을 하는 프로그램을 말한다. ([위키백과](https://ko.wikipedia.org/wiki/%EB%8D%B0%EB%AA%AC_(%EC%BB%B4%ED%93%A8%ED%8C%85)))
- httpd는 웹에서 들어온 요청을 처리하거나, 필요에 따라 다른 프로세스로 전달한다.
- 즉, 웹 서버에서 http 요청을 처리하기 위해 백그라운드에서 동작하는 프로그램이 `httpd`라고 생각하면 될 것 같다.
- 가장 대표적인 httpd 중 하나는 `Apache HTTP Server`이다. ([참고](https://httpd.apache.org/docs/2.4/en/programs/httpd.html))

# httpd.conf 파일 속성, 태그 살펴보기
> 내가 담당하는 서버의 httpd.conf에 있는 태그, 속성 위주로 정리해보려고 한다.

## ServerName
> 서버가 자신을 식별하는 데 사용하는 호스트 이름 및 포트 <br>
> 문법 : `ServerName [scheme://]domain-name|ip-address[:port]`

- ServerName은 이름 기반 가상 호스트(name-based virtual host)를 사용할 때, 가상 호스트를 고유하게 식별하는 데 사용된다.
- ServerName은 서버 정의 내 어디에나 나타날 수 있다.
  - 만약 여러개가 있다면, 맨 마지막에 있는게 ServerName이 된다.
- ServerName이 지정되지 않은 경우, 서버는 먼저 운영 체제에 시스템 호스트 이름을 요청하여 클라이언트의 보이는 호스트 이름을 추론하려고 하고, 실패하면 시스템에 있는 IP 주소를 역방향으로 조회한다.
- 이름 기반 가상 호스트를 사용하는 경우, `<VirtualHost>` 섹션 안의 ServerName은 이 가상 호스트와 일치하도록, 요청의 `Host:` 헤더에 표시할 호스트 이름을 지정한다.

### 참고 : Host vs Server
- 호스트 : 네트워크에 연결되는 컴퓨터 또는 다른 장치
- 서버 : 네트워크 내의 다른 프로그램이나 장치에 서비스를 제공하는 소프트웨어 또는 하드웨어
- 결국엔 서버도 하나의 호스트라고 생각할 수 있을 것 같다.

## \<VirtualHost>
> 특정 호스트 이름 또는 IP 주소에만 적용되는 지시문을 포함 <br>
> 문법 : `<VirtualHost addr[:port] [addr[:port]] ...> ... </VirtualHost>`

- 서버가 특정 가상 호스트에 대한 문서 요청을 받으면, `<VirtualHost>` 섹션에 포함된 구성 지시자(configuration directives)를 사용한다.
- `addr`은 다음 중 하나가 될 수 있으며, 선택적으로 뒤에 콜론과 포트 번호(또는 *)가 올 수 있다.
  - 가상 호스트의 IP 주소
  - 가상 호스트의 IP 주소에 대한 정규화된 도메인 이름(권장하지 않음)
  - 와일드카드 역할을 하고 모든 IP 주소와 일치하는 `*` 문자
  - `*`의 별칭인 문자열 `_default_`

- 각 `<VirtualHost>` 블록 안에 `ServerName`을 지정해야 한다.
  - 없는 경우 메인 서버 구성의 `ServerName`이 상속된다.

- 요청이 수신되면 서버는 먼저 로컬 **IP 주소**와 **포트**를 기준으로 일치하는 `<VirtualHost>`를 찾는다.
  - 와일드카드가 아닌 것이 더 높은 우선순위를 가진다.
  - 일치하는 호스트를 찾을 수 없으면 않으면 메인 서버 구성이 사용된다.

- IP 주소 및 포트에 여러 호스트가 일치하는 경우, 서버는 요청된 **호스트 이름**을 기반으로 일치하는 호스트를 선택한다.
  - 일치하는 가상 호스트가 없으면 **IP 주소와 일치하는 첫 번째 나열된 가상 호스트가 사용된다.**
  - 즉, IP 주소 및 포트 조합에 대해 나열된 첫 번째 가상 호스트가 해당 IP 및 포트 조합에 대한 기본 가상 호스트이다.

## DocumentRoot
> 웹에서 볼 수 있는 main document tree 를 구성하는 디렉토리 <br>
> 문법 : `DocumentRoot directory-path` <br>
> Default : `DocumentRoot "/usr/local/apache/htdocs"`

- 이 지시문은 httpd가 파일을 제공할 디렉토리를 설정한다.
- `Alias`와 같은 지시문과 일치하지 않는 한, 요청된 URL에서 문서 루트까지의 경로를 추가하여 문서의 경로를 만든다.
- 예를 들어, `DocumentRoot "/usr/web"`로 세팅되어 있다면
  - `http://my.example.com/index.html` 에 대한 액세스는 `/usr/web/index.html`을 참조한다.
- 디렉토리 경로가 절대 경로가 아니면, `ServerRoot`에 상대적인 것으로 간주된다.
- **`DocumentRoot`는 후행 슬래시 없이 지정해야 한다.**

## \<Directory>
> 명명된 파일 시스템 디렉터리, 하위 디렉터리 및 해당 내용에만 적용되는 지시문 그룹을 묶는다. <br>
> 문법 : `<Directory directory-path> ... </Directory>`

```text
<Directory "/usr/local/httpd/htdocs">
  Options Indexes FollowSymLinks>
</Directory>
```

- Directory-path는 디렉토리의 전체 경로이거나 Unix 셸 스타일 매칭을 사용하는 와일드카드 문자열이다.
- 와일드카드 문자열에서 `?`는 단일 문자와 일치하고 `*`는 모든 문자 시퀀스와 매칭된다.
- `[]` 문자 범위를 사용할 수도 있다.
- 와일드카드는 `/` 문자와 일치하지 않는다.
  - 즉, `<Directory "/*/public_html">`은 `/home/user/public_html`과 일치하지 않지만 `<Directory "/home/*/public_html">`과는 일치한다.
- `directory-path`는 따옴표로 묶지 않아도 되지만, 경로에 공백이 포함된 경우는 반드시 따옴표로 묶어야 한다. 공백은 끝을 의미하기 때문이다.
- `directory-path`는 Apache httpd가 파일에 액세스하는데 사용하는 파일 시스템 경로와 문자 그대로 일치해야 한다.
  - 즉, 동일한 디렉토리에서 다른 심볼릭 링크를 통해 액세스하는 것과 같은 다른 경로를 통해 액세스하는 파일에는 적용되지 않는다.

## \<Location>
> 포함된 지시문을 일치하는 URL에만 적용 <br>
> 문법 : `<Location URL-path|URL> ... </Location>`

- `<Location>` 지시문은 포함된 지시문의 범위를 URL로 제한한다. (`<Directory>` 지시문과 유사)
- `<Location>` 섹션은 설정 파일에 나타나는 순서대로, `<Directory>` 섹션과 `.htaccess` 파일을 읽은 후, `<Files>` 섹션 이후에 처리된다.
- `<Location>` 지시문이 파일 시스템 위치에 대한 액세스를 제어하는 데 사용되어서는 안된다.
  - 여러 다른 URL이 동일한 파일 시스템 위치에 매핑될 수 있으므로 이러한 액세스 제어가 우회될 수 있다.
- 후행 슬래시가 사용되지 않은 아래 예에서 `/private1`, `/private1/` 및 `/private1/file.txt`에 대한 요청에는 포함된 지시문이 적용되지만 `/private1other`에는 적용되지 않는다.

```text
<Location "/private1">
    #  ...
</Location>
```

- 후행 슬래시가 사용되는 아래 예에서 `/private2/` 및 `/private2/file.txt`에 대한 요청에는 포함된 지시문이 적용되지만 `/private2` 및 `/private2other`에는 적용되지 않는다.

```text
<Location "/private2/">
    # ...
</Location>
```

- 언제 `<Location>`을 사용하는게 좋을까 ?
  - `<Location>`을 사용하여 파일 시스템 외부에 있는 콘텐츠에 지시문을 적용한다.
  - 파일 시스템에 있는 콘텐츠의 경우 `<Directory>` 및 `<Files>`를 사용한다.
  - 예외적으로, `<Location "/">`은 구성을 전체 서버에 쉽게 적용할 수 있는 방법이다.

- 모든 원본(프록시가 아닌) 요청에 대해 일치할 URL은 `/path/` 형식의 URL 경로이다.
  - 즉, 스키마, 호스트 이름, 포트 또는 쿼리 문자열이 포함될 수 없다.
- 프록시 요청의 경우 일치하는 URL은 `scheme://servername/path` 형식이며, 반드시 접두사를 포함해야 한다.

- URL은 와일드카드를 사용할 수 있다.
  - 와일드카드 문자열에서 `?`는 단일 문자와 일치하고 `*`는 모든 문자 시퀀스와 일치한다.
  - 와일드카드 문자는 URL 경로의 `/`와 일치하지 않는다.

- `~` 문자를 추가하여 정규식도 사용할 수 있다.
  - 아래 예는 하위 문자열 `/extra/data` 또는 `/special/data`가 포함된 URL과 일치한다.

```text
<Location ~ "/(extra|special)/data">
    #...
</Location>
```

- `<Location>` 기능은 `SetHandler` 지시문과 결합할 때 특히 유용하다.
  - 예를 들어, 상태 요청을 활성화하되 `example.com`의 브라우저에서만 허용하려면 다음과 같이 사용할 수 있다.

```text
<Location "/status">
  SetHandler server-status
  Require host example.com
</Location>
```


## \<LocationMatch>
> 포함된 지시문을 정규식 일치 URL에만 적용 <br>
> 문법 : `<LocationMatch regex> ... </LocationMatch>`

```text
<LocationMatch "/(extra|special)/data">
    # ...
</LocationMatch>
```

- 지시문 `<LocationMatch>`는 `<Location>`의 정규식 버전과 동일하게 작동하며 많은 글꼴에서 `~`가 `-`와 구별하기 어렵다는 단순한 이유로 선호된다.

## SetHandler
> 일치하는 모든 파일을 강제로 핸들러에서 처리 <br>
> 문법 : `SetHandler handler-name|none|expression`

- `SetHandler`가 `.htaccess` 파일이나 `<Directory>` 또는 `<Location>` 섹션에 배치될 때, 모든 일치하는 파일이 handler-name에 정의된 핸들러를 통해 구문 분석되도록 한다.
- `http://servername/status` 의 URL이 호출될 때마다 서버가 상태 보고서를 표시하도록 하려면 다음을 `httpd.conf`에 추가한다.

```text
<Location "/status">
  SetHandler server-status
</Location>
```

- 특정 파일 확장자를 가진 파일에 대한 특정 핸들러를 구성할 수도 있다.

```text
<FilesMatch "\.php$">
    SetHandler application/x-httpd-php
</FilesMatch>
```

- `None` 값을 사용하여 이전에 정의된 `SetHandler` 지시문을 재정의할 수 있다.

### 참고 : 핸들러란 ?
> 핸들러는 파일이 호출될 때 수행될 작업에 대한 Apache의 내부적인 표현이다.

- 일반적으로 파일에는 파일 유형에 따라 암시적 핸들러가 있다.
- 일반적으로 모든 파일은 단순히 서버에서 제공되지만 특정 파일 형식은 별도로 처리된다.
- 핸들러는 파일 유형과 관계없이 파일 이름 확장자 또는 위치에 따라 명시적으로 구성할 수도 있다.
- 핸들러는 서버에 구축하거나 모듈에 포함하거나 `Action` 지시문으로 추가할 수 있다.
- 표준 배포판에 내장된 핸들러는 다음과 같다.
  - default-handler (core)
    - 정적 콘텐츠를 처리하기 위해 기본적으로 사용되는 핸들러인 `default_handler()`를 사용하여 파일을 보낸다.
  - send-as-is (`mod_asis`)
    - HTTP 헤더가 파일을 있는 그대로 보낸다.
  - cgi-script (`mod_cgi`)
    - 파일을 CGI 스크립트로 취급한다.
  - imap-file (`mod_imagemap`)
    - 이미지맵 규칙 파일(imagemap rule file)로 파싱한다.
  - server-info (`mod_info`)
    - 서버의 구성 정보를 가져온다.
  - server-status (`mod_status`)
    - 서버의 상태 보고서를 가져온다.
  - type-map (`mod_negotiation`)
    - content negotiation을 위해 type map 파일로 파싱한다.

# 참고 자료
- [https://whatis.techtarget.com/definition/Hypertext-Transfer-Protocol-daemon-HTTPD](https://whatis.techtarget.com/definition/Hypertext-Transfer-Protocol-daemon-HTTPD)
- [https://httpd.apache.org/docs/2.4/en/mod/directives.html](https://httpd.apache.org/docs/2.4/en/mod/directives.html)
- [https://pediaa.com/difference-between-host-and-server/](https://pediaa.com/difference-between-host-and-server/)
- [https://httpd.apache.org/docs/2.4/en/handler.html](https://httpd.apache.org/docs/2.4/en/handler.html)
