---
title: SpringKafka自动提交源码学习-Spring生态(二)  
tags: Spring Kafka  
date: 2021/6/24  
categories:
- Java
- Spring
- SpringKafka

keywords: [Spring,SpringKafka,自动提交,源码阅读,Java]   
description: SpringKafka自动提交源码实现-Spring生态(二)
---
Spring Kafka 可以为我们提供非常简单易用的的上层 API 支持. 在一般处理无需幂等的数据场景下, 我们可以使用默认配置 enable-auto-commit 来使用消息队列. 这里有个疑问, auto-commit 究竟是怎么实现的, 具体在怎样的场景中适用 auto-commit 配置? 带着这些问题, 本节基于 spring-kafka2.7.0 跟踪源码, 观察自动提交的底层实现.   
<!-- more -->
# 依赖
Spring Kafka 是对 kafka-client 的再封装, 这里列一下, 本文使用的 jar 包版本
- spring-kafka2.7.0
- kafka-client2.6.0


# 结论
为了方便大家往后理解源码实现, 先说结论.   
spring-kafka 中并没有实现自动提交的相关功能, 它只是将 'enable-auto-commit=true' 这个参数交给了 kafka-client. kafka-client 消费者每次成功从 Topic 拉取 (poll) 数据后, 都会递增更新消费者偏移量. kafka-client 中有个 SubscriptionState 的类, 专门存储当前消费者监听的 topics、partition、offset 信息.    
消费者 poll 消息前, 会触发对 GroupCoordinator 心跳机制校验, 在缺省配置中, kafka-client 每 5 秒会从 SubscriptionState 中获取当前消费者的所有 topics、partition、offset 信息, 并主动发起异步更新的请求.

![自动提交偏移量架构](auto-commit-offset.png)

# 源码跟踪
## SpringKafka源码doPoll
### KafkaMessageListenerContainer.doPoll
前置章节介绍了 spring-kafka 的结构, 我们知道 KafkaMessageListenerContainer 与 kafka-client 实例是一一对应的关系. 并且 KafkaMessageListenerContainer.doPoll() 这个方法是 consumer 获取消息 (Message) 的入口.  
在 doPoll() 中, 是调用 `this.consumer.poll(this.pollTimeout)` 主动拉取数据
```java
@Nullable
private ConsumerRecords<K, V> doPoll() {
	ConsumerRecords<K, V> records;
	if (this.isBatchListener && this.subBatchPerPartition) {
		if (this.batchIterator == null) {
			this.lastBatch = this.consumer.poll(this.pollTimeout);
			if (this.lastBatch.count() == 0) {
				return this.lastBatch;
			}
			else {
				this.batchIterator = this.lastBatch.partitions().iterator();
			}
		}
		TopicPartition next = this.batchIterator.next();
		List<ConsumerRecord<K, V>> subBatch = this.lastBatch.records(next);
		records = new ConsumerRecords<>(Collections.singletonMap(next, subBatch));
		if (!this.batchIterator.hasNext()) {
			this.batchIterator = null;
		}
	}
	else {
		records = this.consumer.poll(this.pollTimeout);
		checkRebalanceCommits();
	}
	return records;
}
```

> 前置章节内容请优先阅读  
> SpringKafka原理解析及源码学习-Spring生态(一): http://blog.diswares.cn/kafka-spring-kafka-structure/


### KafkaConsumer.poll
- 这个方法中可以看到一个 do while 的结构, while 中的判断我们可以知道, 当一次 poll 超过一定时间还是没有拉取到数据, 会认为本次拉取失败从而不继续 poll
- do while 里的代码块, 有两个比较关键的方法: updateAssignmentMetadataIfNeeded(timer, false) 和 pollForFetches(timer)
- updateAssignmentMetadataIfNeeded(timer, false): 此方法为自动提交偏移量的入口, 也是更新 fetcher 信息的入口
- pollForFetches(timer): 拉取新数据

