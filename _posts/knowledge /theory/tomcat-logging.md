
톰캣 로그 넘 많다
catalina.log, catalina.out 등

localhost.YYYY-MM-DD.log: the log of the host
host-manager.YYYY-MM-DD.log and manager.YYYY-MM-DD.log: the logs of the related web applications
catalina.YYYY-MM-DD.log:: the container log file
catalina.out: ??


It might be useful to post the config files, the tomcat version of the log4j in conf and also your applications config of log4j usually in root of your webapp's classpath. One of those may be configured with an appender that is putting things into catalina.out and not into the rotating one. You may also consider reducing the logging level if that's a reason for so much output.


The catalina log is the global log. It is, in fact, the stdout stream for the Tomcat JVM. Tomcat's internal log statements use the java.util.logging package (juli) to log, and the default destination for that log is stdout. The Tomcat run scripts handle the redirection of stdout to a file.

The localhost log is the log for a virtual host within Tomcat. Usually there's not much of interest in it, but when you cannot find an error in catalina.out and something is seriously wrong, check this file.

Each webapp is responsible for its own logging. Tomcat provides no support for application logs at all unless you want to count the old servlet log function that did a brain-dead write to Tomcat stdout. You can use any logger you want to in your webapp, including log4j, juli, apache commons logging, or - as in the case of some of my more complex apps, several of the preceeding, merged and co-ordinated by a master log manager (you have this issue when some of the pre-written third-party components in your webapp are using other loggers). Each webapp therefore is also responsible for its own log configuration.


[JULI]
The internal logging for Apache Tomcat uses JULI, a packaged renamed fork of Apache Commons Logging that is hard-coded to use the java.util.logging framework. This ensures that Tomcat's internal logging and any web application logging will remain independent, even if a web application uses Apache Commons Logging.

To configure Tomcat to use an alternative logging framework for its internal logging, follow the instructions provided by the alternative logging framework for redirecting logging for applications that use java.util.logging. Keep in mind that the alternative logging framework will need to be capable of working in an environment where different loggers with the same name may exist in different class loaders.

A web application running on Apache Tomcat can:

Use any logging framework of its choice.
Use system logging API, java.util.logging.
Use the logging API provided by the Java Servlets specification, javax.servlet.ServletContext.log(...)

---------

많은 개발자들이 개발환경으로 Tomcat 을 많이 사용하고 있습니다. 그리고 log 처리는 log4j를 사용합니다.

그러나 JDK에서 기본으로 제공하는 Logging 클래스도 꽤 쓸만한 기능을 제공하고 있습니다.


java.util.logging 추상 클래스가 바로 그것인데요, 이 클래스를 상속받아 구현한 클래스를 줄여서 JULI 라고 부릅니다.


## logging.properties
 a) 기본적인 Global 설정은 tomcat 디렉토리의 conf 입니다.

  - 이곳에 파일을 두고 설정하면 해당 컨테이너에 등록되는 모든 Application설정을 한방에 할수 있습니다.

 b) Application 별로 설정하고 싶다면, /WEB-INF/classes/ 밑에 logging.properties 를 두면 됩니다.

- 기본적으로 제공하는 핸들러는 java.util.logging.FileHandler 와 java.util.logging.ConsoleHandler 가 있습니다.

- java.util.logging.ConsoleHandler 는 기본출력 (catalina.out)으로 출력하는 핸들러이고,

- java.util.logging.FileHandler 는 날짜별로 롤링되는 특정파일에 출력하는 핸들러입니다.

- level 은 다음과 같이 ALL, FINEST, FINER, FINE, CONFIG, INFO, WARNING, SEVERE를 지원하며

- 오른쪽으로 갈수록 로그량이 적습니다.

- org.apache.tomcat.util.net.TcpWorkerThread 클래스에 대해서 로그를 추가하고 싶을때

ex)
org.apache.tomcat.util.net.TcpWorkerThread.level = ALL
org.apache.tomcat.util.net.TcpWorkerThread.handler = java.util.logging.ConsoleHandler


- org.apache.tomcat.util.net 하위 클래스에 대해서 로그를 추가하고 싶을때

ex)
org.apache.tomcat.util.net.level = ALL
org.apache.tomcat.util.net.handler = java.util.logging.ConsoleHandler


이런식으로 로깅하고 싶은 클래스 또는 패키지를 지정해서 .level = XXX , .handler = java.util.logging.ConsoleHandler 를 달아주기만 하면 됩니다.

------
${INSTANCE_DIR}/conf/logging.properties

Java Logging 에 대한 설정 파일이다. 이 파일 경로는 Tomcat 에 의하여 java.util.logging.config.file 이라는 JVM 시스템 속성으로 정의되어 있다. 만일 이 속성이 없다면 default 로 ${JAVA_HOME}/lib/logging.properties 를 사용하게 된다.

---------

`logging.properties`에서는 총 4가지의 로그가 생성되며, 각 로그는 다음의 내용들로 생성됩니다.

