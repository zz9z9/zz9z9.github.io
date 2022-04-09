---
title: 톰캣 구조 살펴보기
date: 2022-04-07 22:00:00 +0900
categories: [Infra]
tags: [WAS, Tomcat]
---

# 톰캣 구조
<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/145433792-b9c6170e-39f0-4c3f-8b94-351344187311.png" width="70%"/>
  <figcaption align="center">출처 : <a href="https://howtodoinjava.com/tomcat/tomcats-architecture-and-server-xml-configuration-tutorial/" target="_blank"> https://howtodoinjava.com/tomcat/tomcats-architecture-and-server-xml-configuration-tutorial/</a> </figcaption>
</figure>

- 이러한 구조는 일반적으로 Tomcat 설치 폴더의 `/conf` 하위 디렉토리에 있는 `server.xml` 파일에 정의된다.

## server.xml 예시
```xml
<?xml version='1.0' encoding='utf-8'?>
<Server port="8005" shutdown="SHUTDOWN">
   <Listener className="org.apache.catalina.core.AprLifecycleListener" SSLEngine="on" />
   <Listener className="org.apache.catalina.core.JasperListener" />
   <Listener className="org.apache.catalina.core.JreMemoryLeakPreventionListener" />
   <Listener className="org.apache.catalina.mbeans.GlobalResourcesLifecycleListener" />
   <Listener className="org.apache.catalina.core.ThreadLocalLeakPreventionListener" />

  <GlobalNamingResources>
     <Resource name="UserDatabase" auth="Container"
               type="org.apache.catalina.UserDatabase"
               description="User database that can be updated and saved"
               factory="org.apache.catalina.users.MemoryUserDatabaseFactory"
               pathname="conf/tomcat-users.xml" />
   </GlobalNamingResources>

   <Service name="Catalina">
     <Connector port="8080" protocol="HTTP/1.1"
                connectionTimeout="20000"
                redirectPort="8443" />
     <Connector port="8009" protocol="AJP/1.3" redirectPort="8443" />

     <Engine name="Catalina" defaultHost="localhost">
       <Realm className="org.apache.catalina.realm.LockOutRealm">
         <Realm className="org.apache.catalina.realm.UserDatabaseRealm" resourceName="UserDatabase"/>
       </Realm>
       <Host name="localhost"  appBase="webapps"
             unpackWARs="true" autoDeploy="true">
         <Valve className="org.apache.catalina.valves.AccessLogValve" directory="logs"
                prefix="localhost_access_log." suffix=".txt"
                pattern="%h %l %u %t &quot;%r&quot; %s %b" />
       </Host>
     </Engine>
   </Service>
</Server>
```

# 각 구성요소 살펴보기

## Context
> Context는 특정 가상 호스트 내에서 실행되는 웹 애플리케이션을 나타낸다.

- 웹 애플리케이션은 WAR(Web Application Archive) 파일 또는 unpack된 콘텐츠를 포함하는 디렉터리를 기반으로 한다. (버전 2.2 이상 서블릿 스펙에 정의되어 있음)

- 각 HTTP 요청을 처리하는 데 사용되는 웹 애플리케이션은 정의된 각 컨텍스트의 컨텍스트 경로(context path)에 대한 요청 URI의 가능한 가장 긴 접두사를 일치시키는 것을 기반으로 Catalina에 의해 선택된다.
  - 일단 선택되면 해당 컨텍스트는 웹 애플리케이션 배포에 의해 정의된 서블릿 매핑에 따라 들어오는 요청을 처리할 적절한 서블릿을 선택한다.

- 원하는 만큼 Context 엘리먼트를 정의할 수 있다.
  - 각각의 컨텍스트는 반드시 가상 호스트 내에서 고유한 컨텍스트 이름을 가져야 한다.

- Context는 길이가 0인 문자열("")로 된 컨텍스트 경로가 있어야 한다.
  - 이 컨텍스트는 이 가상 호스트의 기본 웹 애플리케이션이 되며, 다른 컨텍스트의 `context path`와 일치하지 않는 모든 요청을 처리하는 데 사용된다.


### 컨텍스트 정의하기
- `<Context>` 엘리먼트를 `server.xml` 파일에 직접 배치하지 않는 것이 좋다.
  - Tomcat을 재시작해야지만 `conf/server.xml` 파일을 다시 로드할 수 있기 때문에, Context 설정을 수정하기가 어려워진다.

