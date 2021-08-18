---
title: 화면 리디렉션시 쿠키 송신이 안되는 현상
date: 2021-05-28 00:29:00 +0900
categories: [개발 일기]
tags: [Cookie, Set-Cookie]
---

# 상황
---
- login.html 화면에서 로그인에 성공하면 쿠키에 logined=true 값을 세팅하고 index.html로 리디렉션 시킨다
![image](https://user-images.githubusercontent.com/64415489/126067313-5d0880e9-3a68-41ad-81bf-c2952b64eeec.png)

- 하지만, index.html 화면을 요청할 때, 기존에 세팅되었던 cookie값이 없어진다.
![image](https://user-images.githubusercontent.com/64415489/126067345-51dae0d2-5025-4c4e-8e52-984372f12152.png)

# 원인
---
- Set-Cookie 헤더의 속성 중 `Path`값을 따로 설정하지 않으면 쿠키를 응답한 화면이 포함된 디렉토리와 그 하위 디렉토리로 요청하는 경우에만 쿠키를 송신한다.
- 파일 디렉토리는 아래와 같기 때문에 Path를 따로 설정하지 않으면, login 화면이 포함된 /user 디렉토리와 그 하위에 있는 자원을 요청하는 경우에만 쿠키가 송신된다.
- 결과적으로, index 화면은 login 화면보다 상위 디렉토리에 존재하기 때문에 index 화면에 리디렉션시 쿠키가 송신되지 않았던 것이다.
```
├── ./index.html
├── ./js
│   ├── ./js/bootstrap.min.js
│   ├── ./js/jquery-2.2.0.min.js
│   └── ./js/scripts.js
├── ./qna
│   ├── ./qna/form.html
│   └── ./qna/show.html
└── ./user
    ├── ./user/form.html
    ├── ./user/list.html
    ├── ./user/login.html
    ├── ./user/login_failed.html
    └── ./user/profile.html
```

# 해결 방법
---
- Path 속성을 추가해준다.
```java
public String login(String id, String pw, HttpResponse response) throws IOException {
    User findUser = findUser(id);
    if(findUser!=null && pw.equals(findUser.getPassword())) {
        response.setCookie("logined=true; Path=/");
        return "/index.html";
    }

    response.setCookie("logined=false; Path=/");
    return "/user/login_failed.html";
}
```

![image](https://user-images.githubusercontent.com/64415489/126068394-179a31d0-5865-4872-abfc-e11ff8033ff8.png)

- 하지만, [이 글](https://secureteam.co.uk/articles/how-to-make-the-perfect-cookies/) 에 보면 여러 개의 애플리케이션이 웹 서버에 있는 경우, Path를 루트 디렉토리(/)로 세팅하는 것은
보안상 좋지 않다고 말한다. 왜냐하면 하위 디렉토리(ex : …/newapp)에 다른 애플리케이션이 있다면, 해당 애플리케이션에 요청하는 경우에도 쿠키가 송신되기 때문이다.

- 따라서, 여러 애플리케이션을 동일한 웹 서버에서 호스팅하는 시나리오에서는 가능한 개별 애플리케이션을 자체 하위 디렉토리("…/myapp1", "…/myapp2" 등)에 배치하고
개별 쿠키를 개별 애플리케이션 경로에만 유효하도록 선언하는 것이 좋다.


## Set-Cookie 필드 속성 값 살펴보기
---

|  속성          |   설명         |
|---------------|---------------|
|name = VALUE    | 쿠키에 부여된 이름과 값(필수) |
|Expires = DATE | 쿠키의 유효 기간(default : 브라우저 닫을 때까지) |
|Path = PATH   | 쿠키 적용이 되는 서버 상의 디렉토리(default : 쿠키를 생성한 도큐먼트와 같은 디렉토리) |
|Domain = 도메인 명| 쿠키 적용 대상이 되는 도메인 명(default : 쿠키를 생성한 서버의 도메인) |
|Secure| HTTPS로 통신하는 경우에만 쿠키 송신|
|HttpOnly| 쿠키를 자바스크립트에서 엑세스하지 못하도록 제한 |


# 참고 자료
---
- 우에노 센, 『그림으로 배우는 Http & Network Basic』, 영진닷컴(2015)
- [https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Set-Cookie](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Set-Cookie)
- [https://secureteam.co.uk/articles/how-to-make-the-perfect-cookies/](https://secureteam.co.uk/articles/how-to-make-the-perfect-cookies/)
