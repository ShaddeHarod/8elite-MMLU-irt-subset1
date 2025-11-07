#!/system/bin/sh
# read_all_subjects_prompts.sh
# 对所有sh脚本别忘了做dos2unix指令
# set -e

# 定义目录和文件
PROMPTS_DIR="prompts_by_subject"
FINISHED_FILE="required_json/finished_subjects.json"
QUESTION_COUNTS_FILE="required_json/question_counts_by_subject.json"
POWER_LOG_DIR="power_logs"
MEMORY_LOG_DIR="memory_logs"

# 创建日志目录
mkdir -p "$POWER_LOG_DIR"
mkdir -p "$MEMORY_LOG_DIR"

# 如果finished_subjects.json不存在，创建一个空的JSON文件
if [ ! -f "$FINISHED_FILE" ]; then
    echo "{}" > "$FINISHED_FILE"
fi

# 全局监控变量
GLOBAL_START_TIME=""
GLOBAL_END_TIME=""
ALL_PIDS_FILE="${POWER_LOG_DIR}/all_pids.txt"
UID_POWER_LOG="${POWER_LOG_DIR}/uid_power_consumption.log"

# 启动全局系统监控
start_global_monitoring() {
    echo "=== 启动全局监控 ==="

    # 记录全局开始时间
    GLOBAL_START_TIME=$(date +%s%3N)
    echo "全局监控开始时间: $(TZ='Asia/Shanghai' date '+%Y-%m-%d %H:%M:%S')"

    # 重置电池统计
    cmd battery unplug >/dev/null 2>&1
    dumpsys batterystats --reset >/dev/null 2>&1

    # 清空PID文件
    > "$ALL_PIDS_FILE"

    # 启动系统级内存监控（监控整个genie相关进程）
    echo "启动系统级内存监控..."
    chmod +x /data/local/tmp/genie-qwen2.5-3b/system_memory_monitor.sh
    sh /data/local/tmp/genie-qwen2.5-3b/system_memory_monitor.sh "${MEMORY_LOG_DIR}/system_memory.log" &
    SYSTEM_MEMORY_PID=$!
    echo "系统内存监控PID: $SYSTEM_MEMORY_PID"
}

# 记录进程PID到全局文件
record_pid() {
    local pid=$1
    echo "记录进程PID: $pid"
    echo "$pid" >> "$ALL_PIDS_FILE"
}

# 停止全局监控并生成报告
stop_global_monitoring() {
    echo "=== 停止全局监控 ==="

    # 记录全局结束时间
    GLOBAL_END_TIME=$(date +%s%3N)
    echo "全局监控结束时间: $(TZ='Asia/Shanghai' date '+%Y-%m-%d %H:%M:%S')"

    # 停止系统内存监控
    [ -n "$SYSTEM_MEMORY_PID" ] && kill $SYSTEM_MEMORY_PID 2>/dev/null

    # 计算总运行时间
    if [ -n "$GLOBAL_START_TIME" ] && [ -n "$GLOBAL_END_TIME" ]; then
        total_runtime_ms=$((GLOBAL_END_TIME - GLOBAL_START_TIME))
        total_runtime_seconds=$((total_runtime_ms / 1000))
        echo "总运行时间: ${total_runtime_seconds} 秒 (${total_runtime_ms} 毫秒)"
    fi

    # 获取最终电池统计
    echo "=== 获取总体功耗统计 ==="
    bs_out="$(dumpsys batterystats --checkin)"

    # 分析所有相关UID的功耗
    echo "分析所有genie相关进程的功耗..."

    # 尝试多个可能的UID（shell、genie进程等）
    target_uids="2000 9999 0"  # shell、通常的应用UID、root
    total_power_mah=0

    for uid in $target_uids; do
        uid_power="$(printf "%s\n" "$bs_out" \
          | awk -v uid="$uid" '
            /Estimated power use \(mAh\)/{in_section=1; next}
            in_section && /Uid/{
                for(i=1;i<=NF;i++) {
                    if($i == "Uid" && $(i+1) == uid) {
                        for(j=i+2;j<=NF;j++) {
                            if($j ~ /^[0-9.]+$/) {
                                print $j
                                break
                            }
                        }
                        break
                    }
                }
            }')"

        if [ -n "$uid_power" ] && [ "$uid_power" != "0" ]; then
            # 优先使用awk进行浮点运算
            total_power_mah=$(awk "BEGIN {printf \"%.3f\", $total_power_mah + $uid_power}")
            echo "UID $uid 功耗: ${uid_power} mAh"
        fi
    done

    echo "总功耗: ${total_power_mah} mAh"

    # 计算平均功耗
    if [ -n "$total_runtime_ms" ] && [ "$total_runtime_ms" -gt 0 ] && [ "$total_power_mah" != "0" ]; then
        # 使用awk进行精确的浮点运算
        runtime_hours=$(awk "BEGIN {printf \"%.9f\", $total_runtime_ms / 3600000}")
        avg_power_ma=$(awk "BEGIN {printf \"%.3f\", $total_power_mah / $runtime_hours}")
        echo "平均功耗: ${avg_power_ma} mA"
    fi

    # 电池恢复操作
    cmd battery reset
    dumpsys batterystats --reset

    # 生成综合报告
    generate_summary_report "$total_runtime_ms" "$total_power_mah" "$avg_power_ma"
}

