---
title: 线程池实现原理及源码阅读-Java多线程(十一)  
tags: 线程池  
date: 2021/6/1  
categories:
- Java
- 多线程
keywords: [Java,多线程,线程池,源码阅读]   
description: 线程池实现原理及源码阅读-Java多线程(十一)
---
Java 的线程对应着操作系统的线程, 众所周知线程在创建和销毁时都会开销一部分的系统资源, 在高并发的场景下, 将资源浪费在频繁的创建销毁线程显然是不理智的, 在 Java1.5 推出了线程池的概念. 本节为大家介绍线程池实现的基本原理及底层源码阅读.   
<!-- more -->
# 线程池运行机制
在学习前需要了解线程池的运行机制, 也就是一个新的线程想要被线程池执行需要经过哪些处理:
- 有空闲的核心线程, 直接交给核心线程处理
- 核心线程数量满了, 则放入阻塞队列
- 期间新来的 task 都会放入阻塞队列, 核心线程监听阻塞队列消费 task
- 如果阻塞队列也被塞满了, 开启工作线程
- 核心线程数 + 工作线程数 > 最大线程数, 执行拒绝策略

上节学习线程池的基本用法时, 我们经常用到两个类: Executors 和 ThreadPoolExecutor. 
# Executors
这是 Jdk 提供的线程池创建的工具类, 不推荐使用, 因为这些线程池或多或少都有些不安全的问题, 可能会内存溢出. 阿里巴巴编程规约要求我们手动创建线程池去代替使用默认的线程, 不光是为了熟悉线程池七个自定义参数, 还有一点是要求我们为线程池命名, 这样在定位问题, 监控线程池状态时可以更加清晰.  
```java
public class Executors {
    public static ExecutorService newFixedThreadPool(int nThreads) {
        return new ThreadPoolExecutor(nThreads, nThreads,
                                      0L, TimeUnit.MILLISECONDS,
                                      new LinkedBlockingQueue<Runnable>());
    }

    public static ExecutorService newWorkStealingPool(int parallelism) {
        return new ForkJoinPool
                (parallelism,
                        ForkJoinPool.defaultForkJoinWorkerThreadFactory,
                        null, true);
    }
    
    ......
```
虽然不推荐大家使用这个类创建线程池, 但是我们可以参考他的实现方式来创建自己的线程池. 对 Executors 感兴趣的同学请移步上一篇博文
> http://blog.diswares.cn/java-multithreading-thread-pool/

# ThreadPoolExecutor
ThreadPoolExecutor 是真正的线程池实现类.  
先从类图了解他的实现结构  
![ThreadPoolExecutor类图](ThreadPoolExecutor_diamgrams.png)   

先来看一下 ThreadPoolExecutor 的静态内部类, 一共有五个静态内部类, 这里可以分为两类:
- Worker(后文会详细介绍): 用来消费线程的
- RejectedExecutionHandler: CallerRunsPolicy、AbortPolicy 、DiscardPolicy、DiscardOldestPolicy 这四个静态内部类都实现了拒绝策略接口     

再来看一下他的继承关系:
- ThreadPoolExecutor 继承了抽象类 AbstractExecutorService
- AbstractExecutorService 实现了 ExecutorService 接口
- ExecutorService 接口继承了 Executor 接口

通过上述继承关系再结合方法实现, 我们可以知道:
- AbstractExecutorService 提供了 submit()
- ThreadPoolExecutor 提供了 execute()
- ThreadPoolExecutor 实现了 shutdown()

# 1.AbstractExecutorService
从源码中可以看出 submit 其实就是将 Runnable/Callable 接口, 转换成 RunnableFuture 接口, 这个 RunnableFuture 其实是继承了 Runnable 和 Future 接口. 最后将转换完成的回调函数, 传递给 ThreadPoolExecutor.execute() 方法进行执行.  
所以 submit 的底层其实就是 ThreadPoolExecutor.execute()

```java
public Future<?> submit(Runnable task) {
    if (task == null) throw new NullPointerException();
    RunnableFuture<Void> ftask = newTaskFor(task, null);
    execute(ftask);
    return ftask;
}

public <T> Future<T> submit(Runnable task, T result) {
    if (task == null) throw new NullPointerException();
    RunnableFuture<T> ftask = newTaskFor(task, result);
    execute(ftask);
    return ftask;
}

public <T> Future<T> submit(Callable<T> task) {
    if (task == null) throw new NullPointerException();
    RunnableFuture<T> ftask = newTaskFor(task);
    execute(ftask);
    return ftask;
}
```

