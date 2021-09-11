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


# java.io.File
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

# 경로

## getPath()
Simply put, getPath() returns the String representation of the file's abstract pathname. This is essentially the pathname passed to the File constructor.

So, if the File object was created using a relative path, the returned value from getPath() method would also be a relative path.

If we invoke the following code from the {user.home}/baeldung directory:

File file = new File("foo/foo-one.txt");
String path = file.getPath();
The path variable would have the value:

foo/foo-one.txt  // on Unix systems
foo\foo-one.txt  // on Windows systems
Notice that for the Windows system, the name-separator character has changed from the forward slash(/) character, which was passed to the constructor, to the backslash (\) character. This is because the returned String always uses the platform's default name-separator character.



- An abstract pathname is a java.io.File object and a pathname string is a java.lang.String object. Both reference the same file on the disk.

  How do I know?

  The first sentence of the Javadoc of java.io.File explains:

  An abstract representation of file and directory pathnames.

  It goes on to explain why:

  User interfaces and operating systems use system-dependent pathname strings to name files and directories. This class presents an abstract, system-independent view of hierarchical pathnames.


- The abstract pathname is just the string form of the file/location held in the File object.

If you check the javadoc of File#toString():

Returns the pathname string of this abstract pathname. This is just the string returned by the getPath() method.

## absolute path
- The getAbsolutePath() method returns the pathname of the file after resolving the path for the current user directory — this is called an absolute pathname.
- So, for our previous example, file.getAbsolutePath() would return:
```
/home/username/baeldung/foo/foo-one.txt     // on Unix systems
C:\Users\username\baeldung\foo\foo-one.txt  // on Windows systems
```

- This method only resolves the current directory for a relative path.
- Shorthand representations (such as “.” and “..”) are not resolved further.
- Hence when we execute the following code from the directory {user.home}/baeldung:

```
File file = new File("bar/baz/../bar-one.txt");
String path = file.getAbsolutePath();
```

```
/home/username/baeldung/bar/baz/../bar-one.txt      // on Unix systems
C:\Users\username\baeldung\bar\baz\..\bar-one.txt   // on Windows systems
```

## canonical path

* Canonical : 절대적인, 유일한


## 절대경로와 상대경로
C:\dir\a 라는 경로에서 C:\dir\b 디렉토리에 접근하려면
- absolute : C:\dir\a\..\b
- canonical : C:\dir\b
- 즉 canonical은 절대적으로 유일하게 표현할 수 있는 경로를 뜻한다.

``

Absolute path, Canonical Path

* Canonical : 절대적인, 유일한





# 참고 자료
---
- 이상민, 『자바의 신 2』, 로드북(2017), 26장
- [https://www.javatpoint.com/java-path-vs-file](https://www.javatpoint.com/java-path-vs-file)
- [https://www.baeldung.com/java-path-vs-file](https://www.baeldung.com/java-path-vs-file)
- [https://docs.oracle.com/javase/7/docs/api/java/nio/file/Path.html](https://docs.oracle.com/javase/7/docs/api/java/nio/file/Path.html)
- [https://stackoverflow.com/questions/24611148/what-does-abstract-path-means-in-java-io](https://stackoverflow.com/questions/24611148/what-does-abstract-path-means-in-java-io)
