#!/system/bin/sh
# system_memory_monitor.sh
# 系统级内存监控，监控所有genie相关进程
#
# 功能说明：
# - 检测genie-t2t-run进程的PSS（Proportional Set Size）内存使用情况
# - 监控系统总体内存使用情况
# - 注意：PSS无法读取NPU专用内存占用，对于大模型推理会有较大偏差
#
# 使用限制：
# - PSS统计只包含用户空间内存，不包含NPU/GPU专用内存
# - 对于加载GB级模型权重的情况，PSS可能只显示几十MB
# - 实际内存消耗需要通过系统总内存变化来估算
#
# 对所有sh脚本别忘了做dos2unix指令
if [ $# -ne 1 ]; then
    echo "用法: $0 <log_file>"
    echo "示例: $0 /data/local/tmp/system_memory.log"
    exit 1
fi

log_file=$1
interval=0.1  # 0.1秒采样间隔, sleep实现

# 清空日志文件
> "$log_file"

echo "开始系统级内存监控..."
echo "采样间隔: ${interval}秒"
echo "日志文件: $log_file"

# 监控循环
while true; do
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # 查找所有genie-t2t-run进程
    genie_processes=$(ps -ef | grep "genie-t2t-run" | grep -v grep)

    if [ -n "$genie_processes" ]; then
        echo "[$timestamp] 检测到genie进程活动" >> "$log_file"

        # 对每个genie进程获取内存信息
        echo "$genie_processes" | while IFS= read -r line; do
            if [ -n "$line" ]; then
                pid=$(echo "$line" | awk '{print $2}')

                # 获取进程内存信息
                if [ -n "$pid" ] && [ -d "/proc/$pid" ]; then
                    # 打印完整的dumpsys meminfo输出用于调试
                    # echo "=== DEBUG: dumpsys meminfo $pid ===" >> "$log_file"
                    # dumpsys meminfo "$pid" >> "$log_file" 2>&1
                    # echo "=== END DEBUG ===" >> "$log_file"

                    # 从TOTAL行获取Pss Total值（精确匹配两种格式）
                    pss_kb=$(dumpsys meminfo "$pid" 2>/dev/null | grep -E "TOTAL PSS:|^[[:space:]]*TOTAL[[:space:]]+[0-9]" | awk '{
    if ($1 == "TOTAL" && $2 == "PSS:") {
        print $3
    } else if ($1 == "TOTAL" && $2 ~ /^[0-9]+$/) {
        print $2
    }
}' | tr -d ',' | head -1)

                    if [ -n "$pss_kb" ]; then
                        echo "  PID:$pid PSS_Total:${pss_kb}KB" >> "$log_file"
                    fi
                fi
            fi
        done

        # 获取系统总体内存使用情况
        mem_total=$(cat /proc/meminfo | grep MemTotal | awk '{print $2}')
        mem_available=$(cat /proc/meminfo | grep MemAvailable | awk '{print $2}')
        mem_used=$((mem_total - mem_available))
        mem_usage_percent=$((mem_used * 100 / mem_total))

        echo "  系统内存: ${mem_used}KB/${mem_total}KB (${mem_usage_percent}%)" >> "$log_file"

    else
        echo "[$timestamp] 无genie进程活动" >> "$log_file"
    fi

    # 添加空行分隔不同时间点
    echo "" >> "$log_file"

    sleep "$interval"
done