---
title: Apache httpd.conf 파일 속성 공부하기(2) (feat. Tomcat 연동)
date: 2022-02-15 13:25:00 +0900
categories: [Infra]
tags: [apache, httpd]
---

# 들어가기 전
---
1편에서 여러가지 태그와 속성을 살펴봤다.
아파치와 톰캣을 연동하기 위한 속성을 살펴보고자 한다.

https://stackoverflow.com/questions/1081918/apache-to-tomcat-mod-jk-vs-mod-proxy

https://tomcat.apache.org/connectors-doc/reference/apache.html

https://tomcat.apache.org/connectors-doc/webserver_howto/apache.html
-> 속성들 적기

## ProxyPass
> Maps remote servers into the local server URL-space

외부에서 들어온 www.domin.com/blog/posts/1 요청을
127.0.0.1:8080/posts/1로 변환시켜주는 기능이다

Additional ProxyPass Keywords

Normally, mod_proxy will canonicalise ProxyPassed URLs. But this may be incompatible with some backends, particularly those that make use of PATH_INFO. The optional `nocanon` keyword suppresses this and passes the URL path "raw" to the backend. Note that this keyword may affect the security of your backend, as it removes the normal limited protection against URL-based attacks provided by the proxy.

### ProxyPassReverse
내부에서 리다이렉트가 일어났을시 생성되는 URL의 도메인이 127.0.0.1:8080/이
되버리기 때문에 이를 다시 www.domain.com/으로 변환해주는 기능이다.

Syntax:	ProxyPassReverse [path] url [interpolate]

This directive lets Apache httpd adjust the URL in the Location, Content-Location and URI headers on HTTP redirect responses. This is essential when Apache httpd is used as a reverse proxy (or gateway) to avoid bypassing the reverse proxy because of HTTP redirects on the backend servers which stay behind the reverse proxy.

Only the HTTP response headers specifically mentioned above will be rewritten. Apache httpd will not rewrite other response headers, nor will it by default rewrite URL references inside HTML pages. This means that if the proxied content contains absolute URL references, they will bypass the proxy. To rewrite HTML content to match the proxy, you must load and enable mod_proxy_html.

ex)
```
ProxyPass         "/mirror/foo/" "http://backend.example.com/"
ProxyPassReverse  "/mirror/foo/" "http://backend.example.com/"
ProxyPassReverseCookieDomain  "backend.example.com"  "public.example.com"
ProxyPassReverseCookiePath  "/"  "/mirror/foo/"
```

For example, suppose the local server has address http://example.com/; then
will not only cause a local request for the http://example.com/mirror/foo/bar to be internally converted into a proxy request to http://backend.example.com/bar (the functionality which ProxyPass provides here). It also takes care of redirects which the server backend.example.com sends when redirecting http://backend.example.com/bar to http://backend.example.com/quux . Apache httpd adjusts this to http://example.com/mirror/foo/quux before forwarding the HTTP redirect response to the client. Note that the hostname used for constructing the URL is chosen in respect to the setting of the UseCanonicalName directive.


### ProxyPreserveHost
> HTTP 요청 헤더의 Host: 부분을 유지하는 옵션이다.

Use incoming Host HTTP request header for proxy request

### ProxyRequests
> 포워드 프록시 서버로 사용(On)할지, 리버스 프록시 서버로 사용(Off)할지 결정

Default:	ProxyRequests Off

This allows or prevents Apache httpd from functioning as a forward proxy server. (Setting ProxyRequests to Off does not disable use of the ProxyPass directive.)

In a typical reverse proxy or gateway configuration, this option should be set to Off.

In order to get the functionality of proxying HTTP or FTP sites, you need also mod_proxy_http or mod_proxy_ftp (or both) present in the server.

In order to get the functionality of (forward) proxying HTTPS sites, you need mod_proxy_connect enabled in the server.

## < Proxy >
> Container for directives applied to proxied resources

- Syntax: `<Proxy wildcard-url> ...</Proxy>`
- Directives placed in `<Proxy>` sections apply only to matching proxied content. Shell-style wildcards are allowed.

- For example, the following will allow only hosts in yournetwork.example.com to access content via your proxy server:
```
<Proxy "*">
  Require host yournetwork.example.com
</Proxy>
```

- The following example will process all files in the foo directory of `example.com` through the `INCLUDES` filter when they are sent through the proxy server:
```
<Proxy "http://example.com/foo/*">
  SetOutputFilter INCLUDES
</Proxy>
```

- For example, the following will allow only hosts in yournetwork.example.com to access content via your proxy server:
```
<Proxy "http://example.com/foo/*">
  SetOutputFilter INCLUDES
</Proxy>
```
- Differences from the Location configuration section
A backend URL matches the configuration section if it begins with the the wildcard-url string, even if the last path segment in the directive only matches a prefix of the backend URL. For example, <Proxy "http://example.com/foo"> matches all of http://example.com/foo, http://example.com/foo/bar, and http://example.com/foobar. The matching of the final URL differs from the behavior of the <Location> section, which for purposes of this note treats the final path component as if it ended in a slash.


## BalancerMember
> Add a member to a load balancing group

- Syntax:	`BalancerMember [balancerurl] url [key=value [key=value ...]]`

- This directive adds a member to a load balancing group. It can be used within a `<Proxy balancer://...>` container directive and can take any of the key value pair parameters available to ProxyPass directives.

## JkAutoAlias
> Automatically Alias webapp context directories into the Apache document space.

Care should be taken to ensure that only static content is served via Apache as a result of using this directive. Any static content served by Apache will bypass any security constraints defined in the application's web.xml.

## JkMount

> A mount point from a context to a Tomcat worker.

This directive is allowed multiple times. It is allowed in the global configuration and in VirtualHost.
You can also use it inside Location with a different syntax. Inside Location, one omits the first argument (path), which gets inherited verbatim from the Location argument. Whereas <Location /myapp> matches any URI beginning with "/myapp", any JkMount nested in such a Location block will only match for requests with exact URI /myapp. Therefore nesting JkMount in Location is typically not the right thing to do.
By default JkMount entries are not inherited from the global server to other VirtualHosts or between VirtualHosts.


## workers.properties
> Tomcat workers are defined in a properties file dubbed `workers.properties`



# 참고 자료
- [https://whatis.techtarget.com/definition/Hypertext-Transfer-Protocol-daemon-HTTPD](https://whatis.techtarget.com/definition/Hypertext-Transfer-Protocol-daemon-HTTPD)
- https://httpd.apache.org/docs/2.4/en/mod/directives.html
- https://velog.io/@always0ne/Proxy-Pass%EB%A5%BC-%EC%82%AC%EC%9A%A9%ED%95%98%EC%97%AC-Apache-Web-Server%EC%97%90-WAS-%EC%97%B0%EB%8F%99%ED%95%98%EA%B8%B0
- https://tomcat.apache.org/connectors-doc/reference/apache.html
- https://tomcat.apache.org/connectors-doc/reference/workers.html
- 로드밸런싱 : https://tomcat.apache.org/connectors-doc/common_howto/loadbalancers.html
- [https://pediaa.com/difference-between-host-and-server/](https://pediaa.com/difference-between-host-and-server/)
