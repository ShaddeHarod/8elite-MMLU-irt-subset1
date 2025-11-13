import json
import os
import re
import traceback
from pathlib import Path
import statistics
import csv

def robust_json_load(file_path):
    """使用多种方法尝试加载可能损坏的JSON文件"""
    
    # 方法1：直接尝试加载
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            return json.load(f)
    except (json.JSONDecodeError, UnicodeDecodeError) as e:
        print(f"直接加载失败: {e}")
    
    # 方法2：忽略编码错误
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
            return json.loads(content)
    except json.JSONDecodeError as e:
        print(f"忽略编码错误加载失败: {e}")
    
    # 方法3：改进的控制字符和引号处理
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()

        # 修复model_output字段中的换行符问题
        # 找到"model_output": "后面的内容，直到遇到真正的结束引号
        model_output_pattern = r'"model_output"\s*:\s*"([^"]*(?:\n[^"]*)*)"'

        def fix_model_output(match):
            raw_content = match.group(1)
            # 将换行符转换为转义的\n
            escaped_content = raw_content.replace('\n', '\\n').replace('\r', '\\r').replace('\t', '\\t')
            # 确保其他特殊字符也被正确转义
            escaped_content = escaped_content.replace('\\', '\\\\')
            return f'"model_output": "{escaped_content}"'

        content = re.sub(model_output_pattern, fix_model_output, content, flags=re.DOTALL)

        # 移除其他控制字符
        content = re.sub(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]', '', content)

        return json.loads(content)
    except json.JSONDecodeError as e:
        print(f"改进方法加载失败: {e}")
    
    # 方法4：逐行修复
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()
        
        # 清理每行
        cleaned_lines = []
        for line in lines:
            line = re.sub(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]', '', line)
            line = line.strip()
            if line:
                cleaned_lines.append(line)
        
        # 尝试重新组合
        content = '\n'.join(cleaned_lines)
        return json.loads(content)
    except json.JSONDecodeError as e:
        print(f"逐行修复后加载失败: {e}")
    
    # 方法5：使用正则表达式提取关键部分
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
        
        # 尝试提取subject
        subject_match = re.search(r'"subject"\s*:\s*"([^"]+)"', content)
        subject = subject_match.group(1) if subject_match else "unknown"
        
        # 尝试提取answers数组
        answers_match = re.search(r'"answers"\s*:\s*\[(.*?)\](?=\s*[,}])', content, re.DOTALL)
        if answers_match:
            answers_str = answers_match.group(1)
            
            # 尝试解析每个answer对象
            answer_pattern = r'\{\s*"question_index"\s*:\s*(\d+)\s*,\s*"final_answer"\s*:\s*"([^"]*)"[^}]*"performance_metrics"\s*:\s*\{[^}]*"prompt_processing_rate_toks_per_sec"\s*:\s*([\d.]+)[^}]*"token_generation_rate_toks_per_sec"\s*:\s*([\d.]+)[^}]*\}'
            matches = re.findall(answer_pattern, answers_str, re.DOTALL)
            
            if matches:
                answers = []
                for match in matches:
                    try:
                        answers.append({
                            "question_index": int(match[0]),
                            "final_answer": match[1],
                            "performance_metrics": {
                                "prompt_processing_rate_toks_per_sec": float(match[2]),
                                "token_generation_rate_toks_per_sec": float(match[3])
                            }
                        })
                    except (ValueError, IndexError):
                        continue
                
                return {"subject": subject, "answers": answers}
    
    except Exception as e:
        print(f"正则表达式提取失败: {e}")
    
    # 方法6：使用更激进的清理方法
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
        
        # 移除所有控制字符
        content = ''.join(char for char in content if ord(char) >= 32 or char in '\t\n\r')
        
        # 修复LaTeX转义字符
        content = content.replace('\\(', '\\\\(').replace('\\)', '\\\\)')
        content = content.replace('\\[', '\\\\[').replace('\\]', '\\\\]')
        content = content.replace('\\{', '\\\\{').replace('\\}', '\\\\}')
        
        # 修复双反斜杠
        content = re.sub(r'(?<!\\)\\(?!\\)', '\\\\', content)
        
        # 修复引号内的转义
        content = re.sub(r'"([^"]*)\\([^\\"])"', r'"\1\\\\\2"', content)
        
        return json.loads(content)
    except json.JSONDecodeError as e:
        print(f"激进清理方法失败: {e}")
    
    # 方法7：逐字符修复
    try:
        with open(file_path, 'rb') as f:
            raw_data = f.read()
        
        # 尝试不同的编码
        for encoding in ['utf-8', 'gbk', 'gb2312', 'latin1']:
            try:
                content = raw_data.decode(encoding)
                break
            except UnicodeDecodeError:
                continue
        else:
            content = raw_data.decode('utf-8', errors='ignore')
        
        # 使用json5库作为最后手段（如果可用）
        try:
            import json5
            return json5.loads(content)
        except ImportError:
            pass
        
        # 手动构建数据
        lines = content.split('\n')
        answers = []
        
        current_answer = {}
        for line in lines:
            line = line.strip()
            if '"question_index"' in line:
                if current_answer:
                    answers.append(current_answer)
                current_answer = {}
                match = re.search(r':\s*(\d+)', line)
                if match:
                    current_answer['question_index'] = int(match.group(1))
            elif '"final_answer"' in line and current_answer:
                match = re.search(r':\s*"([^"]*)"', line)
                if match:
                    current_answer['final_answer'] = match.group(1)
            elif '"prompt_processing_rate_toks_per_sec"' in line and current_answer:
                if 'performance_metrics' not in current_answer:
                    current_answer['performance_metrics'] = {}
                match = re.search(r':\s*([\d.]+)', line)
                if match:
                    current_answer['performance_metrics']['prompt_processing_rate_toks_per_sec'] = float(match.group(1))
            elif '"token_generation_rate_toks_per_sec"' in line and current_answer:
                if 'performance_metrics' not in current_answer:
                    current_answer['performance_metrics'] = {}
                match = re.search(r':\s*([\d.]+)', line)
                if match:
                    current_answer['performance_metrics']['token_generation_rate_toks_per_sec'] = float(match.group(1))
        
        if current_answer:
            answers.append(current_answer)
        
        # 提取subject
        subject_match = re.search(r'"subject"\s*:\s*"([^"]+)"', content)
        subject = subject_match.group(1) if subject_match else "unknown"
        
        return {"subject": subject, "answers": answers}
    
    except Exception as e:
        print(f"最终手动修复方法失败: {e}")
    
    raise ValueError(f"无法解析JSON文件: {file_path}")

