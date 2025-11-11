#!/system/bin/sh
# temperature_monitor.sh
# 获取所有thermal_zone的温度信息并保存到temp_logs文件夹

# 创建temp_logs文件夹（如果不存在）
mkdir -p temp_logs

# 生成带时间戳的日志文件名
timestamp=$(date '+%Y%m%d_%H%M%S')
log_file="temp_logs/thermal_zones_${timestamp}.log"
temp_file_sorted="temp_logs/thermal_zones_temp_${timestamp}.txt"

echo "温度监控开始..."
echo "扫描时间: $(date '+%Y-%m-%d %H:%M:%S')" > "$log_file"
echo "" >> "$log_file"

zone_count=0

# 创建临时文件存储所有数据
> "$temp_file_sorted"

# 遍历所有thermal_zone
for zone_dir in /sys/class/thermal/thermal_zone*; do
    if [ -d "$zone_dir" ]; then
        zone_count=$((zone_count + 1))

        # 提取thermal_zone编号
        zone_name=$(basename "$zone_dir")
        zone_number=$(echo "$zone_name" | sed 's/thermal_zone//')

        # 获取设备类型
        type_file="$zone_dir/type"
        if [ -f "$type_file" ]; then
            device_type=$(cat "$type_file" 2>/dev/null | tr -d '\n\r')
        else
            device_type="unknown"
        fi

        # 获取温度（毫摄氏度）并转换为摄氏度
        temp_file="$zone_dir/temp"
        if [ -f "$temp_file" ]; then
            temp_milli=$(cat "$temp_file" 2>/dev/null | tr -d '\n\r')
            # 验证温度值是否为有效数字
            if echo "$temp_milli" | grep -qE '^[0-9]+$'; then
                # 转换为摄氏度并保留一位小数
                temp_celsius=$(echo "$temp_milli" | awk '{printf "%.1f", $1/1000}')
            else
                temp_celsius="N/A"
            fi
        else
            temp_celsius="N/A"
        fi

        # 存储到临时文件（格式：device_type|zone_number|temp_celsius）
        echo "$device_type|$zone_number|$temp_celsius" >> "$temp_file_sorted"

        # 同时在控制台输出
        printf "Zone %-2s: %-20s %s°C\n" "$zone_number" "$device_type" "$temp_celsius"
    fi
done

# 添加表头到最终日志文件
echo "thermal_zone_number device_type temperature_celsius" >> "$log_file"
echo "-------------------- -------------------- --------------------" >> "$log_file"

# 按device_type排序后输出到日志文件
if [ -f "$temp_file_sorted" ] && [ -s "$temp_file_sorted" ]; then
    sort "$temp_file_sorted" | while IFS='|' read -r device_type zone_number temp_celsius; do
        printf "%-20s %-20s %s\n" "$zone_number" "$device_type" "$temp_celsius" >> "$log_file"
    done
fi

# 删除临时文件
rm -f "$temp_file_sorted"

echo "" >> "$log_file"
echo "扫描完成时间: $(date '+%Y-%m-%d %H:%M:%S')" >> "$log_file"
echo "总计发现 $zone_count 个thermal_zone" >> "$log_file"

echo ""
echo "温度监控完成！"
echo "发现 $zone_count 个thermal_zone"
echo "日志已保存到: $log_file"
echo "注：温度单位为摄氏度(°C)"