# ThreadPoolExecutor
ThreadPoolExecutor 是线程池的实现类, 要读懂这个类, 首先需要对它的一些全局成员变量有一定了解

## 1.全局成员变量
## 1.1.ctl
ctl: 应该是 control 的缩写, 注释中第一句话 The main pool control state. 表明 ctl 是用来控制线程池主要运行状态的变量.  
ctl 的设计比较巧妙, 它是一个 int 类型的变量(AtomicInteger). 一个 int 类型的数是4个字节, 32位. ctl 由两部分组成:
- 前3位是rs(runState), 表示线程运行的状态
- 后29位是wc(workerCount), 表示工作线程(Worker)的数量

作者还提供了一些位运算的方法来切割、缝合、比较 rs/wc 的值
```java
private final AtomicInteger ctl = new AtomicInteger(ctlOf(RUNNING, 0));
private static final int COUNT_BITS = Integer.SIZE - 3;
private static final int CAPACITY   = (1 << COUNT_BITS) - 1;

// 这里有五个静态变量, 分别代表着五种不通的线程池状态
private static final int RUNNING    = -1 << COUNT_BITS;
private static final int SHUTDOWN   =  0 << COUNT_BITS;
private static final int STOP       =  1 << COUNT_BITS;
private static final int TIDYING    =  2 << COUNT_BITS;
private static final int TERMINATED =  3 << COUNT_BITS;

// 与 CAPACITY 的反码相与获取线程状态
private static int runStateOf(int c)     { return c & ~CAPACITY; }
// 与 CAPACITY 相与获取工作线程数量
private static int workerCountOf(int c)  { return c & CAPACITY; }
// 将 rs 和 wc 缝合, 组装成 ctl
private static int ctlOf(int rs, int wc) { return rs | wc; }

...... 等其他runState判断/workerCount获取方法
```

## 1.2.其他
```java
// 阻塞队列
private final BlockingQueue<Runnable> workQueue;
// ctl 值修改用的是 CAS
// 获取线程池状态, 工作线程数量, 控制线程 shutdown 用的是这把独占锁
private final ReentrantLock mainLock = new ReentrantLock();
// 所有的工作线程
private final HashSet<Worker> workers = new HashSet<Worker>();
// 为了延迟过期方法 awaitTermination() 设计的 
private final Condition termination = mainLock.newCondition();

// 线程池状态
private int largestPoolSize;
private long completedTaskCount;

// 线程池构造函数七大参数
private volatile ThreadFactory threadFactory;
private volatile RejectedExecutionHandler handler;
private volatile long keepAliveTime;
private volatile boolean allowCoreThreadTimeOut;
private volatile int corePoolSize;
private volatile int maximumPoolSize;

// 缺省的拒绝策略
private static final RejectedExecutionHandler defaultHandler =
    new AbortPolicy();
```

## 2.execute
终于到 execute() 了, 这是线程池实现的最为核心的方法.   
execute() 的最上层主要控制了新的 task 被执行前, 必经的三个步骤:
1.核心线程没有创建满, 则直接创建核心线程. 这里有个细节, 源码中的实现是 addWorker(command, true), 代表着 command 会直接被 Worker 消费 
2.核心线程满了, 则将 task 丢入阻塞队列(BlockingQueue)
3.阻塞队列满了, 则开启新的工作线程
4.工作线程空闲一段时间后(空闲时间可以配置), 会自动销毁
5.工作线程也创建满了, 会执行拒绝策略, 默认拒绝策略为 AbortPolicy
```java
public void execute(Runnable command) {
    if (command == null)
        throw new NullPointerException();
    int c = ctl.get();
    // 当工作线程总数小于设定的核心线程数时
    if (workerCountOf(c) < corePoolSize) {
        // 添加核心线程 addWorker(command, true)中
        // true代表核心线程
        // false 代表非核心线程
        if (addWorker(command, true))
            return;
        c = ctl.get();
    }
    // 检查线程池状态, 没问题的话, 将其装入阻塞队列
    if (isRunning(c) && workQueue.offer(command)) {
        int recheck = ctl.get();
        // 再次线程池状态, 如果非 Running 状态则删除队列中的 command
        if (! isRunning(recheck) && remove(command))
            // 执行拒绝策略
            reject(command);
        // 线程池状态为 Running 或者工作线程数量没有为 0 时, 创建新的 worker
        // 这步是一个小优化
        else if (workerCountOf(recheck) == 0)
            addWorker(null, false);
    }
    // 没有装入阻塞队列则执行拒绝策略
    else if (!addWorker(command, false))
        reject(command);
}
```

