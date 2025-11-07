import os
import json
import glob

def count_questions_by_subject():
    """统计每个科目的题目数量"""
    # 设置文件夹路径
    ground_truth_dir = "subjects_answers_ground_truth"
    
    # 获取所有json文件
    json_files = glob.glob(os.path.join(ground_truth_dir, "*.json"))
    
    # 存储统计结果
    question_counts = {}
    
    # 遍历每个json文件
    for json_file in json_files:
        # 获取科目名（去掉.json后缀）
        subject_name = os.path.basename(json_file).replace('.json', '')
        
        try:
            # 读取json文件
            with open(json_file, 'r', encoding='utf-8') as f:
                data = json.load(f)
            
            # 统计问题数量（题号从0开始，所以总数为最大index+1）
            if isinstance(data, dict):
                max_index = max([int(k) for k in data.keys() if k.isdigit()], default=-1)
                question_count = max_index + 1 if max_index >= 0 else 0
            else:
                question_count = 0
            
            question_counts[subject_name] = question_count
            print(f"{subject_name}: {question_count} questions")
            
        except Exception as e:
            print(f"Error processing {json_file}: {str(e)}")
            question_counts[subject_name] = 0
    
    # 将结果保存到新的json文件
    output_file = "required_json/question_counts_by_subject.json"
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(question_counts, f, ensure_ascii=False, indent=2)
    
    print(f"\n统计结果已保存到: {output_file}")
    return question_counts

if __name__ == "__main__":
    count_questions_by_subject()