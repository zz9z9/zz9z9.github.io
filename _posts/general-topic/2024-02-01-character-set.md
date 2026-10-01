---
title: 컴퓨터에서 문자열 저장
date: 2024-02-01 20:00:00 +0900
---

## 의문 현상
- `PAYCOMRC03`, `PAYCOMRC04` 모두 저장된 리눅스 서버에서 `file -bi 파일명`으로 확인해보면 `text/plain; charset=iso-8859-1`

| 파일 | in 윈도우 (인코딩 타입 : UTF-8?)  | in 리눅스 (인코딩 타입 : ISO-8859-1 ?) |
| --- |---------------------------|--------------------------------|
| PAYCOMRC03 | 한글로 된 컨텐츠 기준으로 파일 스펙에 안맞음 | 깨지는 타입으로 파일 스펙에 맞음             |
| PAYCOMRC04 | 한글로 된 컨텐츠 기준으로 파일 스펙에 맞음  | 깨지는 타입으로 파일 스펙에 안맞음            |


## 알아보기

- The correct approach is what you just described. The only potential issue is that the encoding being used might be the platform's default, which varies between systems and may not support all characters in the string.

To avoid any character representation issues, it is recommended to employ a specific encoding like UTF-8 that can encompass all characters.


## Single Byte Encoding (ASCII)

## Multi Byte Encoding



## 참고 자료

- https://docs.oracle.com/javase/8/docs/api/java/nio/charset/Charset.html
- https://www.baeldung.com/java-char-encoding
