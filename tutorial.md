先启动powershell的conda环境，建议用这个：

``` bash
conda activate TinyBenchEnv
```



1. csv【ID、Question、A、B、C、D、Answer、Subject】转化为prompt.txt和answer.txt，方便adb读取与对比答案，用` convert_mmlu.py`

```bash
python scripts/convert_mmlu.py mmlu_ZH-CN_subset1_bucket_renumbered.csv mmlu_ZH-CN-prompts.txt mmlu_ZH-CN-answers.txt
```

2. 对于` mmlu_ZH-CN-answers.txt`，变为json（` mmlu_ZH-CN-answers.json`）,之后再把json内容分学科放到` subjects_answers_ground_truth`文件夹中

``` bash
 python scripts/convert_answers_to_json.py mmlu_ZH-CN-answers.txt mmlu_ZH-CN-answers.json
```

3. 对于` mmlu_ZH-CN-prompts`, 转化为` prompts_by_subject` 文件夹中的分学科的txt：

``` bash
python scripts/split_prompts_by_subject_new.py
```

4. 把ans.json文件变为分科目的answer文件夹，后续计算各科目的题目数也会用到这个文件夹：

```bash
python scripts/split_json_ans_by_subject.py
```

5. 创建` required_json`文件夹后，运行` create_finished_subjects_json`脚本，来创建计数文件：

``` bash
python scripts/create_finished_subjects_json.py
```

6. 之后，统计子集各学科的题目数，方便adb确认一个学科的题目完成。放入到` required_json`文件夹里的` question_counts_by_subject.json`里：

``` 
python scripts/count_questions_by_subject.py
```

7. 把QNNv2.39里的内容复制到文件夹中（v2.39有elite gen5的v81架构文件）：

```
#genie_bundle即为/data/local/tmp/genie-qwen2.5-3b的文件夹里。也可以先放到电脑暂存的文件夹里。
cp $QNN_SDK_ROOT/lib/hexagon-v81/unsigned/* genie_bundle
cp $QNN_SDK_ROOT/lib/aarch64-android/* genie_bundle
cp $QNN_SDK_ROOT/bin/aarch64-android/genie-t2t-run genie_bundle
```

8. 脚本都要用dos2unix转化成能在shell里识别的LF换行