---
title: 线程池参数及六种实现-Java多线程(十)  
tags: 线程池  
date: 2021/5/14  
categories:
- Java
- 多线程
keywords: [Java,多线程,线程池]   
description: 线程池参数及六种实现-Java多线程(十)
---
当我们使用 new Thread() 创建线程时, 阿里巴巴编程规约强制约束我们放弃这种创建线程的方式, 并推荐我们使用线程池. 本节主要介绍创建线程池的几个参数, 及 Executors 中提供的六种线程池实现.  
<!-- more -->

# 介绍
线程池其实只是一种线程使用的模式, 底层还是使用 new Thread() 实现的. 创建了过多的线程会产生严重的调度开销, 进而影响缓存局部性和整体性能. 线程池不仅能够保证内核的充分利用, 还能防止过分调度.  

# 线程池参数
创建一个自定义线程池需要创建 ThreadPoolExecutor 对象. 其中形参最多的构造方法本节需要介绍的`创建线程池必须使用的七个参数`   
```java
public ThreadPoolExecutor(int corePoolSize,
                          int maximumPoolSize,
                          long keepAliveTime,
                          TimeUnit unit,
                          BlockingQueue<Runnable> workQueue,
                          ThreadFactory threadFactory,
                          RejectedExecutionHandler handler) {
    if (corePoolSize < 0 ||
        maximumPoolSize <= 0 ||
        maximumPoolSize < corePoolSize ||
        keepAliveTime < 0)
        throw new IllegalArgumentException();
    if (workQueue == null || threadFactory == null || handler == null)
        throw new NullPointerException();
    this.corePoolSize = corePoolSize;
    this.maximumPoolSize = maximumPoolSize;
    this.workQueue = workQueue;
    this.keepAliveTime = unit.toNanos(keepAliveTime);
    this.threadFactory = threadFactory;
    this.handler = handler;
}
```

## corePoolSize
corePoolSize: 线程池核心线程大小. 线程池中会维护一个最小的线程数量, 即使这些线程处理空闲状态, 他们也不会被销毁, 除非设置了 allowCoreThreadTimeOut. 这里的最小线程数量即是 corePoolSize.

## maximumPoolSize
maximumPoolSize: 线程池最大线程数量. 一个任务被提交到线程池以后, 首先会找有没有空闲存活线程, 如果有则直接将任务交给这个空闲线程来执行, 如果没有则会缓存到 workQueue（工作队列, 也是阻塞队列, 后文有详细介绍）中, 如果工作队列满了, 才会创建一个新线程, 然后从工作队列中取出一个任务交由新线程来处理, 而将刚提交的任务放入工作队列尾部. 线程池不会无限制的去创建新线程, 它会有一个最大线程数量的限制, 这个数量即由 maximunPoolSize 指定. 

## keepAliveTime
keepAliveTime: 空闲线程存活时间. 一个线程如果处于空闲状态, 并且当前的线程数量大于 corePoolSize, 那么在指定时间后, 这个空闲线程会被销毁, 这里的指定时间由 keepAliveTime 来设定.

## unit
unit: keepAliveTime 的单位.

## workQueue
workQueue: 工作队列, 也是阻塞队列 BlockingQueue. 新任务被提交后, 会先进入到此工作队列中, 任务调度时再从队列中取出任务. jdk中提供了四种工作队列  

#### ArrayBlockingQueue
基于数组的有界阻塞队列, 按FIFO排序. 新任务进来后, 会放到该队列的队尾, 有界的数组可以防止资源耗尽问题. 当线程池中线程数量达到corePoolSize后, 再有新任务进来, 则会将任务放入该队列的队尾, 等待被调度. 如果队列已经是满的, 则创建一个新线程, 如果线程数量已经达到maxPoolSize, 则会执行拒绝策略. 

#### LinkedBlockingQuene

基于链表的无界阻塞队列（其实最大容量为Interger.MAX）, 按照FIFO排序. 由于该队列的近似无界性, 当线程池中线程数量达到corePoolSize后, 再有新任务进来, 会一直存入该队列, 而不会去创建新线程直到maxPoolSize, 因此使用该工作队列时, 参数maxPoolSize其实是不起作用的. 

#### SynchronousQuene

一个不缓存任务的阻塞队列, 生产者放入一个任务必须等到消费者取出这个任务. 也就是说新任务进来时, 不会缓存, 而是直接被调度执行该任务, 如果没有可用线程, 则创建新线程, 如果线程数量达到maxPoolSize, 则执行拒绝策略. 

