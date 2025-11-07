#!/system/bin/sh
# system_memory_monitor.sh
# 系统级内存监控，监控系统内存使用情况和genie活动状态
#
# 功能说明：
# - 检测genie-t2t-run进程的活动状态
# - 记录系统内存使用情况（总内存和已用内存）
# - 通过对比有无genie活动时的内存差异来计算模型实际内存占用
#
# 日志格式：
# - [YYYY-MM-DD HH:MM:SS] genie_active:true/false system_mem_used:XXXXKB system_mem_total:XXXXKB
# - 便于后续分析函数计算基准内存、峰值内存和模型内存占用
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

    # 获取系统内存使用情况
    mem_total=$(cat /proc/meminfo | grep MemTotal | awk '{print $2}')
    mem_available=$(cat /proc/meminfo | grep MemAvailable | awk '{print $2}')
    mem_used=$((mem_total - mem_available))

    # 判断genie活动状态并记录内存信息
    if [ -n "$genie_processes" ]; then
        echo "[$timestamp] genie_active:true system_mem_used:${mem_used}KB system_mem_total:${mem_total}KB" >> "$log_file"
    else
        echo "[$timestamp] genie_active:false system_mem_used:${mem_used}KB system_mem_total:${mem_total}KB" >> "$log_file"
    fi

    sleep "$interval"
done