## 2.1.addWorker
在 execute() 中比较核心的方法为 addWorker(). 这个方法是创建核心线程和工作线程的入口  
Worker 在后文会详细介绍. 它的概念是线程池中的工作线程, 每个工作线程就像是一个消费任务的消费者, 它消费的任务就是一个个我们自定义的 Runnable 接口实现
```java
    private boolean addWorker(Runnable firstTask, boolean core) {
        // ===================================================
        // 下面用等于号括起来的这一大段, 其实就是些状态控制, 看懂了也不太有用
        // 只需要了解它主要是为了校验线程池状态是否正常
        // 并且对线程数量进行判断, 如果超过限制就不创建
        // 需要在 CAS 变更 ctl 中的 workCount 的值后, 才能进入真正创建 Worker 的地方
        retry:
        // 自旋
        for (;;) {
            int c = ctl.get();
            int rs = runStateOf(c);

            // Check if queue empty only if necessary.
            // 线程池状态 >= SHUTDOWN, 也就是非 Running 状态
            if (rs >= SHUTDOWN &&
                // 排除一些特殊情况
                ! (rs == SHUTDOWN &&
                   firstTask == null &&
                   ! workQueue.isEmpty()))
                return false;

            // 又是一个自旋
            for (;;) {
                int wc = workerCountOf(c);
                if (wc >= CAPACITY ||
                    // 当前新增的是核心线程时, 则判断 wc >= corePoolSize
                    // 当前新增的是工作线程时, 则判断是否超过线程池总量
                    wc >= (core ? corePoolSize : maximumPoolSize))
                    return false;
                if (compareAndIncrementWorkerCount(c))
                    // 确保自增 workerCount 成功, 退出所有循环
                    // 这种写法在 java 中并不推荐
                    break retry;
                c = ctl.get();  // Re-read ctl
                // 多次检查线程池状态
                if (runStateOf(c) != rs)
                    // 同样不推荐这种写法
                    continue retry;
                // else CAS failed due to workerCount change; retry inner loop
            }
        }
        // ============================================

        // 两个事件的标记位, 对理解业务逻辑有帮助
        boolean workerStarted = false;
        boolean workerAdded = false;
        Worker w = null;
        try {
            // 创建一个 Worker 也就是工作线程
            w = new Worker(firstTask);
            final Thread t = w.thread;
            if (t != null) {
                // 在很多需要修改线程池状态的时候, 都会用到 mainLock
                // 就像是操作系统的锁总线, 个人认为性能还是有优化的空间
                // 不过线程池中并发总数并不会高的离谱, 为了实现的简洁, 还是可以舍弃的
                final ReentrantLock mainLock = this.mainLock;
                mainLock.lock();
                try {
                    // Recheck while holding lock.
                    // Back out on ThreadFactory failure or if
                    // shut down before lock acquired.
                    // 这里是 DCL 的实现, 有兴趣的同学可以去搜一搜, 面试常问
                    int rs = runStateOf(ctl.get());

                    if (rs < SHUTDOWN ||
                        (rs == SHUTDOWN && firstTask == null)) {
                        if (t.isAlive()) // precheck that t is startable
                            throw new IllegalThreadStateException();
                        // 工作线程都会被放到 workers 这个容器中强引用, 防止被 GC
                        workers.add(w);
                        // 更新全局缓存的工作线程的数量
                        int s = workers.size();
                        if (s > largestPoolSize)
                            largestPoolSize = s;
                        // 更新标志位
                        workerAdded = true;
                    }
                } finally {
                    mainLock.unlock();
                }
                if (workerAdded) {
                    // 启动线程, 调用 Worker 对象的 run() 方法
                    t.start();
                    workerStarted = true;
                }
            }
        } finally {
            if (! workerStarted)
                addWorkerFailed(w);
        }
        return workerStarted;
    }
```