def calculate_subject_equal_weight_accuracy(all_subjects_results):
    """
    计算subject_equal_weight准确率：每个学科权重相等
    """
    if not all_subjects_results:
        return 0.0

    total_accuracy = 0.0
    subject_count = 0

    for result in all_subjects_results:
        if 'accuracy_rate' in result and result['total_questions'] > 0:
            total_accuracy += result['accuracy_rate']
            subject_count += 1

    if subject_count == 0:
        return 0.0

    return round(total_accuracy / subject_count, 4)

def analyze_power_memory_report(base_dir):
    """
    分析功耗内存报告
    """
    power_mem_report_path = os.path.join(base_dir, "pulled_report_logs", "POWER_MEM_TEMPERATURE_REPORT.json")

    if not os.path.exists(power_mem_report_path):
        print(f"警告：功耗内存报告文件不存在: {power_mem_report_path}")
        return None

    try:
        with open(power_mem_report_path, 'r', encoding='utf-8') as f:
            report_data = json.load(f)

        # 提取关键信息
        analysis = {
            "llm_test_start_time": report_data.get("llm_test_start_time", ""),
            "llm_test_end_time": report_data.get("llm_test_end_time", ""),
            "soc_consumption_mah": report_data.get("genie_net_power", {}).get("soc_consumption_mah", 0.0),
            "soc_average_power_ma": report_data.get("genie_net_power", {}).get("soc_average_power_ma", 0.0),
            "soc_power_per_inference_mah": report_data.get("genie_net_power", {}).get("soc_power_per_inference_mah", 0.0),
            "average_time_per_question_ms": report_data.get("performance_metrics", {}).get("average_time_per_question_ms", 0),
            "test_duration_ms": report_data.get("llm_test", {}).get("duration_ms", 0),
            "generated_at": report_data.get("generated_at", ""),

            # 内存信息转换为MB
            "baseline_mem_mb": round(report_data.get("memory_analysis", {}).get("baseline_mem_kb", 0) / 1024, 2),
            "peak_mem_mb": round(report_data.get("memory_analysis", {}).get("peak_mem_kb", 0) / 1024, 2),
            "model_mem_mb": round(report_data.get("memory_analysis", {}).get("model_memory_kb", 0) / 1024, 2),

            # 温度信息
            "llm_temperature": report_data.get("llm_test", {}).get("component_temperature", {}),
            "baseline_temperature": report_data.get("baseline_test", {}).get("component_temperature", {}),

            # 测试环境信息
            "test_environment": report_data.get("test_environment", {})
        }

        return analysis

    except Exception as e:
        print(f"分析功耗内存报告时出错: {e}")
        return None

