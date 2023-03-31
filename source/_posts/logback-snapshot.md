---
title: Logback 实战之关键日志快照回溯-Logback(二)  
tags: Logback
date: 2021/2/13
categories:
- Java
- Spring
- SpringBoot
- Logback
keywords: [Java,SpringBoot,Logback]
description: Logback 实战之关键日志快照回溯
---
这一节笔者为大家分享一个我在公司项目中遇到的实际案例, 也是对日志使用的一个小拓展.   
由于笔者所在的公司环境复杂, 有开发环境、测试环境、生产环境等, 且各环境间通信隔离. 而这个项目中某核心算法模块内部实现复杂, 很难直接通过观察 LOG 定位问题所在(源码约5000行, 并且还在开发阶段). 那么就需要解决测试、生产环境环境中算法发生故障后, 可以通过一个简单有效的方案来恢复当时的环境. 将环境在开发环境中可以跑起来, 那这样就可以本地 DEBUG 定位问题  
<!-- more -->

# 项目源码
https://gitee.com/zture/spring-test/tree/master/logback

# 需求分析
我们需要实现以下功能: 
- 当核心算法每次被调用的时候, 将它的入参全都记录下来
- 根据唯一 ID 从记录中将当时的环境复现
- 有自动清理功能, 防止磁盘被撑爆. 超过两天或者超过 2GB 需要自动清理

# 定制方案
当明确需求之后我们发现与 Logback 的特性有天然的契合
- 使用 log.debug() 方法将入参输出到日志上
- 在 Logback 配置文件定义一个 `SNAPSHOT` logger 
- 将所有 Logger 名为 SNAPSHOT 的日志输出到一个单独的文件
- 恢复快照时, 使用 RandomAccessFile 倒读文件. 将最后行日志读取出来(可扩展)

# 项目编码

## pom.xml
重要依赖说明:
- spring-boot-starter: 包含了 Logback 相关依赖  
- lombok: 方便我们构建测试对象  
- fastjson: 快速序列化反序列化 Java 对象
```xml
<parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>2.4.5</version>
    <relativePath/> <!-- lookup parent from repository -->
</parent>
<dependencies>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter</artifactId>
    </dependency>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-test</artifactId>
        <scope>test</scope>
    </dependency>
    <dependency>
        <groupId>org.projectlombok</groupId>
        <artifactId>lombok</artifactId>
        <optional>true</optional>
    </dependency>
    <dependency>
        <groupId>com.alibaba</groupId>
        <artifactId>fastjson</artifactId>
        <version>1.2.76</version>
    </dependency>
</dependencies>
```

## Logback 配置
logback-spring.xml 如下配置. 该配置会将所有 'Logger name' 为 'SNAPSHOT' 的日志都通过 appender 名为 'SNAPSHOT_FILE' 的配置, 持久化到文件中.  
开发环境输出路径为: 项目根目录下 log/logback-test/snapshot  
生产环境输出路径为: /opt/log/logback-test/snapshot  

