---
title: SXSSF를 사용하는데 OOM이 발생한다 ?
date: 2025-07-12 22:25:00 +0900
categories: [경험하기, 이슈 노트]
tags: [Java]
---

## 상황
- 백오피스 시스템에서 조회 기간 길게해서 엑셀 파일 다운로드했더니 OOM 발생
- 해당 엑셀 다운로드 로직에서는 파일 생성을 위해 [poi 라이브러리](https://poi.apache.org/components/spreadsheet/)의 `SXSSF` 구현체 사용중
- [전에 `XSSF` 구현체와 비교](https://zz9z9.github.io/posts/xssf-oom-analyze/)했을때, `SXSSF`는 row를 메모리에서 디스크로 flush 하면서 생성한다고 했는데 왜 OOM이 발생한걸까 ?

![image](/assets/img/sxssf-flush-img1.jpeg)
<figure align = "center">
  <figcaption align="center">(SXSSFRow가 11만개나 쌓여있는 것을 볼 수 있다)</figcaption>
</figure>


## 원인 파악

**1. SXSSF 구현체는 어떤 기준으로 row를 flush하는걸까 ?**

> 먼저 `org.apache.poi.xssf.streaming.SXSSFSheet` 코드를 살펴보자

- **SXSSFSheet 기준**으로 row생성시 SXSSFWorkbook을 생성할 때 넘긴 rowAccessWindowSize(default :100)라 불리는 윈도우 사이즈를 초과하면 메모리상의 row를 flush한다.

![image](/assets/img/sxssf-flush-img2.png)

![image](/assets/img/sxssf-flush-img3.png)

> 다음은 `org.apache.poi.xssf.streaming.SXSSFWorkbook`의 코드이다.

- `SXSSFWorkbook.write` 호출시 각 시트별로 메모리상에 남아있는 row를 flush하는 것을 알 수 있다.

![image](/assets/img/sxssf-flush-img4.png)

![image](/assets/img/sxssf-flush-img5.jpeg)

**2. 엑셀 파일 생성 관련 코드**

```java
public void 엑셀생성(...) {
    int excelTabNo = 1;
    int pagingSize = 10000;
    param.changePageSize(pagingSize);

    SXSSFWorkbook workbook = new SXSSFWorkbook(pagingSize);
    while (true) {
        List<FooRow> rows = 목록_조회(pagingSize);
        if (rows.isEmpty()) {
            break;
        }

        // sheet 생성 및 row 채우기
        Sheet sheet = workbook.createSheet("foo_" + excelTabNo);

        ...

        excelTabNo++;
    }

    // 엑셀 파일 생성
    workbook.write(...);
    ...
}
```

- `pagingSize`마다 엑셀 시트가 새롭게 만들어지기 때문에, 하나의 시트에 최대 row수는 `pagingSize`
- `rowAccessWindowSize`는 `pagingSize`와 같으므로, 시트별로 메모리상의 `row수 > rowAccessWindowSize`가 될 수 없음.
- 따라서, `workbook.write` 호출전까지는 flush 되지않고 메모리에 계속 쌓이게됨

## 조치
- `rowAccessWindowSize`는 `pagingSize`가 아닌 default 값(100) 사용
  - 그래도 `workbook.write` 전까지 시트별로 최대 100개의 row는 메모리 상에 쌓여있게됨
  - 시트가 많지는 않으므로 메모리에 부담되진 않을 것으로 생각
  - 100보다 더 작으면 Disk I/O가 너무 많이 발생하지 않을까 생각함
