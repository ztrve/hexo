---
title: AQS等待队列源码学习-Java多线程(九)   
tags: AQS  
date: 2021/5/7     
categories:
- Java
- 多线程  
keywords: [Java,多线程,AQS,AbstractQueuedSynchronizer,源码解析,Condition]  
description: AQS等待队列源码学习-Java多线程(九)
---
AQS (AbstractQueuedSynchronizer) 是由两大核心隐式队列: 阻塞队列和等待队列组成的. 本章就等待队列的源码展开学习讨论. 

<!-- more -->
# 抽象概念
等待队列, 又称条件队列(因为 Condition 可以直译为条件). 在 AQS 中等待队列是由内部类 ConditionObject 实现的. 由于 ConditionObject 中许多核心方法, 都是通过调用 AQS 的基础方法来实现的, 所以设计成内部类的形式也比较合理.  

## 主要功能
等待队列主要功能是: 将竞争到独占资源的线程 A, 从阻塞队列中出队, 二次封装后加入到等待队列休眠. 直至线程 B 将它唤醒, 线程 A 才继续工作. 为了方便各位理解, 这里贴一下流程图:
![AQS等待队列入队出队流程图](aqs-wait-queue-process.png)

## 数据结构
等待队列的结构是单向链表, 单向链表的设计仅仅是为了清理 ws(node 的 waitState) 非 CONDITION. `一个 AQS 中可同时存在多个等待队列`. 一起看一下下图.

![AQS等待队列结构](aqs-wait-queue-structure.png)

## 限制场景
并不是所有场景都可以使用等待队列的. ConditionObject 源码中调用了许多独占模式的方法, 等待队列只适配了独占模式 Exclusive, 而不支持共享模式 Shared

# 源码解析
ConditionObject 的中维护了很多入队出队的方法: await、awaitNanos、awaitUntil、signal、signalAll等等. 本章仅为跟踪阅读 await() 和 signal() 的实现.
## 1-await
这是阻塞当前线程执行的顶层方法. 主要实现了以下几个功能: 
- 将 Node 封装成等待队列节点, 并在等待队列队尾入队
- 将 Node 从阻塞队列中移出
- 等待队列中休眠当前 Node
- Node 被唤醒后, 将节点加入阻塞队列队尾
- 清理等待队列中状态不佳的 Node(help GC 释放内存)
- 补中断

```java
public final void await() throws InterruptedException {
    if (Thread.interrupted())
        throw new InterruptedException();
    // 将 Node 重新封装一下, 并添加到等待队列队尾
    Node node = addConditionWaiter();
    // 释放 node 在阻塞队列中的资源, 并记录此时 Node 的独占资源数量为 savedState
    int savedState = fullyRelease(node);
    // 中断标记位
    int interruptMode = 0;
    // 死循环判断当前节点是否在阻塞队列中
    while (!isOnSyncQueue(node)) {
        // 休眠
        LockSupport.park(this);
        // 判断休眠时, 线程是否中断
        if ((interruptMode = checkInterruptWhileWaiting(node)) != 0)
            break;
    }
    // acquireQueued(node, saveState) 在阻塞队列中竞争资源
    if (acquireQueued(node, savedState) && interruptMode != THROW_IE)
        interruptMode = REINTERRUPT;
    if (node.nextWaiter != null) // clean up if cancelled
        // 清理等待队列中 ws == CANCELLED 的节点
        unlinkCancelledWaiters();
    if (interruptMode != 0)
        // 补中断
        reportInterruptAfterWait(interruptMode);
}
```