- catalina.YY-MM-DD.log
  - catalina.out과 기본 내용은 동일하지만 stdout, stderr로 생성되는 내용이 기록되지 않습니다.

- localhost.YY-MM-DD.log
  - 호스트의 정보가 기록되는 로그입니다.

- manager.YY-MM-DD.log
  - Tomcat manager와 관련된 내용이 기록되는 로그입니다.

- host-manager.YY-MM-DD.log
  - Tomcat host-manager와 관련된 내용이 기록되는 로그입니다.

## 톰캣 로그 저장 위치
tomcat logs 디렉토리(${catalina.base}/logs)에 저장되는 로그는 아래와 같은 곳에서 설정이 가능합니다.

- catalina.out
  ${catalina.base}/bin/catalina.sh

- host-manager, localhost, manager
  ${catalina.base}/conf/logging.properties

- localhost_access_log
  ${catalina.base}/conf/server.xml


로그 저장 위치를 원하는 곳으로 변경 하는 방법은 두가지로 생각해 볼 수 있습니다.



첫번째는 logging.properies, catalina.sh, server.xml 등에서 디렉토리를 변경하는 방법이고

두번째는 ${catalina.base}/logs 디렉토리를 원하는 디렉토리로 soft link 시키는 방법입니다.





1. 각 설정에서 logging 디렉토리 변경

# vi /usr/local/tomcat/conf/logging.properties

변경 전

1catalina.org.apache.juli.FileHandler.level = FINE
1catalina.org.apache.juli.FileHandler.directory = ${catalina.base}/logs
1catalina.org.apache.juli.FileHandler.prefix = catalina.

변경 후

1catalina.org.apache.juli.FileHandler.level = FINE
1catalina.org.apache.juli.FileHandler.directory = /var/log/tomcat
1catalina.org.apache.juli.FileHandler.prefix = catalina.


# vi /user/local/tomcat/bin/catalina.sh

변경 전

if [ -z "$CATALINA_OUT" ] ; then
  CATALINA_OUT="$CATALINA_BASE"/logs/catalina.out
fi

변경 후

if [ -z "$CATALINA_OUT" ] ; then
  CATALINA_OUT=/var/log/tomcat/catalina.out
fi


# vi /user/local/tomcat/conf/server.xml

변경 전
<Valve className="org.apache.catalina.valves.AccessLogValve" directory="logs" prefix="localhost_access_log." suffix=".txt"
pattern="%h %l %u %t &quot;%r&quot; %s %b" />

변경 후
<Valve className="org.apache.catalina.valves.AccessLogValve" directory="/var/log/tomcat" prefix="localhost_access_log." suffix=".txt"
pattern="%h %l %u %t &quot;%r&quot; %s %b" />


2. ${catalina.base}/logs 디렉토리를 원하는 디렉토리로 soft link

# ln -s /var/log/tomcat /usr/local/tomcat/logs


## catalina.log
/conf/logging.properties의 설정에 따라 로깅이 수행되며, 톰켓 내부의 로깅만 출력되며 표준출력(stdio) 및 표준 에러(stderr)는 출력되지 않는다.

톰켓의 내부 로깅은 디폴트로 7.x까지는 Apache Commons Logging을 이용한 로깅 시스템을 구현하였고 8.x에서는 JULI(Apache Commons Logging의 )를 사용한다.

JCL은 다른 로깅 프레임워크의 경량형 래퍼로 실제로 로깅을 구현하는 프레임워크가 필요하다. 톰켓의 디폴트 설정은 java.util.logging을 이용하도록 되어 있다.

------------

Catalina.{YYYY-MM-DD}.log is some logs that Tomcat runs yourself, mainly records Tomcat running content when starting and pause.

----------



## catalina.out
Seems like System.out and System.err are redirected to catalina.out. Not all the loggings. catalina.out used to store console outputs.

tomcat console ??

톰켓 구동 후 표준출력(stdio) 및 표준 에러(stderr)가 모두 출력된다. 한번 만들어 지면 계속해서 추가만되며 커질 경우 문제(비정상 종료)가 발생할 수 있다.

※ 주의 사항:

사용자 소스 코드에서 System.out.println 이나 System.err.println 으로 남기는 로그가 있다면 그 내용은 오직 catalina.out 에서만 찾아볼 수 있다.

이 내용은 "catalina.YYYY-MM-DD.log" 파일에 저장되지 않는다.

-------------

The Catalina.Out log file is "Stdout" and Stdout, and Stderr. We use it in the appSystem.outPrinting content is output to this log file. Also, if we use other log frames in your app, you are configured to output logs to the console, or you will also output it.

This log setting is specified in the startup script of Tomcat. Below is a startup script of Tomcat under Linux:

--------

The catalina.out log messages and log files communicate events and conditions that affect Tomcat server’s operations. Logs for all identity applications components including OSP and Identity Reporting are also logged to the catalina.out file. This file also records the interactions between the Tomcat server and the client.


