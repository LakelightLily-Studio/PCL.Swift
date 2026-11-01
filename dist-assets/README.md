# dist-assets

发到国内分发仓库（`functy/pcl-swift-dist`）的补充素材。**这个目录不参与 App 构建**
（不在 `PCL.Swift.xcodeproj` 的同步组里），只是发版时被 `Scripts/publish-dist.sh` 顺手推过去。

## about/

「更多 → 关于与鸣谢」页的头像。客户端从 `assets/about/<Name>.png` 取，
文件名就是 `PCL.Swift/Assets.xcassets/Avatars` 里 imageset 的名字；
取不到时退回打包在 App 里的同一张图，所以这里缺一张不会让页面变成空圆圈。

绝大多数头像不用放这里：`publish-dist.sh` 会直接从对应的 imageset 里挑分辨率最高的位图
（`@3x` > `@2x` > 1x）推上去。只有 **PCLProto 是纯 SVG**——CI 跑在 ubuntu 上，没有
能把 SVG 转成位图的工具，所以它的 PNG 是本地用 Quick Look 预渲染好放在这里的：

```bash
qlmanage -t -s 512 -o /tmp/pclproto PCL.Swift/Assets.xcassets/Avatars/PCLProto.imageset/PCLProto.svg
sips -Z 256 /tmp/pclproto/PCLProto.svg.png --out dist-assets/about/PCLProto.png
```

换了 SVG 记得重跑上面两条，否则国内那份会一直用旧图。

## icons/

「实例设置 → 概览 → 图标」里那套预设图标。客户端从 `assets/icons/<id>.png` 取，
`<id>` 与 `PCL.Swift/Managers/InstanceIconStore.swift` 里 `InstanceIconCatalog` 的 id 一一对应；
取不到时退回 `PCL.Swift/Assets.xcassets/Icons/Instance` 里的同一张图（断网也能选图标），
开了「设置 → 其他 → 缓存 → 图标缓存」时云端那份会落盘到 `Caches/images`。

这些 PNG 是 256×256、透明背景，取自 **红河素材站**（<https://honghemc.cn/app/>）的 Minecraft 图标库
（站点原图 1024×1024，脚本统一缩到 256）：

```bash
# 默认写入 dist-assets/icons；--out 可换目录
python3 Scripts/fetch-instance-icons.py
```

站点路径规则是 `/images/<分类>/<子分类>/<文件名>`（分类带编号前缀，例如 `20. Blocks`），
slug 与站点的对应关系写在脚本的 `ICONS` 表里，换版本时照站点目录改表即可。
四个模组加载器图标（neoforge / fabric / quilt / optifine）不是原版素材，不在脚本里：
NeoForge / Fabric 取 PCL2 的同名图片，Quilt 与 OptiFine 取官方标识，直接放在本目录。

换图标只要替换这里对应的 PNG 再推一次国内仓库，**不用发版**；
客户端的图标 URL 带一个版本号（`DomesticAssets.mirrors(for:cacheBust:)`），
换图后把 `InstanceIconStore.iconSetVersion` 一起改掉，否则老用户会一直用磁盘里的旧图。
