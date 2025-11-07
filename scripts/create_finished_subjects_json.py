import os
import json

# 定义prompts_by_subject文件夹路径
prompts_dir = "prompts_by_subject"

# 获取所有*_prompts.txt文件
prompt_files = [f for f in os.listdir(prompts_dir) if f.endswith('_prompts.txt')]

# 创建字典，key为去掉.txt后缀的文件名，value为0
finished_subjects = {}
for file in prompt_files:
    key = file.replace('.txt', '')
    finished_subjects[key] = 0

# 将字典写入finished_subjects.json文件（保存在当前工作目录）
json_path = 'required_json/finished_subjects.json'
with open(json_path, 'w', encoding='utf-8') as f:
    json.dump(finished_subjects, f, ensure_ascii=False, indent=2)

print(f"已创建 {json_path} 文件，包含 {len(finished_subjects)} 个科目")