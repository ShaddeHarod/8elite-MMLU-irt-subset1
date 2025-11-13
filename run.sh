#!/system/bin/sh
# run_adb_model.sh
# 两阶段耗电量测试框架：LLM 测试 + 无LLM baseline 测试

# set -e

mkdir -p result

# filepath info
TEST_SCRIPT="read_all_subjects_prompts.sh"
OUTPUT_FILE="output.txt"
POWER_LOG_FILE="power_consumption.log"
POWER_MEM_REPORT_FILE="result/POWER_MEM_TEMPERATURE_REPORT.json"
TEMPERATURE_TEMP_FILE="temperature_temp.log"
LLM_START_TEMPERATURE_FILE="result/temperature_llm_start.json"
LLM_END_TEMPERATURE_FILE="result/temperature_llm_end.json"
BASELINE_START_TEMPERATURE_FILE="result/temperature_baseline_start.json"
BASELINE_END_TEMPERATURE_FILE="result/temperature_baseline_end.json"
# 日志函数
log_info() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] INFO: $1" >> "$POWER_LOG_FILE"
    echo "[$timestamp] INFO: $1" >&2
}

log_error() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] ERROR: $1" >> "$POWER_LOG_FILE"
    echo "[$timestamp] ERROR: $1" >&2
}

# 环境控制
setup_test_environment() {
    log_info "设置测试环境..."

    # 断开充电连接
    cmd battery unplug >/dev/null 2>&1 || true

    # 设置屏幕亮度（如果需要保持屏幕开启）
    # settings put system screen_brightness 100 >/dev/null 2>&1 || true

    # 禁用网络连接以减少耗电量测试干扰（可选）
    # svc wifi disable >/dev/null 2>&1 || true
    # svc data disable >/dev/null 2>&1 || true

    log_info "测试环境设置完成"
}

# 恢复环境设置
restore_environment() {
    log_info "恢复环境设置..."

    # 恢复充电连接
    cmd battery reset >/dev/null 2>&1 || true

    # 重置电池统计
    dumpsys batterystats --reset >/dev/null 2>&1 || true

    log_info "环境恢复完成"
}

# 验证耗电量值是否为有效数字
validate_power_value() {
    local value=$1
    if echo "$value" | grep -qE '^[0-9]+\.?[0-9]*$'; then
        return 0
    else
        return 1
    fi
}

# 记录各组件温度
record_component_temperature() {
    local timestamp_label=$1
    local temp_json=""
    local temp_sum=0
    local temp_count=0
    local avg_temp=0

    # Battery
    local battery_temp=$(cat /sys/class/thermal/thermal_zone81/temp 2>/dev/null || echo "0")
    battery_temp=$((battery_temp / 1000))
    temp_json="${temp_json}\n    \"battery\": { \"${timestamp_label}_temperature\": ${battery_temp} },"

    # CPU-0 (zones: 1,3,5,7,9,11,13,15,17,19,20,21)
    temp_sum=0; temp_count=0
    for zone in 1 3 5 7 9 11 13 15 17 19 20 21; do
        local temp=$(cat /sys/class/thermal/thermal_zone${zone}/temp 2>/dev/null || echo "0")
        if [ "$temp" != "0" ]; then
            temp_sum=$((temp_sum + temp / 1000))
            temp_count=$((temp_count + 1))
        fi
    done
    avg_temp=$((temp_count > 0 ? temp_sum / temp_count : 0))
    temp_json="${temp_json}\n    \"cpu-0\": { \"${timestamp_label}_temperature\": ${avg_temp} },"

    # CPU-1 (zones: 25,26,27,28)
    temp_sum=0; temp_count=0
    for zone in 25 26 27 28; do
        local temp=$(cat /sys/class/thermal/thermal_zone${zone}/temp 2>/dev/null || echo "0")
        if [ "$temp" != "0" ]; then
            temp_sum=$((temp_sum + temp / 1000))
            temp_count=$((temp_count + 1))
        fi
    done
    avg_temp=$((temp_count > 0 ? temp_sum / temp_count : 0))
    temp_json="${temp_json}\n    \"cpu-1\": { \"${timestamp_label}_temperature\": ${avg_temp} },"

    # CPUSS (zones: 22,23,29,30)
    temp_sum=0; temp_count=0
    for zone in 22 23 29 30; do
        local temp=$(cat /sys/class/thermal/thermal_zone${zone}/temp 2>/dev/null || echo "0")
        if [ "$temp" != "0" ]; then
            temp_sum=$((temp_sum + temp / 1000))
            temp_count=$((temp_count + 1))
        fi
    done
    avg_temp=$((temp_count > 0 ? temp_sum / temp_count : 0))
    temp_json="${temp_json}\n    \"cpuss\": { \"${timestamp_label}_temperature\": ${avg_temp} },"

    # DDR (zone: 55)
    local ddr_temp=$(cat /sys/class/thermal/thermal_zone55/temp 2>/dev/null || echo "0")
    ddr_temp=$((ddr_temp / 1000))
    temp_json="${temp_json}\n    \"ddr\": { \"${timestamp_label}_temperature\": ${ddr_temp} },"

    # GPUSS (zones: 32,33,34,35,36,37,38,39)
    temp_sum=0; temp_count=0
    for zone in 32 33 34 35 36 37 38 39; do
        local temp=$(cat /sys/class/thermal/thermal_zone${zone}/temp 2>/dev/null || echo "0")
        if [ "$temp" != "0" ]; then
            temp_sum=$((temp_sum + temp / 1000))
            temp_count=$((temp_count + 1))
        fi
    done
    avg_temp=$((temp_count > 0 ? temp_sum / temp_count : 0))
    temp_json="${temp_json}\n    \"gpuss\": { \"${timestamp_label}_temperature\": ${avg_temp} },"

    # NSPHMX (zones: 51,52,53,54)
    temp_sum=0; temp_count=0
    for zone in 51 52 53 54; do
        local temp=$(cat /sys/class/thermal/thermal_zone${zone}/temp 2>/dev/null || echo "0")
        if [ "$temp" != "0" ]; then
            temp_sum=$((temp_sum + temp / 1000))
            temp_count=$((temp_count + 1))
        fi
    done
    avg_temp=$((temp_count > 0 ? temp_sum / temp_count : 0))
    temp_json="${temp_json}\n    \"nsphmx\": { \"${timestamp_label}_temperature\": ${avg_temp} },"

    # NSPHVX (zones: 48,49,50)
    temp_sum=0; temp_count=0
    for zone in 48 49 50; do
        local temp=$(cat /sys/class/thermal/thermal_zone${zone}/temp 2>/dev/null || echo "0")
        if [ "$temp" != "0" ]; then
            temp_sum=$((temp_sum + temp / 1000))
            temp_count=$((temp_count + 1))
        fi
    done
    avg_temp=$((temp_count > 0 ? temp_sum / temp_count : 0))
    temp_json="${temp_json}\n    \"nsphvx\": { \"${timestamp_label}_temperature\": ${avg_temp} },"

    # Shell components
    local shell_back_temp=$(cat /sys/class/thermal/thermal_zone58/temp 2>/dev/null || echo "0")
    shell_back_temp=$((shell_back_temp / 1000))
    temp_json="${temp_json}\n    \"shell_back\": { \"${timestamp_label}_temperature\": ${shell_back_temp} },"

    local shell_frame_temp=$(cat /sys/class/thermal/thermal_zone57/temp 2>/dev/null || echo "0")
    shell_frame_temp=$((shell_frame_temp / 1000))
    temp_json="${temp_json}\n    \"shell_frame\": { \"${timestamp_label}_temperature\": ${shell_frame_temp} },"

    local shell_front_temp=$(cat /sys/class/thermal/thermal_zone56/temp 2>/dev/null || echo "0")
    shell_front_temp=$((shell_front_temp / 1000))
    temp_json="${temp_json}\n    \"shell_front\": { \"${timestamp_label}_temperature\": ${shell_front_temp} }"

    echo -e "{${temp_json}\n}" > "$TEMPERATURE_TEMP_FILE" 2>&1
}

