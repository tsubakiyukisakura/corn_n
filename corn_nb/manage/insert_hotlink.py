#!/usr/bin/env python3
import sys
import re

if len(sys.argv) != 3:
    print("用法: insert_hotlink.py conf_file referers")
    sys.exit(1)

conf_file = sys.argv[1]
referers = sys.argv[2]

with open(conf_file, 'r', encoding='utf-8') as f:
    lines = f.readlines()

# 1. 检查所有 server 块结构是否正常
brace_stack = []
server_blocks = []  # [(start_line, end_line)]
for i, line in enumerate(lines):
    if re.match(r'\s*server\s*{', line):
        brace_stack.append(i)
    if '{' in line and not re.match(r'\s*server\s*{', line):
        # 其它块
        brace_stack.append(None)
    if '}' in line:
        if not brace_stack:
            print(f"配置文件第{i+1}行多余的 }}，请手动修复！", file=sys.stderr)
            sys.exit(1)
        start = brace_stack.pop()
        if start is not None:
            server_blocks.append((start, i))
if brace_stack:
    print("配置文件 server 块大括号数量不匹配，请手动修复！", file=sys.stderr)
    sys.exit(1)

# 2. 找到 listen 443 ssl 的 server 块
server_start = None
server_end = None
for start, end in server_blocks:
    for j in range(start, end+1):
        if re.search(r'listen\s+443\s+ssl;', lines[j]):
            server_start = start
            server_end = end
            break
    if server_start is not None:
        break
if server_start is None or server_end is None:
    print("未找到 listen 443 ssl 的 server 块，无法插入防盗链规则。", file=sys.stderr)
    sys.exit(1)

# 3. 查找第一个 location 行号
first_loc = None
for idx in range(server_start+1, server_end):
    if re.match(r'\s*location\s', lines[idx]):
        first_loc = idx
        break

hotlink_rule = (
    "    # 防盗链配置\n"
    "    location ~* \\.(gif|jpg|jpeg|png|bmp|swf|flv|mp4|ico|webp)$ {\n"
    f"        valid_referers {referers};\n"
    "        if ($invalid_referer) {\n"
    "            return 403;\n"
    "        }\n"
    "    }\n"
)

# 4. 插入防盗链 location
if first_loc is not None:
    new_lines = lines[:first_loc] + [hotlink_rule] + lines[first_loc:]
else:
    new_lines = lines[:server_end] + [hotlink_rule] + lines[server_end:]

with open(conf_file, 'w', encoding='utf-8') as f:
    f.writelines(new_lines) 