```java
@Override
public ConsumerRecords<K, V> poll(final Duration timeout) {
    return poll(time.timer(timeout), true);
}

private ConsumerRecords<K, V> poll(final Timer timer, final boolean includeMetadataInTimeout) {
    acquireAndEnsureOpen();
    try {
        // 记录一下 本次 poll 的时间信息
        this.kafkaConsumerMetrics.recordPollStart(timer.currentTimeMs());

        if (this.subscriptions.hasNoSubscriptionOrUserAssignment()) {
            throw new IllegalStateException("Consumer is not subscribed to any topics or assigned any partitions");
        }

        // do while 直至超时
        do {
            client.maybeTriggerWakeup();

            if (includeMetadataInTimeout) {
                // 更新 Fetcher 的元信息并自动提交 offset
                updateAssignmentMetadataIfNeeded(timer, false);
            } else {
                while (!updateAssignmentMetadataIfNeeded(time.timer(Long.MAX_VALUE), true)) {
                    log.warn("Still waiting for metadata");
                }
            }

            // nio 拉取新消息
            final Map<TopicPartition, List<ConsumerRecord<K, V>>> records = pollForFetches(timer);
            if (!records.isEmpty()) {
                if (fetcher.sendFetches() > 0 || client.hasPendingRequests()) {
                    client.transmitSends();
                }

                return this.interceptors.onConsume(new ConsumerRecords<>(records));
            }
            // 超时校验
        } while (timer.notExpired());

        return ConsumerRecords.empty();
    } finally {
        release();
        this.kafkaConsumerMetrics.recordPollEnd(timer.currentTimeMs());
    }
}
```