## 3.Worker
至此, 线程池的新增工作线程的核心代码都梳理完了. 那么 Worker 又是怎样消费任务的呢?  
来看一下 Worker 的主要结构.
```java
private final class Worker
    extends AbstractQueuedSynchronizer
    implements Runnable
{
    private static final long serialVersionUID = 6138294804551838833L;
    final Thread thread;
    Runnable firstTask;
    volatile long completedTasks;

    Worker(Runnable firstTask) {
        // 确保独占锁释放
        setState(-1); // inhibit interrupts until runWorker
        // 将要执行的任务放到这个变量里, 可以为 null
        this.firstTask = firstTask;
        // 创建一个新的线程
        this.thread = getThreadFactory().newThread(this);
    }

    public void run() {
        runWorker(this);
    }

    protected boolean isHeldExclusively() { ... }

    protected boolean tryAcquire(int unused) { ... }

    protected boolean tryRelease(int unused) { ... }

    public void lock()        { acquire(1); }
    public boolean tryLock()  { return tryAcquire(1); }
    public void unlock()      { release(1); }
    public boolean isLocked() { return isHeldExclusively(); }

    void interruptIfStarted() { ... }
}
```

- Worker 实现了 Runnable 接口, 因为 Worker 其实就是对线程 Thread 的一种封装, 回想一下如何创建一个新的线程. 我们需要有类似这样的代码 new Thread(() -> { doSomething }).start(); 这里的 lambda 表达式就是个 Runnable 接口, 那么在上文 addWorker() 执行到 t.start() 方法的时候, 其实就是调用 Worker 对象的 run() 方法.
- Worker 继承 AQS 并简单实现了一把独占锁. 这把独占锁是为了保证在 Worker 运行的时候, 有且仅有一个任务被执行. 防止一个 Worker 同时消费两个 task

## 3.1.Worker.run
上文详细讲解了 Worker 的 run() 调用时机是 ThreadPoolExecutor 下的 execute() 调用了 addWorker(), 再调用 thread.start() 执行 Worker 里的 run().    
这里 run() 方法比较简单
```java
/** Delegates main run loop to outer runWorker  */
// Worker 是 ThreadPoolExecutor 的静态内部类, 这里将控制交还给 ThreadPoolExecutor
// 没什么实际意义, 只是将业务代码换了个地方放而已
public void run() {
    runWorker(this);
}
```


## 3.2.ThreadPoolExecutor.runWorker
Worker 的 run() 方法其实又调用了 ThreadPoolExecutor 的 runWorker() 方法.  
在 runWorker() 中, 
```java
final void runWorker(Worker w) {
    // 获取当前线程
    Thread wt = Thread.currentThread();
    // 如果是核心线程, 那么第一次进入该方法, 会有 firstTask
    // 如果是工作线程, 那么就是 null
    Runnable task = w.firstTask;
    w.firstTask = null;
    w.unlock(); // allow interrupts
    boolean completedAbruptly = true;
    try {
        // task != null 是针对核心线程第一次刚创建出来的时候的处理
        // (task = getTask()) != null 中 getTask 会自旋获取 task
        while (task != null || (task = getTask()) != null) {
            // 进入这个方法, 肯定是由 task 可以执行的
            w.lock();
            // 线程池是否是STOP状态, 如果是，则确保当前线程是中断状态
            // If pool is stopping, ensure thread is interrupted;
            // 如果不是，则确保当前线程不是 中断状态
            // if not, ensure thread is not interrupted.  This
            // requires a recheck in second case to deal with
            // shutdownNow race while clearing interrupt
            if ((runStateAtLeast(ctl.get(), STOP) ||
                 (Thread.interrupted() &&
                  runStateAtLeast(ctl.get(), STOP))) &&
                !wt.isInterrupted())
                wt.interrupt();
            try {
                // 这个方法没有具体实现, 留了个语义在这里, 子类有需要就实现
                beforeExecute(wt, task);
                Throwable thrown = null;
                try {
                    // 执行 task
                    task.run();
                // 下面是一堆异常处理
                } catch (RuntimeException x) {
                    thrown = x; throw x;
                } catch (Error x) {
                    thrown = x; throw x;
                } catch (Throwable x) {
                    thrown = x; throw new Error(x);
                } finally {
                    // 这个方法没有具体实现, 留了个语义在这里, 子类有需要就实现
                    afterExecute(task, thrown);
                }
            } finally {
                task = null;
                // 更新 worker 的监控项
                w.completedTasks++;
                // 并且解锁
                w.unlock();
            }
        }
        completedAbruptly = false;
    } finally {
        // 做些 worker 退出后的清理工作
        processWorkerExit(w, completedAbruptly);
    }
}
```