`注意: `若要生产环境配置生效, 需在 application.yml 中配置 spring
```xml
<?xml version="1.0" encoding="UTF-8" ?>
<configuration scan="true" scanPeriod="10 seconds">
    <contextName>logback-spring</contextName>

    <property name="server.name" value="logback-test"/>

    <!-- 日志存放路径 -->
    <!-- 开发环境缺省地址 -->
    <property name="logging.path" value="log/${server.name}"/>
    <springProfile name="prod">
        <!-- 生产环境替换 -->
        <property name="logging.path" value="/opt/log/${server.name}"/>
    </springProfile>

    <property name="model.snapshot.name" value="snapshot"/>
    <property name="model.web.name" value="web"/>
    <!-- web日志过期时间 -->
    <property name="logging.ttl" value="7"/>
    <!-- 快照过期时间 -->
    <property name="snapshot.ttl" value="2"/>

    <conversionRule conversionWord="clr" converterClass="org.springframework.boot.logging.logback.ColorConverter"/>
    <conversionRule conversionWord="wex" converterClass="org.springframework.boot.logging.logback.WhitespaceThrowableProxyConverter"/>
    <conversionRule conversionWord="wEx" converterClass="org.springframework.boot.logging.logback.ExtendedWhitespaceThrowableProxyConverter"/>

    <!-- 彩色日志样式 -->
    <property name="CONSOLE_LOG_PATTERN"
              value="${CONSOLE_LOG_PATTERN:-%clr(%d{yyyy-MM-dd HH:mm:ss.SSS}){faint} %clr(${LOG_LEVEL_PATTERN:-%5p}) %clr(${PID:- }){magenta} %clr(---){faint} %clr([%15.15t]){faint} %clr(%-40.40logger{39}){cyan} %clr(:){faint} %m%n${LOG_EXCEPTION_CONVERSION_WORD:-%wEx}}"
    />
    <property name="WHITE_CONSOLE_LOG_PATTERN"
              value="%d{yyyy-MM-dd HH:mm:ss.SSS} [%thread] %-5level %logger{50} -%msg%n"
    />

    <!--1. 输出到控制台-->
    <appender name="CONSOLE" class="ch.qos.logback.core.ConsoleAppender">
        <filter class="ch.qos.logback.classic.filter.ThresholdFilter">
            <level>debug</level>
        </filter>
        <encoder>
            <pattern>${CONSOLE_LOG_PATTERN}</pattern>
            <charset>UTF-8</charset>
        </encoder>
    </appender>
    
    <!-- SNAPSHOT LOG OUT -->
    <appender name="SNAPSHOT_FILE" class="ch.qos.logback.core.rolling.RollingFileAppender">
        <filter class="ch.qos.logback.classic.filter.LevelFilter">
            <level>debug</level>
            <onMatch>ACCEPT</onMatch>
            <onMismatch>DENY</onMismatch>
        </filter>
        <encoder>
            <pattern>${WHITE_CONSOLE_LOG_PATTERN}</pattern>
            <charset>UTF-8</charset>
        </encoder>
        <rollingPolicy class="ch.qos.logback.core.rolling.SizeAndTimeBasedRollingPolicy">
            <fileNamePattern>${logging.path}/${model.snapshot.name}/${model.snapshot.name}-%d{yyyy-MM-dd}.%i.log</fileNamePattern>
            <maxFileSize>100MB</maxFileSize>
            <totalSizeCap>2GB</totalSizeCap>
            <maxHistory>${snapshot.ttl}</maxHistory>
        </rollingPolicy>
    </appender>

    <root>
        <!-- 生产环境将 WEB 日志打印到控制台. 并记录到文件中 -->
        <level value="debug"/>
        <appender-ref ref="CONSOLE"/>
    </root>

    <logger name="SNAPSHOT" level="debug" additivity="false">
        <appender-ref ref="SNAPSHOT_FILE"/>
    </logger>
</configuration>
```

## 持久化对象
新建一个任意对象, 将来用于测试持久化方法
```java
import lombok.Data;

@Data
public class Foo {
    private String id;
    private String name;
    private String type;

    public Foo() {
    }
}
```

## 快照持久化类
快照持久化类提供以下两个方法
- save(): Java 对象序列化成日志的方法 
- readLast(): 从文件尾读取数据, 并将其反序列化成 Java 对象

```java
import com.alibaba.fastjson.JSON;
import com.ztrue.test.entity.Foo;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.util.ObjectUtils;

import java.io.File;
import java.io.IOException;
import java.io.RandomAccessFile;

/**
 * 快照持久化
 *
 * @author: ztrue
 * @date: 2021/4/20
 * @version: 1.0
 */
public class SnapshotPersistence {
    /**
     * 定义 Logger name 为 SNAPSHOT
     */
    private final static Logger log = LoggerFactory.getLogger("SNAPSHOT");

    /**
     * 持久化 Foo 对象
     */
    public static void save(Foo foo) {
        // logback-spring.xml 的配置中会将 'Logger name = SNAPSHOT' 的日志持久化到 snapshot*.log 文件中
        log.debug("snapshot id = {}, snapshot data = \n{}", foo.getId(), JSON.toJSONString(foo));
    }

    /**
     * 从文件尾开始读数据
     * 
     * RandomAccessFile 读取文件并返回 Java 对象
     */
    public static Foo readLast(File file) {
        if (null == file || !file.exists() || file.isDirectory() || !file.canRead()) {
            return null;
        }

        // 这里是对应解析 {@link SnapshotPersistence#save} 方法的正则表达式
        String regex = "[\\s\\S]*snapshot id = [\\s\\S]*, snapshot data =[\\s\\S]*";

        try (RandomAccessFile raf = new RandomAccessFile(file, "r")) {
            long len = raf.length();
            if (len == 0L) {
                return null;
            } else {
                // 读磁头位置
                long prePos = len;
                long pos = len;

                // 当前行
                String line;
                // 当前行的下一行, 用作缓存
                String nextLine = null;
                while (--pos >= 0) {
                    raf.seek(pos);
                    if (pos == 0 || raf.readByte() == '\n') {
                        byte[] bytes = new byte[(int) (prePos - pos)];
                        raf.read(bytes);
                        line = new String(bytes);
                        if (line.matches(regex)) {
                            // 快照文件匹配到正则后, nextLine 就是我们之间 JSON.toJSONString(foo) 的字符串
                            if (!ObjectUtils.isEmpty(nextLine)) {
                                return JSON.parseObject(nextLine.trim(), Foo.class);
                            } else {
                                return null;
                            }
                        } else {
                            nextLine = line;
                        }
                        prePos = pos;
                    }
                }
            }
        } catch (IOException e) {
            e.printStackTrace();
        }
        return null;
    }
}
```