## 拉取消息源码阅读
本节先讲解 [KafkaConsumer.poll](#KafkaConsumer.poll) 中 pollForFetches 分支的代码. 因为顺序思考 Kafka Consumer 拉取消息并提交偏移量的过程, 应该是先拉取消息, 后提交偏移量
### KafkaConsumer.pollForFetches
```java
private Map<TopicPartition, List<ConsumerRecord<K, V>>> pollForFetches(Timer timer) {
    long pollTimeout = coordinator == null ? timer.remainingMs() :
            Math.min(coordinator.timeToNextPoll(timer.currentTimeMs()), timer.remainingMs());

    // if data is available already, return it immediately
    final Map<TopicPartition, List<ConsumerRecord<K, V>>> records = fetcher.fetchedRecords();
    if (!records.isEmpty()) {
        return records;
    }

    // send any new fetches (won't resend pending fetches)
    fetcher.sendFetches();

    // We do not want to be stuck blocking in poll if we are missing some positions
    // since the offset lookup may be backing off after a failure

    // NOTE: the use of cachedSubscriptionHashAllFetchPositions means we MUST call
    // updateAssignmentMetadataIfNeeded before this method.
    if (!cachedSubscriptionHashAllFetchPositions && pollTimeout > retryBackoffMs) {
        pollTimeout = retryBackoffMs;
    }

    Timer pollTimer = time.timer(pollTimeout);
    client.poll(pollTimer, () -> {
        // since a fetch might be completed by the background thread, we need this poll condition
        // to ensure that we do not block unnecessarily in poll()
        return !fetcher.hasAvailableFetches();
    });
    timer.update(pollTimer.currentTimeMs());

    return fetcher.fetchedRecords();
}
```

### Fetcher.fetchRecords
继续跟踪上面代码块中的方法 fetchRecords 该方法是从 kafka-server 拉取数据和更新偏移量的入口
```java
public Map<TopicPartition, List<ConsumerRecord<K, V>>> fetchedRecords() {
    // fetched 应该是设计者认为 poll 下来的消息有很大可能是属于同一个 topic 的, 所以缓存了一个 map 方便查询
    Map<TopicPartition, List<ConsumerRecord<K, V>>> fetched = new HashMap<>();
    Queue<CompletedFetch> pausedCompletedFetches = new ArrayDeque<>();
    int recordsRemaining = maxPollRecords;

    try {
        // 这里会记录一个最大拉取条数
        while (recordsRemaining > 0) {
            if (nextInLineFetch == null || nextInLineFetch.isConsumed) {
                // 获取同步队列中的数据
                CompletedFetch records = completedFetches.peek();
                if (records == null) break; // 同步队列数据消费光了

                if (records.notInitialized()) {
                    try {
                        nextInLineFetch = initializeCompletedFetch(records);
                    } catch (Exception e) {
                        FetchResponse.PartitionData partition = records.partitionData;
                        if (fetched.isEmpty() && (partition.records == null || partition.records.sizeInBytes() == 0)) {
                            completedFetches.poll();
                        }
                        throw e;
                    }
                } else {
                    nextInLineFetch = records;
                }
                completedFetches.poll();
            } else if (subscriptions.isPaused(nextInLineFetch.partition)) {
                // ... 暂停消费时, 此处逻辑暂时不用深入
                log.debug("Skipping fetching records for assigned partition {} because it is paused", nextInLineFetch.partition);
                pausedCompletedFetches.add(nextInLineFetch);
                nextInLineFetch = null;
            } else {
                // fetchRecords() 会去拉取记录, 并修改本地缓存的偏移量
                // 下文会详细解释
                List<ConsumerRecord<K, V>> records = fetchRecords(nextInLineFetch, recordsRemaining);

                if (!records.isEmpty()) {
                    // 成功拉取到过数据, 将其记录下来
                    TopicPartition partition = nextInLineFetch.partition;
                    List<ConsumerRecord<K, V>> currentRecords = fetched.get(partition);
        
                    // 存储本次拉取到的消息的结果集
                    if (currentRecords == null) {
                        fetched.put(partition, records);
                    } else {
                        List<ConsumerRecord<K, V>> newRecords = new ArrayList<>(records.size() + currentRecords.size());
                        newRecords.addAll(currentRecords);
                        newRecords.addAll(records);
                        fetched.put(partition, newRecords);
                    }
                    recordsRemaining -= records.size();
                }
            }
        }
    } catch (KafkaException e) {
        if (fetched.isEmpty())
            throw e;
    } finally {
        completedFetches.addAll(pausedCompletedFetches);
    }

    return fetched;
}
```

```java
private List<ConsumerRecord<K, V>> fetchRecords(CompletedFetch completedFetch, int maxRecords) {
    if (!subscriptions.isAssigned(completedFetch.partition)) {
        log.debug("Not returning fetched records for partition {} since it is no longer assigned",
                completedFetch.partition);
    } else if (!subscriptions.isFetchable(completedFetch.partition)) {
        log.debug("Not returning fetched records for assigned partition {} since it is no longer fetchable",
                completedFetch.partition);
    } else {
        // 更新 subscriptions 缓存的偏移量
        FetchPosition position = subscriptions.position(completedFetch.partition);
        if (position == null) {
            throw new IllegalStateException("Missing position for fetchable partition " + completedFetch.partition);
        }
        
        if (completedFetch.nextFetchOffset == position.offset) {
            // 拉取数据, 并更新 nextInLineFetch 中缓存的的偏移量
            List<ConsumerRecord<K, V>> partRecords = completedFetch.fetchRecords(maxRecords);

            log.trace("Returning {} fetched records at offset {} for assigned partition {}",
                    partRecords.size(), position, completedFetch.partition);

            // 如果取到数据, 则更新偏移量 offset
            if (completedFetch.nextFetchOffset > position.offset) {
                FetchPosition nextPosition = new FetchPosition(
                        completedFetch.nextFetchOffset,
                        completedFetch.lastEpoch,
                        position.currentLeader);
                log.trace("Update fetching position to {} for partition {}", nextPosition, completedFetch.partition);
                // 将 offset 的最大值同步给 SubscriptionState
                subscriptions.position(completedFetch.partition, nextPosition);
            }
            
            // 更新各类缓存
            Long partitionLag = subscriptions.partitionLag(completedFetch.partition, isolationLevel);
            if (partitionLag != null)
                this.sensors.recordPartitionLag(completedFetch.partition, partitionLag);
            Long lead = subscriptions.partitionLead(completedFetch.partition);
            if (lead != null) {
                this.sensors.recordPartitionLead(completedFetch.partition, lead);
            }

            // 返回将要被消费的 Messages
            return partRecords;
        } else {
            log.debug("Ignoring fetched records for {} at offset {} since the current position is {}",
                    completedFetch.partition, completedFetch.nextFetchOffset, position);
        }
    }

    log.trace("Draining fetched records for partition {}", completedFetch.partition);
    completedFetch.drain();

    return emptyList();
}
```

### Fetcher.fetchRecords
```java
private List<ConsumerRecord<K, V>> fetchRecords(int maxRecords) {
    // Error when fetching the next record before deserialization.
    if (corruptLastRecord)
        throw new KafkaException("Received exception when fetching the next record from " + partition
                                     + ". If needed, please seek past the record to "
                                     + "continue consumption.", cachedRecordException);

    if (isConsumed)
        return Collections.emptyList();

    List<ConsumerRecord<K, V>> records = new ArrayList<>();
    try {
        // 遍历请求的最大次数
        for (int i = 0; i < maxRecords; i++) {
            if (cachedRecordException == null) {
                corruptLastRecord = true;
                // 去 server 端 poll 消息
                lastRecord = nextFetchedRecord();
                corruptLastRecord = false;
            }
            if (lastRecord == null)
                break;
            records.add(parseRecord(partition, currentBatch, lastRecord));
            recordsRead++;
            bytesRead += lastRecord.sizeInBytes();
            // 更新 Consumer 内存中缓存的偏移量
            nextFetchOffset = lastRecord.offset() + 1;
            cachedRecordException = null;
        }
    } catch (SerializationException se) {
        cachedRecordException = se;
        if (records.isEmpty())
            throw se;
    } catch (KafkaException e) {
        cachedRecordException = e;
        if (records.isEmpty())
            throw new KafkaException("Received exception when fetching the next record from " + partition
                                         + ". If needed, please seek past the record to "
                                         + "continue consumption.", e);
    }
    return records;
}
```

### 小结
本节以 SpringKafka 调用的其实是 Kafka Client 的 poll API 去远程获取消息. 而且当 poll 成功后, Kafka Client 中消费者对应的 partition 的偏移量会直接更新

## 自动提交偏移量源码阅读
从上文 [KafkaConsumer.poll](#KafkaConsumer.poll) 这节我们知道, 本段应从 updateAssignmentMetadataIfNeeded 方法入手, 来分析自动提交偏移量的源码
### KafkaConsumer.updateAssignmentMetadataIfNeeded
这个方法是自动提交偏移量的入口类. 其中 coordinator.poll(timer, waitForJoinGroup) 方法才是下级方法的入口. 比较隐蔽
```java
boolean updateAssignmentMetadataIfNeeded(final Timer timer, final boolean waitForJoinGroup) {
    // 自动提交的入口
    if (coordinator != null && !coordinator.poll(timer, waitForJoinGroup)) {
        return false;
    }

    return updateFetchPositions(timer);
}
```

### ConsumerCoordinator.poll
ConsumerCoordinator 这个类主要是控制 Consumer 的业务流程  
这个方法中没有特别需要注意的地方, 只需要知道它是调用 `maybeAutoCommitOffsetsAsync` 的入口

```java
public boolean poll(Timer timer, boolean waitForJoinGroup) {
    ....dosomething
    // ------------ 我忽略了了大段代码 -----------
    maybeAutoCommitOffsetsAsync(timer.currentTimeMs());
    return true;
}
```

### ConsumerCoordinator.maybeAutoCommitOffsetsAsync
好的终于进入正题, 这个方法可以说是自动提交的上层入口了吧. 主要方法就是调用了 `doAutoCommitOffsetsAsync` 方法.   
如果提交一条消息, 就需要建立一条链接, 则对 kafka-server 的开销太大. 这里用心跳机制, 维护了长链接. 我们的自动提交偏移量, 也正是心跳机制的部分实现.  
这里设计了一个 Timer 的工具, 每次自动提交时, 都会更新 Timer 记录的当前时间, 根据这个 currentTime, Timer 就可以处理一系列时间是否超时问题, 还是比较巧妙的.

```java
public void maybeAutoCommitOffsetsAsync(long now) {
    // 判断用户是否开启了自动提交. 缺省为开启
    if (autoCommitEnabled) {
        // 记录当前时间
        nextAutoCommitTimer.update(now);
        // 是否到了自动提交的时间
        if (nextAutoCommitTimer.isExpired()) {
            // 重置过期时间
            nextAutoCommitTimer.reset(autoCommitIntervalMs);
            // 异步自动提交偏移量
            doAutoCommitOffsetsAsync();
        }
    }
}
```

### ConsumerCoordinator.doAutoCommitOffsetsAsync
上文讲过, OffsetAndMetadata 偏移量和元数据信息, KafkaClient 是交给 SubscriptionState 这个类去维护的, 这里通过调用 subscriptions.allConsumed() 即可获得当前 Consumer 中所有 TopicPartition 的偏移量信息.

```java
private void doAutoCommitOffsetsAsync() {
    // 获取所有偏移量和元数据信息
    Map<TopicPartition, OffsetAndMetadata> allConsumedOffsets = subscriptions.allConsumed();
    log.debug("Sending asynchronous auto-commit of offsets {}", allConsumedOffsets);

    // commitOffsetsAsync 异步提交偏移量.
    commitOffsetsAsync(allConsumedOffsets, (offsets, exception) -> {
        // 下面的逻辑是提交成功后的回调, 不用太关注
        if (exception != null) {
            if (exception instanceof RetriableCommitFailedException) {
                log.debug("Asynchronous auto-commit of offsets {} failed due to retriable error: {}", offsets,
                    exception);
                nextAutoCommitTimer.updateAndReset(rebalanceConfig.retryBackoffMs);
            } else {
                log.warn("Asynchronous auto-commit of offsets {} failed: {}", offsets, exception.getMessage());
            }
        } else {
            log.debug("Completed asynchronous auto-commit of offsets {}", offsets);
        }
    });
}
```

### ConsumerCoordinator.commitOffsetsAsync
这个方法异步调用了 doCommitOffsetsAsync.    
值得注意的是 lookupCoordinator() 方法. 在 kafka 0.10 版本之后, offset 偏移量不再提交至 zookeeper, 新版本记录偏移量的是 KafkaServer 中的 GroupCoordinator. 故 lookupCoordinator() 实则为申请一个 GroupCoordinator 的连接

```java
public void commitOffsetsAsync(final Map<TopicPartition, OffsetAndMetadata> offsets, final OffsetCommitCallback callback) {
    invokeCompletedOffsetCommitCallbacks();

    if (!coordinatorUnknown()) {
        doCommitOffsetsAsync(offsets, callback);
    } else {
        // 这里由于一个 ConsumerCoordinator 可能会被多处调用
        // pendingAsyncCommits 这个对象是用来记录并发度的
        pendingAsyncCommits.incrementAndGet();
        // lookupCoordinator() 实则为申请一个 coordinator 的连接
        lookupCoordinator().addListener(new RequestFutureListener<Void>() {
            @Override
            public void onSuccess(Void value) {
                // 更新并发度
                pendingAsyncCommits.decrementAndGet();
                // 关键, 异步提交 offset
                doCommitOffsetsAsync(offsets, callback);
                client.pollNoWakeup();
            }

            @Override
            public void onFailure(RuntimeException e) {
                pendingAsyncCommits.decrementAndGet();
                completedOffsetCommits.add(new OffsetCommitCompletion(callback, offsets,
                        new RetriableCommitFailedException(e)));
            }
        });
    }

    // ensure the commit has a chance to be transmitted (without blocking on its completion).
    // Note that commits are treated as heartbeats by the coordinator, so there is no need to
    // explicitly allow heartbeats through delayed task execution.
    client.pollNoWakeup();
}
```

### ConsumerCoordinator.doCommitOffsetsAsync
关键为 sendOffsetCommitRequest(offsets) 这个方法提交了偏移量, 由于是异步的, 所以返回的还是 RequestFuture 这个数据结构.

```java
private void doCommitOffsetsAsync(final Map<TopicPartition, OffsetAndMetadata> offsets, final OffsetCommitCallback callback) {
    // 异步提交
    RequestFuture<Void> future = sendOffsetCommitRequest(offsets);
    final OffsetCommitCallback cb = callback == null ? defaultOffsetCommitCallback : callback;
    // 提交后的回调
    future.addListener(new RequestFutureListener<Void>() {
        @Override
        public void onSuccess(Void value) {
            if (interceptors != null)
                interceptors.onCommit(offsets);
            completedOffsetCommits.add(new OffsetCommitCompletion(cb, offsets, null));
        }

        @Override
        public void onFailure(RuntimeException e) {
            Exception commitException = e;

            if (e instanceof RetriableException) {
                commitException = new RetriableCommitFailedException(e);
            }
            completedOffsetCommits.add(new OffsetCommitCompletion(cb, offsets, commitException));
            if (commitException instanceof FencedInstanceIdException) {
                asyncCommitFenced.set(true);
            }
        }
    });
}
```

### 

```java
RequestFuture<Void> sendOffsetCommitRequest(final Map<TopicPartition, OffsetAndMetadata> offsets) {
    if (offsets.isEmpty())
        return RequestFuture.voidSuccess();

    // 获取 Coordinator
    Node coordinator = checkAndGetCoordinator();
    if (coordinator == null)
        return RequestFuture.coordinatorNotAvailable();

    // 封装要发送的 Topic 和偏移量信息
    Map<String, OffsetCommitRequestData.OffsetCommitRequestTopic> requestTopicDataMap = new HashMap<>();
    for (Map.Entry<TopicPartition, OffsetAndMetadata> entry : offsets.entrySet()) {
        // ======== 这里是分割线 =========
        // 隐藏了一大段获取 Topic 信息的代码
        // ======== 这里是分割线 =========
        requestTopicDataMap.put(topicPartition.topic(), topic);
    }

    // 一个提交 offset 偏移量的关键参数
    // 用于识别提交者信息
    final Generation generation;
    // ======== 这里是分割线 =========
    // 隐藏了一大段生成 generation 的代码
    // ======== 这里是分割线 =========
        
    // 封装自动提交请求中的 offset 信息
    OffsetCommitRequest.Builder builder = new OffsetCommitRequest.Builder(
            new OffsetCommitRequestData()
                    .setGroupId(this.rebalanceConfig.groupId)
                    .setGenerationId(generation.generationId)
                    .setMemberId(generation.memberId)
                    .setGroupInstanceId(rebalanceConfig.groupInstanceId.orElse(null))
                    .setTopics(new ArrayList<>(requestTopicDataMap.values()))
    );

    log.trace("Sending OffsetCommit request with {} to coordinator {}", offsets, coordinator);

    // 异步提交
    return client.send(coordinator, builder)
            .compose(new OffsetCommitResponseHandler(offsets, generation));
}
```

client.send(coordinator, builder) 即是真正提交偏移量的地方. client 的实现是 ConsumerNetworkClient 这个类如何实现的 nio 有兴趣的同学可以去研究一下.

### 小结
KafkaClient 的自动提交实现是随着心跳机制异步提交的. 