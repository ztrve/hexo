---
title: Hexo Next主题中文锚点失效-Hexo采坑(一) 
tags: Hexo
date: 2021/1/28
categories:
- Hexo
keywords: [Hexo,Next,Bug]
description: Hexo 5 安装 Next 主题后, 侧边栏目录中中文目录锚点点击后无法正常跳转
---
# 问题描述
Hexo 5 安装 Next 主题后, 侧边栏目录中中文目录锚点点击后无法正常跳转
<!-- more -->

# 故障描述
1. 点击后无法正常跳转.
   ![](step1.png)

2. 伴随控制台报错
   ![](step2.png)

# 问题定位
1. 知道是 'post-details.js' 文件报错后就简单了. 阅读源码后我们发现是 targetSelector 解析 UTF8 有问题
```javascript
  // TOC item animation navigate & prevent #item selector in adress bar.
  $('.post-toc a').on('click', function (e) {
    e.preventDefault();
    <!-- targetSelector 解析UTF8的问题 ->
    var targetSelector = NexT.utils.escapeSelector(this.getAttribute('href'));
    var offset = $(targetSelector).offset().top;

    hasVelocity ?
      html.velocity('stop').velocity('scroll', {
        offset: offset  + 'px',
        mobileHA: false
      }) :
      $('html, body').stop().animate({
        scrollTop: offset
      }, 500);
  });
```

# Bugfix
1. 将 targetSelector 再解析一次就好了
```javascript
    var targetSelector = NexT.utils.escapeSelector(this.getAttribute('href'));
    <!-- 添加下面这行代码, 重新解析 URL ->
    targetSelector = decodeURI(this.getAttribute('href'))
    var offset = $(targetSelector).offset().top;
```