def display_temperature_info(power_mem_analysis):
    """
    显示温度信息
    """
    if not power_mem_analysis:
        print("\n温度信息：无数据")
        return

    llm_temp = power_mem_analysis.get('llm_temperature', {})
    baseline_temp = power_mem_analysis.get('baseline_temperature', {})

    if not llm_temp and not baseline_temp:
        print("\n温度信息：无数据")
        return

    print(f"\n=== 温度信息 ===")

    # 定义组件中文名称
    component_names = {
        'battery': '电池',
        'cpu-0': 'CPU-0集群',
        'cpu-1': 'CPU-1集群',
        'cpuss': 'CPU子系统',
        'ddr': 'DDR内存',
        'gpuss': 'GPU子系统',
        'nsphmx': 'NPU高性能部分',
        'nsphvx': 'NPU向量处理单元',
        'shell_back': '设备背面',
        'shell_frame': '设备边框',
        'shell_front': '设备正面'
    }

    components = ['battery', 'cpu-0', 'cpu-1', 'cpuss', 'ddr', 'gpuss', 'nsphmx', 'nsphvx', 'shell_back', 'shell_frame', 'shell_front']

    print(f"{'组件':<15} {'基线开始':<10} {'基线结束':<10} {'LLM开始':<10} {'LLM结束':<10} {'LLM温升':<10}")
    print("-" * 70)

    for component in components:
        comp_name = component_names.get(component, component)

        # 获取温度值
        baseline_start = baseline_temp.get(component, {}).get('start_temperature', 0)
        baseline_end = baseline_temp.get(component, {}).get('end_temperature', 0)
        llm_start = llm_temp.get(component, {}).get('start_temperature', 0)
        llm_end = llm_temp.get(component, {}).get('end_temperature', 0)

        # 计算LLM测试期间的温升
        temp_rise = llm_end - llm_start if llm_start > 0 and llm_end > 0 else 0

        print(f"{comp_name:<15} {baseline_start:<10} {baseline_end:<10} {llm_start:<10} {llm_end:<10} {temp_rise:<10}")