## 1-1-addConditionWaite0r
addConditionWaiter() 是将当前线程封装成一个新的 Node, 并将其接入等待队列队尾. 方法比较简单各位看注释即可.  
若对 [unlinkCancelledWaiters](#1-5-unlinkCancelledWaiters) 方法有疑问, 可点击锚点跳转
```java
private Node addConditionWaiter() {
    // 获取等待队列中最后一个节点
    Node t = lastWaiter;
    // If lastWaiter is cancelled, clean out.
    // 如果最后一个节点状态为 CANCELLED, 就将整个等待队列中 CANCELLED 状态的节点都清除(比较暴力)
    if (t != null && t.waitStatus != Node.CONDITION) {
        unlinkCancelledWaiters();
        // 在清除所有 CANCELLED 状态节点后, 由于是独占模式, 这里肯定不会有多线程的情况发生, 就可以认为最后一个 waiter 状态是非 CANCELLED 的
        t = lastWaiter;
    }
    // 将当前节点封装成等待队列节点
    Node node = new Node(Thread.currentThread(), Node.CONDITION);
    // 下面都是 Node 向等待队列入队的操作, 就不展开了
    if (t == null)
        firstWaiter = node;
    else
        t.nextWaiter = node;
    lastWaiter = node;
    return node;
}
```


## 1-2-fullyRelease
fullyRelease 是调用 AQS 独占模式(Exclusive)释放资源的顶层方法 release(int arg), 将当前节点从阻塞队列中移除, 并释放它的独占的资源, 唤醒阻塞队列中的后继节点.    
savedState: 由于是独占模式, state 变量是用户用来控制独占的重要数据变量. 那就需要将其缓存, 直到被 signal() 唤醒后节点后, 再重新封装一个 state 相同的 Node 还给阻塞队列.  
> 如果对阻塞队列不太熟悉, 请移步上文, AQS阻塞队列源码学习: http://blog.diswares.cn/java-multithreading-aqs-block-queue/
```java
final int fullyRelease(Node node) {
    boolean failed = true;
    try {
        // 缓存 node.state
        int savedState = getState();
        // 独占模式下 release(savedState) 可以释放所有被独占的资源, 并唤醒后继节点
        if (release(savedState)) {
            failed = false;
            return savedState;
        } else {
            throw new IllegalMonitorStateException();
        }
    } finally {
        if (failed)
            node.waitStatus = Node.CANCELLED;
    }
}
```


## 1-3-isOnSyncQueue
isOnSyncQueue 判断当前节点是否在阻塞队列中存在. 
这处源码没必要死磕, 因为源码中调用的地方较多, 细节上对各个调用方法做了多处适配.
- node.waitStatus == Node.CONDITION: 只有在当前节点在等待队列时 node.waitState 会是 CONDITION
- node.prev == null: node 在阻塞队列中出队后满足该条件
- node.next != null: node 只有在阻塞队列中, 才会有 nextNode
- findNodeFromTail(node): 源码中注释说:  node.prev 可以为非空, 但尚未在阻塞队列中, 因为将其放入队列的 CAS 可能会失败. 所以我们必须从尾部遍历以确保它确实做到了. 在调用这个方法时它总是靠近尾部, 除非 CAS 失败（这不太可能），它不出意外就会在那里, 所以我们几乎不会遍历太多


```java
final boolean isOnSyncQueue(Node node) {
    if (node.waitStatus == Node.CONDITION || node.prev == null)
        return false;
    if (node.next != null) // If has successor, it must be on queue
        return true;
    return findNodeFromTail(node);
}

private boolean findNodeFromTail(Node node) {
    Node t = tail;
    for (;;) {
        if (t == node)
            return true;
        if (t == null)
            return false;
        t = t.prev;
    }
}
```


## 1-4-checkInterruptWhileWaiting
判断线程在休眠时是否中断. 并判断到底是抛出 Interrupt 异常还是补一下 Interrupt.
如果没有与 signal() 产生竞争, 那么就会通过 enq(node) 将 node 入阻塞队列队尾
```java
private int checkInterruptWhileWaiting(Node node) {
    return Thread.interrupted() ?
        (transferAfterCancelledWait(node) ? THROW_IE : REINTERRUPT) :
        0;
}

// 这个方法在执行时, 可能会遭遇 signal(), 如果没有 signal 在执行完毕前, 这里就谦让一下
final boolean transferAfterCancelledWait(Node node) {
    if (compareAndSetWaitStatus(node, Node.CONDITION, 0)) {
        enq(node);
        return true;
    }
    while (!isOnSyncQueue(node))
        Thread.yield();
    return false;
}
```


## 1-5-unlinkCancelledWaiters
这个方法比较简单. 作用是: 正向遍历等待队列, 将 CANCELLED 状态的 node 出队. 
```java
private void unlinkCancelledWaiters() {
    Node t = firstWaiter;
    Node trail = null;
    while (t != null) {
        Node next = t.nextWaiter;
        if (t.waitStatus != Node.CONDITION) {
            t.nextWaiter = null;
            if (trail == null)
                firstWaiter = next;
            else
                trail.nextWaiter = next;
            if (next == null)
                lastWaiter = trail;
        }
        else
            trail = t;
        t = next;
    }
}
```


## 1-6-reportInterruptAfterWait
根据中断标记位, 判断到底应该补中断还是直接抛异常.
```java
private void reportInterruptAfterWait(int interruptMode)
    throws InterruptedException {
    if (interruptMode == THROW_IE)
        throw new InterruptedException();
    else if (interruptMode == REINTERRUPT)
        selfInterrupt();
}
```

## 2-signal
看完了 await(), 与之相对应的便是 signal().  
signal() 的作用比较简单, 将等待队列中通过 LockSupport.park() 的线程, unpark 就好了.  
注意这里明确指出子类需要实现 isHeldExclusively(). 而 isHeldExclusively() 是独占模式才需要实现的. 所以可以侧面印证, ConditionObject 只有在独占模式下才能使用
```java
public final void signal() {
    if (!isHeldExclusively())
        throw new IllegalMonitorStateException();
    Node first = firstWaiter;
    if (first != null)
        doSignal(first);
}
```

## 2-1-doSignal
这里代码写的很难看. doSignal 是要将节点从等待队列首节点出队并加入阻塞队列队尾.  
这里可以简单扫一眼, 先了解 transferForSignal(first) 的实现再回过来看
```java
private void doSignal(Node first) {
    do {
        // 斩断与等待队列联系
        if ( (firstWaiter = first.nextWaiter) == null)
            lastWaiter = null;
        first.nextWaiter = null;
    } while (!transferForSignal(first) &&
             (first = firstWaiter) != null);
}
```

## 2-1-1-transferForSignal
将等待队列中的节点唤醒, 并调用 enq(node) 将其加到阻塞队列队尾
```java
final boolean transferForSignal(Node node) {
    // 如果没法修改 ws, 那么这个节点一定是 CANCELLED 的
    if (!compareAndSetWaitStatus(node, Node.CONDITION, 0))
        return false;
    // 将 node 添加至阻塞队列队尾
    Node p = enq(node);
    int ws = p.waitStatus;
    if (ws > 0 || !compareAndSetWaitStatus(p, ws, Node.SIGNAL))
        // 唤醒节点
        LockSupport.unpark(node.thread);
    return true;
}
```