- 개별 컨텍스트는 다음과 같이 명시적으로 정의될 수 있다.
  - 애플리케이션 파일 내부의 `/META-INF/context.xml`에 있는 개별 파일에서.
    - 선택적으로(호스트의 copyXML 속성에 따라) 이것은 `$CATALINA_BASE/conf/[enginename]/[hostname]/`에 복사될 수 있으며 애플리케이션의 기본 파일 이름과 `.xml` 확장자로 이름을 바꿀 수 있다.
  - `$CATALINA_BASE/conf/[enginename]/[hostname]/` 디렉토리의 개별 파일(`.xml` 확장자 포함).
    - 컨텍스트 경로 및 버전은 파일의 기본 이름(파일 이름에서 `.xml` 확장자를 뺀 값)에서 파생된다.
    - 이 파일은 웹 애플리케이션의 `META-INF` 디렉토리에 패키징된 모든 `context.xml` 파일보다 항상 우선된다.
  - 메인 `conf/server.xml`의 Host 엘리먼트 내부에 Context 엘리먼트로 정의.

### Context 속성 살펴보기
- **docBase**
  - 웹 애플리케이션의 Document Base(Context Root) 디렉토리 또는 `war` 파일의 경로 이름(애플리케이션이 WAR 파일에서 직접 실행되는 경우).
  - 이 디렉토리 또는 WAR 파일에 대한 절대 경로 이름을 지정하거나 소유 호스트의 appBase 디렉토리에 상대적인 경로 이름을 지정할 수 있다.
  - Context 엘리먼트가 `server.xml`에 정의되어 있거나 `docBase`가 호스트의 `appBase` 아래에 있지 않은 경우 이 필드의 값을 설정해서는 안된다.
  - `docBase`에 심볼릭 링크가 사용되는 경우 심볼릭 링크에 대한 변경 사항은 Tomcat을 다시 시작한 후 또는 컨텍스트를 배포 취소하고 재배포하는 경우에만 적용된다.

- **path**
  - 처리할 적절한 웹 애플리케이션을 선택하기 위해, 각 요청 URI의 시작 부분과 일치하는 웹 애플리케이션의 컨텍스트 경로
  - 특정 호스트 내의 모든 컨텍스트 경로는 고유해야 한다.
  - 빈 문자열("")의 컨텍스트 경로를 지정하면 다른 컨텍스트에 할당되지 않은 모든 요청을 처리하는 이 호스트에 대한 기본 웹 애플리케이션을 정의하는 것이다.
  - `path` 속성은 `server.xml`에서 Context를 정적으로(statically) 정의할 때만 사용해야 한다.
  - 다른 모든 상황에서 경로는 애플리케이션 별 `.xml` 파일 또는 `docBase`에 사용된 파일 이름에서 유추된다.
  - Context를 `server.xml`에 정적으로 정의하는 경우에도 `docBase`가 호스트의 `appBase` 아래에 있지 않거나 `deployOnStartup` 및 `autoDeploy`가 모두 false인 경우가 아니면 이 속성을 설정해서는 안된다.
  - 이 규칙을 따르지 않을 경우 이중 배포가 발생할 수 있다.

## Connector
> Connector는 클라이언트와의 통신을 처리한다.

- Tomcat에는 여러 커넥터를 사용할 수 있다.
  - HTTP connector : 대부분의 HTTP 트래픽 처리
  - AJP connector : Tomcat을 Apache HTTPD 서버와 같은 웹 서버에 연결할 때 사용(AJP 프로토콜 구현)
    - AJP 커넥터를 사용하면 Tomcat이 동적 웹 페이지만 처리하고, 순수 HTML 서버(예: Apache 웹 서버)가 정적 페이지에 대한 요청을 처리할 수 있다.
    - 웹 서버를 Tomcat과 함께 사용할 계획이 없다면 이 커넥터를 주석 처리할 수 있다.

- AJP 커넥터를 사용하면 Tomcat이 동적 웹 페이지만 처리하고 순수 HTML 서버(예: Apache 웹 서버)가 정적 페이지에 대한 요청을 처리할 수 있다.
- Tomcat 자체가 오늘날 매우 빠르거나 단순히 웹 서버를 Tomcat과 함께 사용할 계획이 없다면 이 커넥터를 주석 처리할 수 있습니다.

- 모든 애플리케이션에 대한 요청은 커넥터의 단일 인스턴스를 통과한다.
  - 요청을 받았을 때, 커넥터 내에 alive 상태로 남아있는 새 스레드가 인스턴스화된다(요청이 처리되는 동안).
- 커넥터는 "Coyote"로 불리기도 한다.

### Connector 속성 살펴보기
- **port**
  - 이 커넥터가 서버 소켓을 만들고 들어오는 연결을 기다리는 TCP 포트 번호
    - 운영 체제는 하나의 서버 애플리케이션만 특정 IP 주소의 특정 포트 번호를 수신하도록 허용한다.
    - `0`을 사용하는 경우 Tomcat은 이 커넥터에 사용할 여유 포트를 임의로 선택한다.

