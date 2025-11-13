#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
JSON文件model_output清理脚本
处理subjects_answers_from_model目录中的JSON文件，清理model_output字段中的换行符和多余空格
"""

import os
import re
import json
from pathlib import Path

def clean_model_output_text(text):
    """
    清理model_output字段的文本内容
    - 删除开头和结尾的换行符
    - 删除结尾的空行和空格
    - 删除所有ASCII控制字符（除了换行符和制表符）
    - 修复常见的LaTeX命令错误
    - 保留内容中间的必要换行
    """
    if not text:
        return text

    # 删除开头和结尾的所有空白字符（包括换行符、空格、制表符）
    cleaned = text.strip()

    # 删除所有ASCII控制字符（除了\n和\t），这些会导致JSON解析失败
    import string
    # 允许的控制字符：\n (10), \t (9)
    cleaned = ''.join(char for char in cleaned if ord(char) >= 32 or char in '\n\t')

    # 修复常见的LaTeX命令错误
    cleaned = cleaned.replace('\\rac', '\\\\frac')  # 修复 \rac 为 \frac
    cleaned = cleaned.replace('\\frac', '\\\\frac')  # 确保 \frac 被正确转义

    return cleaned

def fix_json_file(file_path):
    """
    修复单个JSON文件中的model_output字段
    使用正则表达式处理，避免JSON解析错误
    """
    try:
        # 读取文件内容
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()

        # 使用正则表达式匹配并清理model_output字段的内容
        # 匹配 "model_output": "... " 格式，包括可能的多行内容
        pattern = r'("model_output"\s*:\s*")([^"]*?)(")'

        def replace_match(match):
            prefix = match.group(1)
            content = match.group(2)
            suffix = match.group(3)

            # 清理内容
            cleaned_content = clean_model_output_text(content)

            # 转义JSON字符串中的特殊字符
            cleaned_content = cleaned_content.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n').replace('\r', '\\r').replace('\t', '\\t')

            return f"{prefix}{cleaned_content}{suffix}"

        # 应用替换
        fixed_content = re.sub(pattern, replace_match, content, flags=re.DOTALL)

        # 直接写入修复后的内容（不再备份原文件）
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(fixed_content)

        print(f"[OK] 已修复: {file_path.name}")

        # 验证修复后的JSON是否合法
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                json.load(f)
            print("[VALID] JSON格式验证通过")
        except json.JSONDecodeError as e:
            print(f"[INVALID] JSON格式验证失败: {e}")
            return False

        return True

    except Exception as e:
        print(f"[ERROR] 处理文件失败 {file_path.name}: {e}")
        return False

def main():
    """
    主函数：处理subjects_answers_from_model目录中的所有JSON文件
    """
    import sys
    import io

    # 设置stdout编码为UTF-8，避免Windows下的编码问题
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8')
    else:
        sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

    # 获取当前脚本所在目录
    script_dir = Path(__file__).parent
    subjects_dir = script_dir.parent / "subjects_answers_from_model"

    if not subjects_dir.exists():
        print(f"[ERROR] 错误: 找不到目录 {subjects_dir}")
        return

    print(f"[INFO] 处理目录: {subjects_dir}")
    print("=" * 50)

    # 获取所有JSON文件
    json_files = list(subjects_dir.glob("*.json"))

    if not json_files:
        print("[ERROR] 未找到任何JSON文件")
        return

    print(f"[INFO] 找到 {len(json_files)} 个JSON文件")
    print()

    success_count = 0
    total_count = len(json_files)

    # 处理每个文件
    for json_file in sorted(json_files):
        print(f"[PROCESS] 处理: {json_file.name}")
        if fix_json_file(json_file):
            success_count += 1
        print()

    print("=" * 50)
    print(f"[COMPLETE] 处理完成: {success_count}/{total_count} 个文件成功修复")

    if success_count == total_count:
        print("[SUCCESS] 所有文件都已成功修复！")
    else:
        print("[WARNING] 部分文件修复失败，请检查错误信息")

if __name__ == "__main__":
    main()