## localhost.YYYY-MM-DD.log
Localhost. {YYYY-MM-DD} .log is mainly the log for the application initialization (Filter, servlet), which is not processed by Tomcat, which is also a running log that contains Tomcat startup and pause, but it There is no Catalina.Yyyy-mm-dd.log log.

----------

This is the log for all HTTP transactions between the client and the application server. The log file is named as, localhost_access_log.<date of log generation>.txt file. The default location and rotation policy for this log is the same as catalina.out file.

## localhost_access_log.YYYY-MM-DD.txt
Tomcat's request access log, the request time, the request, the request, and the returned status code have records. Configuring this log is very necessary, let us know the status of the request.

Traditional configuration

The default is configured in Server.xml, as follows:

```xml
<Valve className="org.apache.catalina.valves.AccessLogValve" directory="logs"
               prefix="localhost_access_log" suffix=".txt"
               pattern="%h %l %u %t &quot;%r&quot; %s %b" />
```


## Configuration in Spring Boot
Used in Spring Boot is embedded Tomcat, also supports configuration of Access_log.

```properties
server:
  tomcat:
         # Premier this configuration, the default will be created in the TMP directory, and Linux sometimes deletes the contents of the TMP directory.
    basedir: my-tomcat
    accesslog:
      enabled: true
      pattern: '%t %a "%r" %s %S (%b M) (%D ms)'
```


## application.log
 Each identity application component is responsible for its own logging. Tomcat provides no support for application logs. Each component will have its own logging configuration where default log levels and appender configurations are defined. These logging configuration files are placed under \conf directory of Tomcat server.



## Console
   When running Tomcat on unixes, the console output is usually redirected to the file named `catalina.out`. The name is configurable using an environment variable. (See the startup scripts). Whatever is written to System.err/out will be caught into that file. That may include:

   Uncaught exceptions printed by java.lang.ThreadGroup.uncaughtException(..)
   Thread dumps, if you requested them via a system signal
   When running as a service on Windows, the console output is also caught and redirected, but the file names are different.

   The default logging configuration in Apache Tomcat writes the same messages to the console and to a log file. This is great when using Tomcat for development, but usually is not needed in production.

   Old applications that still use System.out or System.err can be tricked by setting swallowOutput attribute on a Context. If the attribute is set to true, the calls to System.out/err during request processing will be intercepted, and their output will be fed to the logging subsystem using the javax.servlet.ServletContext.log(...) calls.
   Note, that the swallowOutput feature is actually a trick, and it has its limitations. It works only with direct calls to System.out/err, and only during request processing cycle. It may not work in other threads that might be created by the application. It cannot be used to intercept logging frameworks that themselves write to the system streams, as those start early and may obtain a direct reference to the streams before the redirection takes place.


## Using java.util.logging (default)
The default implementation of java.util.logging provided in the JDK is too limited to be useful. The key limitation is the inability to have per-web application logging, as the configuration is per-VM. As a result, Tomcat will, in the default configuration, replace the default LogManager implementation with a container friendly implementation called JULI, which addresses these shortcomings.

JULI supports the same configuration mechanisms as the standard JDK java.util.logging, using either a programmatic approach, or properties files. The main difference is that per-classloader properties files can be set (which enables easy redeployment friendly webapp configuration), and the properties files support extended constructs which allows more freedom for defining handlers and assigning them to loggers.

JULI is enabled by default, and supports per classloader configuration, in addition to the regular global java.util.logging configuration. This means that logging can be configured at the following layers:

Globally. That is usually done in the ${catalina.base}/conf/logging.properties file. The file is specified by the java.util.logging.config.file System property which is set by the startup scripts. If it is not readable or is not configured, the default is to use the ${java.home}/lib/logging.properties file in the JRE.
In the web application. The file will be WEB-INF/classes/logging.properties
The default logging.properties in the JRE specifies a ConsoleHandler that routes logging to System.err. The default conf/logging.properties in Apache Tomcat also adds several AsyncFileHandlers that write to files.

A handler's log level threshold is INFO by default and can be set using SEVERE, WARNING, INFO, CONFIG, FINE, FINER, FINEST or ALL. You can also target specific packages to collect logging from and specify a level.

# 참고 자료
---
- https://tomcat.apache.org/tomcat-8.5-doc/logging.html
- https://stackoverflow.com/questions/51985958/what-is-the-difference-between-catalina-out-and-catalina-yyyy-mm-dd-log-log
- https://m.blog.naver.com/PostView.naver?isHttpsRedirect=true&blogId=estern&logNo=221554101664
- https://programmerall.com/article/91062176084/
- https://linuxism.ustd.ip.or.kr/519
- https://sarc.io/index.php/tomcat/900-apache-tomcat-java-logging-juli
- https://www.netiq.com/documentation/identity-manager-47/identity_apps_admin/data/netiq-identity-manager-types-of-log-files.html
- https://coderanch.com/t/607043/application-servers/Difference-application-log-Catalina-Log
