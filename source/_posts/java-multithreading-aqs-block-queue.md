---
title: AQS阻塞队列源码学习-Java多线程(八)   
tags: AQS  
date: 2021/4/30     
categories:
- Java
- 多线程  
keywords: [Java,多线程,AQS,AbstractQueuedSynchronizer,源码解析]  
description: AQS阻塞队列源码学习-Java多线程(八)
---
AQS (AbstractQueuedSynchronizer) 是由两大核心隐式队列: 阻塞队列和等待队列组成的. 本章就阻塞队列的源码实现进行讨论.

<!-- more -->
# 概念
### 入队出队流程
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

### 资源共享模式
AQS 的阻塞队列定义两种资源共享模式: Exclusive(独占模式, 只有一个线程能执行, 如: ReentrantLock) 和 Share (共享模式, 多个线程可同时执行, 如 Semaphore/CountDownLatch).  
不同的自定义同步器争用共享资源的方式也不同. 自定义同步器在实现时只需要实现共享资源state的获取与释放方式即可, 至于具体线程等待队列的维护(如获取资源失败入队/唤醒出队等), AQS已经在顶层实现好了. 自定义同步器实现时主要实现以下几种方法(面试常考):
- isHeldExclusively(): 该线程是否正在独占资源. 只有用到condition才需要去实现它.
- tryAcquire(int): 独占方式. 尝试获取资源, 成功则返回true, 失败则返回false.
- tryRelease(int): 独占方式. 尝试释放资源, 成功则返回true, 失败则返回false.
- tryAcquireShared(int): 共享方式. 尝试获取资源. 负数表示失败；0表示成功, 但没有剩余可用资源；正数表示成功, 且有剩余资源.
- tryReleaseShared(int): 共享方式. 尝试释放资源, 如果释放后允许唤醒后续等待结点返回true, 否则返回false.

# 源码解析
上一小节了解了实现一个阻塞队列需要复写的几个重要方法, 本节以调用这几个方法的入口方法为切口, 依照acquire、release、acquireShared、releaseShared的次序对 AQS 源码进行分析.

## Node 的五种状态
每个 Node 都有五种线程状态. 线程状态会被记录到当前 Node 的 waitState 中去.
- `CANCELLED(1)`: 当前线程已经取消调度. 当timeout或被中断（线程休眠时中断了, 唤醒后会响应中断），会进入此状态，进入该状态后的结点将不会再变化。
- `SIGNAL(-1)`: 后置节点需要被唤醒. 节点 A 进入阻塞队列后, 会将前置节点的 waitState 修改为 SIGNAL
- `CONDITION(-2)`: 表示节点在`等待队列`中休眠. 当其他线程调用了 Condition 的 signal 方法后, CONDITION 状态的节点会从等待队列中出队, 并入队至阻塞队列队尾
- `PROPAGATE(-3)`: 共享模式下，前继结点不仅会唤醒其后继结点，同时也可能会唤醒后继的后继结点
- 0: Node 被 new 出来时候的缺省状态

源码中喜欢用 waitState > 0 表示线程结束, waitState < 0 表示线程状态健康, 仍能活跃在 AQS 维护的队列中.

## 1-acquire
此方法是`独占模式`下线程获取共享资源的顶层入口。  
如果获取到资源，线程直接返回，否则进入等待队列，直到获取到资源为止，且整个过程忽略中断的影响。这也正是 lock() 的语义，当然不仅仅只限于 lock()。获取到资源后，线程就可以去执行其临界区代码了。下面是 acquire() 的源码：
```java
public final void acquire(int arg) {
        if (!tryAcquire(arg) &&
        acquireQueued(addWaiter(Node.EXCLUSIVE), arg))
        selfInterrupt();
}
```

