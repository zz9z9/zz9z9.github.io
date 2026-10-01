
## 상황
- SXSSF 사용하는데 메모리에 SXSSFRow가 매우 많이 쌓여있음

```java
public void merchantListExcelByTidDownload(HttpServletResponse response,
                                      MerchantListByTidExcelParam param) throws Exception {
    int excelTabNo = 1;
    int pageSize = 10000;
    param.changePageSize(pageSize);

    SXSSFWorkbook workbook = new SXSSFWorkbook(pageSize);

    while (true) {
        List<MerchantListSearchView> rows = getOfflineMerchantByTidExcelList(param);
        if (rows.isEmpty()) {
            break;
        }

        // 엑셀 파일 생성
        Sheet sheet = workbook.createSheet("가맹점_tid별_리스트_" + excelTabNo);
        excelDownUtil.fillExcelHeader(workbook, sheet, param.getHeaderList());

        setExcelRowsWithMasking(rows, param.getFields(), sheet);

        excelTabNo++;
        param.setNextPage();
    }

    excelDownUtil.printExcelFile(response, workbook,  "가맹점_tid별_리스트");
}
```

## pageSize가 초과하면 flush되는게 아니었나 ?
- 기본적으로는 sheet 단위로 createRow시

```java
// org.apache.poi.xssf.streaming.SXSSFSheet
public SXSSFRow createRow(int rownum) {
    int maxrow = SpreadsheetVersion.EXCEL2007.getLastRowIndex();
    if (rownum >= 0 && rownum <= maxrow) {
        if (rownum <= this._writer.getLastFlushedRow()) {
            throw new IllegalArgumentException("Attempting to write a row[" + rownum + "] in the range [0," + this._writer.getLastFlushedRow() + "] that is already written to disk.");
        } else if (this._sh.getPhysicalNumberOfRows() > 0 && rownum <= this._sh.getLastRowNum()) {
            throw new IllegalArgumentException("Attempting to write a row[" + rownum + "] in the range [0," + this._sh.getLastRowNum() + "] that is already written to disk.");
        } else {
            SXSSFRow newRow = new SXSSFRow(this);
            this._rows.put(rownum, newRow);
            this.allFlushed = false;
            if (this._randomAccessWindowSize >= 0 && this._rows.size() > this._randomAccessWindowSize) {
                try {
                    this.flushRows(this._randomAccessWindowSize);
                } catch (IOException var5) {
                    IOException ioe = var5;
                    throw new RuntimeException(ioe);
                }
            }

            return newRow;
        }
    } else {
        throw new IllegalArgumentException("Invalid row number (" + rownum + ") outside allowable range (0.." + maxrow + ")");
    }
}
```

- 또는 SXSSFWorkbook.write시

```java
// org.apache.poi.xssf.streaming.SXSSFWorkbook
public void write(OutputStream stream) throws IOException {
    this.flushSheets();
    ...
}

protected void flushSheets() throws IOException {
    Iterator var1 = this._xFromSxHash.values().iterator();

    while(var1.hasNext()) {
        SXSSFSheet sheet = (SXSSFSheet)var1.next();
        sheet.flushRows();
    }
}
```

- 즉, `SXSSFWorkbook workbook = new SXSSFWorkbook(pageSize);` 이렇게 세팅해놓은 상태에서 sheet별 최대 row수는 pageSize이기 때문에, pageSize를 초과하지 않아 flush가 되지 않았던것

## 조치
- `SXSSFWorkbook workbook = new SXSSFWorkbook(); // default : 100`
  - 시트별로 100개씩은 남아있긴함

- rowAccessWindowSize 조정 ?

| 설정값   | I/O 부하 | 메모리 사용 | 속도                        |
| ----- | ------ | ------ | ------------------------- |
| 작게 설정 | 📈 증가  | 📉 감소  | 📉 느려질 수 있음               |
| 크게 설정 | 📉 감소  | 📈 증가  | 📈 빠를 수 있음 (단, OOM 위험 있음) |


## 테스트
> 2025.01.01 ~ 2025.05.01 => 약 34,000건

- disk await time , disk i/o, heap memory, cpu usage

- defaultSize (100)
  - 시작 : 14:20:26 
  - 끝 : 14:23:09

- pageSize (10000)
  - 시작 : 14:46:53
  - 끝 : 14:49:31