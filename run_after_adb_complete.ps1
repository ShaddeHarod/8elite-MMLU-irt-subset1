conda activate TinyBenchEnv

# 删除已存在的文件夹
if (Test-Path ".\pulled_report_logs") {
    Remove-Item -Path ".\pulled_report_logs" -Recurse -Force
}

if (Test-Path ".\subjects_answers_from_model") {
    Remove-Item -Path ".\subjects_answers_from_model" -Recurse -Force
}

if (Test-Path ".\subjects_perf_results") {
    Remove-Item -Path ".\subjects_perf_results" -Recurse -Force
}

# 1. 列出所有匹配的远端文件路径
$fileList = adb shell ls data/local/tmp/genie-qwen2.5-3b/result/*_LLM_Answer.json

# 创建目标文件夹（如果不存在）
if (-not (Test-Path ".\subjects_answers_from_model")) {
    New-Item -ItemType Directory -Path ".\subjects_answers_from_model" -Force
}

if (-not (Test-Path ".\pulled_report_logs")) {
    New-Item -ItemType Directory -Path ".\pulled_report_logs" -Force
}

# 2. 遍历每个远端路径并 pull 到本地
foreach ($remotePath in $fileList) {
    # 去除首尾空白，并提取文件名
    $remotePath = $remotePath.Trim()
    $fileName   = [System.IO.Path]::GetFileName($remotePath)
    # 拉取到目标文件夹（路径中含空格时用双引号）
    adb pull $remotePath ".\subjects_answers_from_model\$fileName"
}
adb pull /data/local/tmp/genie-qwen2.5-3b/result/POWER_MEM_TEMPERATURE_REPORT.json .\pulled_report_logs
adb pull /data/local/tmp/genie-qwen2.5-3b/memory_logs/system_memory.log .\pulled_report_logs


python scripts/fix_json_model_output.py
python scripts/analyze_llm_results.py