- **connectionTimeout**
  - 정의된 시간동안 활동이 없으면 세션이 종료됨을 의미한다. (단위 : 초)

- **redirectPort**
  - SSL(Secure Socket Layer) 전송이 필요한 요청은 정의된 포트로 리디렉션 된다.

- **address**
  - IP 주소가 두 개 이상인 서버의 경우, 지정된 포트에서 수신 대기하는 데 사용할 주소를 지정한다.
    - 기본적으로 이 포트는 서버와 연결된 모든 IP 주소에서 사용된다.
    - 127.0.0.1 값은 커넥터가 루프백 인터페이스에서만 수신 대기함을 나타낸다.

- **secret(tomcat 9 이상)**
  - `secret` 키워드가 있는 worker의 요청만 수락한다.
  - 기본값은 null이며, `secretRequired`가 명시적으로 `false`로 구성되지 않는 한 이 속성은 null이 아니고 길이가 0이 아닌 값으로 지정되어야 한다.
  - 이 속성이 null, 길이가 0이 아닌 값으로 구성된 경우, 작업자는 worker는 일치하는 값을 제공해야 한다.
    - 그렇지 않으면 `secretRequired` 설정에 관계없이 요청이 거부된다.

- **secretRequired(tomcat 9 이상)**
  - 이 속성이 `true`이면 `secret` 속성이 null과 길이가 0이 아닌 값으로 구성된 경우에만 AJP 커넥터가 시작된다.
  - 이 속성은 커넥터가 신뢰할 수 있는 네트워크에서 사용될 때만 `false`로 설정되어야 한다.

## Host
> Host는 서버의 네트워크 이름(예: `www.example.com`)을 Tomcat이 실행되고 있는 특정 서버와 연결하는 가상 호스트를 나타낸다.

- 클라이언트가 네트워크 이름을 사용하여 Tomcat 서버에 연결할 수 있으려면, 이 이름을 사용자가 속한 인터넷 도메인을 관리하는 DNS(Domain Name Service) 서버에 등록해야 한다.

- 대부분의 경우 시스템 관리자는 둘 이상의 네트워크 이름(예: www.mycompany.com 및 company.com)을 동일한 가상 호스트 및 애플리케이션에 연결하려고 합니다.
  - 이 작업은 호스트 이름 별칭 기능을 사용하여 수행할 수 있다.

- 하나 이상의 Host 엘리먼트가 Engine 엘리먼트 내부에 정의될 수 있다.

- Host 엘리먼트 내에 가상 호스트와 연결된 웹 애플리케이션에 대한 Context 엘리먼트가 하나 이상 정의될 수 있다.

- 각 엔진과 관련된 호스트 중 정확히 하나는 반드시 해당 엔진의 `defaultHost` 속성과 일치하는 이름을 가져야 한다.

- 클라이언트는 일반적으로 호스트 이름을 사용하여 연결하려는 서버를 식별한다.
  - 이 호스트 이름은 HTTP 요청 헤더에도 포함된다.
  - Tomcat은 HTTP 헤더에서 호스트 이름을 추출하고 이름이 일치하는 호스트를 찾는다.
  - 일치하는 항목이 없으면 요청이 기본 호스트로 라우팅된다.
  - DNS 이름이 Host 엘리먼트의 이름과 일치하지 않는 모든 요청은 기본 호스트로 라우팅되기 때문에, 기본 호스트의 이름은 DNS 이름과 일치할 필요가 없다(가능하더라도).

- `CATALINA_BASE` 디렉토리를 설정하여 여러 인스턴스에 대해 Tomcat을 구성하지 않은 경우 `$CATALINA_BASE`는 Tomcat을 설치한 디렉토리인 `$ CATALINA_HOME`의 값으로 설정된다.


### Host 속성 살펴보기
- **appBase**
  - Tomcat 설치 폴더 내의 애플리케이션 디렉터리를 정의한다.
  - 각 애플리케이션은 해당 디렉터리 내의 경로로 식별된다.
  - 유일한 예외는 빈 문자열에 매핑되는 `ROOT` 경로입이다.
  - `localhost`의 애플리케이션 기본 디렉토리는 `webapps`다.
    - 즉, `톰캣 설치 경로\webapps\ROOT\` 디렉토리에 있는 애플리케이션은 빈 문자열로 식별된다.
      - ex : `"http://localhost:8080/`
    - `톰캣 설치 경로\webapps\myapp\`와 같이 `ROOT` 이외의 디렉터리에 있는 다른 애플리케이션의 경우 URL은 `http://localhost:8080/myapp/`로 식별된다.