# 获取batterystats耗电量数据
get_power_consumption() {
    local start_time=$1
    local end_time=$2
    local test_name=$3

    log_info "获取 $test_name 的耗电量数据..."

    # 获取电池统计
    local bs_output
    bs_output=$(dumpsys batterystats 2>/dev/null || echo "")

    if [ -z "$bs_output" ]; then
        log_error "无法获取电池统计数据"
        echo "-1.0 -1.0 -1.0 -1.0"
        return 1
    fi

    # 提取功耗数据
    local computed_drain="-1.0"
    local actual_drain_min="-1.0"
    local actual_drain_max="-1.0"
    local soc_power_mah="-1.0"

    # 查找 "Estimated power use (mAh):" 部分（这是耗电量数据）
    local power_section
    power_section=$(echo "$bs_output" | awk '/Estimated power use \(mAh\):/{found=1; next} found && /^ /{print} !/^ / && found{exit}')


    if [ -n "$power_section" ]; then
        # 提取 Computed drain
        computed_drain=$(echo "$power_section" | sed -n 's/.*Computed drain: \([0-9.-]*\).*/\1/p')

        # 提取 actual drain
        local actual_drain_raw
        actual_drain_raw=$(echo "$power_section" | sed -n 's/.*actual drain: \([0-9.-]*\).*/\1/p')

        # 验证 computed drain
        if [ -n "$computed_drain" ] && validate_power_value "$computed_drain"; then
            log_info "Computed drain: ${computed_drain} mAh"
        else
            computed_drain="-1.0"
            log_info "Computed drain 无效，设置为 -1.0"
        fi

        # 处理 actual drain（可能是范围）
        if [ -n "$actual_drain_raw" ]; then
            if echo "$actual_drain_raw" | grep -q '-'; then
                # 是范围值，如 "41.0-52.0"
                actual_drain_min=$(echo "$actual_drain_raw" | cut -d'-' -f1)
                actual_drain_max=$(echo "$actual_drain_raw" | cut -d'-' -f2)

                # 验证范围值
                if validate_power_value "$actual_drain_min" && validate_power_value "$actual_drain_max"; then
                    log_info "Actual drain 范围: ${actual_drain_min} - ${actual_drain_max} mAh"
                else
                    actual_drain_min="-1.0"
                    actual_drain_max="-1.0"
                    log_info "Actual drain 范围值无效，设置为 -1.0"
                fi
            else
                # 单一值
                if validate_power_value "$actual_drain_raw"; then
                    actual_drain_min="$actual_drain_raw"
                    actual_drain_max="$actual_drain_raw"
                    log_info "Actual drain: ${actual_drain_raw} mAh"
                else
                    actual_drain_min="-1.0"
                    actual_drain_max="-1.0"
                    log_info "Actual drain 值无效，设置为 -1.0"
                fi
            fi
        else
            log_info "未找到 actual drain 数据，设置为 -1.0"
        fi
    else
        log_info "未找到耗电量数据部分，所有值设置为 -1.0"
    fi

    # 提取SoC耗电量（从Global部分的cpu行获取）
    if [ -n "$power_section" ]; then
        soc_power_mah=$(echo "$power_section" | sed -n '/^    Global$/,/^[^ ]/ {
  /^      cpu: /{
    s/^      cpu: \([0-9.-]*\).*$/\1/p
    q
  }
}')
        echo "DEBUG: 提取的 soc_power_mah 原始值: '$soc_power_mah'" >&2

        # 验证SoC耗电量值
        if [ -n "$soc_power_mah" ] && validate_power_value "$soc_power_mah"; then
            log_info "SoC耗电量（来自Global CPU）: ${soc_power_mah} mAh"
        else
           soc_power_mah="-1.0"
            log_info "SoC耗电量无效，设置为 -1.0"
        fi
    else
        log_info "未找到耗电量数据部分，SoC耗电量设置为 -1.0"
        soc_power_mah="-1.0"
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
    if [ -z "$soc_power_mah" ] || [ "$soc_power_mah" = "0" ]; then
        soc_power_mah="-1.0"
    fi

    log_info "$test_name 耗电量结果 - Computed: ${computed_drain} mAh, Actual_min: ${actual_drain_min} mAh, Actual_max: ${actual_drain_max} mAh, SoC: ${soc_power_mah} mAh"
    echo "$computed_drain $actual_drain_min $actual_drain_max $soc_power_mah"
}

# 分析内存数据（从read_all_subjects_prompts.sh移动过来）
analyze_memory_data() {
    local memory_log_file="$1"

    if [ ! -f "$memory_log_file" ] || [ ! -s "$memory_log_file" ]; then
        echo '{"memory_analysis": {"baseline_mem_kb": "NA", "baseline_mem_mb": "NA", "peak_mem_kb": "NA", "peak_mem_mb": "NA", "model_memory_kb": "NA", "model_memory_mb": "NA", "genie_active_samples": 0, "genie_inactive_samples": 0, "total_samples": 0}}'
        return
    fi

    # 提取genie_active=true时的system_mem_used值
    local genie_active_values
    genie_active_values=$(grep "genie_active:true" "$memory_log_file" | grep -o "system_mem_used:[0-9]*KB" | awk -F: '{gsub(/[^0-9]/, "", $2); if($2>0) print $2}')

    # 提取genie_active=false时的system_mem_used值
    local genie_inactive_values
    genie_inactive_values=$(grep "genie_active:false" "$memory_log_file" | grep -o "system_mem_used:[0-9]*KB" | awk -F: '{gsub(/[^0-9]/, "", $2); if($2>0) print $2}')

    # 计算基准内存（genie不活动时的最小值）
    local baseline_mem_kb="NA"
    local baseline_mem_mb="NA"
    local genie_inactive_samples=0

    if [ -n "$genie_inactive_values" ]; then
        baseline_mem_kb=$(echo "$genie_inactive_values" | sort -n | head -1)
        baseline_mem_mb=$(echo "$baseline_mem_kb 1024" | awk '{printf "%.1f", $1 / $2}')
        genie_inactive_samples=$(echo "$genie_inactive_values" | wc -l)
    fi

    # 计算峰值内存（genie活动时的最大值）
    local peak_mem_kb="NA"
    local peak_mem_mb="NA"
    local genie_active_samples=0

    if [ -n "$genie_active_values" ]; then
        peak_mem_kb=$(echo "$genie_active_values" | sort -nr | head -1)
        peak_mem_mb=$(echo "$peak_mem_kb 1024" | awk '{printf "%.1f", $1 / $2}')
        genie_active_samples=$(echo "$genie_active_values" | wc -l)
    fi

    # 计算模型内存占用
    local model_memory_kb="NA"
    local model_memory_mb="NA"

    if [ "$baseline_mem_kb" != "NA" ] && [ "$peak_mem_kb" != "NA" ]; then
        model_memory_kb=$((peak_mem_kb - baseline_mem_kb))
        model_memory_mb=$(echo "$model_memory_kb 1024" | awk '{printf "%.1f", $1 / $2}')
    fi

    # 计算总样本数
    local total_samples=$((genie_active_samples + genie_inactive_samples))

    # 生成JSON输出
    cat << EOF
{
  "memory_analysis": {
    "baseline_mem_kb": $baseline_mem_kb,
    "baseline_mem_mb": $baseline_mem_mb,
    "peak_mem_kb": $peak_mem_kb,
    "peak_mem_mb": $peak_mem_mb,
    "model_memory_kb": $model_memory_kb,
    "model_memory_mb": $model_memory_mb,
    "genie_active_samples": $genie_active_samples,
    "genie_inactive_samples": $genie_inactive_samples,
    "total_samples": $total_samples
  }
}
EOF
}

