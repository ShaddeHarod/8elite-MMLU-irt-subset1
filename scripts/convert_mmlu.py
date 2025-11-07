#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import csv
import sys

def convert(input_csv, prompts_txt, answers_txt):
    with open(input_csv, newline='', encoding='utf-8') as fin, \
         open(prompts_txt, 'w', encoding='utf-8') as fp_out, \
         open(answers_txt, 'w', encoding='utf-8') as fa_out:

        reader = csv.reader(fin)
        header = next(reader)  # ['', 'Question', 'A', 'B', 'C', 'D', 'Answer', 'Subject']
        for row in reader:
            idx      = row[0].strip()
            question = row[1].strip()
            optA     = row[2].strip()
            optB     = row[3].strip()
            optC     = row[4].strip()
            optD     = row[5].strip()
            answer   = row[6].strip()
            subject  = row[7].strip()

            # 写入 prompts.txt
            fp_out.write("----------------------------------------------------------------\n")
            fp_out.write(f"科目：{subject}\n")
            fp_out.write(f"{idx}. 问题：{question} ({subject})\n")
            fp_out.write(f"A. {optA}\n")
            fp_out.write(f"B. {optB}\n")
            fp_out.write(f"C. {optC}\n")
            fp_out.write(f"D. {optD}\n")
            fp_out.write("----------------------------------------------------------------\n\n")

            # 写入 answers.txt
            fa_out.write(f"{subject} {idx} {answer}\n")

if __name__ == "__main__":
    if len(sys.argv) != 4:
        print("用法: python convert_mmlu.py mmlu_ZH-CN.csv mmlu_ZH-CN-prompts.txt mmlu_ZH-CN-answers.txt")
        sys.exit(1)
    _, input_csv, prompts_txt, answers_txt = sys.argv
    convert(input_csv, prompts_txt, answers_txt)
    print("转换完成：")
    print(f"  • Prompts → {prompts_txt}")
    print(f"  • Answers → {answers_txt}")