---
title: AQS核心原理介绍-Java多线程(七)   
tags: AQS  
date: 2021/4/12     
categories:
- Java
- 多线程  
keywords: [Java,多线程,AQS,AbstractQueuedSynchronizer,源码解析]  
description: AQS核心原理介绍-Java多线程(七)
---
AQS (AbstractQueuedSynchronizer) 抽象的队列同步器是 JUC 中的重要实现. AQS 定义了一套多线程访问共享资源的同步器框架, JUC 中许多经典的同步器实现都是基于 AQS 实现. AQS 内部维护了两种隐式的队列: 阻塞队列和条件队列.   
由于 AQS 实现较为复杂, 这里打算分成三个章节(核心原理, 阻塞队列, 条件队列)为大家介绍, 以便吃透 AQS 的底层原理. 本章为大家介绍的是第一部分核心原理介绍.

<!-- more -->
# 前置知识
AQS 的实现较为复杂, 在学习前希望大家先理解多线程中一些术语, 方便阅读理解
- CLH
- 可重入锁
- LockSupport
- 公平锁和非公平锁
- 独占锁和共享锁
- 自旋锁 CAS ABA
- volatile

> 锁的概念: https://blog.csdn.net/weixin_44624375/article/details/110133306  
> CLH锁: http://blog.diswares.cn/java-multithreading-cas-aba/  
> CAS ABA: http://blog.diswares.cn/tags/CAS/  
> Volatile: http://blog.diswares.cn/java-multithreading-volatile/
# AQS 简介
AQS提供了一种实现阻塞锁和一系列依赖FIFO等待队列的同步器的框架. AQS为一系列同步器依赖于一个单独的原子变量 state 的同步器提供了一个非常有用的基础, 所有子类都要通过控制 state 来实现锁.  
AQS同时提供了两种资源共享模式, 一般情况下子类同步器只需要实现其中的一种即可: 
- 互斥模式(exclusive) 
- 共享模式(shared) 


# 原子变量 state
![AQS原子变量State](aqs-state.webp)
AbstractQueuedSynchronizer 维护了一个 volatile int 类型的变量 state.  
用户可以根据自己的喜好定义 state 的抽象概念. 例如: ReentrantLock 中 state 就是锁的状态. 由于是可重入锁, 当 state > 0 时表示当前锁状态为被占用. 当 state == 0 时, 表示当前锁状态为无锁定状态.  
volatile 关键字保证了 state 变量的可见性, 虽然不能保证操作的原子性. 众所周知, 线程在执行时要将公共内存中存储的变量值, 读到本地线程栈, volatile 关键字的特性就是强制更新缓存并保证有序性. 
### state 的访问方式
state的访问方式有三种:
- getState()
- setState()
- compareAndSetState()

其中只有 compareAndSetState 方法是原子性的操作, getState 和 setState 均不能保证原子性.   
getState/setState 的使用场景是当前线程竞争到锁之后再进行锁状态的读取更新. 
compareAndSetState 的使用场景是在多线程竞争的情况下, 在自旋中进行 state 的原子性修改, 如果修改失败, 则继续自旋, 修改成功则退出自旋.

```java
/**
 * The synchronization state.
 */
private volatile int state;

/**
 * Returns the current value of synchronization state.
 * This operation has memory semantics of a {@code volatile} read.
 * @return current state value
 */
protected final int getState() {
        return state;
        }

/**
 * Sets the value of synchronization state.
 * This operation has memory semantics of a {@code volatile} write.
 * @param newState the new state value
 */
protected final void setState(int newState) {
        state = newState;
        }

/**
 * Atomically sets synchronization state to the given updated
 * value if the current state value equals the expected value.
 * This operation has memory semantics of a {@code volatile} read
 * and write.
 *
 * @param expect the expected value
 * @param update the new value
 * @return {@code true} if successful. False return indicates that the actual
 *         value was not equal to the expected value.
 */
protected final boolean compareAndSetState(int expect, int update) {
        // See below for intrinsics setup to support this
        return unsafe.compareAndSwapInt(this, stateOffset, expect, update);
        }
```

