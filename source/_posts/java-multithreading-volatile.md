---
title: Volatile保证可见性的原理-Java多线程(四)  
tags: Volatile  
date: 2021/3/8  
categories:
- Java
- 多线程
keywords: [Java,多线程,volatile,原理]  
description: Synchronized锁升级原理-Java多线程(四)  

---
volatile可以保证线程可见性且提供了一定的有序性, 但是无法保证原子性. 在 JVM 规定 volatile 关键字执行的前后必须加上 `内存屏障`. 而真正的底层实现是 LOCK addl 指令锁总线 
<!-- more -->

# 小实验

> 测试项目地址:
> https://gitee.com/zture/spring-test/tree/master/multithreading/src/test/java/cn/diswares/blog

首先做一个小实验. 

## 小实验1
- 在一个类声明一个成员变量 a
- 线程 A 死循环读取读取 a 的值, 如果 a != 0 就打印输出
- 线程 B 等待 1 秒后将 a 的值修改掉
```java
package cn.diswares.blog;

/**
 * @author: ztrue
 * @date: 2021/3/8
 * @version: 1.0
 */
public class VolatileTests {
  private static int a = 0;
//    private static volatile int a = 0;

  public static void main(String[] args) throws InterruptedException {
    new Thread(() -> {
      while (true) {
        if (a != 0) {
          System.out.println(a);
          break;
        }
      }
    }).start();

    Thread.sleep(1000);
    a = 1;
  }

}
```

预期结果: 程序在 1 秒后就停止运行了
实际结果: 程序陷入死循环

## 小实验2
我们重新写一个测试代码, 这次为 a 变量加上 volatile 关键字, 其它不变
```java
//    private static int a = 0;
    private static volatile int a = 0;
```

执行一下, 观察日志发现程序已经停止了. 

## 原因
线程在运行的时候, 会将 a 的数据从内存中读取出来, copy 到线程的本地内存中去, volatile 关键字可以保证对象在不痛线程之间的可见性.  
那么为什么会有这种现象. 这必要知道 CPU 的工作模式, 及线程进程的基本概念

# 线程和进程的区别
线程: 分配资源的基本单位    
进程: 线程执行的基本单位

# CPU
## CPU 的重要组成
CPU 的组成为: 
- ALU: 算术逻辑单元, 进行复杂的数学运算
- Registers: 寄存器, 存储数据
- PC: 指令寄存器, 存储执行的指令地址
- CACHE: 缓存, 以多核 CPU 举例. 在一个 CPU 核心内一般有二级缓存, 在多个 CPU 核心间, 存在三级缓存

## CPU 工作流程
一个线程在被 CPU 执行前, 需要经过 公共内存 -> L3 cache -> L2 cache -> L1 cache. 然后 CPU 将指令地址放进 PC, data 放进 Registers, 再由 ALU 计算后, 将计算结果 从 Cache -> 公共内存返回.

# 缓存一致性
从 CPU 工作流程中可以发现, 如果一个变量在多个 CPU 中都存在缓存（一般在多线程编程时才会出现）, 那么就可能存缓存一致性问题. 

## 操作系统解决缓存一致性的方式
- 缓存一致性协议: MESI, 64 位核心可以解决 CPU 间 8 byte(缓存行大小)的缓存一致性问题
- 锁总线

# 系统底层保证有序性
- 内存屏障: sfence mfence lfence 等系统原语
- 锁总线

# volatile原理
- Java 层级: volatile i
- Byte Code: ACC_VOLATILE
- JVM 层级: 在 volatile 前后都得加内存屏障
- hotspot 实现: LOCK addl 指令, 锁总线