# Phase 1: LLM测试
run_actual_test() {
    log_info "=== Phase 1: LLM测试开始 ==="

    # 记录测试开始温度
    # 为了简化温度JSON处理，将温度数据保存到临时文件

    record_component_temperature "start"
    cat "$TEMPERATURE_TEMP_FILE" > "$LLM_START_TEMPERATURE_FILE"

    # 重置电池统计
    dumpsys batterystats --reset >/dev/null 2>&1
    local actual_start_time=$(date '+%Y-%m-%dT%H:%M:%S')

    # 运行实际的推理脚本
    log_info "开始运行推理测试..."
    if [ -f "$TEST_SCRIPT" ]; then
        sh "$TEST_SCRIPT" > "$OUTPUT_FILE" 2>&1
        local script_exit_code=$?
    else
        log_error "测试脚本 $TEST_SCRIPT 不存在"
        return 1
    fi

    local actual_end_time=$(date '+%Y-%m-%dT%H:%M:%S')

    # 记录测试结束温度
    record_component_temperature "end"
    cat "$TEMPERATURE_TEMP_FILE" > "$LLM_END_TEMPERATURE_FILE"


    local actual_power_result
    actual_power_result=$(get_power_consumption "$actual_start_time" "$actual_end_time" "LLM测试")

    # 解析功耗结果（四个值：computed actual_min actual_max soc）
    local actual_computed_power=$(echo "$actual_power_result" | awk '{print $1}')
    local actual_actual_min_power=$(echo "$actual_power_result" | awk '{print $2}')
    local actual_actual_max_power=$(echo "$actual_power_result" | awk '{print $3}')
    local actual_soc_power=$(echo "$actual_power_result" | awk '{print $4}')

    # 从输出中提取运行时间
    local runtime_ms=-1
    local runtime_s=-1
    if [ -f "$OUTPUT_FILE" ]; then
        runtime_ms=$(grep "TEST_RUNTIME_MS=" "$OUTPUT_FILE" | tail -1 | cut -d'=' -f2 | tr -d ' \n\r' || echo "-1")
        runtime_s=$(grep "TEST_RUNTIME_SECONDS=" "$OUTPUT_FILE" | tail -1 | cut -d'=' -f2 | tr -d ' \n\r' || echo "-1")

        # 验证提取的值
        if ! echo "$runtime_ms" | grep -qE '^[0-9]+$'; then
            runtime_ms="-1"
            log_info "运行时间(ms)数据无效，设置为 -1"
        fi

        if ! echo "$runtime_s" | grep -qE '^[0-9]+$'; then
            runtime_s="-1"
            log_info "运行时间(s)数据无效，设置为 -1"
        fi
    else
        log_info "输出文件不存在，运行时间设置为 -1"
    fi

    # 输出LLM测试耗电量结果
    {
        echo "LLM_TEST_START_TIMESTAMP=$actual_start_time"
        echo "LLM_TEST_END_TIMESTAMP=$actual_end_time"
        echo "LLM_TEST_DURATION_MS=$runtime_ms"
        echo "LLM_TEST_DURATION_S=$runtime_s"
        echo "LLM_COMPUTED_POWER_MAH=$actual_computed_power"
        echo "LLM_ACTUAL_MIN_POWER_MAH=$actual_actual_min_power"
        echo "LLM_ACTUAL_MAX_POWER_MAH=$actual_actual_max_power"
        echo "LLM_SOC_POWER_MAH=$actual_soc_power"
    } >> "$POWER_LOG_FILE"

    log_info "=== Phase 2: LLM测试完成 ==="
    echo "$actual_computed_power" "$actual_actual_min_power" "$actual_actual_max_power" "$actual_soc_power" "$runtime_ms" "$runtime_s" "$actual_start_time" "$actual_end_time"
}

# Phase 2: 基线测试（空闲运行相同时间）
run_baseline_test() {
    local test_duration=$1

    log_info "=== Phase 2: 基线测试开始 ==="
    log_info "测试时长: ${test_duration} 秒"

    # 记录基线测试开始温度
    record_component_temperature "start"
    cat "$TEMPERATURE_TEMP_FILE" > "$BASELINE_START_TEMPERATURE_FILE"

    # 重置电池统计
    dumpsys batterystats --reset >/dev/null 2>&1
    local baseline_start_time=$(date +%s%3N)

    # 空闲运行相同时间
    log_info "开始空闲运行..."
    sleep "$test_duration"

    local baseline_end_time=$(date +%s%3N)
    local baseline_duration_ms=$((baseline_end_time - baseline_start_time))

    # 记录基线测试结束温度
    record_component_temperature "end"
    cat "$TEMPERATURE_TEMP_FILE" > "$BASELINE_END_TEMPERATURE_FILE"

    local baseline_power_result
    baseline_power_result=$(get_power_consumption "$baseline_start_time" "$baseline_end_time" "基线测试")

    # 解析功耗结果（四个值：computed actual_min actual_max soc）
    local baseline_computed_power=$(echo "$baseline_power_result" | awk '{print $1}')
    local baseline_actual_min_power=$(echo "$baseline_power_result" | awk '{print $2}')
    local baseline_actual_max_power=$(echo "$baseline_power_result" | awk '{print $3}')
    local baseline_soc_power=$(echo "$baseline_power_result" | awk '{print $4}')

    # 输出基线测试耗电量结果
    {
        echo "BASELINE_TEST_DURATION_MS=$baseline_duration_ms"
        echo "BASELINE_TEST_DURATION_S=$test_duration"
        echo "BASELINE_COMPUTED_POWER_MAH=$baseline_computed_power"
        echo "BASELINE_ACTUAL_MIN_POWER_MAH=$baseline_actual_min_power"
        echo "BASELINE_ACTUAL_MAX_POWER_MAH=$baseline_actual_max_power"
        echo "BASELINE_SOC_POWER_MAH=$baseline_soc_power"
    } >> "$POWER_LOG_FILE"

    log_info "=== Phase 1: 基线测试完成 ==="
    echo "$baseline_computed_power" "$baseline_actual_min_power" "$baseline_actual_max_power" "$baseline_soc_power" "$baseline_duration_ms"
}