def append_or_create_csv(csv_path, headers_dict, csv_data):
    """
    创建新的CSV文件或在现有文件中添加新列
    """
    # 生成新的列数据
    new_rows = {}
    for key, header_name in headers_dict.items():
        value = csv_data.get(key, '')
        new_rows[header_name] = value

    if os.path.exists(csv_path):
        # 文件存在，读取现有数据并按指标名称匹配
        existing_data = []
        try:
            with open(csv_path, 'r', encoding='utf-8-sig') as f:
                reader = csv.reader(f)
                existing_data = list(reader)
        except Exception as e:
            print(f"读取现有CSV文件失败，将创建新文件: {e}")
            existing_data = []

        # 验证文件格式并建立指标名称映射
        if len(existing_data) > 1:
            # 创建指标名称到行索引的映射（跳过表头行）
            metric_to_row = {}
            for i, row in enumerate(existing_data[1:], 1):  # 从第1行开始（跳过表头）
                if len(row) > 0 and row[0].strip():  # 确保有指标名称
                    metric_to_row[row[0].strip()] = i

            # 确定当前列数
            current_cols = len(existing_data[0]) if existing_data else 0

            # 为每个新指标添加数据，直接追加到现有列后面
            for header_name, value in new_rows.items():
                if header_name in metric_to_row:
                    # 找到对应行，直接添加新值到末尾
                    row_idx = metric_to_row[header_name]
                    existing_data[row_idx].append(str(value))
                else:
                    # 新指标，添加新行
                    new_row = [header_name]
                    # 填充前面的空列，与现有行保持相同列数-1
                    while len(new_row) < len(existing_data[0]) - 1:
                        new_row.append('')
                    new_row.append(str(value))
                    existing_data.append(new_row)

            # 确保表头行的列数与数据行保持一致
            max_cols = max(len(row) for row in existing_data) if existing_data else 0
            while len(existing_data[0]) < max_cols:
                existing_data[0].append('')

            # 写回文件
            with open(csv_path, 'w', encoding='utf-8-sig', newline='') as f:
                writer = csv.writer(f)
                writer.writerows(existing_data)
        else:
            # 现有文件格式错误，重新创建
            print(f"现有CSV文件格式不正确，重新创建文件: {csv_path}")
            create_new_csv(csv_path, new_rows)
    else:
        # 文件不存在，创建新文件
        create_new_csv(csv_path, new_rows)

def create_new_csv(csv_path, new_rows):
    """
    创建新的CSV文件
    """
    with open(csv_path, 'w', encoding='utf-8-sig', newline='') as f:
        writer = csv.writer(f)
        # 根据文件路径判断是中文还是英文版
        if 'chinese' in csv_path:
            writer.writerow(['属性名称', '数值'])
        else:
            writer.writerow(['Metric', 'Value'])

        for header_name, value in new_rows.items():
            writer.writerow([header_name, str(value)])

