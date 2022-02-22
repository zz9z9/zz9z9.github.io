---
title: Tomcat & Apache HTTP Server 연동(1)
date: 2022-02-10 13:25:00 +0900
categories: [Infra]
tags: [apache, tomcat]
---

# 들어가기 전
---
Tomcat과 Apache HTTP Server 연동과 관련된 기초 지식을 살펴보고, 다음 파트에서는 실제로 연동하는 작업을 진행해보려고 한다.

# Apache Tomcat Connectors
---
> Apache Tomcat Connectors 프로젝트는 Tomcat 프로젝트의 일부이며, 웹 서버를 Tomcat 및 기타 백엔드와 연결하기 위한 웹 서버 플러그인을 제공한다.

- 지원되는 웹 서버는 다음과 같다.

|웹 서버|플러그인|
|--------|-----------|
| Apache HTTP Server | mod_jk  |
| Microsoft IIS | ISAPI redirector  |
| iPlanet Web Server | NSAPI redirector |

- 플러그인 대부분의 기능은 모든 웹 서버에서 동일하며, 세부 사항은 웹 서버별로 다를 수 있다.
- 모든 경우에 플러그인은 `Apache JServ Protocol(AJP)` 라는 특수 프로토콜을 사용하여 백엔드에 연결한다.
- `AJP`를 지원하는 것으로 알려진 백엔드는 `Apache Tomcat`, `Jetty`, `JBoss` 등이 있다.
- 프로토콜에는 `ajp12`, `ajp13`, `ajp14`의 3가지 버전이 있지만, 아직까지 대부분의 경우 `ajp13`만 사용한다.
  - `AJP 1.3` 또는 `AJPv13`이라고 부르지만 주로 `ajp13`라는 이름을 사용한다.
  - 톰캣은 3.2 버전 이후로 `ajp13`을 지원한다.

# Apache HTTP Server - Tomcat 연동
> 위에서 살펴봤듯이 `mod_jk`를 사용하여 연동한다. (최소 버전 : Apache 1.3, Tomcat 3.2)

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/155136015-f91e631a-2c16-4aaa-9389-459838169266.png" width="80%"/>
  <figcaption align="center"><a href="https://www.akadia.com/download/soug/tomcat/html/tomcat_apache.html"> 출처 : https://www.akadia.com/download/soug/tomcat/html/tomcat_apache.html</a></figcaption>
</figure>

- 웹 서버(`Apache HTTP Server`)는 클라이언트 HTTP 요청을 기다리고 있는다.
  - 요청이 도착하면 서버는 필요한 콘텐츠를 제공하여 요청을 처리하는 데 필요한 모든 작업을 수행한다.
- 서블릿 컨테이너(위의 경우 `Tomcat`)를 추가하면 웹 서버는 다음과 같이 동작한다.
  - 요청을 처리하기 전에, 서블릿 컨테이너 어댑터 라이브러리를 로드하고 초기화한다.
  - 요청이 오면, 특정 요청이 서블릿에 속하는지 확인해야 하며, 서블릿에 속하는 경우 어댑터가 요청을 받아 처리하도록 한다.
  - 어댑터는 일반적으로 요청 URL의 일부 패턴과 요청을 보낼 위치를 기반으로 어떤 요청을 처리할지 알아야한다.

## mod_jk 관련 사항
> mod_jk는 두 개의 엔티티가 필요하다.

1. mod_jk.xxx
- Apache HTTP Server 모듈
  - 운영 체제에 따라 `mod_jk.so`, `mod_jk.nlm` 또는 `MOD_JK.SRVPGM`
- 먼저 Apache HTTP Server의 모듈 디렉토리(예:`/usr/lib/apache`)에 설치되어야 하며 `httpd.conf` 파일에서 로드되어야 한다.
  - ex : `LoadModule jk_module modules/mod_jk.so`

