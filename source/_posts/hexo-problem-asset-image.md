---
title: 使用Hexo-asset-image插件导致静态图片路径出错-Hexo采坑(二) 
tags: Hexo
date: 2021/5/21
categories:
- Hexo
keywords: [Hexo,Next,Bug]
description: 使用Hexo-asset-image插件导致静态图片路径出错
---
# 介绍
Hexo 官方提供的静态资源管理功能十分的鸡肋, 并且推荐我们通过安装 hexo-asset-image 来管理自己的静态图片.
<!-- more -->

# 故障描述
使用 Hexo-asset-image 插件静态图片路径会变成一个错误的路径.   
我们可以看到错误的 URL 中, 在 host:port 后, 明显多了一个 .cn 的资源目录, 这在使用域名部署的时候, 明显是不正确的
错误: http://blog.diswares.cn/.cn/java-multithreading-thread-pool/juc-thread-pools.png   
正确: http://blog.diswares.cn/java-multithreading-thread-pool/juc-thread-pools.png

# 解决方案
1. cd node_modules/hexo-asset-image/
2. vim index.js
3. 在 59 行附近, 将以下代码替换掉
    ```javascript
    // $(this).attr('src', config.root + link + src);
    // console.info&&console.info("update link as:-->"+config.root + link + src);
    $(this).attr('src', data.permalink +src);
    console.info&&console.info("update link as:-->" + data.permalink + src);
    ```