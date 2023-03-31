---
title: 跟踪JVM源码了解AtomicInteger的底层实现-Java多线程(二)  
tags: AtomicInteger  
date: 2021/2/20  
categories:
- Java
- 多线程
keywords: [Java,多线程,AtomicInteger,JVM,Hotspot,源码阅读]  
description: 跟踪JVM源码了解AtomicInteger的底层实现-Java多线程(二)
---
本节主要讲解在跟踪 JVM 源码. 了解 AtomicInteger 的底层实现.  
上文提过 AtomicInteger 的实现中关键是调用了 `Unsafe.class.compareAndSwapInt()` 方法. 在 JDK .class文件反编译后的 Unsafe.class 中能看到 compareAndSwapInt 是用 native 关键字修饰的. 那我们要了解它的实现就必须阅读 JVM 的源码
<!-- more -->

# JVM
JVM 是一种规范. 在这个规范下有许多实现, 例如:
- OpenJDK
- Hotspot
- Jrocket
- J9
- TaobaoVM

我们平时在 linux 环境中用的就是 Hotspot VM. 所以本文也是对 Hotspot 的源码跟踪阅读.  

# Hotspot
没有 Hotspot 源码的同学可以移步上篇博文下载源码:  
{% post_link  java-hotspot-code-download %}  

# 源码跟踪
## unsafe
1. 上文提过 AtomicInteger 的实现中关键是调用了 `Unsafe.class.compareAndSwapInt()` 方法. 在 JDK .class文件反编译后的 Unsafe.class 中能看到 compareAndSwapInt 是用 native 关键字修饰的. 有 native 关键字, 说明调用的是 JVM 的本地方法  
```java
package sun.misc;
public final class Unsafe {
    // native 关键字, 说明调用的是 JVM 的本地方法
    public final native boolean compareAndSwapInt(Object var1, long var2, int var4, int var5);
}
```

2. 打开 hotspot 源码的同名的 cpp 文件, 即 `unsafe.cpp`, 路径为 'src\share\vm\prims\unsafe.cpp'. 这里有个同名方法 compareAndSwapInt(). 可以看到关键调用了 `Atomic::cmpxchg()`
```java
UNSAFE_ENTRY(jboolean, Unsafe_CompareAndSwapInt(JNIEnv *env, jobject unsafe, jobject obj, jlong offset, jint e, jint x))
  UnsafeWrapper("Unsafe_CompareAndSwapInt");
  oop p = JNIHandles::resolve(obj);
  jint* addr = (jint *) index_oop_from_field_offset_long(p, offset);
  return (jint)(Atomic::cmpxchg(x, addr, e)) == e; // 这行调用了 Atomic::cmpxchg()
UNSAFE_END
```

3. 找到 Atomic 的同名文件 `src\share\vm\runtime\atomic.cpp` 可以看到预编译时这里有个选择器, 判断在 linux OS 环境下, 会注入 `os_linux.inline.hpp` 的相关依赖
```cpp
#include "precompiled.hpp"
#include "runtime/atomic.hpp"
#ifdef TARGET_OS_FAMILY_linux // 关注这里
# include "os_linux.inline.hpp"
#endif
#ifdef TARGET_OS_FAMILY_solaris
# include "os_solaris.inline.hpp"
#endif
#ifdef TARGET_OS_FAMILY_windows
# include "os_windows.inline.hpp"
#endif
#ifdef TARGET_OS_FAMILY_aix
# include "os_aix.inline.hpp"
#endif
#ifdef TARGET_OS_FAMILY_bsd
# include "os_bsd.inline.hpp"
#endif
```

4. 打开 os_linux.inline.hpp. 这里运行时依赖了 `runtime/atomic.inline.hpp`
```cpp
#include "runtime/atomic.inline.hpp"
#include "runtime/orderAccess.inline.hpp"
#include "runtime/os.hpp"
```

5. 打开 atomic.inline.hpp 这里又是一个选择器, 在 linux_x86 中会注入 `atomic_linux_x86.inline.hpp`
```cpp
// Linux
#ifdef TARGET_OS_ARCH_linux_x86
# include "atomic_linux_x86.inline.hpp"
#endif
#ifdef TARGET_OS_ARCH_linux_sparc
# include "atomic_linux_sparc.inline.hpp"
#endif
#ifdef TARGET_OS_ARCH_linux_zero
# include "atomic_linux_zero.inline.hpp"
#endif
#ifdef TARGET_OS_ARCH_linux_arm
# include "atomic_linux_arm.inline.hpp"
#endif
#ifdef TARGET_OS_ARCH_linux_ppc
# include "atomic_linux_ppc.inline.hpp"
#endif
```

6. 最后打开 atomic_linux_x86.inline.hpp 可以看到如下代码. 
```cpp
inline jint     Atomic::cmpxchg    (jint     exchange_value, volatile jint*     dest, jint     compare_value) {
  int mp = os::is_MP();
  __asm__ volatile (LOCK_IF_MP(%4) "cmpxchgl %1,(%3)" // 汇编语句
                    : "=a" (exchange_value) // 输出寄存器
                    : "r" (exchange_value), "a" (compare_value), "r" (dest), "r" (mp) 
                    : "cc", "memory"); // 会被修改的寄存器
  return exchange_value;
}
```

7. 源码中主要了解以下几点:
- __asm__: 内联汇编指令的写法
- __volatile__: 是向 GCC 编译器声明不允许对该内联汇编优化
- LOCK_IF_MP(%4): 如果是多处理器，在指令前加上 LOCK 前缀，因为在单处理器中，是不会存在缓存不一致的问题的，所有线程都在一个 CPU 上跑，使用同一个缓存区，也就不存在本地内存与主内存不一致的问题，不会造成可见性问题
- cmpxchgl: 比较并交换操作数

# 小结
通过阅读源码我们可以得出以下结论:
- 执行 AtomicInteger.compareAndSet() 的时候会调用 unsafe.compareAndSwapInt
- unsafe.compareAndSwapInt 再去调用 JVM 源码中 unsafe.cpp 的源码
- unsafe.cpp 底层是调用了 Atomic::cmpxchg
- `Atomic::cmpxchg` 的实现是内联汇编指令 `LOCK cmpxchg`
- LOCK 指令防止 CPU 间的竞争导致非原子性的修改发生
- cmpxchgl 就是 compare and exchange 同 compare and swap, 作值修改操作 

