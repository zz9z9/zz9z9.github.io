---
title: maven-default-http-blocker ... Blocked mirror for repositories 에러
date: 2021-12-08 23:00:00 +0900
categories: [경험하기, 이슈 노트]
tags: [Maven, HTTP Block]
---

# 상황
---
회사에서 지급받은 임시 PC를 2주 정도 사용하고, 앞으로 계속 사용하게될 새로운 PC를 지급받아 개발 환경을 다시 세팅하고 있었다.
하지만, 세팅하는 프로젝트에서 의존성을 제대로 다운로드 받지 못하고 다음과 같은 에러 메시지를 출력했다. <br>
`Could not transfer artifact ... from/to maven-default-http-blocker (http://0.0.0.0/): Blocked mirror for repositories`

# 원인
---
> Maven 3.8.1 버전부터 repository에 대한 HTTP 요청이 차단되고 HTTPS만 허용된다. ([3.8.1 버전 릴리즈 노트](https://maven.apache.org/docs/3.8.1/release-notes.html) 참고)

## 하지만, 나는 메이븐 3.8.1 버전을 따로 설치한 적이 없는데 ... ?
> IntelliJ를 설치할 때 메이븐은 플러그인으로 함께 설치된다.

- [IntelliJ 다운로드 페이지](https://www.jetbrains.com/ko-kr/idea/download/#section=mac)에 가보면 아래와 같이 기본적으로 설치되는 플러그인들을 살펴볼 수 있다.
<img src = "https://user-images.githubusercontent.com/64415489/145251895-dd88e334-71d2-4e3a-bfd5-31bb3f16647f.png" width ="70%" />

![image](https://user-images.githubusercontent.com/64415489/145235968-9a1deb3a-26b5-41d8-8e2e-76f72f7473ca.png)

- 이전 PC와 새로운 PC 모두 `IntelliJ IDEA 2021.3` 버전인데, 이전 PC의 경우 함께 설치된 메이븐 버전은 3.6.3이었다.

## 3.6.3 버전과 3.8.1 버전의 settings.xml 비교해보기
> IntelliJ 설치시 함께 세팅되는 메이븐의 `settings.xml` 파일 경로는 다음과 같다. <br>
> MacOS : `/Applications/IntelliJ IDEA.app/Contents/plugins/maven/lib/maven3/conf/settings.xml` <br>
> Windows : `IntelliJ 설치 경로\plugins\maven\lib\maven3\conf\settings.xml`

- **3.6.3 버전**
![image](https://user-images.githubusercontent.com/64415489/145234890-c3216eba-f81e-4f8c-9bb4-7bc6feb9de0f.png)

- **3.8.1 버전** (`<mirror>` 속성이 추가된걸 볼 수 있다)
![image](https://user-images.githubusercontent.com/64415489/145235213-045d8c45-7008-4112-ab66-568a6769b5f4.png)


## \<mirror>란 ?
> 범용적으로 쓰이는 '미러'에 대한 [위키 설명](https://en.wikipedia.org/wiki/Mirror_site)을 보면 <q>**미러 사이트는 다른 인터넷 사이트의 복사본이다.**</q> 라고 나와있다.
>`settings.xml`에 있는 `<mirror>`도 이러한 개념으로 이해하면 될 것 같다.
> 즉, `pom.xml`에 정의된 의존성들을 내려받기 위해 특정 repository로 요청시, 해당 repository 대신 요청받을 mirror repository를 정의하는 것이다.

- `<mirrorOf>`에 정의된 repository(central)로 요청하면 `<url>`에 정의된 repository로 요청이 가게된다.
  - central이 어디에 정의되어 있는지는 [해당 문서](https://maven.apache.org/guides/introduction/introduction-to-the-pom.html)의 Super POM 참조.

```xml
<settings>
  ...
  <mirrors>
    <mirror>
      <id>other-mirror</id>
      <name>Other Mirror Repository</name>
      <url>https://other-mirror.repo.other-company.com/maven2</url>
      <mirrorOf>central</mirrorOf>
    </mirror>
  </mirrors>
  ...
</settings>
```

- [공식 문서](https://maven.apache.org/guides/mini/guide-mirror-settings.html)에서는 mirror를 사용하는 경우에 대해 다음과 같이 설명한다.
  - 지리적으로 더 가깝고 더 빠른 동기화된 미러가 인터넷에 있을 때
  - 특정 리포지토리를 자체 내부 리포지토리로 바꾸려고 할 때
  - 리포지토리 관리자를 실행하여 미러에 로컬 캐시를 제공하고 미러의 URL을 대신 사용할 때

- `<mirrorOf>`에 다음과 같이 세팅할 수 있다.
  - `*` = 모든 레파지토리
  - `external:*` = localhost나 파일 기반 이외의 레파지토리
    - 위에서 본 settings.xml에서 알 수 있듯, 3.8.1부터 `external:http:*`가 적용됐다.
    - 즉, `external:http:*`는 localhost를 사용하는 리포지토리를 제외한 HTTP를 사용하는 모든 리포지토리를 의미한다.
      - 여기에 `<blocked>true</blocked>`와 같은 속성이 더해져 HTTP 요청을 차단한다.
      - **맨 처음에 언급했던, Maven 3.8.1 버전부터 HTTP 요청이 차단되는 이유이다.**
  - `repo,repo1` = repo, repo1 (여러 레파지토리 정의시)
  - `*,!repo1` = repo1을 제외한 모든 레파지토리


# 해결 방법
---
> [공식 문서](https://maven.apache.org/docs/3.8.1/release-notes.html)에 보면 다음과 같은 해결책을 제시한다.
> - upgrade the dependency version to a newer version that replaced the obsolete HTTP repository URL with a HTTPS one
> - keep the dependency version but define a mirror in your settings.

두 방법에 대해 알아보고 정확히 이해하기에는 시간이 걸릴 것 같아 일단 3.6.3 버전을 설치하여 사용하는 방식을 선택했다.

## Maven 3.6.3 버전 적용
> 깔끔하게 모든 의존성이 다운로드 되었다.

![image](https://user-images.githubusercontent.com/64415489/145257020-203a235f-a283-48d9-a7aa-35fdc799842f.png)


# 참고 자료
---
- [https://stackoverflow.com/questions/36757902/what-is-mirror-in-maven-settings-xml-file](https://stackoverflow.com/questions/36757902/what-is-mirror-in-maven-settings-xml-file)
- [https://maven.apache.org/guides/mini/guide-multiple-repositories.html](https://maven.apache.org/guides/mini/guide-multiple-repositories.html)
- [https://maven.apache.org/guides/mini/guide-mirror-settings.html](https://maven.apache.org/guides/mini/guide-mirror-settings.html)