def generate_final_csv_report(all_subjects_results, power_mem_analysis, analysis_results_dir):
    """
    生成最终的CSV报告
    """
    if not all_subjects_results or not power_mem_analysis:
        print("警告：缺少必要的数据，无法生成最终报告")
        return

    # 计算两种准确率
    total_questions = sum(r['total_questions'] for r in all_subjects_results)
    total_correct = sum(r['correct_count'] for r in all_subjects_results)
    question_equal_weight_accuracy = round(total_correct / total_questions, 4) if total_questions > 0 else 0.0
    subject_equal_weight_accuracy = calculate_subject_equal_weight_accuracy(all_subjects_results)

    # 收集所有性能指标进行平均计算
    all_init_times = []
    all_prompt_processing_times = []
    all_token_generation_rates = []

    for result in all_subjects_results:
        if 'detailed_metrics' in result:
            metrics = result['detailed_metrics']
            if 'init_time_us' in metrics and metrics['init_time_us']:
                all_init_times.extend(metrics['init_time_us'])
            if 'prompt_processing_time_us' in metrics and metrics['prompt_processing_time_us']:
                all_prompt_processing_times.extend(metrics['prompt_processing_time_us'])
            if 'token_generation_rate_toks_per_sec' in metrics and metrics['token_generation_rate_toks_per_sec']:
                all_token_generation_rates.extend(metrics['token_generation_rate_toks_per_sec'])

    # 计算平均性能指标
    avg_init_time_us = statistics.mean(all_init_times) if all_init_times else 0.0
    avg_prompt_processing_time_us = statistics.mean(all_prompt_processing_times) if all_prompt_processing_times else 0.0
    avg_token_generation_rate = statistics.mean(all_token_generation_rates) if all_token_generation_rates else 0.0

    # 计算first token时长
    general_first_token_time = avg_init_time_us + avg_prompt_processing_time_us
    first_token_time = avg_prompt_processing_time_us

    # 构建CSV数据行
    test_env = power_mem_analysis.get('test_environment', {})
    csv_data = {
        # 测试环境信息
        'device_info': test_env.get('device_info', ''),
        'android_version': test_env.get('android_version', ''),
        'real_ram_size_gb': test_env.get('real_ram_size', ''),
        'soc_chip': test_env.get('soc_chip', ''),

        # 准确率信息
        'question_equal_weight_accuracy_percent': f"{question_equal_weight_accuracy * 100:.2f}%",
        'subject_equal_weight_accuracy_percent': f"{subject_equal_weight_accuracy * 100:.2f}%",

        # 内存信息
        'baseline_memory_mb': power_mem_analysis.get('baseline_mem_mb', 0),
        'peak_memory_mb': power_mem_analysis.get('peak_mem_mb', 0),
        'model_memory_mb': power_mem_analysis.get('model_mem_mb', 0),

        # 功耗信息
        'soc_consumption_mah': power_mem_analysis.get('soc_consumption_mah', 0),
        'soc_average_power_ma': power_mem_analysis.get('soc_average_power_ma', 0),
        'soc_power_per_inference_mah': power_mem_analysis.get('soc_power_per_inference_mah', 0),

        # 性能指标
        'average_token_throughput_toks_per_sec': round(avg_token_generation_rate, 3),
        'general_first_token_time_us': round(general_first_token_time, 0),
        'first_token_time_us': round(first_token_time, 0),
        'average_time_per_question_ms': power_mem_analysis.get('average_time_per_question_ms', 0),

        # 时间信息
        'test_start_time': power_mem_analysis.get('llm_test_start_time', ''),
        'test_end_time': power_mem_analysis.get('llm_test_end_time', ''),
        'test_duration_ms': power_mem_analysis.get('test_duration_ms', 0),
        'report_generated_at': power_mem_analysis.get('generated_at', '')
    }

    # 定义中文和英文的表头映射
    chinese_headers = {
        'device_info': '设备信息',
        'android_version': 'Android版本',
        'real_ram_size_gb': 'RAM大小(GB)',
        'soc_chip': 'SoC芯片',
        'question_equal_weight_accuracy_percent': '题目等权重准确率(%)',
        'subject_equal_weight_accuracy_percent': '学科等权重准确率(%)',
        'baseline_memory_mb': '基线内存(MB)',
        'peak_memory_mb': '峰值内存(MB)',
        'model_memory_mb': '模型内存(MB)',
        'soc_consumption_mah': 'SoC耗电量(mAh)',
        'soc_average_power_ma': 'SoC平均功耗(mA)',
        'soc_power_per_inference_mah': '单次推理耗电量(mAh)',
        'average_token_throughput_toks_per_sec': '平均Token吞吐率(个/秒)',
        'general_first_token_time_us': '通用首Token时间(微秒)',
        'first_token_time_us': '首Token时间(微秒)',
        'average_time_per_question_ms': '每题平均时间(毫秒)',
        'test_start_time': '测试开始时间',
        'test_end_time': '测试结束时间',
        'test_duration_ms': '测试时长(毫秒)',
        'report_generated_at': '报告生成时间'
    }

    english_headers = {
        'device_info': 'Device Info',
        'android_version': 'Android Version',
        'real_ram_size_gb': 'RAM Size (GB)',
        'soc_chip': 'SoC Chip',
        'question_equal_weight_accuracy_percent': 'Question Equal Weight Accuracy (%)',
        'subject_equal_weight_accuracy_percent': 'Subject Equal Weight Accuracy (%)',
        'baseline_memory_mb': 'Baseline Memory (MB)',
        'peak_memory_mb': 'Peak Memory (MB)',
        'model_memory_mb': 'Model Memory (MB)',
        'soc_consumption_mah': 'SoC Consumption (mAh)',
        'soc_average_power_ma': 'SoC Average Power (mA)',
        'soc_power_per_inference_mah': 'Power Per Inference (mAh)',
        'average_token_throughput_toks_per_sec': 'Average Token Throughput (tokens/sec)',
        'general_first_token_time_us': 'General First Token Time (μs)',
        'first_token_time_us': 'First Token Time (μs)',
        'average_time_per_question_ms': 'Average Time Per Question (ms)',
        'test_start_time': 'Test Start Time',
        'test_end_time': 'Test End Time',
        'test_duration_ms': 'Test Duration (ms)',
        'report_generated_at': 'Report Generated At'
    }

    # 创建中文和英文CSV文件
    chinese_csv_path = os.path.join(analysis_results_dir, "final_result_chinese.csv")
    english_csv_path = os.path.join(analysis_results_dir, "final_result_english.csv")

    try:
        # 生成中文版CSV（追加列或创建新文件）
        append_or_create_csv(chinese_csv_path, chinese_headers, csv_data)

        # 生成英文版CSV（追加列或创建新文件）
        append_or_create_csv(english_csv_path, english_headers, csv_data)

        print(f"中文CSV报告已生成: {chinese_csv_path}")
        print(f"英文CSV报告已生成: {english_csv_path}")

        # 打印汇总信息
        print(f"\n=== 测试结果汇总 ===")
        print(f"设备: {test_env.get('device_info', 'N/A')}")
        print(f"题目等权重准确率: {question_equal_weight_accuracy * 100:.2f}%")
        print(f"学科等权重准确率: {subject_equal_weight_accuracy * 100:.2f}%")
        print(f"SoC耗电量: {power_mem_analysis.get('soc_consumption_mah', 0):.3f} mAh")
        print(f"SoC平均功耗: {power_mem_analysis.get('soc_average_power_ma', 0):.3f} mA")
        # 计算模型运行时的峰值内存（峰值内存 - 基线内存）
        peak_model_memory = power_mem_analysis.get('peak_mem_mb', 0) - power_mem_analysis.get('baseline_mem_mb', 0)
        print(f"峰值内存占用: {peak_model_memory:.2f} MB")
        print(f"通用First Token时长: {general_first_token_time:.0f} 微秒")
        print(f"First Token时长: {first_token_time:.0f} 微秒")
        print(f"平均Token吞吐率: {avg_token_generation_rate:.3f} 个/秒")

        # 显示温度信息
        display_temperature_info(power_mem_analysis)

    except Exception as e:
        print(f"生成CSV报告时出错: {e}")