## 3.2.1.getTask
getTask(): 通过阻塞的形式从阻塞队列中获取任务的方法. 如果获取不到则返回 null.  
需要注意: 这里代码中有一处自旋, 并非是自旋获取任务

这个方法主要是开启自旋从阻塞队列中获取任务. 并且在线程池状态非 Running 的情况下, Worker 安全关闭 (processWorkerExit).

期间以阻塞的形式获取 task, 并判断当前 worker 是否参与过期计算, 闲置时间是否过长 (大于 keepAliveTime). 如果超时, Worker 安全关闭(processWorkerExit)
```java
private Runnable getTask() {
    boolean timedOut = false; // Did the last poll() time out?

    // 开启自旋
    for (;;) {
        int c = ctl.get();
        int rs = runStateOf(c);

        // Check if queue empty only if necessary.
        // 判断线程状态在非 Running 情况下, 安全退出
        if (rs >= SHUTDOWN && (rs >= STOP || workQueue.isEmpty())) {
            // 由于 workerCount 在 ctl 中, 自减需要保证原子性, 这里用的是 CAS
            // 由于低 29 位表示 workerCount, 所以直接 ctl-1 就行了
            decrementWorkerCount();
            // 返回 null 上层方法 runWorker() 会认为是突然完成, 直接走 finally 代码块儿中的 prcessWorkerExit(w, false)
            return null;
        }

        int wc = workerCountOf(c);

        // Are workers subject to culling?
        // 工人会被淘汰吗？
        // allowCoreThreadTimeOut 定义核心线程是否参与超时计算默认为false
        // 再判断一下, workers 的数量是否大于 corePoolSize
        boolean timed = allowCoreThreadTimeOut || wc > corePoolSize;

        // 首先要满足第一组条件: Worker 的数量要大于最大线程数 或 线程空闲时间过长
        if ((wc > maximumPoolSize || (timed && timedOut))
            // 其次要满足第二组条件: Woker 的数量不为零 或者 阻塞队列为空
            && (wc > 1 || workQueue.isEmpty())) {
            if (compareAndDecrementWorkerCount(c))
                return null;
            continue;
        }

        try {
            // 当前 Worker 的本次 getTask() 操作是否参与超时时间计算?
            Runnable r = timed ?
                // 如果参与, 则调用 queue.poll(timeout, unit)
                workQueue.poll(keepAliveTime, TimeUnit.NANOSECONDS) :
                // 不参与则调用阻塞获取 task
                workQueue.take();
            if (r != null)
                return r;
            timedOut = true;
        } catch (InterruptedException retry) {
            timedOut = false;
        }
    }
}
```

## processWorkerExit
核心方法: 安全关闭 Worker 的方法.   
```java
private void processWorkerExit(Worker w, boolean completedAbruptly) {
    //如果 completedAbruptly = true ，则线程执行任务的时候出现了异常，需要从线程池中减少一个线程
    //如果 completedAbruptly = false，则执行getTask方法的时候已经减1，这里无需在进行减1操作
    if (completedAbruptly) // If abrupt, then workerCount wasn't adjusted
        decrementWorkerCount();

    final ReentrantLock mainLock = this.mainLock;
    mainLock.lock();
    try {
        // 修改线程池监控的一些变量
        completedTaskCount += w.completedTasks;
        workers.remove(w);
    } finally {
        mainLock.unlock();
    }
    // 根据线程池的状态，决定是否结束该线程池
    tryTerminate();

    int c = ctl.get();
    if (runStateLessThan(c, STOP)) {
        // 当线程池是RUNNING或SHUTDOWN状态时，如果worker是异常结束，那么会直接addWorker
        // 如果allowCoreThreadTimeOut=true，并且等待队列有任务，至少保留一个worker
        // 如果allowCoreThreadTimeOut=false，活跃线程数不少于corePoolSize
        if (!completedAbruptly) {
            int min = allowCoreThreadTimeOut ? 0 : corePoolSize;
            if (min == 0 && ! workQueue.isEmpty())
                min = 1;
            if (workerCountOf(c) >= min)
                return; // replacement not needed
        }
        addWorker(null, false);
    }
}
```