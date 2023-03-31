---
title: Jenkins离线解决插件兼容性-Jenkins(二)   
tags: Jenkins
date: 2021/3/30
categories:
- Jenkins
keywords: [Jenkins,Plugin,插件]
description: Jenkins离线解决插件兼容性    
---
最近笔者公司在大势所趋下, 终于将代码管理工具从 Subversion 换成了 Git. 代码仓库选用的是 Gitlab, 由于原先项目就使用 Jenkins 做编译服务器, 版本为 2.2204.0. 与现在 Jenkins Release 最新的稳定版本 2.289.1 还是有一定时间差距的, 那么大部分最新的插件都无法直接集成.

<!-- more -->
# 背景介绍
笔者需要完成开发者将代码提交到 Gitlab 的指定分支后, 通过 webhook 将事件主动推送给 Jenkins服务器. 对如何推送感兴趣的同学请移步博文 [GitLab 自动触发 Jenkins 构建
](https://www.jianshu.com/p/eeb15a408d88)  
笔者在安装 gitlab hook 和 gitlab plugin 两个插件时遇到了插件兼容性问题

# 插件之间版本不兼容

![](plugin-plugin.png)

从上图中, 我们很容易可以得知: Gitflow Plugin:v1.0.1 安装失败了. 原因是缺少它的依赖项 maven-plugin:v2.13 后的版本. 这里推荐去国内的镜像站, 如清华大学的镜像站: https://mirrors.tuna.tsinghua.edu.cn/jenkins/

下载最新版本插件, 下载的插件都是 *.hpi 结尾的. 如果 Jenkins 服务器可以访问公网, 那么直接进入 Jenkins -> Manage Jenkins -> Manage Plugins -> update 勾选下载即可

# Jenkins版本太低导致插件不支持

![](plugin-jenkins-version.png)
从报错中可知, Pipeline Declarative Extension Points API:v1.3.2 版本的这款插件不支持在 Jenkins:v2.60.3 中运行, 只需要将 Jenkins 的版本提升到 2.73.3 以上就可以了  

前往 Jenkins 官网自行下载最新版 https://www.jenkins.io/download/
注意: 各位同学根据自己环境上 Jenkins 部署的方式选择升级方案

## Jenkins版本升级后有BUG
`但是笔者碰到一个比较坑的事情, 公司部署的 Jenkins 在升级 war 包之后, 在 project config 页面出现了致命 bug, 导致无法操作项目配置. 那么留给我的路只有两条: 1. 卸载旧版 Jenkins 2. 对插件版本进行降级`  
在实际操作中, 考虑到原先部署的 Jenkins 中各色插件、全局配置, 情况较为复杂, 所以卸载旧版 Jenkins 重新部署, 对我来说代价也比较大. 所以选择了第二条路, 放弃最新版的插件, 转而选择降低 plugin 版本, 来兼容 Jenkins 版本.  

这里需要注意的是, Jenkins 虽然三方插件非常强大, 但是没有像 maven 一样的 dependency tree, 我们只能一个个版本去尝试.  
如果遇到由于插件安装失败而无法卸载. 我们还可以进入 Jenkins 的工作目录, 笔者是 docker 方式部署的, 进入容器后进入工作目录
```shell
jenkins@f1be5415da22:~$ pwd
/var/jenkins_home
```

进入插件文件夹, 并将安装失败的插件删除
```shell
jenkins@f1be5415da22:~$ cd plugins/
jenkins@f1be5415da22:~/plugins$ ls
ace-editor
ace-editor.jpi
```

这里假设 ace-editor 插件安装失败了, 我们将它删除即可.     
没事别乱删插件! 没事别乱删插件! 没事别乱删插件!  
```shell
jenkins@f1be5415da22:~/plugins$ rm -rf ace-editor*
```

