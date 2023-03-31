---
title: Synchronized锁升级原理-Java多线程(三)  
tags: Synchronized  
date: 2021/3/2  
categories:
- Java
- 多线程
keywords: [Java,多线程,Synchronized,锁升级,原理]  
description: Synchronized锁升级原理-Java多线程(三)
---
Synchronized 是 Java 中的关键字, 是利用锁的机制来实现同步的. 是Java内置的机制, 是JVM层面的. JDK 1.6 以前synchronized 关键字只表示重量级锁.  
在 JDK 1.6 开始 ,对锁的实现引入了大量的优化, 如自旋锁、适应性自旋锁、锁消除、锁粗化、偏向锁、轻量级锁等技术来减少锁操作的开销 
<!-- more -->

# 锁升级流程
原图出自水印
![](sync-up-level-process.png)

# 前置知识
## 锁的特性
### 原子性
锁是通过互斥保障原子性的. 所谓互斥, 就是指一个锁一次只能被一个线程持有
### 可见性
锁的获得会隐含地包含刷新处理器缓存这个动作, 这使得读线程在执行临界区代码前(获得锁后)可以将写线程对共享变量所做的更新同步到该线程执行处理器高速缓存中. 而锁的释放也同样隐含着刷新处理器缓存这个动作, 这使得写线程对共享变量所做的更新能够即时更新到该线程执行处理器的高速缓存中, 从而对读线程可同步
### 有序性
读线程无法(也无必要)区分写线程实际上是以什么顺序更新共享变量的, 因此读线程可以认为写线程依照源代码顺序更新了上述共享变量

## Java对象头
这部分知识可以移步下面的文章, 有很详细的介绍: 
{% post_link java-object-layout %}  

笔者将 64 位 JVM 中 Java 对象的 mark word 内存布局贴在下方, 以便大家查看  
![](hotspot-sync-obj-layout.png) 
`注意: `synchronized 锁升级的本质就是对 mark word 进行操作

# 锁升级过程
## 无锁态 (new)
无锁态就是 new Object. 一个对象刚被实例化的时候一定是无锁态的. 这种状态下, 所有线程都可以对这个对象进行访问并同时修改同一个资源. 也就会有线程不安全的问题.

## 偏向锁
当我们为无锁态对象加了一个 synchronized 关键字后, 被第一个线程访问后, 便会将偏向锁标志位从 0 变成 1, 并同时将 mark word 中原先记录 hashcode 的记录抹掉, 改为这个线程的指针. 这样就完成了偏向锁升级.  
从 mark word 内存分布中我们可以看到还有个 Epoch 这个涉及到优化中的优化, 跟本节关系不大. 以后再展开讨论.

## 轻量级锁
也称: 自旋锁, 无锁等. 当有 A B 两个线程同时访问一个锁对象后. 未竞争到偏向的线程 A 在比对 54 位线程指针时发现, 当前记录的不是自己的线程. 此时进行锁升级. 首先 JVM 会启动撤销偏向锁操作, 并等到将竞争到锁 A 的线程运行到安全点的时候, 将其挂起. 然后撤销锁对象的偏向锁相关记录, 也就是 mark word 内存分布中的前 62 位抹掉. 由于之前参与竞争的 A B 线程的线程栈中的有能唯一标识自己线程的 Lock Record 对象, 便将 B (竞争到的线程) 中的 Lock Record 指针贴到之前抹掉的 62 位上. 再将最后两位锁标志位改为 00. 做完这些后将 B 线程唤醒, 继续执行同步代码块的运算.  

## 重量级锁
在 JVM 缺省条件下, 某轻量级锁自旋次数超过 10 次或自旋的线程超过 CPU 核数的 1/2 则升级重量级锁. 由于这个操作需要向 linux 操作系统申请`内核态`操作 mutex, 线程被挂起, 进入等待队列, 等待操作系统调度后将 mutex 指针返回`用户态`空间. 然后 JVM 再将 mark word 中的标记改为 mutex 指针. 并将锁标记位修改为 10

