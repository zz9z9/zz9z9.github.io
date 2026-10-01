
- classpath는 Java 애플리케이션이 실행될 때, 클래스 파일(.class) 및 리소스 파일(.properties, .xml, .csv 등)을 찾는 경로를 의미합니다.

- Java 프로그램이 실행될 때, 클래스와 리소스 파일을 어디에서 찾을지 알려주는 경로
- classpath에 포함된 폴더나 JAR 파일 내에서만 클래스 및 리소스를 로드할 수 있음

- 클래스패스는 클래스까지 가는 가장 정확한 경로 정보를 제공합니다.
- 클래스패스의 정확한 명칭은 클래스 검색 경로(Class Search Path)입니다. “HelloWorld 클래스를 찾으시는군요!! 그렇다면 이곳(디렉토리, JAR, ZIP)으로 가보세요!!”라고 말해주는 안내원이 클래스패스입니다. 만약, 클래스패스 같은 안내원이 없다면 어떨까요? 자바는 HelloWorld 클래스를 찾을 때까지 파일 시스템의 모든 디렉토리를 돌아다닐 겁니다.

- 클래스로더(ClassLoader)와 클래스패스(ClassPath)
자바 클래스로더는 런타임 시 클래스를 동적으로 JVM에 로드하는 역할을 수행합니다. 부트스트랩 클래스로더(Bootstrap classloader), 확장 클래스로더(Extension classloader), 시스템 클래스로더(System classloader)로 구성되어 있습니다. 클래스패스는 시스템 클래스로더가 사용하는 매개변수입니다.


-  왜 컴파일된 결과물(.class, .jar, .war 등)을 `build/` 또는 `target/` 디렉토리에 저장해야 할까?
  -  Java 코드는 .java 파일로 작성되지만, 실행하려면 .class 파일로 변환(컴파일)해야 하기 때문!
  -  JAR 또는 WAR 파일로 패키징해야 애플리케이션을 실행하거나 배포할 수 있기 때문!

### 패키징 ?
> 여러 개의 `.class` 파일을 하나로 묶어야 함

- 프로젝트가 커질수록 .class 파일이 많아짐
- 모든 .class 파일을 실행할 때 하나씩 실행하는 것은 비효율적
- JAR(Java Archive) 파일로 묶어야 실행 및 배포가 쉬워짐

```
jar cvf my-app.jar *.class
```

```
my-project
 ├── HelloWorld.java
 ├── HelloWorld.class
 ├── my-app.jar  # 모든 .class 파일이 포함된 JAR 파일
````
 
 
 3. 웹 애플리케이션(WAR 파일)도 패키징해야 함
✔ Spring Boot 같은 웹 애플리케이션은 .war 파일로 패키징해야 서버에서 실행 가능
✔ .war 파일도 target/ 또는 build/ 디렉토리에 저장됨

📍 Spring Boot 프로젝트 빌드 후 생성된 구조

css
복사
편집
📂 my-project
 ├── 📂 src/main/java/com/example
 │   ├── MainApplication.java
 ├── 📂 src/main/resources
 │   ├── application.properties
 ├── 📂 build/libs
 │   ├── my-app-1.0-SNAPSHOT.jar  <-- 최종 실행 파일
 ├── build.gradle
📌 JAR 실행

bash
복사
편집
java -jar build/libs/my-app-1.0-SNAPSHOT.jar
💡 즉, .class 파일을 패키징해야 실제 운영 서버에 배포할 수 있음!

빌드 도구	기본 출력 디렉토리
Maven	target/
Gradle	build/
IntelliJ IDEA (Gradle 사용 시)	out/production/


### Maven & Gradle에서 resources 폴더의 역할
-  Java 프로젝트에서는 src/main/resources 폴더가 "애플리케이션의 정적 리소스를 저장하는 기본 위치"
- 여기에 있는 파일들은 실행 가능한 JAR 파일을 만들 때 포함됨
- **파일 경로가 자동으로 classpath에 추가됨**
- 프로젝트 구조 (Maven/Gradle)
```
my-project
 ├── 📂 src
 │   ├── 📂 main
 │   │   ├── 📂 java/com/example
 │   │   │   ├── Main.java
 │   │   │   ├── CsvFileReader.java
 │   │   ├── 📂 resources
 │   │   │   ├── data.csv  <-- 여기에 있는 파일이
 ├── 📂 target
 │   ├── 📂 classes
 │   │   ├── data.csv  <-- 컴파일 시 여기에 복사됨
```

- 즉, src/main/resources에 있는 파일은 자동으로 target/classes로 복사되어 classpath에 포함됨.
- 이 과정은 빌드 도구(Maven/Gradle)가 자동으로 처리해 줌!

###  Maven에서 src/main/resources가 target/classes로 이동하는 과정
- Maven 빌드 실행 (mvn package 또는 mvn install)
  - Java 코드를 target/classes/에 .class 파일로 변환
  - src/main/resources 폴더에 있는 파일들을 그대로 target/classes로 복사
  - 즉, data.csv 같은 파일이 "실제 파일 경로"가 아니라 "classpath 내 리소스"가 됨

## 그럼 target, build 이런 디렉토리가 classpath인거야 ?
-  정확히 말하면, "classpath에 포함되는 폴더"이지, classpath 자체는 아님!
- 즉, target/classes/ 또는 build/classes/java/main/ 디렉토리는 classpath에 포함되는 폴더 중 하나임.
- **classpath에 포함된 경로 내에서만 .class 파일과 리소스를 로드할 수 있음**
-  기본적으로 classpath에 포함되는 요소
  - target/classes/ (Maven 빌드 시)
  - build/classes/java/main/ (Gradle 빌드 시)
  - src/main/resources/ → target/classes/ 또는 build/resources/main/으로 복사됨
  - JAR 파일 (lib/ 폴더나 dependency로 등록된 외부 라이브러리)
- Maven 빌드 시 → target/classes/가 classpath에 포함됨
- Gradle 빌드 시 → build/classes/java/main/이 classpath에 포함됨
- **JAR 파일을 실행하면 → JAR 내부가 classpath가 됨** (-jar 옵션을 사용하면 JAR 파일 자체가 classpath로 설정됨)

### maven 프로젝트 예시
```
📂 my-maven-project
 ├── 📂 src/main/java/com/example
 │   ├── App.java
 ├── 📂 src/main/resources
 │   ├── application.properties
 ├── 📂 target
 │   ├── 📂 classes  <-- 📌 classpath에 포함됨!
 │   │   ├── com/example/App.class
 │   │   ├── application.properties
 │   ├── my-app-1.0-SNAPSHOT.jar
```

### gradle 프로젝트 예시

```
📂 my-gradle-project
 ├── 📂 src/main/java/com/example
 │   ├── App.java
 ├── 📂 src/main/resources
 │   ├── application.properties
 ├── 📂 build
 │   ├── 📂 classes/java/main  <-- 📌 classpath에 포함됨!
 │   │   ├── com/example/App.class
 │   ├── 📂 resources/main  <-- 📌 classpath에 포함됨!
 │   │   ├── application.properties
 │   ├── libs
 │   │   ├── my-app-1.0-SNAPSHOT.jar
```