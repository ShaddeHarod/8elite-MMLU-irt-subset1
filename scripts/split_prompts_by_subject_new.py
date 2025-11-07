#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
将mmlu_ZH-CN-prompts.txt按科目分割成独立的文件
保持原始格式不变，包括问题分隔符和空行
"""

import os
import re
from collections import defaultdict

def split_prompts_by_subject(input_file_path):
    """
    按科目分割prompts文件，保持原始分隔符和空行格式
    
    Args:
        input_file_path: 输入文件路径
    """
    # 读取原始文件
    with open(input_file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # 使用正则表达式匹配每个问题块
    question_blocks = re.split(r'(\n-{40,}\n)', content)
    
    # 第一个元素可能是空字符串或文件开头内容
    if not question_blocks[0].strip():
        question_blocks = question_blocks[1:]
    
    # 重新组合问题和分隔符
    questions = []
    for i in range(0, len(question_blocks), 2):
        if i+1 < len(question_blocks):
            # 合并问题和分隔符，并规范化空行
            question = question_blocks[i].rstrip('\n') + question_blocks[i+1].rstrip('\n')
            questions.append(question)
        else:
            questions.append(question_blocks[i].rstrip('\n'))
    
    # 按科目分类问题
    subjects_content = defaultdict(list)
    current_subject = None
    
    for question in questions:
        # 提取科目信息
        subject_match = re.search(r'科目：([^\n]+)', question)
        if subject_match:
            current_subject = subject_match.group(1).strip()
            
        if current_subject:
            subjects_content[current_subject].append(question)
    
    # 创建输出目录
    output_dir = os.path.join(os.path.dirname(input_file_path), 'prompts_by_subject')
    os.makedirs(output_dir, exist_ok=True)
    
    # 为每个科目写入文件
    for subject, questions in subjects_content.items():
        # 清理文件名中的特殊字符
        safe_subject = re.sub(r'[^\w\-_.]', '_', subject)
        output_file = os.path.join(output_dir, f"{safe_subject}_prompts.txt")
        
        # 合并问题并规范化格式
        content = '\n'.join(questions)
        
        # 确保第一行是分割线
        if not content.startswith('-' * 40 + '\n'):
            content = '-' * 40 + '\n' + content
        
        # 确保最后一行是分割线
        if not content.endswith('\n' + '-' * 40):
            content = content + '\n' + '-' * 40
        
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write(content)
        
        print(f"已创建：{output_file} ({len(content)} 字符)")
    
    print(f"\n总计分割了 {len(subjects_content)} 个科目的文件")
    print(f"输出目录：{output_dir}")
    
    return subjects_content

def main():
    """主函数"""
    input_file = r"mmlu_ZH-CN-prompts.txt"
    
    if not os.path.exists(input_file):
        print(f"错误：文件 {input_file} 不存在")
        return
    
    try:
        subjects_content = split_prompts_by_subject(input_file)
        
        # 显示科目列表
        print("\n科目列表：")
        for i, subject in enumerate(sorted(subjects_content.keys()), 1):
            print(f"{i}. {subject}")
            
    except Exception as e:
        print(f"处理文件时出错：{e}")

if __name__ == "__main__":
    main()