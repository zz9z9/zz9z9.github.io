---
title: WEB - HTTP Content-Disposition 헤더
date: 2025-08-05 21:25:00 +0900
categories: [지식 더하기, 이론]
tags: [WEB]
---

## Content-Disposition 헤더
> 콘텐츠를 브라우저에서 웹페이지로 직접 표시할지, 아니면 첨부파일로 다운로드할지를 지정

```
Content-Disposition: inline
Content-Disposition: attachment
Content-Disposition: attachment; filename="file name.jpg"
Content-Disposition: attachment; filename*=UTF-8''file%20name.jpg
```

**특징**
- `inline`이면 웹페이지로 보여지고 `attachment`이면 다운로드 창이 뜸
- Content-Disposition 헤더는 이메일용 MIME 메시지에서 정의된 것이지만, HTTP에서는 일부 파라미터만 사용 (`form-data`, `name`, `filename`)
- 파일명 주변의 따옴표는 선택 사항이지만, 공백 등의 특수문자가 있을 경우 필수
- `filename*`은 RFC 5987로 인코딩됨 (공백은 %20, 한글은 UTF-8로 percent-encode)
- 브라우저는 `/` 또는 `\` 같은 경로 구분자를 `_`로 바꾸는 등의 변환을 수행할 수 있음
- Chrome 및 Firefox 82 이상에서는 `<a download>` 속성이 `Content-Disposition: inline`보다 우선시됨 (같은 출처의 URL에 한함)

<br>
**※ percent 인코딩 ?**
- 일반적으로 HTTP 헤더나 URL에는 다음과 같은 제약이 존재:
  - 공백이나 특수문자는 문제가 될 수 있음 (HTTP 파서 오류, 잘못된 URL 인식 등)
  - ASCII 이외의 문자 (예: 한글, 일본어 등)는 깨질 수 있음
- 따라서, URL이나 HTTP 헤더에서 특수 문자, 공백, 비ASCII 문자(예: 한글) 등을 안전하게 전송하기 위해 사용하는 인코딩 방식으로 percent 인코딩(URL 인코딩)이 사용됨

- 예시 : 문자들을 `% + ASCII 코드의 16진수` 값으로 변경

| 원래 문자       | Percent 인코딩   |
| ----------- | ------------- |
| 공백 (space)  | `%20`         |
| `"` (큰따옴표)  | `%22`         |
| 한글 `가`      | `%EA%B0%80`   |
| `파일 이름.png` | `파일%20이름.png` |

- filename에서 percent 인코딩이 문제되는 이유
  - 브라우저별로 처리방식이 다를 수 있음 (아래 예시 기준):
    - `%20`을 공백으로 잘 디코딩함
    - 디코딩 안 함 → 그대로 `file%20name.png` 저장됨
    - 오류 발생하거나 파일명이 깨짐

```
Content-Disposition: attachment; filename="파일 이름.png"
Content-Disposition: attachment; filename="file%20name.png"
```

- `filename*`은 RFC 5987에 따라 UTF-8 + percent 인코딩을 정식으로 허용
- 예시 : `filename*` → 인코딩된 진짜 이름, `filename` → fallback용 ASCII 이름 (구형 브라우저 대응)
```
Content-Disposition: attachment; filename="fallback.png"; filename*=UTF-8''파일%20이름.png
```


**multipart/form-data**
- multipart/form-data 본문에서는 각 필드에 대한 정보를 제공하기 위해 Content-Disposition 헤더가 필수
- 첫 번째 지시자는 항상 `form-data`
  - 추가 지시자는 대소문자를 구분하지 않으며, `=` 다음에 따옴표로 감싼 값을 가지게됨
- 각 서브 파트는 Content-Type 헤더에 정의된 boundary로 구분
- 예시 : field1은 일반 텍스트 field2는 파일 업로드

```
# 헤더
Content-Type: multipart/form-data; boundary=----WebKitFormBoundary7MA4YWxkTrZu0gW

# 본문
------WebKitFormBoundary7MA4YWxkTrZu0gW
Content-Disposition: form-data; name="field1"

value1
------WebKitFormBoundary7MA4YWxkTrZu0gW
Content-Disposition: form-data; name="field2"; filename="example.txt"
Content-Type: text/plain

value2
------WebKitFormBoundary7MA4YWxkTrZu0gW--
```

## 실제 코드 예시
> [https://start.spring.io/](https://start.spring.io/) 에서 `GENERATE` 버튼 눌렀을 때 파일 다운로드 처리를 담당하는 코드 ([코드 출처](https://github.com/spring-io/initializr/blob/main/initializr-web/src/main/java/io/spring/initializr/web/controller/ProjectGenerationController.java))

```java
// ProjectGenerationController.java

@RequestMapping(path = "/starter.zip", method = { RequestMethod.GET, RequestMethod.POST })
public ResponseEntity<byte[]> springZip(R request) throws IOException {
  ProjectGenerationResult result = this.projectGenerationInvoker.invokeProjectStructureGeneration(request);
  Path archive = createArchive(result, "zip", ZipArchiveOutputStream::new, ZipArchiveEntry::new,
    ZipArchiveEntry::setUnixMode);
  return upload(archive, result.getRootDirectory(),
    generateFileName(result.getProjectDescription().getArtifactId(), "zip"), "application/zip");
}

private ResponseEntity<byte[]> upload(Path archive, Path dir, String fileName, String contentType)
		throws IOException {
	byte[] bytes = Files.readAllBytes(archive);
	logger.info(String.format("Uploading: %s (%s bytes)", archive, bytes.length));
	ResponseEntity<byte[]> result = createResponseEntity(bytes, contentType, fileName);
	this.projectGenerationInvoker.cleanTempFiles(dir);
	return result;
}

private ResponseEntity<byte[]> createResponseEntity(byte[] content, String contentType, String fileName) {
	String contentDispositionValue = "attachment; filename=\"" + fileName + "\"";
	return ResponseEntity.ok()
		.header("Content-Type", contentType)
		.header("Content-Disposition", contentDispositionValue)
		.body(content);
}
```

## 참고 자료
- [https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Disposition](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Disposition)
