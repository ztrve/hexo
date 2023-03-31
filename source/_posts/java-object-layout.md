---
title: Java对象头内存布局-Java底层(一)  
tags: 对象头内存布局  
date: 2021/2/26  
categories:
- Java
keywords: [Java,对象,内存布局,底层]  
description: Java对象的内存布局-Java底层(一)

---
今天来讲些抽象的东西对象头，JDK 中的 synchronized 锁优化和 JVM 中对象年龄升级等等。要深入理解这些知识的原理，了解对象头的概念很有必要
<!-- more -->

# 对象内存构成

Java 中通过 new 关键字创建一个类的实例对象，对象存于内存的堆中并给其分配一个内存地址
![](new-object.png)

在 JVM 中，Java 对象保存在堆中时，由以下三部分组成：

- 对象头(object header): 包括了关于堆对象的布局、类型、GC状态、同步状态和标识哈希码的基本信息。Java 对象和 JVM 内部对象都有一个共同的对象头格式
- 实例数据(instance data): 主要是存放类的数据信息，父类的信息，对象字段属性信息
- 对齐填充(padding): 为了字节对齐，填充的数据

![](object-layout.png)

# 对象头(object header)

我们可以在Hotspot官方文档中找到它的描述(下图)。从中可以发现，它是 Java 对象和虚拟机内部对象都有的共同格式，由两个词组成。另外，如果对象是一个 Java
数组，那在对象头中还必须有一块用于记录数组长度的数据，因为虚拟机可以通过普通 Java 对象的元数据信息确定 Java 对象的大小，但是从数组的元数据中无法确定数组的大小
![](object-header-desc.png)

它里面提到了对象头由两个字组成，这两个字就是: klass header, mark word  
![](two-words-desc.png)

## Mark Word

用于存储对象自身的运行时数据，如哈希码（HashCode）、GC分代年龄、锁状态标志、线程持有的锁、偏向线程ID、偏向时间戳等等。

Mark Word在 32 位 JVM 中的长度是 32 bit，在 64 位 JVM 中长度是 64bit 。我们打开 Openjdk 的源码包，对应路径 '/openjdk/hotspot/src/share/vm/oops',
Mark Word 对应到 C++ 的代码 markOop.hpp，可以从注释中看到它们的组成，本文所有代码是基于Jdk1.8  
![](hotspot-object-layout.png)

Mark Word 在不同的锁状态下存储的内容不同  
在 32 位 JVM 中的布局
![](jvm-32bit-object-layout.png)

在 64 位 JVM 中的布局
![](jvm-64bit-object-layout.png)

虽然它们在不同位数的JVM中长度不一样，但是基本组成内容是一致的。

## Klass Pointer

Klass 指针: 是对象指向它的类元数据的指针，JVM 通过这个指针来确定这个对象是哪个类的实例。

# 实例数据(instance data)

如果对象有属性(成员)，则这里会有数据信息。如果对象无属性字段，则这里就不会有数据 根据字段类型的不同占不同的字节，例如boolean类型占 1 字节，int类型占 4 字节等等, 一个 Java 对象的地址占 4 字节

# 对齐填充(padding)

对象可以有对齐数据也可以没有。缺省情况下，JVM 堆中对象的起始地址需要对齐至 8 的倍数. 如果一个对象用不到 8N 个字节则需要对其填充。如果对象头和实例数据已经占满了 JVM 所分配的内存空间，那么就不用再进行对齐填充了  
字段内存对齐的其中一个原因，是让字段只出现在同一 CPU
的缓存行中。如果字段不是对齐的，那么就有可能出现跨缓存行的字段。也就是说，该字段的读取可能需要替换两个缓存行，而该字段的存储也会同时污染两个缓存行。这两种情况对程序的执行效率而言都是不利的。其实对其填充的最终目的是为了计算机高效寻址

# 对象整体结构布局

至此，我们已经了解了对象在堆内存中的整体结构布局，如下图所示

![](object-layout2.png)

# 校验理论

## 引入依赖

openjdk 给我们提供了一个工具包，可以用来获取对象的信息和虚拟机的信息，首先引入 jol-core 依赖

```xml
<dependency>
    <groupId>org.openjdk.jol</groupId>
    <artifactId>jol-core</artifactId>
    <version>0.9</version>
</dependency>
```

## 校验空对象的内存布局

1. 打印空对象在内存中的布局

