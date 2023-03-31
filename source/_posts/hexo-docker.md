---
title: docker-compose管理Hexo急速建站-Hexo建站(二)  
tags: Hexo
date: 2021/1/19
categories:
- Hexo
keywords: [Hexo,建站,docker-compose,docker]
description: 使用 docker 作为容器 docker-compose 进行容器编排 Hexo 达到快速建站的目的
---

上回介绍了如何在 Linux 服务器上急速建站, 如果对上文感兴趣的同学可以移步: {% post_link  hexo-linux %}
本节主要介绍使用 docker 作为容器 docker-compose 进行容器编排达到快速建站的目的.   
<!-- more -->

以下是这套建站方案带来的其它优点:  
- docker 容器优秀的隔离性, 能让我们的服务器环境更加整洁
- docker-compose 方便在服务器迁移、硬盘损坏等意外情况发生后, 可以再次快速将 hexo 极速启动起来.
- docker-compose 能将不健康状态的应用自动拉起, 在 hexo 由于各种意外情况导致奔溃后, 可以自动重启
- 将 hexo 所有配置及博文上传至 git 远程仓库(Github | Gitee), 利用 git 版本管理, 在误操作导致 hexo 项目状态到了不可修复的状态, 可以 reset 版本, 这样就可以放心折腾 hexo 了,
  
废话不多说, 操作起来.