2. workers.properties
- 웹 서버 worker 정의 및 Tomcat 인스턴스가 사용하는 호스트, 포트 등을 정의하는 파일이다. (아래 Worker 파트 참조)
- `workers.properties`파일은 `${APACHE_HOME}/conf` 디렉토리에 있다.
- `httpd.conf`에서 해당 파일의 경로를 정의해야 한다.
  - ex : `JkWorkersFile /etc/httpd/conf/workers.properties`

### 아파치 `httpd.conf` 톰캣 관련 부분 예시
```
# Load mod_jk module
LoadModule    jk_module  modules/mod_jk.so

# Where to find workers.properties
JkWorkersFile /etc/httpd/conf/workers.properties

# Where to put jk shared memory
JkShmFile     /var/log/httpd/mod_jk.shm

# Where to put jk logs
JkLogFile     /var/log/httpd/mod_jk.log

# Set the jk log level [debug/error/info]
JkLogLevel    info

# Send requests for context /examples to worker named worker1
JkMount  /examples/* worker1
```

## 연동시 주의사항
- Apache와 Tomcat이 동일한 파일 시스템 위치에서 콘텐츠를 제공하도록 구성된 경우, Apache가 `WEB-INF` 디렉토리 또는 `JSP` 소스 코드와 같은 콘텐츠(서블릿 컨테이너가 처리해야하는 콘텐츠)를 제공하지 않도록 해야한다.
  - Apache `DocumentRoot`가 Tomcat Host의 `appBase` 또는 Context의 `docBase`와 겹치면 발생할 수 있다.
  - Apache `Alias` 지시문을 Tomcat Host의 `appBase` 또는 Context의 `docBase`와 함께 사용하면 발생할 수 있다.

# Worker
---

## Tomcat Worker
> Tomcat Worker는 일부 웹 서버를 대신하여 서블릿 또는 기타 콘텐츠를 실행하기 위해 대기 중인 Tomcat 인스턴스이다.

- Apache HTTP Server와 같은 웹 서버가 서블릿 요청을 Tomcat 인스턴스(worker)로 전달하도록 할 수 있다.
- 대표적으로 다음과 같은 경우, 여러 개의 worker를 구성할 수도 있다.
  - 모든 개발자가 동일한 웹 서버를 공유하지만, 자신의 worker를 소유하는 개발 환경이 필요한 경우.
  - 하나의 웹 서버에서 여러 사이트를 제공하기 위해, worker 별로 제공하는 가상 호스트가 필요한 경우.
  - 로드 밸런싱을 제공하고자 하는 경우.
    - 즉, 자체 머신에서 여러 worker를 실행하고 요청을 분배해야 한다.

## 웹 서버 플러그인 Worker
> 웹 서버에서 Tomcat 인스턴스로 요청을 전달, 로드 밸런싱 등의 목적을 가진 Worker로써 <br>
> `workers.properties`라는 속성 파일에 정의된다. (경로 : `${APACHE_HOME}/conf`)

- `worker.list`로 worker를 정의한다.
```
# worker 리스트
worker.list= worker1, worker2
```

- 웹 서버를 시작할 때, 플러그인은 `worker.list` 속성에 이름이 나타나는 worker를 인스턴스화한다.
  - 인스턴스화된 worker는 자신에게 맵핑된 특정 요청을 전달받을 수 있다.
- `worker.list`는 여러 번 사용할 수 있다.

### Worker Type
- 현재 존재하는 Worker Type 다음과 같다. (JK 1.2.5):

|Type|정의|
|--------|-----------|
| ajp13 | 이 worker는 ajp13 프로토콜을 사용하여 Tomcat worker에게 요청을 전달한다. |
| lb | 로드 밸런싱 worker로써, 특정 수준의 내결함성과 함께 유연한 로드 밸런싱을 제공한다.|
| status | 로드밸런서를 관리하기 위한 status worker이다. |
| ajp12 | 이 worker는 ajp12 프로토콜을 사용하여 Tomcat worker에게 요청을 전달한다. |
| ajp14 | 이 worker는 ajp14 프로토콜을 사용하여 Tomcat worker에게 요청을 전달한다. |

