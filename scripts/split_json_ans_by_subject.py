import json
import os

def split_mmlu_answers_by_subject():
    # 读取原始JSON文件
    input_file = 'mmlu_ZH-CN-answers.json'
    output_dir = 'subjects_answers_ground_truth'
    
    # 确保输出目录存在
    os.makedirs(output_dir, exist_ok=True)
    
    try:
        with open(input_file, 'r', encoding='utf-8') as f:
            data = json.load(f)
        
        # 遍历每个学科
        for subject_name, subject_data in data.items():
            output_file = os.path.join(output_dir, f'{subject_name}.json')
            
            with open(output_file, 'w', encoding='utf-8') as f:
                json.dump(subject_data, f, indent=2, ensure_ascii=False)
            
            print(f'已创建: {output_file}')
        
        print(f'成功分割完成，共处理了 {len(data)} 个学科')
        return True
        
    except Exception as e:
        print(f'处理过程中出现错误: {str(e)}')
        return False

if __name__ == '__main__':
    split_mmlu_answers_by_subject()