方法详解:
1. tryAcquire(): 尝试直接去获取资源，如果成功则直接返回. 这里体现了非公平锁. 新线程 A 期望获取锁时会尝试直接抢占资源一次，而阻塞队列中大概率还有线程 B 已经被唤醒了, B 正在自旋获取资源. 线程 A 插队时与 B 会产生竞争, 体现了非公平. 详见: [1-1-tryAcquire](#1-1-tryAcquire)
2. addWaiter(Node.EXCLUSIVE): 新线程 A 抢占资源失败后, addWaiter 会将该线程加入等待队列的尾部，并标记为独占模式 EXCLUSIVE. 详见: [1-2-addWaiter](#1-2-addWaiter)   
3. acquireQueued(Node node): 线程为了获取资源, 一直休眠(阻塞 Block)在等待队列中. 直到获取资源后才返回。如果在整个等待过程中被中断过，则返回true，否则返回false。详见: [1-3-acquireQueued](#1-3-acquireQueued) 
4. selfInterrupt: 响应当前线程中断. 当前线程在休眠时被中断, 该线程是不会被响应中断的, 直到 selfInterruped() 被调用, 才会补上线程中断. 详见: [1-4-selfInterrupted](#1-4-selfInterrupted)

这几个方法看不懂没关系, 了解个大概, 后面有各方法的详细解释

### 1-1-tryAcquire
```java
protected boolean tryAcquire(int arg) {
    throw new UnsupportedOperationException();
}
```
可以看到这是个抽象方法, 因为 AQS 本身是 Abstract 类并用了模板方法实现. 熟悉设计模式的同学都知道 tryAcquire 方法只是 AQS 挖的一个洞, 等子类实现去填坑. 如果子类想实现 Exclusive 模式, 那么就在子类重写 tryAcquire  

### 1-2-addWaiter
将当前线程封装成 Node, 并隐式进入队列. 为什么说是隐式入队呢, 因为阻塞队列是隐式队列, 队列依靠每个节点中存储的 prevNode 和 nextNode 组成. 在这个方法里 node.prev 和 pred.next 两个值的修改, 就是隐式入队操作   

```java
private Node addWaiter(Node mode) {
    // 将当前线程与 mode 进行合并, mode 全文提供两种实现: Node.EXCLUSIVE 和 Node.SHARED
    Node node = new Node(Thread.currentThread(), mode);
    Node pred = tail;
    if (pred != null) {
        // 全局的尾结点作为 node 节点的 prev 节点
        node.prev = pred;
        // comapreAndSetTail(pred, node) 是在没有多线程的竞争的情况下的优化
        // 没有竞争的情况下直接将尾结点替换成 node 节点
        // 这里没有执行成功也没关系, 在 enq(node) 里有更暴力的 CAS 实现
        if (compareAndSetTail(pred, node)) {
            pred.next = node;
            return node;
        }
    }
    // 将节点插入队列, 必要时进行初始化
    enq(node);
    return node;
}
```

注释写的十分详细, 不过多展开

### 1-2-1-enq
```java
private Node enq(final Node node) {
    // 开启自旋
    for (;;) {
        Node t = tail;
        if (t == null) {
            // 必要的初始化操作
            if (compareAndSetHead(new Node()))
                tail = head;
        } else {
            // node 节点的前置节点设置为现在的 tail 节点
            node.prev = t;
            if (compareAndSetTail(t, node)) {
                // 前置节点 tail 的下一个节点当然就是 node
                t.next = node;
                return t;
            }
        }
    }
}
```

enq(node) 方法的作用是: 新增节点 Node 入队.   
我们可以看到: 自旋 + compareAndSwap(Unsafe 类的原子性操作)的代码, 这是经典的 CAS 自旋锁实现. 

> CAS/ABA问题: http://blog.diswares.cn/java-multithreading-cas-aba/

### 1-3-acquireQueued
acquire() 已经调用过了 tryAcquire() 和 addWaiter()，此时线程获取资源失败，并已经被放入阻塞队列尾部了。  
acquireQueued() 执行时首先将当前线程进入等待状态休息，直到其他线程彻底释放资源后唤醒自己，自己醒了后直接去抢资源(可能与当前时刻想进入队列的线程发生竞争, 详见: [1-acquire](#1-acquire). 抢不到大不了继续休息, 等待下一次的唤醒)，抢到之后就可以去干自己想干的事了。  

这里可以先根据注释简单理解一下 acquireQueued 的执行流程. 在看懂整个方法前, 需要先理解 [shouldParkAfterFailedAcquire(p, node)](#1-3-1-shouldParkAfterFailedAcquire) 和 [parkAndCheckInterrupt()](#1-3-2-parkAndCheckInterrupt) 的功能.   
可以在先看后面的方法后, 再会来消化 [acquireQueued](#acquireQueued)
```java
final boolean acquireQueued(final Node node, int arg) {
    // failed: 是个标记位, 用于标记 try {} 代码块是否执行成功
    boolean failed = true;
    try {
        // interrupted: 中断标记, 判断当前线程是否被中断
        boolean interrupted = false;
        for (;;) {
            // 获取前置节点
            final Node p = node.predecessor();
            // 判断前置节点是不是 head 节点
            // 并尝试竞争资源
            if (p == head && tryAcquire(arg)) {
                // 竞争成功, 将当前节点(线程)设置为头结点
                setHead(node);
                // 将前置节点与当前节点的连接断开, 也就是阻塞队列的出队操作
                // 这时 p 节点游离在内存中, 是一个孤立的状态, 没有任何引用指向它
                // JVM GC 的时候这部分内存会自然被回收
                p.next = null; // help GC
                failed = false;
                return interrupted;
            }
            // shouldParkAfterFailedAcquire 从后向前遍历自己的前置节点
            // 前置节点状态不健康, 则将他们挨个出队
            if (shouldParkAfterFailedAcquire(p, node) &&
                // parkAndCheckInterrupt 竞争资源失败后当前 Node 应当 Block
                // 当前线程再次被唤醒之后, 立即判断 interrupt 状态并返回
                parkAndCheckInterrupt())
                interrupted = true;
        }
    } finally {
        // 当程序被中断, 或上面的流程发生异常(一般不会发生)时, 将当前节点状态修改为 CANCEL
        if (failed)
            cancelAcquire(node);
    }
}
```

### 1-3-1-shouldParkAfterFailedAcquire
该方法主要是用来清理本队列前状态不健康的节点, 将 ws == Node.CANCEL 的节点都清理出队, 由于 shouldParkAfterFailedAcquire 外部有个自旋, 下一次进来, 可能前置节点状态就健康了
```java
private static boolean shouldParkAfterFailedAcquire(Node pred, Node node) {
    // 获取前置节点 waitState
    int ws = pred.waitStatus;
    if (ws == Node.SIGNAL)
        // 前置节点状态正常
        return true;
    if (ws > 0) {
        // 前置节点取消了, 帮它出队
        // 使用了一个 do while 语句
        // 因为不确定前置节点的前置节点状态是不是健康
        do {
            // 队列中有 ABCDE 四个节点按顺序排列
            // 假设 node 是 E 节点
            // 那么 pred 就是 D 节点
            // pred.prev 就是 C 节点
            // 这句话的意思就是将 C 节点作为 E 节点的前置节点
            // 奇怪的是被动出队的 D 节点应该有个 next 指针指向 E 节点
            // 这里竟然没有 help GC 的优化
            node.prev = pred = pred.prev;
        } while (pred.waitStatus > 0);
        // 将 C 节点的 next 指针指向 E
        pred.next = node;
    } else {
        // shouldParkAfterFailedAcquire 的外层是个自旋
        // 这里是为了 ws == 0 || ws == PROPAGATE 服务的
        // 如果前驱正常，那就把前驱的状态设置成SIGNAL，告诉它拿完号后通知自己一下。有可能失败，人家说不定刚刚释放完呢
        compareAndSetWaitStatus(pred, ws, Node.SIGNAL);
    }
    return false;
}
```
### 1-3-2-parkAndCheckInterrupt
这个方法比较简单. LockSupport 将当前线程 Block, 等到唤醒后, 立马确认线程是否被中断过
```java
private final boolean parkAndCheckInterrupt() {
    LockSupport.park(this);
    return Thread.interrupted();
}
```

### 1-3-3-cancelAcquire
线程休眠时发生异常, 例如 Thread.stop() 或者被中断过, 那么就需要将该线程安全的出队

```java
// 假设现在阻塞队列中有 ABCDE 五个节点, 方法中的 node 节点为 C 节点
private void cancelAcquire(Node node) {
    // Ignore if node doesn't exist
    if (node == null)
        return;

    node.thread = null;

    // Skip cancelled predecessors
    // 类似代码在 #1-3-1-shouldParkAfterFailedAcquire 中有详细描述, 不在展开
    // 这里拿出的 pred 节点一定是 B 节点, 并且假设 B 节点的 ws 又正好是 CANCELLED
    Node pred = node.prev;
    while (pred.waitStatus > 0)
        // 不断向前遍历, 直至找到为非取消状态的节点 A
        // 并将 A 设置为 C 的前置节点
        node.prev = pred = pred.prev;

    // 上面我们将 node.prev 修改了, 但是 pred.next 还没有修改, 所以才有这一步操作
    Node predNext = pred.next;

    // 将节点状态修改为 CANCELLED
    node.waitStatus = Node.CANCELLED;
    
    if (node == tail && compareAndSetTail(node, pred)) {
        // 如果 node 节点在队尾, 将 pred.next 改为 null
        compareAndSetNext(pred, predNext, null);
    } else {
        // node 节点在队列中间的情况
        // 如果当前节点是在获取到资源后检测出 interrupt 的, 那么需要唤醒后继节点
        // 不是上述的情况, 就需要一些复杂操作来确保节点在意外出队的情况下, 保证原子性
        int ws;
        if (pred != head &&
            ((ws = pred.waitStatus) == Node.SIGNAL ||
             (ws <= 0 && compareAndSetWaitStatus(pred, ws, Node.SIGNAL))) &&
            pred.thread != null) {
            Node next = node.next;
            if (next != null && next.waitStatus <= 0)
                compareAndSetNext(pred, predNext, next);
        } else {
            unparkSuccessor(node);
        }

        node.next = node; // help GC
    }
}
```

### 1-4-selfInterrupted
如果线程在等待过程中被中断过，线程是不会响应的。在获取资源后才再进行自我中断selfInterrupt()，将中断补上。

```java
static void selfInterrupt() {
    Thread.currentThread().interrupt();
}
```

### 1-小结
acquire(int arg) 的方法都看完了. 在这里用一张图总结一下 acquire 的流程:
![aqs-acquire流程图](aqs-acquire-process.png)


## 2-release
上一小节已经把获取资源的顶层入口 acquire() 分析完了. 程序在获取资源后, 就应该执行我们自己的业务代码, 执行完业务代码后, 我们要讲获取的资源释放. 这小节就是分析 AQS 独占模式 EXCLUSIVE 下 释放资源的方法 release(). 此方法是独占模式下线程释放共享资源的顶层入口。它会释放指定量的资源，如果彻底释放了（即state=0）,它会唤醒等待队列里的其他线程来获取资源。这也正是 unlock() 的语义，当然不仅仅只限于unlock()。下面是 release() 的源码：

```java
/**
 * @return the value returned from {@link #tryRelease}
 * 返回值等价 tryRelease() 的返回值
 */
public final boolean release(int arg) {
    // 控制 state 的值
    if (tryRelease(arg)) {
        Node h = head; // 获取头结点 
        if (h != null && h.waitStatus != 0)
            // 唤醒下一个休眠中的节点
            unparkSuccessor(h);
        return true;
    }
    return false;
}
```

这个方法比较简单. 由于是释放定量资源, 一般调用子类实现的 tryRelease 方法去控制 state 值的变更. 当 state 值到达你的定义的释放资源的阈值时, 才去唤醒阻塞队列中下一个等待的 Node.     

### 2-1-tryRelease
没啥好说的, 跟 tryAcquire 的功能一样, 都是作者提供的模板方法.
```java
protected boolean tryRelease(int arg) {
    throw new UnsupportedOperationException();
}
```

### 2-2-unparkSuccessor
这个方法功能就是唤醒阻塞队列中休眠的下一个节点. 如果没有满足条件的下一个节点, 就不唤醒了.

```java
private void unparkSuccessor(Node node) {
    // 重置传入节点的等待状态
    int ws = node.waitStatus;
    if (ws < 0)
        compareAndSetWaitStatus(node, ws, 0);
        
    // 将下一个节点线程状态非 CANCELLED 的节点
    Node s = node.next;
    // 校验 nextNode 状态
    if (s == null || s.waitStatus > 0) {
        s = null;
        for (Node t = tail; t != null && t != node; t = t.prev)
            if (t.waitStatus <= 0)
                s = t;
    }
    if (s != null)
        // 唤醒下一个节点
        LockSupport.unpark(s.thread);
}
```

### 2-小结
release() 是独占模式下线程释放共享资源的顶层入口. 它会释放指定量的资源, 如果彻底释放了(这点由子类复写的 tryRelease 方法的返回值控制), 它会唤醒等待队列里的其他线程来获取资源.   


那么到这里为止独占模式的资源占用和释放都已经解释完了. 接下来让我们一起阅读共享模式下的资源占用和释放

## 3-acquireShared
此方法是共享模式下线程获取共享资源的顶层入口. 它会获取指定量的资源, 获取成功则直接返回, 获取失败则进入等待队列, 直到获取到资源为止, 整个过程忽略中断. 下面是 acquireShared() 的源码：
```java
public final void acquireShared(int arg) {
    if (tryAcquireShared(arg) < 0)
        doAcquireShared(arg);
}
```

### 3-1-tryAcquireShared
注意 tryAcquireShared 的返回值为 int 类型, 而 tryAcquire 的返回值为 boolean. int 类型就是共享模式的一个标志性体现. 当下一个节点需要消耗的资源小于 int 值, 就实现共享了.

```java
protected int tryAcquireShared(int arg) {
    throw new UnsupportedOperationException();
}
```

### 3-2-doAcquireShared
这个方法是不是有点儿眼熟. 跟独占模式的 doAcquireInterruptibly() 基本一模一样. 除了以下两点区别
不过由于共享模式的特性, Doug Lea 将 selfInterrupt 放到了 doAcquireInterruptibly() 里, 而 acquireQueued 中 selfInterrupt 被放到了外层. 这个区别对两处代码运行的过程并没有实质性的影响.    
由于 tryAcquireShared 的特性, 这里又多了一个方法来处理共享 setHeadAndPropagate(node, r)

```java
private void doAcquireShared(int arg) {
    final Node node = addWaiter(Node.SHARED);
    boolean failed = true;
    try {
        boolean interrupted = false;
        for (;;) {
            final Node p = node.predecessor();
            if (p == head) {
                // 返回一个数用于判断是否可以继续释放资源
                int r = tryAcquireShared(arg);
                if (r >= 0) {
                    // 将 head 指向自己, 还有剩余资源可以再唤醒之后的线程
                    setHeadAndPropagate(node, r);
                    p.next = null; // help GC
                    if (interrupted)
                        selfInterrupt();
                    failed = false;
                    return;
                }
            }
            if (shouldParkAfterFailedAcquire(p, node) &&
                parkAndCheckInterrupt())
                interrupted = true;
        }
    } finally {
        if (failed)
            cancelAcquire(node);
    }
}
```

### 3-2-1-setHeadAndPropagate
进入这个方法, 先将头结点改为当前线程, 并且唤醒相邻节点.  
[doReleaseShared](#3-2-1-1-doReleaseShared) 主要作用是唤醒后继节点
```java
private void setHeadAndPropagate(Node node, int propagate) {
    Node h = head;
    setHead(node);
    if (propagate > 0 || h == null || h.waitStatus < 0 ||
        (h = head) == null || h.waitStatus < 0) {
        Node s = node.next;
        if (s == null || s.isShared())
            doReleaseShared();
    }
}
```

### 3-2-1-1-doReleaseShared
这个方法主要用于唤醒相邻的那个后继节点. 其中调用了 [unparkSuccessor](#2-2-unparkSuccessor) 在介绍独占的时候已经有详细分析

```java
private void doReleaseShared() {
    for (;;) {
        Node h = head;
        if (h != null && h != tail) {
            int ws = h.waitStatus;
            if (ws == Node.SIGNAL) {
                if (!compareAndSetWaitStatus(h, Node.SIGNAL, 0))
                    continue;          
                // 唤醒后继节点
                unparkSuccessor(h);
            }
            else if (ws == 0 &&
                     !compareAndSetWaitStatus(h, 0, Node.PROPAGATE))
                continue;              
        }
        if (h == head)                 
            break;
    }
}
```

### 3-小结
在学习过 acquire 之后, acquiredShared 就可以分分钟拿下了. acquiredShared 的流程无非是比独占模式仅仅唤醒后继节点多了一步. 在唤醒后继节点后, 如果剩余资源大于等于 0, 那么就会去唤醒后继节点的后继节点, 直到资源不足.

## 4-releaseShared
上一小节已经把 acquireShared() 说完了, 这一小节就来讲讲它的反操作 releaseShared() 吧. 此方法是共享模式下线程释放共享资源的顶层入口. 它会释放指定量的资源, 如果成功释放且允许唤醒等待线程, 它会唤醒等待队列里的其他线程来获取资源. 下面是 releaseShared() 的源码：

```java
public final boolean releaseShared(int arg) {
    if (tryReleaseShared(arg)) {
        doReleaseShared();
        return true;
    }
    return false;
}
```

[doReleaseShared](#3-2-1-1-doReleaseShared) 分析看前文  

## 4-小结
看到这里, 共享模式的源码也就分析完了. 其实共享模式跟独占模式原理都是一样的, 只不过较独占模式多了一步`唤醒后继节点且资源充足的情况下, 继续唤醒后续节点`的功能.