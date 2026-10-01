---
title: jar 패키징시 resource 디렉토리에 있는 파일 읽기
date: 2021-09-07 22:25:00 +0900
---

# 상황
---
자바 `Socket`을 활용해 간단한 웹 서버를 구현하는 프로젝트를 진행했다. 요구사항 중 하나가 `jar`로 패키징하여 실행하는 것이었는데, 정적 파일들(`.html`)은 함께 패키징
되지 않아 생성된 `.jar` 파일을 실행시켜 브라우저로 테스트시 제대로된 화면이 출력되지 않았다. 프로젝트 구조는 다음과 같았다.

```
.
├── README.md
├── pom.xml
├── src
│ ├── main
│ │ ├── java
│ │ └── resources
│ └── test
│     └── java
└── webapp
```

정적 파일들은 `webapp` 디렉토리 하위에 있는데, `webapp`의 경우 `src` 하위에 있지 않으므로 패키징되지 않는다 (??)


[나랑 비슷한 케이스](https://stackoverflow.com/questions/48504303/getting-resources-outside-of-src-folder-in-a-jar-file)

해결방법 ??

```
Use maven resource plugin, The resources plugin copies files from input resource directories to an output directory.

<plugin>
    <artifactId>maven-resources-plugin</artifactId>
    <version>3.0.2</version>
    <configuration>
        ...
    </configuration>
</plugin>
Assume we want to copy resource files from the directory input-resources to the directory output-resources and we want to exclude all files ending with the extension .png.

just like excludes you can include files using

These requirements are satisfied with this configuration:


<configuration>
    <outputDirectory>output-resources</outputDirectory>
    <resources>
        <resource>
            <directory>input-resources</directory>
            <excludes>
                <exclude>*.png</exclude>
            </excludes>
            <filtering>true</filtering>
        </resource>
    </resources>
</configuration>
```

## What is JAR?
JAR stands for Java ARchive. It's a file format based on the popular ZIP file format and is used for aggregating many files into one. Although JAR can be used as a general archiving tool, the primary motivation for its development was so that Java applets and their requisite components (.class files, images and sounds) can be downloaded to a browser in a single HTTP transaction, rather than opening a new connection for each piece. This greatly improves the speed with which an applet can be loaded onto a web page and begin functioning. The JAR format also supports compression, which reduces the size of the file and improves download time still further. Additionally, individual entries in a JAR file may be digitally signed by the applet author to authenticate their origin.

JAR is:

the only archive format that is cross-platform
the only format that handles audio and image files as well as class files
backward-compatible with existing applet code
an open standard, fully extendable, and written in java
the preferred way to bundle the pieces of a java applet
JAR consists of a zip archive, as defined by PKWARE, containing a manifest file and potentially signature files, as defined in the JAR File Specification.

https://docs.oracle.com/javase/8/docs/technotes/guides/jar/jarGuide.html

## jar 패키징
A JAR (Java Archive) is a package file format typically used to aggregate many Java class files and associated metadata and resources (text, images, etc.) into one file to distribute application software or libraries on the Java platform.
In simple words, a JAR file is a file that contains a compressed version of .class files, audio files, image files, or directories. We can imagine a .jar file as a zipped file(.zip) that is created by using WinZip software. Even, WinZip software can be used to extract the contents of a .jar . So you can use them for tasks such as lossless data compression, archiving, decompression, and archive unpacking.

https://www.geeksforgeeks.org/jar-files-java/

The basic format of the command for creating a JAR file is:

`jar cf jar-file input-file(s)`

The options and arguments used in this command are:

The c option indicates that you want to create a JAR file.
The f option indicates that you want the output to go to a file rather than to stdout.
jar-file is the name that you want the resulting JAR file to have. You can use any filename for a JAR file. By convention, JAR filenames are given a .jar extension, though this is not required.
The input-file(s) argument is a space-separated list of one or more files that you want to include in your JAR file. The input-file(s) argument can contain the wildcard * symbol. If any of the "input-files" are directories, the contents of those directories are added to the JAR archive recursively.
The c and f options can appear in either order, but there must not be any space between them.

This command will generate a compressed JAR file and place it in the current directory. The command will also generate a default manifest file for the JAR archive.

https://docs.oracle.com/javase/tutorial/deployment/jar/build.html


## jar 하면 resource 아래 있는 경로 달라짐

### resource 폴더 의미 ??

What is the src/main/resources folder for in Java project
Every Java project contains a folder named resources, different type of projects have different paths, in a standard Maven project structure, the path is src/main/resources, Gradle projects inherit that layout. The path is the default value defined in Super POM. It looks like this:


<project>
...
<build>
...
<resources>
  <resource>
    <directory>src/main/resources</directory>
 </resource>
</resources>
...
</build>
</project>

By default the process-resources phase will copy the files from ${basedir}/src/main/resources to ${basedir}/target/classes or the directory defined in ${project.build.outputDirectory}.

Many people confused about this folder and don't know where it is or what kind of files should be stored in this folder. The most important thing is the concept of resource is an abstraction, not a concrete path or folder structure. It gives all code in the project an uniform view of a place that stores non Java artifact files.

What the resources folder contains?
The resources folder is the default place where many Java libraries store their configuration files, usually XML based, for example the logging library Logback stores logback.xml in this folder by default. Sometimes the configuration is in the format of property files. It can also stores static files like image, .mp3, etc. If it's Web application, this folder also keeps CSS, Javascript, images for logo, button or background.

http://makble.com/what-is-the-srcmainresources-folder-for-in-java-project

Why resources directory ?

Before maven exists we used to have resources package within application,which will actually contain some application configuration properties file,Internalization property files , XML files (basically non java files which are required for application run-time ).

https://stackoverflow.com/questions/25786185/what-is-the-purpose-for-the-resource-folder-in-maven

https://homoefficio.github.io/2020/07/21/IDE-%EC%97%90%EC%84%9C%EB%8A%94-%EB%90%98%EB%8A%94%EB%8D%B0-jar-%EC%97%90%EC%84%9C%EB%8A%94-%EC%95%88-%EB%8F%BC%EC%9A%94-Java-Resource/


main/resource 안에 있는 파일 읽어오려면 소스상에서 절대경로로 하면 안되고
`JavaClassName.class.getClassLoader().getResourceAsStream("file.txt");` 이런식으로해야함



payco 과제할 때 겪었던거



- 변경된 구조 (jar시에도 동작하게)
```
.
├── README.md
├── pom.xml
└── src
  ├── main
  │ ├── java
  │ └── resources
  │     ├── logback.xml
  │     ├── server-config.json
  │     └── webapp
  └── test
     └── java
```



## 코드 변경

### Before
```java
    File requestFile = new File(hostConfig.getRootDir(), fileName);
    boolean hasServlet = Optional.ofNullable(ServletMapper.getMatchedServlet(fileName)).isPresent();

    if (!requestFile.exists() && !hasServlet) {
        throw new FileNotFoundException(fileName);
    }

    String contentType = URLConnection.getFileNameMap().getContentTypeFor(fileName);

    if (requestFile.exists()) {
        byte[] theData = Files.readAllBytes(requestFile.toPath());
    }
    ...
```

### After
```java
    boolean hasRequestFile = IOUtils.isExistFile(hostConfig.getRootDir()+fileName);
    boolean hasServlet = Optional.ofNullable(ServletMapper.getMatchedServlet(fileName)).isPresent();

    if (!hasRequestFile && !hasServlet) {
        throw new FileNotFoundException(fileName);
    }

    String contentType = URLConnection.getFileNameMap().getContentTypeFor(fileName);

    if (hasRequestFile) {
        byte[] theData = IOUtils.getFileByteData(hostConfig.getRootDir()+fileName);
        sendNormalResponseToClient(httpResp, "200 OK", theData, contentType);
    }
    ...
```


# resource에 있는 파일 jar로 만들었을 때도 정상적으로 동작하게 하려면 ??
If it's already in the classpath, then just obtain it from the classpath instead of from the disk file system. Don't fiddle with relative paths in java.io.File. They are dependent on the current working directory over which you have totally no control from inside the Java code.

Assuming that ListStopWords.txt is in the same package as your FileLoader class, then do:

URL url = getClass().getResource("ListStopWords.txt");
File file = new File(url.getPath());
Or if all you're ultimately after is actually an InputStream of it:

InputStream input = getClass().getResourceAsStream("ListStopWords.txt");


https://stackoverflow.com/questions/3844307/how-to-read-file-from-relative-path-in-java-project-java-io-file-cannot-find-th
