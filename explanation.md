# read_all_subjects_prompts.sh

## 1. 脚本头部和配置 (第1-28行)

```bash
#!/system/bin/sh
# read_all_subjects_prompts.sh
# 增强版：在顶层进行总体功耗和性能监控

set -e  # 遇到错误立即退出

# 定义目录和文件路径
PROMPTS_DIR="prompts_by_subject"                    # 问题文件目录
FINISHED_FILE="required_json/finished_subjects.json"  # 进度跟踪文件
QUESTION_COUNTS_FILE="required_json/question_counts_by_subject.json"  # 题目统计
POWER_LOG_DIR="power_logs"                          # 功耗日志目录
MEMORY_LOG_DIR="memory_logs"                        # 内存日志目录

# 全局监控变量
GLOBAL_START_TIME=""                                # 全局开始时间
GLOBAL_END_TIME=""                                  # 全局结束时间
ALL_PIDS_FILE="${POWER_LOG_DIR}/all_pids.txt"       # 所有进程PID记录
UID_POWER_LOG="${POWER_LOG_DIR}/uid_power_consumption.log"  # UID功耗日志
```

**作用**：定义脚本运行所需的所有目录路径、文件路径和全局变量，为后续的监控和数据处理做准备。

## 2. 启动全局监控 (第30-49行)

```bash
start_global_monitoring() {
    echo "=== 启动全局监控 ==="

    # 记录开始时间（毫秒级时间戳）
    GLOBAL_START_TIME=$(date +%s%3N)

    # 重置电池统计，准备测量功耗
    cmd battery unplug >/dev/null 2>&1
    dumpsys batterystats --reset >/dev/null 2>&1

    # 启动系统级内存监控（后台运行）
    ./system_memory_monitor.sh "${MEMORY_LOG_DIR}/system_memory.log" &
    SYSTEM_MEMORY_PID=$!  # 保存监控进程的PID
}
```

**作用**：准备全局性能监控环境，包括电池统计重置和后台启动内存监控。这是整个性能测量的起点。

## 3. PID记录功能 (第52-56行)

```bash
record_pid() {
    local pid=$1
    echo "记录进程PID: $pid"
    echo "$pid" >> "$ALL_PIDS_FILE"
}
```

**作用**：记录每个 `genie-t2t-run` 进程的PID到统一文件，用于后续功耗分析。这样可以准确追踪哪些进程消耗了资源。

## 4. 停止全局监控 (第58-124行)

```bash
stop_global_monitoring() {
    # 计算总运行时间
    total_runtime_ms=$((GLOBAL_END_TIME - GLOBAL_START_TIME))

    # 获取电池统计信息
    bs_out="$(dumpsys batterystats --checkin)"

    # 分析多个可能UID的功耗（shell:2000, 应用:9999, root:0）
    target_uids="2000 9999 0"
    total_power_mah=0

    for uid in $target_uids; do
        # 从batterystats输出中提取对应UID的功耗
        uid_power="$(printf "%s\n" "$bs_out" | awk ...)"
        total_power_mah=$(awk "BEGIN {printf \"%.3f\", $total_power_mah + $uid_power}")
    done

    # 计算平均功耗 (mA = mAh / 小时)
    runtime_hours=$(awk "BEGIN {printf \"%.9f\", $total_runtime_ms / 3600000}")
    avg_power_ma=$(awk "BEGIN {printf \"%.3f\", $total_power_mah / $runtime_hours}")
}
```

**作用**：停止监控，计算整个测试过程的功耗指标。通过分析多个UID的功耗，确保不遗漏任何相关进程的能耗。

## 5. 内存数据分析 (第126-185行)

```bash
analyze_memory_data() {
    # 提取PSS Total和PSS内存值
    pss_total_values=$(grep "Pss Total:" "$memory_log_file" | awk ...)
    pss_values=$(grep "PSS:" "$memory_log_file" | awk ...)

    # 计算峰值和平均值
    peak_pss_total=$(echo "$pss_total_values" | sort -nr | head -1)
    avg_pss_total=$(echo "$pss_total_values" | awk '{sum+=$1; count++} END {printf "%.0f", sum/count}')

    # 转换为MB并返回JSON格式结果
    peak_pss_total_mb=$(awk "BEGIN {printf \"%.1f\", $peak_pss_total / 1024}")
}
```

