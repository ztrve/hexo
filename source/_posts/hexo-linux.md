---
title: 在 Linux 服务器上快速建站-Hexo建站(一)  
tags: Hexo
date: 2021/1/15
categories:
- Hexo
keywords: [Hexo,建站,Linux]
description: Hexo 在 Linux 服务器上快速建站
---

[Hexo](https://hexo.io/zh-cn/) 作为一款快速、简洁且高效的博客框架火了起来. Hexo 使用 `Markdown`（或其他渲染引擎）解析文章, 在几秒内, 即可利用靓丽的主题生成静态网页.  
<!-- more -->
本文主要是记录 Hexo 在 `linux服务器` 上部署的流程, 当然本站也是由 Hexo 搭建起来的.

## 安装条件
安装 Hexo 相当简单，只需要先安装下列软件即可

### 安装 Node.js
Node.js (Node.js 版本需不低于 10.13，建议使用 Node.js 12.0 及以上版本)
``` shell
sudo apt-get install nodejs
sudo apt-get install npm
```

安装完后, 校验 Node.js 安装成功
``` shell
node -v
npm -v
```

## 安装
由于 Hexo 是发布在 npm 上的前端项目, 我们直接使用 npm 全局安装 Hexo 就可以了, 非常方便
```shell
npm install -g hexo-cli
```

检查是否安装成功
```shell
hexo -v
```

接下来初始化hexo

```shell
hexo init myblog
```

这个myblog可以自己取什么名字都行，然后

``` shell
# 进入这个myblog文件夹
cd myblog 
npm install
```

新建完成后，指定文件夹目录下有：

- node_modules: 依赖包, 由npm下载的 hexo 项目的依赖, 不要去懂
- public：存放生成的页面
- scaffolds：生成文章的一些模板
- `source：用来存放你的文章`
- themes：主题
- `_config.yml: 博客的配置文件`

打开hexo的服务
```shell
hexo g
hexo server
```

在浏览器输入`http://<host>:4000`就可以看到你生成的博客了。   
**注意:** 记得检测防火墙配置