# synchronized 锁对象的原理
先实现简单的由 synchronized 修饰的同步代码块
```java
public class SyncCodeBlock {

   public int i;

   public void syncTask(){
       //同步代码库
       synchronized (this){
           i++;
       }
   }
}
```
编译上述代码, 并使用javap反编译得到字节码如下: 
```log
  Last modified 2017-6-2; size 426 bytes
  MD5 checksum c80bc322c87b312de760942820b4fed5
  Compiled from "SyncCodeBlock.java"
public class com.zejian.concurrencys.SyncCodeBlock
  minor version: 0
  major version: 52
  flags: ACC_PUBLIC, ACC_SUPER
Constant pool:
  //........省略常量池中数据
  //构造函数
  public com.zejian.concurrencys.SyncCodeBlock();
    descriptor: ()V
    flags: ACC_PUBLIC
    Code:
      stack=1, locals=1, args_size=1
         0: aload_0
         1: invokespecial #1                  // Method java/lang/Object."<init>":()V
         4: return
      LineNumberTable:
        line 7: 0
  //===========主要看看syncTask方法实现================
  public void syncTask();
    descriptor: ()V
    flags: ACC_PUBLIC
    Code:
      stack=3, locals=3, args_size=1
         0: aload_0
         1: dup
         2: astore_1
         3: monitorenter  //注意此处, 进入同步方法
         4: aload_0
         5: dup
         6: getfield      #2             // Field i:I
         9: iconst_1
        10: iadd
        11: putfield      #2            // Field i:I
        14: aload_1
        15: monitorexit   //注意此处, 退出同步方法
        16: goto          24
        19: astore_2
        20: aload_1
        21: monitorexit //注意此处, 退出同步方法
        22: aload_2
        23: athrow
        24: return
      Exception table:
      //省略其他字节码.......
}
SourceFile: "SyncCodeBlock.java"
```

我们主要关注字节码中的如下代码：
```log
3: monitorenter  //进入同步方法
//..........省略其他  
15: monitorexit   //退出同步方法
16: goto          24
//省略其他.......
21: monitorexit //退出同步方法
```

从字节码中可知同步语句块的实现使用的是 monitorenter 和 monitorexit 指令, 其中 monitorenter 指令指向同步代码块的开始位置, monitorexit 指令则指明同步代码块的结束位置, 当执行 monitorenter 指令时, 当前线程将试图获取对象锁(objectref)所对应的 monitor 的持有权, 当对象锁的 monitor 的进入计数器为 0, 那线程可以成功取得 monitor, 并将计数器值设置为 1, 取锁成功. 如果当前线程已经拥有对象锁的 monitor 的持有权, 那它可以重入这个 monitor, 重入时计数器的值也会加 1. 倘若其他线程已经拥有对象锁的 monitor 的所有权, 那当前线程将被阻塞, 直到正在执行线程执行完毕, 即 monitorexit 指令被执行, 执行线程将释放 monitor(锁)并设置计数器值为0 , 其他线程将有机会持有 monitor . 值得注意的是编译器将会确保无论方法通过何种方式完成, 方法中调用过的每条 monitorenter 指令都有执行其对应 monitorexit 指令, 而无论这个方法是正常结束还是异常结束. 为了保证在方法异常完成时 monitorenter 和 monitorexit 指令依然可以正确配对执行, 编译器会自动产生一个异常处理器, 这个异常处理器声明可处理所有的异常, 它的目的就是用来执行 monitorexit 指令. 从字节码中也可以看出多了一个monitorexit指令, 它就是异常结束时被执行的释放monitor 的指令. 

# synchronized 锁方法的原理
先实现简单的由 synchronized 修饰的同步方法
```java
public class SyncMethod {

   public int i;

   public synchronized void syncTask(){
           i++;
   }
}
```
反编译后的字节码如下：
```log
  Last modified 2017-6-2; size 308 bytes
  MD5 checksum f34075a8c059ea65e4cc2fa610e0cd94
  Compiled from "SyncMethod.java"
public class com.zejian.concurrencys.SyncMethod
  minor version: 0
  major version: 52
  flags: ACC_PUBLIC, ACC_SUPER
Constant pool;

   //省略没必要的字节码
  //==================syncTask方法======================
  public synchronized void syncTask();
    descriptor: ()V
    //方法标识ACC_PUBLIC代表public修饰, ACC_SYNCHRONIZED指明该方法为同步方法
    flags: ACC_PUBLIC, ACC_SYNCHRONIZED
    Code:
      stack=3, locals=1, args_size=1
         0: aload_0
         1: dup
         2: getfield      #2                  // Field i:I
         5: iconst_1
         6: iadd
         7: putfield      #2                  // Field i:I
        10: return
      LineNumberTable:
        line 12: 0
        line 13: 10
}
SourceFile: "SyncMethod.java"
```
从字节码中可以看出, synchronized 修饰的方法并没有 monitorenter 指令和 monitorexit 指令, 取得代之的其实是 ACC_SYNCHRONIZED 标识, 该标识指明了该方法是一个同步方法, JVM 通过该 ACC_SYNCHRONIZED 访问标志来辨别一个方法是否声明为同步方法, 从而执行相应的同步调用. 

# 总结
了解了那么多, 其实 synchronized 的实现可以分为以下几层理解:
- 第一层: java 代码中使用 synchronized 关键字
- 第二层: 字节码文件中标记 monitorenter monitorexit 来控制加锁释放锁
- 第三层: 执行过程中自动升级(new-偏向锁-轻量级锁-重量级锁-GC)
- 第四层: JVM 调用 Atomic 中的方法, 并使用汇编指令 lock cmpxchg