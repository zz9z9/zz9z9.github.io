---
title: MyBatis 기본 개념
date: 2023-12-31 10:25:00 +0900
---

## SqlSession

https://mybatis.org/mybatis-3/getting-started.html

## SqlSessionFactory

https://mybatis.org/mybatis-3/getting-started.html

## SqlSessionTemplate
- Thread safe, Spring managed SqlSession that works with Spring transaction management to ensure that the
  actual SqlSession used is the one associated with the current Spring transaction.
- In addition, it manages the session life-cycle, including closing, committing or rolling back the session as necessary based on the Spring transaction configuration.
- The template needs a SqlSessionFactory to create SqlSessions, passed as a constructor argument.
- It also can be constructed indicating the executor type to be used, if not, the default executor type, defined in the session factory will be used.
- This template converts MyBatis PersistenceExceptions into unchecked DataAccessExceptions, using, by default, a
  MyBatisExceptionTranslator.
- Because SqlSessionTemplate is thread safe, a single instance can be shared by all DAOs; there should also be a small memory savings by doing this.

- When calling SQL methods, including any method from Mappers returned by getMapper(), SqlSessionTemplate will ensure that the SqlSession used is the one associated with the current Spring transaction. In addition, it manages the session life-cycle, including closing, committing or rolling back the session as necessary. It will also translate MyBatis exceptions into Spring DataAccessExceptions.
https://mybatis.org/spring/sqlsession.html

## TypeHandler
- Whenever MyBatis sets a parameter on a PreparedStatement or retrieves a value from a ResultSet, a TypeHandler is used to retrieve the value in a means appropriate to the Java type. The following table describes the default TypeHandlers.
- NOTE Since version 3.4.5, MyBatis supports JSR-310 (Date and Time API) by default.


https://mybatis.org/mybatis-3/configuration.html#typehandlers

## ResultHandler

## RowBounds

## Mapper
Mappers are interfaces that you create to bind to your mapped statements. Instances of the mapper interfaces are acquired from the SqlSession. As such, technically the broadest scope of any mapper instance is the same as the SqlSession from which they were requested. However, the best scope for mapper instances is method scope. That is, they should be requested within the method that they are used, and then be discarded. They do not need to be closed explicitly. While it's not a problem to keep them around throughout a request, similar to the SqlSession, you might find that managing too many resources at this level will quickly get out of hand. Keep it simple, keep Mappers in the method scope. The following example demonstrates this practice.


https://mybatis.org/mybatis-3/getting-started.html

## ResultMap

## @Select

## Caching
- MyBatis includes a powerful transactional query caching feature which is very configurable and customizable.
- A lot of changes have been made in the MyBatis 3 cache implementation to make it both more powerful and far easier to configure.

- By default, just local session caching is enabled that is used solely to cache data for the duration of a session.
- To enable a global second level of caching you simply need to add one line to your SQL Mapping file: `<cache/>`. Literally that's it.
- The effect of this one simple statement is as follows:
  - All results from select statements in the mapped statement file will be cached.
  - All insert, update and delete statements in the mapped statement file will flush the cache.
  - The cache will use a Least Recently Used (LRU) algorithm for eviction.
  - The cache will not flush on any sort of time based schedule (i.e. no Flush Interval).
  - The cache will store 1024 references to lists or objects (whatever the query method returns).
  - The cache will be treated as a read/write cache, meaning objects retrieved are not shared and can be safely modified by the caller, without interfering with other potential modifications by other callers or threads.

- NOTE
  -  The cache will only apply to statements declared in the mapping file where the cache tag is located. If you are using the Java API in conjunction with the XML mapping files, then statements declared in the companion interface will not be cached by default. You will need to refer to the cache region using the `@CacheNamespaceRef` annotation.
  - Second level cache is transactional. That means that it is updated when a SqlSession finishes with commit or when it finishes with rollback but no inserts/deletes/updates with `flushCache=true` where executed.

### local session caching
- Local session cache is enabled with default option
- Cache boundary is for all the queries within a SqlSession
- An item is cached when querying a record
- The item is reused when querying with the same parameter
- Cache is flushed when insert/update/delete is executed or when the SqlSession is closed
- When flushing cache, all cache items are deleted

