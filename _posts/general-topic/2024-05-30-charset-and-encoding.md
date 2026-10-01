---
title: Character-Set과 Encoding
date: 2024-05-30 22:00:00 +0900
---

# Charset VS Encoding
- Before the invention of Unicode, there was no real difference between charset and encoding.
- Both terms were used to refer to a way to represent letters in binary.
- Therefore, ASCII, Latin1, Cp1252 etc. can be considered as character sets and encodings at the same time, hence the confusion.


- 유니코드가 발명되기 전에는 문자 세트와 인코딩 사이에 실질적인 차이가 없었습니다.
- 두 용어 모두 문자를 이진수로 표현하는 방식을 가리키는 데 사용되었습니다.
- 따라서 ASCII, Latin1, Cp1252 등은 문자 집합인 동시에 인코딩으로 간주하여 혼동을 일으킬 수 있습니다.
- 유니코드가 등장하자 문자를 바이트로 표현하는 것이 이제 2단계 프로세스가 되었기 때문에 명확한 구별이 이루어졌습니다.
  - 문자/문자 개념을 코드 포인트(code point)라는 숫자에 연관시킵니다.
  - 비트를 사용하여 이 "코드 포인트" 번호를 인코딩합니다.

따라서 오늘날 문자 집합, 인코딩 두 용어를 다음과 같이 정의할 수 있습니다.
- 문자 집합
  - 코드 포인트라고 하는 이론적이고 추상적인 숫자에 매핑된 문자 세트입니다.
  - 유니코드는 전 세계에서 사용되는 거의 모든 문자를 포함하는 문자 집합의 예입니다.
  - Charset = letter -> code point

- 인코딩 체계
  - 이러한 코드 포인트가 UTF-8 또는 UTF-16BE와 같이 바이트로 표현되는 방식을 설명합니다.
  - Encoding scheme = code point -> bytes

- Here is an example with the euro symbol “€”:
<img width="724" alt="image" src="https://github.com/zz9z9/zz9z9.github.io/assets/64415489/ec850502-31fe-4a90-a0d1-c6027d0d14c4">


# 참고 자료
- https://medium.com/@joffrey.bion/charset-encoding-encryption-same-thing-6242c3f9da0c
- https://www.joelonsoftware.com/2003/10/08/the-absolute-minimum-every-software-developer-absolutely-positively-must-know-about-unicode-and-character-sets-no-excuses/
