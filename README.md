# 大模型端侧部署Benchmark - test-on-8elite-irt-subset1

## 项目简介

本项目用于在骁龙8 Elite设备上进行大模型端侧部署的性能测试和评估，主要针对MMLU-ZH-CN数据集的子集进行推理测试。

## 重要说明

⚠️ **本仓库未包含以下重要文件和组件**：

- **模型权重文件**: 所有模型权重文件（约2.5GB）由于体积限制未上传到仓库
- **QNN相关组件**: Qualcomm Neural Processing SDK相关文件未包含
  - QNN SDK库文件（lib/hexagon-v81/unsigned/*）
  - ARM架构库文件（lib/aarch64-android/*）
  - 推理可执行文件（bin/aarch64-android/genie-t2t-run）

这些文件需要单独获取并放置在相应目录中才能正常运行完整测试流程。

## 项目结构

```
├── scripts/                    # 数据处理脚本
├── prompts_by_subject/        # 分学科的题目prompt文件
├── subjects_answers_ground_truth/  # 标准答案文件
├── required_json/             # 计数和配置文件
├── model_related_files/       # 模型相关文件（未上传）
├── memory_logs/              # 内存监控日志
├── power_logs/               # 功耗监控日志
├── *.sh                      # 执行脚本
├── *.csv                     # 测试数据
└── *.md                      # 文档
```

## 快速开始

详细的使用教程请参考 [tutorial.md](tutorial.md) 文件。

### 基本流程概述

1. **环境准备**: 激活conda环境
   ```bash
   conda activate TinyBenchEnv
   ```

2. **数据转换**: 将CSV格式数据转换为prompt和answer格式
3. **分科处理**: 按学科分割题目和答案
4. **创建配置**: 生成计数和配置文件
5. **模型部署**: 配置QNN环境和模型权重（需要单独获取）
6. **执行测试**: 运行推理和性能监控

## 脚本说明

- `system_memory_monitor.sh`: 系统级内存监控脚本
- `read_all_subjects_prompts.sh`: 读取所有学科题目的主执行脚本
- `run_adb_model.sh`: ADB模型运行脚本
- `scripts/`: 包含各种数据处理的Python脚本

## 监控功能

项目支持以下性能监控：
- 内存使用监控（PSS、系统内存）
- 功耗监控
- 推理性能统计

## 许可证

本项目仅用于学术研究和性能测试目的。

## 联系方式

如有问题或建议，请通过GitHub Issues联系。