# 安装条件
开发环境(本机):
- [idea](https://www.jetbrains.com/idea/download/)
- [git](https://www.git-scm.com/download/)

生产环境(Linux服务器):
- [docker](https://www.docker.com/)
- [docker-compose](https://docs.docker.com/compose/install/)
- [git](https://www.git-scm.com/download/)

# 选择 docker image
去 [Docker Hub](https://hub.docker.com/)  上搜索 hexo. 笔者过滤了一个比较靠谱的镜像[spurin/hexo](https://hub.docker.com/r/spurin/hexo)
![](spurin-hexo.png)
将它启动起来之后  
```shell
docker create --name=hexo-domain.com \
-e hexo_SERVER_PORT=4000 \
-e GIT_USER="Your Name" \
-e GIT_EMAIL="your.email@domain.tld" \
-v /blog/domain.com:/app \
-p 4000:4000 \
spurin/hexo
```

这里我们一起读一下日志, 看看这个 image 到底是怎么回事  
`注意:`由于容器里使用的 github 的仓库. clone 代码会消耗大量时间. 而且 npm 也没有换成 cnpm 亦或是改了国内镜像源, 在 npm install 那一步也会消耗大量时间, 请耐心等待!
``` shell
Attaching to hexo
# docker image下 /app 文件夹是空的, 初始化 hexo 和 hexo admin
hexo      | ***** App directory is empty, initialising with hexo and hexo-admin *****
# 从 github 下载 hexo-starter 源码
hexo      | INFO  Cloning hexo-starter https://github.com/hexojs/hexo-starter.git
# 拷贝至 /app 目录, 这个路径就是存放源代码、依赖、blog的地方
hexo      | Cloning into '/app'...
# 下载依赖
hexo      | INFO  Install dependencies
hexo      | yarn install v1.22.4
hexo      | info No lockfile found.
# 这里是 hexo-starter 的初始化脚本
hexo      | [1/4] Resolving packages...
hexo      | warning hexo-renderer-stylus > stylus > css-parse > css > urix@0.1.0: Please see https://github.com/lydell/urix#deprecated
hexo      | warning hexo-renderer-stylus > stylus > css-parse > css > source-map-resolve > urix@0.1.0: Please see https://github.com/lydell/urix#deprecated
hexo      | warning hexo-renderer-stylus > stylus > css-parse > css > source-map-resolve > resolve-url@0.2.1: https://github.com/lydell/resolve-url#deprecated
hexo      | [2/4] Fetching packages...
hexo      | info fsevents@2.3.2: The platform "linux" is incompatible with this module.
hexo      | info "fsevents@2.3.2" is an optional dependency and failed compatibility check. Excluding it from installation.
hexo      | [3/4] Linking dependencies...
hexo      | [4/4] Building fresh packages...
hexo      | success Saved lockfile.
hexo      | Done in 57.83s.
hexo      | INFO  Start blogging with Hexo!
# 开始下载 npm 依赖了, 
hexo      | npm WARN deprecated urix@0.1.0: Please see https://github.com/lydell/urix#deprecated
hexo      | npm WARN deprecated resolve-url@0.2.1: https://github.com/lydell/resolve-url#deprecated
===============================
# 这里我删除了很多 npm WARN 日志, 因为太多了, 而且看这个没什么必要
# 只要 npm 报的是 WARN 我们就可以不用理会, 如果报了 ERROR 级别的, 那么需要检查网络, 并重新下载依赖了!
===============================
hexo      | + hexo-admin@2.3.0
hexo      | added 437 packages from 507 contributors and audited 634 packages in 291.059s
hexo      | 21 packages are looking for funding
hexo      |   run `npm fund` for details
hexo      | found 19 vulnerabilities (4 low, 6 moderate, 8 high, 1 critical)
hexo      |   run `npm audit fix` to fix them, or `npm audit` for details
hexo      | ***** App directory contains no requirements.txt file, continuing *****
# 这里会将我们宿主机上 /root/.ssh 文件夹下的 git 秘钥 copy 至 docker image 里
hexo      | ***** App .ssh directory is empty, initialising ssh key and configuring known_hosts for common git repositories (github/gitlab) *****
hexo      | ***** Running git config, user = z_true, email = z_true@163.com *****
hexo      | ***** Copying .ssh from App directory and setting permissions *****
hexo      | ***** Contents of public ssh key (for deploy) - *****
# 笔者的 ssh 秘钥就不给大家展示了
hexo      | ssh-rsa *********************
hexo      | ***** Starting server on port 4000 *****
hexo      | INFO  Validating config
hexo      | INFO  Start processing
hexo      | Deprecated as of 10.7.0. highlight(lang, code, ...args) has been deprecated.
hexo      | Deprecated as of 10.7.0. Please use highlight(code, options) instead.
hexo      | https://github.com/highlightjs/highlight.js/issues/2277
# 启动成功, 对 docker container 中 4000 端口进行监听
hexo      | INFO  Hexo is running at http://localhost:4000 . Press Ctrl+C to stop.
```

总而言之这个镜像就是将官方推荐的一种 hexo 部署方式: 从 `https://github.com/hexojs/hexo-starter.git` 将启动代码拉下来然后执行 npm install.  
打包成了 docker-image. 并且这个 docker-image 中还帮我们安装了 node.js, git 等环境. 我们可以利用这个特性来搭建自己的 hexo 了

# docker-compose 编排 hexo 容器
`注意: `一定要在 Linux 服务器上安装 docker 及 docker-compose, 下载链接请跳转至[安装条件](#安装条件)  
在服务器任意位置, 添加 docker-compose.yml 配置文件
```yaml
version: '2'
services:
  hexo: # 容器名, 有个性化需求的同学可以修改
    container_name: hexo 
    restart: always # 启动方式
    image: spurin/hexo # 镜像勿动
    environment:
      hexo_SERVER_PORT: 4000 # 缺省的端口号
      GIT_USER: <your_name> # image内部安装了 git, 有需要的同学可以修改
      GIT_EMAIL: <your_email>
    ports:  # 端口映射
      - 4000:4000
    volumes: # 磁盘映射
      # 这个镜像将 workspace 设置为了 /app, 我们需要将它持久化到宿主机上 
      # exp: /usr/local/docker/hexo/hexo-starter:/app:rw
      - <your_volume_workspace>:/app:rw
```

后台启动 hexo
```shell
# up 是启动容器, -d 表示后台启动
docker-compose up -d
```
查看 hexo日志
```shell
# 注意命令里的 hexo 与 docker-compose.yml 里的 container_name 需对应
docker-compose logs -f hexo
```

当我们看到以下日志, 并全程没有报 ERROR 级别的日志, 那么就说明初始化成功了
```shell
hexo      | INFO  Hexo is running at http://localhost:4000 . Press Ctrl+C to stop.
```

退出日志, 在宿主机(服务器环境)校验 hexo 是否安装成功. 校验方式可以是:
- 访问`http://<host>:4000` 可以看到hello-world
- 因为我们将 hexo container 中的 4000 端口挂载至宿主机的 4000 端口, 所以也可以直接 `curl localhost:4000`

  ![](hexo-hello-word.png)

# GitHub Fork Hexo Starter
每次新增博客, 都要去容器里使用 `hexo new <title>` 实在太过麻烦. 所以将博客交由 git remote repository 管理. 这里先介绍使用 GitHub管理的方式  
首先需要有你的 Github 账号, 并将开源项目 hexo starter 的代码 fork 到你的私人仓库里, 后期编写博客、添加 hexo 插件维护都交给代码仓库存储, 方便又高效
```url
# 代码仓库地址
https://github.com/hexojs/hexo-starter
```
  
![](fork-hexo-starter.png)

## Gitee 建仓 (可选)
众所周知, 我大天朝访问 GitHub 就很玄幻, 所以我选择将代码迁移至 [Gitee](https://gitee.com/). 码云的服务器在中国, 网速很给力, 在频繁使用 docker pull 更新博客的时候有很大的帮助. 这里教大家一种简单的方法.
1. 使用 idea + git 将项目 clone 到本地电脑
   ![](starter-to-local1.png)  
2. 打开本地项目根目录
   ![](open-folder.png)  
3. 删除`.git`文件夹, 找不到的同学请打开隐藏文件夹
   ![](delete_git_folder.png)  
4. 在 idea 中开启 Terminal, 缺省在 idea 下方. 并且缺省打开项目根目录
   ![](open-terminal.png)  
5. 在 gitee 中注册账号并新建一个代码仓库, 这里不作过多展开
6. 由于当前的项目在 step3 与原 github 的仓库已经解除了绑定, 接下来将本项目与 gitee 上的远程仓库绑定
```shell
# 建立本地仓库
git init
# 将 your_name 修改为你的用户名
# 将your_remote_repository 改为你的仓库名
# exp: https://gitee.com/zture/hexo.git
git remote add origin https://gitee.com/<your_name>/<your_remote_repository>.git
# 将本地项目推送至远程仓库
git push -u origin master
```

## 将仓库里的代码下载到 Linux
1. 先进入[hexo镜像/app目录挂载至宿主机的目录](#docker-compose 编排 hexo 容器)
```shell
cd <your_volumes_workspace>
```

2. 这一步一定要`谨慎操作!!!`将刚才 hexo image 下载的东西全清理掉  
`注意: 请注意文件路径. 不要误操作, 将服务器清空了`
```shell
rm -rf *
```

3. 将 git 仓库里的代码 clone 下来
```shell
git clone https://gitee.com/zture/hexo.git <your_volumes_workspace>
```

4. 下载依赖
```shell
npm install
```

5. 重启hexo
```shell
# 修改 docker-compose.yml 存在的路径
cd <docker-compose.yml_path>
docker-compose restart hexo
```

6. 验证  
在浏览器中输入 `http://<host>:4000` 查看 hexo 的 hello-word 页面是否能看见
   ![]() hexo-hello-word.png %}  

## 代码更新脚本(可选)
当我们修改全局配置 `_config.yml` 文件之后, 需要重启 hexo. 但每次需要拉取 git 代码, 然后再 docker-compose 重启 hexo 就很麻烦. 我们写个简单的脚本放在项目根目录下就可以了. 注意配置 Linux 可执行文件权限
```shell
git pull
chmod +5 *.sh

# ↓修改为你docker-compose.yml的存放文件夹
# exp: cd /usr/local/docker
cd <docker-compose.yml_path>
docker-compose restart hexo
```

## Git 提交脚本
我们会在 hexo 中添加许多插件/主题/配置. 这时候也需要将它们提交. 
```shell
git pull
chmod +5 *.sh

git add -A
git commit -m "linux auto commit"
git push origin master
```

## 我的项目结构
![]() hexo-project-structure.png %}  

