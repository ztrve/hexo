---
title: Interrupt中断线程-Java多线程(五)  
tags: Interrupt  
date: 2021/3/14  
categories:
- Java
- 多线程
keywords: [Java,多线程,Interrupt]  
description: Interrupt中断线程-Java多线程
---
Interrupt 的其作用是"中断"线程, 但实际上线程仍会继续运行, 这是一个非常容易混淆的概念. Interrupt 的真正作用是给线程对象设置一个中断标记, 并不会影响线程的正常运行
<!-- more -->

# 测试代码
> https://gitee.com/zture/spring-test/blob/master/multithreading/src/test/java/cn/diswares/blog/InterruptTests.java

## 测试
为了方便理解简介中 interrupt 的概念, 写个 DEMO 测试一下
```java
    /**
 * 调用 interrupt 并不会影响线程正常运行
 */
@Test
public void testInvokeInterrupt() throws InterruptedException {
    Thread t1 = new Thread(() -> {
    for (int i = 0; ; i++) {
    log.info(i + "");
    }
    });
    t1.start();
    // 确保 t1.start() 成功执行
    Thread.sleep(1);
    log.info("interrupt 前 t1 interrupt 状态 = {}", t1.isInterrupted());
    t1.interrupt();
    log.info("interrupt 后 t1 interrupt 状态 = {}", t1.isInterrupted());
    log.info("t1 是否存活 = {}", t1.isAlive());
}
```

## 执行过程描述
- 首先 main 线程中启动 t1 线程
- t1 线程死循环输出 i++
- main 线程确保 t1.start() 执行后
- 打印 t1 线程的线程中断状态
- 调用 t1.interrupt() 方法使线程中断
- 打印 t1 线程的线程中断状态

## 输出日志
```
ignore logs ......
20:29:57.632 [Thread-1] INFO cn.diswares.blog.interrupt.InterruptTests - 2561
20:29:57.633 [Thread-1] INFO cn.diswares.blog.interrupt.InterruptTests - 2562
20:29:57.633 [Thread-1] INFO cn.diswares.blog.interrupt.InterruptTests - 2563
20:29:57.486 [main] INFO cn.diswares.blog.interrupt.InterruptTests - interrupt 前 t1 interrupt 状态 = false
20:29:57.633 [Thread-1] INFO cn.diswares.blog.interrupt.InterruptTests - 2564
20:29:57.633 [Thread-1] INFO cn.diswares.blog.interrupt.InterruptTests - 2565
20:29:57.633 [Thread-1] INFO cn.diswares.blog.interrupt.InterruptTests - 2566
20:29:57.633 [Thread-1] INFO cn.diswares.blog.interrupt.InterruptTests - 2567
20:29:57.633 [Thread-1] INFO cn.diswares.blog.interrupt.InterruptTests - 2568
20:29:57.633 [main] INFO cn.diswares.blog.interrupt.InterruptTests - interrupt 后 t1 interrupt 状态 = true
20:29:57.633 [main] INFO cn.diswares.blog.interrupt.InterruptTests - t1 是否存活 = true
20:29:57.633 [Thread-1] INFO cn.diswares.blog.interrupt.InterruptTests - 2569
20:29:57.633 [Thread-1] INFO cn.diswares.blog.interrupt.InterruptTests - 2570
20:29:57.633 [Thread-1] INFO cn.diswares.blog.interrupt.InterruptTests - 2571
ignore logs ......
```

## 现象描述
- 调用 t1.interrupt() 执行前线程的 interrupt 状态为 false
- 调用 t1.interrupt() 执行后线程的 interrupt 状态为 true
- 线程并没有被中断, 可以成功死循环输出循环次数

## 结论
Interrupt 的真正作用是给线程对象设置一个中断标记, 并不会影响线程的正常运行

# 主要方法释义
## new Thread().interrupt()
中断此线程（此线程不一定是当前线程，而是指调用该方法的Thread实例所代表的线程），但实际上只是给线程设置一个中断标志，线程仍会继续运行。

