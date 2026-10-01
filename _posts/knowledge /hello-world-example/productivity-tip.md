
## Devtools

The spring-boot-devtools module also includes support for quick application restarts. See the Hot Swapping section in “How-to Guides” for details.
https://docs.spring.io/spring-boot/reference/using/running-your-application.html
https://docs.spring.io/spring-boot/how-to/hotswapping.html


Gradle과 비교

✅ 5) Spring Boot Devtools 자동 빌드 활성화 (선택)

지금 글에서 Devtools는 언급 안했는데
초기 세팅 문서라면 다룰 만함.

Devtools 자동 재시작 활성화
Settings → Build Tools → Gradle → Build and run using: IntelliJ
Compiler → Build project automatically 체크
Advanced Settings → Allow auto-make 체크


Spring Boot 개발 체감 속도 확 올라감.

(단, 팀에서 Gradle 빌드를 강제하는 경우 제외)'

✅ 3) Gradle 빌드 속도 개선 — 로컬 캐시, 병렬 빌드

초기 세팅에서 넣어두면 가성비가 매우 좋음.

org.gradle.parallel=true
org.gradle.caching=true
org.gradle.daemon=true


빌드 속도 20~50% 개선됨.

문서에 넣어도 부담 없고 실용적.

✅ 4) .gitignore + .gitattributes 설정

Git 프로젝트라면 거의 기본적으로 세팅해야 하는데
초기 세팅에서 언급해두면 좋아.

특히 .gitattributes는 라인 엔딩 문제 방지에 매우 중요:

* text=auto eol=lf


macOS/Linux → LF

Windows → CRLF 자동 변환 문제 해결