- `org.apache.ibatis.executor.BaseExecutor#query`
```java
    public <E> List<E> query(MappedStatement ms, Object parameter, RowBounds rowBounds, ResultHandler resultHandler, CacheKey key, BoundSql boundSql) throws SQLException {
        ErrorContext.instance().resource(ms.getResource()).activity("executing a query").object(ms.getId());
        if (this.closed) {
            throw new ExecutorException("Executor was closed.");
        } else {
            if (this.queryStack == 0 && ms.isFlushCacheRequired()) {
                this.clearLocalCache();
            }

            List list;
            try {
                ++this.queryStack;
                list = resultHandler == null ? (List)this.localCache.getObject(key) : null;
                if (list != null) {
                    this.handleLocallyCachedOutputParameters(ms, key, parameter, boundSql);
                } else {
                    list = this.queryFromDatabase(ms, parameter, rowBounds, resultHandler, key, boundSql);
                }
            } finally {
                --this.queryStack;
            }

            ...

            return list;
        }
    }
```

- Example
```xml
<select
  id="selectPerson"
  parameterType="int"
  parameterMap="deprecated"
  resultType="hashmap"
  resultMap="personResultMap"
  flushCache="false"
  useCache="true"
  timeout="10"
  fetchSize="256"
  statementType="PREPARED"
  resultSetType="FORWARD_ONLY">
```

- `flushCache` : Setting this to true will cause the local and 2nd level caches to be flushed whenever this statement is called. Default: false for select statements.
  `useCache` : Setting this to true will cause the results of this statement to be cached in 2nd level cache. (Default: true for select statements.)

### global second level of caching
- Global cache is on by explicit option
- Cache boundary is a mapper’s namespace (= all the sqls within the mapper file)
- An item is cached for queried data
- Cache items are cached when SqlSession.close(), commit() or rollback() (which is different from local cache)
- Cache flushing happens when SqlSession.close(), commit() or rollback()
- Cache flushing happens if insert/update/delete is executed, in that case, all queried data before insert/update/delete are deleted
  - For example, query record 1 -> query record 2 -> update record 1 -> query record  3 happens, only record 3 is cached
(record 1 and 2 are not cached because update is executed)

- Some points to consider
  - If you want to use global cache, split mapper into cache boundary (Don’t put all sqls into one mapper.xml)
  - If insert/update/delete happens frequently, global cache is not recommended (It is diffecult to verify a cache’s lifecycle)
  - Use local cache only if concurrent access to the same record does not happen
  - If insert/update/delete happens frequently, local cache also is not recommended

https://mybatis.org/mybatis-3/sqlmap-xml.html#cache
https://12bme.tistory.com/364
https://tkstoneblog.wordpress.com/2018/10/30/some-points-to-consider-when-using-mybatis-cache/

- 캐시 관련 장애 사례 : https://techblog.lotteon.com/%EC%96%B4%EB%9E%8F-%EC%97%AC%EA%B8%B0%EC%97%90%EC%84%9C-oom-%EB%B0%9C%EC%83%9D%ED%95%A0-%EC%A4%84%EC%9D%B4%EC%95%BC-503ddf286fd

### cache-ref
- Recall from the previous section that only the cache for this particular namespace will be used or flushed for statements within the same namespace.
- There may come a time when you want to share the same cache configuration and instance between namespaces.
- In such cases you can reference another cache by using the `cache-ref` element.
`<cache-ref namespace="com.someone.application.data.SomeMapper"/>`

## Lazy Loading
- Most MyBatis applications will configure a dataSource as in the example. However, it’s not required. Realize though, that to facilitate Lazy Loading, this dataSource is required.

- `lazyLoadingEnabled`	Globally enables or disables lazy loading. When enabled, all relations will be lazily loaded. This value can be superseded for a specific relation by using the fetchType attribute on it. (Default : `false`)

```xml
<settings>
  <setting name="cacheEnabled" value="true"/>
  <setting name="lazyLoadingEnabled" value="true"/>
  ...
</settings>
```

- https://colinch4.github.io/2023-08-21/copy-61/
- https://itecnote.com/tecnote/java-lazy-loading-using-mybatis-3-with-java/

## DataSource

## TransactionManager