**作用**：分析内存监控日志，计算PSS内存的峰值、平均值等指标，返回JSON格式数据。同时处理PSS Total和PSS两种内存指标，确保数据完整性。

## 6. 时间格式化 (第187-195行)

```bash
format_duration() {
    local duration_ms=$1
    local hours=$((duration_ms / 3600000))
    local minutes=$(((duration_ms % 3600000) / 60000))
    local seconds=$(((duration_ms % 60000) / 1000))
    printf "%02d:%02d:%02d" $hours $minutes $seconds
}
```

**作用**：将毫秒时间转换为 HH:MM:SS 格式，便于人类阅读。

## 7. 生成汇总报告 (第197-278行)

```bash
generate_summary_report() {
    # 分析内存统计数据
    memory_stats=$(analyze_memory_data "$MEMORY_LOG_DIR/system_memory.log")

    # 计算进程统计
    process_count=$(wc -l < "$ALL_PIDS_FILE")

    # 计算题目统计（手动累加，避免使用paste命令）
    total_questions=0
    for num in $(cat required_json/question_counts_by_subject.json | grep -o '[0-9]*'); do
        total_questions=$((total_questions + num))
    done

    # 统计完成的题目数量
    completed_questions=0
    for subject_file in result/temp/*_answers.txt; do
        subject_questions=$(grep -c "ANSWER_START" "$subject_file")
        completed_questions=$((completed_questions + subject_questions))
    done

    # 生成JSON格式报告
    cat > "$report_file" << EOF
{
  "test_summary": {
    "total_runtime_ms": $runtime_ms,
    "total_power_consumption_mAh": $total_power_mah,
    "average_power_mA": $avg_power_ma
  },
  "memory_analysis": $memory_stats,
  ...
}
EOF
}
```

**作用**：生成最终的测试报告，包含运行时间、功耗、内存使用、题目完成情况等综合数据。报告采用JSON格式，便于后续分析和可视化。

## 8. 单个科目处理（内联函数版本）(第280-380行)

```bash
run_single_prompt_with_monitoring() {
    local prompt_file=$1
    local subject_key=$2

    # 设置环境变量
    export LD_LIBRARY_PATH=$PWD
    export ADSP_LIBRARY_PATH=$PWD
    chmod +x /data/local/tmp/genie-qwen2.5-3b/genie-t2t-run

    # 重新创建目录
    mkdir -p "result"

    local idx=0
    local prompt=""
    local temp_dir="result/temp"
    mkdir -p "$temp_dir"

    # 逐行处理问题文件
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in
        -----*)  # 问题分隔符
          # 检查是否已完成，避免重复处理
          if [ "$question_idx" -lt "$finished_count" ]; then
              continue  # 跳过已完成的问题
          fi

          # 启动模型推理（后台运行）
          /data/local/tmp/genie-qwen2.5-3b/genie-t2t-run \
              --config "genie_config.json" \
              --prompt "$formatted_prompt" > "$temp_output" 2>&1 &
          genie_pid=$!

          # 记录PID到全局文件
          record_pid $genie_pid

          # 等待推理完成
          wait $genie_pid

          # 提取答案（最后两行，去除格式字符）
          final_answer=$(echo "$model_answer" | tail -2 | sed ...)

          # 保存结果
          echo "ANSWER_START" >> "$subject_file"
          echo "final_answer:$final_answer" >> "$subject_file"
          echo "ANSWER_END" >> "$subject_file"

          # 更新完成进度
          update_finished_progress "$subject" $((question_idx + 1))
          ;;
        *)  # 问题内容
          prompt="${prompt}${line}\n"
          ;;
      esac
    done < "$prompt_file"
}
```

**作用**：处理单个科目的所有问题，包含断点续传、模型推理、答案提取、进度更新等完整流程。这是核心的业务逻辑部分，采用内联函数形式，性能更优，调试更方便。