# 资源共享模式
AQS 的阻塞队列又定义两种资源共享模式: Exclusive(独占模式, 只有一个线程能执行, 如: ReentrantLock) 和 Share (共享模式, 多个线程可同时执行, 如 Semaphore/CountDownLatch).  
不同的自定义同步器争用共享资源的方式也不同. 自定义同步器在实现时只需要实现共享资源state的获取与释放方式即可, 至于具体线程等待队列的维护(如获取资源失败入队/唤醒出队等), AQS已经在顶层实现好了. 自定义同步器实现时主要实现以下几种方法(面试常考):
- isHeldExclusively(): 该线程是否正在独占资源. 只有用到condition才需要去实现它.
- tryAcquire(int): 独占方式. 尝试获取资源, 成功则返回true, 失败则返回false.
- tryRelease(int): 独占方式. 尝试释放资源, 成功则返回true, 失败则返回false.
- tryAcquireShared(int): 共享方式. 尝试获取资源. 负数表示失败；0表示成功, 但没有剩余可用资源；正数表示成功, 且有剩余资源.
- tryReleaseShared(int): 共享方式. 尝试释放资源, 如果释放后允许唤醒后续等待结点返回true, 否则返回false.


# 隐式队列
隐式队列分为两类, 分别是阻塞队列和等待队列(Condition), 阻塞队列是由 AQS 的`静态内部类` Node 实现的隐式队列. Node 的注释中声明了, 隐式队列是 CLH(Craig，Landin and Hagersten) 锁的变体实现.  

> CLH 锁是一种基于单项链表的高性能、公平的自旋锁方案。申请加锁的线程通过自旋前驱节点的锁状态来获取锁

AQS 并不是单纯的单项链表, 从下面的 Node 的成员中就可以看出他是一个双向链表. 
```java
static final class Node {
        volatile int waitStatus;
        volatile Node prev;
        volatile Node next;
        volatile Thread thread;
        // ...... Any final state object
        // ...... Any method
    }
```

但是阻塞队列的部分核心实现与 CLH 的思想是一致的, 那就是通过观察 prevNode 的 waitState 来判断自己是否可以竞争到锁. 只不过 AQS 在实现时进行了性能优化, 让它在多线程竞争的时候更节省 cpu 资源. 


> Java 源码注释对 Node 的释义  
> The wait queue is a variant of a "CLH" (Craig, Landin, and Hagersten) lock queue.
### 阻塞队列
阻塞队列, 又称同步队列. 是基于静态内部类 Node 实现的一种 CLH 变体队列. 网上很多入队出队流程描述的并不清晰, 正确的流程如下: 
![AQS阻塞队列流程](AQS-block-queue-processing.png)
1. 现有新节点 A (节点与线程一一对应, 可以理解为是一个意思)想要获取资源时, 通过 tryAcquire()/tryAcquireShared() 直接尝试获取, 如果可以, 则立即执行
2. 如果上述过程走不通, 则开启一个自旋
3. 自旋中, 将节点 A 加入隐式队列队尾, 
4. 并通过 LockSupport 休眠, 等待唤醒
5. 前置节点 B 释放资源后唤醒自己
6. 继续执行自旋, 如果竞争到资源, 则立即执行
7. 执行之后手动释放资源, 并唤醒下一个待执行的资源
8. 节点 A 被唤醒后, 与可能存在的新节点 C 再次竞争资源, 谁竞争成功谁就执行
9. 假设 step8 中 A 竞争失败了, 则 A 节点再次回到 step5
10. 假设 step8 中 C 竞争失败, 则 C 节点进入 step2 入队

### 等待队列
等待队列, 又称条件队列. 源码中是由内部类 ConditionObject 实现的. 进入这个队列需要满足以下条件:
- 当前节点竞争资源成功(拿到锁)
- 业务中需要等待其他线程执行完成

![AQS等待队列流程](AQS-condition.png)
具体流程如下:
- 当线程 A 执行 await(), 意味着当前节点一定持有阻塞队列资源
- 将当前节点 A 放入到等待队列队尾
- 之后把节点 A 持有的阻塞队列资源释放
- 阻塞队列中自然移除节点 A
- 节点 A 在等待队列中休眠
- 当线程 B 执行了 signal() 唤醒了节点 A
- 节点 A 进入上文[阻塞队列流程](#阻塞队列) step1