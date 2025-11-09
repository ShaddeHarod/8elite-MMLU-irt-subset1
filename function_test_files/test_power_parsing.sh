#!/system/bin/sh
# test_power_parsing.sh
# 测试get_power_consumption()函数对Computed drain和actual drain值的解析

# 验证耗电量值是否为有效数字
validate_power_value() {
    local value=$1
    if echo "$value" | grep -qE '^[0-9]+\.?[0-9]*$'; then
        return 0
    else
        return 1
    fi
}

# 日志函数
log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') $1" >&2
}

log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $1" >&2
}

# 从文件读取batterystats数据并解析耗电量值
get_power_consumption_from_file() {
    local batterystats_file=$1
    local test_name=$2

    log_info "获取 $test_name 的耗电量数据从文件: $batterystats_file"

    # 检查文件是否存在
    if [ ! -f "$batterystats_file" ]; then
        log_error "文件不存在: $batterystats_file"
        echo "-1.0 -1.0 -1.0"
        return 1
    fi

    # 读取文件内容
    local bs_output
    bs_output=$(cat "$batterystats_file")

    if [ -z "$bs_output" ]; then
        log_error "文件内容为空"
        echo "-1.0 -1.0 -1.0"
        return 1
    fi

    # 提取耗电量数据
    local computed_drain="-1.0"
    local actual_drain_min="-1.0"
    local actual_drain_max="-1.0"

    # 查找 "Estimated power use (mAh):" 部分（这是耗电量数据）
    local power_section
    power_section=$(echo "$bs_output" | awk '/Estimated power use \(mAh\):/{found=1; next} found && /^ /{print} !/^ / && found{exit}')

    # 打印power_section到stderr用于调试
    echo "DEBUG: power_section content:" >&2
    echo "$power_section" >&2
    echo "DEBUG: end of power_section" >&2

    if [ -n "$power_section" ]; then
        # 提取 Computed drain
        echo "DEBUG: 使用sed提取 Computed drain" >&2
        computed_drain=$(echo "$power_section" | sed -n 's/.*Computed drain: \([0-9.-]*\).*/\1/p')
        echo "DEBUG: 提取的 computed_drain 原始值: '$computed_drain'" >&2

        # 提取 actual drain
        echo "DEBUG: 使用sed提取 actual drain" >&2
        local actual_drain_raw
        actual_drain_raw=$(echo "$power_section" | sed -n 's/.*actual drain: \([0-9.-]*\).*/\1/p')
        echo "DEBUG: 提取的 actual_drain_raw 原始值: '$actual_drain_raw'" >&2

        # 验证 computed drain
        echo "DEBUG: 开始验证 computed_drain: '$computed_drain'" >&2
        echo "DEBUG: computed_drain 是否为空: $([ -z "$computed_drain" ] && echo "是" || echo "否")" >&2
        if [ -n "$computed_drain" ] && validate_power_value "$computed_drain"; then
            echo "DEBUG: computed_drain 验证通过" >&2
            log_info "Computed drain: ${computed_drain} mAh"
        else
            echo "DEBUG: computed_drain 验证失败，设置为 -1.0" >&2
            computed_drain="-1.0"
            log_info "Computed drain 无效，设置为 -1.0"
        fi

        # 处理 actual drain（可能是范围）
        echo "DEBUG: 开始验证 actual_drain_raw: '$actual_drain_raw'" >&2
        echo "DEBUG: actual_drain_raw 是否为空: $([ -z "$actual_drain_raw" ] && echo "是" || echo "否")" >&2
        if [ -n "$actual_drain_raw" ]; then
            echo "DEBUG: actual_drain_raw 不为空，继续处理" >&2
            if echo "$actual_drain_raw" | grep -q '-'; then
                echo "DEBUG: 检测到 actual_drain_raw 是范围值: '$actual_drain_raw'" >&2
                # 是范围值，如 "41.0-52.0"
                actual_drain_min=$(echo "$actual_drain_raw" | cut -d'-' -f1)
                actual_drain_max=$(echo "$actual_drain_raw" | cut -d'-' -f2)
                echo "DEBUG: 解析范围值 - min: '$actual_drain_min', max: '$actual_drain_max'" >&2

                # 验证范围值
                if validate_power_value "$actual_drain_min" && validate_power_value "$actual_drain_max"; then
                    echo "DEBUG: actual drain 范围值验证通过" >&2
                    log_info "Actual drain 范围: ${actual_drain_min} - ${actual_drain_max} mAh"
                else
                    echo "DEBUG: actual drain 范围值验证失败，设置为 -1.0" >&2
                    actual_drain_min="-1.0"
                    actual_drain_max="-1.0"
                    log_info "Actual drain 范围值无效，设置为 -1.0"
                fi
            else
                echo "DEBUG: 检测到 actual_drain_raw 是单一值: '$actual_drain_raw'" >&2
                # 单一值
                if validate_power_value "$actual_drain_raw"; then
                    echo "DEBUG: actual drain 单一值验证通过" >&2
                    actual_drain_min="$actual_drain_raw"
                    actual_drain_max="$actual_drain_raw"
                    log_info "Actual drain: ${actual_drain_raw} mAh"
                else
                    echo "DEBUG: actual drain 单一值验证失败，设置为 -1.0" >&2
                    actual_drain_min="-1.0"
                    actual_drain_max="-1.0"
                    log_info "Actual drain 值无效，设置为 -1.0"
                fi
            fi
        else
            echo "DEBUG: actual_drain_raw 为空，设置为 -1.0" >&2
            log_info "未找到 actual drain 数据，设置为 -1.0"
        fi
    else
        log_info "未找到耗电量数据部分，所有值设置为 -1.0"
    fi

    # 确保返回有效数值
    if [ -z "$computed_drain" ] || [ "$computed_drain" = "0" ]; then
        computed_drain="-1.0"
    fi
    if [ -z "$actual_drain_min" ] || [ "$actual_drain_min" = "0" ]; then
        actual_drain_min="-1.0"
    fi
    if [ -z "$actual_drain_max" ] || [ "$actual_drain_max" = "0" ]; then
        actual_drain_max="-1.0"
    fi

    log_info "$test_name 耗电量结果 - Computed: ${computed_drain} mAh, Actual_min: ${actual_drain_min} mAh, Actual_max: ${actual_drain_max} mAh"
    echo "$computed_drain $actual_drain_min $actual_drain_max"
}