# 分析内存数据
analyze_memory_data() {
    local memory_log_file="$1"

    if [ ! -f "$memory_log_file" ] || [ ! -s "$memory_log_file" ]; then
        echo '{"pss_total": {"peak_kb": "NA", "avg_kb": "NA", "peak_mb": "NA"}, "pss": {"peak_kb": "NA", "avg_kb": "NA", "peak_mb": "NA"}, "samples": 0}'
        return
    fi

    # 提取所有PSS Total内存值
    pss_total_values=$(grep "PSS_Total:" "$memory_log_file" | awk '{gsub(/[^0-9]/, "", $3); if($3>0) print $3}' | grep -E '^[0-9]+$')

    # 处理PSS Total数据
    if [ -n "$pss_total_values" ]; then
        peak_pss_total=$(echo "$pss_total_values" | sort -nr | head -1)
        avg_pss_total=$(echo "$pss_total_values" | awk '{sum+=$1; count++} END {if(count>0) printf "%.0f", sum/count}')
        peak_pss_total_mb=$(awk "BEGIN {printf \"%.1f\", $peak_pss_total / 1024}")
        pss_total_samples=$(echo "$pss_total_values" | wc -l)
    else
        peak_pss_total="NA"
        avg_pss_total="NA"
        peak_pss_total_mb="NA"
        pss_total_samples=0
    fi

    # 使用PSS Total样本数作为主要样本数
    total_samples=$pss_total_samples

    echo "{"
    echo "  \"pss_total\": {"
    echo "    \"peak_kb\": $peak_pss_total,"
    echo "    \"avg_kb\": $avg_pss_total,"
    echo "    \"peak_mb\": $peak_pss_total_mb,"
    echo "    \"samples\": $pss_total_samples"
    echo "  },"
    echo "  \"total_samples\": $total_samples"
    echo "}"
}

# 格式化时间显示
format_duration() {
    local duration_ms=$1
    local hours=$((duration_ms / 3600000))
    local minutes=$(((duration_ms % 3600000) / 60000))
    local seconds=$(((duration_ms % 60000) / 1000))

    printf "%02d:%02d:%02d" $hours $minutes $seconds
}