def analyze_subject_results(llm_file_path, ground_truth_path):
    """分析单个学科的结果"""
    
    try:
        # 读取LLM结果
        llm_data = robust_json_load(llm_file_path)
        
        # 验证必要字段
        if 'subject' not in llm_data:
            raise ValueError("LLM结果中缺少'subject'字段")
        if 'answers' not in llm_data:
            raise ValueError("LLM结果中缺少'answers'字段")
        
        subject = llm_data['subject']
        answers = llm_data['answers']
        
        if not isinstance(answers, list):
            raise ValueError("'answers'字段应该是列表类型")
        
        # 读取真实答案
        ground_truth_file = os.path.join(ground_truth_path, f"{subject}.json")
        if not os.path.exists(ground_truth_file):
            raise ValueError(f"找不到真实答案文件: {ground_truth_file}")
        
        ground_truth = robust_json_load(ground_truth_file)
        
        # 初始化统计变量
        total_questions = len(answers)
        correct_count = 0
        wrong_count = 0
        answer_not_found_count = 0
        answer_not_found_indices = []

        # 新增：收集5个性能指标
        init_times = []
        prompt_processing_times = []
        prompt_processing_rates = []
        token_generation_times = []
        token_generation_rates = []

        # 保留原有的指标用于兼容性
        old_prompt_processing_rates = []
        old_token_generation_rates = []
        
        # 处理每个答案
        for i, answer_data in enumerate(answers):
            try:
                question_index = str(answer_data.get('question_index', i))
                final_answer = str(answer_data.get('final_answer', ''))
                
                # 收集性能指标
                if 'performance_metrics' in answer_data and isinstance(answer_data['performance_metrics'], dict):
                    metrics = answer_data['performance_metrics']

                    # 新增5个指标的收集
                    init_time = float(metrics.get('init_time_us', 0))
                    prompt_processing_time = float(metrics.get('prompt_processing_time_us', 0))
                    prompt_rate = float(metrics.get('prompt_processing_rate_toks_per_sec', 0))
                    token_generation_time = float(metrics.get('token_generation_time_us', 0))
                    token_rate = float(metrics.get('token_generation_rate_toks_per_sec', 0))

                    if init_time > 0:
                        init_times.append(init_time)
                    if prompt_processing_time > 0:
                        prompt_processing_times.append(prompt_processing_time)
                    if prompt_rate > 0:
                        prompt_processing_rates.append(prompt_rate)
                    if token_generation_time > 0:
                        token_generation_times.append(token_generation_time)
                    if token_rate > 0:
                        token_generation_rates.append(token_rate)

                    # 保留原有逻辑
                    if prompt_rate > 0:
                        old_prompt_processing_rates.append(prompt_rate)
                    if token_rate > 0:
                        old_token_generation_rates.append(token_rate)
                
                # 检查是否为"Answer Not Found"
                if final_answer.strip() == "Answer Not Found":
                    answer_not_found_count += 1
                    answer_not_found_indices.append(int(question_index))
                    wrong_count += 1
                    continue
                
                # 获取真实答案并对比
                true_answer = ground_truth.get(question_index)
                if true_answer is None:
                    print(f"警告：在{subject}中找不到问题{question_index}的真实答案")
                    wrong_count += 1
                    continue
                
                # 标准化答案比较（忽略大小写和空格）
                normalized_llm = final_answer.strip().upper()
                normalized_truth = str(true_answer).strip().upper()
                
                if normalized_llm == normalized_truth:
                    correct_count += 1
                else:
                    wrong_count += 1
                    
            except Exception as e:
                print(f"处理问题{i}时出错: {e}")
                wrong_count += 1
                continue
        
        # 计算平均性能指标
        avg_prompt_processing_rate = statistics.mean(old_prompt_processing_rates) if old_prompt_processing_rates else 0.0
        avg_token_generation_rate = statistics.mean(old_token_generation_rates) if old_token_generation_rates else 0.0

        # 新增：计算5个指标的统计数据
        detailed_metrics = {}
        if init_times:
            detailed_metrics['init_time_us'] = init_times
        if prompt_processing_times:
            detailed_metrics['prompt_processing_time_us'] = prompt_processing_times
        if prompt_processing_rates:
            detailed_metrics['prompt_processing_rate_toks_per_sec'] = prompt_processing_rates
        if token_generation_times:
            detailed_metrics['token_generation_time_us'] = token_generation_times
        if token_generation_rates:
            detailed_metrics['token_generation_rate_toks_per_sec'] = token_generation_rates
        
        # 构建结果
        result = {
            "subject": subject,
            "total_questions": total_questions,
            "correct_count": correct_count,
            "wrong_count": wrong_count,
            "accuracy_rate": round(correct_count / total_questions, 4) if total_questions > 0 else 0.0,
            "answer_not_found": {
                "count": answer_not_found_count,
                "question_indices": sorted(answer_not_found_indices)
            },
            "performance_metrics": {
                "avg_prompt_processing_rate_toks_per_sec": round(avg_prompt_processing_rate, 3),
                "avg_token_generation_rate_toks_per_sec": round(avg_token_generation_rate, 3),
                "total_processed_answers": len(old_prompt_processing_rates)
            },

            # 新增：详细性能指标数据
            "detailed_metrics": detailed_metrics
        }
        
        return result
        
    except Exception as e:
        print(f"分析文件 {llm_file_path} 时发生错误: {e}")
        traceback.print_exc()
        raise

