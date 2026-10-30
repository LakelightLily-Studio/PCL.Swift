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