# 转换答案文件为JSON格式
convert_answers_to_json() {
    echo "=== 开始JSON格式转换函数 ==="

    local temp_dir="result/temp"
    local result_dir="result"

    # 确保目录存在
    mkdir -p "$result_dir"

    # 遍历所有答案文件
    for answers_file in "$temp_dir"/*_answers.txt; do
        [ -f "$answers_file" ] || continue

        # 提取subject名称
        filename=$(basename "$answers_file")
        subject="${filename%_answers.txt}"

        echo "正在处理科目: $subject"

        # 创建JSON文件路径
        json_file="$result_dir/${subject}_LLM_Answer.json"

        # 开始构建JSON
        echo "{" > "$json_file"
        echo "  \"subject\": \"$subject\"," >> "$json_file"
        echo "  \"answers\": [" >> "$json_file"

        local first_answer=true
        local in_answer_block=false
        local question_index=""
        local global_index=""
        local start_timestamp=""
        local final_answer=""
        local model_output=""
        local init_time=""
        local prompt_time=""
        local prompt_rate=""
        local token_time=""
        local token_rate=""
        local end_timestamp=""

        # 逐行解析答案文件
        while IFS= read -r line; do
            case "$line" in
                "ANSWER_START")
                    # 如果不是第一个答案，添加逗号分隔符
                    if [ "$first_answer" = false ]; then
                        echo "," >> "$json_file"
                    fi

                    # 重置变量
                    question_index=""
                    global_index=""
                    start_timestamp=""
                    final_answer=""
                    model_output=""
                    init_time=""
                    prompt_time=""
                    prompt_rate=""
                    token_time=""
                    token_rate=""
                    end_timestamp=""
                    in_answer_block=true

                    # 开始新的答案对象
                    echo "    {" >> "$json_file"
                    ;;
                "question_index:"*)
                    if [ "$in_answer_block" = true ]; then
                        question_index="${line#question_index:}"
                        echo "      \"question_index\": $question_index," >> "$json_file"
                    fi
                    ;;
                "global_index:"*)
                    if [ "$in_answer_block" = true ]; then
                        global_index="${line#global_index:}"
                        echo "      \"global_index\": $global_index," >> "$json_file"
                    fi
                    ;;
                "start_timestamp:"*)
                    if [ "$in_answer_block" = true ]; then
                        start_timestamp="${line#start_timestamp:}"
                        # 转义时间戳中的引号
                        start_timestamp=$(echo "$start_timestamp" | sed 's/"/\\"/g')
                        echo "      \"start_timestamp\": \"$start_timestamp\"," >> "$json_file"
                    fi
                    ;;
                "final_answer:"*)
                    if [ "$in_answer_block" = true ]; then
                        final_answer="${line#final_answer:}"
                        # 转义特殊字符
                        final_answer=$(echo "$final_answer" | sed 's/"/\\"/g')
                        echo "      \"final_answer\": \"$final_answer\"," >> "$json_file"
                    fi
                    ;;
                "model_output:"*)
                    if [ "$in_answer_block" = true ]; then
                        echo "      \"model_output\": \"" >> "$json_file"
                        model_output="waiting_content"
                    fi
                    ;;
                "performance_metrics:"*)
                    if [ "$in_answer_block" = true ]; then
                        # 结束model_output，开始performance_metrics
                        echo "\"," >> "$json_file"
                        echo "      \"performance_metrics\": {" >> "$json_file"
                    fi
                    ;;
                "init_time:"*)
                    if [ "$in_answer_block" = true ]; then
                        init_time="${line#init_time:}"
                        echo "        \"init_time_us\": $init_time," >> "$json_file"
                    fi
                    ;;
                "prompt_processing_time:"*)
                    if [ "$in_answer_block" = true ]; then
                        prompt_time="${line#prompt_processing_time:}"
                        echo "        \"prompt_processing_time_us\": $prompt_time," >> "$json_file"
                    fi
                    ;;
                "prompt_processing_rate:"*)
                    if [ "$in_answer_block" = true ]; then
                        prompt_rate="${line#prompt_processing_rate:}"
                        echo "        \"prompt_processing_rate_toks_per_sec\": $prompt_rate," >> "$json_file"
                    fi
                    ;;
                "token_generation_time:"*)
                    if [ "$in_answer_block" = true ]; then
                        token_time="${line#token_generation_time:}"
                        echo "        \"token_generation_time_us\": $token_time," >> "$json_file"
                    fi
                    ;;
                "token_generation_rate:"*)
                    if [ "$in_answer_block" = true ]; then
                        token_rate="${line#token_generation_rate:}"
                        echo "        \"token_generation_rate_toks_per_sec\": $token_rate" >> "$json_file"
                    fi
                    ;;
                "end_timestamp:"*)
                    if [ "$in_answer_block" = true ]; then
                        end_timestamp="${line#end_timestamp:}"
                        # 转义时间戳中的引号
                        end_timestamp=$(echo "$end_timestamp" | sed 's/"/\\"/g')
                        # 结束performance_metrics对象，并添加逗号，然后添加end_timestamp
                        echo "      }," >> "$json_file"
                        echo "      \"end_timestamp\": \"$end_timestamp\"" >> "$json_file"
                        model_output="completed"  # 标记model_output已处理完成
                    fi
                    ;;
                "ANSWER_END")
                    if [ "$in_answer_block" = true ]; then
                        # 如果model_output还没有结束，需要先结束它
                        if [ "$model_output" = "waiting_content" ]; then
                            echo "\"," >> "$json_file"
                        fi
                        # 结束答案对象
                        echo "    }" >> "$json_file"
                        first_answer=false
                        in_answer_block=false
                    fi
                    ;;
                *)
                    # 处理model_output的内容行
                    if [ "$in_answer_block" = true ] && [ "$model_output" = "waiting_content" ]; then
                        # 转义JSON特殊字符
                        escaped_line=$(echo "$line" | sed 's/\\/\\\\/g; s/"/\\"/g')
                        echo "$escaped_line" >> "$json_file"
                    fi
                    ;;
            esac
        done < "$answers_file"

        # 结束answers数组和JSON对象
        echo "" >> "$json_file"
        echo "  ]" >> "$json_file"
        echo "}" >> "$json_file"

        echo "已生成JSON文件: $json_file"
    done

    echo "=== 答案文件JSON转换完成 ==="
}

# 生成汇总报告
generate_summary_report() {
    echo "DEBUG: 进入 generate_summary_report 函数"

    local runtime_ms=$1
    local total_power_mah=$2
    local avg_power_ma=$3

    echo "DEBUG: 参数接收 - runtime_ms='$runtime_ms'"
    echo "DEBUG: 参数接收 - total_power_mah='$total_power_mah'"
    echo "DEBUG: 参数接收 - avg_power_ma='$avg_power_ma'"

    report_file="result/SUMMARY_REPORT.json"
    echo "DEBUG: 报告文件路径 = '$report_file'"

    echo "DEBUG: 开始创建目录..."
    mkdir -p "$(dirname "$report_file")"
    echo "DEBUG: 目录创建完成"

    echo "DEBUG: 开始生成时间戳..."
    timestamp=$(TZ='Asia/Shanghai' date '+%Y-%m-%d %H:%M:%S')
    echo "DEBUG: 时间戳生成完成 = '$timestamp'"

    # 分析内存统计数据
    echo "DEBUG: 正在分析内存监控数据..."
    echo "DEBUG: 内存日志文件路径 = '$MEMORY_LOG_DIR/system_memory.log'"
    if [ -f "$MEMORY_LOG_DIR/system_memory.log" ]; then
        echo "DEBUG: 内存日志文件存在，开始分析..."
        memory_stats=$(analyze_memory_data "$MEMORY_LOG_DIR/system_memory.log")
        echo "DEBUG: 内存分析完成，结果长度 = ${#memory_stats}"
    else
        echo "DEBUG: 内存日志文件不存在，使用默认值"
        memory_stats='{"pss_total": {"peak_kb": "NA", "avg_kb": "NA", "peak_mb": "NA"}, "pss": {"peak_kb": "NA", "avg_kb": "NA", "peak_mb": "NA"}, "samples": 0}'
    fi

    # 计算进程统计
    echo "DEBUG: 开始计算进程统计..."
    echo "DEBUG: PID文件路径 = '$ALL_PIDS_FILE'"
    process_count=0
    if [ -f "$ALL_PIDS_FILE" ] && [ -s "$ALL_PIDS_FILE" ]; then
        echo "DEBUG: PID文件存在且不为空"
        process_count=$(wc -l < "$ALL_PIDS_FILE")
        echo "DEBUG: 进程计数完成 = $process_count"
    else
        echo "DEBUG: PID文件不存在或为空"
    fi

    # 计算题目统计
    echo "DEBUG: 开始计算题目统计..."
    total_questions=0
    completed_questions=0

    if [ -f "required_json/question_counts_by_subject.json" ]; then
        echo "DEBUG: 题目计数文件存在，开始解析..."
        for num in $(cat required_json/question_counts_by_subject.json | grep -o '[0-9]*'); do
            total_questions=$((total_questions + num))
        done
        echo "DEBUG: 总题目数量计算完成 = $total_questions"
    else
        echo "DEBUG: 题目计数文件不存在"
    fi

    # 统计完成的题目数量
    echo "DEBUG: 开始统计完成的题目数量..."
    echo "DEBUG: 搜索路径 = 'result/temp/*_answers.txt'"
    answer_files_count=$(find result/temp -name "*_answers.txt" 2>/dev/null | wc -l)
    echo "DEBUG: 找到答案文件数量 = $answer_files_count"

    for subject_file in result/temp/*_answers.txt; do
        if [ -f "$subject_file" ]; then
            subject_questions=$(grep -c "ANSWER_START" "$subject_file" 2>/dev/null || echo 0)
            completed_questions=$((completed_questions + subject_questions))
        fi
    done
    echo "DEBUG: 完成题目统计完成 = $completed_questions"

    # 计算基本指标
    echo "DEBUG: 开始计算基本指标..."
    avg_time_per_question=0
    if [ $completed_questions -gt 0 ]; then
        echo "DEBUG: 计算平均时间: runtime_ms=$runtime_ms, completed_questions=$completed_questions"
        # 使用awk进行精确计算
        avg_time_per_question=$(awk "BEGIN {printf \"%.0f\", $runtime_ms / $completed_questions}")
        echo "DEBUG: 平均时间计算完成 = $avg_time_per_question ms"
    else
        echo "DEBUG: 完成题目数量为0，跳过平均时间计算"
    fi

    # 简化时间格式，使用Unix时间戳
    echo "DEBUG: 开始计算时间字符串..."
    if [ -n "$GLOBAL_START_TIME" ]; then
        start_time_str="timestamp_$((GLOBAL_START_TIME/1000))"
        echo "DEBUG: 开始时间字符串 = '$start_time_str'"
    else
        start_time_str="timestamp_unknown"
        echo "DEBUG: 全局开始时间未知"
    fi

    if [ -n "$GLOBAL_END_TIME" ]; then
        end_time_str="timestamp_$((GLOBAL_END_TIME/1000))"
        echo "DEBUG: 结束时间字符串 = '$end_time_str'"
    else
        end_time_str="timestamp_unknown"
        echo "DEBUG: 全局结束时间未知"
    fi

    echo "DEBUG: 开始生成JSON报告文件..."
    echo "DEBUG: 目标文件 = '$report_file'"

    # 使用临时文件先写入，最后再移动
    temp_report_file="${report_file}.tmp"

    cat > "$temp_report_file" << EOF
{
  "test_summary": {
    "test_start_time": "$start_time_str",
    "test_end_time": "$end_time_str",
    "total_runtime_ms": $runtime_ms,
    "total_runtime_seconds": $(awk "BEGIN {printf \"%.2f\", $runtime_ms / 1000}"),
    "total_runtime_formatted": "$(format_duration $runtime_ms)",
    "total_power_consumption_mAh": $total_power_mah,
    "average_power_mA": $avg_power_ma
  },
  "question_metrics": {
    "total_questions_processed": $completed_questions,
    "total_questions_available": $total_questions,
    "average_time_per_question_ms": $avg_time_per_question,
    "average_time_per_question_formatted": "$(format_duration $avg_time_per_question)"
  },
  "process_statistics": {
    "total_genie_processes_launched": $process_count,
    "pids_recorded_file": "$ALL_PIDS_FILE"
  },
  "memory_analysis": $memory_stats,
  "monitoring_info": {
    "memory_log_file": "$MEMORY_LOG_DIR/system_memory.log",
    "power_logs_directory": "power_logs"
  },
  "generated_at": "$timestamp"
}
EOF

    if [ $? -eq 0 ]; then
        echo "DEBUG: JSON文件写入成功，开始移动到最终位置..."
        mv "$temp_report_file" "$report_file"
        if [ $? -eq 0 ]; then
            echo "DEBUG: 文件移动成功"
        else
            echo "DEBUG: 文件移动失败"
            return 1
        fi
    else
        echo "DEBUG: JSON文件写入失败"
        return 1
    fi

    if [ -f "$report_file" ]; then
        file_size=$(wc -c < "$report_file")
        echo "DEBUG: 最终报告文件生成成功，大小 = $file_size 字节"
    else
        echo "DEBUG: 最终报告文件不存在"
        return 1
    fi

    echo "汇总报告已生成: $report_file"
    echo "DEBUG: 退出 generate_summary_report 函数"
}

# 处理单个subject的所有问题
run_single_prompt_with_monitoring() {
    local prompt_file=$1
    local subject_key=$2

    # echo "DEBUG: 进入run_single_prompt_with_monitoring函数"
    # echo "DEBUG: 函数参数 - prompt_file = '$prompt_file'"
    # echo "DEBUG: 函数参数 - subject_key = '$subject_key'"
    # echo "开始处理科目: $subject_key (带全局监控)"

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

    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in
        -----*)
          if [ -n "$prompt" ]; then
            prompt=$(printf "%s" "$prompt" | sed -e '1{/^[[:space:]]*$/d}' -e :a -e '$!N;s/\n[[:space:]]*$/\n/;ta')

            # 输出prompt到测试文件
            printf "%s" "$prompt" > "test_abstract_algebra.txt"

            subject=$(printf "%s" "$prompt" | grep "^科目：" | sed 's/科目：//' | tr -d '\n\r')
            question_idx=$(printf "%s" "$prompt" | grep "^[0-9][0-9]*\. 问题：" | sed 's/\. 问题：.*//' | tr -d '\n\r')
            # echo "DEBUG: 函数内 - prompt 处理后 = '$prompt'"
            # echo "DEBUG: 函数内 - subject = '$subject'"
            # echo "DEBUG: 函数内 - question_idx = '$question_idx'"
            # echo "DEBUG: 函数内 - prompt_file = '$prompt_file'"
            # echo "DEBUG: 函数内 - subject_key = '$subject_key'"

            finished_count=$(cat "required_json/finished_subjects.json" | grep -o "\"${subject}_prompts\":[[:space:]]*[0-9]*" | sed 's/.*://' | tr -d ' ')
            [ -z "$finished_count" ] && finished_count=0

            if [ "$question_idx" -lt "$finished_count" ]; then
                echo "=== 跳过 Prompt #$idx (Subject: $subject, Question: $question_idx) - 已完成 $finished_count 题 ==="
                idx=$((idx + 1))
                prompt=""
                continue
            fi

            echo "=== Prompt #$idx (Subject: $subject, Question: $question_idx) ==="

            mkdir -p "result/temp/${subject}"
            temp_output="${temp_dir}/${subject}/temp_${subject}_${idx}.json"

            formatted_prompt="<|im_start|>system\n你是一个做题专家。先思考并输出解题步骤，解题完后另起一行，此行只输出答案选项，格式必须为\"答案：A\"，（A或B或C或D，单选）最后一行不要添加格式要求外的任何其他文字或字符。<|im_end|><|im_start|>user\n${prompt}<|im_end|>\n<|im_end|><|im_start|>assistant\n"
            start_timestamp=$(TZ='Asia/Shanghai' date '+%Y-%m-%d %H:%M:%S')
            # 运行模型（后台启动，以便获取PID）
            /data/local/tmp/genie-qwen2.5-3b/genie-t2t-run \
              --config "genie_config.json" \
              --prompt "$formatted_prompt" > "$temp_output" 2>&1 &
            genie_pid=$!

            # 记录PID到全局文件
            record_pid $genie_pid

            # 等待模型运行完成
            wait $genie_pid
            end_timestamp=$(TZ='Asia/Shanghai' date '+%Y-%m-%d %H:%M:%S')
            # 答案处理
            if [ -f "$temp_output" ]; then
              model_answer=$(sed -n '/\[BEGIN\]/,/\[KPIS\]/p' "$temp_output" | sed -n 'p/\[END\]/q' | sed 's/\[BEGIN\]: //;s/\[END\].*//')
              final_answer=$(echo "$model_answer" | tail -2 | sed 's/答案[:：[:space:]]*//g' | sed -n 's/\([ABCD,、 ]*\).*/\1/p' | tr -d '\n' | tr -d '\r' | sed 's/[[:space:],、]//g')
              [ -z "$final_answer" ] && final_answer="Answer Not Found"

              
              
              # 提取[KPIS]性能指标
              init_time=$(grep "Init Time:" "$temp_output" | sed 's/.*Init Time: \([0-9]*\) us.*/\1/')
              prompt_time=$(grep "Prompt Processing Time:" "$temp_output" | sed 's/.*Prompt Processing Time: \([0-9]*\) us.*/\1/')
              prompt_rate=$(grep "Prompt Processing Rate" "$temp_output" | sed 's/.*Prompt Processing Rate : \([0-9.]*\) toks\/sec.*/\1/')
              token_time=$(grep "Token Generation Time:" "$temp_output" | sed 's/.*Token Generation Time: \([0-9]*\) us.*/\1/')
              token_rate=$(grep "Token Generation Rate:" "$temp_output" | sed 's/.*Token Generation Rate: \([0-9.]*\) toks\/sec.*/\1/')


              subject_file="${temp_dir}/${subject}_answers.txt"
              echo "ANSWER_START" >> "$subject_file"
              echo "question_index:$question_idx" >> "$subject_file"
              echo "global_index:$idx" >> "$subject_file"
              echo "start_timestamp:$start_timestamp" >> "$subject_file"
              echo "final_answer:$final_answer" >> "$subject_file"
              echo "model_output:" >> "$subject_file"
              echo "$model_answer\n" >> "$subject_file"
              echo "performance_metrics:" >> "$subject_file"
              echo "init_time:$init_time" >> "$subject_file"
              echo "prompt_processing_time:$prompt_time" >> "$subject_file"
              echo "prompt_processing_rate:$prompt_rate" >> "$subject_file"
              echo "token_generation_time:$token_time" >> "$subject_file"
              echo "token_generation_rate:$token_rate" >> "$subject_file"
              echo "end_timestamp:$end_timestamp" >> "$subject_file"
              echo "ANSWER_END" >> "$subject_file"

              echo "  → processed question $question_idx for subject $subject"
            fi

            # 更新完成状态
            update_finished_progress "$subject" $((question_idx + 1))

            idx=$((idx + 1))
            prompt=""
            # echo "等待5秒手机休息..."
            # sleep 5
          fi
          ;;
        *)
          if echo "$line" | grep -q '[^[:space:]]'; then
            prompt="${prompt}${line}"$'\n'
          fi
          ;;
      esac
    done < "$prompt_file"

    processed_files=$((processed_files + 1))
    echo "完成处理科目: $subject_key"

    # # 让手机休息1分钟
    # echo "等待1分钟让手机休息..."
    # sleep 60
}