## Thread.interrupted()
`注意: 这是个静态方法`    
测试当前线程是否被中断(检查中断标志), 返回一个当前线程的 interrupt 状态, 并重置.  
当我们第二次调用时中断状态已经被重置, 将返回一个false  
为了方便理解. 写一个 DEMO

### DEMO
DEMO 非常简单, 调用两次 Thread.interrupted() 观察 main 线程的 interrupt 标记
```java
/**
 * 二次调用 t1.interrupted()
 */
@Test
public void testDoubleInvokeInterrupted () throws InterruptedException {
    Thread.currentThread().interrupt();
    log.info("interrupted1 = {}", Thread.interrupted());
    log.info("interrupted2 = {}", Thread.interrupted());
}
```

### 输出日志
```
21:06:33.397 [main] INFO cn.diswares.blog.interrupt.InterruptTests - interrupted1 = true
21:06:33.402 [main] INFO cn.diswares.blog.interrupt.InterruptTests - interrupted2 = false
```

### 拓展程序
由于是静态方法. 我们来看一下另一个小程序.
- 跟之前一样将 t1 程序中断
- 调用 t1.interrupted()
- 注意这里是个静态方法
```java
/**
 * 在主线程中调用 t1.interrupted()
 */
@Test
public void testMainInterrupted() throws InterruptedException {
    Thread t1 = new Thread(() -> {
        for (int i = 0; ; i++) {
            log.info("t1 is live");
        }
    });

    t1.start();
    Thread.sleep(1);
    t1.interrupt();
    Thread.sleep(1);
    log.info("{}", t1.interrupted());
}
```

### 拓展程序日志
```log
ignore logs ......
21:11:20.504 [Thread-1] INFO cn.diswares.blog.interrupt.InterruptTests - t1 is live
21:11:20.504 [Thread-1] INFO cn.diswares.blog.interrupt.InterruptTests - t1 is live
21:11:20.490 [main] INFO cn.diswares.blog.interrupt.InterruptTests - false
21:11:20.504 [Thread-1] INFO cn.diswares.blog.interrupt.InterruptTests - t1 is live
21:11:20.504 [Thread-1] INFO cn.diswares.blog.interrupt.InterruptTests - t1 is live
21:11:20.504 [Thread-1] INFO cn.diswares.blog.interrupt.InterruptTests - t1 is live
ignore logs ......
```

### 拓展程序结论
- Thread.interrupted() 方法是静态方法
- 它的实现为 Thread.currentThread(), 获取的是当前正在执行的线程, JDK 原文注释如下:
  - Returns a reference to the currently executing thread object.
  - Returns: the currently executing thread.
- 所以这里 t1.interrupted() 返回的其实是 main 线程的线程中断标记



## new Thread().isInterrupted()
返回线程对象的中断标记, 不会改变中断标记
- true: 中断标记存在
- false: 未设置中断标记状态

# 优雅的结束一个线程
在 Java 中结束一个线程一般有下面三种手段:
- (禁用) Thread.stop() 这个方法已经被废弃. 因为这种结束线程的方式过于暴力. 会将当前线程暴力终结. 同时线程持有的锁也都会释放, 并且用户有任何额外的处理来控制, 会导致数据不一致
- volatile: 外部申明 volatile 开关变量, 当开关条件不满足时结束
- (推荐) interrupt: 最优雅的方案


## 实战
最初的 DEMO 是个死循环, 那我们对其改造一下. 让它能够优雅的结束

```java
/**
 * 调用 interrupt 并不会影响线程正常运行
 */
@Test
public void testGracefulEndThread() throws InterruptedException {
    Thread t1 = new Thread(() -> {
        for (int i = 0; ; i++) {
            if (Thread.currentThread().isInterrupted()) {
                log.info("{} = true, i = {}", Thread.currentThread().getName(), i);
                break;
            } else {
                log.info("{} = false, i = {}", Thread.currentThread().getName(), i);
            }
        }
    });
    t1.start();
    // 确保 t1.start() 成功执行
    TimeUnit.SECONDS.sleep(1);
    t1.interrupt();
    TimeUnit.SECONDS.sleep(1);
    log.info(t1.getState().toString());
}
```