- The Application Base directory for this virtual host. This is the pathname of a directory that may contain web applications to be deployed on this virtual host. You may specify an absolute pathname, or a pathname that is relative to the $CATALINA_BASE directory. See Automatic Application Deployment for more information on automatic recognition and deployment of web applications. If not specified, the default of webapps will be used.

- **unpackWARs**
  - `true`로 설정하고 `war` 파일을 `appBase` 디렉토리에 놓으면, Tomcat이 자동으로 압축을 해제하여 일반 폴더로 확장한다.
  - `false`로 설정하면 애플리케이션이 `war` 파일에서 직접 실행된다.
    - 애플리케이션 실행 시 압축을 풀어야 하기 때문에, `true`일 때 보다 실행 속도는 느려지게 된다.

- **autoDeploy**
  - `true`로 설정되면 Tomcat이 실행되는 동안 `appBase` 디렉토리에 애플리케이션을 놓으면 자동으로 배포된다.

## Engine
> Engine은 특정 서비스에 대한 요청 처리 파이프라인을 나타낸다.

- 엔진은 서비스에 정의된 모든 커넥터의 요청을 수신 및 처리하고, 응답을 클라이언트로 전송하기 위해 적절한 커넥터에 다시 전달한다.
- 엔진은 하나 이상의 호스트를 포함해야 하며 그 중 하나는 기본 호스트로 지정된다.
- 기본 Tomcat 구성에는 호스트 localhost를 포함하는 엔진 `Catalina`가 포함된다.(기본 호스트가 유일한 호스트이기 때문에 기본 호스트로 지정됨)
- Catalina 엔진은 HTTP 커넥터를 통해 수신된 모든 수신 요청을 처리하고 해당 응답을 다시 보낸다.
- 요청 헤더에 포함된 정보를 기반으로 각 요청을 올바른 호스트 및 컨텍스트로 전달한다.

## Service
> Service는 요청을 처리하기 위해 엔진 엘리먼트를 공유하는 하나 이상의 커넥터 엘리먼트의 조합을 나타낸다.

- Tomcat의 기본 구성에는 HTTP 및 AJP 커넥터를 `Catalina 엔진`에 연결하는 `Catalina 서비스`가 포함된다.
- 기본 구현이 간단하고 충분하기 때문에 서비스는 사용자에 의해 거의 커스터마이징 되지 않는다.

## Server
> Server는 Catalina 서블릿 컨테이너를 나타낸다.

- 고유한 엔진과 커넥터가 있는 하나 이상의 서비스를 포함할 수 있다.
- `conf/server.xml` 구성 파일에서 가장 바깥쪽의 단일 요소여야 한다.
- 이 속성은 서블릿 컨테이너 전체의 특성을 나타낸다.

### Server 속성 살펴보기
- **port**
  - 서버가 종료(`shutdown`) 명령을 기다리는 TCP/IP 포트 번호
    - shutdown 포트를 비활성화하려면 -1로 설정한다.
    - 종료 포트 비활성화는 Apache Commons Daemon을 사용하여 Tomcat을 시작할 때 잘 작동합니다(Windows에서 서비스로 실행되거나 un * xes에서 jsvc로 실행).
    - 표준 셸 스크립트로 Tomcat을 실행할 때는 사용할 수 없다.
      - 이는 shutdown `bat|.sh` 및 `catalina.bat|.sh`가 정상적으로 중지하는 것을 방지하기 때문이다.

- **shutdown**
  - Tomcat을 종료하기 위해, 지정된 포트 번호에 TCP/IP 연결을 통해 수신해야 하는 명령 문자열


# 참고 자료
---
- [https://howtodoinjava.com/tomcat/tomcats-architecture-and-server-xml-configuration-tutorial/](https://howtodoinjava.com/tomcat/tomcats-architecture-and-server-xml-configuration-tutorial/)
- [https://tomcat.apache.org/tomcat-8.0-doc/config/context.html](https://tomcat.apache.org/tomcat-8.0-doc/config/context.html)
- [https://tomcat.apache.org/tomcat-8.0-doc/config/host.html](https://tomcat.apache.org/tomcat-8.0-doc/config/host.html)
- [https://tomcat.apache.org/tomcat-8.0-doc/config/server.html](https://tomcat.apache.org/tomcat-8.0-doc/config/server.html)
- [https://tomcat.apache.org/tomcat-8.0-doc/config/service.html](https://tomcat.apache.org/tomcat-8.0-doc/config/service.html)
- [https://tomcat.apache.org/tomcat-8.0-doc/config/ajp.html](https://tomcat.apache.org/tomcat-8.0-doc/config/ajp.html)
