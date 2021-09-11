---
title: 자바에서 파일 읽어오기
date: 2021-09-08 00:29:00 +0900
categories: [Java]
tags: [Java, File, Files]
---

# 들어가기 전
---
사실 실무에서 자바 코드로 파일을 읽어와서 데이터를 처리하거나 할 일이 없어서, 파일을 다루는 부분에 대한 코드를 작성할 일이 생기면,
그 때 마다 구글링해서 사용했던 것 같다. 최근에 .json 파일에 있는 데이터를 읽어와서 처리해야할 일이 있었는데,
매번 구글링 하는 것 보다 머릿속에 한 번 확실히 정리해야 할 것 같다는 생각이 들어 정리해보기로 했다.

※ 파일 이외에도 네트워크 등 자바에서의 전반적인 I/O(Input/Output)에 대해 알고싶으면 [이 글](https://zz9z9.github.io/posts/java-io-nio/) 을 먼저 읽고 오시는 것을 추천드립니다.


# 파일과 경로
---
> 파일을 다루는 것과 관련하여 뗼 수 없는 것이 바로 '경로'라고 생각한다. <br>
> 따라서, 자바에서는 경로를 어떻게 다루는지 먼저 살펴보자.

## getPath()
- 간단히 말해서, getPath()는 파일의 추상 경로 이름(abstract pathname)의 문자열 표현을 반환한다.
- 이것은 본질적으로 파일 생성자에 전달되는 경로 이름이다.
- 따라서 상대 경로를 사용하여 File 객체를 생성한 경우 `getPath()` 메서드에서 반환된 값도 상대 경로가 된다.
- {user.home} / baeldung 디렉토리에서 다음 코드를 호출한다고 가정하면 결과는 다음과 같이 될 것이다.

```java
File file = new File("foo/foo-one.txt");
String path = file.getPath();
```

```
foo/foo-one.txt  // on Unix systems
foo\foo-one.txt  // on Windows systems
```

※ 추상 경로 이름(abstract pathname)
- abstract pathname은 java.io.File 객체이고 경로명 문자열은 java.lang.String 객체이다.
- 둘 다 디스크의 동일한 파일을 참조한다.
- [Javadoc](https://docs.oracle.com/javase/7/docs/api/java/io/File.html) 에서는 java.io.File에 대해 다음과 같이 설명한다.
  - 파일 및 디렉토리 경로 이름의 추상 표현.
    - UI 및 운영 체제는 시스템 종속 경로 이름 문자열을 사용하여 파일 및 디렉토리의 이름을 지정한다.
    - 따라서, File 클래스는 계층적 경로 이름에 대한 추상적이고 시스템 독립적인 뷰를 제공한다.

## absolute path
- `getAbsolutePath()` 메서드는 현재 사용자 디렉터리의 경로를 확인한 후 파일의 경로 이름을 반환한다. 이를 '절대 경로명'이라고 한다.

```java
File file = new File("foo/foo-one.txt");
String path = file.getAbsolutePath();
```

```
/home/username/baeldung/foo/foo-one.txt     // on Unix systems
C:\Users\username\baeldung\foo\foo-one.txt  // on Windows systems
```

- 상대 경로에 대한 현재 디렉터리만 확인한다.
- 약식 표현(예: "." 및 "..")은 더 이상 해결되지 않는다.

```java
File file = new File("bar/baz/../bar-one.txt");
String path = file.getAbsolutePath();
```

```
/home/username/baeldung/bar/baz/../bar-one.txt      // on Unix systems
C:\Users\username\baeldung\bar\baz\..\bar-one.txt   // on Windows systems
```

## canonical path
> Canonical : 절대적인, 유일한

- `getCanonicalPath()` 메서드는 한 단계 더 나아가 절대 경로 이름뿐만 아니라 "", "..."와 같은 약어 또는 중복 이름을 확인한다.
- 또한 Unix 시스템에서 심볼릭 링크를 확인하고, Windows 시스템에서는 드라이브 문자를 표준 케이스로 변환한다.


```java
File file = new File("bar/baz/../bar-one.txt");
String path = file.getCanonicalPath();
```

```
/home/username/baeldung/bar/bar-one.txt     // on Unix systems
C:\Users\username\baeldung\bar\bar-one.txt  // on Windows systems
```

- 만약 현재 디렉토리가 ${user.home}/baeldung이고 `new File("bar/baz/.baz-one.txt")`이 생성된다면 `getCanonicalPath()`의 출력은 다음과 같다.

```
/home/username/baeldung/bar/baz/baz-one.txt     // on Unix systems
C:\Users\username\baeldung\bar\baz\baz-one.txt  // on Windows Systems
```

- 약어 표현을 사용할 수 있는 방법은 무궁무진하기 때문에 파일 시스템의 단일 파일은 무한히 많은 절대 경로를 가질 수 있다.
- 그러나 canonical path는 항상 고유하다.
- getCanonicalPath()는 파일 시스템 쿼리가 필요하기 때문에 IOException을 throw할 수 있다.
  - 예를 들어 Windows 시스템에서 잘못된 문자 중 하나를 사용하여 File 객체를 생성하는 경우 표준 경로를 확인하면 IOException이 발생한다.

### 사용 예시
- File 객체를 매개변수로 받아 fully qualified name을 데이터베이스에 저장하는 메소드를 작성한다고 가정해보자.
- 경로가 상대적인지 또는 약어가 포함되어 있는지 알 수 없는 경우, `getCanonicalPath()`를 사용할 수 있다.
  - 하지만, `getCanonicalPath()`는 파일 시스템을 읽기 때문에 성능이 저하된다.
- 따라서, 만약 중복된 이름이나 심볼릭 링크가 없고 드라이브 문자 대소문자가 표준화된 경우(Windows OS를 사용하는 경우) `getAbsoultePath()`를 사용하는 것이 좋다.


# java.io.File
---
> File 객체가 제공하는 기능은 다음과 같다.

- File 객체가 가리키는 것이 파일인 경우
  - 파일이 존재하는지 확인
  - 파일인지 경로인지 확인
  - 읽거나 쓰거나 실행할 수 있는지 확인
  - 언제 수정되었는지 확인
  - 파일 생성, 삭제, 이름 변경
  - 전체 경로 확인

- File 객체가 가리키는 것이 경로인 경우
  - 파일 목록 가져오기
  - 경로 생성, 삭제

- File 클래스의 다양한 생성자
  - child, pathname으로 되어 있는 값은 경로가 될 수도, 파일이 될 수도 있다.

|생성자|설명|
|----|----|
|`File(File parent, String child)`|이미 생성되어 있는 File 객체(parent)와 그 경로의 하위 경로 이름으로 <br> 새로운 File 객체 생성|
|`File(String pathname)`|지정한 경로 이름으로 File 객체를 생성|
|`File(String parent, String child)`|상위 경로(parent)와 하위 경로(child)로 File 객체를 생성|
|`File(URI uri)`|URI에 따른 File 객체를 생성|

- `File.separator`
  - 윈도우에서는 경로를 구할 때 역슬래시(또는 ₩ 기호를 사용한다), 유닉스 계열에서는 슬래시(/)를 사용한다.
  - 따라서 OS에 독립적인 코드를 짜기위해서는 해당 OS의 경로 구분 문자를 가져오는 `File.sperator`를 사용해야한다.

# java.nio.file(Path, Paths, Files)
---
> `java.nio.file` 패키지는 JVM이 파일, 파일 속성 및 파일 시스템에 접근하기 위한 인터페이스 및 클래스를 정의한다. <br>
> 이 API는 java.io.File 패키지의 한계를 극복하기 위해 사용될 수 있다. <br>
> 핵심은 Path이고 Paths, Files에서는 다양한 메서드를 제공하는 것 같다.

- Path
  - 파일 시스템에서 파일을 찾는 데 사용할 수 있는 개체입니다.
  - 일반적으로 시스템 종속 파일 경로를 나타냅니다.
  - 경로는 계층적 경로를 나타내며 특수 구분 기호 또는 구분 기호로 구분된 일련의 디렉토리 및 파일 이름 요소로 구성됩니다.
  - 파일 작업에 대한 보다 효율적이고 광범위한 접근을 위해 `Files` 클래스와 함께 사용할 수 있다.
  ```java
  public interface Path extends Comparable<Path>, Iterable<Path>, Watchable
  ```

- Paths
  - 이 클래스는 경로 문자열 또는 URI를 변환하여 Path를 반환하는 정적 메서드로만 구성된다.
    ```java
    public final class Paths {
        private Paths() { }
        ...
    }
    ```

- Files
  - 이 클래스는 파일, 디렉토리 또는 기타 유형의 파일에서 작동하는 정적 메소드로만 구성된다.
  - 대부분의 경우 여기에 정의된 메서드는 `FileSystemProvider`에게 파일 작업을 수행하도록 위임한다.
  ```java
  public final class Files {
      private Files() { }
      ...
  }
  ```

## java.nio.file.Path

- 자바7 부터 제공되는 NIO2의 일부이다.
  - I/O 작업을 위한 완전히 새로운 API를 제공한다.
  - java.io.File 클래스와 마찬가지로 `Path`는 파일 시스템에서 파일을 찾는 데 사용할 수 있는 객체도 생성한다.

- 마찬가지로 파일 클래스로 수행할 수 있는 모든 작업을 수행할 수 있습니다.
  - `Path path = Paths.get("baeldung/tutorial.txt");`
  - 기존의 File 클래스처럼 생성자를 사용하는 대신 정적 `java.nio.file.Paths.get()`을 사용하여 Path 인스턴스를 만든다.

<br>
'그럼 그냥 기존의 File을 사용하면 되는것 아닌가?' 라는 의문이 들 수 있다. 하지만 기존 File 클래스는 몇 가지 단점이 있다.

## java.io.File의 단점
### 1. 에러 처리
- File 클래스의 많은 메서드는 원하는 결과를 얻지 못하더라도 예외를 발생시키지 않는다. 따라서, 오류 메시지를 얻기가 어려웠다.
- 예를 들어, 파일을 삭제하는 다음과 같은 코드가 있다고 가정해보자.
  - 이 코드는 오류 없이 성공적으로 컴파일 및 실행된다. 물론 false 값을 포함하는 결과 플래그가 있지만 실패의 근본 원인을 알 수는 없다.

```java
File file = new File("baeldung/tutorial.txt");
boolean result = file.delete();
```

- 새로운 NIO2 API를 사용하여 동일한 기능을 다음과 같이 작성할 수 있다.
  - 이제 컴파일러는 `IOException`을 처리하도록 요구한다.
  - 또한, 예외는 실패에 대한 세부 정보를 가지고 있다.

```java
Path path = Paths.get("baeldung/tutorial.txt");
Files.delete(path);
```


### 2. 메타데이터 지원
- java.io.File 클래스는 파일에 대한 메타 정보가 필요한 I/O 작업에 대해 여러 플랫폼에서 일관되게 작동하지 않을 수 있다.
  - 메타데이터에는 권한, 파일 소유자 및 보안 속성 등이 포함될 수 있다.
  - 이로 인해 File 클래스는 심볼릭 링크를 전혀 지원하지 않으며, `rename()` 메서드는 여러 플랫폼에서 일관되게 작동하지 않는다.

※ 심볼릭 링크 : 절대 경로 또는 상대 경로의 형태로 된 다른 파일이나 경로에 대한 참조를 포함하고 있는 특별한 종류의 파일


### 3. 메서드 확장과 성능 Method Scaling and Performance
- 파일 클래스의 메소드는 확장되지 않는다.
  - 따라서, 대규모 디렉토리 목록 요청으로 인해 서버가 중단될 수 있다.
  - 또한 DoS(Denial of Service)로 이어질 수 있는 메모리 리소스 문제를 일으킬 수도 있다.
- File 클래스는 Path 클래스보다 객체 지향적이다.
  - 따라서, Path API 기반 I/O 스트림은 GC 관점에서 File 클래스보다 저렴하다.

## Mapping Functionality
NIO2 패키지는 위에서 살펴본 File 클래스의 단점에 대한 개선 사항을 포함하여 모든 레거시 기능을 제공한다. <br>
주로 `java.nio.file.Files` 클래스의 정적 메소드를 활용한다.

### 1. 파일과 경로 인스턴스 생성
```java
// java.io.File
File file = new File("baeldung", "tutorial.txt");

// java.nio.file
Path path = Paths.get("baeldung", "tutorial.txt");
Path path2 = Paths.get("baeldung").resolve("tutorial.txt");
```

```java
Path pathFromFile = file.toPath();
File fileFromPath = path.toFile();
```

### 2. 파일, 경로 맵핑
- 파일을 생성하려면 `createNewFile()` 및 `Files.createFile()` 메서드를 사용한다.
```java
boolean result = file.createNewFile();
Path newPath = Files.createFile(path);
```

- 디렉토리를 생성하려면 `mkdir()` 또는 `Files.createDirectory()`를 사용한다.
```java
boolean result = file.mkdir();
File newPath = Files.createDirectory(path);
```

- `mkdirs()` 및 `Files.createDirectories()` 메서드를 통해 존재하지 않는 모든 하위 디렉터리를 포함할 수 있다.
```java
boolean result = file.mkdirs();
File newPath = Files.createDirectories(path);
```

- 파일의 이름을 바꾸거나 이동하려면 다른 인스턴스 개체를 만들고 `renameTo()` 또는 `Files.move()`를 사용한다.
```java
boolean result = file.renameTo(new File("baeldung/tutorial2.txt"));
Path newPath = Files.move(path, Paths.get("baeldung/tutorial2.txt"));
```

- 삭제 작업을 수행하려면 `delete()` 또는 `Files.delete()`를 사용한다.
```java
boolean result = file.delete();
Files.delete(Paths.get(path));
```

### 3. 메타데이터 읽기  (Reading Metadata)
- 권한이나 유형과 같은 파일에 대한 기본 정보도 얻을 수 있다.

```java
// java.io API
boolean fileExists = file.exists();
boolean fileIsFile = file.isFile();
boolean fileIsDir = file.isDirectory();
boolean fileReadable = file.canRead();
boolean fileWritable = file.canWrite();
boolean fileExecutable = file.canExecute();
boolean fileHidden = file.isHidden();

// java.nio API
boolean pathExists = Files.exists(path);
boolean pathIsFile = Files.isRegularFile(path);
boolean pathIsDir = Files.isDirectory(path);
boolean pathReadable = Files.isReadable(path);
boolean pathWritable = Files.isWritable(path);
boolean pathExecutable = Files.isExecutable(path);
boolean pathHidden = Files.isHidden(path);
```

### 4. 경로 관련 메서드 (Pathname Methods)
```java
// java.io API
String absolutePathStr = file.getAbsolutePath();
String canonicalPathStr = file.getCanonicalPath();
```

```java
// java.nio API
Path absolutePath = path.toAbsolutePath();
Path canonicalPath = path.toRealPath().normalize();
```

```java
URI fileUri = file.toURI();
URI pathUri = path.toUri();
```

```java
// java.io API
String[] list = file.list();
File[] files = file.listFiles();

// java.nio API
DirectoryStream<Path> paths = Files.newDirectoryStream(path);
```






# 참고 자료
---
- 이상민, 『자바의 신 2』, 로드북(2017), 26장
- [https://www.javatpoint.com/java-path-vs-file](https://www.javatpoint.com/java-path-vs-file)
- [https://www.baeldung.com/java-path-vs-file](https://www.baeldung.com/java-path-vs-file)
- [https://docs.oracle.com/javase/7/docs/api/java/nio/file/Path.html](https://docs.oracle.com/javase/7/docs/api/java/nio/file/Path.html)
- [https://stackoverflow.com/questions/24611148/what-does-abstract-path-means-in-java-io](https://stackoverflow.com/questions/24611148/what-does-abstract-path-means-in-java-io)