# 计算功耗指标（假设运行时间20秒） - 功耗 = 耗电量 ÷ 时间
calculate_power_metrics() {
    local computed_drain=$1
    local actual_drain_min=$2
    local actual_drain_max=$3
    local runtime_seconds=20

    log_info "计算功耗指标（假设运行时间: ${runtime_seconds}秒）"
    log_info "输入参数 - computed_drain: '$computed_drain', actual_drain_min: '$actual_drain_min', actual_drain_max: '$actual_drain_max'"

    # 验证输入参数
    if [ -z "$computed_drain" ] || [ "$computed_drain" = "-1.0" ] || [ "$computed_drain" = "0" ]; then
        log_info "computed_drain值无效: '$computed_drain'"
        computed_drain="-1.0"
    fi

    if [ -z "$actual_drain_min" ] || [ "$actual_drain_min" = "-1.0" ] || [ "$actual_drain_min" = "0" ]; then
        log_info "actual_drain_min值无效: '$actual_drain_min'"
        actual_drain_min="-1.0"
    fi

    if [ -z "$actual_drain_max" ] || [ "$actual_drain_max" = "-1.0" ] || [ "$actual_drain_max" = "0" ]; then
        log_info "actual_drain_max值无效: '$actual_drain_max'"
        actual_drain_max="-1.0"
    fi

    # 计算平均功耗 (mA) - 功耗 = 耗电量 ÷ 时间(小时)
    local avg_power_computed="-1.0"
    local avg_power_actual_min="-1.0"
    local avg_power_actual_max="-1.0"

    # 时间转换为小时
    local runtime_hours=$(echo "$runtime_seconds 3600" | awk '{printf "%.6f", $1 / $2}')
    log_info "时间转换: ${runtime_seconds}秒 = ${runtime_hours}小时"

    if [ "$computed_drain" != "-1.0" ] && echo "$computed_drain" | grep -qE '^[0-9]+\.?[0-9]*$'; then
        avg_power_computed=$(echo "$computed_drain $runtime_hours" | awk '{printf "%.3f", $1 / $2}')
        log_info "computed功耗计算: $computed_drain mAh ÷ $runtime_hours h = $avg_power_computed mA"
    else
        log_info "跳过computed功耗计算，值无效: $computed_drain"
    fi

    if [ "$actual_drain_min" != "-1.0" ] && echo "$actual_drain_min" | grep -qE '^[0-9]+\.?[0-9]*$'; then
        avg_power_actual_min=$(echo "$actual_drain_min $runtime_hours" | awk '{printf "%.3f", $1 / $2}')
        log_info "actual_min功耗计算: $actual_drain_min mAh ÷ $runtime_hours h = $avg_power_actual_min mA"
    else
        log_info "跳过actual_min功耗计算，值无效: $actual_drain_min"
    fi

    if [ "$actual_drain_max" != "-1.0" ] && echo "$actual_drain_max" | grep -qE '^[0-9]+\.?[0-9]*$'; then
        avg_power_actual_max=$(echo "$actual_drain_max $runtime_hours" | awk '{printf "%.3f", $1 / $2}')
        log_info "actual_max功耗计算: $actual_drain_max mAh ÷ $runtime_hours h = $avg_power_actual_max mA"
    else
        log_info "跳过actual_max功耗计算，值无效: $actual_drain_max"
    fi

    # 输出结果
    log_info "平均功耗计算结果:"
    log_info "  Computed drain 平均功耗: ${avg_power_computed} mA"
    log_info "  Actual drain 平均功耗范围: ${avg_power_actual_min} - ${avg_power_actual_max} mA"

    # 生成JSON结果
    cat << EOF
{
  "power_consumption_analysis": {
    "runtime_seconds": $runtime_seconds,
    "computed_drain_mah": $computed_drain,
    "actual_drain_min_mah": $actual_drain_min,
    "actual_drain_max_mah": $actual_drain_max,
    "avg_power_computed_ma": $avg_power_computed,
    "avg_power_actual_min_ma": $avg_power_actual_min,
    "avg_power_actual_max_ma": $avg_power_actual_max
  }
}
EOF
}

