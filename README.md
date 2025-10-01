## 通过box64可以很好地运行dst和steamcmd，但还需面板做些适配

本分支在原版基础上做了以下调整：

- **镜像与入口脚本**
  - 修改 `docker-entrypoint.sh`，位于 `packager/docker-entrypoint.wrap.sh`。
  - 在入口脚本中增加了box64 安装步骤，用于兼容amd64/i386。

- **SteamCMD 适配**
  - 目前可以在容器内手动运行 `steamcmd` 与 DST 专服，功能正常。
  - 由于 SteamCMD 会自愈覆盖自身 ELF，因此：
    - 不能使用 `steamcmd.sh`（它内部调用 ELF 时无法加上 box 前缀）。
    - 必须直接调用二进制，并在前面显式加上 `box86` 或 `box64`，例如：
      ```
      box64 /steamcmd/linux32/steamcmd +login anonymous ...
      box64 /data/dst/bin/dontstarve_dedicated_server_nullrenderer_x64 ...
      ```

- **目前需要面板做的兼容**
  - 现阶段面板启动二进制时未自动加上 box 前缀，因此无法直接通过面板启动专服。
  - 其他面板功能（配置、管理、备份等）未见异常。

- **尝试过的替代方案**
  - 使用命令前面加box64的脚本替换`steamcmd`，被 SteamCMD 自愈覆盖，行不通。
  - 使用box推荐的 `binfmt_misc`方法，**可以在不修改面板的情况下正常运行**， 但是必须需要修改宿主机内核环境，不符合docker初衷。

> 总来说就是，需要面板在启动二进制文件时在前面加上box64。

测试时的[docker镜像仓库地址](https://hub.docker.com/repository/docker/starlain/dst-admin-go-arm64/general)


# dst-admin-go
> 饥荒联机版管理后台
> 
> 预览 https://carrot-hu23.github.io/dst-admin-go-preview/

[English](README-EN.md)/[中文](README.md)

**新面板 [泰拉瑞亚面板](https://github.com/carrot-hu23/terraria-panel-app) 支持window,linux 一键启动，内置 1449 版本**

## 推广
感谢莱卡云赞助广告

[【莱卡云】热卖套餐配置低至32元/月起，镜像内置面板，一键开服，即刻畅玩，立享优惠！](https://www.lcayun.com/aff/OYXIWEQC)
![tengxunad1](docs/image/莱卡云游戏面板.png)


**现已支持 windows 和 Linux 平台**
> 低版本window server 请使用 1.2.8 之前的版本，高版本window使用最新的版本

使用go编写的饥荒管理面板,部署简单,占用内存少,界面美观,操作简单,提供可视化界面操作房间配置和模组在线配置,支持多房间管理，备份快照等功能

## 部署
注意目录必须要有读写权限。

点击查看 [部署文档](https://carrot-hu23.github.io/dst-admin-go-docs/)

## 预览

![首页效果](docs/image/登录.png)
![首页效果](docs/image/房间.png)
![首页效果](docs/image/mod.png)
![首页效果](docs/image/mod配置.png)
![统计效果](docs/image/统计.png)
![面板效果](docs/image/面板.png)
![日志效果](docs/image/日志.png)


## 运行

**修改config.yml**
```
#端口
port: 8082
database: dst-db
```


运行
```
go mod tidy
go run main.go
```

## 打包


### window 打包

window 下打包 Linux 二进制

```
打开 cmd
set GOARCH=amd64
set GOOS=linux

go build
```

## QQ 群
![QQ 群](docs/image/饥荒开服面板交流issue群聊二维码.png)


