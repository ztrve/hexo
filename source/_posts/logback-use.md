---
title: SpringBoot 集成 Logback-Logback(一) 
tags: Logback
date: 2021/2/8
categories:
- Java
- Spring
- SpringBoot
- Logback
keywords: [Java,SpringBoot,Logback]
description: SpringBoot 集成 Logback
---

Spring Boot 家族中核心 Spring Boot Starter 中集成了 Logback 日志框架.    
Logback 的作者说: Logback 的目的是成为目前流行的 Log4j 项目的继承者, 填补 Log4j 的空白.   
让我们一起看看 Logback 到底有什么过人之处.  
>测试项目地址: https://gitee.com/zture/spring-test/tree/master/logback
<!-- more -->

# Logback 的介绍
[Logback](http://logback.qos.ch)是由log4j创始人设计的另一个开源日志组件. 它当前分为下面几个模块: 
- logback-core: 其它两个模块的基础模块
- logback-classic: 它是log4j的一个改良版本, 同时它完整实现了 Slf4j 使你可以很方便地更换成其它日志系统如 Log4j 或 JDK14 Logging
- logback-access: 访问模块与 Servlet 容器集成提供通过 Http 来访问日志的功能

# Logback 取代 log4j 的主要理由
- 更快的实现: Logback的内核重写了, 在一些关键执行路径上性能提升10倍以上. 
- 非常充分的测试: Logback经过了几年, 数不清小时的测试. 
- logback-classic 非常自然实现了 Slf4j.
- 非常充分的文档: 官方网站有两百多页的文档. 
- 自动重新加载配置文件: 当配置文件修改了, logback-classic 能自动重新加载配置文件. 扫描过程快且安全, 它并不需要另外创建一个扫描线程.
- 能够安全地写道同一个日志文件. 
- 配置文件可以处理不同的环境.
- 自动压缩已经打出来的log: 产生新文件的时候, 会自动异步压缩已经打出来的日志文件. 
- 自动去除旧的日志文件: 通过设置文件大小, 过期时间可以自动去除过期日志.

# Spring Boot 中的 Logback
### pom.xml
新建一个简单的 SpringBoot 工程 pom.xml 关键配置如下
```xml
<parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>2.4.5</version>
    <relativePath/> <!-- lookup parent from repository -->
</parent>
<!-- 注意 spring-boot-starter 中会依赖 spring-boot-starter-logging -->
<!-- 而 SpringBoot 其他的 Starter 中会又会依赖 spring-boot-starter -->
<!-- 所以放心用就好了, 肯定会有的 -->
<dependencies>
<!--		<dependency>-->
<!--			<groupId>org.springframework.boot</groupId>-->
<!--			<artifactId>spring-boot-starter</artifactId>-->
<!--		</dependency>-->
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-logging</artifactId>
    </dependency>
</dependencies>
```

我们通过 `mvn dependency:tree` 来观察一下依赖树, 这里只保留了跟 log相关的依赖
```log
[INFO] --- maven-dependency-plugin:3.1.2:tree (default-cli) @ test ---
[INFO] com.ztrue.test:test:jar:0.0.1-SNAPSHOT
[INFO] \- org.springframework.boot:spring-boot-starter-logging:jar:2.4.5:compile
[INFO]    +- ch.qos.logback:logback-classic:jar:1.2.3:compile
[INFO]    |  +- ch.qos.logback:logback-core:jar:1.2.3:compile
[INFO]    |  \- org.slf4j:slf4j-api:jar:1.7.30:compile
[INFO]    +- org.apache.logging.log4j:log4j-to-slf4j:jar:2.13.3:compile
[INFO]    |  \- org.apache.logging.log4j:log4j-api:jar:2.13.3:compile
[INFO]    \- org.slf4j:jul-to-slf4j:jar:1.7.30:compile
```

可以看到 SpringBoot 中缺省还是存在 Logback 和 Log4j. 但是默认开启 Logback. 如果想使用 Log4j 请划走.  

### application.yaml 配置
虽然在 SpringBoot 中 application.yml 也可以直接对 Logback 进行一些简单配置. 但真实生产环境中, 对日志配置的需求十分复杂. 所以这里只对 xml 中的配置进行详细展开  
SpringBoot 官方推荐配置文件名为 logback-spring.xml. 在未经配置的情况下, SpringBoot 会为我们自动扫描 classpath 根路径下以下列命名为规范的 logback 配置文件
- logback-spring.xml
- logback-spring.groovy
- logback.xml
- logback.groovy

如果想要自定义配置文件路径. 那么就在 application.yml 中添加如下配置
```yaml
logging:
  config: classpath:log/logback-spring.xml
```

# Logback 配置详解
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!-- 日志级别从低到高分为TRACE < DEBUG < INFO < WARN < ERROR < FATAL，如果设置为WARN，则低于WARN的信息都不会输出 -->
<!-- scan:当此属性设置为true时，配置文档如果发生改变，将会被重新加载，默认值为true -->
<!-- scanPeriod:设置监测配置文档是否有修改的时间间隔，如果没有给出时间单位，默认单位是毫秒。
                 当scan为true时，此属性生效。默认的时间间隔为1分钟。 -->
<!-- debug:当此属性设置为true时，将打印出logback内部日志信息，实时查看logback运行状态。默认值为false。 -->
<!--
总体说明：根节点下有2个属性，三个节点
属性： contextName 上下文名称； property 设置变量
节点： appender,  root， logger
-->
<configuration scan="true" scanPeriod="10 seconds">
        <!--
           contextName说明：
           每个logger都关联到logger上下文，默认上下文名称为“default”。但可以使用设置成其他名字，
           用于区分不同应用程序的记录。一旦设置，不能修改,可以通过%contextName来打印日志上下文名称。
         -->
    <contextName>logback-spring</contextName>
    <!-- name的值是变量的名称，value的值时变量定义的值。通过定义的值会被插入到logger上下文中。定义后，可以使“${}”来使用变量。 -->
    <property name="logging.path" value="myLogs"/>

    <!--0. 日志格式和颜色渲染 -->
    <!-- 彩色日志依赖的渲染类 -->
    <conversionRule conversionWord="clr"
                    converterClass="org.springframework.boot.logging.logback.ColorConverter"/>
    <conversionRule conversionWord="wex"
                    converterClass="org.springframework.boot.logging.logback.WhitespaceThrowableProxyConverter"/>
    <conversionRule conversionWord="wEx"
                    converterClass="org.springframework.boot.logging.logback.ExtendedWhitespaceThrowableProxyConverter"/>
    <!-- 彩色日志格式 -->
    <property name="CONSOLE_LOG_PATTERN"
              value="${CONSOLE_LOG_PATTERN:-%clr(%d{yyyy-MM-dd HH:mm:ss.SSS}){faint} %clr(${LOG_LEVEL_PATTERN:-%5p}) %clr(${PID:- }){magenta} %clr(---){faint} %clr([%15.15t]){faint} %clr(%-40.40logger{39}){cyan} %clr(:){faint} %m%n${LOG_EXCEPTION_CONVERSION_WORD:-%wEx}}"/>

    <!--1. 输出到控制台-->
    <appender name="CONSOLE" class="ch.qos.logback.core.ConsoleAppender">
        <!--此日志appender是为开发使用，只配置最底级别，控制台输出的日志级别是大于或等于此级别的日志信息-->
        <filter class="ch.qos.logback.classic.filter.ThresholdFilter">
            <level>debug</level>
        </filter>

        <!--日志文档输出格式-->
        <encoder>
            <!--指定日志格式-->
            <Pattern>${CONSOLE_LOG_PATTERN}</Pattern>
            <!--设置字符集-->
            <charset>UTF-8</charset>
        </encoder>
    </appender>

    <!--输出到文档-->
    <!-- 时间滚动输出 level为 DEBUG 日志 -->
    <appender name="DEBUG_FILE" class="ch.qos.logback.core.rolling.RollingFileAppender">
        <!-- 正在记录的日志文件的路径及文件名~~~~~file设置打印的文件的路径及文件名，建议绝对路径-->
        <file>${logging.path}/web_debug.log</file>

        <!--日志文档输出格式-->
        <encoder>
            <!--指定日志格式-->
            <pattern>%d{yyyy-MM-dd HH:mm:ss.SSS} [%thread] %-5level %logger{50} - %msg%n</pattern>
            <!-- 设置字符集 -->
            <charset>UTF-8</charset>
        </encoder>

        <!-- 日志记录器的滚动策略，按日期，按大小记录 -->
        <!--
            日志记录器的滚动策略
            SizeAndTimeBasedRollingPolicy 按日期，大小记录日志
            另外一种方式：
                rollingPolicy的class设置为ch.qos.logback.core.rolling.TimeBasedRollingPolicy

        -->
        <rollingPolicy class="ch.qos.logback.core.rolling.TimeBasedRollingPolicy">
            <!-- 日志归档 -->
            <!--
                归档的日志文件的路径，例如今天是2018-08-23日志，当前写的日志文件路径为file节点指定，
                可以将此文件与file指定文件路径设置为不同路径，从而将当前日志文件或归档日志文件置不同的目录。
                而2018-08-23的日志文件在由fileNamePattern指定。%d{yyyy-MM-dd}指定日期格式，%i指定索引
             -->
            <fileNamePattern>${logging.path}/web-debug-%d{yyyy-MM-dd}.%i.log</fileNamePattern>

            <!--
               配置日志文件不能超过100M，若超过100M，日志文件会以索引0开始，命名日志文件
               例如error.20180823.0.txt
               -->
            <timeBasedFileNamingAndTriggeringPolicy
                    class="ch.qos.logback.core.rolling.SizeAndTimeBasedFNATP">
                <maxFileSize>100MB</maxFileSize>
            </timeBasedFileNamingAndTriggeringPolicy>

            <!--日志文档保留天数-->
            <maxHistory>15</maxHistory>
        </rollingPolicy>

        <!-- 此日志文档只记录debug级别的 -->
        <!-- 过滤策略：
            LevelFilter ： 只打印level标签设置的日志级别
            ThresholdFilter：打印大于等于level标签设置的级别，小的舍弃
         -->
        <!--<filter class="ch.qos.logback.classic.filter.ThresholdFilter">-->
        <filter class="ch.qos.logback.classic.filter.LevelFilter">
            <!-- 过滤的日志级别 -->
            <level>debug</level>
            <!--匹配到就允许-->
            <onMatch>ACCEPT</onMatch>
            <!--没有匹配到就禁止-->
            <onMismatch>DENY</onMismatch>
        </filter>
    </appender>


    <!-- 2.2 level为 INFO 日志，时间滚动输出  -->
    <appender name="INFO_FILE" class="ch.qos.logback.core.rolling.RollingFileAppender">
        <!-- 正在记录的日志文档的路径及文档名 -->
        <file>${logging.path}/web_info.log</file>
        <!--日志文档输出格式-->
        <encoder>
            <pattern>%d{yyyy-MM-dd HH:mm:ss.SSS} [%thread] %-5level %logger{50} - %msg%n</pattern>
            <charset>UTF-8</charset>
        </encoder>
        <!-- 日志记录器的滚动策略，按日期，按大小记录 -->
        <rollingPolicy class="ch.qos.logback.core.rolling.TimeBasedRollingPolicy">
            <!-- 每天日志归档路径以及格式 -->
            <fileNamePattern>${logging.path}/web-info-%d{yyyy-MM-dd}.%i.log</fileNamePattern>
            <timeBasedFileNamingAndTriggeringPolicy
                    class="ch.qos.logback.core.rolling.SizeAndTimeBasedFNATP">
                <maxFileSize>100MB</maxFileSize>
            </timeBasedFileNamingAndTriggeringPolicy>
            <!--日志文档保留天数-->
            <maxHistory>15</maxHistory>
        </rollingPolicy>
        <!-- 此日志文档只记录info级别的 -->
        <filter class="ch.qos.logback.classic.filter.LevelFilter">
            <level>info</level>
            <onMatch>ACCEPT</onMatch>
            <onMismatch>DENY</onMismatch>
        </filter>
    </appender>

    <!-- 2.3 level为 WARN 日志，时间滚动输出  -->
    <appender name="WARN_FILE" class="ch.qos.logback.core.rolling.RollingFileAppender">
        <!-- 正在记录的日志文档的路径及文档名 -->
        <file>${logging.path}/web_warn.log</file>
        <!--日志文档输出格式-->
        <encoder>
            <pattern>%d{yyyy-MM-dd HH:mm:ss.SSS} [%thread] %-5level %logger{50} - %msg%n</pattern>
            <charset>UTF-8</charset> <!-- 此处设置字符集 -->
        </encoder>
        <!-- 日志记录器的滚动策略，按日期，按大小记录 -->
        <rollingPolicy class="ch.qos.logback.core.rolling.TimeBasedRollingPolicy">
            <fileNamePattern>${logging.path}/web-warn-%d{yyyy-MM-dd}.%i.log</fileNamePattern>
            <timeBasedFileNamingAndTriggeringPolicy
                    class="ch.qos.logback.core.rolling.SizeAndTimeBasedFNATP">
                <maxFileSize>100MB</maxFileSize>
            </timeBasedFileNamingAndTriggeringPolicy>
            <!--日志文档保留天数-->
            <maxHistory>15</maxHistory>
        </rollingPolicy>
        <!-- 此日志文档只记录warn级别的 -->
        <filter class="ch.qos.logback.classic.filter.LevelFilter">
            <level>warn</level>
            <onMatch>ACCEPT</onMatch>
            <onMismatch>DENY</onMismatch>
        </filter>
    </appender>

    <!-- 2.4 level为 ERROR 日志，时间滚动输出  -->
    <appender name="ERROR_FILE" class="ch.qos.logback.core.rolling.RollingFileAppender">
        <!-- 正在记录的日志文档的路径及文档名 -->
        <file>${logging.path}/web_error.log</file>
        <!--日志文档输出格式-->
        <encoder>
            <pattern>%d{yyyy-MM-dd HH:mm:ss.SSS} [%thread] %-5level %logger{50} - %msg%n</pattern>
            <charset>UTF-8</charset> <!-- 此处设置字符集 -->
        </encoder>
        <!-- 日志记录器的滚动策略，按日期，按大小记录 -->
        <rollingPolicy class="ch.qos.logback.core.rolling.TimeBasedRollingPolicy">
            <fileNamePattern>${logging.path}/web-error-%d{yyyy-MM-dd}.%i.log</fileNamePattern>
            <timeBasedFileNamingAndTriggeringPolicy
                    class="ch.qos.logback.core.rolling.SizeAndTimeBasedFNATP">
                <maxFileSize>100MB</maxFileSize>
            </timeBasedFileNamingAndTriggeringPolicy>
            <!--日志文档保留天数-->
            <maxHistory>15</maxHistory>
        </rollingPolicy>
        <!-- 此日志文档只记录ERROR级别的 -->
        <filter class="ch.qos.logback.classic.filter.LevelFilter">
            <level>ERROR</level>
            <onMatch>ACCEPT</onMatch>
            <onMismatch>DENY</onMismatch>
        </filter>
    </appender>





    <!--
      <logger>用来设置某一个包或者具体的某一个类的日志打印级别、
      以及指定<appender>。<logger>仅有一个name属性，
      一个可选的level和一个可选的addtivity属性。
      name:用来指定受此logger约束的某一个包或者具体的某一个类。
      level:用来设置打印级别，大小写无关：TRACE, DEBUG, INFO, WARN, ERROR, ALL 和 OFF，
            还有一个特俗值INHERITED或者同义词NULL，代表强制执行上级的级别。
            如果未设置此属性，那么当前logger将会继承上级的级别。
      addtivity:是否向上级logger传递打印信息。默认是true。
      <logger name="org.springframework.web" level="info"/>
      <logger name="org.springframework.scheduling.annotation.ScheduledAnnotationBeanPostProcessor" level="INFO"/>
  -->

    <!--
        使用mybatis的时候，sql语句是debug下才会打印，而这里我们只配置了info，所以想要查看sql语句的话，有以下两种操作：
        第一种把<root level="info">改成<root level="DEBUG">这样就会打印sql，不过这样日志那边会出现很多其他消息
        第二种就是单独给dao下目录配置debug模式，代码如下，这样配置sql语句会打印，其他还是正常info级别：
        【logging.level.org.mybatis=debug logging.level.dao=debug】
     -->

    <!--
        root节点是必选节点，用来指定最基础的日志输出级别，只有一个level属性
        level:用来设置打印级别，大小写无关：TRACE, DEBUG, INFO, WARN, ERROR, ALL 和 OFF，
        不能设置为INHERITED或者同义词NULL。默认是DEBUG
        可以包含零个或多个元素，标识这个appender将会添加到这个logger。
    -->



    <!-- 4. 最终的策略 -->
    <!-- 4.1 开发环境:打印控制台-->
   <!-- <springProfile name="dev">
        <logger name="com.cic.analysis.business.dao" level="debug"/>&lt;!&ndash; 修改此处扫描包名 &ndash;&gt;
    </springProfile>-->

    <!--
        root指定最基础的日志输出级别，level属性指定
        appender-ref标识的appender将会添加到这个logger
    -->
    <root level="info">
        <appender-ref ref="CONSOLE"/>
        <appender-ref ref="DEBUG_FILE"/>
        <appender-ref ref="INFO_FILE"/>
        <appender-ref ref="WARN_FILE"/>
        <appender-ref ref="ERROR_FILE"/>
    </root>

    <!-- 4.2 生产环境:输出到文档
    <springProfile name="pro">
        <root level="info">
            <appender-ref ref="CONSOLE" />
            <appender-ref ref="DEBUG_FILE" />
            <appender-ref ref="INFO_FILE" />
            <appender-ref ref="ERROR_FILE" />
            <appender-ref ref="WARN_FILE" />
        </root>
    </springProfile> -->

</configuration>
```


# Spring Boot 中的三种常用使用方式
```java
import lombok.extern.slf4j.Slf4j;
// 注意: SpringBoot 集成了 Junit5 包名跟 Junit4 有很大区别
import org.junit.jupiter.api.Test;
// 方式1: 通过 Lombok 自动生成 Logger
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.test.context.SpringBootTest;

@SpringBootTest
// 通过 Lombok 自动生成 Logger
@Slf4j
class LogbackApplicationTests {
    // 通过 ClassName 生成 Logger
    private final static Logger log1 = LoggerFactory.getLogger(TestApplicationTests.class);
    // 手动输入名称生成 Logger
    private final static Logger log2 = LoggerFactory.getLogger("ztrue");

    @Test
    void loggerGenerateTest() {
        log.info("Log generate by Lombok");
        log1.info("Log generate by class name");
        log2.info("Log generate by Lombok");
    }
}
```

输出日志

```log
2021-02-08 20:50:23.509  INFO 4388 --- [           main] com.ztrue.test.TestApplicationTests      : Log generate by Lombok
2021-02-08 20:50:23.509  INFO 4388 --- [           main] com.ztrue.test.TestApplicationTests      : Log generate by class name
2021-02-08 20:50:23.509  INFO 4388 --- [           main] ztrue                                    : Log generate by Lombok
```

# Spring Boot 日志级别的调用
```log
@Slf4j
class TestApplicationTests {
	@Test
	void logLevelTest() {
		log.debug("DEBUG log");
		log.info("INFO log");
		log.warn("WARN log");
		log.error("ERROR log");
	}
}
```

输出日志
```log
2021-02-08 21:34:05.508  INFO 8088 --- [           main] com.ztrue.test.TestApplicationTests      : INFO log
2021-02-08 21:34:05.508  WARN 8088 --- [           main] com.ztrue.test.TestApplicationTests      : WARN log
2021-02-08 21:34:05.508 ERROR 8088 --- [           main] com.ztrue.test.TestApplicationTests      : ERROR log
```