#### PriorityBlockingQueue
具有优先级的无界阻塞队列, 优先级通过参数Comparator实现. 

#### DelayedWorkQueue
保证添加到队列中的任务, 会按照任务的延时时间进行排序, 延时时间少的任务首先被获取

## threadFactory
threadFactory: 线程工厂. 创建一个新线程时使用的工厂, 可以用来设定线程名、是否为daemon线程等等

## handler
handler: 拒绝策略. 当工作队列中的任务已到达最大限制, 并且线程池中的线程数量也达到最大限制, 这时如果有新任务提交进来, 该如何处理呢. 这里的拒绝策略, 就是解决这个问题的.  
当然jdk中也提供了4中拒绝策略：CallerRunsPolicy/AbortPolicy/DiscardPolicy/DiscardOldestPolicy  
这里就不过多介绍了, 一般我们使用线程池都需要自己实现拒绝策略. 实现 RejectedExecutionHandler 接口, 复写 rejectedExecution().

# 六种线程池
JUC 提供的静态工厂工具类 Executors 中提供了六种线程池. 不推荐使用! 因为他们各自有着不同的缺陷, 有的会导致程序崩溃.  

![Java提供的线程池](juc-thread-pools.png)

## FixedThreadPool
特点：固定池子中线程的个数
问题: LinkedBlockingQueue 是由一个最大长度为 Integer#MAX_VALUE 的链表实现, 有内存溢出的风险
```java
public static ExecutorService newFixedThreadPool(int nThreads) {
    return new ThreadPoolExecutor(nThreads, nThreads,
                                  0L, TimeUnit.MILLISECONDS,
                                  new LinkedBlockingQueue<Runnable>());
}
```

## CachedThreadPool
特点：没有核心线程数, 最多可以创建 Integer.MAX_VALUE 个线程 
问题: 同时运行的线程数过多, 会导致内存溢出. 即使没有内存溢出, 由于线程切换会浪费大量的系统资源, 导致多线程执行效率地下, 以至于线程越多, 越容易内存溢出
```java
public static ExecutorService newCachedThreadPool(ThreadFactory threadFactory) {
    return new ThreadPoolExecutor(0, Integer.MAX_VALUE,
                                  60L, TimeUnit.SECONDS,
                                  new SynchronousQueue<Runnable>(),
                                  threadFactory);
}
```

## SingleThreadPool
特点：作用是保证任务的顺序执行. 池中只有一个线程, 如果扔5个任务进来, 那么有4个任务将排队; 
```java
public static ExecutorService newSingleThreadExecutor(ThreadFactory threadFactory) {
    return new FinalizableDelegatedExecutorService
        (new ThreadPoolExecutor(1, 1,
                                0L, TimeUnit.MILLISECONDS,
                                new LinkedBlockingQueue<Runnable>(),
                                threadFactory));
}
```

## ScheduledThreadPool
这个线程池返回的是 ScheduledExecutorService, ScheduledExecutorService 继承自 ExecutorService, 不仅提供了线程池相关的方法, 也提供了定时器相关的方法 schedule()
问题: 同 FixedThreadPool
```java
public static ScheduledExecutorService newScheduledThreadPool(
        int corePoolSize, ThreadFactory threadFactory) {
    return new ScheduledThreadPoolExecutor(corePoolSize, threadFactory);
}

public ScheduledThreadPoolExecutor(int corePoolSize,
                                   ThreadFactory threadFactory) {
    super(corePoolSize, Integer.MAX_VALUE, 0, NANOSECONDS,
          new DelayedWorkQueue(), threadFactory);
}
```

## SingleThreadScheduledExecutor
ScheduledExecutorService 的单例实现
```java
public static ScheduledExecutorService newSingleThreadScheduledExecutor() {
    return new DelegatedScheduledExecutorService
        (new ScheduledThreadPoolExecutor(1));
}
```

## WorkStealingPool
在 Java1.8 时引入. Stealing 翻译为抢断、窃取的意思, 它实现的一个线程池和上面五种都不一样, 用的是 ForkJoinPool 类. 这里使用参数 parallelism 控制线程的并行度, 而不像之前那样指定 corePoolSize 等来控制并发. 
```java
public static ExecutorService newWorkStealingPool(int parallelism) {
    return new ForkJoinPool
        (parallelism,
         ForkJoinPool.defaultForkJoinWorkerThreadFactory,
         null, true);
}
```

> 值得一提的是 ForkJoinPool 为 Java8 Stream API 中 parallelStream  提供了支撑