## Worker Type별 속성 살펴보기
> `workers.properties`파일에 세팅되는 속성과 관련해서 자세한 내용은 [공식 문서](https://tomcat.apache.org/connectors-doc/reference/workers.html) 참조

### ajp13 Worker 살펴보기
> TCP/IP 소켓을 통해 ajp13 프로토콜을 사용하여 Tomcat Worker에게 요청을 전달한다.

```
# "worker2"는 3lb 팩터를 사용하여 www2.x.com가 올라간 서버의 포트 8009에서 수신 대기 중인 Tomcat과 통신한다.
worker.worker2.type=ajp13
worker.worker2.host=www2.x.com
worker.worker2.port=8009
worker.worker2.lbfactor=3
```

### lb Worker 살펴보기
> 로드 밸런싱 worker는 실제로 Tomcat worker와 통신하지 않고, 웹 서버 플러그인 worker 관리를 담당한다.

- 관리하는 부분은 다음과 같다.
  - 웹 서버 플러그인 worker를 인스턴스화
  - 관리되는 worker의 로드 밸런싱 factor(lbfactor)를 사용하여 가중치 라운드 로빈(weighted round-robin) 로드 밸런싱을 수행
    - 가중치 라운드 로빈에서는 lbfactor가 높을수록 더 강력한 시스템(더 많은 요청을 처리함)을 의미
  - 동일한 Tomcat worker에서 실행되는 동일한 세션에 속하는 요청 유지(세션 고정)
  - 실패한 Tomcat worker를 식별하여 요청을 일시 중지하고, lb worker가 관리하는 다른 worker로 fail-over

- 결과적으로, lb worker가 관리하는 worker들은 로드 밸런싱되고(lbfactor 및 현재 사용자 세션을 기반으로) 장애 조치가 이루어지므로 단일 Tomcat 프로세스 종료로 인해 전체 사이트가 마비되지 않는다.

- 다음은 lb worker가 가질 수 있는 속성이다.
  - `balance_workers`
    - 로드 밸런서가 관리해야 하는 worker 목록이다.
    ```
    # The worker balance1 while use "real" workers worker1 and worker2
    worker.balance1.balance_workers=worker1, worker2
    ```
  - `sticky_session`
    - SESSION ID가 있는 요청을 동일한 Tomcat worker로 다시 라우팅해야 하는지 여부를 지정한다.
    - Tomcat이 여러 Tomcat 인스턴스에서 세션 데이터를 유지할 수 있는 세션 관리자를 사용하는 경우 sticky_session을 `false`로 설정한다.
    - 기본적으로 `true`로 설정된다.

# 정리
- 아파치와 톰캣이 연동되려면 `mod_jk` 모듈이 필요하다. (운영체제 별로 이름은 다를 수 있다.)
  - 해당 모듈은 `Apache JServ Protocol(AJP)` 프로토콜을 사용하여 아파치와 톰캣간 통신한다.
- `mod_jk` 모듈을 사용하려면 ?
  - 먼저 아파치 모듈 디렉토리(예:`/usr/lib/apache`)에 설치되어야 있어야한다.
  - 아파치 `httpd.conf`에 모듈이 로드되어야하고, `JKMount` 등 관련 옵션들이 정의되어야 한다.
  - `workers.properties` 파일이 작성되어야한다.
    - `workers.properties`는 웹 서버에서 서블릿 컨텐츠 요청 등을 전달하기 위한 웹 서버 플러그인 worker와 요청을 전달받을 톰캣 인스턴스의 호스트 및 포트 등을 정의한 파일이다.

# 참고 자료
---
- [https://tomcat.apache.org/connectors-doc/](https://tomcat.apache.org/connectors-doc/)
- [https://tomcat.apache.org/connectors-doc/webserver_howto/apache.html](https://tomcat.apache.org/connectors-doc/webserver_howto/apache.html)
- [https://tomcat.apache.org/connectors-doc/common_howto/workers.html](https://tomcat.apache.org/connectors-doc/common_howto/workers.html)
