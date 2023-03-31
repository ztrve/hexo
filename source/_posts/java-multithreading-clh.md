---
title: CLH锁原理及实现-Java多线程(六)   
tags: CLH  
date: 2021/4/5
categories:
- Java
- 多线程  
keywords: [Java,多线程,CAS,ABA]  
description: CLH锁原理及实现-Java多线程(六)
---
CLH(Craig，Landin andHagersten)是一种基于单项链表的高性能、公平的自旋锁方案。申请加锁的线程通过自旋前驱节点的锁状态来获取锁。在 Java 中著名的 AQS(AbstractQueuedSynchronized) 就是它的其中一种实现。本节是为了更好的学习 AQS 的底层原理，而学习的前置知识。

<!-- more -->
# 服务器系统架构


在学习 CLH 之前, 我们首先需要补充一些服务器架构知识.  
从系统架构来看，目前的商用服务器大体可以分为三类，即对称多处理器结构(SMP：Symmetric Multi-Processor)，非一致存储访问结构(NUMA：Non-Uniform Memory Access)，以及海量并行处理结构(MPP：Massive Parallel Processing)。

> 摘自博文: https://blog.csdn.net/z136370204/article/details/104636110

## SMP对称多处理器结构
SMP(Symmetric Multi-Processor)对称多处理器结构. 是指服务器中多个CPU对称工作，无主次或从属关系。各CPU共享相同的物理内存，每个 CPU 访问内存中的任何地址所需时间是相同的，因此SMP也被称为一致存储器访问结构(UMA：Uniform Memory Access)。对SMP服务器进行扩展的方式包括增加内存、使用更快的CPU、增加CPU、扩充I/O(槽口数与总线数)以及添加更多的外部设备(通常是磁盘存储)。

## NUMA
![](NUMA.gif)
NUMA(Non-Uniform Memory Access)非一致存储访问结构. 它的基本特征是具有多个CPU模块，每个CPU模块由多个CPU(如4个)组成，并且具有独立的本地内存、I/O槽口等。由于其节点之间可以通过互联模块(如称为Crossbar Switch)进行连接和信息交互，因此每个CPU可以访问整个系统的内存(这是NUMA系统与MPP系统的重要差别)。显然，访问本地内存的速度将远远高于访问远地内存(系统内其它节点的内存)的速度，这也是非一致存储访问NUMA的由来。由于这个特点，为了更好地发挥系统性能，开发应用程序时需要尽量减少不同CPU模块之间的信息交互。利用NUMA技术，可以较好地解决原来SMP系统的扩展问题，在一个物理服务器内可以支持上百个CPU。比较典型的NUMA服务器的例子包括HP的Superdome、SUN15K、IBMp690等。


# CLH
CLH (Craig，Landin andHagersten)是一种基于单向链表的高性能、公平的自旋锁。申请加锁的线程通过前驱节点的变量进行自旋。在前置节点解锁后，当前节点会结束自旋，并进行加锁。在SMP架构下，CLH更具有优势。在NUMA架构下，如果当前节点与前驱节点不在同一CPU模块下，跨CPU模块会带来额外的系统开销，而MCS锁更适用于NUMA架构。  
## 核心
CLH 锁维护了一个隐式的线程队列, 这个队列由多个需要竞争锁资源的线程组成. 在并发情况下, 每个需要竞争锁的线程都会通过 CAS 操作有序的插入到队列的最末端, 并将之前最后的那个节点设置为自己的 prevNode. 随后, 自旋监听 prevNode 的锁状态, 当 prevNode 释放锁, 则认为自己竞争到了锁.  
解锁逻辑也很简单, 只需要将自己的锁状态修改为释放就可以了. 

## Node和锁标记
网上很多 CLH 图描述的都是很不清晰. 我们可以将每个线程都看成一个 Node. 每个 Node 都会维护三个基本信息, 前一个节点的内存地址, 当前节点的锁状态以及尾结点的内存地址. 那么 CLH 锁的工作流程应该是这样的.


![](CLH-node.png)

> 定义一个概念
> lock = true  表示 lock 所在的 Node 想要获取锁
> lock = false 表示 lock 所在的节点释放了锁资源

## 过程详解
### 线程1
1. 首先进来了一个线程1
2. 将线程1 封装成一个 Node1 过程如下
3. 由于 Node1 没有前置节点则: node1.prevNode = initNode() 初始化 Node 方法, 该 Node 的 lock 属性为 false
4. 由于 Node1 想要获取锁则: node1.lock = true
5. 利用 CAS 将 Node1 设置为尾节点: tail = node1
6. 并开启 Node1 的一个自旋, 当 node1.prevNode.lock == false 时, 结束自旋

