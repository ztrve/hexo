---
title: CAS、ABA 问题讲解-Java多线程(一)  
tags: CAS  
date: 2021/2/14  
categories:
- Java
- 多线程
keywords: [Java,多线程,CAS,ABA]  
description: CAS、ABA问题讲解
---
Java 面试中必然会问到有关多线程方面的知识. 本文主要讲解多线程中的基础知识 CAS(Compare And Swap)机制和 ABA 问题.  
<!-- more -->

# CAS
## 介绍
CAS 全称 Compare And Swap, 顾名思义就是比较和改变的意思. 在 Java 中比较常用的实现有 synchronize 的轻量级锁(有的地方也称为无锁、自旋锁可重入锁)、`java.util.concurrent.atomic` 包下的 Atomic 家族. 这些实现之间有一个共性: 经常配合循环操作，直到完成为止. 

## 过程
所谓的 CAS 就是不停的计算. 具体的流程如下:  
![](cas-process.png)

其中 Step4 比较关键.  
这一步需要比较 A 与 C 的值相等. 如果相等, 则进行 swap value 操作. 否则, 就重入 Step1. 这个特性也就是`可重入锁`名称的由来.  
假设各线程对 value 的竞争异常激烈. 那么某一线程则会不停的重复 Step4 -> Step1 -> ... -> Step4 -> Step1 的过程就像一个不停旋转的环. 所以我们又称之为`自旋锁`  

# ABA问题
当流程进入 Step5 之前. 这里需要解决 ABA 问题.  
## 介绍
假设当前环境对内存中 value 的竞争非常的激烈. 我们现在观察的是线程1的流程, 那么在上述流程图 Step4 校验成功前. 内存中的 value 值先经过了线程2的计算变成了 D, 再由线程3的计算变成了E, 而 E 值与流程图中 C 值比较结果又恰好相等. 这就是 ABA问题    
如果你还是不太能理解这个问题. 或者不太能理解 ABA 问题会带来什么样的影响. 那么想象一下你的女朋友在跟你分手之后, 又经历了别的男人, 又跟你复合了.   
## 解决
解决这一问题也很简单, 只要我们在 value 值中根据修改次数加个版本号就可以解决.  


# 源码中的 CAS 与 ABA
以 AtomicInteger 为例. 找到 getAndIncrement() 方法. 这个方法类似于 'n++'
```java
package java.util.concurrent.atomic;

import sun.misc.Unsafe;

public class AtomicInteger extends Number implements java.io.Serializable {
    private static final Unsafe unsafe = Unsafe.getUnsafe();
    /**
     * Atomically increments by one the current value.
     * 以原子方式将当前值增加一
     *
     * @return the previous value
     */
    public final int getAndIncrement() {
        return unsafe.getAndAddInt(this, valueOffset, 1);
    }
}

```
可以看到底层是调用了 sun.misc.Unsafe 的 getAndSetInt() 方法. 继续跟踪 getAndAddInt(). AtomicInteger 解决 CAS 与 ABA 的方法为 compareAndSwapInt(). 由于是 native 方法需要跟踪 c++ 源码, 就放到下节展开
```java
package sun.misc;
public final class Unsafe {
    /**
     * Atomic家族几乎所有的原子性修改值方法基本都是类似
     * 
     * @param var1 流程图中 Step1 中 A 的值
     * @param var2 版本号
     * @param var4 参与计算的值
     * @return 修改后的值
     */
    public final int getAndAddInt(Object var1, long var2, int var4) {
        int var5;
        // do while 就是上文说的自旋模型
        do {
            // 这里等价 Step3 中的 C 值
            var5 = this.getIntVolatile(var1, var2);
            // this.compareAndSwapInt() 等价 Step4 加上 Step5. Hotspot源码下节会展开
            // this.compareAndSwapInt() 中的参数详细解释一下
            // var1 等价 Step1 中的 A
            // var2 等价 A 的版本号
            // var5 等价 Step4 中的 C
            // var5 + var4 等价 Step2 中的 B
        } while(!this.compareAndSwapInt(var1, var2, var5, var5 + var4));
        
        return var5;
    }
}
```