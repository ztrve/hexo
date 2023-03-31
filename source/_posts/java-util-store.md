---
title: 优雅的实现计算机容量Bit Byte KB等互相转换-Java工具类  
tags: 工具类   
date: 2021/3/19  
categories:
- Java
keywords: [Java,Bit,Byte,KB,MB,GB,TB,计算机,容量,转换]  
description: 计算机容量转换 Bit Byte KB等互相转换-Java工具类

---
日常工作中, 偶尔会遇到计算机容量之间的相互转换. 众所周知计算机的基本存储单位有Bit, Byte, KB, MB, GB, TB等. 这里参考 TimeUnit 实现一套优雅的计算机容量互相转换工具, 并提供一个支持自动升级容量单位的方法.  
<!-- more -->

# 工具类源码
>https://gitee.com/zture/spring-test/blob/master/demo/src/main/java/cn/diswares/blog/demo/util/StoreUnit.java

# 实现思路
## 创建枚举类 StoreUnit
```java
public enum StoreUnit {}
```
## 定义公共方法
这类方法每个枚举实例都需要实现

```java
/**
 * 将 待转换单位的大小 转换 为此单位的大小.
 *
 * 从细粒度向粗粒度的转化将会被截断处理, 所以会失去精确性.
 * 例如, 转换 {@code 999} KB 到 MB 的结果是 {@code 0}.
 * 从粗粒度转化为细粒度, 结果可能溢出 {@code Long.MAX_VALUE}
 * 或 {@code Long.MIN_VALUE}
 *
 * For example, to convert 10 KB to MB, use:
 * {@code StoreUnit.MB.convert(10L, StoreUnit.KB)}
 *
 * @param source {@param storeUnit} 对应的实际容量
 * @param storeUnit 被转换的单位
 * @return 转换成后的容量大小
 */
public long convert (long source, StoreUnit storeUnit) { throw new AbstractMethodError(); }

/**
 * 容量单位互相转换的公共定义
 */
public long toBit(long source) { throw new AbstractMethodError(); }
public long toByte(long source) { throw new AbstractMethodError(); }
public long toKB(long source) { throw new AbstractMethodError(); }
public long toMB(long source) { throw new AbstractMethodError(); }
public long toGB(long source) { throw new AbstractMethodError(); }
public long toTB(long source) { throw new AbstractMethodError(); }
```

## 定义各容量间互相转换的比率
```java
// bit
static final long C0 = 1L;
// bit to byte
static final long C1 = C0 << 3;
// byte to KB
static final long C2 = C1 << 10;
// KB to MB
static final long C3 = C2 << 10;
// MB to GB
static final long C4 = C3 << 10;
// GB to TB
static final long C5 = C4 << 10;
```

## 容量升级、降级
```java
/**
 * 降级
 *
 * 将 s 按 m 进行放大, 并检查是否溢出
 *
 * @param target 原值
 * @param m 放大比例
 */
static long lower (long target, long m) {
    long absoluteOver = MAX / m;
    if (target > absoluteOver) return Long.MAX_VALUE;
    if (target < -absoluteOver) return Long.MIN_VALUE;
    return target * m;
}

/**
 * 升级
 */
static long upper (long s, long m) {
    return s/m;
}
```

## BIT、BYTE转换实现展示
```java
BIT {
    public long convert (long source, StoreUnit storeUnit) { return storeUnit.toBit(source); }

    // 自己对自己转换 直接返回
    public long toBit(long s) { return s; }
    // 升级则调用升级方法
    public long toByte(long s) { return upper(s, C1/C0); }
    public long toKB(long s) { return upper(s, C2/C0); }
    public long toMB(long s) { return upper(s, C3/C0); }
    public long toGB(long s) { return upper(s, C4/C0); }
    public long toTB(long s) { return upper(s, C5/C0); }
},

BYTE {
    public long convert (long source, StoreUnit storeUnit) { return storeUnit.toByte(source); }

    // 降级调用降级方法
    public long toBit(long s) { return lower(s, C1/C0); }
    // 自己对自己转换 直接返回
    public long toByte(long s) { return s; }
    // 升级则调用升级方法
    public long toKB(long s) { return upper(s, C2/C1); }
    public long toMB(long s) { return upper(s, C3/C1); }
    public long toGB(long s) { return upper(s, C4/C1); }
    public long toTB(long s) { return upper(s, C5/C1); }
},
```