## 测试

编写测试类

```java
import com.alibaba.fastjson.JSON;
import com.ztrue.test.entity.Foo;
import com.ztrue.test.snapshot.SnapshotPersistence;
import lombok.extern.slf4j.Slf4j;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.util.ObjectUtils;

import java.io.File;
import java.util.UUID;

@SpringBootTest
@Slf4j
public class SnapshotTest {

    @Test
    public void testSave() {
        Foo foo = new Foo();
        foo.setId(UUID.randomUUID().toString());
        foo.setName("zhangsan");
        foo.setType("people");
        SnapshotPersistence.save(foo);
        log.debug("save success! Foo is {}", JSON.toJSONString(foo));
    }

    @Test
    public void testConcurrentSave () {
        for (int i = 0; i < 100; i++) {
            new Thread(this::testSave)
                    .start();
        }
    }

    @Test
    public void testReadLog() {
        // 日志存放的目录
        String snapshotDir = "log/logback-test/snapshot";
        File dir = new File(snapshotDir);
        log.info("snapshotDir = {}", snapshotDir);
        if (!dir.isDirectory()) {
            log.error("SnapshotDir is not a directory! Please change your input.");
            return;
        }
        // 获取目录下的所有文件
        String[] fileList = dir.list();
        if (ObjectUtils.isEmpty(fileList)) {
            log.error("SnapshotDir can not been empty!");
            return;
        }
        // 将目录下的第一个文件最后一行配置读取出来
        File readFile = new File(snapshotDir + "/" + fileList[0]);
        Foo foo = SnapshotPersistence.readLast(readFile);
        log.info("Read Foo success!");
        log.info("Foo is {}", JSON.toJSONString(foo));
    }
}
```

## 测试持久化到文件
1. 执行 {@link SnapshotTest#testSave} 方法, 看到控制台输出以下日志说明已经持久化到文件成功了  
```log
2021-04-20 22:03:40.840 DEBUG 6836 --- [           main] com.ztrue.test.SnapshotTest              : save success! Foo is {"id":"c7179e92-8123-4e23-b5bb-fbb782e6a21b","name":"zhangsan","type":"people"}
```

2. 日志在项目根目录 log/logback-test/snapshot 下生成了  
![](test-step1.png)
   
3. 点开日志, 可以看到我们持久化的数据  
![](test-step2.png)
   
## 测试高并发写入
1. 执行 {@link SnapshotTest#testConcurrentSave} 方法
2. 打开日志文件观察有没有串行的情况发生, 即:
- 同时出现两行 JSON.toJSONString(foo) 的日志
- 或两行类似 '2021-02-08 22:03:40.839 [main] DEBUG SNAPSHOT -snapshot id = c7179e92-8123-4e23-b5bb-fbb782e6a21b, snapshot data ='的日志
![](test-step4.png)
3. 测试成功! 说明在高并发情况下, Logback 也可以将日志依次写入文件(Logback 特性之一)

## 测试反序列化
1. 执行 {@link SnapshotTest#testReadLog} 方法, 看到控制台输出:
```log
2021-04-20 22:15:29.910  INFO 11400 --- [           main] com.ztrue.test.SnapshotTest              : snapshotDir = log/logback-test/snapshot
2021-04-20 22:15:29.985  INFO 11400 --- [           main] com.ztrue.test.SnapshotTest              : Read Foo success!
```

2. Debug打断点看看 Java 对象中是否被成功读取
![](test-step3.png)
   
3. 测试成功!

# 小结
Logback 当然还能做很多事情, 这里只是举了实战中的一个例子而已. 当然这部分测试代码还有许多可以优化的地方, 比如: save() 和 readLast() 方法可以传泛型进来, 只是公司里的场景对泛型没有需求, 代码的实现应该视场景而定.  
结合框架的特性来使用才能达到期望的效果

