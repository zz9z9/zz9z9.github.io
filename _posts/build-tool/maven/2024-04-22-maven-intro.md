---
title: Maven 맛보기
date: 2024-04-22 22:00:00 +0900
---

## Build Tool이 없으면 ?
- javac Main.java > java Main

- junit 라이브러리 추가 without build tool
```java
import org.junit.Test;

import static org.junit.Assert.assertEquals;

public class Md5Util2Test {

    @Test
    public void helloWorld() throws Exception {
        // Given
        String input = "Hello, world!";
        String expectedOutput = "6cd3556deb0da54bca060b4c39479839";

        // When
        String actualOutput = Md5Util2.stringToMd5(input);

        // Then
        assertEquals(expectedOutput, actualOutput);
    }
}
```

```
$ java -cp .:junit-4.12.jar:hamcrest-core-1.3.jar org.junit.runner.JUnitCore Md5Util2Test
```
=> 이 정도 수준으로만 이해하기는 조금 애매한듯, 이것 뿐만이라면 ant 사용해도 됐을건데 ??
=>https://maven.apache.org/background/history-of-maven.html


## plugin
- Maven은 핵심적으로 플러그인 실행 프레임워크입니다. 모든 작업은 플러그인으로 수행됩니다.
- build 및 reporting 플러그인이 있습니다.
- Build 플러그인
  - 빌드 중에 실행되며 POM의 `<build/>` 요소에서 구성되어야 합니다.
- Reporting 플러그인
  - 사이트 생성 중에 실행되며 POM의 <reporting/> 요소에서 구성되어야 합니다.
  - 보고 플러그인의 결과는 생성된 사이트의 일부이므로 보고 플러그인은 국제화 및 현지화되어야 합니다.

- ex : clean 플러그인 소스 코드 : https://github.com/apache/maven-clean-plugin/blob/master/src/main/java/org/apache/maven/plugins/clean/Cleaner.java

## build lifecycle
- Maven은 빌드 라이프사이클의 중심 개념을 기반으로 합니다. 즉, 특정 아티팩트(프로젝트)를 구축하고 배포하는 프로세스가 명확하게 정의된다는 것입니다.
- 'default', 'clean', 'site'라는 세 가지 빌드 라이프사이클이 내장되어 있습니다.
  - `default` : 프로젝트 배포
  - `clean` : 프로젝트 정리
  - `site` : 프로젝트 웹 사이트 생성

- 빌드 라이프사이클은 여러 단계로 구성됩니다.
  - 이러한 각 빌드 수명 주기는 서로 다른 빌드 단계(phase) 목록으로 정의됩니다.
  - 여기서 빌드 단계는 라이프사이클의 한 단계를 나타냅니다.

- For example, the default lifecycle comprises of the following phases (for a complete list of the lifecycle phases, refer to the Lifecycle Reference):
=> 상세 정보 : https://maven.apache.org/guides/introduction/introduction-to-the-lifecycle.html#Lifecycle_Reference

validate - validate the project is correct and all necessary information is available
compile - compile the source code of the project
test - test the compiled source code using a suitable unit testing framework. These tests should not require the code be packaged or deployed
package - take the compiled code and package it in its distributable format, such as a JAR.
verify - run any checks on results of integration tests to ensure quality criteria are met
install - install the package into the local repository, for use as a dependency in other projects locally
deploy - done in the build environment, copies the final package to the remote repository for sharing with other developers and projects.
These lifecycle phases (plus the other lifecycle phases not shown here) are executed sequentially to complete the default lifecycle. Given the lifecycle phases above, this means that when the default lifecycle is used, Maven will first validate the project, then will try to compile the sources, run those against the tests, package the binaries (e.g. jar), run integration tests against that package, verify the integration tests, install the verified package to the local repository, then deploy the installed package to a remote repository.