### 线程2  
1. 这时候又进来了一个线程2想要获取锁
2. 将线程2封装成 Node2 过程如下
3. 由于在隐式队列中 Node2 之前已经有 Node1 了, 则: node2.prevNode = node1
4. 由于 Node2 也想要获取锁则: node2.lock = true
5. 利用 CAS 将 Node2 设置为尾节点: tail = node2
6. 并开启 Node1 的一个自旋, 当 node2.prevNode 也就是 node1 的 lock 属性为 false 时, 结束自旋

### 其他并发线程
其他线程模仿线程2的初始化方式, 不过需要保证, 在替换 tail 属性时, 必须是原子性的.

### 争抢锁 
1. 由于隐式队列满足先进先出的规则
2. 一定是线程1的自旋最先结束
3. 线程1 执行自己的业务代码
4. 线程1 释放锁: node1.lock 修改为 false
5. 线程2 发现 prevNode.lock == false 结束自旋, 也就是获得了锁
6. 线程2 获取锁
7. ........(重复 step5 & step6 直至隐式队列中所有线程执行完毕)

# CLH 源码实现
理论知识我们已经掌握了, 那么动手撸一个 CLH 锁吧  

并在 main 方法中开十个线程测试一下执行过程是否正确
## 源码
```java
package cn.diswares.blog.clh;

import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;
import java.util.concurrent.locks.Condition;
import java.util.concurrent.locks.Lock;

public class CLHLock implements Lock {
    private AtomicReference<Node> tail;

    private ThreadLocal<Node> prevNode;

    private ThreadLocal<Node> currentNode;

    public CLHLock() {
        // 初始化一个释放锁的节点, 当作当前隐式队列的尾结点
        this.tail = new AtomicReference<>(new Node());
        this.currentNode = ThreadLocal.withInitial(Node::new);
        this.prevNode = ThreadLocal.withInitial(() -> null);
    }

    @Override
    public void lock() {
        System.out.println(Thread.currentThread().getName() + " try lock");
        Node node = currentNode.get();
        node.locked = true;
        // 将 tail 中缓存的 node 拿出来赋值给 prev, 将 currentNode 放入 tail 中
        Node prev = tail.getAndSet(node);
        this.prevNode.set(prev);

        // 自旋判断上一个节点是否释放锁, 直至获取锁
        // locked == true  表示当前节点期望获取锁
        // lock   == false 表示当前节点已经释放锁
        // prev.locked == true  表示上一个节点未释放锁
        // prev.locked == false 表示上一个节点释放锁了, 也就意味着自己竞争到锁了
        while (prev.locked) {}
        System.out.println(Thread.currentThread().getName() + " get lock");
    }

    @Override
    public void unlock() {
        Node node = currentNode.get();
        node.locked = false; // 释放锁
        System.out.println(Thread.currentThread().getName() + " unlocked");
        this.currentNode.remove();
        this.prevNode.remove();
    }

    static class Node {
        volatile boolean locked;
    }

    public static void main(String[] args) {
        final Lock lock = new CLHLock();

        for (int i = 0; i < 10; i++) {
            new Thread(() -> {
                try {
                    lock.lock();
                    Thread.sleep(500);
                } catch (InterruptedException ignored) {
                } finally {
                    lock.unlock();
                }
            }).start();
        }
    }

    @Override
    public void lockInterruptibly() {

    }

    @Override
    public boolean tryLock() {
        return false;
    }

    @Override
    public boolean tryLock(long time, TimeUnit unit) {
        return false;
    }

    @Override
    public Condition newCondition() {
        return null;
    }
}
```

## 执行结果
从日志中可以看到开始时 Thread-0 和 Thread-2 发生了竞争  
Thread-0 还是成功抢到了锁, 然后 Thread-2 进入了自旋  
由于隐式队列的先进先出, 下一个拿到锁的必定是 Thread-2 
```
Thread-0 try lock
Thread-2 try lock
Thread-0 get lock
Thread-1 try lock
Thread-3 try lock
Thread-4 try lock
Thread-8 try lock
Thread-5 try lock
Thread-7 try lock
Thread-6 try lock
Thread-9 try lock
Thread-0 unlocked
Thread-2 get lock
Thread-2 unlocked
Thread-1 get lock
Thread-1 unlocked
Thread-3 get lock
Thread-3 unlocked
Thread-4 get lock
Thread-4 unlocked
Thread-8 get lock
Thread-5 get lock
Thread-8 unlocked
Thread-5 unlocked
Thread-7 get lock
Thread-6 get lock
Thread-7 unlocked
Thread-9 get lock
Thread-6 unlocked
Thread-9 unlocked
```

