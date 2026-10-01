---
title: 예외 핸들링은 어떻게하는게 좋을까 ?
date: 2025-02-23 22:29:00 +0900
categories: [생각해보기, 코드 작성]
tags: []
---

```java
// com.mysql.cj.jdbc.ConnectionImpl#close
public void close() throws SQLException {
    try {
        synchronized(this.getConnectionMutex()) {
            if (this.connectionLifecycleInterceptors != null) {
                Iterator var2 = this.connectionLifecycleInterceptors.iterator();

                while(var2.hasNext()) {
                    ConnectionLifecycleInterceptor cli = (ConnectionLifecycleInterceptor)var2.next();
                    cli.close();
                }
            }

            this.realClose(true, true, false, (Throwable)null);
        }
    } catch (CJException var7) {
        throw SQLExceptionsMapping.translateException(var7, this.getExceptionInterceptor());
    }
}
```

- 나의 경우, 서비스 레이어에서 관심있는거는 '변경이 가능한지 아닌지'에 대한 부분이라고 생각해서 `ClientModificationNotAllowedException` 이런식으로 변환해서 예외를 던졌는데, 어떤지 ?

```java
   public ClientUpdateResult update(Client toClient) {
  try {
    Client currClient = validate(toClient.getContactNum(), toClient.getEmail());
    Client updateClient = clientStore.update(toClient);

    log.info("고객({}) 정보 수정 완료", currClient.getContactNum());

    return new ClientUpdateResult(currClient, updateClient);
  } catch (LockAlreadyAcquiredException ex) {
    throw new ClientModificationNotAllowedException(String.format("이미 %s 처리 중인 고객입니다.", ex.getLockType().getName()), HttpStatus.CONFLICT);
  } catch (DuplicateKeyException | ConcurrentModificationException ex) {
    throw new ClientModificationNotAllowedException(ex.getMessage(), HttpStatus.CONFLICT);
  }
}
```

- LockAlreadyAcquiredException, DuplicateKeyException 이런것들을 모두 DataStorageException 이런거로 묶었어야되는건가 ??

```java
// com.mysql.cj.jdbc.exceptions.SQLExceptionsMapping
public class SQLExceptionsMapping {
  public SQLExceptionsMapping() {
  }

  public static SQLException translateException(Throwable ex, ExceptionInterceptor interceptor) {
    if (ex instanceof SQLException) {
      return (SQLException)ex;
    } else if (ex.getCause() != null && ex.getCause() instanceof SQLException) {
      return (SQLException)ex.getCause();
    } else if (ex instanceof CJCommunicationsException) {
      return SQLError.createCommunicationsException(ex.getMessage(), ex, interceptor);
    } else if (ex instanceof CJConnectionFeatureNotAvailableException) {
      return new ConnectionFeatureNotAvailableException(ex.getMessage(), ex);
    } else if (ex instanceof SSLParamsException) {
      return SQLError.createSQLException(ex.getMessage(), "08000", 0, false, ex, interceptor);
    } else if (ex instanceof ConnectionIsClosedException) {
      return SQLError.createSQLException(ex.getMessage(), "08003", ex, interceptor);
    } else if (ex instanceof InvalidConnectionAttributeException) {
      return SQLError.createSQLException(ex.getMessage(), "01S00", ex, interceptor);
    } else if (ex instanceof UnableToConnectException) {
      return SQLError.createSQLException(ex.getMessage(), "08001", ex, interceptor);
    } else if (ex instanceof StatementIsClosedException) {
      return SQLError.createSQLException(ex.getMessage(), "S1009", ex, interceptor);
    } else if (ex instanceof WrongArgumentException) {
      return SQLError.createSQLException(ex.getMessage(), "S1009", ex, interceptor);
    } else if (ex instanceof StringIndexOutOfBoundsException) {
      return SQLError.createSQLException(ex.getMessage(), "S1009", ex, interceptor);
    } else if (ex instanceof NumberOutOfRange) {
      return SQLError.createSQLException(ex.getMessage(), "22003", ex, interceptor);
    } else if (ex instanceof DataConversionException) {
      return SQLError.createSQLException(ex.getMessage(), "22018", ex, interceptor);
    } else if (ex instanceof DataReadException) {
      return SQLError.createSQLException(ex.getMessage(), "S1009", ex, interceptor);
    } else if (ex instanceof DataTruncationException) {
      return new MysqlDataTruncation(((DataTruncationException)ex).getMessage(), ((DataTruncationException)ex).getIndex(), ((DataTruncationException)ex).isParameter(), ((DataTruncationException)ex).isRead(), ((DataTruncationException)ex).getDataSize(), ((DataTruncationException)ex).getTransferSize(), ((DataTruncationException)ex).getVendorCode());
    } else if (ex instanceof CJPacketTooBigException) {
      return new PacketTooBigException(ex.getMessage());
    } else if (ex instanceof OperationCancelledException) {
      return new MySQLStatementCancelledException(ex.getMessage());
    } else if (ex instanceof CJTimeoutException) {
      return new MySQLTimeoutException(ex.getMessage());
    } else if (ex instanceof CJOperationNotSupportedException) {
      return new OperationNotSupportedException(ex.getMessage());
    } else if (ex instanceof UnsupportedOperationException) {
      return new OperationNotSupportedException(ex.getMessage());
    } else {
      return ex instanceof CJException ? SQLError.createSQLException(ex.getMessage(), ((CJException)ex).getSQLState(), ((CJException)ex).getVendorCode(), ((CJException)ex).isTransient(), ex.getCause(), interceptor) : SQLError.createSQLException(ex.getMessage(), "S1000", ex, interceptor);
    }
  }

  public static SQLException translateException(Throwable ex) {
    return translateException(ex, (ExceptionInterceptor)null);
  }
}
```


예외 ? 핸들링 목적 ?
