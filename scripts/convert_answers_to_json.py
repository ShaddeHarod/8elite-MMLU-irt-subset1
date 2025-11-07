#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import json
import sys
from collections import defaultdict

def convert_answers_to_json(input_file, output_file):
    """
    将answers.txt转换为JSON格式
    输入格式：subject index answer
    输出格式：{subject: {index: answer, ...}, ...}
    """
    answers = defaultdict(dict)
    
    with open(input_file, 'r', encoding='utf-8') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
                
            parts = line.split(' ')
            if len(parts) != 3:
                print(f"警告：第{line_num}行格式错误: {line}")
                continue
                
            subject, index, answer = parts
            try:
                index = int(index)
            except ValueError:
                print(f"警告：第{line_num}行索引不是数字: {line}")
                continue
                
            if answer not in ['A', 'B', 'C', 'D']:
                print(f"警告：第{line_num}行答案不在A-D范围内: {line}")
                continue
                
            answers[subject][index] = answer
    
    # 转换为普通字典以便JSON序列化
    result = {}
    for subject, subject_answers in answers.items():
        result[subject] = dict(subject_answers)
    
    # 写入JSON文件
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(result, f, ensure_ascii=False, indent=2)
    
    # 统计信息
    total_questions = sum(len(subject_answers) for subject_answers in result.values())
    print(f"转换完成:")
    print(f"  • 总科目数: {len(result)}")
    print(f"  • 总问题数: {total_questions}")
    print(f"  • 输出文件: {output_file}")
    
    # 显示各科目问题数量
    print(f"\n各科目问题数量:")
    for subject, subject_answers in sorted(result.items()):
        print(f"  • {subject}: {len(subject_answers)}题")

def main():
    if len(sys.argv) != 3:
        print("用法: python convert_answers_to_json.py input_answers.txt output_answers.json")
        sys.exit(1)
    
    input_file = sys.argv[1]
    output_file = sys.argv[2]
    
    try:
        convert_answers_to_json(input_file, output_file)
    except FileNotFoundError:
        print(f"错误：找不到文件 {input_file}")
        sys.exit(1)
    except Exception as e:
        print(f"错误：{e}")
        sys.exit(1)

if __name__ == "__main__":
    main() 