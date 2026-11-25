# 录屏复刻

从主菜单次行选择 **录屏复刻**。这是 52.375 秒的独立实机剪辑，不会替换原有的 75 秒玩法演示。片中计时起点和枯树林的 `+30 s` 是分镜设定；速度、挡位、转速、进度、驾驶输入及轮胎触地均来自项目的驾驶录制。回放不写玩家档案、计时成绩或照片。

| 片中时间 | 场景和镜头 |
| --- | --- |
| 0:00.000–0:06.850 | 阳光砂石路。蓝色赛车跟拍，先带仪表，再切干净画面。 |
| 0:06.850–0:20.750 | 枯树林。斜上方取景，切跟车仪表，最后拉远。 |
| 0:20.750–0:39.850 | 夕阳公路。红色赛车加速，固定镜头看车驶下坡，再切高速跟车。 |
| 0:39.850–0:50.750 | 蓝调雨夜。先从路边侧拍，再跟随车灯、尾灯和轮后水雾。 |
| 0:50.750–0:52.375 | 切回开场。 |

四套环境使用独立的 Godot 3D 世界。松岭与高地复用项目赛段；公路是专为回放生成的路线，不加入可选赛段。天空、灯光、景物和音效由项目重建，并非原录屏的素材或像素级拷贝。

## 本地复现与验收

使用项目要求的 Godot 版本，先运行 `godot --headless --editor --import`。下列命令在项目根目录执行，`godot` 可替换为引擎可执行文件路径。两条录制命令会更新对应遥测素材；日常观看不需要录制。

```bash
godot --headless --fixed-fps 120 -s res://scripts/dev/record_showcase.gd -- \
  --stage=sunset_ridge --car=R200 --start=395 --duration=15 --speed=16.8 \
  --out=res://resources/showcase/reference_gravel.json

godot --headless --fixed-fps 120 -s res://scripts/dev/record_showcase.gd -- \
  --stage=reference_highway --car=R200 --start=620 --duration=28 --speed=41 \
  --lane=-1.55 --lift-from=18 --lift-to=19.35 --lift-speed=31 \
  --out=res://resources/showcase/reference_highway.json

godot --headless -s res://tests/reference_film_test.gd

# 通过真实游戏菜单进入剪辑，截取 1280×720 的镜头和 1600×900 的 HUD / 暂停页。
capture_dir=$(mktemp -d)
godot --resolution 1280x720 -s res://tests/reference_film_test.gd -- --capture-dir="$capture_dir"
```