- `default` 라이프사이클은 플러그인 바인딩 없이 정의됩니다. 플러그인 바인딩은 각 패키징마다 다르므로 `META-INF/plexus/default-bounds.xml`에 별도로 정의됩니다.
- 예를 들어, jar를 위한 빌드 라이프사이클의 플러그인 바인딩은 아래와 같다.
```xml
<phases>
  <process-resources>
    org.apache.maven.plugins:maven-resources-plugin:3.3.1:resources
  </process-resources>
  <compile>
    org.apache.maven.plugins:maven-compiler-plugin:3.11.0:compile
  </compile>
  <process-test-resources>
    org.apache.maven.plugins:maven-resources-plugin:3.3.1:testResources
  </process-test-resources>
  <test-compile>
    org.apache.maven.plugins:maven-compiler-plugin:3.11.0:testCompile
  </test-compile>
  <test>
    org.apache.maven.plugins:maven-surefire-plugin:3.2.2:test
  </test>
  <package>
    org.apache.maven.plugins:maven-jar-plugin:3.3.0:jar
  </package>
  <install>
    org.apache.maven.plugins:maven-install-plugin:3.1.1:install
  </install>
  <deploy>
    org.apache.maven.plugins:maven-deploy-plugin:3.1.1:deploy
  </deploy>
</phases>
```

## phase
- 빌드 라이프사이클의 한 단계이며, 각 단계별로 순서가 지정되어있다.
- 단계가 주어지면 Maven은 정의된 단계를 포함하여 시퀀스의 모든 단계를 실행합니다.
- 예를 들어 컴파일 단계를 실행하는 경우 실제로 실행되는 단계는 다음과 같습니다.

```
1. validate
2. generate-sources
3. process-sources
4. generate-resources
5. process-resources
6. compile
```

- validate: validate the project is correct and all necessary information is available
- compile: compile the source code of the project
- test: test the compiled source code using a suitable unit testing framework. These tests should not require the code be packaged or deployed
- package: take the compiled code and package it in its distributable format, such as a JAR.
- integration-test: process and deploy the package if necessary into an environment where integration tests can be run
- verify: run any checks to verify the package is valid and meets quality criteria
- install: install the package into the local repository, for use as a dependency in other projects locally
- deploy: done in an integration or release environment, copies the final package to the remote repository for sharing with other developers and projects.

## goal
- Each phase is a sequence of goals, and each goal is responsible for a specific task.
- When we run a phase, all goals bound to this phase are executed in order.
- Phases are actually mapped to underlying goals.
- The specific goals executed per phase is dependant upon the packaging type of the project.
- For example, `package` executes jar:jar if the project type is a JAR, and war:war if the project type is a WAR.
- An interesting thing to note is that phases and goals may be executed in sequence.
```
mvn clean dependency:copy-dependencies package
```
- This command will clean the project, copy dependencies, and package the project (executing all phases up to package, of course).

`mvn help:describe -Dcmd=compile`
=> compile' is a phase corresponding to this plugin:
org.apache.maven.plugins:maven-compiler-plugin:3.1:compile
As mentioned above, this means the compile goal from the compiler plugin is bound to the compile phase.




## 중간 정리
> build lifecycle은 phase로 구성된다. <br>
> phase는 goal로 구성된다.

- build 과정을 볶음밥 만드는 것에 비유하면
  - lifecycle :
  - phase : 볶음밥을 만들기 위한 각 단계 (장보기 - 재료 손질 - 조리)
  - goal : 각 phase별로 수행하는 실제 행위
      - 장보기의 goal : 마트를 간다, 재료를 산다, 돈을 지불한다.
      - 재료 손질의 goal : 칼을 꺼낸다, 재료를 썬다, 각 재료별로 그릇에 담는다
      - 조리의 goal : 손질한 재료를 넣고 볶는다, 밥을 함께 볶는다,



## Module

## The Reactor
- The mechanism in Maven that handles multi-module projects is referred to as the reactor. This part of the Maven core does the following:

Collects all the available modules to build
Sorts the projects into the correct build order
Builds the selected projects in order

## 참고 자료
- https://maven.apache.org/guides/getting-started/index.html
- https://dev.to/aldok/how-to-run-java-without-maven-gradle-or-ide-3hbf
- https://maven.apache.org/guides/getting-started/maven-in-five-minutes.html
- https://maven.apache.org/guides/introduction/introduction-to-the-lifecycle.html
- https://www.baeldung.com/maven-goals-phases
- https://maven.apache.org/plugins/index.html
- https://maven.apache.org/ref/3.9.6/maven-core/default-bindings.html