# 更新完成进度
update_finished_progress() {
    local subject=$1
    local next_question=$2
    local finished_key="${subject}_prompts"

    # echo "DEBUG: 进入update_finished_progress函数"
    # echo "DEBUG: 更新进度 - subject = '$subject'"
    # echo "DEBUG: 更新进度 - next_question = '$next_question'"
    # echo "DEBUG: 更新进度 - finished_key = '$finished_key'"

    # 使用更安全的临时文件命名
    local temp_json="/tmp/temp_json_$$$(date +%s%3N)"

    cat "required_json/finished_subjects.json" > "$temp_json"


    if grep -q "\"$finished_key\"" "$temp_json"; then
        echo "DEBUG: 找到现有key，进行更新"
        sed -i "s/\"$finished_key\":[[:space:]]*[0-9]*/\"$finished_key\": $next_question/" "$temp_json"
    else
        echo "DEBUG: 未找到现有key，进行添加"
        if [ "$(cat "$temp_json" | wc -c)" -le 3 ]; then
            echo "{\"$finished_key\": $next_question}" > "$temp_json"
        else
            sed -i "s/}$/, \"$finished_key\": $next_question}/" "$temp_json"
        fi
    fi

    # echo "DEBUG: 更新后的JSON内容："
    # cat "$temp_json"

    cat "$temp_json" > "required_json/finished_subjects.json"
    rm -f "$temp_json"
}