# 主测试函数
main() {
    log_info "=== 开始耗电量解析测试 ==="

    # 测试文件1: 单一actual drain值
    echo ""
    log_info "测试文件1: mock_btstats_1.txt (单一actual drain值)"
    local result1=$(get_power_consumption_from_file "mock_btstats_1.txt" "Test1_Single_Actual_Drain")
    log_info "函数返回结果: '$result1'"
    local computed_drain1=$(echo "$result1" | awk '{print $1}')
    local actual_drain_min1=$(echo "$result1" | awk '{print $2}')
    local actual_drain_max1=$(echo "$result1" | awk '{print $3}')
    log_info "提取的数值 - computed: '$computed_drain1', actual_min: '$actual_drain_min1', actual_max: '$actual_drain_max1'"

    echo ""
    calculate_power_metrics "$computed_drain1" "$actual_drain_min1" "$actual_drain_max1"

    # 测试文件2: actual drain范围值
    echo ""
    log_info "测试文件2: mock_btstats_2.txt (actual drain范围值)"
    local result2=$(get_power_consumption_from_file "mock_btstats_2.txt" "Test2_Range_Actual_Drain")
    log_info "函数返回结果: '$result2'"
    local computed_drain2=$(echo "$result2" | awk '{print $1}')
    local actual_drain_min2=$(echo "$result2" | awk '{print $2}')
    local actual_drain_max2=$(echo "$result2" | awk '{print $3}')
    log_info "提取的数值 - computed: '$computed_drain2', actual_min: '$actual_drain_min2', actual_max: '$actual_drain_max2'"

    echo ""
    calculate_power_metrics "$computed_drain2" "$actual_drain_min2" "$actual_drain_max2"

    log_info "=== 耗电量解析测试完成 ==="
}

# 执行主函数
main "$@"