## 自动升级容量
```java
/**
 * 自动升级容量
 * <p>
 * 传入任意一类小容量, 自动识别适合使用哪种容量来展示
 * For example, 如果你传入 1024BIT, 那么就会输出 128BYTE
 */
public static String autoUpper (long source, StoreUnit storeUnit) {
    long convert;
    switch (storeUnit) {
        case BIT:
            if ((convert = BIT.convert(source, storeUnit)) < 8) return convert + BIT.name();
        case BYTE:
            if ((convert = BYTE.convert(source, storeUnit)) < 1024) return convert + BYTE.name();
        case KB:
            if ((convert = KB.convert(source, storeUnit)) < 1024) return convert + KB.name();
        case MB:
            if ((convert = MB.convert(source, storeUnit)) < 1024) return convert + MB.name();
        case GB:
            if ((convert = GB.convert(source, storeUnit)) < 1024) return convert + GB.name();
        case TB:
            if ((convert = TB.convert(source, storeUnit)) < 1024) return convert + TB.name();
        default:
            return source + storeUnit.name();
    }
}
}
```

## 测试
```java

import cn.diswares.blog.demo.util.StoreUnit;
import lombok.extern.slf4j.Slf4j;
import org.junit.jupiter.api.Test;

/**
 * @author: ztrue
 * @date: 2021/5/27
 * @version: 1.0
 */
@Slf4j
public class StoreUnitTests {

    @Test
    public void trans () {
        long bit = 1024L * 1024L * 1024L;

        log.info("{} = {}", StoreUnit.BIT, StoreUnit.BIT.toBit(bit));
        log.info("{} = {}", StoreUnit.BYTE, StoreUnit.BIT.toByte(bit));
        log.info("{} = {}", StoreUnit.KB, StoreUnit.BIT.toKB(bit));
        log.info("{} = {}", StoreUnit.MB, StoreUnit.BIT.toMB(bit));
        log.info("{} = {}", StoreUnit.GB, StoreUnit.BIT.toGB(bit));
        log.info("{} = {}", StoreUnit.TB, StoreUnit.BIT.toTB(bit));
        log.info("===========================");
        log.info("{} = {}", StoreUnit.BIT, StoreUnit.BIT.convert(bit, StoreUnit.BIT));
        log.info("{} = {}", StoreUnit.BYTE, StoreUnit.BYTE.convert(bit, StoreUnit.BIT));
        log.info("{} = {}", StoreUnit.KB, StoreUnit.KB.convert(bit, StoreUnit.BIT));
        log.info("{} = {}", StoreUnit.MB, StoreUnit.MB.convert(bit, StoreUnit.BIT));
        log.info("{} = {}", StoreUnit.GB, StoreUnit.GB.convert(bit, StoreUnit.BIT));
        log.info("{} = {}", StoreUnit.TB, StoreUnit.TB.convert(bit, StoreUnit.BIT));
        log.info("===========================");
        log.info("autoUpper = {}", StoreUnit.autoUpper(bit, StoreUnit.BIT));
    }

}
```

## 测试结果
```log
20:49:12.371 [main] INFO cn.diswares.blog.demo.StoreUnitTests - BIT = 1073741824
20:49:12.379 [main] INFO cn.diswares.blog.demo.StoreUnitTests - BYTE = 134217728
20:49:12.379 [main] INFO cn.diswares.blog.demo.StoreUnitTests - KB = 131072
20:49:12.379 [main] INFO cn.diswares.blog.demo.StoreUnitTests - MB = 128
20:49:12.379 [main] INFO cn.diswares.blog.demo.StoreUnitTests - GB = 0
20:49:12.379 [main] INFO cn.diswares.blog.demo.StoreUnitTests - TB = 0
20:49:12.379 [main] INFO cn.diswares.blog.demo.StoreUnitTests - ===========================
20:49:12.379 [main] INFO cn.diswares.blog.demo.StoreUnitTests - BIT = 1073741824
20:49:12.379 [main] INFO cn.diswares.blog.demo.StoreUnitTests - BYTE = 134217728
20:49:12.379 [main] INFO cn.diswares.blog.demo.StoreUnitTests - KB = 131072
20:49:12.379 [main] INFO cn.diswares.blog.demo.StoreUnitTests - MB = 128
20:49:12.379 [main] INFO cn.diswares.blog.demo.StoreUnitTests - GB = 0
20:49:12.379 [main] INFO cn.diswares.blog.demo.StoreUnitTests - TB = 0
20:49:12.379 [main] INFO cn.diswares.blog.demo.StoreUnitTests - ===========================
20:49:12.380 [main] INFO cn.diswares.blog.demo.StoreUnitTests - autoUpper = 128MB
```

# 总结
此工具类是使用 long 为基本数据类型实现的, 对于低级容量向高级容量转换, 会丢失精度. 若对精度有需求, 将 long 类型改为 double 就可以.  
需要注意的是, 使用 double 类型进行计算, 可能导致计算结果不精确, 对计算结果有严格要求的工程请实现 BigDecimal 版本.  
