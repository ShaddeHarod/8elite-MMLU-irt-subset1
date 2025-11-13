1. 这里的.sh脚本都是运行在安卓手机的adb shell环境中的，而非在本机中运行。因此，请不要试图把这里的*.sh脚本在windows的cmd里运行。而.py和.ps1的脚本代码都是在本机运行的。
2. 有时需要去测试.sh脚本的。虽然这些.sh脚本都是在adb shell里运行，但脚本里有些命令是可以在本机测试的。
3. 目前脚本里run.sh、read_all_subjects_prompts.sh、system_memory_monitor.sh文件是在adb shell环境中运行的。

## Memory Content

本项目是一个基于安卓adb shell环境的大模型端侧功耗和内存性能测试框架，主要测试Qwen2.5-3B模型在骁龙8 Elite芯片上的运行表现。

### 脚本架构与功能

**1. run.sh** - 主测试框架脚本
- 实施两阶段测试：LLM推理测试 + 无LLM基线测试
- 通过batterystats获取SoC功耗数据（Computed drain、Actual drain等）
- 监测各硬件组件温度（CPU、DDR、GPU、电池等）
- 调用read_all_subjects_prompts.sh执行模型推理
- 生成POWER_MEM_TEMPERATURE_REPORT.json综合报告

**2. read_all_subjects_prompts.sh** - 模型推理与数据处理脚本
- 读取prompts_by_subject/目录下的MMLU测试题
- 调用genie-t2t-run运行Qwen2.5-3B模型进行推理
- 提取模型答案和性能指标（初始化时间、推理速度、token生成率等）
- 将结果转换为JSON格式并保存到result/目录
- 支持断点续测功能

**3. system_memory_monitor.sh** - 内存监控脚本
- 0.1秒间隔采样系统内存使用情况
- 检测genie-t2t-run进程活动状态
- 记录模型运行时的内存占用变化，用于计算模型实际内存开销

### 测试流程
1. run.sh设置测试环境，记录起始温度和电池状态
2. 启动read_all_subjects_prompts.sh运行MMLU测试集推理
3. 系统级内存监控持续记录内存使用数据
4. 完成后进行基线测试（空闲运行相同时间）
5. 生成包含功耗、温度、内存、性能的综合测试报告