def main():
    """主函数"""

    # 设置路径
    script_dir = os.path.dirname(os.path.abspath(__file__))
    base_dir = os.path.join(script_dir, "..")
    llm_answers_dir = os.path.join(base_dir, "subjects_answers_from_model")
    ground_truth_dir = os.path.join(base_dir, "subjects_answers_ground_truth")
    output_dir = os.path.join(base_dir, "subjects_perf_results")
    analysis_results_dir = os.path.join(base_dir, "analysis_results")

    # 创建analysis_results文件夹（如果不存在）
    os.makedirs(analysis_results_dir, exist_ok=True)
    
    # 验证目录存在
    if not os.path.exists(llm_answers_dir):
        print(f"错误：LLM答案目录不存在: {llm_answers_dir}")
        return
    
    if not os.path.exists(ground_truth_dir):
        print(f"错误：真实答案目录不存在: {ground_truth_dir}")
        return
    
    # 创建输出目录
    os.makedirs(output_dir, exist_ok=True)
    
    # 获取所有LLM答案文件
    llm_files = [f for f in os.listdir(llm_answers_dir) 
                if f.endswith('_LLM_Answer.json') and os.path.isfile(os.path.join(llm_answers_dir, f))]
    
    if not llm_files:
        print("警告：未找到任何LLM答案文件")
        return
    
    print(f"找到 {len(llm_files)} 个学科的结果文件，开始分析...")
    
    # 统计处理结果
    processed_count = 0
    failed_count = 0
    failed_files = []

    # 存储所有学科的结果用于最终分析
    all_subjects_results = []

    # 处理每个学科
    for llm_file in llm_files:
        llm_file_path = os.path.join(llm_answers_dir, llm_file)
        
        try:
            print(f"正在处理: {llm_file}")
            
            # 分析结果
            result = analyze_subject_results(llm_file_path, ground_truth_dir)
            
            # 保存结果
            output_file = os.path.join(output_dir, f"{result['subject']}_perf.json")
            with open(output_file, 'w', encoding='utf-8') as f:
                json.dump(result, f, ensure_ascii=False, indent=2)
            
            print(f"已处理 {result['subject']}: 总题数={result['total_questions']}, "
                  f"正确={result['correct_count']}, 错误={result['wrong_count']}, "
                  f"准确率={result['accuracy_rate']:.2%}")

            if result['answer_not_found']['count'] > 0:
                print(f"  - Answer Not Found: {result['answer_not_found']['count']} 题, "
                      f"题号: {result['answer_not_found']['question_indices']}")

            # 将结果添加到总列表中
            all_subjects_results.append(result)

            processed_count += 1
            
        except Exception as e:
            print(f"处理 {llm_file} 时出错: {str(e)}")
            failed_count += 1
            failed_files.append(llm_file)
            continue
    
    # 分析功耗内存报告
    print(f"\n正在分析功耗内存报告...")
    power_mem_analysis = analyze_power_memory_report(base_dir)

    if power_mem_analysis:
        print(f"功耗内存报告分析完成")
    else:
        print(f"功耗内存报告分析失败")

    # 生成最终CSV报告
    print(f"\n正在生成最终CSV报告...")
    if all_subjects_results and power_mem_analysis:
        generate_final_csv_report(all_subjects_results, power_mem_analysis, analysis_results_dir)
    else:
        print(f"警告：缺少必要数据，跳过CSV报告生成")

    # 输出总结
    print(f"\n{'='*50}")
    print(f"处理完成！")
    print(f"成功处理: {processed_count} 个学科")
    print(f"处理失败: {failed_count} 个学科")

    if failed_files:
        print(f"失败的文件: {', '.join(failed_files)}")

    print(f"学科详细结果已保存到: {output_dir}")
    print(f"最终汇总报告已保存到: {analysis_results_dir}")

if __name__ == "__main__":
    main()