```java
public void testEmptyObject(){
        log.info("print empty object layout");
        Object o=new Object();
        System.out.println(ClassLayout.parseInstance(o).toPrintable());
        }
```

2. 控制台输出

```log
00:03:47.188 [main] INFO cn.diswares.blog.MarkWordTests - print empty object layout
java.lang.Object object internals:
 OFFSET  SIZE   TYPE DESCRIPTION                               VALUE
      0     4        (object header)                           01 00 00 00 (00000001 00000000 00000000 00000000) (1)
      4     4        (object header)                           00 00 00 00 (00000000 00000000 00000000 00000000) (0)
      8     4        (object header)                           e5 01 00 f8 (11100101 00000001 00000000 11111000) (-134217243)
     12     4        (loss due to the next object alignment)
Instance size: 16 bytes
Space losses: 0 bytes internal + 4 bytes external = 4 bytes total
```

3. 日志中表格 column 的含义如下:

- OFFSET: 偏移量
- SIZE: 大小, 单位 bit
- TYPE DESCRIPTION: 类型描述，其中object header为对象头
- value: 对应内存中当前存储的值

4. 对照 console log 来印证一下之前的理论:

- [0-8] mark word
- [9-12] klass pointer
- [13-16] padding

## 校验包含单个成员的对象的内存布局

1. 打印包含单个成员的对象在内存中的布局

```java
public void testSingleMemberObject(){
        log.info("print single member object layout");
        SingleMemberDO singleMemberDO=new SingleMemberDO();
        System.out.println(ClassLayout.parseInstance(singleMemberDO).toPrintable());
        }
```

2. 控制台输出

```log
00:03:49.706 [main] INFO cn.diswares.blog.MarkWordTests - print single member object layout
cn.diswares.blog.entity.SingleMemberDO object internals:
 OFFSET  SIZE               TYPE DESCRIPTION                               VALUE
      0     4                    (object header)                           01 00 00 00 (00000001 00000000 00000000 00000000) (1)
      4     4                    (object header)                           00 00 00 00 (00000000 00000000 00000000 00000000) (0)
      8     4                    (object header)                           fe 2f 03 f8 (11111110 00101111 00000011 11111000) (-134008834)
     12     4   java.lang.String SingleMemberDO.foo                        (object)
Instance size: 16 bytes
Space losses: 0 bytes internal + 0 bytes external = 0 bytes total
```

3. 对照 console log 来印证一下之前的理论:

- [0-8] mark word
- [9-12] klass pointer
- [13-16] member address

## 不同的 JVM 运行参数中 

可以看到 klass pointer 是 4 个字节. 在 64 位的 JVM 中, 按道理应该是 8 个字节. 但是 JVM 在缺省情况下是开启 +UseCompressedClassPointers 和 +UseCompressedOops 这两个参数的.
```shell
>java -XX:+PrintCommandLineFlags -version

-XX:InitialHeapSize=267392448 -XX:MaxHeapSize=4278279168 -XX:+PrintCommandLineFlags -XX:+UseCompressedClassPointers -XX:+UseCompressedOops -XX:-UseLargePagesIndividualAllocation -XX:+UseParallelGC
java version "1.8.0_281"
Java(TM) SE Runtime Environment (build 1.8.0_281-b09)
Java HotSpot(TM) 64-Bit Server VM (build 25.281-b09, mixed mode)

```


并且 +UseCompressedClassPointers 必须依赖 +UseCompressedOops.
一起来看一下开启这些参数, 一个普通 Object 对象在内存中占用内存是怎样的. 下表单位: byte

|  VM param                    | desc                | 内存  | 堆    | Object  | mark word  | klass pointer  | member  | padding  |
|:----------------------------:|:-------------------:|:-----:|:-----:|:------:|:-----------:|:--------------:|:-------:|:--------:|
| -UseCompressedOops           | 关闭普通对象指针压缩 | 24    | 8     | 16      | 8          | 8              | 0       | 0        |
| +UseCompressedOops           | 开启普通对象指针压缩 | 20    | 4     | 16      | 8          | 4              | 0       | 4        |
| -UseCompressedClassPointers  | 关闭类指针压缩       | 20    | 4     | 16      | 8          | 4              | 0       | 4        |
| +UseCompressedClassPointers  | 开启类指针压缩       | 20    | 4     | 16      | 8          | 4              | 0       | 4        |