# 生成最终报告
generate_final_report() {
    local baseline_computed_power=$1
    local baseline_actual_min_power=$2
    local baseline_actual_max_power=$3
    local baseline_soc_power=$4
    local baseline_duration_ms=$5
    local actual_computed_power=$6
    local actual_actual_min_power=$7
    local actual_actual_max_power=$8
    local actual_soc_power=$9
    local runtime_ms=${10}
    local runtime_s=${11}
    local actual_start_time=${12}
    local actual_end_time=${13}
    local actual_start_temp_file="$LLM_START_TEMPERATURE_FILE"
    local actual_end_temp_file="$LLM_END_TEMPERATURE_FILE"
    local baseline_start_temp_file="$BASELINE_START_TEMPERATURE_FILE"
    local baseline_end_temp_file="$BASELINE_END_TEMPERATURE_FILE"

    log_info "生成最终报告..."

    # 直接使用格式化时间（无需转换）
    local llm_start_time_readable="-1"
    local llm_end_time_readable="-1"

    if [ -n "$actual_start_time" ] && [ "$actual_start_time" != "-1" ]; then
        llm_start_time_readable="$actual_start_time"
    fi

    if [ -n "$actual_end_time" ] && [ "$actual_end_time" != "-1" ]; then
        llm_end_time_readable="$actual_end_time"
    fi

    # 计算genie实际耗电量（三种方式）
    local genie_computed_power="-1.0"
    local genie_actual_min_power="-1.0"
    local genie_actual_max_power="-1.0"
    local genie_computed_avg_power="-1.0"
    local genie_actual_min_avg_power="-1.0"
    local genie_actual_max_avg_power="-1.0"

    # 计算SoC净耗电量（来自Global CPU）
    local genie_soc_power="-1.0"
    local genie_soc_avg_power="-1.0"
    local genie_soc_power_per_inference="-1.0"

    # 检查输入值是否有效（不是-1且是有效数字）
    local baseline_computed_valid=false
    local baseline_actual_min_valid=false
    local baseline_actual_max_valid=false
    local baseline_soc_valid=false
    local actual_computed_valid=false
    local actual_actual_min_valid=false
    local actual_actual_max_valid=false
    local actual_soc_valid=false
    local runtime_valid=false

    # 验证基线耗电量
    if echo "$baseline_computed_power" | grep -qE '^-?[0-9]+\.?[0-9]*$' && [ "$baseline_computed_power" != "-1.0" ] && [ "$baseline_computed_power" != "-1" ]; then
        baseline_computed_valid=true
    fi
    if echo "$baseline_actual_min_power" | grep -qE '^-?[0-9]+\.?[0-9]*$' && [ "$baseline_actual_min_power" != "-1.0" ] && [ "$baseline_actual_min_power" != "-1" ]; then
        baseline_actual_min_valid=true
    fi
    if echo "$baseline_actual_max_power" | grep -qE '^-?[0-9]+\.?[0-9]*$' && [ "$baseline_actual_max_power" != "-1.0" ] && [ "$baseline_actual_max_power" != "-1" ]; then
        baseline_actual_max_valid=true
    fi
    if echo "$baseline_soc_power" | grep -qE '^-?[0-9]+\.?[0-9]*$' && [ "$baseline_soc_power" != "-1.0" ] && [ "$baseline_soc_power" != "-1" ]; then
        baseline_soc_valid=true
    fi

    # 验证实际耗电量
    if echo "$actual_computed_power" | grep -qE '^-?[0-9]+\.?[0-9]*$' && [ "$actual_computed_power" != "-1.0" ] && [ "$actual_computed_power" != "-1" ]; then
        actual_computed_valid=true
    fi
    if echo "$actual_actual_min_power" | grep -qE '^-?[0-9]+\.?[0-9]*$' && [ "$actual_actual_min_power" != "-1.0" ] && [ "$actual_actual_min_power" != "-1" ]; then
        actual_actual_min_valid=true
    fi
    if echo "$actual_actual_max_power" | grep -qE '^-?[0-9]+\.?[0-9]*$' && [ "$actual_actual_max_power" != "-1.0" ] && [ "$actual_actual_max_power" != "-1" ]; then
        actual_actual_max_valid=true
    fi
    if echo "$actual_soc_power" | grep -qE '^-?[0-9]+\.?[0-9]*$' && [ "$actual_soc_power" != "-1.0" ] && [ "$actual_soc_power" != "-1" ]; then
        actual_soc_valid=true
    fi

    # 验证运行时间
    if echo "$runtime_s" | grep -qE '^-?[0-9]+$' && [ "$runtime_s" != "-1" ] && [ "$runtime_s" -gt 0 ]; then
        runtime_valid=true
    fi

    # 计算净耗电量
    if $baseline_computed_valid && $actual_computed_valid; then
        genie_computed_power=$(echo "$actual_computed_power $baseline_computed_power" | awk '{printf "%.3f", $1 - $2}')
        log_info "计算computed净耗电量: $actual_computed_power - $baseline_computed_power = $genie_computed_power mAh"
    else
        log_info "无法计算computed净耗电量 - 基线有效: $baseline_computed_valid, 实际有效: $actual_computed_valid"
    fi

    if $baseline_actual_min_valid && $actual_actual_min_valid; then
        genie_actual_min_power=$(echo "$actual_actual_min_power $baseline_actual_min_power" | awk '{printf "%.3f", $1 - $2}')
        log_info "计算actual_min净耗电量: $actual_actual_min_power - $baseline_actual_min_power = $genie_actual_min_power mAh"
    else
        log_info "无法计算actual_min净耗电量 - 基线有效: $baseline_actual_min_valid, 实际有效: $actual_actual_min_valid"
    fi

    if $baseline_actual_max_valid && $actual_actual_max_valid; then
        genie_actual_max_power=$(echo "$actual_actual_max_power $baseline_actual_max_power" | awk '{printf "%.3f", $1 - $2}')
        log_info "计算actual_max净耗电量: $actual_actual_max_power - $baseline_actual_max_power = $genie_actual_max_power mAh"
    else
        log_info "无法计算actual_max净耗电量 - 基线有效: $baseline_actual_max_valid, 实际有效: $actual_actual_max_valid"
    fi

    # 计算SoC净耗电量（来自Global CPU）
    if $baseline_soc_valid && $actual_soc_valid; then
        genie_soc_power=$(echo "$actual_soc_power $baseline_soc_power" | awk '{printf "%.3f", $1 - $2}')
        log_info "计算SoC净耗电量: $actual_soc_power - $baseline_soc_power = $genie_soc_power mAh (来自Global CPU)"
    else
        log_info "无法计算SoC净耗电量 - 基线有效: $baseline_soc_valid, 实际有效: $actual_soc_valid"
    fi

    # 计算基线功耗（基线耗电量 ÷ 基线时间(小时)）
    local baseline_computed_avg_power="-1.0"
    local baseline_actual_min_avg_power="-1.0"
    local baseline_actual_max_avg_power="-1.0"

    if [ "$baseline_duration_s" -gt 0 ]; then
        # 时间转换为小时
        local baseline_duration_hours=$(echo "$baseline_duration_s 3600" | awk '{printf "%.6f", $1 / $2}')
        log_info "基线时间转换: ${baseline_duration_s}秒 = ${baseline_duration_hours}小时"

        if echo "$baseline_computed_power_from_log" | grep -qE '^-?[0-9]+\.?[0-9]*$' && [ "$baseline_computed_power_from_log" != "-1.0" ]; then
            baseline_computed_avg_power=$(echo "$baseline_computed_power_from_log $baseline_duration_hours" | awk '{printf "%.3f", $1 / $2}')
            log_info "计算基线computed功耗: ${baseline_computed_power_from_log} mAh ÷ ${baseline_duration_hours} h = $baseline_computed_avg_power mA"
        fi

        if echo "$baseline_actual_min_power_from_log" | grep -qE '^-?[0-9]+\.?[0-9]*$' && [ "$baseline_actual_min_power_from_log" != "-1.0" ]; then
            baseline_actual_min_avg_power=$(echo "$baseline_actual_min_power_from_log $baseline_duration_hours" | awk '{printf "%.3f", $1 / $2}')
            log_info "计算基线actual_min功耗: ${baseline_actual_min_power_from_log} mAh ÷ ${baseline_duration_hours} h = $baseline_actual_min_avg_power mA"
        fi

        if echo "$baseline_actual_max_power_from_log" | grep -qE '^-?[0-9]+\.?[0-9]*$' && [ "$baseline_actual_max_power_from_log" != "-1.0" ]; then
            baseline_actual_max_avg_power=$(echo "$baseline_actual_max_power_from_log $baseline_duration_hours" | awk '{printf "%.3f", $1 / $2}')
            log_info "计算基线actual_max功耗: ${baseline_actual_max_power_from_log} mAh ÷ ${baseline_duration_hours} h = $baseline_actual_max_avg_power mA"
        fi
    else
        log_info "基线时间无效，无法计算基线功耗 - 基线时长: $baseline_duration_s"
    fi

    # 计算实际功耗（实际耗电量 ÷ 实际时间(小时)）
    local actual_computed_avg_power="-1.0"
    local actual_actual_min_avg_power="-1.0"
    local actual_actual_max_avg_power="-1.0"

    if $runtime_valid; then
        # 时间转换为小时
        local runtime_hours=$(echo "$runtime_s 3600" | awk '{printf "%.6f", $1 / $2}')
        log_info "实际时间转换: ${runtime_s}秒 = ${runtime_hours}小时"

        if echo "$actual_computed_power" | grep -qE '^-?[0-9]+\.?[0-9]*$' && [ "$actual_computed_power" != "-1.0" ]; then
            actual_computed_avg_power=$(echo "$actual_computed_power $runtime_hours" | awk '{printf "%.3f", $1 / $2}')
            log_info "计算实际computed功耗: ${actual_computed_power} mAh ÷ ${runtime_hours} h = $actual_computed_avg_power mA"
        fi

        if echo "$actual_actual_min_power" | grep -qE '^-?[0-9]+\.?[0-9]*$' && [ "$actual_actual_min_power" != "-1.0" ]; then
            actual_actual_min_avg_power=$(echo "$actual_actual_min_power $runtime_hours" | awk '{printf "%.3f", $1 / $2}')
            log_info "计算实际actual_min功耗: ${actual_actual_min_power} mAh ÷ ${runtime_hours} h = $actual_actual_min_avg_power mA"
        fi

        if echo "$actual_actual_max_power" | grep -qE '^-?[0-9]+\.?[0-9]*$' && [ "$actual_actual_max_power" != "-1.0" ]; then
            actual_actual_max_avg_power=$(echo "$actual_actual_max_power $runtime_hours" | awk '{printf "%.3f", $1 / $2}')
            log_info "计算实际actual_max功耗: ${actual_actual_max_power} mAh ÷ ${runtime_hours} h = $actual_actual_max_avg_power mA"
        fi
    else
        log_info "实际时间无效，无法计算实际功耗 - 运行时间: $runtime_s"
    fi

    # 计算Genie净功耗（Genie净耗电量 ÷ 实际时间(小时)）
    local genie_computed_avg_power="-1.0"
    local genie_actual_min_avg_power="-1.0"
    local genie_actual_max_avg_power="-1.0"

    if $runtime_valid; then
        # 使用之前转换的时间
        log_info "计算Genie净功耗使用时间转换: ${runtime_s}秒 = ${runtime_hours}小时"

        if echo "$genie_computed_power" | grep -qE '^-?[0-9]+\.?[0-9]*$' && [ "$genie_computed_power" != "-1.0" ]; then
            genie_computed_avg_power=$(echo "$genie_computed_power $runtime_hours" | awk '{printf "%.3f", $1 / $2}')
            log_info "计算Genie computed平均功耗: $genie_computed_power mAh ÷ $runtime_hours h = $genie_computed_avg_power mA"
        fi

        if echo "$genie_actual_min_power" | grep -qE '^-?[0-9]+\.?[0-9]*$' && [ "$genie_actual_min_power" != "-1.0" ]; then
            genie_actual_min_avg_power=$(echo "$genie_actual_min_power $runtime_hours" | awk '{printf "%.3f", $1 / $2}')
            log_info "计算Genie actual_min平均功耗: $genie_actual_min_power mAh ÷ $runtime_hours h = $genie_actual_min_avg_power mA"
        fi

        if echo "$genie_actual_max_power" | grep -qE '^-?[0-9]+\.?[0-9]*$' && [ "$genie_actual_max_power" != "-1.0" ]; then
            genie_actual_max_avg_power=$(echo "$genie_actual_max_power $runtime_hours" | awk '{printf "%.3f", $1 / $2}')
            log_info "计算Genie actual_max平均功耗: $genie_actual_max_power mAh ÷ $runtime_hours h = $genie_actual_max_avg_power mA"
        fi

        # 计算SoC净功耗
        if echo "$genie_soc_power" | grep -qE '^-?[0-9]+\.?[0-9]*$' && [ "$genie_soc_power" != "-1.0" ]; then
            genie_soc_avg_power=$(echo "$genie_soc_power $runtime_hours" | awk '{printf "%.3f", $1 / $2}')
            log_info "计算SoC平均功耗: $genie_soc_power mAh ÷ $runtime_hours h = $genie_soc_avg_power mA (来自Global CPU)"
        fi
    else
        log_info "无法计算Genie净功耗 - 运行时间有效: $runtime_valid"
    fi

    # 分析内存数据
    local memory_stats
    memory_stats=$(analyze_memory_data "memory_logs/system_memory.log")

    # 统计推理进程数量
    local process_count=0
    if [ -f "power_logs/all_pids.txt" ]; then
        process_count=$(wc -l < "power_logs/all_pids.txt")
    fi

    # 统计完成的题目数量
    local completed_questions=0
    for subject_file in result/temp/*_answers.txt; do
        if [ -f "$subject_file" ]; then
            local subject_questions
            subject_questions=$(grep -c "ANSWER_START" "$subject_file" 2>/dev/null || echo 0)
            completed_questions=$((completed_questions + subject_questions))
        fi
    done 2>/dev/null || true

    # 预计算复杂的awk值（三种耗电量方式）
    local computed_power_per_inference="-1.0"
    local actual_min_power_per_inference="-1.0"
    local actual_max_power_per_inference="-1.0"

    if [ $process_count -gt 0 ]; then
        if echo "$genie_computed_power" | grep -qE '^-?[0-9]+\.?[0-9]*$' && [ "$genie_computed_power" != "-1.0" ]; then
            computed_power_per_inference=$(echo "$genie_computed_power $process_count" | awk '{printf "%.6f", $1 / $2}')
            log_info "计算computed每次推理耗电量: $genie_computed_power / $process_count = $computed_power_per_inference mAh"
        else
            log_info "无法计算computed每次推理耗电量 - 净耗电量: $genie_computed_power, 进程数: $process_count"
        fi

        if echo "$genie_actual_min_power" | grep -qE '^-?[0-9]+\.?[0-9]*$' && [ "$genie_actual_min_power" != "-1.0" ]; then
            actual_min_power_per_inference=$(echo "$genie_actual_min_power $process_count" | awk '{printf "%.6f", $1 / $2}')
            log_info "计算actual_min每次推理耗电量: $genie_actual_min_power / $process_count = $actual_min_power_per_inference mAh"
        else
            log_info "无法计算actual_min每次推理耗电量 - 净耗电量: $genie_actual_min_power, 进程数: $process_count"
        fi

        if echo "$genie_actual_max_power" | grep -qE '^-?[0-9]+\.?[0-9]*$' && [ "$genie_actual_max_power" != "-1.0" ]; then
            actual_max_power_per_inference=$(echo "$genie_actual_max_power $process_count" | awk '{printf "%.6f", $1 / $2}')
            log_info "计算actual_max每次推理耗电量: $genie_actual_max_power / $process_count = $actual_max_power_per_inference mAh"
        else
            log_info "无法计算actual_max每次推理耗电量 - 净耗电量: $genie_actual_max_power, 进程数: $process_count"
        fi

        # 计算SoC每次推理耗电量
        if echo "$genie_soc_power" | grep -qE '^-?[0-9]+\.?[0-9]*$' && [ "$genie_soc_power" != "-1.0" ]; then
            genie_soc_power_per_inference=$(echo "$genie_soc_power $process_count" | awk '{printf "%.6f", $1 / $2}')
            log_info "计算SoC每次推理耗电量: $genie_soc_power / $process_count = $genie_soc_power_per_inference mAh (来自Global CPU)"
        else
            log_info "无法计算SoC每次推理耗电量 - 净耗电量: $genie_soc_power, 进程数: $process_count"
        fi
    fi

    local avg_time_per_question="-1"
    if [ $completed_questions -gt 0 ] && echo "$runtime_ms" | grep -qE '^-?[0-9]+$' && [ "$runtime_ms" != "-1" ]; then
        avg_time_per_question=$(echo "$runtime_ms $completed_questions" | awk '{printf "%.0f", $1 / $2}')
        log_info "计算每题平均时间: $runtime_ms / $completed_questions = $avg_time_per_question ms"
    else
        log_info "无法计算每题平均时间 - 运行时间: $runtime_ms, 完成题目数: $completed_questions"
    fi

    # 从日志文件中提取基线测试耗电量数据
    local baseline_duration_s=-1
    local baseline_computed_power_from_log="-1.0"
    local baseline_actual_min_power_from_log="-1.0"
    local baseline_actual_max_power_from_log="-1.0"
    local baseline_soc_power_from_log="-1.0"
    if [ -f "$POWER_LOG_FILE" ]; then
        # 提取基线时长，确保只获取数值部分
        baseline_duration_s=$(grep "BASELINE_TEST_DURATION_S=" "$POWER_LOG_FILE" | tail -1 | cut -d'=' -f2 | tr -d ' \n\r' || echo "-1")
        # 验证并转换为数字
        if ! echo "$baseline_duration_s" | grep -qE '^[0-9]+$'; then
            baseline_duration_s="-1"
            log_info "基线时长数据无效，设置为 -1"
        fi

        # 提取基线耗电量（四种）
        baseline_computed_power_from_log=$(grep "BASELINE_COMPUTED_POWER_MAH=" "$POWER_LOG_FILE" | tail -1 | cut -d'=' -f2 | tr -d ' \n\r' || echo "-1.0")
        baseline_actual_min_power_from_log=$(grep "BASELINE_ACTUAL_MIN_POWER_MAH=" "$POWER_LOG_FILE" | tail -1 | cut -d'=' -f2 | tr -d ' \n\r' || echo "-1.0")
        baseline_actual_max_power_from_log=$(grep "BASELINE_ACTUAL_MAX_POWER_MAH=" "$POWER_LOG_FILE" | tail -1 | cut -d'=' -f2 | tr -d ' \n\r' || echo "-1.0")
        baseline_soc_power_from_log=$(grep "BASELINE_SOC_POWER_MAH=" "$POWER_LOG_FILE" | tail -1 | cut -d'=' -f2 | tr -d ' \n\r' || echo "-1.0")

        # 验证并转换为数字
        for var in baseline_computed_power_from_log baseline_actual_min_power_from_log baseline_actual_max_power_from_log baseline_soc_power_from_log; do
            local value=$(eval echo \$$var)
            if ! echo "$value" | grep -qE '^[0-9]+\.?[0-9]*$'; then
                eval "$var=\"-1.0\""
                log_info "基线${var}耗电量数据无效，设置为 -1.0"
            fi
        done

        log_info "从日志提取 - 基线时长: ${baseline_duration_s}s, 基线computed耗电量: ${baseline_computed_power_from_log}mAh, 基线actual_min耗电量: ${baseline_actual_min_power_from_log}mAh, 基线actual_max耗电量: ${baseline_actual_max_power_from_log}mAh, 基线SoC耗电量: ${baseline_soc_power_from_log}mAh"
    else
        log_info "日志文件不存在，基线数据设置为 -1"
    fi

    # 生成JSON报告
    local timestamp
    timestamp=$(TZ='Asia/Shanghai' date '+%Y-%m-%d %H:%M:%S')

    local safe_baseline_soc_power=${baseline_soc_power_from_log:-"-1.0"}
    local safe_baseline_duration_ms=${baseline_duration_ms:-"-1"}
    local safe_runtime_ms=${runtime_ms:-"-1"}
    local safe_runtime_s=${runtime_s:-"-1"}
    local safe_baseline_duration_s=${baseline_duration_s:-"-1"}
    local safe_avg_time_per_question=${avg_time_per_question:-"-1"}
    local safe_genie_soc_power=${genie_soc_power:-"-1.0"}
    local safe_genie_soc_avg_power=${genie_soc_avg_power:-"-1.0"}
    local safe_genie_soc_power_per_inference=${genie_soc_power_per_inference:-"-1.0"}

    # 验证和清理所有时间数值
    for var in safe_runtime_ms safe_runtime_s safe_baseline_duration_s safe_baseline_duration_ms safe_avg_time_per_question; do
        local value=$(eval echo \$$var)
        if ! echo "$value" | grep -qE '^-?[0-9]+$'; then
            eval "$var=\"-1\""
            log_info "变量 $var 的值($value)无效，设置为 -1"
        fi
    done

    # 读取温度数据
    local baseline_component_temperature="{}"
    local llm_component_temperature="{}"

    if [ -f "$baseline_start_temp_file" ] && [ -f "$baseline_end_temp_file" ]; then
        # 简化温度JSON读取，避免复杂的管道操作
        local battery_start_temp=$(cat "$baseline_start_temp_file" 2>/dev/null | grep -o '"battery": {[^}]*}' | grep -o '[0-9]*' | head -1)
        local battery_end_temp=$(cat "$baseline_end_temp_file" 2>/dev/null | grep -o '"battery": {[^}]*}' | grep -o '[0-9]*' | head -1)
        local cpu0_start_temp=$(cat "$baseline_start_temp_file" 2>/dev/null | grep -o '"cpu-0": {[^}]*}' | grep -o '[0-9]*' | head -1)
        local cpu0_end_temp=$(cat "$baseline_end_temp_file" 2>/dev/null | grep -o '"cpu-0": {[^}]*}' | grep -o '[0-9]*' | head -1)
        local cpu1_start_temp=$(cat "$baseline_start_temp_file" 2>/dev/null | grep -o '"cpu-1": {[^}]*}' | grep -o '[0-9]*' | head -1)
        local cpu1_end_temp=$(cat "$baseline_end_temp_file" 2>/dev/null | grep -o '"cpu-1": {[^}]*}' | grep -o '[0-9]*' | head -1)
        local cpuss_start_temp=$(cat "$baseline_start_temp_file" 2>/dev/null | grep -o '"cpuss": {[^}]*}' | grep -o '[0-9]*' | head -1)
        local cpuss_end_temp=$(cat "$baseline_end_temp_file" 2>/dev/null | grep -o '"cpuss": {[^}]*}' | grep -o '[0-9]*' | head -1)
        local ddr_start_temp=$(cat "$baseline_start_temp_file" 2>/dev/null | grep -o '"ddr": {[^}]*}' | grep -o '[0-9]*' | head -1)
        local ddr_end_temp=$(cat "$baseline_end_temp_file" 2>/dev/null | grep -o '"ddr": {[^}]*}' | grep -o '[0-9]*' | head -1)
        local gpuss_start_temp=$(cat "$baseline_start_temp_file" 2>/dev/null | grep -o '"gpuss": {[^}]*}' | grep -o '[0-9]*' | head -1)
        local gpuss_end_temp=$(cat "$baseline_end_temp_file" 2>/dev/null | grep -o '"gpuss": {[^}]*}' | grep -o '[0-9]*' | head -1)
        local nsphmx_start_temp=$(cat "$baseline_start_temp_file" 2>/dev/null | grep -o '"nsphmx": {[^}]*}' | grep -o '[0-9]*' | head -1)
        local nsphmx_end_temp=$(cat "$baseline_end_temp_file" 2>/dev/null | grep -o '"nsphmx": {[^}]*}' | grep -o '[0-9]*' | head -1)
        local nsphvx_start_temp=$(cat "$baseline_start_temp_file" 2>/dev/null | grep -o '"nsphvx": {[^}]*}' | grep -o '[0-9]*' | head -1)
        local nsphvx_end_temp=$(cat "$baseline_end_temp_file" 2>/dev/null | grep -o '"nsphvx": {[^}]*}' | grep -o '[0-9]*' | head -1)
        local shell_back_start_temp=$(cat "$baseline_start_temp_file" 2>/dev/null | grep -o '"shell_back": {[^}]*}' | grep -o '[0-9]*' | head -1)
        local shell_back_end_temp=$(cat "$baseline_end_temp_file" 2>/dev/null | grep -o '"shell_back": {[^}]*}' | grep -o '[0-9]*' | head -1)
        local shell_frame_start_temp=$(cat "$baseline_start_temp_file" 2>/dev/null | grep -o '"shell_frame": {[^}]*}' | grep -o '[0-9]*' | head -1)
        local shell_frame_end_temp=$(cat "$baseline_end_temp_file" 2>/dev/null | grep -o '"shell_frame": {[^}]*}' | grep -o '[0-9]*' | head -1)
        local shell_front_start_temp=$(cat "$baseline_start_temp_file" 2>/dev/null | grep -o '"shell_front": {[^}]*}' | grep -o '[0-9]*' | head -1)
        local shell_front_end_temp=$(cat "$baseline_end_temp_file" 2>/dev/null | grep -o '"shell_front": {[^}]*}' | grep -o '[0-9]*' | head -1)

        # 设置默认值
        [ -z "$battery_start_temp" ] && battery_start_temp="0"
        [ -z "$battery_end_temp" ] && battery_end_temp="0"
        [ -z "$cpu0_start_temp" ] && cpu0_start_temp="0"
        [ -z "$cpu0_end_temp" ] && cpu0_end_temp="0"
        [ -z "$cpu1_start_temp" ] && cpu1_start_temp="0"
        [ -z "$cpu1_end_temp" ] && cpu1_end_temp="0"
        [ -z "$cpuss_start_temp" ] && cpuss_start_temp="0"
        [ -z "$cpuss_end_temp" ] && cpuss_end_temp="0"
        [ -z "$ddr_start_temp" ] && ddr_start_temp="0"
        [ -z "$ddr_end_temp" ] && ddr_end_temp="0"
        [ -z "$gpuss_start_temp" ] && gpuss_start_temp="0"
        [ -z "$gpuss_end_temp" ] && gpuss_end_temp="0"
        [ -z "$nsphmx_start_temp" ] && nsphmx_start_temp="0"
        [ -z "$nsphmx_end_temp" ] && nsphmx_end_temp="0"
        [ -z "$nsphvx_start_temp" ] && nsphvx_start_temp="0"
        [ -z "$nsphvx_end_temp" ] && nsphvx_end_temp="0"
        [ -z "$shell_back_start_temp" ] && shell_back_start_temp="0"
        [ -z "$shell_back_end_temp" ] && shell_back_end_temp="0"
        [ -z "$shell_frame_start_temp" ] && shell_frame_start_temp="0"
        [ -z "$shell_frame_end_temp" ] && shell_frame_end_temp="0"
        [ -z "$shell_front_start_temp" ] && shell_front_start_temp="0"
        [ -z "$shell_front_end_temp" ] && shell_front_end_temp="0"

        baseline_component_temperature="{
  \"battery\": { \"start_temperature\": ${battery_start_temp}, \"end_temperature\": ${battery_end_temp} },
  \"cpu-0\": { \"start_temperature\": ${cpu0_start_temp}, \"end_temperature\": ${cpu0_end_temp} },
  \"cpu-1\": { \"start_temperature\": ${cpu1_start_temp}, \"end_temperature\": ${cpu1_end_temp} },
  \"cpuss\": { \"start_temperature\": ${cpuss_start_temp}, \"end_temperature\": ${cpuss_end_temp} },
  \"ddr\": { \"start_temperature\": ${ddr_start_temp}, \"end_temperature\": ${ddr_end_temp} },
  \"gpuss\": { \"start_temperature\": ${gpuss_start_temp}, \"end_temperature\": ${gpuss_end_temp} },
  \"nsphmx\": { \"start_temperature\": ${nsphmx_start_temp}, \"end_temperature\": ${nsphmx_end_temp} },
  \"nsphvx\": { \"start_temperature\": ${nsphvx_start_temp}, \"end_temperature\": ${nsphvx_end_temp} },
  \"shell_back\": { \"start_temperature\": ${shell_back_start_temp}, \"end_temperature\": ${shell_back_end_temp} },
  \"shell_frame\": { \"start_temperature\": ${shell_frame_start_temp}, \"end_temperature\": ${shell_frame_end_temp} },
  \"shell_front\": { \"start_temperature\": ${shell_front_start_temp}, \"end_temperature\": ${shell_front_end_temp} }
}"
    fi

    if [ -f "$actual_start_temp_file" ] && [ -f "$actual_end_temp_file" ]; then
        # 简化温度JSON读取，避免复杂的管道操作
        local battery_start_temp=$(cat "$actual_start_temp_file" 2>/dev/null | grep -o '"battery": {[^}]*}' | grep -o '[0-9]*' | head -1)
        local battery_end_temp=$(cat "$actual_end_temp_file" 2>/dev/null | grep -o '"battery": {[^}]*}' | grep -o '[0-9]*' | head -1)
        local cpu0_start_temp=$(cat "$actual_start_temp_file" 2>/dev/null | grep -o '"cpu-0": {[^}]*}' | grep -o '[0-9]*' | head -1)
        local cpu0_end_temp=$(cat "$actual_end_temp_file" 2>/dev/null | grep -o '"cpu-0": {[^}]*}' | grep -o '[0-9]*' | head -1)
        local cpu1_start_temp=$(cat "$actual_start_temp_file" 2>/dev/null | grep -o '"cpu-1": {[^}]*}' | grep -o '[0-9]*' | head -1)
        local cpu1_end_temp=$(cat "$actual_end_temp_file" 2>/dev/null | grep -o '"cpu-1": {[^}]*}' | grep -o '[0-9]*' | head -1)
        local cpuss_start_temp=$(cat "$actual_start_temp_file" 2>/dev/null | grep -o '"cpuss": {[^}]*}' | grep -o '[0-9]*' | head -1)
        local cpuss_end_temp=$(cat "$actual_end_temp_file" 2>/dev/null | grep -o '"cpuss": {[^}]*}' | grep -o '[0-9]*' | head -1)
        local ddr_start_temp=$(cat "$actual_start_temp_file" 2>/dev/null | grep -o '"ddr": {[^}]*}' | grep -o '[0-9]*' | head -1)
        local ddr_end_temp=$(cat "$actual_end_temp_file" 2>/dev/null | grep -o '"ddr": {[^}]*}' | grep -o '[0-9]*' | head -1)
        local gpuss_start_temp=$(cat "$actual_start_temp_file" 2>/dev/null | grep -o '"gpuss": {[^}]*}' | grep -o '[0-9]*' | head -1)
        local gpuss_end_temp=$(cat "$actual_end_temp_file" 2>/dev/null | grep -o '"gpuss": {[^}]*}' | grep -o '[0-9]*' | head -1)
        local nsphmx_start_temp=$(cat "$actual_start_temp_file" 2>/dev/null | grep -o '"nsphmx": {[^}]*}' | grep -o '[0-9]*' | head -1)
        local nsphmx_end_temp=$(cat "$actual_end_temp_file" 2>/dev/null | grep -o '"nsphmx": {[^}]*}' | grep -o '[0-9]*' | head -1)
        local nsphvx_start_temp=$(cat "$actual_start_temp_file" 2>/dev/null | grep -o '"nsphvx": {[^}]*}' | grep -o '[0-9]*' | head -1)
        local nsphvx_end_temp=$(cat "$actual_end_temp_file" 2>/dev/null | grep -o '"nsphvx": {[^}]*}' | grep -o '[0-9]*' | head -1)
        local shell_back_start_temp=$(cat "$actual_start_temp_file" 2>/dev/null | grep -o '"shell_back": {[^}]*}' | grep -o '[0-9]*' | head -1)
        local shell_back_end_temp=$(cat "$actual_end_temp_file" 2>/dev/null | grep -o '"shell_back": {[^}]*}' | grep -o '[0-9]*' | head -1)
        local shell_frame_start_temp=$(cat "$actual_start_temp_file" 2>/dev/null | grep -o '"shell_frame": {[^}]*}' | grep -o '[0-9]*' | head -1)
        local shell_frame_end_temp=$(cat "$actual_end_temp_file" 2>/dev/null | grep -o '"shell_frame": {[^}]*}' | grep -o '[0-9]*' | head -1)
        local shell_front_start_temp=$(cat "$actual_start_temp_file" 2>/dev/null | grep -o '"shell_front": {[^}]*}' | grep -o '[0-9]*' | head -1)
        local shell_front_end_temp=$(cat "$actual_end_temp_file" 2>/dev/null | grep -o '"shell_front": {[^}]*}' | grep -o '[0-9]*' | head -1)

        # 设置默认值
        [ -z "$battery_start_temp" ] && battery_start_temp="0"
        [ -z "$battery_end_temp" ] && battery_end_temp="0"
        [ -z "$cpu0_start_temp" ] && cpu0_start_temp="0"
        [ -z "$cpu0_end_temp" ] && cpu0_end_temp="0"
        [ -z "$cpu1_start_temp" ] && cpu1_start_temp="0"
        [ -z "$cpu1_end_temp" ] && cpu1_end_temp="0"
        [ -z "$cpuss_start_temp" ] && cpuss_start_temp="0"
        [ -z "$cpuss_end_temp" ] && cpuss_end_temp="0"
        [ -z "$ddr_start_temp" ] && ddr_start_temp="0"
        [ -z "$ddr_end_temp" ] && ddr_end_temp="0"
        [ -z "$gpuss_start_temp" ] && gpuss_start_temp="0"
        [ -z "$gpuss_end_temp" ] && gpuss_end_temp="0"
        [ -z "$nsphmx_start_temp" ] && nsphmx_start_temp="0"
        [ -z "$nsphmx_end_temp" ] && nsphmx_end_temp="0"
        [ -z "$nsphvx_start_temp" ] && nsphvx_start_temp="0"
        [ -z "$nsphvx_end_temp" ] && nsphvx_end_temp="0"
        [ -z "$shell_back_start_temp" ] && shell_back_start_temp="0"
        [ -z "$shell_back_end_temp" ] && shell_back_end_temp="0"
        [ -z "$shell_frame_start_temp" ] && shell_frame_start_temp="0"
        [ -z "$shell_frame_end_temp" ] && shell_frame_end_temp="0"
        [ -z "$shell_front_start_temp" ] && shell_front_start_temp="0"
        [ -z "$shell_front_end_temp" ] && shell_front_end_temp="0"

        llm_component_temperature="{
  \"battery\": { \"start_temperature\": ${battery_start_temp}, \"end_temperature\": ${battery_end_temp} },
  \"cpu-0\": { \"start_temperature\": ${cpu0_start_temp}, \"end_temperature\": ${cpu0_end_temp} },
  \"cpu-1\": { \"start_temperature\": ${cpu1_start_temp}, \"end_temperature\": ${cpu1_end_temp} },
  \"cpuss\": { \"start_temperature\": ${cpuss_start_temp}, \"end_temperature\": ${cpuss_end_temp} },
  \"ddr\": { \"start_temperature\": ${ddr_start_temp}, \"end_temperature\": ${ddr_end_temp} },
  \"gpuss\": { \"start_temperature\": ${gpuss_start_temp}, \"end_temperature\": ${gpuss_end_temp} },
  \"nsphmx\": { \"start_temperature\": ${nsphmx_start_temp}, \"end_temperature\": ${nsphmx_end_temp} },
  \"nsphvx\": { \"start_temperature\": ${nsphvx_start_temp}, \"end_temperature\": ${nsphvx_end_temp} },
  \"shell_back\": { \"start_temperature\": ${shell_back_start_temp}, \"end_temperature\": ${shell_back_end_temp} },
  \"shell_frame\": { \"start_temperature\": ${shell_frame_start_temp}, \"end_temperature\": ${shell_frame_end_temp} },
  \"shell_front\": { \"start_temperature\": ${shell_front_start_temp}, \"end_temperature\": ${shell_front_end_temp} }
}"
    fi

    # 清理临时温度文件
    # rm -f "$actual_start_temp_file" "$actual_end_temp_file" "$baseline_start_temp_file" "$baseline_end_temp_file" 2>/dev/null || true

    cat > "$POWER_MEM_REPORT_FILE" << EOF
{
  "llm_test_start_time": "$llm_start_time_readable",
  "llm_test_end_time": "$llm_end_time_readable",
  "genie_net_power": {
    "soc_consumption_mah": $safe_genie_soc_power,
    "soc_average_power_ma": $safe_genie_soc_avg_power,
    "soc_power_per_inference_mah": $safe_genie_soc_power_per_inference
  },
  "performance_metrics": {
    "total_genie_processes": $process_count,
    "completed_questions": $completed_questions,
    "average_time_per_question_ms": $safe_avg_time_per_question
  },
  $(echo "$memory_stats" | sed '1d;$d'),
  "baseline_test": {
    "soc_power_mah": $safe_baseline_soc_power,
    "duration_s": $safe_baseline_duration_s,
    "component_temperature": $baseline_component_temperature
  },
  "llm_test": {
    "soc_power_mah": $actual_soc_power,
    "duration_ms": $safe_runtime_ms,
    "component_temperature": $llm_component_temperature
  },
  "test_environment": {
    "device_info": "$(getprop ro.product.model 2>/dev/null || echo 'Unknown')",
    "android_version": "$(getprop ro.build.version.release 2>/dev/null || echo 'Unknown')",
    "real_ram_size": "$(cat /proc/meminfo | grep MemTotal | awk '{printf "%.1f", $2/1048576}')",
    "soc_chip": "$(getprop ro.board.platform 2>/dev/null || getprop ro.product.board 2>/dev/null || getprop ro.hardware 2>/dev/null || echo 'Unknown')"
  },
  "generated_at": "$timestamp"
}
EOF

    log_info "最终报告已生成: $POWER_MEM_REPORT_FILE"

    # 输出关键结果
    echo "=== 测试结果摘要 ==="
    echo "基线耗电量 - SoC: ${baseline_soc_power} mAh"
    echo "LLM测试耗电量 - SoC: ${actual_soc_power} mAh"
    echo "Genie净耗电量: ${genie_soc_power} mAh (来自BatteryStats-Global)"
    echo "Genie净功耗: ${genie_soc_avg_power} mA (来自BatteryStats-Global)"
    echo "推理进程数: $process_count"
    echo "完成题目数: $completed_questions"
    echo "详细报告: $POWER_MEM_REPORT_FILE"
}

# 主函数
main() {
    log_info "=== 开始两阶段耗电量测试 ==="

    # 设置环境
    setup_test_environment

    # Phase 1: LLM测试
    local llm_test_result=$(run_actual_test)
    local actual_computed_power=$(echo "$llm_test_result" | awk '{print $1}')
    local actual_actual_min_power=$(echo "$llm_test_result" | awk '{print $2}')
    local actual_actual_max_power=$(echo "$llm_test_result" | awk '{print $3}')
    local actual_soc_power=$(echo "$llm_test_result" | awk '{print $4}')
    local runtime_ms=$(echo "$llm_test_result" | awk '{print $5}')
    local runtime_s=$(echo "$llm_test_result" | awk '{print $6}')
    local actual_start_time=$(echo "$llm_test_result" | awk '{print $7}')
    local actual_end_time=$(echo "$llm_test_result" | awk '{print $8}')




    # Phase 2: 基线测试
    local baseline_computed_power="-1.0"
    local baseline_actual_min_power="-1.0"
    local baseline_actual_max_power="-1.0"
    local baseline_soc_power="-1.0"
    local baseline_duration_ms="-1"

    if [ "$runtime_s" -gt 0 ]; then
        log_info "开始基线测试，时长: $runtime_s 秒"
        local baseline_test_result
        baseline_test_result=$(run_baseline_test "$runtime_s")
        baseline_computed_power=$(echo "$baseline_test_result" | awk '{print $1}')
        baseline_actual_min_power=$(echo "$baseline_test_result" | awk '{print $2}')
        baseline_actual_max_power=$(echo "$baseline_test_result" | awk '{print $3}')
        baseline_soc_power=$(echo "$baseline_test_result" | awk '{print $4}')
        baseline_duration_ms=$(echo "$baseline_test_result" | awk '{print $5}')

        # 保存基线温度数据到临时文件
        local baseline_start_temp_file="temp_baseline_start.json"
        local baseline_end_temp_file="temp_baseline_end.json"

    else
        log_error "LLM测试时长无效(runtime_s=$runtime_s)，无法进行基线测试"
    fi

    # 生成最终报告
    generate_final_report "$baseline_computed_power" "$baseline_actual_min_power" "$baseline_actual_max_power" "$baseline_soc_power" "$baseline_duration_ms" "$actual_computed_power" "$actual_actual_min_power" "$actual_actual_max_power" "$actual_soc_power" "$runtime_ms" "$runtime_s" "$actual_start_time" "$actual_end_time"

    # 恢复环境
    restore_environment

    log_info "=== 两阶段耗电量测试完成 ==="
}

# 错误处理
trap 'log_error "测试被中断"; restore_environment; exit 1' INT TERM

# 执行主函数
main "$@"