## 9. 进度更新函数 (第382-405行)

```bash
update_finished_progress() {
    local subject=$1
    local next_question=$2
    local finished_key="${subject}_prompts"

    # 使用临时文件安全更新JSON
    local temp_json="/tmp/temp_json_$$$(date +%s%3N)"

    cat "required_json/finished_subjects.json" > "$temp_json"

    if grep -q "\"$finished_key\"" "$temp_json"; then
        sed -i "s/\"$finished_key\":[[:space:]]*[0-9]*/\"$finished_key\": $next_question/" "$temp_json"
    else
        if [ "$(cat "$temp_json" | wc -c)" -le 3 ]; then
            echo "{\"$finished_key\": $next_question}" > "$temp_json"
        else
            sed -i "s/}$/, \"$finished_key\": $next_question}/" "$temp_json"
        fi
    fi

    cat "$temp_json" > "required_json/finished_subjects.json"
    rm -f "$temp_json"
}
```

**作用**：安全地更新完成进度到JSON文件。使用临时文件避免并发写入冲突，确保数据完整性。

## 10. 主执行逻辑 (第407-460行)

```bash
main() {
    # 启动全局监控
    start_global_monitoring

    # 遍历所有科目文件
    for prompt_file in "$PROMPTS_DIR"/*_prompts.txt; do
        # 获取科目名称
        subject_key=$(basename "$filename" _prompts.txt)

        # 检查完成状态
        finished_count=$(cat "$FINISHED_FILE" | grep "\"${subject_key}_prompts\"")
        total_count=$(cat "$QUESTION_COUNTS_FILE" | grep "\"${subject_key}\"")

        # 跳过已完成的科目
        if [ "$finished_count" -eq "$total_count" ]; then
            echo "跳过已完成的科目: $subject_key"
            continue
        fi

        # 处理该科目（内联函数调用）
        run_single_prompt_with_monitoring "$prompt_file" "$subject_key"

        # 让手机休息1分钟
        echo "等待1分钟让手机休息..."
        sleep 60
    done

    # 停止全局监控并生成报告
    stop_global_monitoring
}
```

**作用**：协调整个测试流程，自动遍历所有科目文件，跳过已完成的科目，处理未完成的科目，并在每科之间设置休息时间。

## 11. 错误处理和执行 (第462-466行)

```bash
# 捕获中断信号，确保清理资源
trap 'echo "脚本被中断，正在清理..."; stop_global_monitoring; exit 1' INT TERM

# 执行主函数
main "$@"
```

**作用**：设置信号处理机制，确保即使脚本被中断也能正确清理资源（停止监控进程等）。

## 核心特性总结

1. **全局功耗监控**：在整个测试过程中统一测量功耗，避免短进程测量不准确的问题
2. **断点续传**：支持中断后继续执行，避免重复处理已完成的问题
3. **自动进度管理**：自动跟踪每个科目的完成进度
4. **内存分析**：详细的PSS内存使用统计（包括PSS Total和PSS两种指标）
5. **多科目处理**：自动遍历所有科目文件，一键运行全部测试
6. **资源清理**：完善的中断处理和资源清理机制

## 运行方式

```bash
# 直接运行，不需要任何参数
sh read_all_subjects_prompts.sh

# 或者通过run_adb_model.sh运行（带输出保存）
sh run_adb_model.sh
```

## 需要的文件结构

```
当前目录/
├── read_all_subjects_prompts.sh          # 主脚本（重构后的内联函数版本）
├── system_memory_monitor.sh              # 内存监控脚本
├── genie_config.json                     # 模型配置文件
├── run_adb_model.sh                      # 运行脚本（可选，用于保存输出）
├── prompts_by_subject/                   # 问题文件目录
│   ├── abstract_algebra_prompts.txt
│   ├── high_school_world_history_prompts.txt
│   └── ...其他科目_prompts.txt
├── required_json/                        # 配置目录
│   ├── question_counts_by_subject.json   # 题目统计
│   └── finished_subjects.json            # 进度跟踪（自动创建）
└── result/                               # 结果目录（自动创建）
```
