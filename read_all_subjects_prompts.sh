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

# 启动内存监控
start_memory_monitoring() {
    echo "=== 启动内存监控 ==="

    # 记录全局开始时间
    GLOBAL_START_TIME=$(date +%s%3N)
    echo "测试开始时间: $(TZ='Asia/Shanghai' date '+%Y-%m-%d %H:%M:%S')"

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

# 停止内存监控
stop_memory_monitoring() {
    echo "=== 停止内存监控 ==="

    # 记录全局结束时间
    GLOBAL_END_TIME=$(date +%s%3N)
    echo "测试结束时间: $(TZ='Asia/Shanghai' date '+%Y-%m-%d %H:%M:%S')"

    # 停止系统内存监控
    [ -n "$SYSTEM_MEMORY_PID" ] && kill $SYSTEM_MEMORY_PID 2>/dev/null

    # 计算总运行时间
    if [ -n "$GLOBAL_START_TIME" ] && [ -n "$GLOBAL_END_TIME" ]; then
        total_runtime_ms=$((GLOBAL_END_TIME - GLOBAL_START_TIME))
        total_runtime_seconds=$((total_runtime_ms / 1000))
        echo "总运行时间: ${total_runtime_seconds} 秒 (${total_runtime_ms} 毫秒)"

        # 输出关键信息供外层脚本使用
        echo "TEST_RUNTIME_MS=$total_runtime_ms"
        echo "TEST_RUNTIME_SECONDS=$total_runtime_seconds"
    fi
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


# 处理单个subject的所有问题
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

    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in
        -----*)
          if [ -n "$prompt" ]; then
            prompt=$(printf "%s" "$prompt" | sed -e '1{/^[[:space:]]*$/d}' -e :a -e '$!N;s/\n[[:space:]]*$/\n/;ta')

            # 输出prompt到测试文件
            printf "%s" "$prompt" > "test_abstract_algebra.txt"

            subject=$(printf "%s" "$prompt" | grep "^科目：" | sed 's/科目：//' | tr -d '\n\r')
            question_idx=$(printf "%s" "$prompt" | grep "^[0-9][0-9]*\. 问题：" | sed 's/\. 问题：.*//' | tr -d '\n\r')


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



    # 使用更安全的临时文件命名
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

# 主执行逻辑
main() {
    # 计数器
    total_files=0
    processed_files=0
    skipped_files=0

    # 启动内存监控
    start_memory_monitoring

    # 遍历prompts_by_subject目录下的所有*_prompts.txt文件
    for prompt_file in "$PROMPTS_DIR"/*_prompts.txt; do
        [ -f "$prompt_file" ] || continue

        total_files=$((total_files + 1))

        # 获取文件名（不含路径）
        filename=$(basename "$prompt_file")


        # 去掉_prompts.txt后缀作为subject key
        subject_key=$(basename "$filename" _prompts.txt)


        finished_subject_key="${subject_key}_prompts"


        total_subject_key="$subject_key"


        # 获取已完成的题目数量和总题目数量

        finished_count=$(cat "$FINISHED_FILE" | grep -o "\"${finished_subject_key}\":[[:space:]]*[0-9]*" | sed 's/.*://' | tr -d ' ')



        total_count=$(cat "$QUESTION_COUNTS_FILE" | grep -o "\"${total_subject_key}\":[[:space:]]*[0-9]*" | sed 's/.*://' | tr -d ' ')


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

    # 停止内存监控
    stop_memory_monitoring

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
trap 'echo "脚本被中断，正在清理..."; stop_memory_monitoring; exit 1' INT TERM

# 执行主函数
main "$@"