# 主执行逻辑
main() {
    # 计数器
    total_files=0
    processed_files=0
    skipped_files=0

    # 启动全局监控
    start_global_monitoring

    # 遍历prompts_by_subject目录下的所有*_prompts.txt文件
    for prompt_file in "$PROMPTS_DIR"/*_prompts.txt; do
        [ -f "$prompt_file" ] || continue

        total_files=$((total_files + 1))

        # 获取文件名（不含路径）
        filename=$(basename "$prompt_file")
        echo "DEBUG: filename = '$filename'"

        # 去掉_prompts.txt后缀作为subject key
        subject_key=$(basename "$filename" _prompts.txt)
        echo "DEBUG: subject_key = '$subject_key'"

        finished_subject_key="${subject_key}_prompts"
        echo "DEBUG: finished_subject_key = '$finished_subject_key'"
        echo "DEBUG: finished_subject_key length = ${#finished_subject_key}"

        total_subject_key="$subject_key"
        echo "DEBUG: total_subject_key = '$total_subject_key'"

        # 获取已完成的题目数量和总题目数量
        echo "DEBUG: 开始获取计数信息..."
        echo "DEBUG: FINISHED_FILE = $FINISHED_FILE"
        echo "DEBUG: QUESTION_COUNTS_FILE = $QUESTION_COUNTS_FILE"

        echo "DEBUG: 搜索finished_subject_key: '${finished_subject_key}'"
        finished_count=$(cat "$FINISHED_FILE" | grep -o "\"${finished_subject_key}\":[[:space:]]*[0-9]*" | sed 's/.*://' | tr -d ' ')
        echo "DEBUG: finished_count = '$finished_count'"

        echo "DEBUG: 搜索total_subject_key: '${total_subject_key}'"
        total_count=$(cat "$QUESTION_COUNTS_FILE" | grep -o "\"${total_subject_key}\":[[:space:]]*[0-9]*" | sed 's/.*://' | tr -d ' ')
        echo "DEBUG: total_count = '$total_count'"

        [ -z "$finished_count" ] && finished_count=0

        # 如果已完成数量等于总数量，跳过该科目
        if [ "$finished_count" -eq "$total_count" ]; then
            echo "跳过已完成的科目: $subject_key ($finished_count/$total_count)"
            skipped_files=$((skipped_files + 1))
            continue
        fi

        # 如果已完成数量大于等于总数量，也跳过
        if [ "$finished_count" -ge "$total_count" ]; then
            echo "科目 $subject_key 已完成 ($finished_count/$total_count)，跳过"
            skipped_files=$((skipped_files + 1))
            continue
        fi

        # 运行带监控的prompt处理
        run_single_prompt_with_monitoring "$prompt_file" "$subject_key"
    done

    # 停止全局监控并生成报告
    stop_global_monitoring

    # 转换答案文件为JSON格式
    echo "=== 开始转换答案文件为JSON格式 ==="
    convert_answers_to_json

    echo "=== 处理完成统计 ==="
    echo "总文件数: $total_files"
    echo "已处理: $processed_files"
    echo "已跳过: $skipped_files"
    echo "所有科目的prompts文件处理完成！"
}

# 错误处理
trap 'echo "脚本被中断，正在清理..."; stop_global_monitoring; exit 1' INT TERM

# 执行主函数
main "$@"